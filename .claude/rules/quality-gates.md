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

**90 (peer-review ready):**
- All of the above, plus:
- First-stage F-statistic row present in 2SLS tables
- Stars legend correct (*** p<0.01, ** p<0.05, * p<0.1)
- Table compiles without errors or overfull hboxes
