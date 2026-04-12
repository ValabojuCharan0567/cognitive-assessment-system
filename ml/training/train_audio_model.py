#!/usr/bin/env python3
"""
Train audio cognitive-load classifier bundle compatible with runtime loading.

Output bundle keys: model, scaler — see ml/preprocessing/pseudo_label_audio.py and
backend/core/model_loader.get_audio_model_bundle().

Features match backend/audio_features.extract_features_from_path().
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.metrics import classification_report
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from xgboost import XGBClassifier


def _ensure_backend_path() -> Path:
    repo = Path(__file__).resolve().parents[2]
    backend = repo / "backend"
    if str(backend) not in sys.path:
        sys.path.insert(0, str(backend))
    return repo


def main() -> int:
    repo = _ensure_backend_path()
    from audio_features import extract_features_from_path

    parser = argparse.ArgumentParser(description="Train audio fluency / load classifier for CAS backend.")
    parser.add_argument(
        "--manifest",
        required=True,
        help="CSV with columns: path, label (0=Low, 1=Medium, 2=High)",
    )
    parser.add_argument(
        "--out",
        default="models/audio_fluency_model.joblib",
        help="Output joblib path",
    )
    parser.add_argument("--test-size", type=float, default=0.2)
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    manifest_path = Path(args.manifest).expanduser()
    if not manifest_path.is_file():
        print(f"ERROR: manifest not found: {manifest_path}", file=sys.stderr)
        return 1

    df = pd.read_csv(manifest_path)
    if "path" not in df.columns or "label" not in df.columns:
        print("ERROR: manifest CSV must have columns: path, label", file=sys.stderr)
        return 1

    features_list: list[np.ndarray] = []
    labels_list: list[int] = []
    base = manifest_path.parent

    for _, row in df.iterrows():
        raw_path = Path(str(row["path"]).strip())
        if not raw_path.is_absolute():
            raw_path = (repo / raw_path).resolve()
        label = int(row["label"])
        if label not in (0, 1, 2):
            print(f"WARN: skip invalid label {label} for {raw_path}", file=sys.stderr)
            continue
        if not raw_path.is_file():
            print(f"WARN: missing file {raw_path}", file=sys.stderr)
            continue
        try:
            vec = extract_features_from_path(raw_path)
        except Exception as exc:
            print(f"WARN: feature extract failed {raw_path}: {exc}", file=sys.stderr)
            continue
        features_list.append(np.asarray(vec, dtype=float).ravel())
        labels_list.append(label)

    if len(features_list) < 12:
        print("ERROR: need at least ~12 successful rows after extraction.", file=sys.stderr)
        return 1

    n_feat = features_list[0].shape[0]
    for i, v in enumerate(features_list):
        if v.shape[0] != n_feat:
            print(f"ERROR: inconsistent feature length at row {i}: {v.shape[0]} vs {n_feat}", file=sys.stderr)
            return 1

    X = np.vstack(features_list)
    y = np.array(labels_list, dtype=int)

    if len(np.unique(y)) < 2:
        print("ERROR: labels must include at least 2 classes.", file=sys.stderr)
        return 1

    X_train, X_test, y_train, y_test = train_test_split(
        X,
        y,
        test_size=args.test_size,
        random_state=args.seed,
        stratify=y,
    )

    scaler = StandardScaler()
    X_train_s = scaler.fit_transform(X_train)
    X_test_s = scaler.transform(X_test)

    model = XGBClassifier(
        n_estimators=250,
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
    model.fit(X_train_s, y_train)
    y_pred = model.predict(X_test_s)
    print("=== Audio classifier (holdout) ===")
    print(classification_report(y_test, y_pred, digits=3))

    out_path = Path(args.out).expanduser()
    if not out_path.is_absolute():
        out_path = repo / out_path
    out_path.parent.mkdir(parents=True, exist_ok=True)

    bundle = {
        "model": model,
        "scaler": scaler,
        "model_path": str(out_path),
        "n_features": int(n_feat),
    }
    joblib.dump(bundle, out_path)
    print(f"Wrote {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
