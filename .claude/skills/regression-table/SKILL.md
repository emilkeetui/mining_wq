---
name: regression-table
description: Run regression table script (run_main_tables.r or specified script), verify LaTeX output in output/reg/, check column labels against CLAUDE.md spec, and report pass/fail with first-stage F-stat.
argument-hint: "[script name, default: run_main_tables.r] [optional: specific table name]"
allowed-tools: ["Bash", "Read", "Grep"]
---

# Regression Table Workflow

Run the regression script, verify the LaTeX output, and confirm the table meets the
econometric quality standard defined in `.claude/rules/quality-gates.md`.

**Input:** `$ARGUMENTS` — script name (default: `run_main_tables.r`) and optionally a
specific table name to check (e.g., `2sls_nitrates_downstream`).

---

## Steps

### Step 1: Run the Script

```bash
"Z:/R/R-4.5.2/bin/x64/Rscript.exe" --vanilla code/coal_mining_water_quality/${SCRIPT:-run_main_tables.r}
```

Capture exit code. If non-zero: report the error and stop.

### Step 2: Confirm Output Exists

```bash
ls output/reg/*.tex | sort -t/ -k3 | tail -10
```

Confirm expected `.tex` files were created or updated.

### Step 3: Check Table Content

For each newly generated `.tex` file:

1. **Column headers** — confirm they match CLAUDE.md sample-cut definitions:
   - Colocated: `minehuc_mine == 1 & minehuc_downstream_of_mine == 0`
   - Downstream: `minehuc_downstream_of_mine == 1 & minehuc_mine == 0`
   - Colocated + downstream: `minehuc_upstream_of_mine == 0`

2. **Sample size footnote** — confirm N is present and plausible (thousands)

3. **First-stage F-statistic** — grep for it:
   ```bash
   grep -i "F-stat\|first.stage\|weak" output/reg/<table>.tex
   ```
   Flag if missing or < 10.

4. **Coefficient signs** — for 2SLS on mining-related outcomes: coefficient on
   `num_coal_mines_unified` should be positive (more mining → more violations)

5. **Stars legend** — confirm `*** p<0.01, ** p<0.05, * p<0.1`

### Step 4: Report

```
Regression Table Report
─────────────────────────────
Script:    [script name]
Exit code: 0 ✓

Tables generated:
  output/reg/[name].tex
    Columns:    [list]
    N:          [value] ✓ / [MISSING]
    F-stat:     [value] ✓ / [< 10 — weak instrument warning]
    Signs:      [pass / flag: unexpected negative on mining coef]
    Quality:    [score]/100

Overall: PASS / FAIL
Issues:  [list any]
```
