---
description: "Run the standard EEG training and evaluation workflow and summarize outputs, warnings, and next actions. Use for model refresh, regression checks, and report generation."
name: "Train And Evaluate Models"
argument-hint: "Optional: preview EDF path or focus area"
agent: "agent"
---
Run the project's training and evaluation workflow safely and summarize actionable outcomes.

## Task
1. Read current project instructions and verify expected commands.
2. If the user provided a preview EDF path in input, run:
   - bash backend/run_all.sh --preview <path>
3. Otherwise run:
   - bash backend/run_all.sh
4. If run_all.sh cannot be used, fall back to:
   - python backend/train_eeg_from_edf.py
   - python backend/model_evaluation.py
5. Summarize key outputs from:
   - model_reports/model_evaluation_report.json
   - model_reports/MODEL_EVALUATION_SUMMARY.md

## Output Format
- Commands executed
- Success/failure status
- Key model metrics snapshot
- Any data/schema/environment warnings
- Recommended next actions

## Constraints
- Do not change production deployment settings.
- Keep changes local and reversible.
- If prerequisites are missing, report exact blocker and minimal fix steps.
