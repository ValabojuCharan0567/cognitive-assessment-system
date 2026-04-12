#!/bin/bash
#  Quick status check for the Cognitive Assessment System setup

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/backend"
VENV_DIR="$BACKEND_DIR/.venv"
PYTHON_BIN="$VENV_DIR/bin/python"

echo "=== System Status ==="

# Check venv
if [[ -f "$PYTHON_BIN" ]]; then
  echo "✓ Backend venv: OK"
else
  echo "✗ Backend venv: NOT FOUND"
  exit 1
fi

# Check required modules
echo "Checking Python modules..."
$PYTHON_BIN << 'EOF'
try:
    from config import DEMO_MODE
    from ml_models import HybridAnalyticsEngine
    from core.feature_pipeline import analyze_audio_payload
    print("✓ All imports: OK")
except Exception as e:
    print(f"✗ Import error: {e}")
    exit(1)
EOF

# Check emulator
echo ""
echo "=== Android Emulator Status ==="
if pgrep -f "emulator.*Medium_Phone_API" >/dev/null; then
  echo "✓ Android emulator: RUNNING"
else
  echo "✗ Android emulator: NOT RUNNING"
  echo "  To start: flutter emulators --launch Medium_Phone_API_36.0"
fi

# Check Flutter
echo ""
echo "=== Flutter Devices ==="
flutter devices 2>&1 | head -10

echo ""
echo "To start the full system, run: bash scripts/dev.sh"
