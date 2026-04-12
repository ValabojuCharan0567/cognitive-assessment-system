#!/usr/bin/env bash

set -euo pipefail

# Script lives in scripts/ — repo root is one level up
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Prefer backend/.venv (matches README); fall back to backend/venv.
if [[ -x "$ROOT_DIR/backend/.venv/bin/python" ]]; then
    VENV_DIR="$ROOT_DIR/backend/.venv"
elif [[ -x "$ROOT_DIR/backend/venv/bin/python" ]]; then
    VENV_DIR="$ROOT_DIR/backend/venv"
else
    VENV_DIR="$ROOT_DIR/backend/.venv"
fi
PYTHON_BIN="$VENV_DIR/bin/python"
PIP_BIN="$VENV_DIR/bin/pip"
export DATASET_PATH="${DATASET_PATH:-$HOME/Datasets/CognitiveAssessment}"

if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 is not available on PATH."
    exit 1
fi

if [[ ! -x "$PYTHON_BIN" ]]; then
    echo "==> creating virtual environment at $VENV_DIR"
    python3 -m venv "$VENV_DIR"
fi

if [[ ! -x "$PIP_BIN" ]]; then
    echo "ERROR: pip is not available inside $VENV_DIR"
    exit 1
fi

echo "==> installing backend dependencies"
"$PIP_BIN" install -r "$ROOT_DIR/backend/requirements.txt"

export REQUIRE_HTTPS_UPLOADS="${REQUIRE_HTTPS_UPLOADS:-1}"
# Phones on Wi‑Fi hit the laptop with a private IP (e.g. 192.168.x.x), not loopback.
# Set to 0 when the API is exposed on a LAN you do not fully trust.
export ALLOW_HTTP_PRIVATE_LAN="${ALLOW_HTTP_PRIVATE_LAN:-1}"
export FLASK_SSL_ADHOC="${FLASK_SSL_ADHOC:-0}"

echo "==> REQUIRE_HTTPS_UPLOADS=$REQUIRE_HTTPS_UPLOADS"
echo "==> ALLOW_HTTP_PRIVATE_LAN=$ALLOW_HTTP_PRIVATE_LAN"
echo "==> DATASET_PATH=$DATASET_PATH"
if [[ "$FLASK_SSL_ADHOC" == "1" ]]; then
    echo "==> FLASK_SSL_ADHOC=1 (serving HTTPS with adhoc certificate)"
else
    echo "==> FLASK_SSL_ADHOC=0 (serving HTTP; local development only)"
fi

echo "==> starting Flask API on port 8000"
export PYTHONPATH="$ROOT_DIR/backend:$PYTHONPATH"
exec "$PYTHON_BIN" -u "$ROOT_DIR/backend/api/app.py"
