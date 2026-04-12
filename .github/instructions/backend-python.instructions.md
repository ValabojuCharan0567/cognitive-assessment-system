---
description: "Use when editing backend Python Flask routes, feature extraction, model scoring, or database logic in backend/*.py. Covers API compatibility, EEG feature-schema safety, and local validation commands."
name: "Backend Python Guardrails"
applyTo: "backend/**/*.py"
---
# Backend Python Guardrails

## Scope
- Apply these rules for all Python backend edits under backend/.
- Keep behavior aligned with existing Flask blueprint structure in backend/app.py, backend/feature_api.py, backend/cloud_api.py, and backend/reports_api.py.

## API and Data Compatibility
- Preserve request and response key compatibility for existing clients, especially base64 payload fields used by EEG/audio endpoints.
- Keep score-composition behavior stable unless the task explicitly asks to change product logic.
- Avoid renaming public route paths or response keys without a migration-safe transition.

## EEG and Model Schema Safety
- Treat EEG feature columns as contract-bound between training and inference.
- Before adding or removing any EEG feature field, check both backend/train_models.py and backend/feature_pipeline.py in the same change.
- If model artifacts are retrained or replaced, note that backend restart is required for fresh model loading.

## Implementation Style
- Prefer small helper functions over long route handlers.
- Keep payload validation/parsing separate from model inference and scoring logic.
- Preserve Python 3.10+ compatible syntax and current module style.

## Validation Checklist
- For backend server behavior: run ./run_backend.sh
- For local end-to-end app checks: run ./run_local_dev.sh backend or platform mode
- For model/report workflows: run python backend/model_evaluation.py

## Related Docs
- See secure_deployment.md for HTTPS and upload security behavior.
- See research_improvements.md for evaluation/reporting workflow.
