#!/usr/bin/env python3
"""
Pseudo-labeling pipeline for unlabeled audio data.

Loads trained audio model and predicts cognitive load labels for unlabeled audio.
Filters predictions by confidence threshold and outputs high-confidence results.

Usage:
    python pseudo_label_audio.py --input-dir /path/to/unlabeled/audio --confidence-threshold 0.8
"""

import os
import sys
import glob
import argparse
import json
import numpy as np
import pandas as pd
from pathlib import Path
import joblib

# Add backend to path for imports
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from audio_features import align_features_for_model, extract_features_from_path
from config import dataset_subpath


def load_trained_model(model_path):
    """Load trained audio XGBoost model."""
    if not os.path.exists(model_path):
        raise FileNotFoundError(f"Model not found: {model_path}")
    
    model_bundle = joblib.load(model_path)
    model = model_bundle.get("model")
    scaler = model_bundle.get("scaler")
    
    if model is None:
        raise ValueError("Model bundle missing 'model' key")
    if scaler is None:
        raise ValueError("Model bundle missing 'scaler' key")
    
    return model, scaler


def get_audio_files(directory, extensions=[".wav", ".mp3"]):
    """Recursively find audio files in directory."""
    audio_files = []
    for ext in extensions:
        pattern = os.path.join(directory, f"**/*{ext}")
        audio_files.extend(glob.glob(pattern, recursive=True))
    return sorted(audio_files)


def predict_cognitive_load(audio_file, model, scaler, debug: bool = False):
    """
    Extract features from audio and predict cognitive load.
    
    Returns:
        dict: {
            'filename': str,
            'predicted_label': str (Low/Medium/High),
            'predicted_code': int (0/1/2),
            'confidence': float,
            'probabilities': dict {label: prob},
            'error': str or None
        }
    """
    try:
        # Extract features
        features = extract_features_from_path(Path(audio_file))
        
        if features is None or len(features) == 0:
            return {
                'filename': os.path.basename(audio_file),
                'filepath': audio_file,
                'predicted_label': None,
                'predicted_code': None,
                'confidence': 0.0,
                'probabilities': {},
                'error': 'Feature extraction failed'
            }
        
        # Keep feature sizing consistent with training/inference even if the
        # extracted vector is shorter/longer for a given clip.
        features_aligned = align_features_for_model(features, scaler=scaler)
        features_scaled = scaler.transform([features_aligned])
        
        # Get predictions and probabilities
        prediction = model.predict(features_scaled)[0]
        probabilities = model.predict_proba(features_scaled)[0]
        confidence = np.max(probabilities)
        
        # Map to labels
        label_map = {0: "Low", 1: "Medium", 2: "High"}
        predicted_label = label_map.get(prediction, "Unknown")
        
        prob_dict = {
            label_map[i]: float(probabilities[i])
            for i in range(min(len(label_map), len(probabilities)))
        }

        if debug:
            print(
                f"[PRED DEBUG] file={os.path.basename(audio_file)} "
                f"pred={predicted_label} conf={float(confidence):.4f} probs={prob_dict}",
                flush=True,
            )
        
        return {
            'filename': os.path.basename(audio_file),
            'filepath': audio_file,
            'predicted_label': predicted_label,
            'predicted_code': int(prediction),
            'confidence': float(confidence),
            'probabilities': prob_dict,
            'error': None
        }
    
    except Exception as e:
        return {
            'filename': os.path.basename(audio_file),
            'filepath': audio_file,
            'predicted_label': None,
            'predicted_code': None,
            'confidence': 0.0,
            'probabilities': {},
            'error': str(e)
        }


