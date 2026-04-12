#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/app"
MODE="${1:-mobile}"
export DATASET_PATH="${DATASET_PATH:-$HOME/Datasets/CognitiveAssessment}"

usage() {
  cat <<'EOF'
Usage:
  ./run_local_dev.sh mobile
  ./run_local_dev.sh backend
  ./run_local_dev.sh android
  ./run_local_dev.sh ios
  ./run_local_dev.sh web

Modes:
  mobile   Default mobile launcher (same as android)
  backend  Start only backend (HTTP local mode)
  android  Start backend + flutter run for Android emulator
  ios      Start backend + flutter run for iOS simulator
  web      Start backend + flutter run for web

Optional env vars:
  DATASET_PATH        External dataset directory (default: $HOME/Datasets/CognitiveAssessment).
  LOCAL_IP            Required for physical-device URL mapping if needed.
  ANDROID_EMULATOR_ID Android emulator id (default: Medium_Phone_API_36.0).
  ANDROID_DEVICE_ID   Android device id (default: emulator-5554).
  FLUTTER_EXTRA_ARGS  Extra args forwarded to flutter run.
EOF
}

if [[ "$MODE" == "-h" || "$MODE" == "--help" ]]; then
  usage
  exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: curl not found."
  exit 1
fi

if [[ ! -f "$ROOT_DIR/scripts/run_backend.sh" ]]; then
  echo "ERROR: scripts/run_backend.sh not found under $ROOT_DIR"
  exit 1
fi

API_URL="http://127.0.0.1:8000/api"
case "$MODE" in
  mobile)
    API_URL="http://10.0.2.2:8000/api"
    MODE="android"
    ;;
  backend)
    API_URL="http://127.0.0.1:8000/api"
    ;;
  android)
    API_URL="http://10.0.2.2:8000/api"
    ;;
  ios)
    API_URL="http://127.0.0.1:8000/api"
    ;;
  web)
    API_URL="http://127.0.0.1:8000/api"
    ;;
  *)
    echo "ERROR: unknown mode '$MODE'"
    usage
    exit 1
    ;;
esac

BACK_PID=""
STOPPED="0"
ANDROID_EMULATOR_ID="${ANDROID_EMULATOR_ID:-Medium_Phone_API_36.0}"
ANDROID_DEVICE_ID="${ANDROID_DEVICE_ID:-emulator-5554}"

find_adb() {
  if command -v adb >/dev/null 2>&1; then
    command -v adb
    return
  fi

  local sdk_path
  sdk_path="$(flutter doctor -v 2>/dev/null | awk -F'at ' '/Android SDK at/{print $2; exit}')"
  if [[ -n "$sdk_path" && -x "$sdk_path/platform-tools/adb" ]]; then
    echo "$sdk_path/platform-tools/adb"
    return
  fi

  echo ""
}

wait_for_android_boot_complete() {
  local adb_bin="$1"
  local device_id="$2"
  local timeout_seconds="${3:-240}"
  local waited=0

  while [[ "$waited" -lt "$timeout_seconds" ]]; do
    local sys_boot dev_boot boot_anim pm_ready
    sys_boot="$("$adb_bin" -s "$device_id" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
    dev_boot="$("$adb_bin" -s "$device_id" shell getprop dev.bootcomplete 2>/dev/null | tr -d '\r')"
    boot_anim="$("$adb_bin" -s "$device_id" shell getprop init.svc.bootanim 2>/dev/null | tr -d '\r')"
    pm_ready="$("$adb_bin" -s "$device_id" shell pm path android 2>/dev/null || true)"

    if [[ "$sys_boot" == "1" && "$dev_boot" == "1" && "$boot_anim" == "stopped" && "$pm_ready" == package:* ]]; then
      echo "Android device is fully booted and package manager is ready."
      return 0
    fi

    sleep 2
    waited=$((waited + 2))
  done

  echo "WARNING: Timed out waiting for full Android boot readiness."
  return 1
}

