from __future__ import annotations

from pathlib import Path
from typing import Dict, List, Union

import librosa
import numpy as np

from backend.audio_features import extract_features_from_path
from backend.eeg_features import extract_features_from_edf


def _safe_log(x: float, base: float = np.e) -> float:
    return float(np.log(x + 1e-12) / np.log(base))


def _minmax_normalize(values: np.ndarray) -> np.ndarray:
    values = np.asarray(values, dtype=float)
    if values.size == 0:
        return values
    mn = np.nanmin(values)
    mx = np.nanmax(values)
    if mx <= mn:
        return np.zeros_like(values)
    return (values - mn) / (mx - mn)


def prepare_eeg_dataset(edf_path: Union[str, Path]) -> Dict[str, float]:
    """Load EDF and derive requested EEG features."""
    edf_path = Path(edf_path)
    if not edf_path.exists():
        raise FileNotFoundError(f"EEG EDF file not found: {edf_path}")

    raw_feats = extract_features_from_edf(edf_path)

    alpha = raw_feats.get("alpha_power_mean", 0.0)
    beta = raw_feats.get("beta_power_mean", 0.0)
    gamma = raw_feats.get("gamma_power_mean", 0.0)
    theta = raw_feats.get("theta_power_mean", 0.0)

    log_alpha = _safe_log(alpha)
    log_beta = _safe_log(beta)
    log_gamma = _safe_log(gamma)
    log_theta = _safe_log(theta)

    # log-based ratio alpha/beta
    alpha_beta_ratio = _safe_log(alpha / (beta + 1e-12))

    return {
        "alpha_power": alpha,
        "beta_power": beta,
        "gamma_power": gamma,
        "theta_power": theta,
        "alpha_power_log": log_alpha,
        "beta_power_log": log_beta,
        "gamma_power_log": log_gamma,
        "theta_power_log": log_theta,
        "alpha_beta_log_ratio": alpha_beta_ratio,
        "frontal_asymmetry_index": raw_feats.get("frontal_asymmetry_index", 0.0),
        "entropy": raw_feats.get("signal_entropy", 0.0),
    }


def prepare_audio_dataset(audio_path: Union[str, Path]) -> Dict[str, Union[float, np.ndarray]]:
    """Load audio file and derive requested audio features."""
    audio_path = Path(audio_path)
    if not audio_path.exists():
        raise FileNotFoundError(f"Audio file not found: {audio_path}")

    y, sr = librosa.load(audio_path.as_posix(), sr=None, mono=True)
    if y.size == 0 or sr <= 0:
        raise ValueError("Invalid audio content")

    # Core metrics
    zcr = librosa.feature.zero_crossing_rate(y)[0]
    rmss = librosa.feature.rms(y=y)[0]

    # Pitch estimation via librosa.yin (typical speech range C2-C7)
    try:
        f0 = librosa.yin(y, fmin=librosa.note_to_hz("C2"), fmax=librosa.note_to_hz("C7"), sr=sr)
        f0 = f0[np.isfinite(f0)]
    except Exception:
        f0 = np.array([], dtype=float)

    mfcc = librosa.feature.mfcc(y=y, sr=sr, n_mfcc=13)
    mfcc_mean = np.mean(mfcc, axis=1)
    mfcc_std = np.std(mfcc, axis=1)

    # Normalize the core features (per sample)
    zcr_norm = float(_minmax_normalize(zcr).mean())
    energy_norm = float(_minmax_normalize(rmss).mean())
    pitch_mean = float(np.mean(f0) if f0.size else 0.0)
    pitch_std = float(np.std(f0) if f0.size else 0.0)
    pitch_norm = float(np.mean(_minmax_normalize(f0))) if f0.size else 0.0

    return {
        "mfcc_mean": mfcc_mean.tolist(),
        "mfcc_std": mfcc_std.tolist(),
        "pitch_mean": pitch_mean,
        "pitch_std": pitch_std,
        "pitch_norm": pitch_norm,
        "energy_mean": float(np.mean(rmss)),
        "energy_std": float(np.std(rmss)),
        "energy_norm": energy_norm,
        "zcr_mean": float(np.mean(zcr)),
        "zcr_std": float(np.std(zcr)),
        "zcr_norm": zcr_norm,
    }


def prepare_behavioral_metrics(trials: List[Dict[str, Union[bool, int, float]]]) -> Dict[str, float]:
    """Compute mandatory behavioral indicators from task trials."""
    if not trials:
        raise ValueError("behavioral trials list is empty")

    n = len(trials)

    correct = []
    reaction_times = []

    for t in trials:
        is_correct = t.get("correct")
        rt = t.get("reaction_time_ms")

        if is_correct is None or rt is None:
            raise ValueError("each trial must include 'correct' and 'reaction_time_ms'")

        correct.append(1 if bool(is_correct) else 0)
        reaction_times.append(float(rt))

    accuracy_pct = float(np.mean(correct) * 100.0)
    rt_mean = float(np.mean(reaction_times))
    rt_variance = float(np.var(reaction_times, ddof=0))

    return {
        "accuracy_percent": accuracy_pct,
        "reaction_time_ms_mean": rt_mean,
        "reaction_time_ms_variance": rt_variance,
        "consistency_index": float(1.0 / (1.0 + rt_variance)) if rt_variance >= 0 else 0.0,
    }


def prepare_multimodal_sample(
    eeg_path: Union[str, Path],
    audio_path: Union[str, Path],
    behavioral_trials: List[Dict[str, Union[bool, int, float]]],
) -> Dict[str, object]:
    """Combined multimodal data prep pipeline (EEG+Audio+Behavioral)."""
    return {
        "eeg": prepare_eeg_dataset(eeg_path),
        "audio": prepare_audio_dataset(audio_path),
        "behavioral": prepare_behavioral_metrics(behavioral_trials),
    }
