# 🧠 Cognitive Assessment System

An AI-powered cognitive assessment platform using:
- 🎤 Audio analysis
- 🧠 EEG processing
- 🎮 Cognitive games
- 📱 Flutter mobile app (Android)
- 🔌 Flask backend

## 🚀 Run Locally

### Quick Start (One Command)

```bash
bash scripts/dev.sh
```

This starts:
1. Backend API (Python Flask) on port 8000
2. Flutter Android app (on emulator or device)

### Autorun API + Flutter (same machine)

```bash
bash scripts/autorun_app.sh
```

Uses your Mac’s Wi‑Fi IP for `API_BASE_URL` when possible (physical phone). Emulator: set `API_BASE_URL` or use `adb reverse tcp:8000 tcp:8000` and `API_BASE_URL=http://127.0.0.1:8000/api`.

### Run backend only:

```bash
bash scripts/run_backend.sh
```

### Cursor / VS Code (no `pyenv shell` needed)

The workspace uses **`backend/.venv`** automatically:

- **`.vscode/settings.json`** — default Python interpreter is `backend/.venv/bin/python`, and the integrated terminal can activate that environment (Python extension).
- **`.vscode/tasks.json`** — default **build** task (**Cmd+Shift+B** / **Ctrl+Shift+B**) runs **`Autorun: Backend + Flutter`** (`scripts/autorun_app.sh`: API on port 8000, then `flutter run` with `API_BASE_URL` set from your LAN IP). Other tasks: **Backend only** or **Backend (skip pip)** via **Terminal → Run Task…**.

From a terminal you can do the same:

```bash
bash scripts/autorun_app.sh
```

Optional: `FLUTTER_DEVICE_ID=<id> bash scripts/autorun_app.sh` or `API_BASE_URL=http://127.0.0.1:8000/api` for emulator + `adb reverse`.

If you use **pyenv** elsewhere, you do not need `pyenv shell` for this repo: use the venv above, or run `pyenv init` in your shell profile if you want `pyenv shell` to work globally.

### Run on specific device:

```bash
cd app && flutter run -d <device_id>
```

List available devices:
```bash
flutter devices
```

### Local Google Sign-In build flags
If you are testing Google sign-in locally, export the client IDs and the run scripts will forward them into Flutter automatically:

```bash
export GOOGLE_SERVER_CLIENT_ID="<your-android-server-client-id>"
export GOOGLE_WEB_CLIENT_ID="<your-web-client-id>"
bash scripts/run_local_dev.sh android
```

If you use `scripts/autorun_app.sh`, it also forwards these values.

### Build the release APK with Google sign-in
Use the repo wrapper so the Android Google sign-in client ID is always included:

```bash
cd '/Users/charanvalaboju/valaboju charan/Cognitive Assessment System'
./scripts/build_release_apk.sh \
  --api-url=https://cognitive-assessment-system-production.up.railway.app/api \
  --google-server-client-id=994631611469-h0rrsme268j2f4h5t92kbpdb3hc75n34.apps.googleusercontent.com
```

If you have a local `.env`, the script will also read `API_BASE_URL` and `GOOGLE_SERVER_CLIENT_ID` from it.

### Fix "HTTPS is required for secure upload" during local Google login

Phones use a **private LAN IP** (for example `192.168.x.x`), not `127.0.0.1`, so the backend may treat them as non-local and require HTTPS.

**Recommended (default in `scripts/run_backend.sh`):** allow HTTP from private LAN clients only:

```bash
bash scripts/run_backend.sh
# exports ALLOW_HTTP_PRIVATE_LAN=1 by default; set ALLOW_HTTP_PRIVATE_LAN=0 on untrusted networks
```

**If you start Flask manually**, either allow LAN HTTP or disable the upload HTTPS gate entirely:

```bash
cd "/Users/charanvalaboju/valaboju charan/Cognitive Assessment System"
source backend/.venv/bin/activate
export PYTHONPATH=backend:$PYTHONPATH
export ALLOW_HTTP_PRIVATE_LAN=1   # HTTP OK for 10.x / 172.16–31.x / 192.168.x clients
export FLASK_SSL_ADHOC=0
python backend/api/app.py
# Alternative: REQUIRE_HTTPS_UPLOADS=0 (disables the check for all clients — dev only)
```

Use your Mac’s LAN IP in Flutter (see `ifconfig`), for example:

```bash
cd app && flutter run -d <device_id> --dart-define=API_BASE_URL=http://192.168.31.159:8000/api
```

If port 8000 is busy: `lsof -i :8000` then `kill <pid>`.


## 🛠 Tech Stack

- **Frontend:** Flutter (Dart)
- **Backend:** Flask (Python 3.11+)
- **ML:** scikit-learn, librosa, signal processing
- **Data:** EEG (EDF format) + Audio features
- **Mobile:** Flutter Android

## 📂 Project Structure

```
Cognitive-Assessment-System/
├── app/               # Flutter mobile app (Android)
├── backend/           # Flask API + inference
├── ml/                # ML pipeline (preprocessing, features, evaluation)
├── models/            # Trained ML artifacts
├── docs/              # Documentation & reports
├── scripts/           # Run scripts
├── infra/             # Docker & environment configs
└── data/              # Optional local samples (see data/README.md; not the external DATASET_PATH)
```

## 🧠 System Flow

1. User launches app on Android device/emulator
2. App sends data to backend API
3. Features extracted (audio/EEG)
4. ML model predicts cognitive score
5. Results displayed in app

## 📊 Dataset Setup

