#!/usr/bin/env python
"""Utility script to load and inspect joblib model files."""

import joblib

from utils.paths import get_models_dir

def load_and_inspect_model(filename):
    """Load a joblib file and print its contents."""
    filepath = get_models_dir() / filename
    
    print(f"\n{'='*60}")
    print(f"Loading: {filename}")
    print(f"Path: {filepath}")
    print(f"{'='*60}")
    
    try:
        obj = joblib.load(filepath)
        print(f"✓ Successfully loaded!")
        print(f"Type: {type(obj)}")
        
        if isinstance(obj, dict):
            print(f"Dictionary with keys: {list(obj.keys())}")
            for key, value in obj.items():
                print(f"  - {key}: {type(value).__name__}")
                if hasattr(value, 'get_params'):
                    print(f"    Parameters: {value.get_params()}")
        else:
            print(f"Object attributes: {dir(obj)}")
            if hasattr(obj, 'get_params'):
                print(f"Model parameters: {obj.get_params()}")
        
        return obj
    except Exception as e:
        print(f"✗ Error loading file: {e}")
        import traceback
        traceback.print_exc()
        return None

def main():
    """Load all models and display information."""
    models = [
        "eeg_model.pkl",
        "eeg_cognitive_model.joblib",
        "audio_fluency_model.joblib",
        "audio_dt_model.joblib",
        "behavioral_model.joblib",
        "behavioral_model.pkl",
    ]
    
    print("\n" + "="*60)
    print("JOBLIB MODEL LOADER")
    print("="*60)
    print(f"Models directory: {get_models_dir()}")
    
    loaded_models = {}
    for model_file in models:
        obj = load_and_inspect_model(model_file)
        if obj is not None:
            loaded_models[model_file] = obj
    
    print("\n" + "="*60)
    print(f"Summary: {len(loaded_models)}/{len(models)} models loaded successfully")
    print("="*60 + "\n")
    
    return loaded_models

if __name__ == "__main__":
    models = main()