resolve_android_device_id() {
  local flutter_out detected
  flutter_out="$(flutter devices 2>/dev/null || true)"

  if [[ "$flutter_out" == *"$ANDROID_DEVICE_ID"* ]]; then
    echo "$ANDROID_DEVICE_ID"
    return
  fi

  detected="$(printf '%s\n' "$flutter_out" | awk '/android/ && /\(mobile\)/ {print $NF; exit}')"
  if [[ -n "$detected" ]]; then
    echo "$detected"
    return
  fi

  echo "$ANDROID_DEVICE_ID"
}

ensure_android_ready() {
  if [[ "$MODE" != "android" ]]; then
    return
  fi

  android_device_present() {
    local out
    out="$(flutter devices 2>/dev/null || true)"
    [[ "$out" == *"$ANDROID_DEVICE_ID"* ]] || [[ "$out" == *"android-arm"* ]]
  }

  echo "Preparing Android emulator/device..."
  if ! android_device_present; then
    echo "Launching emulator $ANDROID_EMULATOR_ID..."
    flutter emulators --launch "$ANDROID_EMULATOR_ID" >/dev/null 2>&1 || true
  fi

  echo "Waiting for Android device $ANDROID_DEVICE_ID..."
  for _ in $(seq 1 120); do
    if android_device_present; then
      break
    fi
    sleep 1
  done

  if ! android_device_present; then
    echo "ERROR: Android device $ANDROID_DEVICE_ID not available."
    echo "Tip: run 'flutter emulators --launch $ANDROID_EMULATOR_ID' and try again."
    exit 1
  fi

  ANDROID_DEVICE_ID="$(resolve_android_device_id)"
  echo "Using Android device: $ANDROID_DEVICE_ID"

  local adb_bin
  adb_bin="$(find_adb)"
  if [[ -n "$adb_bin" ]]; then
    "$adb_bin" start-server >/dev/null 2>&1 || true
    "$adb_bin" -s "$ANDROID_DEVICE_ID" wait-for-device >/dev/null 2>&1 || true

    # Wait for full Android boot + package manager readiness to avoid
    # "device is still booting" during install.
    wait_for_android_boot_complete "$adb_bin" "$ANDROID_DEVICE_ID" 300 || true

    if [[ "$ANDROID_DEVICE_ID" != "emulator-"* ]]; then
      echo "📱 Physical device detected: setting up adb reverse for port 8000"
      "$adb_bin" -s "$ANDROID_DEVICE_ID" reverse tcp:8000 tcp:8000 >/dev/null 2>&1 || true
    fi
  fi
}