See **[data/README.md](data/README.md)** for layout (`EEG/`, `speech_data/`), the repo **`data/`** bundle for Docker/Railway, and the gitignored **`Dataset/`** convention.

**Local default** (large data usually outside the clone):

```bash
$HOME/Datasets/CognitiveAssessment
```

Override:

```bash
export DATASET_PATH="/path/to/folder/with/EEG/and/speech_data"
```

**Docker / Railway:** `backend/Dockerfile` copies **`data/`** → `/workspace/data` and sets `DATASET_PATH`. That directory must exist in the repo for `docker build` to succeed.

The backend reads `DATASET_PATH` through `backend/config/config.py`.

## 🐳 Docker

Build the backend image:

```bash
docker build -t cognitive-backend -f backend/Dockerfile .
```

Run with dataset mounted:

```bash
docker run -p 8000:8000 \
  -e DATASET_PATH=/data/dataset \
  -v /Users/charanvalaboju/Datasets/CognitiveAssessment:/data/dataset:ro \
  cognitive-backend
```

Or use Docker Compose (reads env from `infra/.env`):

```bash
docker compose -f infra/docker-compose.yml up --build
```

## 📚 ML Pipeline

See [ml/README.md](ml/README.md) for details on:
- Data preprocessing
- Feature extraction
- Model training & evaluation

## 🔐 Deployment

See [docs/secure_deployment.md](docs/secure_deployment.md) for production setup guide.

## 📘 Full Technical Documentation

### 1. Project Overview

- **Project name:** Cognitive Assessment System (CAS)
- **Objective and problem statement:**
  - Provide an integrated system for neuroscience-based cognitive assessment using EEG and audio signals.
  - Solve cross-platform deployment of actionable cognitive scoring for researchers and evaluators.
- **Key features and functionalities:**
  - EEG and audio feature extraction
  - Flask-based API for inference and reporting
  - Flutter mobile frontend with interactive cognitive tasks
  - SQLite persistence and historical result tracking
  - Offline/local dataset compatibility and Docker support
- **Target users:**
  - Researchers and clinicians
  - Academic project evaluators
  - Mobile µhealth developers

### 2. System Architecture

- **High-level architecture:**
  - Frontend: Flutter app in `app/` (mobile UI and data capture)
  - Backend: Flask API in `backend/` (feature extraction + model scoring)
  - Database: SQLite via `backend/database.py`
  - APIs: `backend/feature_api.py`, `backend/cloud_api.py`, `backend/reports_api.py`
- **Data flow explanation:**
  1. App submits EEG/audio/behavioral payload to API endpoint.
  2. Backend pipelines decode and validate input.
  3. `backend/feature_pipeline.py` extracts features.
  4. `backend/ml_models.py` runs prediction logic.
  5. Results saved and returned to app.

### 3. Technology Stack

- **Frontend:** Flutter/Dart
- **Backend:** Python + Flask
- **Database:** SQLite
- **ML libraries:** scikit-learn, numpy, pandas, librosa
- **Tools:** Docker, Git, Flutter CLI

**Justification:** lightweight, cross-platform, easy onboarding, reproducible model artifacts.

**Alternatives considered:** React Native, FastAPI, Postgres. Chosen stack remains aligned with existing codebase and simple deployment.

### 4. Project Structure (File/Folder Explanation)

- `app/` — Flutter mobile app source.
- `backend/` — API, model pipeline, DB, config.
- `ml/` — dataset analysis, training scripts.
- `models/` — joblib artifacts.
- `docs/` — security and research docs.
- `scripts/` — startup scripts.
- `infra/` — docker-compose and environment.
- `data/` — datasets or sample payloads.

### 5. Code Explanation

- `backend/app.py`: app bootstrap, blueprint registration, HTTPS check.
- `backend/feature_pipeline.py`: data parsing & feature extraction.
- `backend/ml_models.py`: cognitive score calculation and confidence signaling.
- `backend/model_loader.py`: artifact load helpers.
- `backend/database.py`: schema and storage functions.

### 6. Database / Data Handling

- Data sources: EEG (.edf), audio capture, behavioral form input.
- Schema: `users`, `sessions`, `results` (structured fields + JSON features).
- Flow: request -> extract -> score -> insert -> respond.

### 7. Model / Logic

- Models: EEG classifier, audio fluency classifier, behavior model.
- Weighted scoring using features from multiple modalities.
- Limitations: small dataset, absence of online training.
- Improvements: deep learning, streaming, advanced validation.

### 8. Setup and Installation Guide

**Prerequisites:** Python 3.10+, Flutter SDK, git, sqlite3.

**Backend setup:**
- `python3 -m venv backend/.venv`
- `source backend/.venv/bin/activate`
- `pip install -r backend/requirements.txt`
- `bash scripts/run_backend.sh`

**Mobile setup:**
- `cd app`
- `flutter pub get`
- `./run_local_dev.sh android`
- `flutter run -d <device_id>`

### 9. Usage Guide

- Open app → choose cognitive task → record and upload data.
- API responds with cognitive score + confidence label.
- Use reports screen to compare sessions.

### 10. Challenges and Solutions

- Audio minimum duration, EEG noise, HTTPS upload constraints.
- Solved via validation in `feature_pipeline.py`, filtering in EEG modules, env-based HTTPS override.

### 11. Future Enhancements

- Real-time EEG streaming
- Cloud deployment with managed database
- Federated learning and user roles

### 12. Conclusion

CAS is a full-stack prototype for neuroscience-backed cognitive assessment, combining mobile interaction, backend inference, and research-grade model workflows.
