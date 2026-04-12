# Model training (baseline)

Trained artifacts live in the repo root `models/` directory and are loaded at runtime by `backend/core/model_loader.py`.  
These scripts **retrain compatible bundles** using the **same schemas** as inference so you do not drift from `EEG_FEATURE_COLUMNS` or the audio feature extractor.

## Setup

Use the backend virtualenv and ensure `PYTHONPATH` includes `backend` (the scripts add it automatically when run from the repo):

```bash
cd "/path/to/Cognitive Assessment System"
source backend/.venv/bin/activate
python ml/training/train_eeg_models.py --help
python ml/training/train_audio_model.py --help
```

**Back up** existing files under `models/` before overwriting.

## EEG (`train_eeg_models.py`)

**Input CSV** must include:

- Every column in `EEG_FEATURE_COLUMNS` (see `backend/utils/model_utils.py`) — same order is not required; columns are selected by name.
- `load_class` — integer label `0` (Low), `1` (Medium), `2` (High).
- `effort` — float in `[0, 1]` for the regressor head (normalized mental effort).

**Output:** `eeg_cognitive_model.joblib` (default) with keys `clf`, `reg`, `scaler` — matching `EEGCognitiveModel` in `backend/core/ml_models.py`.

Example:

```bash
python ml/training/train_eeg_models.py \
  --csv /path/to/eeg_training.csv \
  --out models/eeg_cognitive_model.joblib
```

## Audio (`train_audio_model.py`)

**Input manifest CSV** with columns:

- `path` — absolute or repo-relative path to a `.wav` (or other format `librosa` can read).
- `label` — `0` / `1` / `2` (Low / Medium / High).

Features are computed with `backend/audio_features.extract_features_from_path` so the vector length matches **production** extraction.

Example:

```bash
python ml/training/train_audio_model.py \
  --manifest /path/to/audio_manifest.csv \
  --out models/audio_fluency_model.joblib
```

**Output:** joblib dict with `model` (classifier) and `scaler` — matching `pseudo_label_audio.py` / runtime audio bundle loading.

## Notes

- These are **baselines**; tune hyperparameters, validation splits, and class balance for your dataset.
- After retraining, restart the API and run your integration tests; XGBoost version mismatches can trigger load warnings — re-save models with the same `xgboost` version as in `backend/requirements.txt` when possible.
