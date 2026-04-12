#!/usr/bin/env bash
# Simple wrapper to perform the EDF workflow end-to-end from a fresh clone.
# Usage from project root:
#    bash backend/run_all.sh [--preview path/to/file.edf]
# The script will:
#  1. ensure the venv is activated (or prompt you)
#  2. install python dependencies
#  3. optionally preview a single EDF
#  4. verify DATASET_PATH/EEG_EDF/labels.csv exists
#  5. train the EEG model
#  6. run model evaluation

set -euo pipefail

VENV_ACTIVATE="$PWD/.venv/bin/activate"
export DATASET_PATH="${DATASET_PATH:-$HOME/Datasets/CognitiveAssessment}"
if [[ -f "$VENV_ACTIVATE" ]]; then
    # shellcheck source=/dev/null
    source "$VENV_ACTIVATE"
else
    echo "ERROR: virtualenv activate script not found at $VENV_ACTIVATE"
    echo "Please create and activate a Python venv first."
    exit 1
fi

# parse args
PREVIEW_FILE=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --preview)
            PREVIEW_FILE="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

# install requirements
echo "==> installing backend dependencies"
pip install -r backend/requirements.txt

if [[ -n "$PREVIEW_FILE" ]]; then
    echo "==> previewing EDF file: $PREVIEW_FILE"
    python backend/preview_edf.py "$PREVIEW_FILE"
fi

# dataset check
EEG_DIR="$DATASET_PATH/EEG_EDF"
LABELS_CSV="$EEG_DIR/labels.csv"
if [[ ! -f "$LABELS_CSV" ]]; then
    echo "WARNING: labels.csv not found in $EEG_DIR"
    echo "Create one before running training. Exiting."
    exit 1
fi

echo "==> training EEG model (classification + regression)"
python backend/train_eeg_from_edf.py

echo "==> running evaluation report"
python backend/model_evaluation.py

echo "All done. Models and reports should be in models/ and model_reports/"
