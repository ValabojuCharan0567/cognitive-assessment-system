#!/bin/sh
set -e

cd /app/backend
exec gunicorn api.app:app --bind "0.0.0.0:${PORT:-8000}"
