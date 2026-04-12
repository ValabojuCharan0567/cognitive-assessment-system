#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/app"
MODE="${1:-android}"
FAST_MODE="${2:-}"
export DATASET_PATH="${DATASET_PATH:-$HOME/Datasets/CognitiveAssessment}"
BACKEND_LOG="$ROOT_DIR/backend.log"
TEMP_BACKEND_LOG="/tmp/cognitive_backend.log"
ANDROID_EMULATOR_ID="${ANDROID_EMULATOR_ID:-Medium_Phone_API_36.0}"
ANDROID_DEVICE_ID="${ANDROID_DEVICE_ID:-emulator-5554}"

usage() {
  cat <<'EOF'
Usage:
  ./start_fresh.sh backend
  ./start_fresh.sh android
  ./start_fresh.sh mobile
  ./start_fresh.sh ios
  ./start_fresh.sh web
  ./start_fresh.sh android fast
  ./start_fresh.sh ios fast
  ./start_fresh.sh web fast

Notes:
  - backend starts only the Flask API
  - android/mobile starts backend + Flutter on Android
  - ios starts backend + Flutter on iOS
  - web starts backend + Flutter on web
  - pass 'fast' as the second arg to skip flutter pub get
EOF
}

log_section() {
  echo "================================================"
  echo "$1"
  echo "================================================"
}

kill_port_if_busy() {
  local port="$1"
  if lsof -tiTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "Killing process on port $port..."
    lsof -tiTCP:"$port" -sTCP:LISTEN | xargs kill -9
  else
    echo "✓ No process listening on port $port"
  fi
}

find_adb() {
  if command -v adb >/dev/null 2>&1; then
    command -v adb
    return
  fi

  local sdk_path=""
  sdk_path="$(flutter doctor -v 2>/dev/null | awk -F'at ' '/Android SDK at/{print $2; exit}')"
  if [[ -n "$sdk_path" && -x "$sdk_path/platform-tools/adb" ]]; then
    echo "$sdk_path/platform-tools/adb"
    return
  fi

  echo ""
}

find_emulator_bin() {
  if command -v emulator >/dev/null 2>&1; then
    command -v emulator
    return
  fi

  local sdk_path=""
  sdk_path="$(flutter doctor -v 2>/dev/null | awk -F'at ' '/Android SDK at/{print $2; exit}')"
  if [[ -n "$sdk_path" && -x "$sdk_path/emulator/emulator" ]]; then
    echo "$sdk_path/emulator/emulator"
    return
  fi

  echo ""
}

wait_for_android_boot_complete() {
  local adb_bin="$1"
  local device_id="$2"
  local timeout_seconds="${3:-300}"
  local waited=0

  until [[ "$waited" -ge "$timeout_seconds" ]]; do
    local sys_boot dev_boot boot_anim pm_ready
    sys_boot="$("$adb_bin" -s "$device_id" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
    dev_boot="$("$adb_bin" -s "$device_id" shell getprop dev.bootcomplete 2>/dev/null | tr -d '\r')"
    boot_anim="$("$adb_bin" -s "$device_id" shell getprop init.svc.bootanim 2>/dev/null | tr -d '\r')"
    pm_ready="$("$adb_bin" -s "$device_id" shell pm path android 2>/dev/null || true)"

    if [[ "$sys_boot" == "1" && "$dev_boot" == "1" && "$boot_anim" == "stopped" && "$pm_ready" == package:* ]]; then
      echo "✅ Emulator ready"
      return 0
    fi

    echo "⏳ Waiting for emulator boot... (${waited}s/${timeout_seconds}s)"
    sleep 2
    waited=$((waited + 2))
  done

  echo "⚠️ Timed out waiting for full Android boot readiness."
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
  local adb_bin emulator_bin avd_name

  adb_bin="$(find_adb)"
  emulator_bin="$(find_emulator_bin)"

  echo "Resetting ADB..."
  if [[ -n "$adb_bin" ]]; then
    "$adb_bin" kill-server >/dev/null 2>&1 || true
    sleep 2
    "$adb_bin" start-server >/dev/null 2>&1 || true
  else
    echo "⚠️ adb not found on PATH; continuing with flutter tooling only."
  fi

  log_section "📱 CHECKING DEVICE"
  if [[ -n "$adb_bin" ]]; then
    "$adb_bin" devices || true
  else
    flutter devices || true
  fi

  local flutter_out=""
  flutter_out="$(flutter devices 2>/dev/null || true)"
  if [[ "$flutter_out" == *"android"*"(mobile)"* ]]; then
    ANDROID_DEVICE_ID="$(resolve_android_device_id)"
    echo "✅ Device connected: $ANDROID_DEVICE_ID"
    return
  fi

  echo "⚠️ No Android device found. Trying to start emulator..."
  if [[ -z "$emulator_bin" ]]; then
    echo "❌ Android emulator binary not found."
    exit 1
  fi

  avd_name="$("$emulator_bin" -list-avds | head -n 1)"
  avd_name="${ANDROID_EMULATOR_ID:-$avd_name}"
  if [[ -z "$avd_name" ]]; then
    echo "❌ No Android emulator found. Please create one first."
    exit 1
  fi

  echo "Starting emulator: $avd_name"
  nohup "$emulator_bin" -avd "$avd_name" >/tmp/cognitive_emulator.log 2>&1 &

  if [[ -n "$adb_bin" ]]; then
    "$adb_bin" wait-for-device >/dev/null 2>&1 || true
  fi

  echo "Waiting for Android device to appear in Flutter..."
  for _ in $(seq 1 120); do
    flutter_out="$(flutter devices 2>/dev/null || true)"
    if [[ "$flutter_out" == *"android"*"(mobile)"* ]]; then
      break
    fi
    echo "⏳ Device not visible yet; retrying..."
    sleep 2
  done

  ANDROID_DEVICE_ID="$(resolve_android_device_id)"
  if [[ -n "$adb_bin" ]]; then
    wait_for_android_boot_complete "$adb_bin" "$ANDROID_DEVICE_ID" 300 || true
    if [[ "$ANDROID_DEVICE_ID" != "emulator-"* ]]; then
      echo "📱 Physical device detected: setting up adb reverse for port 8000"
      "$adb_bin" -s "$ANDROID_DEVICE_ID" reverse tcp:8000 tcp:8000 >/dev/null 2>&1 || true
    fi
  fi
}

