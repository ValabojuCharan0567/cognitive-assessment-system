from __future__ import annotations

import csv
from functools import lru_cache
from pathlib import Path
from typing import Any, Dict

import numpy as np
from config import dataset_subpath


ROOT = Path(__file__).resolve().parents[1]
EEG_SIGNAL_DIR = dataset_subpath("EEG SIGNAL DATA")


def _safe_float(x: Any) -> float | None:
    try:
        v = float(x)
        if np.isfinite(v):
            return v
        return None
    except Exception:
        return None


@lru_cache(maxsize=1)
def _reference_efforts_sorted() -> np.ndarray:
    """
    Build a reference distribution of mental_effort_score from the EEG SIGNAL DATA folder.
    We compute effort as theta/(alpha+beta) and clamp to [0, 1], matching the app's EDF extractor.
    """
    if not EEG_SIGNAL_DIR.exists():
        raise FileNotFoundError(f"EEG reference folder not found: {EEG_SIGNAL_DIR}")

    efforts: list[float] = []
    for p in sorted(EEG_SIGNAL_DIR.glob("P*.csv")):
        with open(p, "r", newline="") as f:
            reader = csv.DictReader(f)
            for row in reader:
                theta = _safe_float(row.get("theta_power_mean"))
                alpha = _safe_float(row.get("alpha_power_mean"))
                beta = _safe_float(row.get("beta_power_mean"))
                if theta is None or alpha is None or beta is None:
                    continue
                effort = theta / (alpha + beta + 1e-6)
                if effort < 0.0:
                    effort = 0.0
                elif effort > 1.0:
                    effort = 1.0
                efforts.append(float(effort))

    if not efforts:
        raise RuntimeError(f"No valid rows found in: {EEG_SIGNAL_DIR}")

    arr = np.array(efforts, dtype=float)
    arr.sort()
    return arr


def effort_reference_analysis(effort: float) -> Dict[str, Any]:
    """
    Return percentile and reference banding for a given effort value in [0, 1].
    """
    e = float(effort)
    if not np.isfinite(e):
        return {"error": "effort not finite"}
    e = max(0.0, min(1.0, e))

    ref = _reference_efforts_sorted()

    # Percentile rank (0..100)
    idx = int(np.searchsorted(ref, e, side="right"))
    pct = (idx / len(ref)) * 100.0

    p25, p50, p75 = np.percentile(ref, [25, 50, 75])
    if e < p25:
        band = "low"
    elif e > p75:
        band = "high"
    else:
        band = "typical"

    return {
        "percentile": round(float(pct), 1),
        "band": band,
        "reference": {
            "n": int(ref.size),
            "p25": round(float(p25), 3),
            "p50": round(float(p50), 3),
            "p75": round(float(p75), 3),
        },
    }
