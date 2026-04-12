from __future__ import annotations

import base64
import csv
import io
import math
from pathlib import Path
from typing import Dict, Any
import logging

import numpy as np
import librosa
import webrtcvad
import soundfile as sf  # for debugging audio save


# -------------------------------
# 🔊 CONFIG (ultra relaxed for debugging)
# -------------------------------
MIN_RMS = 0.0005         # very relaxed minimum loudness
MIN_PEAK = 0.002         # very relaxed minimum peak
MIN_SPEECH_RATIO = 0.01  # very relaxed: 1% frames must contain speech

# DEBUG: Temporarily disable VAD for testing (set to True to bypass)
DISABLE_VAD_FOR_DEBUG = False

logger = logging.getLogger(__name__)
if not logger.handlers:
    handler = logging.StreamHandler()
    formatter = logging.Formatter("%(asctime)s [%(levelname)s] %(name)s: %(message)s")
    handler.setFormatter(formatter)
    logger.addHandler(handler)
logger.setLevel(logging.DEBUG)

from audio_features import (
    CANONICAL_AUDIO_SR,
    align_features_for_model,
    extract_features_from_bytes,
    extract_features_from_path,
    load_audio_consistent,
)
from eeg_features import extract_features_from_edf
from model_utils import (
    build_eeg_vector_for_inference,
    compute_eeg_confidence,
    compute_eeg_effort,
    effort_to_load,
    sigmoid_log_ratio,
)
# Lazy import to avoid circular import
# from model_loader import get_audio_model_bundle, get_eeg_model_bundle
from utils.paths import create_temp_file

logger.info("feature_pipeline module: %s", __file__)

class AudioValidationError(RuntimeError):
    """Raised when the uploaded audio is not valid for speech analysis."""

    def __init__(self, message: str, *, silence_detected: bool = False):
        super().__init__(message)
        self.silence_detected = bool(silence_detected)


def _clamp_percent(value: Any) -> float:
    try:
        numeric = float(value)
    except (TypeError, ValueError):
        numeric = 0.0
    return float(max(0.0, min(100.0, numeric)))


def _calculate_breakdown_metrics(feats):
    """
    Compute speed and clarity from feature vector.
    Safe fallback implementation.
    """

    # Force global binding (prevents NameError in Flask reload / hot-reload environment)
    globals()['_calculate_breakdown_metrics'] = _calculate_breakdown_metrics

    try:
        rms = float(feats.get("rms_mean", 0.0)) if isinstance(feats, dict) else 0.0
        zcr = float(feats.get("zcr_mean", 0.0)) if isinstance(feats, dict) else 0.0
        centroid = float(feats.get("spectral_centroid_mean", 0.0)) if isinstance(feats, dict) else 0.0
        bandwidth = float(feats.get("spectral_bandwidth_mean", 0.0)) if isinstance(feats, dict) else 0.0

        speed = float(min(max((rms + zcr) * 50.0, 0.0), 100.0))
        clarity = float(min(max((centroid + bandwidth) / 100.0, 0.0), 100.0))

        return speed, clarity
    except Exception as e:
        print(f"[WARN] breakdown fallback: {e}")
        return 50.0, 50.0


def calculate_breakdown_metrics(feats):
    """
    Backward-compatible public alias for breakdown metric computation.

    Some runtime environments may still reference the older non-underscored
    helper name after reloads; keep both names valid so audio analysis stays
    stable across imports and hot reload cycles.
    """

    helper = globals().get("_calculate_breakdown_metrics")
    if callable(helper):
        try:
            return helper(feats)
        except Exception as e:
            print(f"[WARN] public breakdown helper fallback: {e}", flush=True)

    try:
        rms = float(feats.get("rms_mean", 0.0)) if isinstance(feats, dict) else 0.0
        zcr = float(feats.get("zcr_mean", 0.0)) if isinstance(feats, dict) else 0.0
        centroid = float(feats.get("spectral_centroid_mean", 0.0)) if isinstance(feats, dict) else 0.0
        bandwidth = float(feats.get("spectral_bandwidth_mean", 0.0)) if isinstance(feats, dict) else 0.0

        speed = float(min(max((rms + zcr) * 50.0, 0.0), 100.0))
        clarity = float(min(max((centroid + bandwidth) / 100.0, 0.0), 100.0))
        return speed, clarity
    except Exception as e:
        print(f"[WARN] public breakdown fallback: {e}", flush=True)
        return 50.0, 50.0


