# Pseudo-Labeling Pipeline Guide

## Overview

The pseudo-labeling system uses your trained audio XGBoost model to predict cognitive load labels for **unlabeled audio datasets**. This allows you to automatically expand your training data with high-confidence predictions.

**Key benefits:**
- 🚀 Expand training dataset without manual labeling
- 🔒 Built-in confidence filtering to ensure quality
- 📊 Track which samples are real vs. pseudo-labeled
- 🔄 Iterative model improvement through semi-supervised learning

## Architecture

### Three Main Components

1. **`pseudo_label_audio.py`** - Core inference pipeline
   - Loads trained model and scaler
   - Extracts audio features for unlabeled files
   - Generates predictions with confidence scores
   - Filters by confidence threshold
   - Outputs high-confidence predictions to CSV

2. **`pseudo_labeling_workflow.py`** - Orchestration script
   - Manages complete end-to-end workflow
   - Optionally appends pseudo-labels to training CSV
   - Optionally retrains model with expanded data
   - Provides detailed statistics and progress

3. **`train_audio_model.py`** (updated) - Training with pseudo-labels
   - Loads both real labeled and pseudo-labeled data
   - Maintains speaker-aware grouping for both
   - Tracks data sources (real vs. pseudo)
   - Same tuning and evaluation as before

## Quick Start

### Step 1: Generate Pseudo-Labels

```bash
python backend/pseudo_label_audio.py \
  --input-dir /path/to/unlabeled/audio \
  --confidence-threshold 0.8 \
  --output-csv Dataset/speech_data/pseudo_labeled_audio.csv
```

**Output:** CSV with predicted labels and confidence scores

### Step 2: Review Results

```bash
# Check pseudo-labeled data
head -20 Dataset/speech_data/pseudo_labeled_audio.csv
```

Example output:
```
filename,filepath,cognitive_load,confidence,speaker_id,source
T0003G0036S0001.wav,/path/to/T0003G0036S0001.wav,Medium,0.8945,T0003,pseudo_labeled
T0003G4011S0001.wav,/path/to/T0003G4011S0001.wav,Low,0.9234,T0003,pseudo_labeled
```

### Step 3: Append to Training Data (Manual or Automatic)

**Option A: Manual inspection first**
```bash
# Just generate pseudo-labels, no automatic append
python backend/pseudo_label_audio.py \
  --input-dir /path/to/unlabeled/audio \
  --confidence-threshold 0.8

# Manually review: Dataset/speech_data/pseudo_labeled_audio.csv
# Then manually append rows to Dataset/speech_data/audio_labels.csv
```

**Option B: Automatic workflow**
```bash
python backend/pseudo_labeling_workflow.py \
  --input-dir /path/to/unlabeled/audio \
  --confidence-threshold 0.8 \
  --append-to-training
```

### Step 4: Retrain Model

```bash
# Retrain with pseudo-labeled samples included
python backend/train_audio_model.py --with-pseudo
```

Or use the workflow script for full automation:
```bash
python backend/pseudo_labeling_workflow.py \
  --input-dir /path/to/unlabeled/audio \
  --confidence-threshold 0.8 \
  --append-to-training \
  --retrain
```

## Detailed Configuration

### Confidence Threshold

Controls which predictions to include (0.0 to 1.0):

```
Threshold  |  Impact
-----------+------------------
   0.5     |  Include most predictions (noisy)
   0.7     |  Balanced (recommended default)
   0.8     |  Conservative (high quality)
   0.9     |  Very strict (few samples)
   1.0     |  Only 100% confident (rare)
```

**Recommendation:** Start with `0.8` and adjust based on label distribution.

### Limiting Processing

For large datasets, use `--max-samples`:

```bash
python backend/pseudo_label_audio.py \
  --input-dir /path/to/unlabeled/audio \
  --max-samples 500
```

## Output Files

### Main Output: `pseudo_labeled_audio.csv`

```csv
filename,filepath,cognitive_load,confidence,speaker_id,source
F10_01_01.wav,Dataset/speech_data/F10_01_01.wav,Low,0.8234,F10,pseudo_labeled
F10_02_01.wav,Dataset/speech_data/F10_02_01.wav,Medium,0.9123,F10,pseudo_labeled
```

**Columns:**
- `filename`: Audio file name
- `filepath`: Full path to audio file
- `cognitive_load`: Predicted label (Low/Medium/High)
- `confidence`: Model confidence (0.0-1.0)
- `speaker_id`: Extracted from filename for grouping
- `source`: Always "pseudo_labeled"

### Training Data: `audio_labels.csv` (updated)

When pseudo-labels are appended:
```csv
path,label
F10_01_01.wav,Low
F10_02_01.wav,Medium
existing_samples_remain_here,...,...
```

## Quality Control

### Checking Pseudo-Label Distribution

```python
import pandas as pd

pseudo_df = pd.read_csv("Dataset/speech_data/pseudo_labeled_audio.csv")

# Label distribution
print(pseudo_df['cognitive_load'].value_counts())

# Confidence statistics
print(f"Mean confidence: {pseudo_df['confidence'].mean():.4f}")
print(f"Min confidence: {pseudo_df['confidence'].min():.4f}")
print(f"Max confidence: {pseudo_df['confidence'].max():.4f}")

# Low-confidence samples (for manual review)
low_conf = pseudo_df[pseudo_df['confidence'] < 0.75]
print(f"Low-confidence samples: {len(low_conf)}")
```

### Verifying Speaker Distribution

```python
# Check speaker diversity
print(pseudo_df['speaker_id'].nunique())
print(pseudo_df.groupby('speaker_id')['cognitive_load'].value_counts())
```

## Common Workflows

### Scenario 1: Add Nexdata Dataset

