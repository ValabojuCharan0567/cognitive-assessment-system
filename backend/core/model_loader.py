from __future__ import annotations

from functools import lru_cache
from pathlib import Path
from typing import Any, Dict

import joblib

from model_utils import patch_xgboost_compat
from utils.paths import get_models_dir


def _resolve_first_existing(*candidates: str) -> Path:
    models_dir = get_models_dir()
    for candidate in candidates:
        path = models_dir / candidate
        if path.exists():
            return path
    raise FileNotFoundError(
        f"Model not found. Expected one of: {', '.join(candidates)}"
    )


@lru_cache(maxsize=1)
def get_audio_model_bundle() -> Dict[str, Any]:
    path = _resolve_first_existing("audio_fluency_model.joblib", "audio_dt_model.joblib")
    bundle = joblib.load(path)
    if isinstance(bundle, dict):
        bundle.setdefault("model_path", str(path))
        patch_xgboost_compat(bundle.get("model"))
    return bundle


@lru_cache(maxsize=1)
def get_eeg_model_bundle() -> Dict[str, Any]:
    path = _resolve_first_existing("eeg_model.pkl", "eeg_cognitive_model.joblib")
    bundle = joblib.load(path)
    if isinstance(bundle, dict):
        bundle.setdefault("model_path", str(path))
        patch_xgboost_compat(bundle.get("clf"))
        patch_xgboost_compat(bundle.get("reg"))
    return bundle


def warmup_models() -> None:
    get_eeg_model_bundle()
    get_audio_model_bundle()