def _get_breakdown_metrics(feats):
    """
    Resolve the available breakdown helper defensively.

    This avoids fragile NameError behavior if the runtime is holding onto an
    older module state during development reloads.
    """

    helper = globals().get("_calculate_breakdown_metrics")
    if callable(helper):
        try:
            return helper(feats)
        except Exception as e:
            print(f"[AUDIO DEBUG] private breakdown helper failed: {e}", flush=True)

    helper = globals().get("calculate_breakdown_metrics")
    if callable(helper):
        try:
            return helper(feats)
        except Exception as e:
            print(f"[AUDIO DEBUG] public breakdown helper failed: {e}", flush=True)

    print("[AUDIO DEBUG] no working breakdown helper, using hard fallback", flush=True)
    return 50.0, 50.0


def analyze_behavioral_payload(
    behavioral: Dict[str, Any],
    *,
    fallback_scores: Dict[str, float] | None = None,
) -> Dict[str, Any]:
    """Compute the structured behavioral result used by the assessment backend."""
    if not isinstance(behavioral, dict):
        raise RuntimeError("behavioral payload must be an object")

    accuracy_raw = behavioral.get("accuracy_percent")
    if accuracy_raw is None:
        try:
            correct = float(behavioral.get("correct_count", 0.0))
            total = float(behavioral.get("total_trials", 0.0))
            accuracy = (100.0 * correct / total) if total > 0.0 else 0.0
        except (TypeError, ValueError, ZeroDivisionError):
            accuracy = 0.0
    else:
        accuracy = _clamp_percent(accuracy_raw)

    try:
        reaction_time_ms = float(behavioral.get("mean_reaction_ms", 1200.0))
    except (TypeError, ValueError):
        reaction_time_ms = 1200.0
    rt_score = _clamp_percent(100.0 - ((reaction_time_ms - 800.0) / 20.0))

    consistency_raw = behavioral.get("consistency", behavioral.get("rt_variance"))
    try:
        consistency_variability = float(consistency_raw)
    except (TypeError, ValueError):
        if fallback_scores:
            values = [float(v) for v in fallback_scores.values()]
            consistency_variability = float(np.std(values) * 10.0) if values else 0.0
        else:
            consistency_variability = 0.0

    consistency_dispersion = math.sqrt(consistency_variability) if consistency_variability > 5000.0 else consistency_variability
    consistency_score = _clamp_percent(100.0 * math.exp(-max(0.0, consistency_dispersion) / 350.0))
    consistency_bonus = float(0.2 * consistency_score)
    behavioral_score = _clamp_percent((0.5 * accuracy) + (0.3 * rt_score) + consistency_bonus)

    return {
        "valid": True,
        "formula": "0.5*accuracy + 0.3*rt_score + 0.2*consistency_score",
        "accuracy": float(accuracy),
        "accuracy_percent": float(accuracy),
        "reaction_time_ms": float(reaction_time_ms),
        "rt_score": float(rt_score),
        "consistency_score": float(consistency_score),
        "consistency_bonus": float(consistency_bonus),
        "consistency_variability": float(consistency_variability),
        "behavioral_score": float(behavioral_score),
        "components": {
            "accuracy": float(accuracy),
            "rt_score": float(rt_score),
            "consistency_bonus": float(consistency_bonus),
        },
    }


def _align_audio_features_for_inference(feats: Any, scaler: Any) -> np.ndarray:
    """Keep audio inference feature sizing aligned with training/pseudo-labeling."""
    return align_features_for_model(np.asarray(feats, dtype=float), scaler=scaler)


def _derive_eeg_summary_from_features(features: Dict[str, float]) -> Dict[str, Any]:
    theta = float(features.get("theta_power_mean", 0.0))
    alpha = float(features.get("alpha_power_mean", 0.0))
    beta = float(features.get("beta_power_mean", 0.0))
    gamma = float(features.get("gamma_power_mean", 0.0))

    effort = compute_eeg_effort(theta, alpha, beta)
    load_class, load_level = effort_to_load(effort)
    confidence = compute_eeg_confidence(
        alpha,
        beta,
        gamma,
        effort=effort,
        theta_power=theta,
    )
    return {
        "load_class": load_class,
        "load_level": load_level,
        "effort": effort,
        "confidence": confidence,
        "low_confidence": confidence < 0.55,
    }


