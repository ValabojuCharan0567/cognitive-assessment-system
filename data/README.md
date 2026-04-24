# Dataset layout (`DATASET_PATH`)

The backend expects **`DATASET_PATH`** to point at a directory that contains at least:

```text
<DATASET_PATH>/
  speech_data/  # required for full (non-demo) API startup validation
  EEG/  OR  EEG SIGNAL DATA/  # at least one; reference analytics use EEG SIGNAL DATA (see utils/eeg_reference.py)
```

Use **`EEG/`** for the minimal Docker bundle under repo **`data/`**. A common local checkout uses root **`Dataset/`** with the research folder name **`EEG SIGNAL DATA/`** — set:

`export DATASET_PATH="/Users/charanvalaboju/valaboju charan/Cognitive Assessment System/Dataset"`

Optional (used by some **`ml/`** scripts, not by the live Flask `validate_dataset` check):

```text
  EEG_EDF/      # e.g. labels.csv for training pipelines — see ml/preprocessing/
```

## Three ways to provide data

| Where | Path | Git |
|--------|------|-----|
| **Docker / Railway (bundled)** | Image: `/workspace/data` from repo **`data/`** | Commit small `EEG/` + `speech_data/` subsets under GitHub size limits |
| **Local (default)** | `$HOME/Datasets/CognitiveAssessment` | Not in repo; set `DATASET_PATH` if you use another folder |
| **Legacy local folder name** | `./Dataset/` at repo root | **Gitignored** — convenience only; same role as any external `DATASET_PATH` |

Docs that say `Dataset/speech_data/...` mean “under your dataset root,” not a special folder name.

## Docker

`backend/Dockerfile` runs:

```dockerfile
COPY data /workspace/data
ENV DATASET_PATH=/workspace/data
```

So the **repo directory `data/`** must exist (even if only empty `EEG/` + `speech_data/` with placeholders) or the **image build fails**.

## Railway

Usually **no extra env** is needed; the Dockerfile sets `DATASET_PATH`. Override only if you change the image layout.

## Size

GitHub: keep large binaries under per-file limits; use **Git LFS**, host storage, or mount a volume for multi‑GB datasets.
