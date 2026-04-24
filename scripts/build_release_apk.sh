#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -f "$ROOT_DIR/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.env"
  set +a
fi

API_URL="${API_BASE_URL:-}"
GOOGLE_SERVER_CLIENT_ID="${GOOGLE_SERVER_CLIENT_ID:-}"

usage() {
  cat <<'EOF'
Usage: ./scripts/build_release_apk.sh [--api-url URL] [--google-server-client-id ID]

Build the Flutter release APK with required compile-time defines for this repo.

Required values:
  --api-url                 Full API base URL, e.g. https://your-host/api
  --google-server-client-id Google server client ID for Android sign-in

The script also reads values from .env if present.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --api-url)
      API_URL="$2"
      shift 2
      ;;
    --google-server-client-id)
      GOOGLE_SERVER_CLIENT_ID="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$API_URL" ]]; then
  echo 'ERROR: API_BASE_URL is not set. Use --api-url or set API_BASE_URL in .env.'
  exit 1
fi

if [[ -z "$GOOGLE_SERVER_CLIENT_ID" ]]; then
  echo 'ERROR: GOOGLE_SERVER_CLIENT_ID is not set. Use --google-server-client-id or set GOOGLE_SERVER_CLIENT_ID in .env.'
  exit 1
fi

echo "Building release APK with API_BASE_URL=$API_URL"
echo "Building release APK with GOOGLE_SERVER_CLIENT_ID=$GOOGLE_SERVER_CLIENT_ID"

cd "$ROOT_DIR/app"
flutter build apk --release \
  --dart-define=API_BASE_URL="$API_URL" \
  --dart-define=GOOGLE_SERVER_CLIENT_ID="$GOOGLE_SERVER_CLIENT_ID"
