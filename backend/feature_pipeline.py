"""Re-export feature_pipeline from core module with compatibility helpers."""
from core.feature_pipeline import *  # noqa: F401, F403
from core.feature_pipeline import (
    is_valid_speech,
    _align_audio_features_for_inference,
    _predict_eeg_load_and_effort,
    _get_breakdown_metrics,
    _generate_dynamic_confidence_hint,
)

# Keep a non-private alias fallback for tests or legacy code that references app-level module.
__all__ = [
    *globals().get("__all__", []),
    "is_valid_speech",
    "_align_audio_features_for_inference",
    "_predict_eeg_load_and_effort",
    "_get_breakdown_metrics",
    "_generate_dynamic_confidence_hint",
]

