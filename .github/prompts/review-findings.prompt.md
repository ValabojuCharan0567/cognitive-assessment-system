---
description: "Generate severity-ordered code review findings for selected files or recent changes. Use for bug/risk detection, regression checks, and test-gap review."
name: "Review Findings"
argument-hint: "Optional: files, module, or risk focus"
agent: "agent"
---
Produce a code review focused on defects and risk, not style.

## Input Handling
- If the user provides input, treat it as scope and priorities.
- If no input is provided, review the most relevant current workspace changes.
- Prefer high-signal files first (core logic, API boundaries, data/schema code).

## Review Goals
1. Find real bugs and behavioral regressions.
2. Identify security, data-integrity, and reliability risks.
3. Call out missing tests for risky paths.

## Output Format
1. Findings (ordered by severity, highest first)
- Severity: Critical | High | Medium | Low
- Location: file path and line reference
- Why it matters: concrete user/system impact
- Evidence: brief code-based reasoning
- Fix direction: minimal safe change
2. Open questions or assumptions
3. Brief change-risk summary

## Constraints
- Prioritize correctness over stylistic preferences.
- Avoid speculative issues without evidence.
- Be concise and specific.