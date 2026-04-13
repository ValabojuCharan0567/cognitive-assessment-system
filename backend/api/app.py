"""Flask API for Child Cognitive Assessment System with SQLite persistence."""

from __future__ import annotations

import base64
import csv
import io
import ipaddress
import json
import os
import signal
import ssl
import sys
import math
import statistics
import traceback
from urllib import request as urllib_request
from urllib import error as urllib_error
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any, Dict, List

# Load repo-root `.env` before `config` reads os.environ (local dev / Docker env_file).
_repo_root = Path(__file__).resolve().parents[2]
try:
    from dotenv import load_dotenv

    load_dotenv(_repo_root / ".env")
    load_dotenv(_repo_root / "infra" / ".env", override=False)
except ImportError:
    pass

from flask import Flask, jsonify, request
import certifi
import requests
from config import DEMO_MODE, validate_dataset
from database import get_db, init_db
from ml_models import HybridAnalyticsEngine
from model_loader import warmup_models
from feature_pipeline import AudioValidationError, analyze_audio_payload, analyze_behavioral_payload, extract_eeg_payload, extract_eeg_payload_bytes
from feature_api import features_bp
from cloud_api import cloud_bp
from reports_api import reports_bp
from flask_cors import CORS
try:
    from google.oauth2 import id_token as google_id_token
    from google.auth.transport import requests as google_requests
except Exception:
    google_id_token = None
    google_requests = None
try:
    from eeg_reference import effort_reference_analysis
except Exception:
    effort_reference_analysis = None

app = Flask(__name__)
# Local dev: be permissive for Flutter Web requests across origins/ports.
# This prevents browser "Failed to fetch" when preflight header sets differ.
CORS(
    app,
    resources={r"/api/*": {"origins": "*"}},
    allow_headers="*",
    methods=["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"],
)
engine = HybridAnalyticsEngine()

app.register_blueprint(features_bp)
app.register_blueprint(cloud_bp)
app.register_blueprint(reports_bp)

_SSL_CONTEXT = ssl.create_default_context(cafile=certifi.where())


def _should_run_startup_init() -> bool:
    """Run startup init in normal processes and Werkzeug's reloader child only."""
    reloader_state = os.environ.get("WERKZEUG_RUN_MAIN")
    return reloader_state in {None, "true"}


def _initialize_runtime() -> None:
    if DEMO_MODE:
        print("[INIT] Running in DEMO MODE (dataset not found)", flush=True)
    print("[INIT] Starting database and model initialization...", flush=True)
    init_db()
    print("[INIT] Database and models ready", flush=True)


def _shutdown_handler(signum: int, _frame: Any) -> None:
    print(f"[SHUTDOWN] Received signal {signum}; exiting gracefully.", flush=True)
    sys.exit(0)


if DEMO_MODE:
    print("[INIT] Dataset not found; starting in DEMO MODE", flush=True)
else:
    validate_dataset(
        required_dirs=["speech_data"],
        required_any_of=["EEG", "EEG SIGNAL DATA"],
    )
print("Warming up models...", flush=True)
warmup_models()
print("Models ready", flush=True)
if _should_run_startup_init():
    _initialize_runtime()
    signal.signal(signal.SIGTERM, _shutdown_handler)
    signal.signal(signal.SIGINT, _shutdown_handler)


def _is_local_request() -> bool:
    remote = (request.remote_addr or "").strip()
    return remote in {"127.0.0.1", "::1", "localhost"}


def _is_private_lan_client() -> bool:
    """When ALLOW_HTTP_PRIVATE_LAN=1, treat RFC1918/CGNAT clients like local dev (HTTP OK).

    Physical phones reach the dev laptop over Wi‑Fi with a 192.168.x.x address, so they
    are not loopback; this avoids forcing TLS on plain HTTP during local testing.
    """
    if os.getenv("ALLOW_HTTP_PRIVATE_LAN", "0").strip().lower() not in {
        "1",
        "true",
        "yes",
    }:
        return False
    remote = (request.remote_addr or "").strip()
    if not remote:
        return False
    host = remote.split("%", 1)[0].strip("[]")
    try:
        return bool(ipaddress.ip_address(host).is_private)
    except ValueError:
        return False


def _is_https_request() -> bool:
    if request.is_secure:
        return True
    forwarded_proto = request.headers.get("X-Forwarded-Proto", "")
    return forwarded_proto.lower() == "https"


def _get_request_data() -> dict:
    data = request.get_json(silent=True)
    if isinstance(data, dict):
        return data
    return request.form.to_dict(flat=True)


def _coerce_optional_dict(value: Any) -> dict[str, Any] | None:
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
            suffix = Path(uploaded.filename or "").suffix.lstrip(".").lower()
            audio_ext = suffix

    return audio_b64, audio_ext


def _extract_eeg_input(data: dict) -> tuple[str | None, bytes | None, str]:
    """Return (eeg_base64, eeg_bytes, eeg_ext). Supports JSON base64 and multipart file upload."""
    eeg_b64 = data.get("eeg_base64")
    eeg_ext = str(data.get("eeg_ext") or "csv").strip().lower()

    uploaded = request.files.get("eeg")
    if (not eeg_b64 or not str(eeg_b64).strip()) and uploaded is not None:
        raw = uploaded.read()
        if raw:
            suffix = Path(uploaded.filename or "").suffix.lstrip(".").lower()
            if suffix:
                eeg_ext = suffix
            return None, raw, eeg_ext

    if eeg_b64 and str(eeg_b64).strip():
        return str(eeg_b64), None, eeg_ext

    return None, None, eeg_ext


# Paths that never carry multimodal uploads; allow HTTP for phone/emulator dev.
_HTTPS_UPLOAD_EXEMPT_PREFIXES: tuple[str, ...] = (
    "/api/cloud/health",
    "/api/cloud/ready",
    "/api/login",  # includes /api/login/google
)


def _is_https_upload_exempt_path(path: str) -> bool:
    return any(path == p or path.startswith(p + "/") for p in _HTTPS_UPLOAD_EXEMPT_PREFIXES)


@app.before_request
def enforce_https_uploads() -> Any:
    require_https = os.getenv("REQUIRE_HTTPS_UPLOADS", "1").strip().lower() in {
        "1",
        "true",
        "yes",
    }
    if not require_https:
        return None

    if _is_https_upload_exempt_path(request.path):
        return None

    if _is_local_request():
        return None

    if _is_private_lan_client():
        return None

    if not _is_https_request():
        return jsonify({"error": "HTTPS is required for secure upload."}), 426

    return None


# Game library for report recommendations.
# The report still recommends only 2-3 games per weak section, but it now
# chooses from a library of 100+ activities.
GAME_LIBRARY = {
    "memory": [
        "Memory Card Match",
        "Sequence Recall",
        "Number Pattern Game",
        "Card Matching Game",
        "Sequence Memory Game",
        "Location Memory Game",
        "Picture Pair Recall",
        "Animal Memory Tiles",
        "Sound Sequence Recall",
        "Color Flash Recall",
        "Object Position Memory",
        "Story Order Recall",
        "Pattern Copy Challenge",
        "Treasure Chest Recall",
        "Shape Memory Quest",
        "Daily Items Recall",
        "Emoji Sequence Recall",
        "Mirror Pattern Memory",
        "Musical Notes Recall",
        "Quick Glance Memory",
        "Hidden Pair Explorer",
        "Number Span Builder",
        "Route Recall Puzzle",
        "Classroom Object Recall",
        "Color Sequence Builder",
        "Flashlight Memory Hunt",
        "Word Chain Memory",
        "Picture Grid Recall",
        "Sequence Tap Challenge",
        "Memory Maze Recall",
        "Farm Friends Recall",
        "Planet Pattern Recall",
        "Treasure Map Memory",
        "Shape Stack Recall",
        "Everyday List Recall",
        "Visual Route Recall",
    ],
    "attention": [
        "Object Search Game",
        "Focus Tracking",
        "Color Target Game",
        "Visual Search Game",
        "Odd-One-Out Puzzle",
        "Go / No-Go Game",
        "Spot the Difference Sprint",
        "Target Tap Challenge",
        "Shape Sorting Focus",
        "Color Switch Watch",
        "Attention Spotlight",
        "Distractor Dodge",
        "Rapid Symbol Scan",
        "Focus Beam Trainer",
        "Find the Hidden Star",
        "Selective Attention Quest",
        "Traffic Signal Focus",
        "Pattern Watch Patrol",
        "Fast Match Finder",
        "Reaction Arrow Tap",
        "Concentration Grid",
        "Track the Ball",
        "Eyes on Target",
        "Focus Ladder",
        "Impulse Control Tap",
        "Signal Stop Challenge",
        "Attention Burst Trainer",
        "Quick Choice Game",
        "Symbol Sweep",
        "Visual Alert Race",
        "Target Trail Challenge",
        "Focus and Freeze",
        "Searchlight Explorer",
        "Attention Switch Game",
        "Clue Catcher",
        "Precision Tap Quest",
    ],
    "language": [
        "Vocabulary Builder",
        "Story Completion",
        "Word Match Game",
        "Word–Picture Matching",
        "Listening Comprehension Game",
        "Sentence Understanding Game",
        "Rhyme Finder",
        "Synonym Match",
        "Picture Naming Quest",
        "Sentence Builder",
        "Story Sequence Talk",
        "Listening Clue Hunt",
        "Verb Action Match",
        "Category Sorting Words",
        "Alphabet Sound Match",
        "Word Family Builder",
        "Comprehension Checkpoint",
        "Describe the Scene",
        "Question and Answer Quest",
        "Phrase Builder",
        "Vocabulary Ladder",
        "Word Meaning Match",
        "Picture Story Talk",
        "Grammar Garden",
        "Sound and Syllable Tap",
        "Listening Directions Game",
        "Conversation Starter Cards",
        "Story Retell Builder",
        "Topic Word Hunt",
        "Sentence Repair Challenge",
        "Language Clue Puzzle",
        "Reading Buddy Match",
        "Word Puzzle Sprint",
        "Meaning Maker",
        "Listening Link-Up",
        "Communication Quest",
    ],
}

