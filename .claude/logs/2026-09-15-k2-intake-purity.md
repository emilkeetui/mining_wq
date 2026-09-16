# Session: 2026-09-15 — k2 intake-purity sample comparison

## Objective
Test whether utilities with "impure" intake portfolios (upstream and/or unclassified
intake HUCs) drive the k2 two-step-linkage main-arm results. Compare three nested
utility samples — status quo (SQ), no-upstream (A1), downstream-only (A2) — across
first stage, MR, visit, enforcement, and SYR2 families. No new .tex tables; output is
a terminal comparison + one tidy parquet, per plan `structured-twirling-spark.md`.

## Approach
1. `build_k2_intake_purity.py` — classify each k2 main-arm utility's intake HUCs via
   k-step linkage (`huc_step_distance.parquet`), build SQ/A1/A2 sample flags, write
   `clean_data/cws_data/k2_intake_purity.parquet`.
2. `compare_k2_intake_purity.r` — reuse `k2_common.r` helpers to re-run the k2 main
   spec (first stage, MR, visits, enforcement, SYR2) on each of the three samples,
   gate status-quo numbers against already-published k2 table values, write
   `clean_data/cws_data/k2_intake_purity_compare.parquet`, print side-by-side report.

## Key Context
- Baseline dataset: k2 two-step linkage (`run_k2_main_tables.r`, `run_k2_6yr_tables.r`),
  embedded in `main.tex` at commit 5bddf2f.
- Intake classification priority: downstream > upstream > unclassified (matches static
  CSV convention for HUCs that are both).
- Old static downstream sample (340 utilities) verified A1=A2=SQ by construction —
  shown as reference only, no re-estimation.

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| Branch off kgrid-coef-plots after committing its work | User chose "commit then branch" to keep prior session's work intact before starting this task |
| No `candidate_hucs` filter in intake linkage copy | That filter silently drops unclassified intakes — exactly what A2 needs to detect |

## Verification Results
- [x] Step 1 (`build_k2_intake_purity.py`) ran end-to-end: SQ=666, A1=656 (10 dropped),
      A2=582 (84 dropped from SQ). All gates passed (no SQ PWSID missing/lost, every SQ
      utility has ≥1 downstream intake). `clean_data/cws_data/k2_intake_purity.parquet` written.
- [x] Step 2 (`compare_k2_intake_purity.r`) ran end-to-end. All status-quo gates matched
      published k2 values exactly: first-stage F 50.01, MR IV (nitrates 3.28/1.73, arsenic
      3.11/1.52, inorganic 2.00/1.60), SYR2 OLS (arsenic 0.0001/0.0001, nitrate 0.1037/0.0281,
      barium 0.0130/0.0116, selenium 0.0004/0.0002).
- [x] A2 ⊆ A1 ⊆ SQ verified; N-obs monotonicity held in all 52 cells checked (0 violations).
- [x] `clean_data/cws_data/k2_intake_purity_compare.parquet` written, 156 rows, no NA in
      sample/outcome/model.

## Results Summary
- Utility-level intake classification (k=2 step distance): 247 downstream intake HUCs, 11
  upstream, 109 unclassified, across the 666 SQ utilities' 367 distinct intake HUCs.
- MR and first-stage coefficients are stable across SQ/A1/A2 (differences mostly <0.1 in
  magnitude, all same sign, no significance flips on the headline inorganic-chemicals/
  arsenic/nitrates MR results).
- Sign flips appeared only in small, statistically insignificant coefficients: `any_tech`
  (visits, IV and RF, state×year FE) and `no_enf` (enforcement, IV/OLS/RF, state×year FE) —
  all near zero with wide SEs in both SQ and A2, not a substantive reversal of any
  significant finding.
- No weak-instrument flags (`f_clustered` stayed 39–50 across all samples/FEs).
- fixest emitted "fixed-effects are not regular" NOTEs for some `huc02^year` SYR2
  regressions on the smaller A2 sample — informational, not a gate failure; SYR2
  coefficients were numerically identical to 4 decimals across SQ/A1/A2 for all four
  chemicals regardless.
- Old static downstream sample (340 utilities, different instrument/FE) printed for context
  only — not a like-for-like comparison.

## Quality Score
~88/100 (commit-ready, most peer-review criteria met). Minor rough edges: static-reference
block extracts table rows via a generic text-line grep rather than a structured per-column
parser (acceptable since it's terminal-only context, not a rendered table).

## Open Questions / Blockers
- None — no coefficient sign flips affected a headline (significant) result.

## Next Steps
- Awaiting user decision on whether to commit this branch (`k2-intake-purity`).
