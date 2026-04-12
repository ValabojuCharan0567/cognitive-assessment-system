# Model evaluation

Runtime evaluation reports are exposed by the Flask API and stored under versioned docs:

- **HTTP:** `GET /api/reports/model_evaluation` (with the backend running).
- **Checked-in snapshots:** [docs/model_reports/](../../docs/model_reports/) (JSON + summary markdown).

For **offline** metrics after retraining, use a holdout split inside the training scripts in [`../training/`](../training/) or export predictions and compute metrics in a notebook.

This directory is a namespace placeholder for future standalone eval scripts (e.g. batch scoring against a labeled CSV).
