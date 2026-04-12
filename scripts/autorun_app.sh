#!/usr/bin/env bash
# Start Flask (background) then Flutter on a device. Stops backend when Flutter exits.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PYTHON_BIN="$ROOT_DIR/backend/.venv/bin/python"
if [[ ! -x "$PYTHON_BIN" ]]; then
  echo "ERROR: Missing $PYTHON_BIN — run: bash scripts/run_backend.sh once to create the venv."
  exit 1
fi

if command -v lsof >/dev/null 2>&1; then
  for pid in $(lsof -ti:TCP:8000 -sTCP:LISTEN 2>/dev/null || true); do
    echo "==> Freeing port 8000 (PID $pid)"
    kill "$pid" 2>/dev/null || true
  done
  sleep 1
fi

export PYTHONPATH="$ROOT_DIR/backend"
export ALLOW_HTTP_PRIVATE_LAN="${ALLOW_HTTP_PRIVATE_LAN:-1}"
export REQUIRE_HTTPS_UPLOADS="${REQUIRE_HTTPS_UPLOADS:-1}"
export FLASK_SSL_ADHOC="${FLASK_SSL_ADHOC:-0}"
export DATASET_PATH="${DATASET_PATH:-$HOME/Datasets/CognitiveAssessment}"

LAN_IP="${API_HOST:-}"
if [[ -z "$LAN_IP" ]]; then
  LAN_IP="$(ipconfig getifaddr en0 2>/dev/null || true)"
fi
if [[ -z "$LAN_IP" ]]; then
  LAN_IP="$(ipconfig getifaddr en1 2>/dev/null || true)"
fi
if [[ -z "$LAN_IP" ]]; then
  LAN_IP="127.0.0.1"
fi
API_BASE_URL="${API_BASE_URL:-http://${LAN_IP}:8000/api}"

BACKEND_LOG="${BACKEND_LOG:-/tmp/cas_autorun_backend.log}"
: >"$BACKEND_LOG"

cleanup() {
  echo ""
  echo "==> Stopping backend on port 8000..."
  if command -v lsof >/dev/null 2>&1; then
    for pid in $(lsof -ti:TCP:8000 -sTCP:LISTEN 2>/dev/null || true); do
      kill "$pid" 2>/dev/null || true
    done
  fi
}
trap cleanup EXIT INT TERM

echo "==> Starting Flask (log: $BACKEND_LOG)"
echo "==> Flutter will use API_BASE_URL=$API_BASE_URL"
"$PYTHON_BIN" -u "$ROOT_DIR/backend/api/app.py" >>"$BACKEND_LOG" 2>&1 &
BACK_PID=$!

for i in $(seq 1 120); do
  if curl -sf "http://127.0.0.1:8000/api/cloud/health" >/dev/null 2>&1; then
    echo "==> Backend ready (${i}s)"
    break
  fi
  if ! kill -0 "$BACK_PID" 2>/dev/null; then
    echo "ERROR: Backend process exited. Last log lines:"
    tail -40 "$BACKEND_LOG" || true
    exit 1
  fi
  sleep 1
done

if ! curl -sf "http://127.0.0.1:8000/api/cloud/health" >/dev/null; then
  echo "ERROR: Backend did not respond on port 8000"
  tail -50 "$BACKEND_LOG" || true
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "ERROR: flutter not on PATH"
  exit 1
fi

cd "$ROOT_DIR/app"
flutter_args=(--dart-define=API_BASE_URL="$API_BASE_URL")
if [[ -n "${FLUTTER_DEVICE_ID:-}" ]]; then
  flutter_args+=(-d "$FLUTTER_DEVICE_ID")
fi
# shellcheck disable=SC2086
set +e
flutter run "${flutter_args[@]}" ${FLUTTER_EXTRA_ARGS:-}
exit_code=$?
set -e
exit "$exit_code"
