#!/usr/bin/env python3
"""Prepare training manifest from processed audio scores."""

import pandas as pd
from pathlib import Path

# Load the processed audio data
csv_path = Path('Dataset/processed_audio_sample_scoring.csv')
df = pd.read_csv(csv_path)

# Convert Fluency score (0-100) to class (0=Low, 1=Medium, 2=High)
def fluency_to_class(score):
    score = float(score)
    if score <= 33:
        return 0  # Low
    elif score <= 66:
        return 1  # Medium
    else:
        return 2  # High

df['label'] = df['Fluency'].apply(fluency_to_class)

# Create manifest with just path and label
manifest = df[['Record Audio Name', 'label']].copy()
manifest.columns = ['path', 'label']

# Prepend 'Dataset/speech_data/' and append '.m4a' to paths
manifest['path'] = 'Dataset/speech_data/' + manifest['path'].astype(str) + '.m4a'

# Save manifest
manifest.to_csv('Dataset/audio_training_manifest.csv', index=False)

# Print stats
print('Manifest created: Dataset/audio_training_manifest.csv')
print('Total samples:', len(manifest))
print('Low (0):', (manifest['label'] == 0).sum())
print('Medium (1):', (manifest['label'] == 1).sum())
print('High (2):', (manifest['label'] == 2).sum())
print()
print('First 5 rows:')
print(manifest.head())
