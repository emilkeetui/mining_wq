---
name: review-python
description: Run the Python pipeline review protocol on data pipeline scripts. Checks CRS consistency, parquet schema, raw_data protection, and reproducibility. Produces a report without editing files.
argument-hint: "[filename or 'all']"
allowed-tools: ["Read", "Grep", "Glob", "Write", "Task"]
---

# Review Python Pipeline Scripts

Run the comprehensive Python code review protocol for the data pipeline scripts.

## Steps

1. **Identify scripts to review:**
   - If `$ARGUMENTS` is a specific filename: review that file only
   - If `$ARGUMENTS` is `all`: review all `.py` files in `code/coal_mining_water_quality/`

2. **Read `.claude/rules/python-code-conventions.md`** for current project standards.

3. **For each script, launch the `python-pipeline-reviewer` agent** with the full path,
   instructing it to:
   - Follow the 10-category review protocol in the agent file
   - Pay special attention to: parquet schema (PWSID str, year int64, engine="pyarrow"),
     CRS assertion before spatial joins, no writes to raw_data/
   - Save report to `.claude/logs/[script-name]-py-review.md`

4. **After all reviews complete**, present a summary:
   - Total issues per script
   - Breakdown: Critical / Major / Minor
   - Top issues to fix first

5. **IMPORTANT: Do NOT edit any Python source files.** Report only. Fixes applied after user review.

## Report Format

```
Python Pipeline Review: [script-name]
Date: YYYY-MM-DD
Score: XX/100

Critical Issues (block commit):
  - [location]: [issue] → [suggested fix]

Major Issues (block peer-review):
  - [location]: [issue] → [suggested fix]

Minor Issues:
  - [location]: [issue] → [suggested fix]

Passed checks:
  ✓ [check name]
```
