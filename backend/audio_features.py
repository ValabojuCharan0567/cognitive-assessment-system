from __future__ import annotations

from pathlib import Path
from typing import Iterable
import io
import os
import subprocess
import tempfile

import librosa
import numpy as np
import soundfile as sf


MIN_VALID_SAMPLES = 256
MIN_ANALYSIS_SAMPLES = 2048
# Strengthen silence/noise rejection for production use
MIN_PEAK_AMPLITUDE = 4e-2  # ~0.04 peak corresponds to low but audible human voice
MIN_RMS_AMPLITUDE = 5e-3  # ~0.005 RMS to avoid non-speech hiss
CANONICAL_AUDIO_SR = 16000
AUDIO_DECODE_TIMEOUT_SEC = int(os.getenv("AUDIO_DECODE_TIMEOUT_SEC", "20") or 20)


def _expected_feature_count(scaler: object | None = None, expected: int | None = None) -> int | None:
    if expected is not None:
        try:
            return int(expected)
        except Exception:
            return None

    n_features = getattr(scaler, "n_features_in_", None)
    if n_features is None:
        return None
    try:
        return int(n_features)
    except Exception:
        return None


def align_features_for_model(
    feats: np.ndarray,
    scaler: object | None = None,
    expected: int | None = None,
) -> np.ndarray:
    """Pad/truncate an audio feature vector to the model's expected size."""
    vec = np.asarray(feats, dtype=float).reshape(-1)
    target = _expected_feature_count(scaler=scaler, expected=expected)
    if target is None or target <= 0 or vec.shape[0] == target:
        return vec

    out = np.zeros(target, dtype=float)
    copy_len = min(target, vec.shape[0])
    if copy_len > 0:
        out[:copy_len] = vec[:copy_len]
    return out


def _prepare_audio_signal(y: np.ndarray, sr: int) -> tuple[np.ndarray, int]:
    """Normalize audio for stable feature extraction.

    Raises on empty/silent/corrupted clips, and pads short but valid clips so
    downstream FFT-based features do not crash or emit warning spam.
    """
    y = np.asarray(y, dtype=float)
    if y.ndim > 1:
        y = np.mean(y, axis=0)
    y = np.ravel(y)

    if y.size == 0:
        raise ValueError("audio length = 0")

    y = np.nan_to_num(y, nan=0.0, posinf=0.0, neginf=0.0)
    peak = float(np.max(np.abs(y))) if y.size else 0.0
    rms = float(np.sqrt(np.mean(y ** 2))) if y.size else 0.0

    if peak < MIN_PEAK_AMPLITUDE or rms < MIN_RMS_AMPLITUDE:
        raise ValueError("audio is silent or near-silent")

    if y.size < MIN_VALID_SAMPLES:
        raise ValueError(f"audio too short ({y.size} samples)")

    if y.size < MIN_ANALYSIS_SAMPLES:
        y = np.pad(y, (0, MIN_ANALYSIS_SAMPLES - y.size))

    return y.astype(np.float32, copy=False), int(sr or CANONICAL_AUDIO_SR)


def load_audio_consistent(source: str | Path | io.BytesIO) -> tuple[np.ndarray, int]:
    """Decode audio into one canonical model-ready representation.

    All runtime audio inference should pass through here so input format does
    not silently change the model's sample rate, channel count, or numeric type.
    """
    y: np.ndarray
    sr: int

    # Fast path: formats directly supported by libsndfile (e.g. WAV/FLAC/OGG).
    try:
        if isinstance(source, io.BytesIO):
            source.seek(0)
        y_raw, sr_raw = sf.read(source, dtype="float32", always_2d=False)
        y = np.asarray(y_raw, dtype=np.float32)
        if y.ndim > 1:
            y = np.mean(y, axis=1)
        sr = int(sr_raw)
    except Exception:
        # Fallback for AAC/M4A and other formats: decode with ffmpeg to PCM WAV.
        y, sr = _decode_with_ffmpeg(source)

    if sr != CANONICAL_AUDIO_SR and y.size > 0:
        y = librosa.resample(y, orig_sr=sr, target_sr=CANONICAL_AUDIO_SR)
        sr = CANONICAL_AUDIO_SR

    y = np.ravel(y)
    y = np.nan_to_num(y, nan=0.0, posinf=0.0, neginf=0.0)

    peak = float(np.max(np.abs(y))) if y.size else 0.0
    if peak > 0.0:
        y = y / peak

    return y.astype(np.float32, copy=False), CANONICAL_AUDIO_SR


