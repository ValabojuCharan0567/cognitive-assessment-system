from __future__ import annotations

import math
import statistics
from typing import Any, Dict

# Canonical EEG feature order used during training and inference. Keep this in
# one place so model retraining and runtime scoring cannot silently drift apart.
EEG_FEATURE_COLUMNS = [
    "delta_power_mean",
    "theta_power_mean",
    "alpha_power_mean",
    "beta_power_mean",
    "gamma_power_mean",
    "low_alpha",
    "high_alpha",
    "smr",
    "high_beta",
    "frontal_asymmetry_index",
    "mental_effort_score",
    "signal_entropy",
    "alpha_beta_ratio",
    "theta_alpha_ratio",
    "theta_beta_ratio",
    "psd_mean",
    "psd_std",
    "psd_max",
    "signal_mean",
    "signal_std",
    "signal_rms",
    "pp_amplitude",
    "hjorth_activity",
    "hjorth_mobility",
    "hjorth_complexity",
    "petrosian_fd",
    "spectral_edge_freq",
    "zero_crossing_rate",
    "pupil_dilation_avg",
    "heart_rate_variability",
]

# These richer EEG descriptors indicate that the uploaded payload is detailed
# enough to run the full regressor/classifier rather than the light fallback.
EEG_ADVANCED_FEATURE_KEYS = {
    "low_alpha",
    "high_alpha",
    "smr",
    "high_beta",
    "alpha_beta_ratio",
    "theta_alpha_ratio",
    "theta_beta_ratio",
    "psd_mean",
    "psd_std",
    "psd_max",
    "signal_mean",
    "signal_std",
    "signal_rms",
    "pp_amplitude",
    "hjorth_activity",
    "hjorth_mobility",
    "hjorth_complexity",
    "petrosian_fd",
    "spectral_edge_freq",
    "zero_crossing_rate",
}


def scaler_expected_features(scaler: Any) -> int | None:
    n_features = getattr(scaler, "n_features_in_", None)
    if n_features is None:
        return None
    try:
        return int(n_features)
    except Exception:
        return None


def clamp_float(value: float, low: float, high: float) -> float:
    """Clamp a numeric value to a bounded range and return a float."""
    return float(max(low, min(high, float(value))))


def sigmoid_log_ratio(numerator: float, denominator: float, eps: float = 1e-12) -> float:
    """Return a stable 0-1 ratio from tiny EEG power values using log scaling."""
    log_ratio = float(math.log(numerator + eps) - math.log(denominator + eps))
    return float(1.0 / (1.0 + math.exp(-log_ratio)))


def compute_eeg_effort(theta_power: float, alpha_power: float, beta_power: float) -> float:
    """Compute a normalized 0-1 EEG effort estimate from core band powers."""
    beta_alpha = sigmoid_log_ratio(beta_power, alpha_power)
    theta_alpha = sigmoid_log_ratio(theta_power, alpha_power)
    return clamp_float((0.6 * beta_alpha) + (0.4 * theta_alpha), 0.0, 1.0)


def effort_to_load(effort: float) -> tuple[int, str]:
    """Map normalized EEG effort into the Low / Medium / High load bands."""
    effort = clamp_float(effort, 0.0, 1.0)
    if effort < 0.35:
        return 0, "Low"
    if effort < 0.75:
        return 1, "Medium"
    return 2, "High"


def compute_eeg_confidence(
    alpha_power: float,
    beta_power: float,
    gamma_power: float,
    *,
    effort: float | None = None,
    theta_power: float | None = None,
) -> float:
    """Estimate EEG confidence from spectral stability and class separation."""
    logs: list[float] = []
    for power in [alpha_power, beta_power, gamma_power, theta_power]:
        try:
            value = float(power)
        except (TypeError, ValueError):
            continue
        if value > 0.0:
            logs.append(float(math.log(value + 1e-12)))

    stability = 0.5 if len(logs) < 2 else float(1.0 / (1.0 + statistics.pstdev(logs)))
    if effort is None:
        effort = compute_eeg_effort(theta_power or 0.0, alpha_power, beta_power)

    load_class, _ = effort_to_load(effort)
    class_centers = {0: 0.175, 1: 0.55, 2: 0.875}
    separation = 1.0 - min(abs(float(effort) - class_centers[load_class]) / 0.35, 1.0)
    return clamp_float((0.65 * stability) + (0.35 * separation), 0.0, 1.0)


def build_eeg_vector_for_inference(features: Dict[str, float], scaler: Any) -> list[list[float]]:
    """Create the model input vector while enforcing the trained EEG schema."""
    expected = scaler_expected_features(scaler)
    if expected is not None and expected != len(EEG_FEATURE_COLUMNS):
        raise RuntimeError(
            "EEG model/scaler schema mismatch: "
            f"scaler expects {expected} features, "
            f"but inference schema defines {len(EEG_FEATURE_COLUMNS)}."
        )

    return [[float(features.get(column, 0.0)) for column in EEG_FEATURE_COLUMNS]]


def patch_xgboost_compat(model: Any) -> None:
    """Keep deserialized XGBoost sklearn wrappers usable across package versions."""
    if model is None:
        return

    cls = model.__class__
    cls_name = getattr(cls, "__name__", "")
    cls_module = getattr(cls, "__module__", "")
    is_xgb_wrapper = "xgboost" in cls_module.lower() and cls_name.startswith("XGB")

    if is_xgb_wrapper:
        defaults = {
            "use_label_encoder": False,
            "gpu_id": None,
            "predictor": None,
            "enable_categorical": False,
            "max_cat_to_onehot": None,
            "callbacks": None,
            "early_stopping_rounds": None,
        }
        for attr, default in defaults.items():
            if not hasattr(model, attr):
                try:
                    setattr(model, attr, default)
                except Exception:
                    pass

    if hasattr(model, "estimators_"):
        try:
            estimators = getattr(model, "estimators_")
            for estimator in estimators:
                if isinstance(estimator, tuple) and len(estimator) >= 2:
                    patch_xgboost_compat(estimator[1])
                else:
                    patch_xgboost_compat(estimator)
        except Exception:
            pass

    if hasattr(model, "named_estimators_"):
        try:
            for estimator in getattr(model, "named_estimators_").values():
                patch_xgboost_compat(estimator)
        except Exception:
            pass
