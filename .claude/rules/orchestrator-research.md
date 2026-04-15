# Orchestrator Protocol: Research Mode

**After a plan is approved, implement autonomously. Surface only genuine decision points.**

## The Loop

```
Plan approved → orchestrator activates
  │
  Step 1: IMPLEMENT — execute plan steps in order
  │
  Step 2: RUN — execute the script(s) end-to-end
  │         R:      Rscript --vanilla code/coal_mining_water_quality/script.r
  │         Python: "Z:/.../python.exe" code/coal_mining_water_quality/script.py
  │
  Step 3: CHECK OUTPUT
  │         • Script exits 0 (no error)
  │         • Expected output file exists in clean_data/ or output/
  │         • Row counts are plausible (not 0, not suspiciously small)
  │         • No NaN leakage in key columns (PWSID, year, outcome vars)
  │
  Step 4: FIX (if Step 3 fails)
  │         Diagnose → fix → re-run (back to Step 2)
  │         Max 3 fix loops before surfacing to user
  │
  Step 5: SCORE — apply quality-gates.md rubric
  │
  └── Score ≥ 80?
        YES → present summary to user
        NO  → fix critical issues → re-run → re-score (max 3 total rounds)
              After max rounds → present with remaining issues listed
```

## Regression Table Checks (Step 3, extended)

After generating a `.tex` table in `output/reg/`:
1. Column headers match the CLAUDE.md sample-cut definitions
2. Sample size in the footnote is plausible (thousands of observations, not zero)
3. The 2SLS coefficient on `num_coal_mines_unified` has the expected sign
   (positive for mining-related outcomes; near-zero for placebo outcomes)
4. The first-stage F-statistic is reported and is > 10 (weak instrument check)

## Decision Points — Stop and Ask

Stop and ask the user when:
- Fix loop hits 3 iterations without resolving the error
- Output row count is 0 or < 100 (likely a merge failure)
- A coefficient has a strongly unexpected sign in a main spec (not placebo)
- A file that should not be overwritten exists at the output path

## "Just Do It" Mode

When user says "just do it" / "handle it" / "go ahead":
- Skip final approval pause
- Run the full implement → run → check → fix loop
- Present a summary when done (output path, row counts, quality score)
