# Session: 2026-07-29 — Backcasting leave-one-out validation

## Objective
Implement the two validation exercises promised in `writeup/cws_exposure_backcasting.tex`
§3.8, the largest remaining gap in the backcasting exercise:
1. **LOAO** — leave-one-anchor-out, tests the Step 3 capture-ratio layer.
2. **LODO** — leave-one-decade-out, tests the Step 2 kappa-constant assumption
   independently of any reported figure.

Plan: `Z:\Users\ek559\.claude\plans\backcast-leave-one-out-validation.md`

## Context
Steps 1–3 are built and committed (`40cdc6c`). `population_backcasting.tex` currently
concedes the missing validation in prose rather than reporting a number — accuracy of
the backcast is entirely unmeasured.

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| LOAO folds are **era-blocks**, not individual anchors | 2010/2011 are near-duplicates: corr 0.998, **90.8% of 360 systems report identical values**. Per-anchor LOO would predict 2011 from 2010 with ~zero error — a vacuous pass. Three folds: A={2010,2011}, B={2006}, C=SYR2 era |
| Tiers reported separately, **never pooled** | County-tier `S_hat` reproduces reported values exactly at its own anchors by construction (level carry, not ratio). Pooling would let 38 near-tautological county systems dilute the 227 service-area systems that actually test r |
| LOAO calls the **production** `carry_ratio()` with a filtered anchor set | Fold prediction is the real estimator with less information, not a parallel code path that could silently diverge |
| LODO withholds **both** interior decennials (2000, 2010), each predicted from **both** directions | All 366 systems have all 4 decennials → no sample loss. Two directions separate "chaining is biased" from "chaining is noisy". 1990/2020 are endpoints, excluded |
| LODO truth = the true block apportionment | The whole point: error measured with no reported figure in the loop |
| Aggregate error first, per-system second; mean APE discounted | Headline estimand is a sum. Writeup predicts "aggregates accurate where individual systems are noisy" — worth testing, not asserting. Small systems produce huge APEs off near-zero bases (same pathology as pct-change, documented 2026-07-27) |

## Fold eligibility (verified against the anchor panel before planning)
| Fold | Held out | Predicted from | Eligible (SA / county) |
|---|---|---|---|
| A | 2010 + 2011 | SYR2 + 2006 | 265 (227 / 38) |
| B | 2006 | SYR2 + 2010/2011 | 259 (225 / 34) |
| C | SYR2 (1998–2005) | 2006 + 2010/2011 | 140 (118 / 22) |

Fold A is the most demanding (4–12 yr extrapolation gap) → the honest headline.

## Changes Made
- `code/coal_mining_water_quality/backcast_validation.py` (new): LOAO (3 era-block
  folds, imports and reuses `compute_ratios()`/`carry_ratio()` from
  `build_cws_reported_ratio.py` unmodified — no refactor was needed, see below) +
  LODO (2000/2010 × forward/backward, reuses the eq. 8 PEP-blend logic).
- `code/coal_mining_water_quality/backcast_validation_tables.py` (new): writes
  `sum/backcast_loao.tex`, `sum/backcast_lodo.tex`.
- `clean_data/cws_data/cws_loao_validation.parquet` (new, 929 rows, PWSID/fold grain)
- `clean_data/cws_data/cws_lodo_validation.parquet` (new, 1,464 rows = 366×2×2)
- `writeup/.../population_backcasting.tex`: validation subsection expanded from
  "four checks, two exercises outstanding" to six checks with the two new tables
  and a results paragraph for each, `\input`ed at the right place.

## Plan deviation
`build_cws_reported_ratio.py` needed **no refactor**. Verified by direct call
before writing any new code: `compute_ratios()`/`carry_ratio()` already take the
anchor/ratio frame as a plain argument, importing the module doesn't trip the
`main()`-only overwrite guard, and calling both functions on the full anchor set
reproduces the committed `cws_capture_ratio_annual.parquet`'s `pop_served_hat`
bit-for-bit (max abs diff 0.0). So LOAO folds call the production functions
directly with a filtered anchor frame — genuinely "the estimator with less
information," not a reimplementation.

