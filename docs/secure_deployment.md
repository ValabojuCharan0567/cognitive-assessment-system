# Secure Upload and Feature Pipeline Setup

This project now supports:

- dedicated cloud feature extraction module
- explicit cloud processing API namespace
- on-device preprocessing metadata for EEG and audio uploads
- HTTPS enforcement for non-local requests
- optional ad-hoc TLS for local HTTPS testing

## What changed

1. New feature module endpoints:
- POST /api/features/eeg/extract
- POST /api/features/audio/analyze

2. Reports blueprint is registered and active:
- /api/reports/*

3. Cloud processing namespace is available:
- GET /api/cloud/health
- GET /api/cloud/pipeline
- GET /api/cloud/stats

4. HTTPS is enforced by default for non-local clients:
- Environment variable: REQUIRE_HTTPS_UPLOADS=1 (default)

5. Optional Flask ad-hoc TLS mode:
- Environment variable: FLASK_SSL_ADHOC=1

## Local development (HTTP)

Use this for same-machine testing only:

```bash
REQUIRE_HTTPS_UPLOADS=0 FLASK_SSL_ADHOC=0 ./run_backend.sh
```

Or use one-command local launcher:

```bash
./run_local_dev.sh
./run_local_dev.sh mobile
./run_local_dev.sh backend
./run_local_dev.sh android
./run_local_dev.sh ios
./run_local_dev.sh web
```

Note: `./run_local_dev.sh` now defaults to mobile app launch (`android`).

## Local development (HTTPS)

Use this to test secure upload behavior:

```bash
REQUIRE_HTTPS_UPLOADS=1 FLASK_SSL_ADHOC=1 ./run_backend.sh
```

Notes:
- Ad-hoc certs are self-signed and not suitable for production.
- Mobile clients may reject self-signed certificates unless trust settings are changed.

## Production recommendation

Run Flask behind an HTTPS reverse proxy (Nginx/Caddy/Traefik) and forward:
- X-Forwarded-Proto: https

Keep these settings:

```bash
REQUIRE_HTTPS_UPLOADS=1
FLASK_SSL_ADHOC=0
```

## Flutter app endpoint config

The app supports compile-time endpoint override:

```bash
flutter run --dart-define=API_BASE_URL=https://your-domain.example/api --dart-define=FORCE_HTTPS_UPLOADS=true
```

If API_BASE_URL is not provided, the app chooses a platform default and uses HTTPS for non-local hosts when FORCE_HTTPS_UPLOADS=true.