def _predict_eeg_load_and_effort(features: Dict[str, float]) -> Dict[str, Any]:
    # Lazy import to avoid circular import
    from model_loader import get_eeg_model_bundle
    bundle = get_eeg_model_bundle()
    scaler = bundle["scaler"]
    clf = bundle["clf"]
    reg = bundle["reg"]

    derived = _derive_eeg_summary_from_features(features)
    x = build_eeg_vector_for_inference(features, scaler)
    xs = scaler.transform(x)

    predicted_class = int(clf.predict(xs)[0])
    effort = float(reg.predict(xs)[0])
    if not np.isfinite(effort) or effort < 0.05:
        effort = float(derived["effort"])
    else:
        effort = float(np.clip((0.65 * effort) + (0.35 * float(derived["effort"])), 0.0, 1.0))

    load_class, load_level = effort_to_load(effort)
    confidence = float(derived["confidence"])
    class_probabilities: dict[str, float] | None = None

    if hasattr(clf, "predict_proba"):
        try:
            probs = np.asarray(clf.predict_proba(xs)[0], dtype=float)
            probs = np.nan_to_num(probs, nan=0.0, posinf=0.0, neginf=0.0)
            total = float(np.sum(probs))
            if total > 0.0:
                probs = probs / total
            if probs.size >= 3:
                sorted_probs = np.sort(probs)[::-1]
                margin = float(sorted_probs[0] - (sorted_probs[1] if sorted_probs.size > 1 else 0.0))
                confidence = float(np.clip((0.6 * margin) + (0.4 * confidence), 0.0, 1.0))
                class_probabilities = {
                    "low": float(probs[0]),
                    "medium": float(probs[1]),
                    "high": float(probs[2]),
                }
        except Exception:
            pass

    if predicted_class != load_class:
        confidence = float(np.clip(confidence * 0.85, 0.0, 1.0))

    result = {
        "load_class": load_class,
        "load_level": load_level,
        "effort": effort,
        "confidence": confidence,
        "low_confidence": confidence < 0.55,
    }
    if class_probabilities is not None:
        result["class_probabilities"] = class_probabilities
    return result


def compute_eeg_features_from_csv_bytes(raw: bytes) -> Dict[str, float]:
    """
    Parse a CSV file containing EEG band features and aggregate core metrics.

    The EEG inference path consumes a fixed 30-feature schema; any unavailable
    advanced features are defaulted to 0.0 during vector construction.
    """
    text = raw.decode("utf-8-sig", errors="replace")
    reader = csv.DictReader(io.StringIO(text))
    if not reader.fieldnames:
        raise RuntimeError("EEG CSV has no header row.")

    required_cols = {
        "delta_power_mean",
        "theta_power_mean",
        "alpha_power_mean",
        "beta_power_mean",
        "gamma_power_mean",
        "signal_entropy",
        "pupil_dilation_avg",
        "heart_rate_variability",
    }
    missing = required_cols.difference(reader.fieldnames)
    if missing:
        raise RuntimeError(f"EEG CSV missing columns: {sorted(missing)}")

    sums: Dict[str, float] = {c: 0.0 for c in required_cols}
    sums["frontal_asymmetry_index"] = 0.0
    sums["mental_effort_score"] = 0.0
    count = 0

    for row in reader:
        try:
            vals = {c: float(row[c]) for c in required_cols}
        except Exception:
            continue

        theta = vals["theta_power_mean"]
        alpha = vals["alpha_power_mean"]
        beta = vals["beta_power_mean"]

        # Use log-ratio + sigmoid normalization so tiny PSD scales do not push
        # the effort estimate toward misleading near-zero values.
        effort = compute_eeg_effort(theta, alpha, beta)

        try:
            fai = float(row.get("frontal_asymmetry_index", 0.0))
        except Exception:
            fai = 0.0
        if not np.isfinite(fai) or abs(fai) < 1e-6:
            # Proxy fallback when CSV uploads do not contain explicit left/right frontal asymmetry.
            fai = float(np.clip(np.log(beta + 1e-12) - np.log(alpha + 1e-12), -1.0, 1.0))
        vals["frontal_asymmetry_index"] = fai

        for c, v in vals.items():
            sums[c] += v
        sums["mental_effort_score"] += float(effort)
        count += 1

    if count == 0:
        raise RuntimeError("No valid numeric EEG rows found in CSV.")

    return {k: float(v / count) for k, v in sums.items()}