## Two bugs caught during verification
1. **Undefined `\geopop` macro.** First draft of the two new prose paragraphs used
   `\geopop_{i,t}` (copied from the methods-only companion file
   `writeup/cws_exposure_backcasting.tex`), but `population_backcasting.tex` uses
   plain `G_{i,t}` throughout and defines no such macro — would have been a hard
   compile error. Caught by grep-checking the file's own notation before compiling,
   not by the compile itself. Fixed in both the .tex and the table-generator script.
2. **Column-count mismatch in `backcast_lodo.tex`.** The LODO row builder emitted 8
   `&`-separated fields (target, direction, tier, systems, agg err, median APE,
   within-10%, within-25%) against a 7-column `tabular{llrrrrr}` spec, corrupting
   the table into `\halign` "Extra alignment tab" errors that cascaded through the
   rest of the document. Caught by compiling, not by inspection — the generated
   .tex looked plausible until pdflatex's `\endtemplate` error pointed at the exact
   row. Fixed by merging the two "within" values into one cell
   (`within10 / within25`), matching what the header column actually promised.

## Verification Results
- [x] Both new scripts exit 0
- [x] `compute_ratios()`/`carry_ratio()` reproduce committed `pop_served_hat`
      bit-for-bit (max abs diff 0.0) — confirmed *before* writing the validation
      script, which is why no refactor was needed
- [x] Fold eligibility matches 265 / 259 / 140 exactly (76+454, 34+225, 22+118 = 929
      rows after dropping ineligible held-out anchors)
- [x] LODO row count = 366 × 2 × 2 = 1,464, no nulls
- [x] Tables compile cleanly in isolation: `backcast_lodo.tex` and
      `backcast_loao.tex` both open/close with zero errors in the pdflatex log,
      confirmed on three separate full-document compiles
- [x] Every number in the rewritten prose cross-checked against the parquet
      directly (LOAO agg err by fold×tier, LODO agg err/median APE/within-25% by
      target×direction) — all match exactly
- [~] Full-document cross-reference resolution (`\ref`/`\eqref` → real numbers
      instead of `??`): **not confirmed**. See below.

## Open Questions / Blockers
- **`main.tex` does not fully resolve cross-references even after 3 identical
  compile passes** — `eq:chain-closed`, `sec:backcast-step3`,
  `tab:backcast_{loao,lodo}` all show `??` in the rendered PDF. Diagnosed as
  pre-existing and NOT caused by this session's edits: (a) `.aux` after every run
  contains the correct `\newlabel` entries for all of these at the right pages, and
  (b) an *unmodified* pre-existing cross-reference from the 2026-07-27 session
  (`Table~\ref{tab:backcast_ratio}`, defined and used entirely outside this
  session's changes) shows the identical `??` symptom on the same page. Likely root
  cause: the already-documented `sum/npdwr_changes.tex:29` `tablenotes`/
  `threeparttable` fatal error later in the document prevents `\end{document}` from
  running cleanly, which appears to stop LaTeX from doing a fully consistent
  label pass even though the `.aux` entries themselves look correct. Not
  investigated further — fixing it means touching `main.tex`'s preamble
  (`\usepackage{threeparttable}`), which both this session's plan and the
  2026-07-27 session explicitly scoped out as unrelated. The tables' *content* is
  independently verified correct (visual inspection + parquet cross-check), so the
  numbers reported in prose and tables are right; only the `\ref{}` page/number
  callouts in the surrounding text will show as `??` until someone applies that
  one-line preamble fix.

## Next Steps
- Apply `\usepackage{threeparttable}` to `main.tex`'s preamble (flagged twice now,
  2026-07-27 and today) to get a fully clean compile with resolved cross-refs —
  small, low-risk, but requires user confirmation since it touches shared preamble.
- Remaining backcasting queue, in priority order: (3) shrink the county tier, (4)
  ACS intercensal apportionment — LODO's service-area median APE of 7–12% is a
  concrete argument for this, since ACS would replace PEP-chaining in exactly the
  years being tested here, (5) Q4 EJ write-up, (6) Q3 intensity-weighted
  counterfactual, (7) ML robustness layer.
