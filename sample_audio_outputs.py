#!/usr/bin/env python3
"""
Sample Audio Analysis Output Generator
Shows example fluency scores and confidence values for testing
"""

import random
import json
from typing import Dict, Any

def generate_sample_audio_analysis() -> Dict[str, Any]:
    """Generate a sample audio analysis result with random but realistic values"""

    # Random fluency score (30-90 scale, as per model)
    fluency_score_raw = random.uniform(30.0, 90.0)

    # Normalized score (0-100 scale)
    fluency_score_normalized = (fluency_score_raw - 30.0) / 60.0 * 100.0

    # Fluency labels based on score ranges
    if fluency_score_raw >= 70.0:
        label = "High Fluency"
    elif fluency_score_raw >= 50.0:
        label = "Medium Fluency"
    else:
        label = "Low Fluency"

    # Confidence metrics
    confidence = random.uniform(0.4, 0.95)  # Top probability
    confidence_entropy = random.uniform(20.0, 80.0)  # Distribution-aware confidence

    # Confidence label
    if confidence_entropy >= 60.0:
        confidence_label = "High Confidence"
    elif confidence_entropy >= 40.0:
        confidence_label = "Moderate Confidence"
    else:
        confidence_label = "Low Confidence"

    # Breakdown metrics
    speed_score = random.uniform(30.0, 90.0)
    clarity_score = random.uniform(30.0, 90.0)

    # Probabilities for 3 classes (Low/Medium/High)
    probs = [random.random() for _ in range(3)]
    total = sum(probs)
    probs = [p/total for p in probs]  # Normalize

    result = {
        "fluency_score": round(fluency_score_normalized, 1),
        "fluency_score_raw": round(fluency_score_raw, 1),
        "fluency_label": label,
        "confidence": round(confidence, 3),
        "confidence_entropy": round(confidence_entropy, 1),
        "confidence_label": confidence_label,
        "confidence_hint": "Sample analysis - confidence based on audio quality",
        "confidence_raw": round(confidence, 3),
        "confidence_margin": round(random.uniform(0.1, 0.5), 3),
        "top_probability": round(max(probs), 3),
        "breakdown": {
            "speed": round(speed_score, 1),
            "clarity": round(clarity_score, 1),
            "confidence": round(confidence_entropy, 1),
        },
        "probabilities": {
            "Low Fluency": round(probs[0], 3),
            "Medium Fluency": round(probs[1], 3),
            "High Fluency": round(probs[2], 3),
        },
        "valid": True,
        "low_confidence": confidence < 0.6,
        "silence_detected": False,
    }

    return result

def main():
    print("🎤 Sample Audio Analysis Results")
    print("=" * 50)

    for i in range(5):
        print(f"\n📊 Sample Analysis #{i+1}")
        print("-" * 30)
        result = generate_sample_audio_analysis()

        print(f"Fluency Score: {result['fluency_score']}/100 ({result['fluency_label']})")
        print(f"Raw Score: {result['fluency_score_raw']}/90")
        print(f"Confidence: {result['confidence_label']} ({result['confidence_entropy']}/100)")
        print(f"Breakdown:")
        print(f"  - Speed: {result['breakdown']['speed']}")
        print(f"  - Clarity: {result['breakdown']['clarity']}")
        print(f"Probabilities: {result['probabilities']}")

        # Show JSON format
        print(f"\n📝 JSON Response:")
        print(json.dumps(result, indent=2))
        print()

if __name__ == "__main__":
    main()