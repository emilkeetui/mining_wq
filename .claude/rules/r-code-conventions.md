# R Code Conventions

## Header Block (required on every script)

```r
# ============================================================
# Script: [name].r
# Purpose: [one-line description]
# Inputs: [files read]
# Outputs: [files written]
# Author: EK  Date: YYYY-MM-DD
# ============================================================
```

## Naming and Style

- Snake_case for all object and variable names — no camelCase
- Variable names must match the CLAUDE.md glossary exactly (e.g., `sulfur_unified`, not `avg_sulfur`)
- No hardcoded absolute paths — use paths relative to the project root or passed as arguments
- `set.seed()` required in any script that uses randomness
- Match the style of surrounding code — indentation, spacing, naming patterns

## Parquet I/O

- **Read:** `arrow::read_parquet(path)`
- **Write:** `arrow::write_parquet(df, path)`
- Never use `read_csv()` / `write_csv()` for main analysis datasets
- Intermediate R-only outputs: save as `.rds` with `saveRDS()` / `readRDS()`

**Cross-language schema check:** when reading a parquet written by a Python script,
immediately confirm types after loading:
```r
df <- arrow::read_parquet("clean_data/cws_data/prod_vio_sulfur.parquet")
str(df)  # PWSID must be <chr>, year must be <int>
```
If PWSID is integer, the merge with SDWIS will silently fail. Stop and fix the Python
writer before proceeding.

## Regression Style

- Keep `feols()` formula objects named for reuse:
  ```r
  fml_main  <- viol ~ num_coal_mines_unified + num_facilities | PWSID + year + state
  fml_iv    <- viol ~ num_facilities | PWSID + year + state | num_coal_mines_unified ~ post95:sulfur_unified
  ```
- Line-length exceptions for regression formulas — long formulas do not need line breaks
- SEs clustered at PWSID level: `cluster = ~ PWSID`
- Always use `fixest::feols()`; never `lm()` for panel regressions
- When the dependent variable is a 0/1 indicator, scale displayed
  coefficients and SEs by 100 (percentage-point units) before rendering —
  see `table-figure-formatting.md` Rule 6

## Output

- Regression tables to `output/reg/*.tex` via `etable()` or `modelsummary()`
- Figures to `output/fig/*.png` — publication-ready, no titles unless necessary,
  informative axis labels, no gridlines on coefficient plots
- Summary statistics to `output/sum/*.tex`
- Table notes for any table `\input{}`'d into `main.tex`'s body must follow
  `table-notes-conventions.md` (starts with `\textit{Notes:}`, no variable
  names, no cross-references, no file paths, no individual sample IDs, stars
  legend on regressions, no FE discussion when FE rows are shown, no
  sample-cleaning narration, no robustness-check labeling)
- All tables and figures must follow `table-figure-formatting.md`:
  left-justified notes/captions, no scientific notation, consistent
  significant figures within a table, decimal-aligned numeric columns,
  capitalized display labels (not raw snake_case variable names), ×100
  scaling for binary-outcome coefficients, and no FE checkmark row when FEs
  are uniform across all columns
