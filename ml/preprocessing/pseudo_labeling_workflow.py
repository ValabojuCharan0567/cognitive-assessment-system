#!/usr/bin/env python3
"""
Pseudo-labeling orchestration script.

Runs the complete workflow:
1. Pseudo-label unlabeled audio using trained model
2. Review pseudo-labeled results
3. Optionally append to training data
4. Optionally retrain model with expanded dataset
"""

import os
import sys
import argparse
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import pandas as pd
import numpy as np
from pseudo_label_audio import run_pseudo_labeling
from config import dataset_subpath


def append_pseudo_labels_to_training_data(
    pseudo_csv: str,
    training_csv: str,
    min_confidence: float = 0.0
) -> int:
    """
    Append high-confidence pseudo-labeled samples to training CSV.
    
    Args:
        pseudo_csv: Path to pseudo-labeled CSV
        training_csv: Path to training labels CSV
        min_confidence: Only include predictions with confidence >= min_confidence
    
    Returns:
        Number of samples appended
    """
    print(f"\n📋 APPENDING PSEUDO-LABELED DATA")
    print("=" * 70)
    
    if not os.path.exists(pseudo_csv):
        print(f"❌ Pseudo-labeled CSV not found: {pseudo_csv}")
        return 0
    
    pseudo_df = pd.read_csv(pseudo_csv)
    
    # Filter by confidence
    if min_confidence > 0:
        pseudo_df = pseudo_df[pseudo_df['confidence'] >= min_confidence]
    
    print(f"Pseudo-labeled samples (conf >= {min_confidence}): {len(pseudo_df)}")
    
    # Load existing training data
    if os.path.exists(training_csv):
        train_df = pd.read_csv(training_csv)
        print(f"Existing training samples: {len(train_df)}")
    else:
        train_df = pd.DataFrame()
        print(f"Creating new training CSV: {training_csv}")
    
    # Prepare pseudo-labeled data for appending
    # Convert to same format as training CSV (path, label)
    append_rows = []
    speech_root = Path(training_csv).resolve().parent
    for _, row in pseudo_df.iterrows():
        raw_path = str(row.get('filepath', '')).strip()
        if raw_path:
            try:
                resolved = Path(raw_path).resolve()
                rel_path = resolved.relative_to(speech_root).as_posix()
            except Exception:
                raw_norm = raw_path.replace('\\', '/')
                marker = "/speech_data/"
                rel_path = raw_norm.split(marker, 1)[1] if marker in raw_norm else Path(raw_norm).name
        else:
            rel_path = str(row.get('filename', '')).strip()

        append_rows.append({
            'path': rel_path,
            'label': row['cognitive_load']
        })
    
    append_df = pd.DataFrame(append_rows)
    
    # Combine
    combined_df = pd.concat([train_df, append_df], ignore_index=True)
    
    # Remove duplicates (keep first occurrence)
    combined_df = combined_df.drop_duplicates(subset=['path'], keep='first')
    
    # Save
    combined_df.to_csv(training_csv, index=False)
    
    new_count = len(combined_df) - len(train_df)
    print(f"\n✅ Appended {new_count} pseudo-labeled samples")
    print(f"📊 New total: {len(combined_df)} samples")
    
    return new_count


def retrain_model_with_pseudo_labels(use_sidecar_pseudo_csv: bool = False):
    """
    Retrain audio model with pseudo-labeled data.

    Args:
        use_sidecar_pseudo_csv: If True, load pseudo labels from pseudo_labeled_audio.csv
            in addition to audio_labels.csv. If False, train only from audio_labels.csv.
    """
    print(f"\n🔄 RETRAINING MODEL WITH PSEUDO-LABELED DATA")
    print("=" * 70)
    
    from train_audio_model import train_audio_model
    
    mode = "audio_labels.csv + pseudo_labeled_audio.csv" if use_sidecar_pseudo_csv else "audio_labels.csv only"
    print(f"Starting model retraining with data source: {mode}")
    try:
        train_audio_model(include_pseudo_labeled=use_sidecar_pseudo_csv)
        print("\n✅ Model retraining completed successfully!")
        return True
    except Exception as e:
        print(f"\n❌ Model retraining failed: {e}")
        return False