def _decode_with_ffmpeg(source: str | Path | io.BytesIO) -> tuple[np.ndarray, int]:
    temp_dir = tempfile.mkdtemp(prefix="audio_decode_")
    in_path = Path(temp_dir) / "input_audio"
    out_path = Path(temp_dir) / "decoded.wav"

    try:
        if isinstance(source, io.BytesIO):
            source.seek(0)
            in_path.write_bytes(source.read())
        else:
            src_path = Path(source)
            in_path.write_bytes(src_path.read_bytes())

        cmd = [
            "ffmpeg",
            "-nostdin",
            "-v",
            "error",
            "-y",
            "-i",
            str(in_path),
            "-ar",
            str(CANONICAL_AUDIO_SR),
            "-ac",
            "1",
            str(out_path),
        ]
        try:
            proc = subprocess.run(
                cmd,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                timeout=AUDIO_DECODE_TIMEOUT_SEC,
                check=False,
                text=True,
            )
        except FileNotFoundError as exc:
            raise ValueError(
                "Audio decode backend missing: ffmpeg is not installed on the server."
            ) from exc
        except subprocess.TimeoutExpired as exc:
            raise ValueError(
                f"Audio decode timed out after {AUDIO_DECODE_TIMEOUT_SEC}s."
            ) from exc

        if proc.returncode != 0 or not out_path.exists():
            detail = (proc.stderr or "").strip()
            raise ValueError(
                f"Audio decode failed via ffmpeg: {detail or 'unknown ffmpeg error'}"
            )

        y_raw, sr_raw = sf.read(out_path, dtype="float32", always_2d=False)
        y = np.asarray(y_raw, dtype=np.float32)
        if y.ndim > 1:
            y = np.mean(y, axis=1)
        return y, int(sr_raw)
    finally:
        try:
            out_path.unlink(missing_ok=True)
        except Exception:
            pass
        try:
            in_path.unlink(missing_ok=True)
        except Exception:
            pass
        try:
            Path(temp_dir).rmdir()
        except Exception:
            pass


