# Quality Gates

| Score | Gate | Meaning |
|-------|------|---------|
| 80 | Commit | Runs correctly, structurally sound |
| 90 | Peer-review ready | Clean, reproducible, matches spec |
| 95 | Excellence | Aspirational; minimal reviewer friction |

## R Scripts — Threshold Criteria

**80 (commit):**
- Runs end-to-end without error
- Header block present and complete
- No hardcoded absolute paths
- Parquet I/O uses `arrow::read_parquet()` / `arrow::write_parquet()`
- Variable names match CLAUDE.md glossary

**90 (peer-review ready):**
- All of the above, plus:
- Cross-language schema check present (PWSID character, year integer)
- `feols()` formula objects named and reusable
- Non-obvious steps have comments
- Output files (tables, figures) exist and are non-trivially non-zero

## Python Scripts — Threshold Criteria

**80 (commit):**
- Runs end-to-end without error using the full venv path
- Header block present and complete
- All outputs go to `clean_data/`, never `raw_data/`
- Parquet writes use `engine="pyarrow"`, `index=False`
- PWSID cast to `str`, year cast to `int64` before writing

**90 (peer-review ready):**
- All of the above, plus:
- CRS logged and asserted before every spatial join
- `df.dtypes` printed before final parquet write
- Output row count validated after write
- Existing output file warned before overwrite

## LaTeX Tables — Threshold Criteria

**80 (commit):**
- Column headers correctly label the sample cut (colocated, downstream, etc.)
- Sample size footnote present with plausible N
- No `\undefined` or `??` references
- Coefficient cells are non-trivially non-zero
- Notes begin with `\textit{Notes:}` (see `table-notes-conventions.md`)
- No scientific notation anywhere in the table
- Notes/captions are left-justified, not centered or fully justified
- Display labels (row/column headers) are capitalized, not raw snake_case
  variable names
- Binary-outcome coefficients and SEs are scaled ×100 (percentage points)

**90 (peer-review ready):**
- All of the above, plus:
- First-stage F-statistic row present in 2SLS tables
- Stars legend correct (*** p<0.01, ** p<0.05, * p<0.1) and present in every
  regression table's notes, per `table-notes-conventions.md`
- Table compiles without errors or overfull hboxes
- Notes contain no variable names, cross-references, file paths, individual
  sample IDs, sample-cleaning narration, or robustness-check labeling — full
  checklist in `table-notes-conventions.md`
- Fixed-effects discussion in notes only when FE checkmark rows are omitted
  because FEs are uniform across all columns; checkmark rows kept (and notes
  silent on FEs) when FEs differ across columns — see
  `table-notes-conventions.md` Rule 7 / `table-figure-formatting.md` Rule 7
- Significant figures are consistent across all numeric entries in the table
- Numeric columns with decimals are decimal-aligned (`dcolumn`/`siunitx` or
  equivalent) — full checklist in `table-figure-formatting.md`
