from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Dict

from model_utils import (
    EEG_ADVANCED_FEATURE_KEYS,
    build_eeg_vector_for_inference,
)
# from model_loader import get_eeg_model_bundle  # Lazy import to avoid circular dependency


@dataclass
class DomainScores:
    memory: float
    attention: float
    language: float


def _effort_to_load(effort: float) -> tuple[int, str]:
    effort = max(0.0, min(1.0, float(effort)))
    if effort < 0.35:
        return 0, "Low"
    if effort < 0.75:
        return 1, "Medium"
    return 2, "High"


class EEGCognitiveModel:
    """Wrapper around the production EEG classifier/regressor bundle.

    The runtime intentionally supports two paths:
    1. full 30-feature inference when advanced EEG descriptors are present
    2. a stable fallback to `mental_effort_score` for older or lighter payloads

    This keeps demo uploads backward-compatible while preventing near-zero EEG
    effort regressions from silently degrading the fused cognitive report.
    """

    def __init__(self) -> None:
        from model_loader import get_eeg_model_bundle  # Lazy import
        bundle = get_eeg_model_bundle()
        self.clf = bundle["clf"]
        self.reg = bundle["reg"]
        self.scaler = bundle["scaler"]

    def predict_load_and_effort(self, features: Dict[str, float]) -> Dict[str, Any]:
        """Return categorical EEG load plus a normalized 0-1 effort estimate.

        If the payload only has the core band-power metrics, the trained model can
        become unstable because its richer EEG descriptors are absent. In that case
        we trust the already-normalized `mental_effort_score` instead of inventing
        fake zero values.
        """
        has_any_advanced = any(key in features for key in EEG_ADVANCED_FEATURE_KEYS)
        if not has_any_advanced:
            mental_effort = max(0.0, min(1.0, float(features.get("mental_effort_score", 0.5))))
            load_class, load_level = _effort_to_load(mental_effort)
            return {
                "load_class": load_class,
                "load_level": load_level,
                "effort": mental_effort,
            }

        x = build_eeg_vector_for_inference(features, self.scaler)
        xs = self.scaler.transform(x)
        load_class = int(self.clf.predict(xs)[0])
        effort = float(self.reg.predict(xs)[0])

        # If the regressor collapses even though the payload carries a reliable
        # mental-effort estimate, fall back to that explicit feature so the EEG
        # summary stays aligned with the extracted band-power evidence.
        mental_effort = features.get("mental_effort_score")
        if mental_effort is not None:
            mental_effort = max(0.0, min(1.0, float(mental_effort)))
            if effort < 0.05:
                effort = max(effort, mental_effort)
                load_class, load_level = _effort_to_load(effort)
                return {
                    "load_class": load_class,
                    "load_level": load_level,
                    "effort": effort,
                }

        load_level = {0: "Low", 1: "Medium", 2: "High"}.get(load_class, "Medium")
        return {
            "load_class": load_class,
            "load_level": load_level,
            "effort": effort,
        }


class HybridAnalyticsEngine:
    def __init__(self) -> None:
        self.eeg_model = EEGCognitiveModel()

    def score_domains(
        self,
        behavioral: Dict[str, float],
        eeg_features: Dict[str, float],
        audio_features: Dict[str, float],
    ) -> DomainScores:
        """Fuse behavioral, EEG, and audio evidence into domain scores.

        Demo weighting is intentionally simple and interpretable:
        - `memory` = 60% EEG-derived cognitive effort + 40% task accuracy
        - `attention` = 60% EEG-derived cognitive effort + 40% RT score
        - `language` = audio fluency score from the speech model

        This keeps behavioral performance as the anchor signal while EEG and
        audio act as supporting modalities in the final report.
        """
        lang_raw = float(audio_features.get("fluency_score", 60.0))
        if 0.0 <= lang_raw <= 2.0:
            # Backward compatibility for older clients that still send only the
            # categorical class (0=Low, 1=Medium, 2=High).
            lang = 30.0 + (lang_raw * 30.0)
        else:
            lang = lang_raw

        eeg_result = self.eeg_model.predict_load_and_effort(eeg_features)
        effort = float(eeg_result["effort"])

        eff_norm = max(0.0, min(1.0, effort))
        base_cog = 40.0 + (eff_norm * 60.0)

        accuracy = float(behavioral.get("accuracy_percent", 70.0))
        rt = float(behavioral.get("mean_reaction_ms", 1200.0))
        rt_clamped = max(300.0, min(2500.0, rt))
        rt_score = 100.0 - (((rt_clamped - 300.0) / (2500.0 - 300.0)) * 60.0)

        memory = (0.6 * base_cog) + (0.4 * accuracy)
        attention = (0.6 * base_cog) + (0.4 * rt_score)

        return DomainScores(
            memory=float(max(0.0, min(100.0, memory))),
            attention=float(max(0.0, min(100.0, attention))),
            language=float(max(0.0, min(100.0, lang))),
        )