MEMORY_GAMES = GAME_LIBRARY["memory"]
ATTENTION_GAMES = GAME_LIBRARY["attention"]
LANGUAGE_GAMES = GAME_LIBRARY["language"]
TOTAL_GAME_CATALOG_SIZE = sum(len(pool) for pool in GAME_LIBRARY.values())


def _normalize_email(s) -> str:
    return (s or "").strip().lower()


def _google_userinfo_from_access_token(access_token: str) -> Dict[str, Any]:
    req = urllib_request.Request(
        "https://www.googleapis.com/oauth2/v3/userinfo",
        headers={"Authorization": f"Bearer {access_token}"},
    )
    with urllib_request.urlopen(req, timeout=10, context=_SSL_CONTEXT) as resp:
        raw = resp.read().decode("utf-8")
    return json.loads(raw)


def _upsert_google_user(email: str, name: str | None) -> None:
    with get_db() as conn:
        cur = conn.cursor()
        cur.execute("SELECT id, email_verified FROM users WHERE email = ?", (email,))
        row = cur.fetchone()
        if row:
            if int(row["email_verified"] or 0) != 1:
                cur.execute(
                    "UPDATE users SET email_verified = 1, verification_code = NULL WHERE id = ?",
                    (row["id"],),
                )
            return

        cur.execute(
            """INSERT INTO users
               (name, email, password, email_verified, verification_code, verification_sent_at)
               VALUES (?, ?, ?, 1, NULL, NULL)""",
            (name or email, email, None),
        )


def _get_child_accounts_for_parent(email: str) -> List[Dict[str, Any]]:
    with get_db() as conn:
        cur = conn.cursor()
        cur.execute(
            """SELECT c.id, c.name, c.age, c.gender, c.difficulty_level, c.dob, u.email
               FROM children c
               JOIN users u ON c.user_id = u.id
               WHERE u.email = ?""",
            (email,),
        )
        rows = cur.fetchall()

    return [
        {
            "id": str(row["id"]),
            "name": row["name"],
            "age": row["age"],
            "gender": row["gender"],
            "parent_email": row["email"],
            "difficulty_level": row["difficulty_level"] or 1,
            "dob": row["dob"],
        }
        for row in rows
    ]


# NOTE: legacy duplicate EEG parsing and score-composition helpers were removed
# from `app.py`. The demo now uses a single source of truth in
# `feature_pipeline.py` (feature extraction) and `ml_models.py` (EEG inference)
# to avoid old/unused EEG logic drifting out of sync.


def detect_weak_areas(
    memory: float,
    attention: float,
    language: float,
    *,
    threshold: float = 70.0,
) -> List[Dict[str, Any]]:
    """Identify weaker domains that should receive targeted game practice."""
    domains = [
        ("memory", float(memory)),
        ("attention", float(attention)),
        ("language", float(language)),
    ]
    weak_areas = []
    for name, score in domains:
        if score < threshold:
            weak_areas.append(
                {
                    "domain": name,
                    "score": round(score, 1),
                    "severity": "high" if score < 55 else "moderate",
                }
            )
    weak_areas.sort(key=lambda item: item["score"])
    return weak_areas



def generate_recommendations(
    memory: float, attention: float, language: float
) -> Dict[str, List[str]]:
    """Return 2-3 games per weak category, with a fallback to the two lowest areas."""
    import random

    recs: Dict[str, List[str]] = {}
    weak_areas = detect_weak_areas(memory, attention, language)

    def pick(pool: List[str], score: float) -> List[str]:
        count = 3 if score < 55 else 2
        count = min(count, len(pool))
        return random.sample(pool, count)

    for item in weak_areas:
        skill = str(item["domain"])
        score = float(item["score"])
        if skill == "memory":
            recs[skill] = pick(MEMORY_GAMES, score)
        elif skill == "attention":
            recs[skill] = pick(ATTENTION_GAMES, score)
        elif skill == "language":
            recs[skill] = pick(LANGUAGE_GAMES, score)

    if not recs:
        ranked = [
            ("memory", memory, MEMORY_GAMES),
            ("attention", attention, ATTENTION_GAMES),
            ("language", language, LANGUAGE_GAMES),
        ]
        ranked.sort(key=lambda item: item[1])
        for skill, score, pool in ranked[:2]:
            recs[skill] = pick(pool, score)

    return recs


def build_report_json(
    memory_score: float,
    attention_score: float,
    language_score: float,
    eeg_score: float,
    audio_score: float,
    cognitive_score: float,
    recs: Dict[str, List[str]],
    summary: str,
    behavioral: Dict[str, Any] | None = None,
    audio_meta: Dict[str, Any] | None = None,
    eeg_meta: Dict[str, Any] | None = None,
) -> Dict[str, Any]:
    """Build the report structure for storage and display."""
    strengths = []
    weakness = []
    if memory_score >= 70:
        strengths.append("Memory")
    else:
        weakness.append("Memory")
    if attention_score >= 70:
        strengths.append("Attention")
    else:
        weakness.append("Attention")
    if language_score >= 70:
        strengths.append("Language")
    else:
        weakness.append("Language")
    weak_areas = detect_weak_areas(memory_score, attention_score, language_score)
    weak_area_names = {item["domain"] for item in weak_areas}

    report = {
        "memory_score": round(memory_score, 1),
        "attention_score": round(attention_score, 1),
        "language_score": round(language_score, 1),
        "eeg_score": round(eeg_score, 4),
        "audio_score": round(audio_score, 1),
        "cognitive_score": cognitive_score,
        "strengths": strengths,
        "weakness": weakness,
        "weak_areas_detected": weak_areas,
        "summary": summary,
        "game_library_total": TOTAL_GAME_CATALOG_SIZE,
        "recommendation_note": "The app keeps a library of 100+ training games and recommends 2-3 focused activities for each weak category in Memory, Attention, and Language.",
        "recommendation_logic": {
            "weak_area_threshold": 70,
            "recommended_games_per_category": "2-3",
            "rule": "3 games if score < 55, otherwise 2 games when score < 70.",
            "fallback": "If no weak category is detected, recommend the two lowest-scoring categories.",
        },
        "recommendations": [
            {
                "domain": skill,
                "title": f"{skill.title()} Training Plan",
                "description": (
                    f"Recommended {len(games)} {skill.lower()} games from a larger library "
                    f"of {len(GAME_LIBRARY.get(skill, []))} activities."
                ),
                "games": games,
                "catalog_size": len(GAME_LIBRARY.get(skill, [])),
                "recommended_count": len(games),
                "weak_area_detected": skill in weak_area_names,
                "selection_logic": "3 games if score < 55 else 2 games if score < 70.",
            }
            for skill, games in recs.items()
        ],
    }
    if behavioral:
        report["behavioral"] = behavioral
    if audio_meta:
        report["audio"] = audio_meta
    if eeg_meta:
        report["eeg"] = eeg_meta
    return report


