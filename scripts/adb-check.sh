#!/bin/bash
# Helper script to diagnose and fix ADB connection issues

ADB="/Users/charanvalaboju/Library/Android/sdk/platform-tools/adb"

echo "=== ADB Diagnostic Check ==="

# Check if ADB exists
if [[ ! -f "$ADB" ]]; then
  echo "ERROR: ADB not found at $ADB"
  exit 1
fi

echo "1. ADB Version:"
"$ADB" version

echo ""
echo "2. Killing ADB server..."
"$ADB" kill-server

sleep 2

echo "3. Starting ADB server..."
"$ADB" start-server

sleep 2

echo "4. Connected devices:"
"$ADB" devices

echo ""
echo "5. Checking for emulator connection..."
if "$ADB" devices 2>/dev/null | grep -q "emulator.*device"; then
  echo "✓ Emulator connected and ready"
  "$ADB" shell getprop ro.serialno
else
  echo "✗ No emulator device found"
  echo "  Make sure the emulator is fully booted"
  echo "  Try: flutter emulators --launch Medium_Phone_API_36.0"
fi
