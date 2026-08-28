# Session: 2026-08-28 — Downstream-of-intake mines placebo/falsification test

## Objective
Test the exclusion restriction of the ARP instrument by re-running the main binary-violation
2SLS specification on a placebo treatment: coal mines located in the HUC12 immediately
downstream of a CWS intake. Contamination cannot flow upstream, so these mines should have
no effect on the CWS's water; a null result supports the exclusion restriction.

Plan: `~/.claude/plans/downstream-of-intake-mines-placebo-test.md`

## Changes Made
- `code/coal_mining_water_quality/build_placebo_downstream_intake.py` (new): builds the
  placebo PWSID x year panel. Mirrors `build_2step_sample.py` structure; HUC linkage logic
  follows intake HUC -> tohuc, keeping only links where the downstream HUC is a mine HUC.
- `clean_data/cws_data/prod_vio_sulfur_placebo_downstream_intake.parquet` (new): 18,102 rows,
  431 CWSs, PWSID str / year int64 confirmed.
- `code/coal_mining_water_quality/run_placebo_downstream_intake.r` (new): binary-violation
  2SLS tables (MR/MCL/allcat), first-stage table, surface-water robustness table, and an
  independent-samples equivalence (z-)test against the main D1 sample's reduced form.
- 6 new files in `output/reg/`: `2sls_placebo_dwnstrmintake_minevio_{mr,mcl,allcat}_ivsum_binvio.tex`,
  `fs_placebo_dwnstrmintake_minevio_ivsum_binvio.tex`,
  `2sls_placebo_dwnstrmintake_minevio_mr_ivsum_binvio_surfacewater.tex`,
  `placebo_equivalence_downstream_intake.tex`.

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| New variables use `_downstream_intake` suffix (`num_coal_mines_downstream_intake_sum`, `sulfur_downstream_intake_sum`, `production_short_tons_coal_downstream_intake_sum`) | Plan's naming warning: existing `minehuc_downstream_of_mine` means CWS-downstream-of-mine (treated group), the exact opposite of this placebo (mine-downstream-of-CWS-intake). Reusing `_upstream_sum`/`sulfur_unified_sum` names risked a downstream script silently reading the wrong column. |
| Placebo sample excludes any CWS with an intake in a mine HUC or a `downstream_of_mine` HUC | Isolates CWSs with zero real mining exposure, so the placebo tests the exclusion restriction cleanly and its CWS set is guaranteed disjoint from the main D1 sample (asserted explicitly in R; 0 overlap confirmed). |
| `digits = "r4"` added to both `etable()` calls in the new script (not in `run_main_tables.r`, per the plan's "do not modify" constraint) | Default etable rendering produced scientific notation (e.g. `$-1.46\times 10^{-6}$`) for near-zero MCL coefficients, violating the no-scientific-notation formatting rule. `digits = "r4"` forces fixed 4-decimal rendering; confirmed via a standalone R test that `digits = 4` (significant-digits mode) does *not* suppress scientific notation for tiny coefficients but `"r4"` (round-to-4-decimals mode) does. |
| Kept the existing CWS/year fixed-effects checkmark rows in the table body (did not switch to prose-only FE statement in notes) | Matches the precedent already established by `run_main_tables.r`'s `tsls_reg_output_main()`/`first_stage_table()`, which was copied verbatim per the plan. Per `table-notes-conventions.md` Rule 7, since FE rows are shown, FE are correctly *not* discussed in the notes prose. |

## Verification Results
- [x] Python script exits 0; parquet written; `PWSID` is `str`, `year` is `int64`
- [x] Placebo panel: 431 CWSs (≥ 100); `sulfur_downstream_intake_sum > 0` on 12,222 rows (non-zero variation)
- [x] Placebo sample shares **zero** PWSIDs with the main D1 sample (asserted explicitly in R, confirmed)
- [x] R script exits 0; all 6 `.tex` files exist and are non-empty
- [x] Placebo first-stage clustered F reported in every table
- [x] Column headers match outcome labels; N in footnotes plausible (9,051 / 6,111 main; 1,827 / 1,260 surface-water)
- [x] No `??` or `\undefined` in any new `.tex` output
- [x] Table notes checked against all nine rules in `table-notes-conventions.md` — pass (the only "placebo"/"robustness"-adjacent string hits are inside internal `\label{}` keys, which are not rendered text)

## Placebo Results
- **First-stage F (clustered): 1.82** (surface-water subsample: 2.80) — well below both the
  homoskedastic rule-of-thumb (10) and the Montiel Olea & Pflueger (2013) K_eff=1 threshold
  (23.11) cited in the plan's interpretation guide.
- Reduced-form coefficients (post95 x downstream-of-intake sulfur sum), MR outcomes:
  nitrates -0.0131 (SE 0.0077, *p*<0.1), arsenic -0.0122 (SE 0.0074, n.s.), inorganic
  chemicals -0.0130 (SE 0.0075, *p*<0.1) — same sign as the main-sample estimates but with
  wide standard errors.
- 2SLS coefficients on downstream-of-intake coal mines are **positive** (e.g. 0.2379 for
  nitrates MR) but **not significant** given SEs roughly the same magnitude as the point
  estimate (weak-instrument-driven imprecision) — this does *not* trip the "positive and
  significant at 5%" stop condition, but the sign is worth flagging.
- Equivalence test (placebo vs. main D1 reduced form, independent samples since CWS sets are
  disjoint): for all three MR outcomes, `z` in [-0.95, -0.37], `p` in [0.34, 0.71] — the
  main-sample estimate falls **inside** the placebo's 95% CI in every case (flag = No).

## Interpretation
Per the plan's interpretation table, F = 1.82 falls in the **"Weak (< 10)"** row: *"Test is
uninformative. The instrument has no bite in this sample, so a null reduced form says nothing
about the exclusion restriction. Report the weak F and do not claim the placebo passed."*
This is a **stop-and-ask condition** per the plan's Step 4 — surfaced to the user rather than
reported as a clean pass.

## Open Questions / Blockers
- **Placebo first-stage F (1.82) is weak.** The user should decide how to proceed: e.g.
  (a) report the placebo as inconclusive/underpowered rather than as support for the
  exclusion restriction, (b) investigate why the downstream-of-intake instrument has so much
  less power than the main upstream-sum instrument (431 placebo CWSs vs. thousands of
  intake->mine links suggests a possible sparsity/measurement issue in the one-hop-downstream
  linkage), or (c) treat this as sufficient given the equivalence test's directional result.

## Investigation of the Weak First Stage (2026-08-28, follow-up)
User asked to investigate before deciding how to report. Findings:

1. **Data-quality bug found, but ruled out as the cause.** 3 of the 1,116 HUC12s classified
   `minehuc == "mine"` in `clean_data/huc_coal_charac_geom_match.csv` are geographically
   implausible: `031002010400` (FL, "Venice Inlet-Gulf of Mexico", drains to `OCEAN`),
   `031102060605` (FL, drains to `CLOSED BASIN`), and `050500030801` (WV, drains to
   `CLOSED BASIN`). The Florida HUC in particular shows `sulfur_colocated = 0`,
   `btu_colocated = 0`, but a two-year-only production spike (276,707 tons in 1993, 13,371 in
   1994, zero every other year 1983-2024) in `clean_data/coal_huc_prod.csv` — almost certainly
   an artifact of the upstream `minegeomatch.py` step (e.g. a mismatched or erroneous MSHA
   mine location), not a real coal mine near Sarasota, FL. This explains the 47 Florida CWSs
   that showed up in the placebo sample (many intake HUCs flow into these few bad terminal
   HUCs). **This was not fixed** — `huc_coal_charac_geom_match.csv` and `coal_huc_prod.csv`
   are upstream `clean_data/` pipeline outputs from earlier steps, out of scope to edit without
   explicit confirmation per `data-safeguards.md`.
   - Broader check: mine-HUC state distribution is otherwise legitimate coal country (WV 249,
     KY 247, PA 176, AL 126, IL 56, CO 35, UT 29, ...); only these 3 HUCs are terminal/coastal.
     1,091 of 1,116 mine HUCs (98%) have positive production in at least one year.
2. **The bug does not explain the weak F.** All 3 bad HUCs have `sulfur_colocated == 0`, so
   `sulfur_downstream_intake_sum` is `NaN` for any CWS whose only downstream-intake mine link
   is one of them (`sulfur_sum_df` filters `sulfur != 0`). Since the first-stage/RF/IV formula
   uses `post95:sulfur_downstream_intake_sum`, rows with `NaN` sulfur are automatically dropped
   by `feols()` — confirmed the identifying sample is already exactly the 291 CWSs with a
   valid nonzero-sulfur match (6,111 obs, matching the reported table), with or without
   explicitly restricting to them.
3. **The weak F is a genuine structural feature of the identified sample**, not a fixable
   artifact: re-estimating the first stage on just the 291 valid-match CWSs gives Within
   R² = 0.0026 — the post95 x sulfur interaction explains essentially none of the
   within-CWS variation in downstream-of-intake mine counts. The likely reading: the
   "immediately downstream of an arbitrary CWS intake" geometric criterion picks up a much
   more diffuse, less persistent set of mine links than the main sample's upstream-of-mine
   set (which was purpose-built by the earlier geomatch pipeline around the actual mines
   feeding the treated CWSs). This is a power problem inherent to the placebo's identification
   strategy, not a bug in the new scripts.

**Conclusion:** the placebo test is underpowered and should be reported as inconclusive, not
as evidence for or against the exclusion restriction — per the plan's own interpretation
guide for F < 10. Separately, the 3 misclassified mine HUCs are worth flagging to whoever
owns the `minegeomatch.py` / mine-HUC classification step, since they could also introduce
noise elsewhere in the pipeline (any place that sums `num_coal_mines`/production over "mine"
HUCs without the sulfur>0 filter that happened to protect this analysis).

## Next Steps
- Report placebo as inconclusive/underpowered (F = 1.82) in any write-up; do not claim it
  supports the exclusion restriction.
- Flag the 3 misclassified mine HUCs (`031002010400`, `031102060605`, `050500030801`) to the
  owner of the mine-HUC geomatching step for correction at the source.
