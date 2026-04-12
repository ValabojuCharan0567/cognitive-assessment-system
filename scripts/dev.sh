#!/bin/bash
# Start the Cognitive Assessment System with Android emulator (robust version)

set -e

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/backend"
VENV_DIR="$BACKEND_DIR/.venv"
PYTHON_BIN="$VENV_DIR/bin/python"
ANDROID_EMULATOR="/Users/charanvalaboju/Library/Android/sdk/emulator/emulator"
ADB="/Users/charanvalaboju/Library/Android/sdk/platform-tools/adb"
EMULATOR_NAME="Medium_Phone_API_36.0"

# Cleanup handler
cleanup() {
  echo ""
  echo "Shutting down..."
  pkill -f "python.*api/app.py" 2>/dev/null || true
  exit 0
}
trap cleanup SIGINT SIGTERM

echo "╔════════════════════════════════════════════╗"
echo "║  Cognitive Assessment System Launcher      ║"
echo "║  Mode: Android Emulator                    ║"
echo "╚════════════════════════════════════════════╝"

# Check prerequisites
if [[ ! -f "$PYTHON_BIN" ]]; then
  echo "ERROR: Python venv not found at $PYTHON_BIN"
  echo "Creating venv..."
  python3 -m venv "$VENV_DIR"
  "$PYTHON_BIN" -m pip install --upgrade pip setuptools wheel
  "$PYTHON_BIN" -m pip install -r "$BACKEND_DIR/requirements.txt"
fi

if [[ ! -f "$ANDROID_EMULATOR" ]]; then
  echo "ERROR: Android emulator not found at $ANDROID_EMULATOR"
  exit 1
fi

if [[ ! -f "$ADB" ]]; then
  echo "ERROR: ADB not found at $ADB"
  exit 1
fi

# Wait a bit for any cleanup from previous runs
sleep 2

echo ""
echo "Step 1/4: Starting Android emulator..."
if pgrep -f "emulator.*$EMULATOR_NAME" >/dev/null 2>&1; then
  echo "  → Emulator already running, will reuse"
else
  echo "  → Launching $EMULATOR_NAME..."
  "$ANDROID_EMULATOR" -avd "$EMULATOR_NAME" -no-snapshot-load -prop ro.kernel.qemu=1 >/dev/null 2>&1 &
  echo "  → Waiting 60 seconds for emulator to boot..."
  sleep 60
  echo "  → Emulator boot complete"
fi

echo ""
echo "Step 2/4: Verifying ADB connection..."
"$ADB" kill-server 2>/dev/null || true
sleep 2
"$ADB" start-server >/dev/null 2>&1
sleep 3

# Wait for device
WAIT_COUNT=0
MAX_WAITS=20
while ! "$ADB" devices 2>/dev/null | grep -q "emulator.*device"; do
  WAIT_COUNT=$((WAIT_COUNT + 1))
  if [[ $WAIT_COUNT -gt $MAX_WAITS ]]; then
    echo "ERROR: Emulator did not connect via ADB after $(($MAX_WAITS * 2)) seconds"
    echo "Try restarting the emulator manually:"
    echo "  flutter emulators --launch $EMULATOR_NAME"
    exit 1
  fi
  echo "  → Waiting for ADB... ($WAIT_COUNT/$MAX_WAITS)"
  sleep 2
done
echo "  ✓ ADB connection ready"

echo ""
echo "Step 3/4: Starting backend API..."
cd "$BACKEND_DIR" || exit 1
export PYTHONPATH="$BACKEND_DIR:$PYTHONPATH"
"$PYTHON_BIN" api/app.py >/dev/null 2>&1 &
BACK_PID=$!
echo "  ✓ Backend started (PID: $BACK_PID)"
sleep 3

echo ""
echo "Step 4/4: Deploying Flutter app..."
cd "$ROOT_DIR/app" || exit 1
echo "  → Building and deploying to emulator..."
flutter run -d emulator-5554

cleanup



