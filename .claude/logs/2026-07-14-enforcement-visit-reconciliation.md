# Session: 2026-07-14 — Reconciling mean tables vs. FE regressions on sanitary visits, mining, and formal enforcement

## Objective
User asked to reconcile two apparent puzzles:
1. Why summary-statistic (mean) tables show more mining/contamination/visits →
   more formal enforcement, while CWS+year FE regressions show more mining →
   less formal enforcement.
2. Why mining raises sanitary visits (h2_snsv_d12.tex, 2SLS +0.14***) but lowers
   formal enforcement (h3_inf_formal_d12.tex, 2SLS -0.057***), when the prior is
   that visits + higher pollution should raise enforcement.

## Tables/scripts reviewed
- output/reg/h3_inf_formal_d12.tex — D1 downstream, formal enforcement 2SLS = -0.0565***
- output/reg/h2_snsv_d12.tex — D1 downstream, sanitary visit 2SLS = +0.1406***
- output/reg/sanitary_visit_upstream_mines_ols.tex — any_formal on any_snsv +
  upstream_mines_above_median, no FE / year FE / CWS FE
- output/sum/sanitary_visit_formal_enforcement_rate.tex
- output/sum/sanitary_visit_timing_formal_enforcement_rate.tex
- output/sum/sanitary_visit_formal_enforcement_rate_syr2_measurement.tex
- code/coal_mining_water_quality/sanitary_visit_upstream_mines_ols.r

(Note: output/sum/sanitary_visit_formal_enforcement_rate_upstream_mines_above_median.tex
does not exist as a separate file — the relevant "above median mines" row lives inside
sanitary_visit_timing_formal_enforcement_rate.tex, row 6.)

## Key finding: the mean tables do NOT actually show mining → more enforcement
The mean-table gradient (2.5% → 11.6% → 22.2%) is produced by conditioning on
MR violation and same-year sanitary visit — i.e. varying violations/visits, not
mining. The one row in sanitary_visit_timing_formal_enforcement_rate.tex that
does restrict on mining (row 6: MR + visit + upstream mines > median) goes
DOWN, 22.2% → 17.8% — same sign as the CWS-FE OLS (-0.048) and 2SLS (-0.057).
So there is no real contradiction between means and regressions on the mining
margin once you condition correctly; the earlier appearance of one came from
comparing a mining-margin regression result to a violation/visit-margin mean
result.

## Why the visit/violation gradient in means differs from the FE regression
- Between-system selection: chronically troubled CWSs accumulate violations,
  visits, and enforcement together (no-FE visit coefficient +0.024***, pure
  selection).
- Common time trends: enforcement and sanitary surveys both rose in the
  late-1990s post-amendments era; adding year FE alone kills the visit
  coefficient (-0.010, n.s.). Mining was concurrently declining and
  concentrated in early low-enforcement years, which is why the mining
  coefficient flips sign under year FE alone (+0.009, n.s.).
- Reverse timing / conditioning on a selected outcome: sanitary_visit_timing
  table shows enforcement rate is higher when MR violation precedes the visit
  (24.2%) than when visit precedes violation (17.4%) — visits partly follow
  enforcement processes rather than trigger them.

## Reconciling visits up / formal enforcement down under mining
Consistent with the existing MR-substitution finding ([[project_regulator_pivot]]
in memory): mining-exposed CWSs strategically incur MR violations to avoid
documented MCL violations. Formal enforcement needs a documented, fixable
violation to run on; if monitoring is avoided, that paper trail doesn't exist.
The regulator's remaining tool is the sanitary survey, which doesn't require a
monitoring record — hence visits and investigation-type actions rise
(enforcement visits 2SLS +0.037*) while formal actions fall. This is presence
without escalation, not simple forbearance.

## Caveats flagged to user
1. PA dominance ([[project_pa_dominance]] in memory): all downstream 2SLS
   results, including formal enforcement, are driven by Pennsylvania alone.
   Worth checking whether the h2 sanitary-visit 2SLS is also PA-driven — if
   visits and enforcement move on the same PA variation the substitution story
   holds together; if not, the two effects are identified off different
   systems.
2. Timing of instrument: post95 x sulfur coincides with the 1996 SDWA
   amendments' national enforcement expansion. Year FE absorb the national
   trend, but a sulfur-correlated differential enforcement ramp-up (e.g. a
   PA-specific post-96 program change) could still mimic the effect. Existing
   temporal-placebo apparatus is the right check.

## Open Questions / Blockers
- Confirm h2_snsv_d12.tex 2SLS result is/isn't PA-driven (parallel jackknife
  check to the one already run for formal enforcement).
- Consider re-running sanitary_visit_timing_formal_enforcement_rate.tex with
  an explicit "mining above median" cut on the unconditional (not MR+visit
  restricted) sample for a cleaner mean-vs-regression comparison.

## Next Steps
- No code changes made this session — this was an interpretive/reconciliation
  discussion only. Next step is the PA-jackknife check on h2_snsv_d12 if user
  wants to firm up the substitution narrative for the writeup.

## Update (later same session)
- Verified nitrate compliance mechanics against 40 CFR 141.23 (Cornell LII):
  nitrate single-sample + 24-hr confirmation (f)(2)/(i)(3); 50%-MCL quarterly
  trigger (d)(2); CORRECTION — annually-monitored systems are in violation on
  a single sample > MCL (i)(2), so "single state sample can't create a
  violation" was overstated for small systems.
- Reframed avoidance target: detection/monitoring ratchet (waiver loss,
  quarterly escalation), not MCL-hiding — SYR2 readings are 10x below MCLs.
- mr_concentration_lag.tex nitrate 50%-MCL result identified as the trigger
  test; pooled-IOC null at 50% MCL is a built-in placebo (threshold has no
  regulatory meaning for other IOCs). Caveat: only 3 treated readings.
- Delegated power fix (a) to a Sonnet subagent (per user instruction):
  national SYR2 nitrate sample, build_mr_concentration_lag_national.py +
  mr_concentration_lag_national.r → output/reg/mr_concentration_lag_national.tex,
  new parquet clean_data/mr_concentration_lag_national_nitrate.parquet.
- Saved full argument memo: docs/enforcement-substitution-puzzle.md (puzzle,
  table-by-table resolution, ratchet mechanism, CFR citations, five unresolved
  competing explanations).
- Sonnet subagent completed national test: 1,052,487 nitrate readings,
  119,092 above 50% MCL. near_mcl -> MR: +0.0049** (1-yr), +0.0024*** (6-mon);
  past placebos ~0 (p=0.78/0.53). N=1,041,124, PWSID+YEAR FE, cluster PWSID.
  Ratchet replicates nationally; national ~0.5pp is the credible magnitude
  (downstream +0.59 rested on 3 obs). Verified table myself; fixed one
  note-wording inaccuracy in mr_concentration_lag_national.r/.tex
  ("z-scored within PWSID-YEAR" -> "PWSID-YEAR mean, z-scored across sample").
  Memo section 6 updated with the result.
