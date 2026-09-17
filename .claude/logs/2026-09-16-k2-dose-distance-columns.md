# Session: 2026-09-16 — k2-dose-distance-columns

## Objective
Add a one-step-upstream dose regressor alongside the existing two-step dose in
`6yr_huc02fe_inorg_ravalli_2005_k2.tex`, on the exact same k2 sample, to show that
contamination decays with distance (dose-distance decay). Table becomes 8 columns
(two superheaders x 4 chemicals), placed in `main.tex` on a landscape page.

## Approach
- Generalize `build_dose_sample()` in `run_k2_6yr_tables.r` to
  `build_dose_sample(sample_k, dose_k = sample_k)`: sample selection unchanged
  (`k == sample_k`), dose column optionally pulled from a different `k` via a
  left_join on (PWSID, year), without re-filtering on `n_mine_hucs_linked` or
  re-applying `apply_a2()`.
- Build `dose2` (k=2, unchanged, still used by sumstats/balance) and
  `dose2_k1` (k=2 sample, k=1 dose) — same rows, added gates on row count and
  monotonicity (one-step dose <= two-step dose).
- 8-model loop: `dose_list <- list(one = dose2_k1, two = dose2)` x `CHEMS`,
  fixest 0.14.2 list-span header syntax for the two superheaders.
- main.tex: wrap the `\outreg{6yr_huc02fe_inorg_ravalli_2005_k2}` call (line 762)
  in the existing `\begin{landscape}...\end{landscape}` pattern.

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| One-step columns reuse the exact k2 sample rows | User decision — isolates the regressor change from sample composition changes |
| Utilities with only two-step mines get one-step dose = 0 | Natural consequence of left_join with no match; not treated as missing |
| Keep column name `coal_prod_upstream_cumsum_10mst` for both dose defs | Lets both share one etable row/dict label |
| Do not touch sumstats / pt_balance_6yr_k2 / syr2_mr_comparison_k2 | They still use `dose2`; must stay byte-identical |

## Verification Results
- [x] Script runs end-to-end (exit 0)
- [x] Output exists at expected path (`output/reg/6yr_huc02fe_inorg_ravalli_2005_k2.tex`, `_present.tex`)
- [x] Columns 5-8 match anchor values exactly: Arsenic 0.0001 (0.0001) N366; Nitrate 0.0883*** (0.0257)
      N472; Barium 0.0136 (0.0112) N353; Selenium 0.0004** (0.0002) N350
- [x] Columns 1-4 (one-step dose) share the same N as their paired columns 5-8 (366/472/353/350),
      since both use the identical k2 sample rows
- [x] `git diff --stat` shows no change to `output/sum/6yr_huc02fe_inorg_val_sumstats_ravalli_2005_k2*.tex`,
      `output/reg/pt_balance_6yr_k2.tex`, `output/sum/syr2_mr_comparison_k2*.tex` — byte-identical
- [x] main.tex compiles clean (latexmk, 0 errors, no `??`, no overfull box on the table's page 68,
      landscape confirmed), job_talk.tex compiles clean (0 errors, no overfull box on the `_present`
      slide, page 17-18)
- [x] Formatting: `digits = "r4"` throughout, no `e+`/`e-`, capitalized dict labels, notes start with
      `\textit{Notes:}` below the adjustbox, stars legend present, FE stated in notes (uniform across
      all 8 columns, no checkmark rows per table-figure-formatting.md Rule 7)

## Econometric Check — Dose-Distance Decay
One-step (closer) vs. two-step (published) coefficient per 10M short tons:

| Chemical | One-step | Two-step | Decay holds? |
|----------|----------|----------|---------------|
| Arsenic  | 0.0022*** (0.0004) | 0.0001 (0.0001)  | Yes — one-step larger |
| Nitrate  | 0.0278 (0.1021)    | 0.0883*** (0.0257) | **No** — one-step smaller and loses significance |
| Barium   | 0.0213** (0.0097)  | 0.0136 (0.0112)   | Yes — one-step larger |
| Selenium | 0.0031** (0.0015)  | 0.0004** (0.0002) | Yes — one-step larger |

3 of 4 chemicals (arsenic, barium, selenium) show the expected decay pattern — the one-step
coefficient is larger, consistent with dose concentration falling off with upstream distance.
Nitrate is the exception: its one-step coefficient (0.0278, not significant) is smaller than its
two-step coefficient (0.0883***), and loses significance. Per the plan, the spec was **not**
changed in response to this — flagging it for the user instead. One-step dose is 0 for 30.7% of
rows (527 of 1,716), i.e. utilities whose only linked mines are two flow-steps upstream.

## Open Questions / Blockers
- Nitrate does not show dose-distance decay (see table above) — worth discussing with the user
  before this table is presented as clean evidence of decay across all four chemicals.

## Quality Score
Target ≥ 90 (quality-gates.md). Self-assessment: **~92**.
- 80-gate: met (runs end-to-end, header block updated, no hardcoded paths, arrow parquet I/O
  unchanged, variable names match glossary).
- 90-gate: met (cross-language schema untouched since no new parquet write; `feols()` formula
  reused; non-obvious steps commented — dose_k generalization, the A2-purity note; both regenerated
  tables compile in both main.tex and job_talk.tex with no errors).
- Held back from 95 by the unresolved nitrate anomaly, which is a substantive econometric finding
  rather than a code-quality gap.

## Next Steps
- User to review the nitrate exception and decide whether/how to discuss it in the writeup text
  next to this table.
- Branch `k2-dose-distance-columns` left unmerged per plan Step 5 — commit and merge only after
  user confirms the table and its notes are as wanted.