def _score_band(value: float) -> str:
    if value >= 80:
        return "well above the expected range for their age"
    if value >= 65:
        return "within the expected range for their age"
    if value >= 50:
        return "a little below the expected range and may need some extra support"
    return "below the expected range and would benefit from closer monitoring and structured support"


def build_clinical_summary(
    memory: float,
    attention: float,
    language: float,
    behavioral: Dict[str, Any],
    eeg: Dict[str, Any],
    audio: Dict[str, Any],
) -> str:
    """Generate parent-friendly narrative summary."""
    mem_band = _score_band(memory)
    att_band = _score_band(attention)
    lang_band = _score_band(language)

    # Prefer effort/load_level computed during EEG feature extraction.
    # This prevents rare cases where a second-pass ML inference can collapse.
    effort_val = eeg.get("effort")
    if isinstance(effort_val, (int, float)):
        effort = float(effort_val)
        load_level = str(eeg.get("load_level") or "Medium").lower()
    else:
        # Compute normalized effort from power bands (log-normalized for stability)
        import math
        alpha = float(eeg.get("alpha_power_mean") or 1e-10)
        beta = float(eeg.get("beta_power_mean") or 1e-10)
        theta = float(eeg.get("theta_power_mean") or 1e-10)
        
        # Log-domain normalization to avoid numerical instability.
        log_ratio = math.log(beta + 1e-10) - math.log(alpha + 1e-10)
        effort = 1.0 / (1.0 + math.exp(-log_ratio))  # Sigmoid normalization

        # Keep EEG effort on the requested 0-1 range.
        effort = max(0.0, min(effort, 1.0))

        # Derive load level from normalized effort.
        if effort < 0.35:
            load_level = "low"
        elif effort < 0.75:
            load_level = "medium"
        else:
            load_level = "high"
    
    # Compute frontal asymmetry index if not present.
    fai = float(eeg.get("frontal_asymmetry_index") or 0.0)
    if abs(fai) < 1e-6:
        alpha = float(eeg.get("alpha_power_mean") or 1e-10)
        beta = float(eeg.get("beta_power_mean") or 1e-10)
        fai = math.log(beta + 1e-10) - math.log(alpha + 1e-10)
        fai = max(-1.0, min(fai, 1.0))

    effort_band = "high" if effort >= 0.75 else ("moderate" if effort >= 0.5 else "low")

    overall_acc = float(behavioral.get("accuracy_percent", 0.0))
    mean_rt = float(behavioral.get("mean_reaction_ms", 1200.0))
    rt_desc = "typical"
    if mean_rt <= 800:
        rt_desc = "faster than average"
    elif mean_rt >= 1600:
        rt_desc = "slower than average"

    flu_label = str(audio.get("fluency_label", "") or "").strip()
    fluency_sentence = ""
    if flu_label:
        if flu_label.lower() == "low":
            fluency_sentence = (
                "The speech-based tasks suggested that your child's verbal fluency was on the lower side "
                "during this short sample."
            )
        elif flu_label.lower() == "medium":
            fluency_sentence = (
                "The speech-based tasks suggested that your child's verbal fluency was in the typical range."
            )
        elif flu_label.lower() == "high":
            fluency_sentence = (
                "The speech-based tasks suggested that your child's verbal fluency was strong."
            )

    parts = [
        "This assessment analyzed your child's brain activity (EEG), speech patterns, and problem-solving skills to "
        "understand their cognitive strengths.",
        f"Memory: Score {memory:.0f}/100 - {mem_band}. "
        f"Attention & Focus: Score {attention:.0f}/100 - {att_band}. "
        f"Language & Communication: Score {language:.0f}/100 - {lang_band}.",
        f"Brain activity showed {effort_band} mental effort and {load_level} cognitive load.",
        f"During problem-solving tasks, your child got around {overall_acc:.0f}% correct with {rt_desc} reaction time.",
    ]
    if fluency_sentence:
        parts.append(fluency_sentence)
    parts.append(
        "Focus practice on areas that need improvement to build stronger skills."
    )
    return "\n\n".join(parts)


def can_take_post_test(initial_report_date: datetime) -> bool:
    """Post test allowed only after 14 days from initial assessment."""
    return datetime.utcnow() >= initial_report_date + timedelta(days=14)


def compare_reports(initial: Dict[str, float], post: Dict[str, float]) -> Dict[str, float]:
    """Return improvement (post - initial) per skill."""
    keys = ["memory_score", "attention_score", "language_score"]
    return {
        k.replace("_score", ""): round(post.get(k, 0) - initial.get(k, 0), 1)
        for k in keys
    }


def compute_adaptive_fusion(
    behavioral_score: float,
    eeg_score: float,
    audio_score: float,
    *,
    eeg_confidence: float = 1.0,
    audio_confidence: float = 1.0,
    effort: float = 0.5,
    difficulty_weight: float = 1.0,
) -> Dict[str, Any]:
    """Combine behavioral, EEG, and audio evidence into the final cognitive score."""
    behavioral_score = max(0.0, min(100.0, float(behavioral_score)))
    eeg_score = max(0.0, min(100.0, float(eeg_score)))
    audio_score = max(0.0, min(100.0, float(audio_score)))
    eeg_confidence = max(0.0, min(1.0, float(eeg_confidence)))
    audio_confidence = max(0.0, min(1.0, float(audio_confidence)))
    effort = max(0.0, min(1.0, float(effort)))
    difficulty_weight = max(0.5, min(2.0, float(difficulty_weight)))

    if behavioral_score < 40.0:
        mode = "low_performance"
        w_behav, w_eeg, w_audio = 0.6, 0.25, 0.15
    else:
        mode = "normal"
        w_behav, w_eeg, w_audio = 0.5, 0.3, 0.2

    cognitive_raw = (w_behav * behavioral_score) + (w_eeg * eeg_score) + (w_audio * audio_score)
    cognitive_score = max(0.0, min(100.0, round(cognitive_raw * difficulty_weight, 1)))

    # Cognitive efficiency rewards strong performance with balanced effort and
    # reliable supporting-signal confidence.
    effort_balance = 1.0 - min(1.0, abs(effort - 0.55) / 0.55)
    support_confidence = (0.6 * eeg_confidence) + (0.4 * audio_confidence)
    efficiency_multiplier = 0.55 + (0.25 * effort_balance) + (0.20 * support_confidence)
    cognitive_efficiency = max(0.0, min(100.0, behavioral_score * efficiency_multiplier))

    return {
        "mode": mode,
        "weights": {
            "behavioral": w_behav,
            "eeg": w_eeg,
            "audio": w_audio,
        },
        "formula": "Cognitive Score = B*Behavioral + E*EEG + A*Audio",
        "cognitive_raw": round(float(cognitive_raw), 1),
        "cognitive_score": float(cognitive_score),
        "cognitive_efficiency": float(cognitive_efficiency),
        "confidence_weighting": {
            "eeg_confidence": float(eeg_confidence),
            "audio_confidence": float(audio_confidence),
            "weighted_eeg_score": float(eeg_score),
            "weighted_audio_score": float(audio_score),
        },
    }


# ---------------------------------------------------------------------------
# API Routes
# ---------------------------------------------------------------------------

@app.route("/api/register", methods=["POST"])
def register():
    return (
        jsonify(
            {
                "error": "Email/password signup is disabled. Please continue with Google.",
                "provider": "google",
            }
        ),
        403,
    )


@app.route("/api/verify-email", methods=["POST"])
def verify_email():
    return (
        jsonify(
            {
                "error": "Email verification is not required. Please continue with Google.",
                "provider": "google",
            }
        ),
        403,
    )


@app.route("/api/login", methods=["POST"])
def login():
    return (
        jsonify(
            {
                "error": "Email/password login is disabled. Please continue with Google.",
                "provider": "google",
            }
        ),
        403,
    )


