# Dataset bundle for Docker / Render

This folder is **copied into the container** by `backend/Dockerfile` as `/workspace/data`.

## Required layout

```text
data/
  EEG/ # EEG assets your pipeline expects (e.g. .edf or per your training layout)
  speech_data/   # Speech/audio dataset layout used by training / pseudo-labeling
```

`backend/api/app.py` validates that **`EEG/`** and **`speech_data/`** exist under `DATASET_PATH` when not in demo mode.

## Size / GitHub

- GitHub warns above ~50 MB per file; hard limit ~100 MB per file.
- If your dataset is larger, use **Git LFS**, a **persistent disk** on the host, or **object storage** — do not commit multi‑GB raw data here.

## Render

Set in the dashboard (optional if the image already sets defaults):

```env
DATASET_PATH=/workspace/data
```

Local development can still use `DATASET_PATH=$HOME/Datasets/CognitiveAssessment` or your own path.
