from __future__ import annotations

import base64
import json

from flask import Blueprint, jsonify, request
import logging

from feature_pipeline import AudioValidationError, analyze_audio_payload, analyze_behavioral_payload, extract_eeg_payload

logger = logging.getLogger(__name__)
if not logger.handlers:
    handler = logging.StreamHandler()
    formatter = logging.Formatter("%(asctime)s [%(levelname)s] %(name)s: %(message)s")
    handler.setFormatter(formatter)
    logger.addHandler(handler)
logger.setLevel(logging.DEBUG)

features_bp = Blueprint("features", __name__, url_prefix="/api/features")


def _get_request_data() -> dict:
    data = request.get_json(silent=True)
    if isinstance(data, dict):
        return data
    return request.form.to_dict(flat=True)


def _coerce_optional_dict(value):
    if isinstance(value, dict):
        return value
    if isinstance(value, str) and value.strip():
        try:
            parsed = json.loads(value)
        except json.JSONDecodeError:
            return None
        if isinstance(parsed, dict):
            return parsed
    return None


def _extract_audio_input(data: dict) -> tuple[str | None, str]:
    audio_b64 = data.get("audio_base64")
    audio_ext = (data.get("audio_ext") or "").strip().lower()

    uploaded = request.files.get("audio")
    if not audio_b64 and uploaded is not None:
        raw = uploaded.read()
        if raw:
            audio_b64 = base64.b64encode(raw).decode("ascii")
        if not audio_ext:
            filename = (uploaded.filename or "").strip()
            if "." in filename:
                audio_ext = filename.rsplit(".", 1)[-1].lower()

    return audio_b64, audio_ext


@features_bp.route("/audio/analyze", methods=["POST"])
def features_audio_analyze():
    request_id = (request.headers.get("X-Request-ID") or "unknown").strip() or "unknown"
    data = _get_request_data()
    audio_b64, audio_ext = _extract_audio_input(data)
    device_preprocessing = _coerce_optional_dict(data.get("device_preprocessing"))
    logger.debug("features_audio_analyze request_id=%s audio_ext=%s device_preprocessing=%s", request_id, audio_ext, device_preprocessing)

    if not audio_b64 or not audio_b64.strip():
        return jsonify({"error": "audio_base64 required and cannot be empty"}), 400

    try:
        logger.debug("REQ %s Audio request received ext=%s", request_id, audio_ext or 'unknown')
        result = analyze_audio_payload(audio_b64, audio_ext)
        if isinstance(device_preprocessing, dict):
            result["device_preprocessing"] = device_preprocessing
        result["request_id"] = request_id
        logger.debug("REQ %s Audio request completed", request_id)
        return jsonify(result)
    except AudioValidationError as exc:
        message = str(exc)
        silence_flag = bool(getattr(exc, "silence_detected", False))
        print(f"[REQ {request_id}] Audio validation failed: {message}", flush=True)
        return jsonify(
            {
                "error": message,
                "valid": False,
                "silence_detected": silence_flag,
                "request_id": request_id,
            }
        ), 400
    except Exception as exc:
        print(f"[REQ {request_id}] Audio request failed: {exc}", flush=True)
        return jsonify({"error": f"audio analysis failed: {exc}"}), 500


@features_bp.route("/behavioral/analyze", methods=["POST"])
def features_behavioral_analyze():
    data = _get_request_data()
    payload = data.get("behavioral") if isinstance(data.get("behavioral"), dict) else data

    try:
        result = analyze_behavioral_payload(payload)
        return jsonify(result)
    except Exception as exc:
        return jsonify({"error": f"behavioral analysis failed: {exc}"}), 400


@features_bp.route("/eeg/extract", methods=["POST"])
def features_eeg_extract():
    data = _get_request_data()
    eeg_b64 = data.get("eeg_base64")
    eeg_ext = str(data.get("eeg_ext", "csv")).strip().lower()
    device_preprocessing = _coerce_optional_dict(data.get("device_preprocessing"))

    if not eeg_b64 or not eeg_b64.strip():
        return jsonify({"error": "eeg_base64 required and cannot be empty"}), 400

    try:
        result = extract_eeg_payload(eeg_b64, eeg_ext)
        if isinstance(device_preprocessing, dict):
            result["device_preprocessing"] = device_preprocessing
        return jsonify(result)
    except Exception as exc:
        return jsonify({"error": f"EEG feature extraction failed: {exc}"}), 500


__all__ = ["features_bp"]