@app.route("/api/login/google", methods=["POST"])
def google_login():
    data = request.get_json(force=True)
    id_token_str = str(data.get("id_token") or "").strip()
    access_token = str(data.get("access_token") or "").strip()

    if not id_token_str and not access_token:
        return jsonify({"error": "id_token or access_token is required"}), 400

    email = ""
    name = None
    email_verified = False

    if id_token_str:
        if google_id_token is None or google_requests is None:
            return jsonify({"error": "Google token verification dependencies are not installed."}), 500
        try:
            audience = os.getenv("GOOGLE_OAUTH_CLIENT_ID", "").strip() or None
            google_session = requests.Session()
            google_session.verify = certifi.where()
            token_info = google_id_token.verify_oauth2_token(
                id_token_str,
                google_requests.Request(session=google_session),
                audience=audience,
            )
            issuer = str(token_info.get("iss") or "")
            if issuer not in {"accounts.google.com", "https://accounts.google.com"}:
                return jsonify({"error": "Invalid Google token issuer."}), 401
            email = _normalize_email(token_info.get("email"))
            name = token_info.get("name")
            email_verified = bool(token_info.get("email_verified"))
        except Exception as exc:
            return jsonify({"error": f"Invalid Google id_token: {exc}"}), 401

    if not email and access_token:
        try:
            info = _google_userinfo_from_access_token(access_token)
            email = _normalize_email(info.get("email"))
            name = info.get("name")
            email_verified = bool(info.get("email_verified"))
        except urllib_error.HTTPError as exc:
            return jsonify({"error": f"Invalid Google access_token: {exc.code}"}), 401
        except Exception as exc:
            return jsonify({"error": f"Failed to validate Google access_token: {exc}"}), 401

    if not email:
        return jsonify({"error": "Google account email is missing."}), 400
    if not email_verified:
        return jsonify({"error": "Google account email is not verified."}), 403

    _upsert_google_user(email, name)
    accounts = _get_child_accounts_for_parent(email)
    return jsonify(
        {
            "message": "login successful",
            "provider": "google",
            "accounts": accounts,
            "user": {"email": email, "name": name},
        }
    )


@app.route("/api/child", methods=["POST"])
def create_child():
    data = request.get_json(force=True)
    name = data.get("name")
    age = data.get("age")
    parent_email = _normalize_email(data.get("parent_email"))
    if not name or age is None or not parent_email:
        return jsonify({"error": "name, age and parent_email required"}), 400

    with get_db() as conn:
        cur = conn.cursor()
        cur.execute("SELECT id FROM users WHERE email = ?", (parent_email,))
        user_row = cur.fetchone()
        if not user_row:
            return jsonify({"error": "Parent account not found"}), 400
        user_id = user_row["id"]
        cur.execute(
            """INSERT INTO children (user_id, name, age, gender, grade, difficulty_level, dob)
               VALUES (?, ?, ?, ?, ?, ?, ?)""",
            (
                user_id,
                name,
                age,
                data.get("gender"),
                data.get("grade"),
                data.get("difficulty_level", 1),
                data.get("dob"),
            ),
        )
        child_id = cur.lastrowid

        cur.execute(
            "SELECT id, name, age, gender, grade, difficulty_level, dob FROM children WHERE id = ?",
            (child_id,),
        )
        row = cur.fetchone()

    profile = {
        "id": str(child_id),
        "name": row["name"],
        "age": row["age"],
        "gender": row["gender"],
        "dob": row["dob"],
        "parent_email": parent_email,
        "difficulty_level": row["difficulty_level"] or 1,
        "created_at": datetime.utcnow().isoformat(),
    }
    return jsonify(profile), 201


@app.route("/api/assessment/start", methods=["POST"])
def start_assessment():
    data = request.get_json(force=True)
    child_id_str = data.get("child_id")
    if not child_id_str:
        return jsonify({"error": "child_id required"}), 400

    try:
        child_id = int(child_id_str)
    except (ValueError, TypeError):
        return jsonify({"error": "child not found"}), 404

    asm_type = (data.get("type") or "initial").strip().lower()
    if asm_type not in {"initial", "post"}:
        return jsonify({"error": "type must be 'initial' or 'post'"}), 400

    pre_report_id_raw = data.get("pre_report_id")
    linked_pre_report_id = None
    if pre_report_id_raw not in (None, "", "null"):
        try:
            linked_pre_report_id = int(pre_report_id_raw)
        except (ValueError, TypeError):
            return jsonify({"error": "pre_report_id must be an integer"}), 400

    with get_db() as conn:
        cur = conn.cursor()
        cur.execute("SELECT id FROM children WHERE id = ?", (child_id,))
        child_record = cur.fetchone()

        # Auto-create test child if using ID 1 and it doesn't exist (development/testing)
        if not child_record and child_id == 1:
            cur.execute(
                """INSERT OR IGNORE INTO children
                   (id, name, age, gender, difficulty_level, dob)
                   VALUES (?, ?, ?, ?, ?, ?)""",
                (1, "Test Child", 8, "M", 1, None),
            )
            child_record = (1,)

        if not child_record:
            return jsonify({"error": "child not found"}), 404

        if asm_type == "post":
            if linked_pre_report_id is None:
                cur.execute(
                    """SELECT r.id FROM reports r
                       JOIN assessments a ON r.assessment_id = a.id
                       WHERE r.child_id = ? AND a.type = 'initial'
                       ORDER BY r.created_at DESC LIMIT 1""",
                    (child_id,),
                )
                latest_pre = cur.fetchone()
                if latest_pre:
                    linked_pre_report_id = int(latest_pre["id"])

            if linked_pre_report_id is None:
                return jsonify(
                    {"error": "A pre-assessment report is required before starting a post assessment."}
                ), 400

            cur.execute(
                """SELECT r.id FROM reports r
                   JOIN assessments a ON r.assessment_id = a.id
                   WHERE r.id = ? AND r.child_id = ? AND a.type = 'initial'
                   LIMIT 1""",
                (linked_pre_report_id, child_id),
            )
            pre_report_row = cur.fetchone()
            if not pre_report_row:
                return jsonify({"error": "Selected pre-assessment report was not found for this child."}), 404

            cur.execute(
                """SELECT r.id FROM reports r
                   JOIN assessments a ON r.assessment_id = a.id
                   WHERE r.child_id = ? AND a.type = 'post' AND a.linked_pre_report_id = ?
                   ORDER BY r.created_at DESC LIMIT 1""",
                (child_id, linked_pre_report_id),
            )
            existing_post = cur.fetchone()
            if existing_post:
                return jsonify(
                    {
                        "error": "A post assessment already exists for this saved report.",
                        "post_report_id": str(existing_post["id"]),
                    }
                ), 409

        cur.execute(
            """INSERT INTO assessments (child_id, type, status, linked_pre_report_id)
               VALUES (?, ?, 'in_progress', ?)""",
            (child_id, asm_type, linked_pre_report_id),
        )
        asm_id = cur.lastrowid

    return (
        jsonify(
            {
                "id": str(asm_id),
                "child_id": child_id_str,
                "status": "in_progress",
                "created_at": datetime.utcnow().isoformat(),
                "pre_report_id": str(linked_pre_report_id) if linked_pre_report_id is not None else "",
            }
        ),
        201,
    )