def run_pseudo_labeling(
    input_dir,
    model_path="models/audio_dt_model.joblib",
    confidence_threshold=0.9,
    output_csv=None,
    max_samples=500,
    skip_samples=0,
    debug: bool = False,
):
    """
    Run pseudo-labeling on unlabeled audio files.
    
    Args:
        input_dir: Directory containing unlabeled audio files
        model_path: Path to trained model bundle
        confidence_threshold: Minimum confidence for including predictions (0.0-1.0)
        output_csv: Output CSV path for pseudo-labeled data
        max_samples: Limit number of files to process (None = all)
        skip_samples: Skip first N files after sorting (for batch processing)
    
    Returns:
        dict: Summary statistics
    """
    if output_csv is None:
        output_csv = str(dataset_subpath("speech_data", "pseudo_labeled_audio.csv"))

    print(f"\n{'='*70}")
    print(f"AUDIO PSEUDO-LABELING PIPELINE")
    print(f"{'='*70}")
    
    # Validate inputs
    if not os.path.isdir(input_dir):
        raise FileNotFoundError(f"Input directory not found: {input_dir}")
    
    # Load model
    print(f"\n📦 Loading model: {model_path}")
    model, scaler = load_trained_model(model_path)
    print(f"✓ Model loaded successfully")
    
    # Find audio files
    print(f"\n🔍 Scanning for audio files in: {input_dir}")
    audio_files = get_audio_files(input_dir)
    
    if skip_samples and skip_samples > 0:
        audio_files = audio_files[skip_samples:]

    if max_samples:
        audio_files = audio_files[:max_samples]
    
    print(f"✓ Found {len(audio_files)} audio files")
    
    if len(audio_files) == 0:
        print("⚠ No audio files found!")
        return {
            'total_files': 0,
            'high_confidence': 0,
            'low_confidence': 0,
            'errors': 0,
            'confidence_threshold': confidence_threshold,
            'output_file': output_csv
        }
    
    # Run inference
    print(f"\n🎯 Running inference (confidence threshold: {confidence_threshold})")
    print("-" * 70)
    
    results = []
    high_confidence_count = 0
    low_confidence_count = 0
    error_count = 0
    
    for i, audio_file in enumerate(audio_files, 1):
        result = predict_cognitive_load(audio_file, model, scaler, debug=debug)
        results.append(result)
        
        if result['error']:
            error_count += 1
            status = "❌ ERROR"
        elif result['confidence'] >= confidence_threshold:
            high_confidence_count += 1
            status = "✅ HIGH"
        else:
            low_confidence_count += 1
            status = "⚠️ LOW"
        
        # Progress indicator
        if i % 10 == 0 or i == len(audio_files):
            print(f"  [{i:4d}/{len(audio_files):4d}] {status} confidence: {result.get('confidence', 0.0):.4f}")
    
    print("-" * 70)
    
    # Filter to high-confidence predictions
    high_confidence_results = [
        r for r in results 
        if r['error'] is None and r['confidence'] >= confidence_threshold
    ]
    
    # Prepare output dataframe
    data_rows = []
    for result in high_confidence_results:
        # Extract speaker ID from filename (e.g., "F10_01_01.wav" -> "F10")
        filename = result['filename']
        speaker_id = filename.split('_')[0] if '_' in filename else 'Unknown'
        
        data_rows.append({
            'filename': filename,
            'filepath': result['filepath'],
            'cognitive_load': result['predicted_label'],
            'predicted_code': result['predicted_code'],
            'confidence': result['confidence'],
            'speaker_id': speaker_id,
            'source': 'pseudo_labeled'
        })
    
    pseudo_df = pd.DataFrame(data_rows)
    
    # Save output
    os.makedirs(os.path.dirname(output_csv), exist_ok=True)
    pseudo_df.to_csv(output_csv, index=False)
    
    # Print summary
    print(f"\n📊 PSEUDO-LABELING SUMMARY")
    print(f"{'='*70}")
    print(f"Total files processed:    {len(audio_files)}")
    print(f"High confidence (≥{confidence_threshold}):  {high_confidence_count} ({high_confidence_count/len(audio_files)*100:.1f}%)")
    print(f"Low confidence (<{confidence_threshold}):  {low_confidence_count} ({low_confidence_count/len(audio_files)*100:.1f}%)")
    print(f"Errors:                   {error_count} ({error_count/len(audio_files)*100:.1f}%)")
    print(f"\n✅ Pseudo-labeled samples: {len(pseudo_df)}")
    print(f"📁 Output saved: {output_csv}")
    
    if len(pseudo_df) > 0:
        print(f"\n📈 Label distribution:")
        label_counts = pseudo_df['cognitive_load'].value_counts()
        for label, count in label_counts.items():
            pct = count / len(pseudo_df) * 100
            print(f"  {label:8s}: {count:4d} ({pct:5.1f}%)")
        
        print(f"\n📊 Confidence statistics:")
        print(f"  Mean:     {pseudo_df['confidence'].mean():.4f}")
        print(f"  Std:      {pseudo_df['confidence'].std():.4f}")
        print(f"  Min:      {pseudo_df['confidence'].min():.4f}")
        print(f"  Max:      {pseudo_df['confidence'].max():.4f}")
    
    print(f"\n" + "="*70)
    print(f"Next step: Review pseudo-labeled data, then append to audio_labels.csv")
    print(f"="*70 + "\n")
    
    return {
        'total_files': len(audio_files),
        'high_confidence': high_confidence_count,
        'low_confidence': low_confidence_count,
        'errors': error_count,
        'pseudo_labeled_count': len(pseudo_df),
        'confidence_threshold': confidence_threshold,
        'output_file': output_csv,
        'dataframe': pseudo_df
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Pseudo-label unlabeled audio using trained model"
    )
    parser.add_argument(
        "--input-dir",
        required=True,
        help="Directory containing unlabeled audio files"
    )
    parser.add_argument(
        "--model-path",
        default="models/audio_dt_model.joblib",
        help="Path to trained model bundle"
    )
    parser.add_argument(
        "--confidence-threshold",
        type=float,
        default=0.9,
        help="Minimum confidence for including predictions (0.0-1.0)"
    )
    parser.add_argument(
        "--output-csv",
        default=str(dataset_subpath("speech_data", "pseudo_labeled_audio.csv")),
        help="Output CSV path for pseudo-labeled data"
    )
    parser.add_argument(
        "--max-samples",
        type=int,
        default=500,
        help="Limit number of files to process (None = all)"
    )
    parser.add_argument(
        "--skip-samples",
        type=int,
        default=0,
        help="Skip first N files after sorting (for batch processing)"
    )
    parser.add_argument(
        "--debug",
        action="store_true",
        help="Print per-file predicted class probabilities and confidence"
    )
    
    args = parser.parse_args()
    
    summary = run_pseudo_labeling(
        input_dir=args.input_dir,
        model_path=args.model_path,
        confidence_threshold=args.confidence_threshold,
        output_csv=args.output_csv,
        max_samples=args.max_samples,
        skip_samples=args.skip_samples,
        debug=args.debug,
    )
