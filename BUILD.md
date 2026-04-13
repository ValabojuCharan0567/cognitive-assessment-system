# Release build and deployment quick reference

This complements [README.md](README.md) and [docs/secure_deployment.md](docs/secure_deployment.md).

## Quick start (2-minute overview)

1. Deploy the backend (e.g. **Render** or **Railway**) using `backend/Dockerfile`.
2. Set [environment variables](#environment-variables-reference) in the platform dashboard (especially `GOOGLE_OAUTH_CLIENT_ID`, `DATASET_PATH`, HTTPS flags).
3. Verify in a browser:
   - `https://YOUR_HOST/api/cloud/health` → **200**, JSON with `"status": "ok"`
   - `https://YOUR_HOST/api/cloud/ready` → **200** (not 503)
4. Build the Android APK from **`app/`**:
   ```bash
   flutter build apk --release \
     --dart-define=API_BASE_URL=https://YOUR_HOST/api
   ```
5. Install the APK (Drive, Telegram, etc.) and test on a device **off your dev Wi‑Fi** if possible.

If something fails → **[Common failures & fixes](#common-failures--fixes)**. For the full path, continue below.

## Why `http://192.168.x.x:8000/api` is not enough

That address only works on **your LAN** (same Wi‑Fi, or tricks like USB/`adb reverse`). **Public users** need a **stable HTTPS URL** on the internet, e.g. `https://your-service.onrender.com/api`.

## Final execution checklist (production)

Work through this in order. Play Store is optional for a first pilot.

### Backend (Render / Railway / similar)

- [ ] Deploy **Flask via Docker** (image built from `backend/Dockerfile`).
- [ ] Gunicorn WSGI target is **`api.app:app`** (already set in this repo’s Dockerfile).
- [ ] Set environment variables on the host — see [Environment variables (reference)](#environment-variables-reference).

### Test the API (before building the APK)

1. **Health (process is up):**  
   `https://your-app.onrender.com/api/cloud/health`  
   - Expect JSON including `"status": "ok"`. If this fails, fix deploy before continuing.

2. **Ready (full stack — use this too):**  
   `https://your-app.onrender.com/api/cloud/ready`  
   - **`health`** = HTTP server responding.  
   - **`ready`** = DB + models + dataset checks (see `backend/api/cloud_api.py`). HTTP **200** means “ready”; **503** means something is missing (models, dataset path, or DB).  
   - Use **`ready`** to avoid “app talks to API but ML behaves wrong.”

### ML + data

- [ ] **`models/`** is present in the Docker image (Dockerfile already copies `models/`).
- [ ] **`DATASET_PATH`** is set and mounted or baked so `EEG/` and `speech_data/` exist for **full** mode.
- Without a valid dataset, the service may still run in **`DEMO_MODE`** (limited behavior) — see backend config.

### Flutter app

From **`app/`**, do **not** hardcode the URL for production users. Build with:

```bash
flutter pub get
flutter build apk --release \
  --dart-define=API_BASE_URL=https://your-app.onrender.com/api
```

APK output: `app/build/app/outputs/flutter-apk/app-release.apk`.

### Google Sign-In

- [ ] Backend: **`GOOGLE_OAUTH_CLIENT_ID`** = Web client used to verify `id_token`.
- [ ] Google Cloud Console: **Android** OAuth client with **same package name** as the app and **release keystore SHA-1** (not only debug).

### Distribution

- [ ] Share APK (Drive, Telegram, WhatsApp, etc.).
- [ ] Install on a phone **without USB** (e.g. cellular) and test: login, API flows, assessment flows.

---

## Production upgrades (do not skip)

### 1. Prefer `/api/cloud/ready` for go-live checks

| Endpoint | Meaning |
|----------|--------|
| `GET /api/cloud/health` | Process alive; quick sanity check. |
| `GET /api/cloud/ready` | Models loaded, DB reachable, dataset path OK (full mode). Returns **503** if not fully ready. |

Use both: **health** first, **ready** before you declare “backend is production-ready.”

### 2. Protect SQLite on ephemeral hosts

SQLite file: **`database.db`** at project root in the container (`/workspace/database.db`).

On **Render** (and similar), filesystems are often **ephemeral** — redeploys can wipe data unless you:

- Attach a **persistent disk** and mount it where `database.db` lives, **or**
- Move to a managed DB (e.g. Postgres) later.

Without persistence, user accounts and reports can **reset** after a deploy.

---

## Target architecture

```text
Flutter APK
     ↓  HTTPS
Public API (e.g. Render)
     ↓
Flask + Gunicorn
     ↓
ML models + dataset (server)
     ↓
SQLite (persist disk or migrate later)
```

### After “works locally”

Most issues become **deployment**: wrong env vars, missing files/volumes, OAuth client mismatch. Fix **`ready`**, **`DATASET_PATH`**, **`GOOGLE_OAUTH_CLIENT_ID`**, and **disk** first.

## Environment variables (reference)

Set these in Render / Railway / Docker / secrets. Values below are typical **production** choices.

| Variable | Required | Description |
|----------|----------|-------------|
| `PORT` | Yes | HTTP port Gunicorn binds (often `8000`; some platforms inject their own — use theirs if documented). |
| `FLASK_DEBUG` | Yes | Use **`0`** in production (no debugger / safer). |
| `FLASK_SSL_ADHOC` | Yes | Use **`0`** in production; TLS is handled by the platform or reverse proxy. |
| `GOOGLE_OAUTH_CLIENT_ID` | Yes if using Google login | **Web** OAuth client ID; backend uses it to verify Google `id_token` audience. |
| `DATASET_PATH` | Yes for full ML | Path **inside** the container to dataset root (`EEG/`, `speech_data/`). **Dockerfile default:** `/workspace/data` (copied from repo `data/`). Override on Render only if you use another layout. |
| `REQUIRE_HTTPS_UPLOADS` | Yes | Set **`1`** so non-local clients must use HTTPS for uploads. |
| `ALLOW_HTTP_PRIVATE_LAN` | Yes | Set **`0`** on the public internet (do not treat RFC1918 LAN as exempt). |
| `GUNICORN_WORKERS` | No | Default is fine; increase under load. |
| `GUNICORN_THREADS` | No | Default is fine. |
| `GUNICORN_TIMEOUT` | No | Raise if long EEG/audio jobs time out (default often 120s). |

**Flutter (build-time, not read by Flask):** pass at `flutter build` / `flutter run`:

| Variable | Required | Description |
|----------|----------|-------------|
| `API_BASE_URL` | Yes for production | Full base URL including **`/api`**, e.g. `https://your-app.onrender.com/api`. |

See [infra/.env.example](infra/.env.example) for copy-paste names and comments.

## First successful deployment checklist

Use this as the **final validation gate** before you call the rollout “done”:

- [ ] `GET /api/cloud/health` returns **200** and JSON includes `"status": "ok"`.
- [ ] `GET /api/cloud/ready` returns **200** (not **503**) — models, DB, and dataset path OK for full mode.
- [ ] Flutter app built with `--dart-define=API_BASE_URL=https://<your-host>/api` reaches the API (no LAN URL).
- [ ] Google Sign-In completes (Web client ID on backend + Android OAuth + release SHA-1).
- [ ] ML-related flows return sensible results (not silent demo/fallback unless intended).
- [ ] Release APK installed **without USB** (e.g. cellular) still works.

## Common failures & fixes

### Backend container exits or will not start

- Confirm Gunicorn module is **`api.app:app`** (this repo’s `backend/Dockerfile`).
- Check **build logs** and **runtime logs** in the platform dashboard (Render → Logs).
- Verify `PORT` matches what the platform expects (some set `PORT` automatically).

### `/api/cloud/health` works but `/api/cloud/ready` returns 503

- **`DATASET_PATH`** wrong or volume not mounted → dataset folders missing.
- **Models** missing from image → confirm `models/` is copied in Docker build.
- **Database** not writable or path wrong → SQLite at `/workspace/database.db`; check permissions / disk.

### Google login fails after deploy

- **`GOOGLE_OAUTH_CLIENT_ID`** does not match the **Web** client used by the app / token audience.
- **Android OAuth** client: **package name** mismatch or **SHA-1** from **release** keystore missing (debug SHA-1 does not cover release APK).

### Audio / EEG: `ClientConnection closed while receiving data` or timeouts

- **Large/slow ML:** `/audio/analyze` sends big JSON + runs librosa on the server; the connection can drop if the worker is killed (**OOM**) or times out.
- **Render free (512 MB):** use **`GUNICORN_WORKERS=1`** so only one worker loads models (reduces RAM). Optionally raise plan for more CPU/RAM.
- **Server timeout:** set **`GUNICORN_TIMEOUT=300`** (seconds) in Render environment variables (matches `backend/gunicorn.conf.py` default after deploy).
- **Cold start:** open **`/api/cloud/health`** once, wait ~30s, then try analysis again.
- **App:** release builds use a **5-minute** client timeout for heavy `POST`s (`app/lib/services/api_service.dart`); rebuild the APK after pulling latest.

### Flutter app cannot reach API

- **`API_BASE_URL`** typo, missing `/api` suffix, or still pointing at `192.168.x.x`.
- **HTTP vs HTTPS:** release builds use `usesCleartextTraffic="false"` — use **`https://`** for production API.
- **Backend HTTPS gate:** `REQUIRE_HTTPS_UPLOADS=1` requires the server to see the request as HTTPS (platform TLS + `X-Forwarded-Proto`).

## Backend (Docker)

### Bundled dataset (full ML on Render)

The image includes **`COPY data /workspace/data`** and **`DATASET_PATH=/workspace/data`**. Commit your **`data/EEG/`** and **`data/speech_data/`** files under the [rules in `data/README.md`](data/README.md) (watch GitHub file size limits). For large corpora, use disk/LFS/storage instead.

From the **repository root**:

```bash
docker build -t cognitive-backend -f backend/Dockerfile .
```

Run (example: mount dataset read-only and persist SQLite on the host):

```bash
touch database.db   # once, at repo root on the host
docker run -p 8000:8000 \
  -e DATASET_PATH=/data/dataset \
  -e REQUIRE_HTTPS_UPLOADS=1 \
  -e ALLOW_HTTP_PRIVATE_LAN=0 \
  -e GOOGLE_OAUTH_CLIENT_ID="your-web-client-id.apps.googleusercontent.com" \
  -v "$(pwd)/database.db:/workspace/database.db" \
  -v /path/on/host/to/CognitiveAssessment:/data/dataset:ro \
  cognitive-backend
```

Notes:

- The API process sets the working directory to `backend/`; the Flask application module is **`api.app:app`** (see `backend/Dockerfile`).
- For production, terminate TLS in front of the container (or on the platform) and forward **`X-Forwarded-Proto: https`** so upload routes accept HTTPS clients. See `enforce_https_uploads` in `backend/api/app.py`.
- SQLite lives at **`/workspace/database.db`** in the container (`backend/utils/paths.py` resolves the repo root to `/workspace`). Bind-mount that file (as above) or migrate to a managed database for multi-instance hosting.

Compose (optional):

```bash
cp .env.example .env
# Edit .env — set GOOGLE_OAUTH_CLIENT_ID, DATASET_PATH, HOST_DATASET_PATH, etc.
docker compose -f infra/docker-compose.yml up --build
```

Compose reads **`../.env`** (repo root) via `env_file`. Local Flask loads the same **`.env`** automatically (see `backend/api/app.py` + `python-dotenv`).

## Flutter Android — release APK

From **`app/`**, replace the URL with your **HTTPS** API base (must include the `/api` suffix):

```bash
cd app
flutter pub get
flutter build apk --release \
  --dart-define=API_BASE_URL=https://your-api-host.example.com/api
```

APK output: `app/build/app/outputs/flutter-apk/app-release.apk`.

## Flutter Android — Play Store (AAB)

```bash
cd app
flutter build appbundle --release \
  --dart-define=API_BASE_URL=https://your-api-host.example.com/api
```

AAB output: `app/build/app/outputs/bundle/release/app-release.aab`.

Configure **release signing** in `app/android` (keystore, `key.properties`) per [Flutter’s signing docs](https://docs.flutter.dev/deployment/android).

## Google Sign-In

- Backend: set **`GOOGLE_OAUTH_CLIENT_ID`** to your **OAuth 2.0 Web client** ID (same audience used when verifying the ID token).
- Android: in Google Cloud Console, create an **Android** OAuth client with your **applicationId** and **release SHA-1** from your upload keystore.

## Local debug vs release networking

- **Debug** builds may allow HTTP cleartext (see `app/android/app/src/debug/AndroidManifest.xml`).
- **Release** uses `android:usesCleartextTraffic="false"` — the production **`API_BASE_URL` must use `https://`**.
