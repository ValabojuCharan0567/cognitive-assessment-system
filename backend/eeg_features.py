

from __future__ import annotations

from pathlib import Path
from typing import Dict

import mne
import numpy as np

from model_utils import compute_eeg_effort, sigmoid_log_ratio


def _normalize_channel_name(name: str) -> str:
    return "".join(ch for ch in str(name).upper() if ch.isalnum())


def _find_channel_index(pick_names: list[str], target: str) -> int | None:
    target_norm = _normalize_channel_name(target)
    normalized = {_normalize_channel_name(name): idx for idx, name in enumerate(pick_names)}
    if target_norm in normalized:
        return normalized[target_norm]
    for name_norm, idx in normalized.items():
        if name_norm.startswith(target_norm) or name_norm.endswith(target_norm) or target_norm in name_norm:
            return idx
    return None


def _compute_frontal_asymmetry(psd_data: np.ndarray, freqs: np.ndarray, pick_names: list[str]) -> float:
    """Use the log alpha-power difference on a frontal left/right pair when available."""
    alpha_idx = np.logical_and(freqs >= 8, freqs <= 13)
    if not np.any(alpha_idx):
        return 0.0

    candidate_pairs = [
        ("F4", "F3"),
        ("FP2", "FP1"),
        ("AF4", "AF3"),
        ("F2", "F1"),
        ("F8", "F7"),
        ("FC4", "FC3"),
    ]
    for right_name, left_name in candidate_pairs:
        right_idx = _find_channel_index(pick_names, right_name)
        left_idx = _find_channel_index(pick_names, left_name)
        if right_idx is None or left_idx is None:
            continue

        right_alpha = float(psd_data[right_idx, alpha_idx].mean())
        left_alpha = float(psd_data[left_idx, alpha_idx].mean())
        if right_alpha > 0.0 and left_alpha > 0.0:
            fa_index = float(np.log(right_alpha + 1e-12) - np.log(left_alpha + 1e-12))
            return float(np.clip(fa_index, -1.5, 1.5))

    return 0.0


