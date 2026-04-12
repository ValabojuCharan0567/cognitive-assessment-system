#!/usr/bin/env python3
"""
Train EEG classifier + regressor bundle compatible with backend inference.

Output bundle keys: clf, reg, scaler — see backend/core/ml_models.py (EEGCognitiveModel).
Feature schema: backend/utils/model_utils.EEG_FEATURE_COLUMNS
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.metrics import classification_report, mean_squared_error

try:
    from sklearn.metrics import root_mean_squared_error
except ImportError:  # sklearn < 1.4
    root_mean_squared_error = None  # type: ignore[misc, assignment]
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from xgboost import XGBClassifier, XGBRegressor


def _ensure_backend_path() -> Path:
    repo = Path(__file__).resolve().parents[2]
    backend = repo / "backend"
    if str(backend) not in sys.path:
        sys.path.insert(0, str(backend))
    return repo


def main() -> int:
    _ensure_backend_path()
    from utils.model_utils import EEG_FEATURE_COLUMNS

    parser = argparse.ArgumentParser(description="Train EEG clf+reg bundle for CAS backend.")
    parser.add_argument("--csv", required=True, help="Training CSV with EEG columns + load_class + effort")
    parser.add_argument(
        "--out",
        default="models/eeg_cognitive_model.joblib",
        help="Output joblib path (default: models/eeg_cognitive_model.joblib)",
    )
    parser.add_argument("--test-size", type=float, default=0.2, help="Holdout fraction")
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    csv_path = Path(args.csv).expanduser()
    if not csv_path.is_file():
        print(f"ERROR: CSV not found: {csv_path}", file=sys.stderr)
        return 1

    df = pd.read_csv(csv_path)
    required = set(EEG_FEATURE_COLUMNS) | {"load_class", "effort"}
    missing = required - set(df.columns)
    if missing:
        print(f"ERROR: CSV missing columns: {sorted(missing)}", file=sys.stderr)
        return 1

    y_cls = df["load_class"].astype(int).values
    y_eff = df["effort"].astype(float).values
    y_eff = np.clip(y_eff, 0.0, 1.0)

    if len(df) < 12:
        print("ERROR: Need at least ~12 rows for a minimal train/test split.", file=sys.stderr)
        return 1

    if len(np.unique(y_cls)) < 2:
        print("ERROR: load_class must contain at least 2 distinct classes.", file=sys.stderr)
        return 1

    X = df[list(EEG_FEATURE_COLUMNS)].astype(float).values

    X_train, X_test, yc_train, yc_test, ye_train, ye_test = train_test_split(
        X,
        y_cls,
        y_eff,
        test_size=args.test_size,
        random_state=args.seed,
        stratify=y_cls,
    )

    scaler = StandardScaler()
    X_train_s = scaler.fit_transform(X_train)
    X_test_s = scaler.transform(X_test)

    clf = XGBClassifier(
        n_estimators=200,
        max_depth=6,
        learning_rate=0.05,
        subsample=0.9,
        colsample_bytree=0.9,
        objective="multi:softprob",
        num_class=3,
        eval_metric="mlogloss",
        random_state=args.seed,
        n_jobs=-1,
    )
    clf.fit(X_train_s, yc_train)
    y_pred = clf.predict(X_test_s)
    print("=== EEG classifier (holdout) ===")
    print(classification_report(yc_test, y_pred, digits=3))

    reg = XGBRegressor(
        n_estimators=200,
        max_depth=6,
        learning_rate=0.05,
        subsample=0.9,
        colsample_bytree=0.9,
        objective="reg:squarederror",
        random_state=args.seed,
        n_jobs=-1,
    )
    reg.fit(X_train_s, ye_train)
    ye_pred = reg.predict(X_test_s)
    if root_mean_squared_error is not None:
        rmse = float(root_mean_squared_error(ye_test, ye_pred))
    else:
        rmse = float(mean_squared_error(ye_test, ye_pred, squared=False))
    print(f"=== EEG regressor RMSE (effort, holdout): {rmse:.4f} ===")

    repo_root = _ensure_backend_path()
    out_path = Path(args.out).expanduser()
    if not out_path.is_absolute():
        out_path = repo_root / out_path
    out_path.parent.mkdir(parents=True, exist_ok=True)

    bundle = {
        "clf": clf,
        "reg": reg,
        "scaler": scaler,
        "model_path": str(out_path),
        "feature_columns": list(EEG_FEATURE_COLUMNS),
    }
    joblib.dump(bundle, out_path)
    print(f"Wrote {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