def run_full_workflow(
    unlabeled_dir: str,
    confidence_threshold: float = 0.9,
    append_to_training: bool = False,
    retrain: bool = False,
    max_samples: int = 500,
    skip_samples: int = 0,
):
    """
    Run complete pseudo-labeling workflow.
    
    Args:
        unlabeled_dir: Directory with unlabeled audio
        confidence_threshold: Minimum confidence for predictions
        append_to_training: Whether to append pseudo-labels to training data
        retrain: Whether to retrain model after appending
        max_samples: Limit number of files to process
    """
    print(f"\n{'='*70}")
    print(f"PSEUDO-LABELING WORKFLOW")
    print(f"{'='*70}")
    
    # Step 1: Run pseudo-labeling
    print(f"\n✨ STEP 1: PSEUDO-LABELING")
    pseudo_csv = dataset_subpath("speech_data", "pseudo_labeled_audio.csv")
    training_csv = dataset_subpath("speech_data", "audio_labels.csv")
    
    summary = run_pseudo_labeling(
        input_dir=unlabeled_dir,
        confidence_threshold=confidence_threshold,
        output_csv=str(pseudo_csv),
        max_samples=max_samples,
        skip_samples=skip_samples,
    )
    
    if summary['pseudo_labeled_count'] == 0:
        print("\n⚠️  No high-confidence predictions generated. Exiting.")
        return False
    
    # Step 2: Optional append to training data
    if append_to_training:
        print(f"\n✨ STEP 2: APPENDING TO TRAINING DATA")
        appended = append_pseudo_labels_to_training_data(
            pseudo_csv=str(pseudo_csv),
            training_csv=str(training_csv),
            min_confidence=confidence_threshold
        )
        
        if appended == 0:
            print("\n⚠️  No samples appended. Exiting.")
            return False
        
        # Step 3: Optional retrain
        if retrain:
            print(f"\n✨ STEP 3: RETRAINING MODEL")
            # After append, audio_labels.csv already contains pseudo-labels.
            # Train from one source to avoid double-counting the same samples.
            success = retrain_model_with_pseudo_labels(use_sidecar_pseudo_csv=False)
            return success
    else:
        print(f"\n📝 Pseudo-labeled data saved to: {pseudo_csv}")
        print(f"📝 To append to training, run with --append-to-training flag")
        print(f"📝 Then retrain with either:")
        print(f"   - python backend/train_audio_model.py --with-pseudo  (sidecar pseudo CSV)")
        print(f"   - python backend/train_audio_model.py               (if already appended)")
    
    print(f"\n{'='*70}")
    print(f"✅ WORKFLOW COMPLETE")
    print(f"{'='*70}\n")
    
    return True


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Pseudo-labeling workflow orchestrator"
    )
    parser.add_argument(
        "--input-dir",
        required=True,
        help="Directory containing unlabeled audio files"
    )
    parser.add_argument(
        "--confidence-threshold",
        type=float,
        default=0.9,
        help="Minimum confidence for pseudo-labels (default: 0.8)"
    )
    parser.add_argument(
        "--append-to-training",
        action="store_true",
        help="Automatically append pseudo-labels to training data"
    )
    parser.add_argument(
        "--retrain",
        action="store_true",
        help="Automatically retrain model after appending pseudo-labels"
    )
    parser.add_argument(
        "--max-samples",
        type=int,
        default=500,
        help="Limit number of files to pseudo-label"
    )
    parser.add_argument(
        "--skip-samples",
        type=int,
        default=0,
        help="Skip first N files after sorting (for batch processing)"
    )
    
    args = parser.parse_args()
    
    success = run_full_workflow(
        unlabeled_dir=args.input_dir,
        confidence_threshold=args.confidence_threshold,
        append_to_training=args.append_to_training,
        retrain=args.retrain,
        max_samples=args.max_samples,
        skip_samples=args.skip_samples,
    )
    
    sys.exit(0 if success else 1)
