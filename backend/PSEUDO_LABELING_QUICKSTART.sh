#!/bin/bash
# Quick Reference: Pseudo-Labeling Commands
# Copy-paste these commands to get started immediately

export DATASET_PATH="${DATASET_PATH:-$HOME/Datasets/CognitiveAssessment}"
SPEECH_DIR="$DATASET_PATH/speech_data"

# ============================================================================
# OPTION 1: Just generate pseudo-labels (no auto-append)
# ============================================================================

# Replace /path/to/unlabeled/audio with actual directory
python backend/pseudo_label_audio.py \
  --input-dir /path/to/unlabeled/audio \
  --confidence-threshold 0.8 \
  --output-csv "$SPEECH_DIR/pseudo_labeled_audio.csv"

# Output: $SPEECH_DIR/pseudo_labeled_audio.csv
# Next: Manually review and append to audio_labels.csv if desired


# ============================================================================
# OPTION 2: Full automatic workflow (label → append → retrain)
# ============================================================================

python backend/pseudo_labeling_workflow.py \
  --input-dir /path/to/unlabeled/audio \
  --confidence-threshold 0.8 \
  --append-to-training \
  --retrain

# This does all three steps in one go


# ============================================================================
# OPTION 3: Step-by-step manual control
# ============================================================================

# Step 1: Generate pseudo-labels
python backend/pseudo_label_audio.py \
  --input-dir /path/to/unlabeled/audio \
  --confidence-threshold 0.8

# Step 2: Review results
head -20 "$SPEECH_DIR/pseudo_labeled_audio.csv"

# Step 3: Manually append pseudo-labeled rows to audio_labels.csv
# (use spreadsheet or Python script)

# Step 4: Retrain with pseudo-labels included
python backend/train_audio_model.py --with-pseudo


# ============================================================================
# OPTION 4: Conservative approach (high quality only)
# ============================================================================

python backend/pseudo_labeling_workflow.py \
  --input-dir /path/to/unlabeled/audio \
  --confidence-threshold 0.9 \
  --append-to-training \
  --retrain

# Only includes very high-confidence predictions


# ============================================================================
# OPTION 5: Process large dataset in chunks
# ============================================================================

# Process first 500 files only
python backend/pseudo_label_audio.py \
  --input-dir /path/to/unlabeled/audio \
  --confidence-threshold 0.8 \
  --max-samples 500

# Useful for testing or limits on time/computation


# ============================================================================
# VERIFICATION: Check pseudo-label quality
# ============================================================================

python3 << 'EOF'
import pandas as pd

import os

speech_dir = os.path.join(os.environ["DATASET_PATH"], "speech_data")
pseudo_df = pd.read_csv(os.path.join(speech_dir, "pseudo_labeled_audio.csv"))

print(f"Total pseudo-labeled: {len(pseudo_df)}")
print(f"\nLabel distribution:")
print(pseudo_df['cognitive_load'].value_counts())
print(f"\nConfidence stats:")
print(f"  Mean: {pseudo_df['confidence'].mean():.4f}")
print(f"  Std: {pseudo_df['confidence'].std():.4f}")
print(f"  Min: {pseudo_df['confidence'].min():.4f}")
print(f"  Max: {pseudo_df['confidence'].max():.4f}")
EOF


# ============================================================================
# DATA INTEGRATION: Append pseudo-labels to training CSV
# ============================================================================

python3 << 'EOF'
import pandas as pd

# Load data
import os

speech_dir = os.path.join(os.environ["DATASET_PATH"], "speech_data")
pseudo_df = pd.read_csv(os.path.join(speech_dir, "pseudo_labeled_audio.csv"))
train_df = pd.read_csv(os.path.join(speech_dir, "audio_labels.csv"))

# Filter by confidence if desired
high_conf = pseudo_df[pseudo_df['confidence'] >= 0.85]

# Convert to training format (filename -> path, cognitive_load -> label)
append_rows = []
for _, row in high_conf.iterrows():
    append_rows.append({
        'path': row['filename'],
        'label': row['cognitive_load']
    })

append_df = pd.DataFrame(append_rows)

# Combine
combined = pd.concat([train_df, append_df], ignore_index=True)

# Remove duplicates
combined = combined.drop_duplicates(subset=['path'], keep='first')

# Save
combined.to_csv(os.path.join(speech_dir, "audio_labels.csv"), index=False)

print(f"Original: {len(train_df)} samples")
print(f"Added: {len(append_df)} pseudo-labeled samples")
print(f"Total: {len(combined)} samples (deduplicated)")
EOF


# ============================================================================
# TRAINING: Retrain model with pseudo-labels
# ============================================================================

# Using pseudo-labeled data (if already appended to audio_labels.csv)
python backend/train_audio_model.py --with-pseudo

# Output will show composition:
#   Real labeled:    4900 samples
#   Pseudo-labeled:  1250 samples
#   Total:           6150 samples


# ============================================================================
# COMPARISON: Before vs After Pseudo-Labeling
# ============================================================================

# 1. Backup original model performance
cp models/audio_dt_model.joblib models/audio_dt_model.backup.joblib

# 2. Note original metrics (from previous training)
#    Original CV accuracy: 38.76% ± 4.39%

# 3. Generate pseudo-labels and retrain
python backend/pseudo_labeling_workflow.py \
  --input-dir /path/to/unlabeled/audio \
  --confidence-threshold 0.8 \
  --append-to-training \
  --retrain

# 4. Compare new metrics (printed in logs)
#    New CV accuracy: ?? ± ??


# ============================================================================
# TROUBLESHOOTING
# ============================================================================

# Problem: FileNotFoundError for model
# Solution: Ensure models/audio_dt_model.joblib exists
ls -la models/audio_dt_model.joblib

# Problem: No audio files found
# Solution: Check directory and file extensions
find /path/to/unlabeled/audio -name "*.wav" | head -5

# Problem: All predictions below confidence threshold
# Solution: Lower threshold
python backend/pseudo_label_audio.py \
  --input-dir /path/to/unlabeled/audio \
  --confidence-threshold 0.70

# Problem: MemoryError on large dataset
# Solution: Use max-samples to process in batches
python backend/pseudo_label_audio.py \
  --input-dir /path/to/unlabeled/audio \
  --max-samples 1000