start_backend_only() {
  log_section "🐍 STARTING BACKEND"
  rm -f "$BACKEND_LOG" "$TEMP_BACKEND_LOG"
  (
    cd "$ROOT_DIR"
    REQUIRE_HTTPS_UPLOADS=0 FLASK_SSL_ADHOC=0 bash scripts/run_backend.sh
  ) >"$BACKEND_LOG" 2>&1 &

  echo "Waiting for backend on port 8000..."
  for second in $(seq 1 60); do
    if curl -sf "http://127.0.0.1:8000/api/cloud/health" >/dev/null 2>&1; then
      break
    fi
    echo "⏳ Waiting for backend health... (${second}s/60s)"
    sleep 1
  done

  if curl -sf "http://127.0.0.1:8000/api/cloud/health" >/dev/null 2>&1; then
    echo "✅ Backend running on port 8000"
  else
    echo "❌ Backend failed to start"
    [[ -f "$BACKEND_LOG" ]] && tail -n 20 "$BACKEND_LOG"
    exit 1
  fi
}

run_flutter_pub_get_if_needed() {
  if [[ "$FAST_MODE" == "fast" ]]; then
    echo "⚡ Fast mode enabled: skipping flutter pub get"
    return
  fi

  echo "Running flutter pub get..."
  (cd "$APP_DIR" && flutter pub get)
}

log_section "🧹 CLEANING UP OLD PROCESSES"
kill_port_if_busy 8000

if pgrep -f "flutter run" >/dev/null 2>&1; then
  echo "Killing Flutter processes..."
  pkill -9 -f "flutter run" || true
else
  echo "✓ No flutter run process"
fi

if pgrep -f "dart" >/dev/null 2>&1; then
  echo "Killing Dart processes..."
  pkill -9 -f "dart" || true
else
  echo "✓ No Dart process"
fi

if pgrep -f "python.*backend/api/app.py" >/dev/null 2>&1; then
  echo "Killing backend Python processes..."
  pkill -9 -f "python.*backend/api/app.py" || true
else
  echo "✓ No backend Python process"
fi

echo "DATASET_PATH=$DATASET_PATH"

if [[ -f "$BACKEND_LOG" ]]; then
  log_section "📋 RECENT BACKEND LOGS"
  tail -n 10 "$BACKEND_LOG" || true
fi

case "$MODE" in
  backend)
    start_backend_only
    ;;
  android|mobile)
    ensure_android_ready
    start_backend_only
    log_section "🚀 STARTING FLUTTER APP"
    cd "$APP_DIR"
    run_flutter_pub_get_if_needed
    API_URL="http://10.0.2.2:8000/api"
    if [[ "$ANDROID_DEVICE_ID" != "emulator-"* ]]; then
      API_URL="http://127.0.0.1:8000/api"
    fi
    flutter run -d "$ANDROID_DEVICE_ID" \
      --dart-define=API_BASE_URL="$API_URL"
    ;;
  ios)
    start_backend_only
    log_section "🚀 STARTING FLUTTER APP"
    cd "$ROOT_DIR"
    run_flutter_pub_get_if_needed
    bash scripts/run_local_dev.sh ios
    ;;
  web)
    start_backend_only
    log_section "🚀 STARTING FLUTTER APP"
    cd "$ROOT_DIR"
    run_flutter_pub_get_if_needed
    bash scripts/run_local_dev.sh web
    ;;
  -h|--help)
    usage
    ;;
  *)
    echo "❌ Unknown mode: $MODE"
    usage
    exit 1
    ;;
esac

log_section "✅ ALL SYSTEMS RUNNING"