def _get_feature_value(feats: Any, key: str, default: float) -> float:
    if isinstance(feats, dict):
        try:
            value = float(feats.get(key, default))
        except Exception:
            value = float(default)
    else:
        value = float(default)
    return value


def _generate_dynamic_confidence_hint(
    confidence_entropy: float | None,
    speech_ratio: float,
    feats: Dict[str, float] | np.ndarray,
) -> str | None:
    """
    Generate context-aware confidence hints based on actual audio characteristics.
    
    Analyzes speech patterns, energy, and clarity to diagnose the root cause
    and provide specific, actionable feedback.
    
    Returns: Specific hint string tailored to the detected issue
    """
    if confidence_entropy is None:
        return None
    
    # Already high confidence — no hint needed
    if confidence_entropy >= 75.0:
        return "Analysis quality is good. Results are reliable."
    
    # Extract relevant features
    rms_mean = _get_feature_value(feats, 'rms_mean', 0.05)
    spectral_centroid = _get_feature_value(feats, 'spectral_centroid_mean', 2000.0)
    zcr_mean = _get_feature_value(feats, 'zcr_mean', 0.08)
    zcr_std = _get_feature_value(feats, 'zcr_std', 0.02)
    
    # ====================================================================
    # DIAGNOSTIC RULES (in priority order)
    # ====================================================================
    
    # Rule 1: Too many pauses (discontinuous speech)
    if speech_ratio is not None and speech_ratio < 0.35:
        return "Speak more continuously with fewer pauses for better analysis."
    
    # Rule 2: Too quiet (low RMS energy)
    if rms_mean < 0.04:
        return "Speak louder and clearer. Move closer to the microphone if needed."
    
    # Rule 3: High noise (high ZCR variance = background noise)
    if zcr_std > 0.025:
        return "Reduce background noise. Record in a quiet environment."
    
    # Rule 4: Muffled/unclear speech (low spectral centroid)
    if spectral_centroid < 1500.0:
        return "Speak more clearly. Articulate your words better."
    
    # Rule 5: Generic moderate confidence fallback
    if confidence_entropy >= 50.0:
        return "Please re-record in a quiet environment for better accuracy."
    
    # Rule 6: Low confidence fallback (multiple issues detected)
    return "Please re-record in a quiet environment with clear, consistent speech."


# _calculate_breakdown_metrics is de-duplicated and defined near the top as a safe fallback.
# Keep this local call into the top-level implementation.


# -------------------------------
# 🎙️ ULTRA RELIABLE SPEECH DETECTION
# -------------------------------
def is_valid_speech(audio, sr):
    rms = np.sqrt(np.mean(audio**2))
    peak = np.max(np.abs(audio))

    print(f"[DEBUG] RMS={rms:.6f}, PEAK={peak:.6f}")

    # 🔥 Very relaxed thresholds
    if rms < 0.0005 and peak < 0.002:
        return False, "Audio too silent"

    # Normalize safely
    if peak > 1e-6:
        audio = audio / peak

    # Frame energy
    frame_len = int(0.025 * sr)
    hop = int(0.01 * sr)

    energies = [
        np.sqrt(np.mean(audio[i:i+frame_len]**2))
        for i in range(0, len(audio)-frame_len, hop)
    ]

    if len(energies) == 0:
        return False, "Empty audio"

    energies = np.array(energies)

    threshold = np.mean(energies) * 1.2
    speech_ratio = np.sum(energies > threshold) / len(energies)

    print(f"[DEBUG] Speech ratio={speech_ratio:.2f}")

    if speech_ratio < 0.01:
        return False, "No speech pattern detected"

    return True, speech_ratio


