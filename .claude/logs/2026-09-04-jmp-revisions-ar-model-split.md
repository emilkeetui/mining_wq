# Session: 2026-09-04 — JMP revisions (AR intervals, model split, balance table, retitle)

## Objective
Act on a reviewer-style assessment of `main.tex` against the criterion "technical
expertise plus plain-English motivation, method, data, implications." User selected
five changes and explicitly dropped the introduction rewrite mid-session.

## Changes Made

- `code/coal_mining_water_quality/run_main_tables.r`: added `ar_ci()` (closed-form
  cluster-robust Anderson-Rubin confidence set for just-identified IV) and `fmt_ar()`;
  computed per outcome in `tsls_reg_output_main()`; added an AR row to the 2SLS panel
  in `render_panel_binary_table()` and a plain-English gloss inserted ahead of the
  stars legend in the notes.
- `code/coal_mining_water_quality/enforcement_chain_d12.r`: mirrored all of the above
  into its own copy of the helpers (project convention is per-script copies, not
  `source()`); wired `ar` into `result_b` (visit types) and `result_h3_inf`
  (enforcement types).
- `writeup/.../main.tex`:
  - retitled to "When Pollution Rises, Reporting Falls: Coal Mining and
    Self-Monitoring under the Safe Drinking Water Act"; moved `pdfauthor`/`pdftitle`
    out of hyperref package options into `\hypersetup{}`.
  - Section 5: added explicit non-causal framing, reported the concentration sample
    size (319-432), added `\subsection{Comparability of utilities by upstream
    production}` interpreting the restored balance table, fixed 0.05 -> 0.057.
  - Section 6: new paragraph explaining Anderson-Rubin intuitively.
  - Sections 7/8: AR intervals reported alongside every 2SLS estimate; new paragraph
    addressing the formal-enforcement coefficient exceeding its own base rate.
  - Discussion: removed the contradiction between "cannot distinguish" and the
    concealment conclusion; now states the cost channel is favored, with the caveat.
  - Model section cut to setup + reporting cutoff + two-paragraph Proposition 2
    intuition; all derivations and proofs moved verbatim to `\appendix` /
    `\section{Proofs of the propositions}` (`app:proofs`).
  - Added `\outreg{pt_balance_6yr}` to the end-matter float block.
- `writeup/.../citation.bib`: added `anderson1949estimation`.

## Design Decisions

| Decision | Rationale |
|---|---|
| Closed-form AR set rather than grid search | AR stat is a ratio of quadratics in b0, so the confidence set solves a quadratic inequality exactly; ~9x faster than a grid and gives exact endpoints |
| Calibrate fixest's small-sample factor via `vcov(adj=FALSE, cluster.adj=FALSE)` ratio | The correction is a constant multiple of the statistic; recovering it from one auxiliary fit guarantees the AR set matches the SEs printed in the same table, without replicating fixest's df bookkeeping |
| `demean()` + `qr.resid()` instead of `resid(feols())` | `feols` drops FE singletons and errors on collinear controls, which misaligned residuals with the data rows (7 AR failures in the surface-water subsample); `demean` keeps row alignment and QR pivoting tolerates rank deficiency |
| Address the negative-probability formal-enforcement estimate by rescaling to the realized dose | The instrument moves upstream mines by ~0.30 per SD of upstream sulfur against a within-utility SD of 0.72, so "one mine" is ~3x the delivered dose; at the realized margin the implied probabilities stay inside [0,1] |
| Proofs to an appendix rather than deleted | Only Proposition 2 is tested, but Propositions 1 and 3 carry the model's structure and its policy statement |

## Verification Results
- [x] `ar_ci()` validated against a brute-force grid inversion using `feols` at 0.02
      resolution on 5 outcomes — endpoints matched to grid resolution in all cases
- [x] `run_main_tables.r` exits 0, zero AR errors (was 7 before the demean rewrite)
- [x] `enforcement_chain_d12.r` exits 0, no errors
- [x] `main.tex` compiles: exit 0, 69 pages, no undefined references or citations
- [x] No new overfull hboxes in table files; the three remaining >10pt are in the
      bibliography and two body paragraphs
- [x] All AR sets are bounded; every headline result excludes zero under AR

## Key results (AR 95% intervals, percentage points per upstream mine)
- MR violations: nitrates [3.1, 19.1], arsenic [1.6, 14.6], IOC [0.8, 14.6] — all exclude 0
- Any violation: IOC [-0.3, 13.9] includes 0 (the combined-outcome column only)
- MCL violations: all include 0, and are narrow — a tight null, not an imprecise one
- Sanitary visits [5.8, 27.0]; enforcement visits [0.6, 8.8] (AR excludes 0 where the
  conventional SE only reached 10%); formal enforcement [-10.5, -1.8]

## Reversed later in the session (user instruction)

- **Anderson-Rubin intervals removed from the paper.** User will add them in future.
  All AR prose was stripped from Sections 6, 7 and 8 of `main.tex`, and the AR row
  and its notes sentence no longer render. `ar_ci()` / `fmt_ar()` remain in both
  scripts behind a single `show_ar <- FALSE` flag declared just above `ar_ci()`;
  setting it to `TRUE` in either script restores the row and the notes gloss with no
  other edits. `anderson1949estimation` is left in `citation.bib` (uncited entries
  are not printed by biblatex) for the same reason.
- **[LEARN:econometrics]** My claim that the per-mine coefficient was a linear
  extrapolation beyond the delivered dose was wrong -> the instrument is per mine,
  and the coefficient is the effect of one additional upstream mine as reported. The
  paragraph rescaling effects to a per-standard-deviation-of-sulfur margin was
  removed from Section 8. Do not reinterpret the treatment's units.
- **Introduction** now reads "I document that coal mining raises contaminant
  concentrations" rather than "I confirm", bringing it into step with Section 5's
  observational framing.

## Open Questions / Blockers
- `output/reg/mr_concentration_lag_ols.tex` still carries the stale label
  `tab:mr_concentration_lag_logit` (the estimator is OLS). Not in scope this session.
- Still no robustness section; the `_days` outcomes promised in the Data section are
  not reported anywhere.

## Next Steps
- Fill the red-text acknowledgments placeholders before circulating.
- Re-enable `show_ar` when the user wants the Anderson-Rubin intervals back.