def extract_features_from_edf(edf_path: str | Path) -> Dict[str, float]:
    """Extract demo-safe EEG features from an EDF recording.

    The pipeline keeps one consistent feature contract for both model inference
    and UI reporting. Band ratios are log-normalised and squashed with a sigmoid
    so tiny PSD values do not collapse into misleading near-zero effort scores.
    """

    raw = mne.io.read_raw_edf(str(edf_path), preload=True, verbose=False)

    # Bandpass filter
    raw.filter(0.5, 40.0, fir_design="firwin", verbose=False)

    # Pick EEG channels
    picks = mne.pick_types(raw.info, eeg=True)
    if len(picks) == 0:
        raise RuntimeError("No EEG channels found in recording.")

    # Compute Power Spectral Density
    psd = raw.compute_psd(picks=picks, fmin=0.5, fmax=40.0)
    psd_data, freqs = psd.get_data(return_freqs=True)

    def band_power(fmin: float, fmax: float) -> float:
        idx = np.logical_and(freqs >= fmin, freqs <= fmax)
        if not np.any(idx):
            return 0.0
        return float(psd_data[:, idx].mean())

    # EEG frequency bands
    delta = band_power(1, 4)
    theta = band_power(4, 8)
    alpha = band_power(8, 13)
    beta = band_power(13, 30)
    gamma = band_power(30, 40)
    
    # Sub-bands for more granular analysis
    low_alpha = band_power(8, 10)    # Low-alpha
    high_alpha = band_power(10, 12)  # High-alpha
    smr = band_power(12, 15)         # Sensorimotor rhythm
    high_beta = band_power(20, 30)   # High-beta

    # Frontal asymmetry: robustly match frontal channel names such as `F3..`,
    # `EEG F3-REF`, etc., and use the research-standard log alpha-power difference.
    pick_names = [raw.ch_names[idx] for idx in picks]
    fa_index = _compute_frontal_asymmetry(psd_data, freqs, pick_names)

    # Mental effort estimate: log-ratio + sigmoid keeps tiny PSD values stable.
    beta_alpha_score = sigmoid_log_ratio(beta, alpha)
    theta_alpha_score = sigmoid_log_ratio(theta, alpha)
    mental_effort = compute_eeg_effort(theta, alpha, beta)

    # Signal entropy
    p = psd_data.flatten()
    p = p / (p.sum() + 1e-12)
    entropy = float(-(p * np.log(p + 1e-12)).sum())

    # Band ratios (important cognitive load indicators)
    # Use log-ratio sigmoid normalization instead of raw division so very small
    # values do not collapse toward fake near-zero outputs.
    alpha_beta_ratio = sigmoid_log_ratio(alpha, beta)
    theta_alpha_ratio = sigmoid_log_ratio(theta, alpha)
    theta_beta_ratio = sigmoid_log_ratio(theta, beta)
    
    # PSD statistics
    psd_mean = float(psd_data.mean())
    psd_std = float(psd_data.std())
    psd_max = float(psd_data.max())

    # Time-domain statistics from raw signal
    raw_data = raw.get_data(picks=picks)  # shape: (n_channels, n_samples)
    signal_mean = float(raw_data.mean())
    signal_std = float(raw_data.std())
    signal_rms = float(np.sqrt(np.mean(raw_data ** 2)))
    
    # Peak-to-peak amplitude
    pp_amplitude = float(raw_data.max() - raw_data.min())

    # ========== HJORTH PARAMETERS ==========
    # Extract mean across channels for Hjorth computation
    signal_1d = raw_data.flatten()
    
    # Activity = variance
    activity = float(np.var(signal_1d))
    
    # Mobility = sqrt(var(derivative) / var(signal))
    diff1 = np.diff(signal_1d)
    mobility = float(np.sqrt(np.var(diff1) / (np.var(signal_1d) + 1e-12)))
    
    # Complexity = mobility(derivative) / mobility(signal)
    diff2 = np.diff(diff1)
    complexity = float(np.sqrt(np.var(diff2) / (np.var(diff1) + 1e-12)) / (mobility + 1e-12))
    
    # ========== FRACTAL DIMENSION (PETROSIAN) ==========
    # Simple approximation of self-similarity
    n0 = np.sum(np.abs(np.diff(signal_1d)) > 0)
    petrosian_fd = float(np.log10(len(signal_1d)) / (np.log10(len(signal_1d)) + np.log10(len(signal_1d) / (len(signal_1d) + 0.4 * n0 + 1e-12))))
    
    # ========== SPECTRAL EDGE FREQUENCY ==========
    # Frequency at which 95% of power is below
    cumsum_psd = np.cumsum(psd_data.flatten() + 1e-12)
    cumsum_psd = cumsum_psd / (cumsum_psd[-1] + 1e-12)
    idx_95 = np.argmax(cumsum_psd >= 0.95)
    spectral_edge_freq = float(freqs[min(idx_95, len(freqs)-1)] if idx_95 < len(freqs) else freqs[-1])
    
    # ========== ZERO CROSSING RATE ==========
    zero_crossings = np.sum(np.diff(np.sign(signal_1d)) != 0)
    zero_crossing_rate = float(zero_crossings / len(signal_1d))

    # Compatibility proxies for legacy schema fields that historically came
    # from non-EEG sensors. Keep them dynamic and data-derived rather than
    # returning hard-coded placeholder numbers.
    entropy_norm = float(np.clip(entropy / 10.0, 0.0, 1.0))
    rms_norm = float(np.clip(np.log1p(signal_rms * 1e6) / 8.0, 0.0, 1.0))
    mobility_norm = float(np.clip(mobility / 2.0, 0.0, 1.0))
    pupil_dilation_proxy = float(np.clip(2.5 + (1.6 * mental_effort) + (1.2 * entropy_norm), 2.0, 7.0))
    heart_rate_variability_proxy = float(
        np.clip(30.0 + (45.0 * (1.0 - beta_alpha_score)) + (10.0 * (1.0 - mobility_norm)) + (5.0 * rms_norm), 20.0, 120.0)
    )

    return {
        # Frequency bands
        "delta_power_mean": delta,
        "theta_power_mean": theta,
        "alpha_power_mean": alpha,
        "beta_power_mean": beta,
        "gamma_power_mean": gamma,
        
        # Sub-bands
        "low_alpha": low_alpha,
        "high_alpha": high_alpha,
        "smr": smr,
        "high_beta": high_beta,
        
        # Classical measures
        "frontal_asymmetry_index": fa_index,
        "mental_effort_score": mental_effort,
        "signal_entropy": entropy,
        
        # Band ratios
        "alpha_beta_ratio": alpha_beta_ratio,
        "theta_alpha_ratio": theta_alpha_ratio,
        "theta_beta_ratio": theta_beta_ratio,
        
        # PSD statistics
        "psd_mean": psd_mean,
        "psd_std": psd_std,
        "psd_max": psd_max,
        
        # Time-domain statistics
        "signal_mean": signal_mean,
        "signal_std": signal_std,
        "signal_rms": signal_rms,
        "pp_amplitude": pp_amplitude,
        
        # Hjorth parameters (activity, mobility, complexity)
        "hjorth_activity": activity,
        "hjorth_mobility": mobility,
        "hjorth_complexity": complexity,
        
        # Fractal dimension & spectral features
        "petrosian_fd": petrosian_fd,
        "spectral_edge_freq": spectral_edge_freq,
        "zero_crossing_rate": zero_crossing_rate,
        
        # Legacy schema compatibility fields now derived from the EEG signal.
        "pupil_dilation_avg": pupil_dilation_proxy,
        "heart_rate_variability": heart_rate_variability_proxy,
    }