@app.route("/api/assessment/submit", methods=["POST"])
def submit_assessment():
    data = request.get_json(force=True)
    asm_id_str = data.get("assessment_id")
    if not asm_id_str:
        return jsonify({"error": "assessment_id required"}), 400

    try:
        asm_id = int(asm_id_str)
    except (ValueError, TypeError):
        return jsonify({"error": "assessment not found"}), 404

    behavioral = data.get("behavioral", {}) or {}
    eeg = data.get("eeg", {}) or {}
    audio = data.get("audio", {}) or {}


    required_eeg = [
        "delta_power_mean",
        "theta_power_mean",
        "alpha_power_mean",
        "beta_power_mean",
        "gamma_power_mean",
        "frontal_asymmetry_index",
        "mental_effort_score",
        "signal_entropy",
        "pupil_dilation_avg",
        "heart_rate_variability",
    ]
    missing_eeg = [k for k in required_eeg if k not in eeg or eeg.get(k) is None]
    if missing_eeg:
        return jsonify({"error": f"Missing EEG features: {missing_eeg}"}), 400

    if audio.get("silence_detected") or audio.get("valid") is False:
        return jsonify(
            {
                "error": audio.get("error")
                or "Invalid audio sample. Please record clear speech before continuing.",
            }
        ), 400

    if audio.get("fluency_score") is None:
        return jsonify({"error": "audio.fluency_score is required"}), 400

    required_behavioral = [
        "accuracy_percent",
        "mean_reaction_ms",
        "memory_accuracy",
        "attention_accuracy",
        "language_accuracy",
        "correct_count",
        "error_count",
        "total_trials",
    ]
    missing_behavioral = [
        k for k in required_behavioral if k not in behavioral or behavioral.get(k) is None
    ]
    if missing_behavioral:
        return jsonify({"error": f"Missing behavioral values: {missing_behavioral}"}), 400

    if int(behavioral.get("total_trials", 0)) <= 0:
        return jsonify({"error": "behavioral.total_trials must be > 0"}), 400

    # Load assessment + child metadata early (for difficulty adjustment).
    with get_db() as conn:
        cur = conn.cursor()
        cur.execute(
            """SELECT child_id, type, linked_pre_report_id FROM assessments
               WHERE id = ? AND status = 'in_progress'""",
            (asm_id,),
        )
        asm_row = cur.fetchone()
        if not asm_row:
            return jsonify({"error": "assessment not found"}), 404
        child_id = asm_row["child_id"]
        asm_type = asm_row["type"]
        linked_pre_report_id = asm_row["linked_pre_report_id"]

        cur.execute(
            "SELECT difficulty_level FROM children WHERE id = ?",
            (child_id,),
        )
        child_row = cur.fetchone()
        difficulty_level = int(child_row["difficulty_level"] or 1) if child_row else 1

    # Domain scores from ML engine
    from dataclasses import asdict
    scores_obj = engine.score_domains(
        behavioral=behavioral,
        eeg_features=eeg,
        audio_features=audio,
    )
    scores = asdict(scores_obj)
    memory = float(scores.get("memory", 0.0))
    attention = float(scores.get("attention", 0.0))
    language = float(scores.get("language", 0.0))

    # -----------------------------------------------------------------------
    # Adaptive scoring (research-style improvements)
    # -----------------------------------------------------------------------
    # 2) Behavioral scoring (requested formula)
    behavioral_result = analyze_behavioral_payload(
        behavioral,
        fallback_scores={
            "memory": memory,
            "attention": attention,
            "language": language,
        },
    )
    accuracy = float(behavioral_result["accuracy"])
    reaction_time = float(behavioral_result["reaction_time_ms"])
    rt_score = float(behavioral_result["rt_score"])
    consistency_score = float(behavioral_result["consistency_score"])
    consistency_bonus = float(behavioral_result["consistency_bonus"])
    consistency_variability = float(behavioral_result["consistency_variability"])
    behavioral_score = float(behavioral_result["behavioral_score"])

    # EEG score: always use the trained EEG model on the extracted features.
    eeg_result = engine.eeg_model.predict_load_and_effort(eeg)
    ml_effort = float(eeg_result.get("effort", 0.5))
    ml_load_level = eeg_result.get("load_level")

    # Trust categorical `load_level` coming from EEG extraction whenever present.
    load_level_raw = eeg.get("load_level") or eeg.get("cognitive_load_level") or ml_load_level
    load_level = ml_load_level
    if isinstance(load_level_raw, str):
        ll = load_level_raw.strip()
        lower = ll.lower()
        if lower == "low":
            load_level = "Low"
        elif lower == "medium":
            load_level = "Medium"
        elif lower == "high":
            load_level = "High"
        else:
            load_level = ll

    # For effort (numeric), prefer EEG extraction effort if provided.
    effort_val = eeg.get("effort")
    if isinstance(effort_val, (int, float)):
        effort = float(effort_val)
    elif isinstance(eeg.get("mental_effort_score"), (int, float)):
        effort = float(eeg.get("mental_effort_score"))
    else:
        effort = ml_effort

    # Optional: derive effort directly from band powers to avoid scale collapse.
    # Use a research-standard log-ratio and sigmoid normalisation:
    #   raw_ratio = log(beta/alpha) = log(beta) - log(alpha)
    #   derived_effort = sigmoid(raw_ratio) -> [0, 1]
    derived_effort = None
    try:
        alpha_p = float(eeg.get("alpha_power_mean", 0.0))
        beta_p = float(eeg.get("beta_power_mean", 0.0))
        if alpha_p > 0.0 and beta_p > 0.0:
            alpha_log = math.log(alpha_p + 1e-10)
            beta_log = math.log(beta_p + 1e-10)
            raw_ratio = beta_log - alpha_log
            derived_effort = 1.0 / (1.0 + math.exp(-raw_ratio))
    except Exception:
        derived_effort = None

    # Fuse derived effort with original effort for robustness.
    # If original effort collapses near zero, the derived effort should dominate.
    if derived_effort is not None:
        if effort <= 0.05:
            effort = (0.75 * derived_effort) + (0.25 * effort)
        else:
            effort = (0.60 * derived_effort) + (0.40 * effort)

    # EEG effort is expected to be in [0, 1].
    effort = max(0.0, min(1.0, effort))

    # If we still don't have a clean categorical load level, derive it from effort.
    if not load_level:
        if effort < 0.3:
            load_level = "Low"
        elif effort < 0.7:
            load_level = "Medium"
        else:
            load_level = "High"

    # 3) EEG non-linear scaling (optimal effort around ~0.6), with tunable sigma.
    sigma = 0.2
    eeg_score = 100.0 * math.exp(-((effort - 0.6) ** 2) / (2.0 * (sigma ** 2)))
    eeg_score = max(0.0, min(100.0, float(eeg_score)))

    # 2b) EEG confidence (down-weight noisy spectral estimates).
    # Use log-power stability to avoid tiny-value scale effects.
    eeg_confidence = 1.0
    try:
        alpha_p = float(eeg.get("alpha_power_mean", 0.0))
        beta_p = float(eeg.get("beta_power_mean", 0.0))
        gamma_p = float(eeg.get("gamma_power_mean", 0.0))
        if alpha_p > 0.0 and beta_p > 0.0 and gamma_p > 0.0:
            logs = [
                math.log(alpha_p + 1e-10),
                math.log(beta_p + 1e-10),
                math.log(gamma_p + 1e-10),
            ]
            s = float(statistics.pstdev(logs))
            eeg_confidence = 1.0 / (1.0 + s)
            eeg_confidence = max(0.0, min(1.0, eeg_confidence))
    except Exception:
        eeg_confidence = 1.0

    eeg_score = max(0.0, min(100.0, eeg_score * eeg_confidence))

    # 4) Audio confidence weighting (if available)
    audio_base = float(audio.get("fluency_score", 60.0))
    audio_conf = audio.get("confidence", 1.0)
    try:
        audio_conf = float(audio_conf)
    except Exception:
        audio_conf = 1.0
    audio_conf = max(0.0, min(1.0, audio_conf))
    audio_score = max(0.0, min(100.0, audio_base * audio_conf))

    # 6) Difficulty adjustment factor (1→1.0, 2→1.1, 3+→1.2)
    if difficulty_level <= 1:
        difficulty_weight = 1.0
    elif difficulty_level == 2:
        difficulty_weight = 1.1
    else:
        difficulty_weight = 1.2
    # Face / vision features are not used in scoring now.
    face_score = 0.0

    # 4b) Adaptive multimodal fusion.
    # Behavioral performance stays the anchor signal because it is the most
    # interpretable child-facing metric in the demo. EEG and audio then act as
    # confidence-weighted supporting modalities.
    fusion_result = compute_adaptive_fusion(
        behavioral_score,
        eeg_score,
        audio_score,
        eeg_confidence=eeg_confidence,
        audio_confidence=audio_conf,
        effort=effort,
        difficulty_weight=difficulty_weight,
    )
    w_behav = float(fusion_result["weights"]["behavioral"])
    w_eeg = float(fusion_result["weights"]["eeg"])
    w_audio = float(fusion_result["weights"]["audio"])
    cognitive_raw = float(fusion_result["cognitive_raw"])
    cognitive_score = float(fusion_result["cognitive_score"])
    cognitive_efficiency = float(fusion_result["cognitive_efficiency"])

    if cognitive_score >= 80:
        cognitive_level = "High Cognitive Performance"
    elif cognitive_score >= 50:
        cognitive_level = "Moderate Performance"
    else:
        cognitive_level = "Needs Improvement"

    recs = generate_recommendations(memory, attention, language)
    summary = build_clinical_summary(
        memory, attention, language, behavioral, eeg, audio
    )

    total_trials = int(behavioral.get("total_trials", 0))
    domain_total_base, domain_total_remainder = divmod(max(total_trials, 0), 3)
    default_domain_totals = {
        "memory": domain_total_base + (1 if domain_total_remainder > 0 else 0),
        "attention": domain_total_base + (1 if domain_total_remainder > 1 else 0),
        "language": domain_total_base,
    }

    def _resolve_domain_counts(domain: str, accuracy_key: str) -> tuple[int, int]:
        total_raw = behavioral.get(f"{domain}_total")
        correct_raw = behavioral.get(f"{domain}_correct")

        try:
            total_val = int(total_raw) if total_raw is not None else int(default_domain_totals[domain])
        except (TypeError, ValueError):
            total_val = int(default_domain_totals[domain])
        total_val = max(0, total_val)

        if correct_raw is not None:
            try:
                correct_val = int(correct_raw)
            except (TypeError, ValueError):
                correct_val = 0
        else:
            try:
                accuracy_val = float(behavioral.get(accuracy_key, 0.0))
            except (TypeError, ValueError):
                accuracy_val = 0.0
            accuracy_val = max(0.0, min(100.0, accuracy_val))
            correct_val = int(round((accuracy_val / 100.0) * total_val))

        correct_val = max(0, min(total_val, correct_val))
        return correct_val, total_val

    memory_correct, memory_total = _resolve_domain_counts("memory", "memory_accuracy")
    attention_correct, attention_total = _resolve_domain_counts("attention", "attention_accuracy")
    language_correct, language_total = _resolve_domain_counts("language", "language_accuracy")

    behavioral_payload = {
        "accuracy_percent": float(behavioral.get("accuracy_percent", 0.0)),
        "mean_reaction_ms": float(behavioral.get("mean_reaction_ms", 1200.0)),
        "correct_count": int(behavioral.get("correct_count", 0)),
        "error_count": int(behavioral.get("error_count", 0)),
        "total_trials": total_trials,
        "memory_accuracy": float(behavioral.get("memory_accuracy", 0.0)),
        "attention_accuracy": float(behavioral.get("attention_accuracy", 0.0)),
        "language_accuracy": float(behavioral.get("language_accuracy", 0.0)),
        "memory_correct": memory_correct,
        "memory_total": memory_total,
        "attention_correct": attention_correct,
        "attention_total": attention_total,
        "language_correct": language_correct,
        "language_total": language_total,
    }

    audio_payload = {
        "class": audio.get("class") or audio.get("fluency_label"),
        "class_id": audio.get("class_id", audio.get("fluency_class")),
        "fluency_class": audio.get("fluency_class"),
        "fluency_label": audio.get("fluency_label"),
        "fluency_score": audio.get("fluency_score", audio.get("score")),
        "confidence": audio.get("confidence"),
        "speech_ratio": audio.get("speech_ratio"),
        "low_confidence": bool(audio.get("low_confidence", False)),
    }

    report_data = build_report_json(
        memory,
        attention,
        language,
        eeg_score,
        audio_score,
        cognitive_score,
        recs,
        summary,
        behavioral=behavioral_payload,
        audio_meta=audio_payload,
        eeg_meta={
            "load_level": load_level,
            "effort": float(effort),
        },
    )

    saved_at = datetime.utcnow().isoformat()
    report_data["assessment_id"] = str(asm_id)
    report_data["report_type"] = "pre" if asm_type == "initial" else "post"
    report_data["created_at"] = saved_at
    report_data["linked_pre_report_id"] = (
        str(linked_pre_report_id) if linked_pre_report_id is not None else ""
    )

    # Flutter expects: scores (memory, attention, language), recs (list of {domain, title, description, games}), summary
    recs_for_flutter = report_data["recommendations"]

    with get_db() as conn:
        cur = conn.cursor()
        cur.execute(
            """UPDATE assessments SET
               status = 'completed', completed_at = ?,
               behavioral_score = ?, eeg_score = ?, audio_score = ?, face_score = ?,
               cognitive_score = ?, memory_score = ?, attention_score = ?, language_score = ?
               WHERE id = ?""",
            (
                datetime.utcnow().isoformat(),
                behavioral_score, eeg_score, audio_score, face_score,
                cognitive_score, memory, attention, language,
                asm_id,
            ),
        )

        cur.execute(
            """INSERT INTO reports (child_id, assessment_id, report_json, created_at)
               VALUES (?, ?, ?, ?)""",
            (child_id, asm_id, json.dumps(report_data), saved_at),
        )
        report_id = cur.lastrowid

        # Store recommendations
        for skill, games in recs.items():
            cur.execute(
                """INSERT INTO recommendations (child_id, skill, game1, game2, game3)
                   VALUES (?, ?, ?, ?, ?)""",
                (
                    child_id,
                    skill.title(),
                    games[0] if len(games) > 0 else None,
                    games[1] if len(games) > 1 else None,
                    games[2] if len(games) > 2 else None,
                ),
            )

    # Pre vs post comparison for post assessments
    trends = None
    deltas = None
    comparison = {}
    if asm_type == "post":
        with get_db() as conn:
            cur = conn.cursor()
            if linked_pre_report_id is not None:
                cur.execute(
                    """SELECT r.report_json FROM reports r
                       JOIN assessments a ON r.assessment_id = a.id
                       WHERE r.id = ? AND a.type = 'initial'
                       LIMIT 1""",
                    (linked_pre_report_id,),
                )
            else:
                cur.execute(
                    """SELECT r.report_json FROM reports r
                       JOIN assessments a ON r.assessment_id = a.id
                       WHERE a.child_id = ? AND a.type = 'initial' AND a.status = 'completed'
                       ORDER BY r.created_at DESC LIMIT 1""",
                    (child_id,),
                )
            pre_row = cur.fetchone()
        if pre_row:
            pre_data = json.loads(pre_row["report_json"])
            initial = {
                "memory_score": pre_data["memory_score"],
                "attention_score": pre_data["attention_score"],
                "language_score": pre_data["language_score"],
            }
            post_map = {
                "memory_score": memory,
                "attention_score": attention,
                "language_score": language,
            }
            deltas = compare_reports(initial, post_map)

            def label(delta: float) -> str:
                if delta > 3:
                    return "improved"
                if delta < -3:
                    return "declined"
                return "no_change"

            trends = {k.replace("_score", ""): label(v) for k, v in deltas.items()}

            average_change = round(
                sum(float(v) for v in deltas.values()) / max(len(deltas), 1),
                1,
            )
            if average_change > 3:
                comparison_summary = "Overall performance improved compared with the linked pre-test."
            elif average_change < -3:
                comparison_summary = "Overall performance declined compared with the linked pre-test."
            else:
                comparison_summary = "Overall performance remained broadly stable compared with the linked pre-test."

            comparison = {
                "available": True,
                "linked_pre_report_id": str(linked_pre_report_id) if linked_pre_report_id is not None else "",
                "average_change": average_change,
                "summary": comparison_summary,
                "domains": {
                    "memory": {
                        "pre": round(float(initial["memory_score"]), 1),
                        "post": round(float(memory), 1),
                        "delta": round(float(deltas.get("memory_score", 0)), 1),
                        "trend": trends.get("memory", "no_change"),
                    },
                    "attention": {
                        "pre": round(float(initial["attention_score"]), 1),
                        "post": round(float(attention), 1),
                        "delta": round(float(deltas.get("attention_score", 0)), 1),
                        "trend": trends.get("attention", "no_change"),
                    },
                    "language": {
                        "pre": round(float(initial["language_score"]), 1),
                        "post": round(float(language), 1),
                        "delta": round(float(deltas.get("language_score", 0)), 1),
                        "trend": trends.get("language", "no_change"),
                    },
                },
            }

    if deltas is not None:
        report_data["deltas"] = deltas
    if trends is not None:
        report_data["trends"] = trends
    if comparison:
        report_data["comparison"] = comparison

    with get_db() as conn:
        cur = conn.cursor()
        cur.execute(
            "UPDATE reports SET report_json = ? WHERE id = ?",
            (json.dumps(report_data), report_id),
        )

    # Reference EEG analysis depends on optional dataset folders.
    # If those files are missing, don't fail the whole submit request.
    eeg_reference = None
    if effort_reference_analysis is not None:
        try:
            eeg_reference = effort_reference_analysis(effort)
        except Exception:
            eeg_reference = None

    return jsonify(
        {
            "scores": {
                "memory": memory,
                "attention": attention,
                "language": language,
                "cognitive": cognitive_score,
                "overall_cognitive": cognitive_score,
            },
            "recommendations": recs_for_flutter,
            "summary": summary,
            "analysis": {
                "cognitive_score": cognitive_score,
                "cognitive_level": cognitive_level,
                "difficulty_level": difficulty_level,
                "difficulty_weight": round(float(difficulty_weight), 2),
                "fusion_mode": fusion_result["mode"],
                "fusion_formula": fusion_result["formula"],
                "fusion_weights": {
                    "behavioral": round(float(w_behav), 2),
                    "eeg": round(float(w_eeg), 2),
                    "audio": round(float(w_audio), 2),
                },
                "confidence_weighting": {
                    "eeg_confidence": round(float(fusion_result["confidence_weighting"]["eeg_confidence"]), 3),
                    "audio_confidence": round(float(fusion_result["confidence_weighting"]["audio_confidence"]), 3),
                    "weighted_eeg_score": round(float(fusion_result["confidence_weighting"]["weighted_eeg_score"]), 2),
                    "weighted_audio_score": round(float(fusion_result["confidence_weighting"]["weighted_audio_score"]), 2),
                },
                "cognitive_raw": round(float(cognitive_raw), 1),
                "cognitive_efficiency": round(float(cognitive_efficiency), 1),
                "behavioral_score": round(behavioral_score, 1),
                "behavioral_mean": round(behavioral_score, 1),
                "behavioral_formula": "0.5*accuracy + 0.3*rt_score + 0.2*consistency_score",
                "behavioral_accuracy": round(float(accuracy), 1),
                "behavioral_rt_score": round(float(rt_score), 1),
                "behavioral_consistency_score": round(float(consistency_score), 1),
                "behavioral_consistency_variance": round(float(consistency_variability), 1),
                "behavioral_consistency_bonus": round(float(consistency_bonus), 2),
                "behavioral_components": {
                    "accuracy": round(float(accuracy), 1),
                    "rt_score": round(float(rt_score), 1),
                    "consistency_score": round(float(consistency_score), 1),
                    "consistency_bonus": round(float(consistency_bonus), 2),
                },
                "behavioral_result": {
                    "accuracy": round(float(behavioral_result["accuracy"]), 1),
                    "rt_score": round(float(behavioral_result["rt_score"]), 1),
                    "consistency_bonus": round(float(behavioral_result["consistency_bonus"]), 2),
                    "behavioral_score": round(float(behavioral_result["behavioral_score"]), 1),
                    "formula": behavioral_result["formula"],
                },
                "behavioral_domains": {
                    "memory": round(memory, 1),
                    "attention": round(attention, 1),
                    "language": round(language, 1),
                },
                "eeg_score": round(eeg_score, 4),
                "audio_score": round(audio_score, 1),
                "eeg": {
                    "load_level": load_level,
                    "effort": effort,
                    "confidence": round(float(eeg_confidence), 3),
                },
                "eeg_reference": eeg_reference or {},
                "audio": audio_payload,
            },
            "behavioral": behavioral_payload,
            "report_id": str(report_id),
            "report_type": "pre" if asm_type == "initial" else "post",
            "assessment_type": asm_type,
            "created_at": saved_at,
            "report_saved": True,
            "comparison": comparison,
            "trends": trends or {},
            "deltas": deltas or {},
        }
    )