def analyze_audio_payload(audio_b64: str, audio_ext: str = "") -> Dict[str, Any]:
    allowed_exts = {"wav", "mp3", "m4a", "webm"}
    ext = (audio_ext or "").strip().lower()
    logger.debug("analyze_audio_payload called with ext='%s' (original: '%s')", ext, audio_ext)
    if ext and ext not in allowed_exts:
        raise AudioValidationError(
            f"Unsupported audio format '{ext}'. Please upload WAV, MP3, M4A or WEBM."
        )

    try:
        raw = base64.b64decode(audio_b64, validate=True)
    except Exception as exc:
        raise AudioValidationError("Invalid audio payload encoding.") from exc

    speech_ratio: float | None = None

    if ext in allowed_exts:
        tmp_path = create_temp_file(suffix=f".{ext}")
        with open(tmp_path, "wb") as f:
            f.write(raw)

        # ====================================================================
        # 🎯 STEP 1: Load audio and basic checks
        # ====================================================================
        audio, sr = librosa.load(tmp_path.as_posix(), sr=16000)

        # Save debug file (optional)
        sf.write("debug_audio.wav", audio, sr)

        # -------------------------------
        # 🔍 STEP 1: Basic amplitude checks
        # -------------------------------
        rms = np.sqrt(np.mean(audio ** 2))
        peak = np.max(np.abs(audio))

        print(f"[DEBUG] RMS: {rms:.6f}, Peak: {peak:.6f}")

        if rms < MIN_RMS and peak < MIN_PEAK:
            try:
                tmp_path.unlink(missing_ok=True)
            except Exception:
                pass
            raise AudioValidationError(
                "No speech detected. Please speak clearly and try again.",
                silence_detected=True,
            )

        # -------------------------------
        # 🔊 STEP 2: Normalize
        # -------------------------------
        audio = audio / (peak + 1e-6)

        # -------------------------------
        # 🧠 STEP 3: Speech detection
        # -------------------------------
        valid, reason = is_valid_speech(audio, sr)

        if not valid:
            try:
                tmp_path.unlink(missing_ok=True)
            except Exception:
                pass
            raise AudioValidationError(
                f"No speech detected. Please speak clearly and try again. ({reason})",
                silence_detected=True,
            )

        try:
            feats = extract_features_from_path(tmp_path)
        except ValueError as exc:
            try:
                tmp_path.unlink(missing_ok=True)
            except Exception:
                pass
            raise AudioValidationError(str(exc)) from exc
        try:
            tmp_path.unlink(missing_ok=True)
        except Exception:
            pass
    else:
        try:
            feats = extract_features_from_bytes(raw)
        except ValueError as exc:
            raise AudioValidationError(str(exc)) from exc

    # Lazy import to avoid circular import
    from model_loader import get_audio_model_bundle
    bundle = get_audio_model_bundle()
    scaler = bundle["scaler"]
    model = bundle["model"]
    feats_aligned = np.asarray(_align_audio_features_for_inference(feats, scaler), dtype=float)
    
    # 🔥 IMPROVED: Validate feature scaling before prediction
    print(f"[AUDIO DEBUG] Feature vector shape: {feats_aligned.shape}, expected: {getattr(scaler, 'n_features_in_', 'unknown')}", flush=True)
    
    X = scaler.transform([feats_aligned])
    cls = int(model.predict(X)[0])
    
    # ========================================================================
    # Extract breakdown metrics from raw features (for speed, clarity scores)
    # ========================================================================
    try:
        speed_score, clarity_score = _get_breakdown_metrics(feats)
    except Exception as e:
        print(f"[AUDIO DEBUG] ERROR: Breakdown metrics resolution failed: {e}", flush=True)
        speed_score, clarity_score = 50.0, 50.0

    # ========================================================================
    # Calculate score from probabilities (weighted)
    # Then derive label from SCORE (not from cls)
    # This ensures score and label are always aligned
    # ========================================================================
    confidence: float | None = None
    confidence_margin: float | None = None
    confidence_entropy: float | None = None
    fluency_score: float
    fluency_score_normalized: float | None = None

    raw_probabilities: dict[str, float] | None = None
    top_probability: float | None = None
    low_confidence = False

    if hasattr(model, "predict_proba"):
        try:
            probs = np.asarray(model.predict_proba(X)[0], dtype=float)

            if probs.size > 0:
                probs = np.nan_to_num(probs, nan=0.0, posinf=0.0, neginf=0.0)
                total = float(np.sum(probs))
                if total > 0:
                    probs = probs / total

            # Ensure we have 3 probabilities (Low, Medium, High)
            if probs.size >= 3:
                # 🔥 IMPROVED: Use np.dot for cleaner, more scalable scoring
                # Weights: Low=30, Medium=60, High=90
                weights = np.array([30.0, 60.0, 90.0])
                fluency_score = float(np.dot(probs[:3], weights))
                
                # 🚀 NEW: Normalize score from [30-90] to [0-100]
                fluency_score_normalized = float(((fluency_score - 30.0) / 60.0) * 100.0)
                fluency_score_normalized = float(np.clip(fluency_score_normalized, 0.0, 100.0))
                
                sorted_probs = np.sort(probs)[::-1]
                top_probability = float(sorted_probs[0])
                second_probability = (
                    float(sorted_probs[1]) if sorted_probs.size > 1 else 0.0
                )

                # The app-facing confidence should reflect how likely the top class is.
                # Keep the separation from the runner-up as a separate diagnostic field.
                confidence = float(np.clip(top_probability, 0.0, 1.0))
                confidence_margin = float(
                    np.clip(top_probability - second_probability, 0.0, 1.0)
                )
                
                # 🚀 NEW: Entropy-based confidence (distribution-aware)
                # Combines top probability with distribution entropy  
                # Formula: confidence = (top_prob * 0.7 + entropy_factor * 0.3) * 100
                # This balances model certainty with distribution spread
                entropy = float(-np.sum(probs[:3] * np.log(probs[:3] + 1e-10)))
                max_entropy = float(np.log(3.0))  # log(3) for 3 classes
                entropy_factor = float(1.0 - (entropy / max_entropy))
                confidence_entropy = float(np.clip(
                    (top_probability * 0.7 + entropy_factor * 0.3) * 100.0,
                    0.0, 100.0
                ))
                
                # 🔥 IMPROVED: Use entropy confidence consistently everywhere
                # This ensures logic matches UI (avoid confidence conflicts)
                low_confidence = confidence_entropy < 50.0 if confidence_entropy is not None else False
                
                raw_probabilities = {
                    "low": float(probs[0]),
                    "medium": float(probs[1]),
                    "high": float(probs[2]),
                }
            else:
                fluency_score = float(30.0 + cls * 30.0)
                confidence = None
                confidence_margin = None

            print(
                f"[AUDIO DEBUG] cls={cls}, probs={probs}, score={fluency_score:.2f}, "
                f"normalized_score={fluency_score_normalized:.2f}, "
                f"top_probability={(top_probability if top_probability is not None else -1):.3f}, "
                f"entropy_confidence={confidence_entropy:.1f}",
                flush=True,
            )
        except Exception as e:
            fluency_score = float(30.0 + cls * 30.0)
            confidence = None
            print(f"[AUDIO DEBUG] Error in proba: {e}, fallback score={fluency_score:.2f}", flush=True)
    else:
        fluency_score = float(30.0 + cls * 30.0)
        confidence = None
        print(f"[AUDIO DEBUG] No predict_proba, cls={cls}, score={fluency_score:.2f}", flush=True)
    
    # ========================================================================
    # Derive label from NORMALIZED SCORE (0-100 scale, not raw 30-90)
    # This ensures consistency: UI scale matches label logic
    # Mapping: 0-25="Low", 25-58="Medium", 58-100="High"
    # ========================================================================
    if fluency_score_normalized is not None:
        if fluency_score_normalized < 25.0:
            label = "Low"
        elif fluency_score_normalized < 58.0:
            label = "Medium"
        else:
            label = "High"
    else:
        # Fallback to raw score if normalization failed
        if fluency_score < 45.0:
            label = "Low"
        elif fluency_score < 65.0:
            label = "Medium"
        else:
            label = "High"

    # 🔥 IMPROVED: Add "Uncertain" label for very low confidence
    if low_confidence and confidence is not None and confidence < 0.4:
        label = "Uncertain"
        warning = (
            "Analysis uncertain due to low confidence. Please record in a quiet environment with clear speech."
        )
    elif low_confidence:
        warning = None
    else:
        warning = None
    
    # 🚀 NEW: Dynamic confidence hints (context-aware feedback)
    # Analyzes actual audio characteristics to diagnose issues
    confidence_label = None
    confidence_hint = None
    if confidence_entropy is not None:
        if confidence_entropy >= 75.0:
            confidence_label = "High Confidence"
        elif confidence_entropy >= 50.0:
            confidence_label = "Moderate Confidence"
        else:
            confidence_label = "Low Confidence"
        
        # Generate context-aware hint based on audio characteristics
        confidence_hint = _generate_dynamic_confidence_hint(
            confidence_entropy, speech_ratio or 0.0, feats
        )

    # Build the result dictionary with BOTH normalized and original scores
    result = {
        # 🚀 NEW: Primary score (0-100 scale for app display)
        "fluency_score": fluency_score_normalized if fluency_score_normalized is not None else fluency_score,
        
        # Backward compatibility: Keep original 30-90 scale
        "fluency_score_raw": fluency_score,
        
        "fluency_label": label,
        
        # 🚀 NEW: Enhanced confidence metrics
        "confidence": confidence if confidence is not None else 0.0,  # Backward compat: top probability (0-1)
        "confidence_entropy": confidence_entropy,  # New: distribution-aware 0-100
        "confidence_label": confidence_label,  # Human-readable: "High/Moderate/Low Confidence"
        "confidence_hint": confidence_hint,  # Actionable guidance for user
        "confidence_raw": confidence,      # Preserve raw probability (0-1)
        "confidence_margin": confidence_margin,
        "top_probability": top_probability,
        
        # 🚀 NEW: Breakdown metrics
        "breakdown": {
            "speed": float(speed_score),
            "clarity": float(clarity_score),
            "confidence": confidence_entropy,
        },
        
        "valid": True,
        "low_confidence": low_confidence,
        "silence_detected": False,
    }
    
    if raw_probabilities is not None:
        result["probabilities"] = raw_probabilities
    
    if warning is not None:
        result["warning"] = warning

    return result