def _extract_features_from_signal(
    y: np.ndarray, sr: int, mfcc: bool = True, chroma: bool = True, mel: bool = True
) -> np.ndarray:
    y, sr = _prepare_audio_signal(y, sr)
    analysis_n_fft = min(1024, len(y))
    hop_length = max(128, analysis_n_fft // 4)

    result: Iterable[float] | np.ndarray = np.array([])
    stft = None
    if chroma:
        stft = np.abs(librosa.stft(y, n_fft=analysis_n_fft, hop_length=hop_length))
    if mfcc:
        mfcc_matrix = librosa.feature.mfcc(
            y=y,
            sr=sr,
            n_mfcc=40,
            n_fft=analysis_n_fft,
            hop_length=hop_length,
        )
        mfccs = np.mean(mfcc_matrix.T, axis=0)
        result = np.hstack((result, mfccs))
        # Keep temporal variation of MFCCs for better speaker/content robustness.
        mfccs_std = np.std(mfcc_matrix.T, axis=0)
        result = np.hstack((result, mfccs_std))

        # Temporal dynamics help emotion/cognitive-state separation.
        frame_count = int(mfcc_matrix.shape[1])
        delta_width = min(9, frame_count if frame_count % 2 == 1 else frame_count - 1)
        if delta_width >= 3:
            mfcc_delta = librosa.feature.delta(mfcc_matrix, width=delta_width)
            mfcc_delta2 = librosa.feature.delta(mfcc_matrix, order=2, width=delta_width)
            result = np.hstack((result, np.mean(mfcc_delta.T, axis=0), np.std(mfcc_delta.T, axis=0)))
            result = np.hstack((result, np.mean(mfcc_delta2.T, axis=0), np.std(mfcc_delta2.T, axis=0)))
        else:
            zeros = np.zeros(mfcc_matrix.shape[0], dtype=float)
            result = np.hstack((result, zeros, zeros, zeros, zeros))
    if chroma and stft is not None:
        chroma_feat = np.mean(
            librosa.feature.chroma_stft(S=stft, sr=sr, hop_length=hop_length).T,
            axis=0,
        )
        result = np.hstack((result, chroma_feat))
    if mel:
        mel_spec = np.mean(
            librosa.feature.melspectrogram(
                y=y,
                sr=sr,
                n_fft=analysis_n_fft,
                hop_length=hop_length,
            ).T,
            axis=0,
        )
        result = np.hstack((result, mel_spec))

    # Adds spectral shape separation across sub-bands.
    # Low-sample-rate clips can violate spectral_contrast's Nyquist band
    # assumptions, so adapt the number of bands and zero-pad the summary back
    # to the fixed training width.
    contrast_features = np.zeros(14, dtype=float)
    try:
        contrast_fmin = 200.0
        nyquist = float(sr) / 2.0
        if nyquist > contrast_fmin * 2.0:
            max_n_bands = int(np.floor(np.log2(nyquist / contrast_fmin)))
            contrast_n_bands = max(1, min(6, max_n_bands))
            contrast = librosa.feature.spectral_contrast(
                y=y,
                sr=sr,
                n_fft=analysis_n_fft,
                hop_length=hop_length,
                fmin=contrast_fmin,
                n_bands=contrast_n_bands,
            )
            contrast_summary = np.hstack((np.mean(contrast.T, axis=0), np.std(contrast.T, axis=0)))
            copy_len = min(contrast_features.shape[0], contrast_summary.shape[0])
            if copy_len > 0:
                contrast_features[:copy_len] = contrast_summary[:copy_len]
    except Exception:
        pass
    result = np.hstack((result, contrast_features))

    # Harmonic tonal structure can separate calmer vs stressed speech characteristics.
    # Very short clips do not carry stable tonal structure and can trigger CQT
    # warning spam inside tonnetz, so skip this block for sub-second audio.
    try:
        if len(y) >= max(analysis_n_fft, sr // 2):
            y_harmonic = librosa.effects.harmonic(y)
            tonnetz = librosa.feature.tonnetz(y=y_harmonic, sr=sr)
            result = np.hstack((result, np.mean(tonnetz.T, axis=0), np.std(tonnetz.T, axis=0)))
        else:
            result = np.hstack((result, np.zeros(12, dtype=float)))
    except Exception:
        result = np.hstack((result, np.zeros(12, dtype=float)))

    # Core audio descriptors requested for robust cognitive-load modeling.
    zcr = librosa.feature.zero_crossing_rate(y, hop_length=hop_length)
    result = np.hstack((result, np.mean(zcr, axis=1), np.std(zcr, axis=1)))

    centroid = librosa.feature.spectral_centroid(
        y=y,
        sr=sr,
        n_fft=analysis_n_fft,
        hop_length=hop_length,
    )
    result = np.hstack((result, np.mean(centroid, axis=1), np.std(centroid, axis=1)))

    bandwidth = librosa.feature.spectral_bandwidth(
        y=y,
        sr=sr,
        n_fft=analysis_n_fft,
        hop_length=hop_length,
    )
    result = np.hstack((result, np.mean(bandwidth, axis=1), np.std(bandwidth, axis=1)))

    # Calm-speech cues: low energy and low temporal variance are informative for Low class.
    rms = librosa.feature.rms(y=y, frame_length=analysis_n_fft, hop_length=hop_length)
    rms_vals = rms.flatten()
    result = np.hstack(
        (
            result,
            np.mean(rms_vals),
            np.std(rms_vals),
            np.var(rms_vals),
            np.percentile(rms_vals, 10),
            np.percentile(rms_vals, 90),
        )
    )

    # Medium-class cue: proportion of frames in moderate energy band.
    p25 = np.percentile(rms_vals, 25)
    p75 = np.percentile(rms_vals, 75)
    moderate_energy_ratio = float(np.mean((rms_vals >= p25) & (rms_vals <= p75)))
    result = np.hstack((result, moderate_energy_ratio))

    # Pitch stability: calmer speech tends to show less F0 volatility.
    try:
        f0 = librosa.yin(
            y,
            fmin=librosa.note_to_hz("C2"),
            fmax=librosa.note_to_hz("C7"),
            sr=sr,
            frame_length=analysis_n_fft,
            hop_length=hop_length,
        )
        f0 = f0[np.isfinite(f0)]
        if f0.size > 0:
            f0_std = np.std(f0)
            f0_iqr = np.percentile(f0, 75) - np.percentile(f0, 25)
            # Medium-class cue: moderate pitch variability (distance from center band).
            moderate_pitch_score = 1.0 / (1.0 + abs(f0_std - np.median(np.abs(f0 - np.median(f0)))))
            result = np.hstack(
                (
                    result,
                    np.mean(f0),
                    f0_std,
                    np.var(f0),
                    np.percentile(f0, 25),
                    np.percentile(f0, 75),
                    f0_iqr,
                    moderate_pitch_score,
                )
            )
        else:
            result = np.hstack((result, np.zeros(8, dtype=float)))
    except Exception:
        result = np.hstack((result, np.zeros(8, dtype=float)))

    # Rhythm consistency: onset and tempo stability can separate medium expressiveness.
    try:
        onset_env = librosa.onset.onset_strength(
            y=y,
            sr=sr,
            n_fft=analysis_n_fft,
            hop_length=hop_length,
        )
        tempo, _ = librosa.beat.beat_track(
            onset_envelope=onset_env,
            sr=sr,
            hop_length=hop_length,
        )
        result = np.hstack(
            (
                result,
                np.mean(onset_env),
                np.std(onset_env),
                np.var(onset_env),
                float(tempo),
            )
        )
    except Exception:
        result = np.hstack((result, np.zeros(4, dtype=float)))

    return np.asarray(result, dtype=float)


def extract_features_from_path(path: Path) -> np.ndarray:
    y, sr = load_audio_consistent(path.as_posix())
    return _extract_features_from_signal(y, sr)


def extract_features_from_bytes(raw: bytes) -> np.ndarray:
    with io.BytesIO(raw) as bio:
        y, sr = load_audio_consistent(bio)
    return _extract_features_from_signal(y, sr)


def extract_features_from_signal(y: np.ndarray, sr: int) -> np.ndarray:
    """Extract runtime audio features from an already-decoded signal."""
    y = np.asarray(y, dtype=np.float32)
    return _extract_features_from_signal(y, int(sr or CANONICAL_AUDIO_SR))


def extract_augmented_features_from_path(path: Path, noise_scale: float = 0.005) -> list[np.ndarray]:
    """Generate augmented feature variants from one audio file (noise, pitch, speed)."""
    y, sr = load_audio_consistent(path.as_posix())
    y, sr = _prepare_audio_signal(y, sr)
    augmented: list[np.ndarray] = []

    # Additive Gaussian noise
    noise = y + noise_scale * np.random.randn(len(y))
    augmented.append(_extract_features_from_signal(noise, sr))

    # Pitch shift (up two semitones)
    try:
        pitch = librosa.effects.pitch_shift(y, sr=sr, n_steps=2)
        augmented.append(_extract_features_from_signal(pitch, sr))
    except Exception:
        pass

    # Slight speed change
    try:
        speed = librosa.effects.time_stretch(y, rate=1.1)
        augmented.append(_extract_features_from_signal(speed, sr))
    except Exception:
        pass

    return augmented