@app.route("/api/audio/analyze", methods=["POST"])
def audio_analyze():
    request_id = (request.headers.get("X-Request-ID") or "unknown").strip() or "unknown"
    data = _get_request_data()
    audio_b64, audio_ext = _extract_audio_input(data)
    device_preprocessing = _coerce_optional_dict(data.get("device_preprocessing"))
    child_id = str(data.get("child_id") or "").strip()
    if not audio_b64 or not audio_b64.strip():
        return jsonify({"error": "audio_base64 required and cannot be empty"}), 400

    try:
        result = analyze_audio_payload(audio_b64, audio_ext)
        if isinstance(device_preprocessing, dict):
            result["device_preprocessing"] = device_preprocessing
        result["request_id"] = request_id
        if child_id:
            result["child_id"] = child_id
        return jsonify(result)
    except AudioValidationError as exc:
        message = str(exc)
        return jsonify(
            {
                "error": message,
                "valid": False,
                "silence_detected": "no speech" in message.lower(),
                "request_id": request_id,
                **({"child_id": child_id} if child_id else {}),
            }
        ), 400
    except Exception as exc:
        print(
            f"[REQ {request_id}] audio analysis failed child_id={child_id}: {exc}\n"
            f"{traceback.format_exc()}",
            flush=True,
        )
        return jsonify(
            {
                "error": f"audio analysis failed: {exc}",
                "request_id": request_id,
                **({"child_id": child_id} if child_id else {}),
            }
        ), 500


