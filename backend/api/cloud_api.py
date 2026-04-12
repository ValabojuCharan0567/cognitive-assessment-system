from __future__ import annotations

import os
from pathlib import Path
from datetime import datetime, timezone

from flask import Blueprint, jsonify

from config import DEMO_MODE
from database import get_db
from model_loader import get_audio_model_bundle, get_eeg_model_bundle

cloud_bp = Blueprint("cloud", __name__, url_prefix="/api/cloud")


@cloud_bp.route("/health", methods=["GET"])
def cloud_health():
    require_https = os.getenv("REQUIRE_HTTPS_UPLOADS", "1").strip().lower() in {
        "1",
        "true",
        "yes",
    }
    return jsonify(
        {
            "status": "ok",
            "service": "cloud-processing",
            "mode": "demo" if DEMO_MODE else "full",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "secure_upload_required": require_https,
        }
    )


@cloud_bp.route("/ready", methods=["GET"])
def cloud_ready():
    if DEMO_MODE:
        return jsonify(
            {
                "status": "ready",
                "mode": "demo",
                "dataset_exists": False,
                "dataset_path": str(Path(os.getenv("DATASET_PATH", "/data/dataset"))),
                "timestamp": datetime.now(timezone.utc).isoformat(),
            }
        )

    dataset_path = Path(os.getenv("DATASET_PATH", "/data/dataset"))
    checks = {
        "dataset_path": str(dataset_path),
        "dataset_exists": dataset_path.exists(),
        "mode": "full",
        "audio_model_loaded": False,
        "eeg_model_loaded": False,
        "database_ok": False,
    }

    status_code = 200

    try:
        get_audio_model_bundle()
        checks["audio_model_loaded"] = True
    except Exception as exc:
        checks["audio_model_error"] = str(exc)
        status_code = 503

    try:
        get_eeg_model_bundle()
        checks["eeg_model_loaded"] = True
    except Exception as exc:
        checks["eeg_model_error"] = str(exc)
        status_code = 503

    try:
        with get_db() as conn:
            conn.execute("SELECT 1")
        checks["database_ok"] = True
    except Exception as exc:
        checks["database_error"] = str(exc)
        status_code = 503

    if not checks["dataset_exists"]:
        status_code = 503

    checks["status"] = "ready" if status_code == 200 else "not_ready"
    checks["timestamp"] = datetime.now(timezone.utc).isoformat()
    return jsonify(checks), status_code


@cloud_bp.route("/pipeline", methods=["GET"])
def cloud_pipeline():
    return jsonify(
        {
            "name": "Cloud Processing Pipeline",
            "stages": [
                {
                    "id": "ingest",
                    "description": "Receives secure EEG/audio payloads from mobile clients.",
                },
                {
                    "id": "feature_extraction",
                    "description": "Extracts modality features via /api/features namespace.",
                    "routes": [
                        "/api/features/eeg/extract",
                        "/api/features/audio/analyze",
                    ],
                },
                {
                    "id": "analytics",
                    "description": "Computes domain scores and cognitive score.",
                    "route": "/api/assessment/submit",
                },
                {
                    "id": "reporting",
                    "description": "Publishes longitudinal and research-grade reports.",
                    "routes": [
                        "/api/reports/model_evaluation",
                        "/api/reports/assessment_comparison/<child_id>",
                        "/api/reports/longitudinal_progress/<child_id>",
                        "/api/reports/feature_importance",
                    ],
                },
            ],
        }
    )


@cloud_bp.route("/stats", methods=["GET"])
def cloud_stats():
    with get_db() as conn:
        cur = conn.cursor()
        cur.execute("SELECT COUNT(*) AS n FROM children")
        children = int(cur.fetchone()["n"])

        cur.execute("SELECT COUNT(*) AS n FROM assessments")
        assessments = int(cur.fetchone()["n"])

        cur.execute("SELECT COUNT(*) AS n FROM reports")
        reports = int(cur.fetchone()["n"])

    return jsonify(
        {
            "children": children,
            "assessments": assessments,
            "reports": reports,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
    )


__all__ = ["cloud_bp"]