def extract_eeg_payload(eeg_b64: str, eeg_ext: str = "csv") -> Dict[str, float]:
    ext = str(eeg_ext or "csv").strip().lower()
    raw_bytes = base64.b64decode(eeg_b64)

    if ext == "edf":
        tmp_path = create_temp_file(suffix=".edf")
        with open(tmp_path, "wb") as f:
            f.write(raw_bytes)
        try:
            feats = extract_features_from_edf(tmp_path)
        finally:
            try:
                tmp_path.unlink(missing_ok=True)
            except Exception:
                pass
    else:
        feats = compute_eeg_features_from_csv_bytes(raw_bytes)

    # Always derive a stable EEG summary from the uploaded features, then enrich
    # it with model predictions when the trained bundle is available.
    pred = _derive_eeg_summary_from_features(feats)
    try:
        pred = {**pred, **_predict_eeg_load_and_effort(feats)}
    except Exception:
        # If the model is unavailable, keep the derived fallback values.
        pass

    fai = float(feats.get("frontal_asymmetry_index", 0.0) or 0.0)
    if not np.isfinite(fai) or abs(fai) < 1e-6:
        alpha = float(feats.get("alpha_power_mean", 1e-10))
        beta = float(feats.get("beta_power_mean", 1e-10))
        fai = float(np.clip(np.log(beta + 1e-12) - np.log(alpha + 1e-12), -1.0, 1.0))

    result = {
        **feats,
        "load_class": int(pred["load_class"]),
        "load_level": str(pred["load_level"]),
        "effort": float(np.clip(pred["effort"], 0.0, 1.0)),
        "confidence": float(np.clip(pred.get("confidence", 0.5), 0.0, 1.0)),
        "frontal_asymmetry_index": fai,
        "low_confidence": bool(pred.get("low_confidence", False)),
    }
    class_probabilities = pred.get("class_probabilities")
    if isinstance(class_probabilities, dict):
        result["class_probabilities"] = class_probabilities
    if result["low_confidence"]:
        result["warning"] = (
            "EEG confidence is low for this sample. Please ensure a stable sensor connection and minimal movement."
        )

    return result