@app.route("/api/eeg/analyze", methods=["POST"])
@app.route("/api/eeg/extract", methods=["POST"])
@app.route("/api/eeg/extract_features", methods=["POST"])
def eeg_extract_features():
    """Extract EEG features from uploaded CSV or EDF (base64)."""
    request_id = (request.headers.get("X-Request-ID") or "unknown").strip() or "unknown"
    data = _get_request_data()
    eeg_b64, eeg_bytes, eeg_ext = _extract_eeg_input(data)
    device_preprocessing = _coerce_optional_dict(data.get("device_preprocessing"))
    child_id = str(data.get("child_id") or "").strip()
    if (not eeg_b64 or not str(eeg_b64).strip()) and not eeg_bytes:
        return jsonify({"error": "eeg_base64 required and cannot be empty"}), 400

    try:
        if eeg_bytes:
            feats = extract_eeg_payload_bytes(eeg_bytes, eeg_ext)
        else:
            feats = extract_eeg_payload(str(eeg_b64), eeg_ext)
        if isinstance(device_preprocessing, dict):
            feats["device_preprocessing"] = device_preprocessing
        feats["request_id"] = request_id
        if child_id:
            feats["child_id"] = child_id
        return jsonify(feats)
    except Exception as exc:  # pragma: no cover - defensive
        print(
            f"[REQ {request_id}] EEG feature extraction failed child_id={child_id}: {exc}\n"
            f"{traceback.format_exc()}",
            flush=True,
        )
        return jsonify(
            {
                "error": f"EEG feature extraction failed: {exc}",
                "request_id": request_id,
                **({"child_id": child_id} if child_id else {}),
            }
        ), 500


@app.route("/api/progress/<child_id>", methods=["GET"])
def get_progress(child_id: str):
    try:
        cid = int(child_id)
    except (ValueError, TypeError):
        return jsonify([])

    with get_db() as conn:
        cur = conn.cursor()
        cur.execute(
            """SELECT created_at, memory_score, attention_score, language_score
               FROM assessments WHERE child_id = ? AND status = 'completed'
               ORDER BY created_at""",
            (cid,),
        )
        rows = cur.fetchall()

    history = [
        {
            "id": str(i + 1),
            "created_at": row["created_at"],
            "scores": {
                "memory": row["memory_score"] or 0,
                "attention": row["attention_score"] or 0,
                "language": row["language_score"] or 0,
            },
        }
        for i, row in enumerate(rows)
    ]
    return jsonify(history)


