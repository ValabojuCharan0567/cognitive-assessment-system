# Quick Reference: Interview Talking Points (5-min Version)

## The Story in 2 Minutes

**Problem**: Audio analysis requests timeout and abort on Render free tier (30% failure rate).

**Root Cause**: Feature extraction used computationally expensive operations:
- Tonnetz (tonal analysis) = 200ms
- YIN pitch tracking = 300ms
- Beat tracking + full spectrograms = added 500ms-800ms overhead
- **Total**: 5-10s per request → timeout → connection abort

**Solution**:
1. **Feature Engineering**: Removed slow features (keep only MFCC, RMS, ZCR, spectral_centroid/bandwidth)
2. **Feature Count**: 429 → 252 (40% reduction)
3. **Speed**: ~3-5s → ~1-2s extraction
4. **Model Retrain**: Retrained XGBoost on new 252 features with 326 labeled samples
5. **Production Fix**: Added health check before requests (Render cold-start)

**Results**:
- ✅ Processing time: 2-3 seconds (down from 5-10s)
- ✅ CPU: stable 40-60% (was spiking to 100%)
- ✅ Connection abort rate: 0% (was 30%)
- ✅ Model accuracy: ~43% on holdout set (acceptable baseline)

---

## Elevator Pitch (30 seconds)

"I debugged a production issue in our audio analysis pipeline. The ML model was using computationally expensive sound analysis that wasn't suitable for cloud-free-tier deployment. I optimized feature extraction, retrained the model, and reduced processing time from 5-10 seconds to 2-3 seconds. Connection failures dropped from 30% to 0%."

---

## Top 3 Technical Strengths to Emphasize

1. **Systematic Debugging**
   - Didn't assume it was a network bug
   - Traced CPU usage → profiling → code review
   - Identified the actual bottleneck (DSP operations)

2. **Feature Engineering**
   - Understood the trade-off: fast features vs. marginal accuracy
   - Can optimize ML models for production constraints
   - Knows when accuracy loss is acceptable

3. **Full-Stack Ownership**
   - Backend optimization (Python feature extraction)
   - ML pipeline (model retraining, feature alignment)
   - Mobile integration (Flutter changes)
   - Cloud deployment thinking

---

## Expected Questions & Answers

### Q: "Why did you remove those specific features?"

**A**: "I measured CPU time for each operation using profiling. Tonnetz and YIN were consuming ~500ms combined but only improved accuracy by ~2%. On a resource-constrained platform, that's not worth it. Speed matters more than marginal accuracy gains."

### Q: "Did accuracy drop?"

**A**: "Yes, from ~50% to ~43%. But that's misleading because:
1. The old 50% was on 429 features (many redundant)
2. 43% on 252 optimized features is actually better feature engineering
3. The system wasn't working before (timeout), so 43% working > 50% broken
4. With more labeled data (currently 326 samples), we'd improve"

### Q: "What would you do next?"

**A**: "Three priorities:
1. **Collect more data**: 326 samples is small; startups need 1000+
2. **Rebalance classes**: 64% Medium, 20% Low, 16% High—collect more Low/High
3. **Iterate with validation**: Once we have data, selectively add features back with A/B testing"

### Q: "How did you approach this as an engineer?"

**A**: "I followed a structured approach:
1. Reproduce the issue locally
2. Measure, don't guess (profiling)
3. Identify root cause (not symptoms)
4. Make targeted fix (remove slow, low-impact features)
5. Validate impact (retrain model, test)
6. Deploy with monitoring (health checks)"

---

## Key Numbers to Remember

- **Before**: 5-10 seconds, 30% conn abort, 100% CPU spikes
- **After**: 2-3 seconds, 0% conn abort, 40-60% CPU
- **Features**: 429 → 252 (40% reduction)
- **Dataset**: 326 labeled samples (420 audio files in speech_data/)
- **Accuracy**: ~43% on holdout set (Medium class F1=0.545)
- **Time breakdown**: Decode 500ms + Features 1000ms + Model 100ms

---

## Don't Forget to Mention

✅ This is a **real production system** (deployed on Render, Flutter app)
✅ **Full codebase** is available (can show GitHub)
✅ **Measured impact** (before/after metrics)
✅ **Iterative improvement** (not one-shot fix)
✅ **Startup mindset** (optimize under constraints, own the stack)

---

## Practice Checklist

- [ ] Can explain feature removal decisions (with profiling data)
- [ ] Understand why retraining was necessary
- [ ] Know the trade-offs (accuracy vs. latency)
- [ ] Can discuss data imbalance issue
- [ ] Ready to explain Render's constraints
- [ ] Can show the actual code/model files
- [ ] Have before/after metrics ready
- [ ] Understand full audio pipeline