cleanup() {
  if [[ "$STOPPED" == "1" ]]; then
    return
  fi
  STOPPED="1"
  if [[ -n "$BACK_PID" ]] && kill -0 "$BACK_PID" >/dev/null 2>&1; then
    echo "Stopping backend (pid $BACK_PID)..."
    kill "$BACK_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

echo "Starting backend in local mode..."
(
  cd "$ROOT_DIR"
  REQUIRE_HTTPS_UPLOADS=0 FLASK_SSL_ADHOC=0 bash scripts/run_backend.sh
) >/tmp/cognitive_backend.log 2>&1 &
BACK_PID=$!

echo "Waiting for backend on http://127.0.0.1:8000/api/cloud/health ..."
for _ in $(seq 1 60); do
  if curl -sf "http://127.0.0.1:8000/api/cloud/health" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! curl -sf "http://127.0.0.1:8000/api/cloud/health" >/dev/null 2>&1; then
  echo "Backend failed to start. Check /tmp/cognitive_backend.log"
  exit 1
fi

echo "Backend is up."
echo "API URL for app: $API_URL"

if [[ "$MODE" == "backend" ]]; then
  echo "Backend-only mode running. Press Ctrl+C to stop."
  wait "$BACK_PID"
  exit 0
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "ERROR: flutter not found on PATH."
  echo "Backend remains running; check /tmp/cognitive_backend.log"
  exit 1
fi

if [[ ! -d "$APP_DIR" ]]; then
  echo "ERROR: Flutter app directory not found: $APP_DIR"
  exit 1
fi

ensure_android_ready

if [[ "$MODE" == "android" && "$ANDROID_DEVICE_ID" != "emulator-"* ]]; then
  # Physical Android device needs 127.0.0.1 instead of 10.0.2.2
  # because we forwarded the port over USB using adb reverse.
  API_URL="http://127.0.0.1:8000/api"
  if [[ -n "${LOCAL_IP:-}" ]]; then
    API_URL="http://${LOCAL_IP}:8000/api"
  fi
fi

flutter_args=(
  --dart-define=API_BASE_URL="$API_URL"
  --dart-define=FORCE_HTTPS_UPLOADS=false
)

# Flutter web uses the current origin (host+port) for OAuth redirect_uri.
# To avoid "redirect_uri_mismatch" between runs, we force a stable origin.
if [[ "$MODE" == "web" ]]; then
  WEB_HOSTNAME="${WEB_HOSTNAME:-127.0.0.1}"
  WEB_PORT="${WEB_PORT:-54624}"
  flutter_args+=(--web-hostname "$WEB_HOSTNAME" --web-port "$WEB_PORT")

  # If you already exported GOOGLE_WEB_CLIENT_ID, wire it into the web build.
  if [[ -n "${GOOGLE_WEB_CLIENT_ID:-}" ]]; then
    flutter_args+=(--dart-define=GOOGLE_WEB_CLIENT_ID="$GOOGLE_WEB_CLIENT_ID")
  fi
fi

if [[ "$MODE" == "android" ]]; then
  if [[ " ${FLUTTER_EXTRA_ARGS:-} " != *" -d "* ]]; then
    ANDROID_DEVICE_ID="$(resolve_android_device_id)"
    flutter_args+=("-d" "$ANDROID_DEVICE_ID")
  fi
fi

echo "Starting Flutter ($MODE)..."
cd "$APP_DIR"
set +e
flutter run "${flutter_args[@]}" ${FLUTTER_EXTRA_ARGS:-}
run_exit=$?

if [[ "$MODE" == "android" && $run_exit -ne 0 ]]; then
  echo "Flutter run failed once, attempting one Android reconnect retry..."
  adb_bin="$(find_adb)"
  if [[ -n "$adb_bin" ]]; then
    "$adb_bin" kill-server >/dev/null 2>&1 || true
    "$adb_bin" start-server >/dev/null 2>&1 || true
    "$adb_bin" reconnect >/dev/null 2>&1 || true
    ANDROID_DEVICE_ID="$(resolve_android_device_id)"
    "$adb_bin" -s "$ANDROID_DEVICE_ID" wait-for-device >/dev/null 2>&1 || true
    wait_for_android_boot_complete "$adb_bin" "$ANDROID_DEVICE_ID" 180 || true
    if [[ "$ANDROID_DEVICE_ID" != "emulator-"* ]]; then
      "$adb_bin" -s "$ANDROID_DEVICE_ID" reverse tcp:8000 tcp:8000 >/dev/null 2>&1 || true
    fi
  fi
  retry_args=(
    --dart-define=API_BASE_URL="$API_URL"
    --dart-define=FORCE_HTTPS_UPLOADS=false
  )
  if [[ "$MODE" == "android" && " ${FLUTTER_EXTRA_ARGS:-} " != *" -d "* ]]; then
    retry_args+=("-d" "$ANDROID_DEVICE_ID")
  fi
  flutter run "${retry_args[@]}" ${FLUTTER_EXTRA_ARGS:-}
  run_exit=$?
fi
set -e
exit $run_exit