@app.route("/api/reports/<child_id>", methods=["GET"])
def get_reports(child_id: str):
    try:
        cid = int(child_id)
    except (ValueError, TypeError):
        return jsonify([])

    with get_db() as conn:
        cur = conn.cursor()
        cur.execute(
            """SELECT r.id, r.report_json, r.created_at, a.type, a.linked_pre_report_id
               FROM reports r
               JOIN assessments a ON r.assessment_id = a.id
               WHERE r.child_id = ?
               ORDER BY r.created_at DESC""",
            (cid,),
        )
        rows = cur.fetchall()

    result = []
    pre_data = None
    pre_reports_by_id = {}
    for row in rows:
        if row["type"] == "initial":
            pre_reports_by_id[int(row["id"])] = json.loads(row["report_json"])

    for row in rows:
        data = json.loads(row["report_json"])
        report_type = "pre" if row["type"] == "initial" else "post"
        recs = data.get("recommendations", [])
        linked_pre_report_id = row["linked_pre_report_id"]

        trends = data.get("trends") or {}
        deltas = data.get("deltas")
        if isinstance(deltas, dict):
            deltas = {str(k).replace("_score", ""): v for k, v in deltas.items()}
        if isinstance(trends, dict):
            trends = {str(k).replace("_score", ""): v for k, v in trends.items()}
        if report_type == "post" and not deltas:
            linked_pre_data = None
            if linked_pre_report_id is not None:
                linked_pre_data = pre_reports_by_id.get(int(linked_pre_report_id))
            if linked_pre_data is None:
                linked_pre_data = pre_data
            if linked_pre_data:
                deltas = {}
                trends = {}
                for k in ["memory_score", "attention_score", "language_score"]:
                    delta = data.get(k, 0) - linked_pre_data.get(k, 0)
                    key = k.replace("_score", "")
                    deltas[key] = round(float(delta), 1)
                    if delta > 3:
                        trends[key] = "improved"
                    elif delta < -3:
                        trends[key] = "declined"
                    else:
                        trends[key] = "no_change"
        if report_type == "pre":
            pre_data = data

        cognitive_score = data.get("cognitive_score")
        comparison = data.get("comparison") or {}
        if report_type == "post" and not comparison and isinstance(deltas, dict):
            average_change = round(
                sum(float(v) for v in deltas.values()) / max(len(deltas), 1),
                1,
            )
            if average_change > 3:
                comparison_summary = "Overall performance improved compared with the linked pre-test."
            elif average_change < -3:
                comparison_summary = "Overall performance declined compared with the linked pre-test."
            else:
                comparison_summary = "Overall performance remained broadly stable compared with the linked pre-test."
            comparison = {
                "available": True,
                "linked_pre_report_id": str(linked_pre_report_id) if linked_pre_report_id is not None else data.get("linked_pre_report_id", ""),
                "average_change": average_change,
                "summary": comparison_summary,
                "domains": {
                    "memory": {
                        "delta": deltas.get("memory"),
                        "trend": trends.get("memory", "no_change"),
                    },
                    "attention": {
                        "delta": deltas.get("attention"),
                        "trend": trends.get("attention", "no_change"),
                    },
                    "language": {
                        "delta": deltas.get("language"),
                        "trend": trends.get("language", "no_change"),
                    },
                },
            }

        result.append({
            "id": str(row["id"]),
            "child_id": str(cid),
            "type": report_type,
            "created_at": row["created_at"],
            "linked_pre_report_id": str(linked_pre_report_id) if linked_pre_report_id is not None else data.get("linked_pre_report_id"),
            "scores": {
                "memory": data.get("memory_score", 0),
                "attention": data.get("attention_score", 0),
                "language": data.get("language_score", 0),
                "cognitive": cognitive_score,
                "overall_cognitive": cognitive_score,
            },
            "recommendations": recs,
            "summary": data.get("summary", ""),
            "game_library_total": data.get("game_library_total", TOTAL_GAME_CATALOG_SIZE),
            "recommendation_note": data.get("recommendation_note", ""),
            "weak_areas_detected": data.get("weak_areas_detected", []),
            "recommendation_logic": data.get("recommendation_logic", {}),
            "analysis": {
                "cognitive_score": cognitive_score,
                "eeg_score": data.get("eeg_score"),
                "audio_score": data.get("audio_score"),
                "face_score": data.get("face_score"),
                # Optional extended analysis used by the Flutter Results screen.
                # Older stored reports may not have these keys.
                "eeg": data.get("eeg") or {},
                "audio": data.get("audio") or {},
                "behavioral_components": {
                    "memory": data.get("memory_score") or 0,
                    "attention": data.get("attention_score") or 0,
                    "language": data.get("language_score") or 0,
                },
            },
            "behavioral": data.get("behavioral"),
            "audio": data.get("audio"),
            "comparison": comparison,
            "trends": trends,
            "deltas": deltas,
        })

    return jsonify(result)


@app.route("/api/assessment/post_status/<child_id>", methods=["GET"])
def post_status(child_id: str):
    try:
        cid = int(child_id)
    except (ValueError, TypeError):
        return jsonify({"status": "no_pre", "message": "Invalid child."}), 400

    pre_report_id_raw = request.args.get("pre_report_id")
    selected_pre_report_id = None
    if pre_report_id_raw not in (None, "", "null"):
        try:
            selected_pre_report_id = int(pre_report_id_raw)
        except (ValueError, TypeError):
            return jsonify({"status": "invalid", "message": "Invalid pre report id."}), 400

    with get_db() as conn:
        cur = conn.cursor()
        if selected_pre_report_id is not None:
            cur.execute(
                """SELECT r.id, r.created_at FROM reports r
                   JOIN assessments a ON r.assessment_id = a.id
                   WHERE r.id = ? AND r.child_id = ? AND a.type = 'initial'
                   LIMIT 1""",
                (selected_pre_report_id, cid),
            )
        else:
            cur.execute(
                """SELECT r.id, r.created_at FROM reports r
                   JOIN assessments a ON r.assessment_id = a.id
                   WHERE r.child_id = ? AND a.type = 'initial'
                   ORDER BY r.created_at DESC LIMIT 1""",
                (cid,),
            )
        row = cur.fetchone()

        if row:
            cur.execute(
                """SELECT r.id FROM reports r
                   JOIN assessments a ON r.assessment_id = a.id
                   WHERE r.child_id = ? AND a.type = 'post' AND a.linked_pre_report_id = ?
                   ORDER BY r.created_at DESC LIMIT 1""",
                (cid, int(row["id"])),
            )
            existing_post = cur.fetchone()
        else:
            existing_post = None

    if not row:
        return jsonify(
            {
                "status": "no_pre",
                "message": "A pre-assessment report is required before scheduling a post assessment.",
            }
        )

    if existing_post:
        return jsonify(
            {
                "status": "completed",
                "message": "A post assessment is already saved for this report.",
                "post_report_id": str(existing_post["id"]),
            }
        )

    created_str = str(row["created_at"])
    try:
        created = datetime.fromisoformat(created_str.replace("Z", "+00:00"))
    except ValueError:
        created = datetime.strptime(created_str[:19].replace(" ", "T"), "%Y-%m-%dT%H:%M:%S")
    if created.tzinfo:
        created = created.replace(tzinfo=None)

    if not can_take_post_test(created):
        available_at = created + timedelta(days=14)
        return jsonify(
            {
                "status": "locked",
                "available_at": available_at.isoformat(),
                "message": "Post assessment available after 2 weeks from the initial report.",
            }
        )
    return jsonify({"status": "unlocked"})

@app.route("/api/behavior/submit", methods=["POST"])
def submit_behavioral_results():
    """
    Accepts behavioral test results and returns combined cognitive assessment summary.
    Expects JSON with keys: eeg_score, audio_score, reaction_time_ms, stroop_accuracy, memory_score, [optionally: user_id, session_id]
    """
    data = request.get_json(force=True)
    eeg_score = float(data.get("eeg_score", 0))
    audio_score = float(data.get("audio_score", 0))
    reaction_time_ms = float(data.get("reaction_time_ms", 0))
    stroop_accuracy = float(data.get("stroop_accuracy", 0))
    memory_score = float(data.get("memory_score", 0))

    # Normalize behavioral score (simple average, can be weighted)
    # Reaction time: lower is better, invert and scale (assume 200-800ms typical)
    rt_norm = max(0, min(1, (800 - reaction_time_ms) / 600))
    stroop_norm = stroop_accuracy / 100.0
    mem_norm = memory_score / 10.0  # assuming out of 10
    behavior_score = (rt_norm + stroop_norm + mem_norm) / 3

    # Combined score
    final_score = 0.4 * eeg_score + 0.3 * audio_score + 0.3 * behavior_score

    # Cognitive load level
    if final_score >= 0.75:
        level = "Low (Good)"
    elif final_score >= 0.5:
        level = "Moderate"
    else:
        level = "High (Needs Attention)"

    summary = {
        "eeg_score": eeg_score,
        "audio_score": audio_score,
        "behavioral": {
            "reaction_time_ms": reaction_time_ms,
            "stroop_accuracy": stroop_accuracy,
            "memory_score": memory_score,
            "behavior_score": round(behavior_score, 3),
        },
        "final_score": round(final_score, 3),
        "cognitive_load_level": level,
        "message": f"EEG: {eeg_score:.2f}, Audio: {audio_score:.2f}, Behavior: {behavior_score:.2f} → Final: {final_score:.2f} ({level})"
    }
    return jsonify(summary), 200

@app.route("/api/children/by_parent/<email>", methods=["GET"])
def get_children_by_parent(email: str):
    email = _normalize_email(email)
    children = _get_child_accounts_for_parent(email)
    return jsonify(children)


if __name__ == "__main__":
    # 🚀 Unbuffered output: Ensure logs appear immediately
    os.environ['PYTHONUNBUFFERED'] = '1'
    
    ssl_mode = os.getenv("FLASK_SSL_ADHOC", "0").strip().lower() in {
        "1",
        "true",
        "yes",
    }
    ssl_context = "adhoc" if ssl_mode else None
    debug_mode = os.getenv("FLASK_DEBUG", "1").strip().lower() in {
        "1",
        "true",
        "yes",
    }
    port = int(os.getenv("PORT", "8000"))
    
    # Debug mode with auto-reload for development
    # Werkzeug's reloader ensures heavy initialization only runs once
    app.run(
        host="0.0.0.0",
        port=port,
        debug=debug_mode,
        ssl_context=ssl_context,
    )
