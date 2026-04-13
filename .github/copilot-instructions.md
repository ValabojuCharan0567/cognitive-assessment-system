# Project Guidelines

## Code Style
- Keep backend changes Python 3.10+ compatible and consistent with existing Flask module style in `backend/api/app.py` and `backend/feature_pipeline.py`.
- Prefer small, composable helpers over large route handlers; keep request validation and feature/model logic separated.
- For Flutter (`app/lib/`), preserve existing service + screen + engine split. Avoid moving business logic into UI widgets.

## Architecture
- Backend (`backend/`) is a Flask API with SQLite persistence and blueprint-based routing:
  - `backend/api/app.py`: app bootstrap, auth/core endpoints, HTTPS enforcement.
  - `backend/api/feature_api.py`, `backend/api/cloud_api.py`, `backend/api/reports_api.py`: API blueprints (plus thin `backend/feature_api.py` etc. re-exports for `PYTHONPATH=backend`).
  - `backend/feature_pipeline.py`: EEG/audio payload parsing and feature extraction.
  - `backend/ml_models.py`: cognitive scoring models and domain score logic.
  - `backend/database.py`: schema + lightweight migrations.
- Mobile app (`app/`) is a Flutter client that calls backend APIs through `app/lib/services/api_service.dart` and runs game logic in `app/lib/engine/`.
- Trained artifacts live in `models/`; generated evaluation outputs live in `model_reports/`.

## Build And Run
- Backend local setup/run (installs dependencies and starts Flask on port 8000):
  - `bash scripts/run_backend.sh`
- Full local dev launcher (backend + Flutter target):
  - `bash scripts/run_local_dev.sh`
  - `bash scripts/run_local_dev.sh android|ios|web|backend`
- EDF training and report pipeline:
  - `bash backend/run_all.sh [--preview path/to/file.edf]`
- Individual training/evaluation scripts:
  - `python backend/train_eeg_from_edf.py`
  - `python backend/model_evaluation.py`

## Conventions
- EEG model feature schema is fixed and must stay aligned between training and inference; reference `backend/train_models.py` and `backend/feature_pipeline.py` before adding/removing columns.
- API payloads often use base64 for EEG/audio uploads; maintain backward compatibility for existing request keys when extending endpoints.
- Cognitive scoring weights are currently behavioral/audio/EEG combined in backend logic; preserve existing scoring behavior unless explicitly asked to change product behavior.
- Flutter API endpoint selection should prefer compile-time `--dart-define=API_BASE_URL=...` overrides rather than hardcoding environment-specific URLs.
- Audio analysis pipeline requires minimum 2-second duration for reliable fluency assessment; enforce validation in `backend/feature_pipeline.py`.
- Audio fluency scoring uses probability-weighted calculation with np.dot() for scalability; maintain weights [30.0, 60.0, 90.0] for Low/Medium/High classes.
- Confidence assessment includes "Uncertain" label for predictions with <40% top probability; provide clear user feedback for low-confidence results.

## Pitfalls
- HTTPS upload enforcement is on by default (`REQUIRE_HTTPS_UPLOADS=1`); local mobile testing often needs `bash scripts/run_local_dev.sh` or explicit env overrides.
- Model bundles are loaded in-process; after retraining, restart backend to ensure new artifacts are used.
- `backend/run_all.sh` checks training layout under `DATASET_PATH` (e.g. `EEG_EDF/labels.csv`). The live API validates `EEG/` and `speech_data/` — see `data/README.md`. A gitignored `Dataset/` folder is optional local naming only.

## Docs
- Security and deployment requirements: `secure_deployment.md`
- Research-grade evaluation/reporting workflow: `research_improvements.md`
- Current model performance summary: `model_reports/MODEL_EVALUATION_SUMMARY.md`
