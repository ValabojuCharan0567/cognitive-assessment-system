import base64
import io
import tempfile
import unittest
import wave
from pathlib import Path
from unittest.mock import patch

import numpy as np
import database
import feature_pipeline
import core.feature_pipeline as fp
import audio_features
from api.app import app as flask_app
from database import get_db, init_db

# Rule: avoid direct imports of private helper functions.
# Prefer: import core.feature_pipeline as fp
# This keeps tests resilient to pipeline refactor and re-export path changes.


def _valid_behavioral_payload():
    return {
        "accuracy_percent": 82.0,
        "mean_reaction_ms": 920.0,
        "memory_accuracy": 80.0,
        "attention_accuracy": 84.0,
        "language_accuracy": 82.0,
        "correct_count": 41,
        "error_count": 9,
        "total_trials": 50,
    }


def _valid_eeg_payload():
    return {
        "delta_power_mean": 0.8,
        "theta_power_mean": 0.7,
        "alpha_power_mean": 0.6,
        "beta_power_mean": 0.9,
        "gamma_power_mean": 0.5,
        "frontal_asymmetry_index": 0.1,
        "mental_effort_score": 0.58,
        "signal_entropy": 0.3,
        "pupil_dilation_avg": 2.4,
        "heart_rate_variability": 0.12,
    }


def _valid_audio_payload():
    return {
        "fluency_score": 78.0,
        "fluency_label": "Medium",
        "confidence": 0.9,
        "valid": True,
        "silence_detected": False,
    }


class PipelineApiTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        database.DB_PATH = Path(self.temp_dir.name) / "test_database.db"
        init_db()
        self.client = flask_app.test_client()

        with get_db() as conn:
            cur = conn.cursor()
            cur.execute(
                """
                INSERT INTO users (name, email, password, email_verified)
                VALUES (?, ?, ?, ?)
                """,
                ("Tester", "tester@example.com", "secret", 1),
            )
            user_id = cur.lastrowid
            cur.execute(
                """
                INSERT INTO children (user_id, name, age, gender, grade, difficulty_level)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                (user_id, "Child One", 10, "M", "5", 2),
            )
            child_id = cur.lastrowid
            cur.execute(
                """
                INSERT INTO assessments (child_id, type, status)
                VALUES (?, ?, ?)
                """,
                (child_id, "initial", "in_progress"),
            )
            self.assessment_id = cur.lastrowid

    def tearDown(self):
        self.temp_dir.cleanup()

    @patch("api.app.engine.score_domains")
    @patch("api.app.engine.eeg_model.predict_load_and_effort")
    def test_full_pipeline_submit_returns_result(
        self,
        mock_predict_load_and_effort,
        mock_score_domains,
    ):
        from ml_models import DomainScores

        mock_score_domains.return_value = DomainScores(
            memory=79.0,
            attention=81.0,
            language=80.0,
        )
        mock_predict_load_and_effort.return_value = {"effort": 0.58, "load_level": "Medium"}

        response = self.client.post(
            "/api/assessment/submit",
            json={
                "assessment_id": str(self.assessment_id),
                "behavioral": _valid_behavioral_payload(),
                "eeg": _valid_eeg_payload(),
                "audio": _valid_audio_payload(),
            },
        )
        self.assertEqual(response.status_code, 200)
        payload = response.get_json()

        self.assertIn("scores", payload)
        self.assertIn("analysis", payload)
        self.assertIn("behavioral", payload)
        self.assertIn("report_id", payload)
        self.assertTrue(payload.get("report_saved"))
        self.assertIn("cognitive", payload["scores"])

    def test_edge_case_no_audio_rejected(self):
        response = self.client.post("/api/audio/analyze", json={"audio_ext": "wav"})
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.get_json().get("error"), "audio_base64 required and cannot be empty")

    def test_silent_or_low_noise_audio_is_rejected(self):
        # Create ~2s of truly silent audio (zeros)
        sr = 16000
        duration = 2
        num_samples = sr * duration
        silent_noise = np.zeros(num_samples, dtype=np.int16)

        buf = io.BytesIO()
        with wave.open(buf, "wb") as wav_file:
            wav_file.setnchannels(1)
            wav_file.setsampwidth(2)
            wav_file.setframerate(sr)
            wav_file.writeframes(silent_noise.tobytes())

        encoded = base64.b64encode(buf.getvalue()).decode("ascii")

        with self.assertRaises(feature_pipeline.AudioValidationError):
            feature_pipeline.analyze_audio_payload(encoded, "wav")

    @patch("api.app.analyze_audio_payload")
    def test_audio_multipart_upload_is_supported(self, mock_analyze_audio_payload):
        mock_analyze_audio_payload.return_value = {
            "fluency_score": 78.0,
            "fluency_label": "Medium",
            "valid": True,
            "silence_detected": False,
        }

        response = self.client.post(
            "/api/audio/analyze",
            data={
                "audio_ext": "wav",
                "device_preprocessing": '{"sample_rate_hz":16000}',
                "audio": (io.BytesIO(b"fake wav bytes"), "sample.wav"),
            },
            content_type="multipart/form-data",
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json().get("device_preprocessing"), {"sample_rate_hz": 16000})
        mock_analyze_audio_payload.assert_called_once()

    @patch("api.app.engine.score_domains")
    @patch("api.app.engine.eeg_model.predict_load_and_effort")
    def test_edge_case_empty_eeg_rejected(
        self,
        mock_predict_load_and_effort,
        mock_score_domains,
    ):
        from ml_models import DomainScores

        mock_score_domains.return_value = DomainScores(
            memory=75.0,
            attention=76.0,
            language=74.0,
        )
        mock_predict_load_and_effort.return_value = {"effort": 0.52, "load_level": "Medium"}

        response = self.client.post(
            "/api/assessment/submit",
            json={
                "assessment_id": str(self.assessment_id),
                "behavioral": _valid_behavioral_payload(),
                "eeg": {},
                "audio": _valid_audio_payload(),
            },
        )
        self.assertEqual(response.status_code, 400)
        self.assertIn("Missing EEG features", response.get_json().get("error", ""))

    @patch("api.app.analyze_audio_payload")
    @patch("api.app.extract_eeg_payload")
    def test_cross_device_preprocessing_fields_echoed(
        self,
        mock_extract_eeg_payload,
        mock_analyze_audio_payload,
    ):
        mock_analyze_audio_payload.return_value = {
            "fluency_score": 82.0,
            "fluency_label": "High",
            "valid": True,
            "silence_detected": False,
        }
        mock_extract_eeg_payload.return_value = _valid_eeg_payload()

        device_meta = {
            "device_model": "Pixel 8",
            "sample_rate_hz": 16000,
            "normalization": "zscore",
        }

        audio_resp = self.client.post(
            "/api/audio/analyze",
            json={
                "audio_base64": "ZmFrZV9hdWRpbw==",
                "audio_ext": "wav",
                "device_preprocessing": device_meta,
            },
        )
        self.assertEqual(audio_resp.status_code, 200)
        self.assertEqual(audio_resp.get_json().get("device_preprocessing"), device_meta)

        eeg_resp = self.client.post(
            "/api/eeg/analyze",
            json={
                "eeg_base64": "ZmFrZV9lZWc=",
                "eeg_ext": "csv",
                "device_preprocessing": device_meta,
            },
        )
        self.assertEqual(eeg_resp.status_code, 200)
        self.assertEqual(eeg_resp.get_json().get("device_preprocessing"), device_meta)

    @patch("core.feature_pipeline.is_valid_speech", return_value=(True, 0.82))
    @patch("core.feature_pipeline.extract_features_from_path", return_value={"mfcc_mean": 0.42})
    @patch("core.feature_pipeline._align_audio_features_for_inference", return_value=[0.42])
    @patch("librosa.load", return_value=(np.random.random(16000), 16000))
    @patch("model_loader.get_audio_model_bundle")
    def test_audio_confidence_uses_top_probability_not_margin(
        self,
        mock_get_audio_model_bundle,
        mock_librosa_load,
        mock_align_audio_features,
        mock_extract_features,
        mock_is_valid_speech,
    ):
        class _IdentityScaler:
            def transform(self, rows):
                return rows

        class _ProbModel:
            def predict(self, rows):
                return [1]

            def predict_proba(self, rows):
                return [[0.20, 0.41, 0.39]]

        mock_get_audio_model_bundle.return_value = {
            "scaler": _IdentityScaler(),
            "model": _ProbModel(),
        }

        audio_b64 = base64.b64encode(b"fake-audio-payload").decode("ascii")
        result = feature_pipeline.analyze_audio_payload(audio_b64, "wav")

        self.assertAlmostEqual(result["top_probability"], 0.41, places=3)
        self.assertAlmostEqual(result["confidence"], 0.41, places=3)
        self.assertAlmostEqual(result["confidence_margin"], 0.02, places=3)
        self.assertTrue(result["low_confidence"])

    @patch("core.feature_pipeline.extract_features_from_edf")
    @patch("core.feature_pipeline._predict_eeg_load_and_effort")
    def test_extract_eeg_payload_edf_does_not_depend_on_root_global(
        self,
        mock_predict_eeg,
        mock_extract_features_from_edf,
    ):
        mock_extract_features_from_edf.return_value = {
            "delta_power_mean": 0.8,
            "theta_power_mean": 0.7,
            "alpha_power_mean": 0.6,
            "beta_power_mean": 0.9,
            "gamma_power_mean": 0.5,
            "frontal_asymmetry_index": 0.1,
            "mental_effort_score": 0.58,
            "signal_entropy": 0.3,
            "pupil_dilation_avg": 2.4,
            "heart_rate_variability": 0.12,
        }
        mock_predict_eeg.return_value = {
            "load_class": 1,
            "load_level": "Medium",
            "effort": 0.58,
            "confidence": 0.81,
            "low_confidence": False,
        }

        original_root = feature_pipeline.__dict__.pop("ROOT", None)
        try:
            result = feature_pipeline.extract_eeg_payload(
                base64.b64encode(b"fake-edf").decode("ascii"),
                "edf",
            )
        finally:
            if original_root is not None:
                feature_pipeline.__dict__["ROOT"] = original_root

        self.assertEqual(result["load_level"], "Medium")
        self.assertAlmostEqual(result["confidence"], 0.81, places=3)
        mock_extract_features_from_edf.assert_called_once()

    @patch("audio_features.librosa.load")
    def test_load_audio_consistent_normalizes_and_resamples(self, mock_librosa_load):
        mock_librosa_load.return_value = (
            np.array([0.0, 0.5, -1.0, 2.0], dtype=np.float64),
            22050,
        )

        y, sr = audio_features.load_audio_consistent("sample.m4a")

        self.assertEqual(sr, 16000)
        self.assertEqual(y.dtype, np.float32)
        self.assertAlmostEqual(float(np.max(np.abs(y))), 1.0, places=6)
        mock_librosa_load.assert_called_once_with("sample.m4a", sr=16000, mono=True)

    def test_get_breakdown_metrics_survives_missing_private_helper(self):
        feats = {
            "rms_mean": 0.8,
            "zcr_mean": 0.2,
            "spectral_centroid_mean": 120.0,
            "spectral_bandwidth_mean": 80.0,
        }
        original_private = fp.__dict__.pop("_calculate_breakdown_metrics", None)
        try:
            result = fp._get_breakdown_metrics(feats)
        finally:
            if original_private is not None:
                fp.__dict__["_calculate_breakdown_metrics"] = original_private

        self.assertIsInstance(result, tuple)
        self.assertEqual(len(result), 2)
        self.assertTrue(all(isinstance(value, float) for value in result))

    def test_get_breakdown_metrics_returns_hard_fallback_without_any_helper(self):
        original_private = fp.__dict__.pop("_calculate_breakdown_metrics", None)
        original_public = fp.__dict__.pop("calculate_breakdown_metrics", None)
        try:
            result = fp._get_breakdown_metrics(object())
        finally:
            if original_private is not None:
                fp.__dict__["_calculate_breakdown_metrics"] = original_private
            if original_public is not None:
                fp.__dict__["calculate_breakdown_metrics"] = original_public

        self.assertEqual(result, (50.0, 50.0))

    def test_generate_dynamic_confidence_hint_handles_numpy_array(self):
        hint = feature_pipeline._generate_dynamic_confidence_hint(42.0, 0.55, np.zeros(20))
        self.assertIsNotNone(hint)
        self.assertIsInstance(hint, str)


if __name__ == "__main__":
    unittest.main()
