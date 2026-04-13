"""Gunicorn settings for container and cloud deployments."""

from __future__ import annotations

import os


bind = f"0.0.0.0:{os.getenv('PORT', '8000')}"
workers = int(os.getenv("GUNICORN_WORKERS", "2"))
threads = int(os.getenv("GUNICORN_THREADS", "2"))
# Cloud ML routes (e.g. audio) can exceed 120s on cold start / small instances.
timeout = int(os.getenv("GUNICORN_TIMEOUT", "300"))
graceful_timeout = int(os.getenv("GUNICORN_GRACEFUL_TIMEOUT", "30"))
keepalive = int(os.getenv("GUNICORN_KEEPALIVE", "5"))
loglevel = os.getenv("GUNICORN_LOG_LEVEL", "info")
accesslog = "-"
errorlog = "-"
preload_app = os.getenv("GUNICORN_PRELOAD", "1").strip().lower() in {
    "1",
    "true",
    "yes",
}