```bash
# 1. Download Nexdata samples to local directory
# (e.g., Dataset/nexdata_samples/)

# 2. Pseudo-label all Nexdata samples
python backend/pseudo_label_audio.py \
  --input-dir Dataset/nexdata_samples \
  --confidence-threshold 0.85 \
  --output-csv Dataset/speech_data/pseudo_labeled_nexdata.csv

# 3. Review pseudo-labeled results
# ... check confidence, label distribution, etc.

# 4. Append to training
python backend/pseudo_labeling_workflow.py \
  --input-dir Dataset/nexdata_samples \
  --confidence-threshold 0.85 \
  --append-to-training \
  --retrain
```

### Scenario 2: Iterative Improvement

```bash
# Initial training (current)
python backend/train_audio_model.py

# Add 500 unlabeled samples with high confidence
python backend/pseudo_labeling_workflow.py \
  --input-dir new_unlabeled_dir \
  --confidence-threshold 0.9 \
  --max-samples 500 \
  --append-to-training \
  --retrain

# Compare metrics before/after
```

### Scenario 3: Mixed Data (Manual Append)

```bash
# Generate pseudo-labels
python backend/pseudo_label_audio.py \
  --input-dir Dataset/nexdata_samples \
  --confidence-threshold 0.8

# Manually filter pseudo_labeled_audio.csv to highest-quality samples
# Only keep confidence >= 0.95 rows

# Manually append to audio_labels.csv in spreadsheet or script

# Retrain
python backend/train_audio_model.py --with-pseudo
```

## Model Training with Mixed Data

When `--with-pseudo` is used:

1. **Data loading:**
   - Real labeled samples from `audio_labels.csv`
   - Pseudo-labeled samples from `pseudo_labeled_audio.csv`
   - Both tracked separately

2. **Training output includes:**
   ```
   📊 Training data composition:
     Real labeled:    4900 samples
     Pseudo-labeled:  1250 samples
     Total:           6150 samples
   
   Train data: 4920 real + 1000 pseudo
   ```

3. **Same methodology applied:**
   - Speaker-aware grouped CV
   - Class balancing
   - Hyperparameter tuning
   - Comprehensive metrics

## Troubleshooting

### Problem: "No high-confidence predictions"

**Cause:** Model predicts with low confidence on the dataset
**Solutions:**
- Lower confidence threshold: `--confidence-threshold 0.7`
- Check if unlabeled data matches training domain
- Verify unlabeled audio quality (sample rate, duration)

### Problem: "FeatureExtractionError" on some files

**Cause:** Some audio files corrupt or wrong format
**Solution:** Filter input directory to valid audio:
```bash
# Only process .wav files
find Dataset/nexdata_samples -name "*.wav" > valid_files.txt
```

### Problem: Label distribution is imbalanced after pseudo-labeling

**Cause:** Model biased toward majority class
**Solutions:**
- Use `--confidence-threshold 0.9` for rare classes
- Manually filter pseudo-labels by class
- Use weighted sampling during retraining

## Performance Monitoring

### Metrics to Track

```python
import json

# Load model bundle
import joblib
bundle = joblib.load("models/audio_dt_model.joblib")

# Check if trained with pseudo-labels
print(bundle.get("trained_with_pseudo_labels", False))
```

### A/B Testing

Compare models:
1. **Before pseudo-labeling:**
   - CV accuracy (real data only): 38.76%
   - Test accuracy: ~42%

2. **After pseudo-labeling:**
   - CV accuracy (mixed data): ?%
   - Test accuracy: ?%

## Advanced Usage

### Custom Feature Extraction

To use different audio features for pseudo-labeling:

```python
# Modify audio_features.py
# Then pseudo-labeling will automatically use new features

python backend/pseudo_label_audio.py \
  --input-dir Dataset/nexdata_samples \
  --confidence-threshold 0.8
```

### Confidence Calibration

If pseudo-labels are too uncertain:

```python
# Increase confidence by model refinement
# (advanced: requires model surgery)
```

## Best Practices

1. **Start conservative:** Use `--confidence-threshold 0.85-0.9`
2. **Review before appending:** Always inspect `pseudo_labeled_audio.csv` first
3. **Monitor metrics:** Compare CV scores before/after pseudo-labeling
4. **Diverse sources:** Mix pseudo-labels from multiple datasets
5. **Iterative:** Run multiple cycles of pseudo-labeling for continuous improvement
6. **Speaker balance:** Ensure pseudo-labeled data has diverse speakers

## API Reference

### `pseudo_label_audio.py`

```python
from pseudo_label_audio import run_pseudo_labeling

summary = run_pseudo_labeling(
    input_dir="/path/to/unlabeled",
    model_path="models/audio_dt_model.joblib",
    confidence_threshold=0.8,
    output_csv="Dataset/speech_data/pseudo_labeled_audio.csv",
    max_samples=None
)
```

### `pseudo_labeling_workflow.py`

```python
from pseudo_labeling_workflow import (
    run_full_workflow,
    append_pseudo_labels_to_training_data,
    retrain_model_with_pseudo_labels
)

run_full_workflow(
    unlabeled_dir="/path/to/unlabeled",
    confidence_threshold=0.8,
    append_to_training=True,
    retrain=True
)
```

### `train_audio_model.py`

```python
from train_audio_model import train_audio_model

train_audio_model(include_pseudo_labeled=True)
```

## References

- Pseudo-labeling: https://en.wikipedia.org/wiki/Semi-supervised_learning
- Self-training: https://scikit-learn.org/stable/modules/semi_supervised.html
- Your model documentation: See `MODEL_EVALUATION_SUMMARY.md`

---

**Last Updated:** March 2026
**Pipeline Status:** ✅ Production Ready
