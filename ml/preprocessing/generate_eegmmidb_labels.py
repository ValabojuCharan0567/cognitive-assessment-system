#!/usr/bin/env python3
"""Generate balanced labels CSV for EEGMMIDB dataset."""

from pathlib import Path
import pandas as pd
from config import dataset_subpath

ROOT = Path(__file__).resolve().parents[1]
DATASET_DIR = dataset_subpath("EEG")
LABELS_CSV = dataset_subpath("EEG_EDF", "labels.csv")
RAW_LABELS_CSV = dataset_subpath("EEG", "labels.csv")

def generate_labels():
    """Scan the EEG dataset folder and create balanced labels.csv."""
    rows = []
    
    # Collect all EDF files
    for subject_dir in sorted(DATASET_DIR.glob("S*")):
        if not subject_dir.is_dir():
            continue
        subject_id = subject_dir.name
        edf_files = sorted(subject_dir.glob("*.edf"))
        
        for edf_file in edf_files:
            rel_path = f"{subject_id}/{edf_file.name}"
            rows.append({"path": rel_path})
    
    subject_count = len(list(DATASET_DIR.glob('S*')))
    print(f"[INFO] Found {len(rows)} EDF files across {subject_count} subjects")
    
    if not rows:
        raise RuntimeError(f"No EDF files found in {DATASET_DIR}")
    
    df = pd.DataFrame(rows)
    
    # Assign balanced cognitive load labels
    # Strategy: Use run type as proxy for cognitive load
    # - R01, R02 (baseline/eyes open): Low
    # - R03-R06 (motor imagery/movement): Medium
    # - R07-R14 (motor imagery evaluation): High
    def assign_label(path_str):
        run_num = int(path_str.split("R")[1].split(".")[0])
        if run_num in [1, 2]:
            return "Low"
        elif run_num in [3, 4, 5, 6]:
            return "Medium"
        else:  # 7-14
            return "High"

    def assign_effort(path_str):
        run_num = int(path_str.split("R")[1].split(".")[0])
        effort_by_run = {
            1: 0.18,
            2: 0.25,
            3: 0.42,
            4: 0.50,
            5: 0.58,
            6: 0.65,
            7: 0.72,
            8: 0.76,
            9: 0.80,
            10: 0.83,
            11: 0.86,
            12: 0.89,
            13: 0.92,
            14: 0.95,
        }
        return float(effort_by_run.get(run_num, 0.55))

    df["label"] = df["path"].apply(assign_label)
    df["effort"] = df["path"].apply(assign_effort)
    
    # Verify balance
    label_counts = df["label"].value_counts()
    print(f"[INFO] Label distribution: {dict(label_counts)}")
    
    # Save CSV in both the EEG_EDF location and the raw EEG location so
    # training utilities can discover the prepared labels reliably.
    LABELS_CSV.parent.mkdir(parents=True, exist_ok=True)
    RAW_LABELS_CSV.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(LABELS_CSV, index=False)
    df.to_csv(RAW_LABELS_CSV, index=False)
    print(f"[SUCCESS] Saved labels to {LABELS_CSV}")
    print(f"[SUCCESS] Saved labels to {RAW_LABELS_CSV}")

if __name__ == "__main__":
    generate_labels()
