# Why does mining increase sanitary visits but decrease formal enforcement?

*Research memo, 2026-07-14. Consolidates the reconciliation argument developed across the
sanitary-visit / enforcement analyses. All table references are to `output/reg/` and
`output/sum/` unless noted.*

---

## 1. The apparent puzzle

Four facts that seem mutually inconsistent:

1. **Mining raises contamination.** Upstream coal mining raises measured inorganic
   concentrations at downstream CWSs (`output/reg/6yr_huc02fe_inorg_ravalli_2005.tex`).
2. **Mining raises sanitary visits.** 2SLS on the D1 downstream sample: upstream mines →
   sanitary visit probability +0.1406*** (`output/reg/h2_snsv_d12.tex`).
3. **Mining lowers formal enforcement.** Same sample and instrument: upstream mines →
   any formal enforcement −0.0565*** (OLS −0.0169***)
   (`output/reg/h3_inf_formal_d12.tex`).
4. **Yet the summary tables appear to show the opposite gradient**: the formal
   enforcement rate climbs 2.52% → 11.59% → 22.22% as the sample is restricted to
   CWS-years with an MR violation and then an MR violation + same-year sanitary visit
   (`output/sum/sanitary_visit_formal_enforcement_rate.tex`,
   `output/sum/sanitary_visit_timing_formal_enforcement_rate.tex`,
   `output/sum/sanitary_visit_formal_enforcement_rate_syr2_measurement.tex`).

The prior that generates the puzzle: if regulators visit more where pollution is higher,
those visits should uncover problems and produce *more* formal enforcement, not less.

## 2. Resolution part 1 — the mean tables never showed mining → more enforcement

The 2.5% → 11.6% → 22.2% gradient in the summary tables varies the **violation/visit
margin**, not the mining margin. The one row that varies mining — row 6 of
`sanitary_visit_timing_formal_enforcement_rate.tex`, restricting the MR+visit cell to
above-median upstream mines — moves **down**: 22.22% → 17.78%. That is the same sign as
the CWS-FE OLS (−0.048***, col 3 of `sanitary_visit_upstream_mines_ols.tex`) and the
2SLS (−0.057***). The SYR2-measurement variant (row 4, 7.94% → 9.09%) varies measured
*contamination*, not mining, and rests on 4 vs. 5 enforcement events (N = 44 vs. 63) —
uninformative. **Once you condition correctly there is no means-vs-regression conflict
on the mining margin.**

Why the visit/violation gradient in the means still differs from the FE regressions:

- **Between-system selection.** Chronically troubled CWSs accumulate violations, visits,
  and enforcement together. No-FE OLS: sanitary visit +0.024*** on formal enforcement
  (`sanitary_visit_upstream_mines_ols.tex`, col 1). A statement about *which systems are
  bad*, not what a visit causes.
- **Common time trends.** Formal enforcement and sanitary surveys both ramped up in the
  late 1990s (post-1996 SDWA amendments). Year FE alone kill the visit coefficient
  (−0.010, n.s., col 2). Mining was declining and concentrated in early low-enforcement
  years, which is why the mining coefficient flips sign under year FE alone (+0.009, n.s.).
- **Reverse timing.** Enforcement rates are *higher* when the MR violation precedes the
  visit (24.19%) than when the visit precedes the violation (17.42%)
  (`sanitary_visit_timing_formal_enforcement_rate.tex`, rows 4-5): visits partly *follow*
  enforcement processes rather than trigger them.
- **Conditioning on an MR onset** selects the sample on an outcome that mining and visits
  themselves affect.

## 3. Resolution part 2 — visits substitute for sanctions when the violation record is missing

The h2/h3 pair is not a contradiction; it is two halves of an enforcement-instrument
substitution:

- **Formal enforcement runs on a documented, fixable violation.** Mining-exposed CWSs
  avoid monitoring (the MR-substitution results); without readings there is no documented
  MCL violation and no return-to-compliance path to formally enforce.
- **The sanitary survey is the one instrument that needs no monitoring record.** It is a
  physical inspection of the system and its records — which is also *how a lapsed
  monitoring schedule gets discovered*, consistent with visits and MR violations
  co-occurring (the 22% cell).
- **Presence without escalation.** Under 2SLS, "enforcement visits" (investigations) also
  *rise* with mining (+0.037*, `h2_snsv_d12.tex`) while formal actions *fall*. Regulators
  show up and investigate more where mining is active; they do not escalate to formal
  orders.
- **Discretion rationale.** Mining contamination is source-water pollution the CWS did not
  cause and often cannot remediate (the polluter is regulated under SMCRA/CWA, not SDWA).
  Surveys + technical assistance can change the outcome; sanctioning a small downstream
  system for its watershed cannot.

## 4. Why avoid monitoring if no MCL is being hidden? The detection ratchet

Key institutional facts (verified against 40 CFR 141.23, Cornell LII text; promulgated by
the Phase II rule, 56 FR 3526, Jan. 30, 1991, effective ~1993):

- **Sanitary surveys are not compliance-sampling events.** Compliance is determined from
  the system's own routine samples at designated points; the surveyor audits records.
- **Nitrate**: single sample above the MCL + 24-hour confirmation sample; compliance =
  average of the two (141.23(f)(2), (i)(3)). A single reading **≥ 50% of the MCL**
  (5 mg/L) forces **quarterly monitoring for at least a year** (141.23(d)(2)).
- **Other IOCs**: running annual average for systems on quarterly schedules (141.23(i)(1));
  but — important correction — for systems monitoring **annually or less** (most small
  systems), a *single* sample above the MCL is out of compliance (141.23(i)(2)).
- **The ratchet**: any exceedance triggers quarterly monitoring (141.23(c)(7));
  reduced-monitoring waivers require a clean documented history (141.23(c)(2), (c)(4)).

The SYR2 readings for downstream CWSs sit an order of magnitude below the MCLs (arsenic
mean 0.0029 vs. then-MCL 0.05 mg/L; nitrate 0.752 vs. 10 mg/L), no observed reading ever
exceeds an MCL, and the K&S structural exercise could not identify k_MCL because MCL
events are too rare. So the literal "hiding an MCL exceedance" story is too strong. The
avoidance target is the **detection/trigger ratchet**, not the MCL:

1. A detection or trigger-crossing forfeits the reduced-monitoring waiver and multiplies
   sampling costs permanently — even when the reading is nowhere near the MCL.
2. Consequences are asymmetric: an MR violation is cheap (formal enforcement follows only
   11.59% of MR-violation years, mostly informal responses), while a bad sample carries
   tail risk — confirmation sampling, public notification, mandated treatment whose capital
   cost is existential for a small system.
3. Mining shifts the concentration distribution rightward, raising the expected cost of
   *taking* a test even when P(MCL exceedance) ≈ 0. Not testing is the cheap option.

**Supporting evidence**: `output/reg/mr_concentration_lag.tex` — a nitrate reading above
50% of the MCL (exactly the 141.23(d)(2) trigger) predicts a same-contaminant MR violation
within 1 year (+0.59**) and 6 months (+0.26**), CWS + year FE. Two features strengthen it:

- The pooled-IOC columns show **zero** effect at 50% MCL — as they should, since 50% MCL
  has no regulatory meaning for the other IOCs (their ratchet triggers on *detection*).
  The effect appears exactly where the regulation places a threshold and nowhere else.
- Near-zero coefficients on mean concentration: threshold behavior, not dose-response —
  what regulation-driven behavior should look like.
- Past-window placebo table (`mr_concentration_lag_placebo.tex`) provides the timing
  falsification.

## 5. The full causal chain (each link has a table)

```
mining → contamination           6yr_huc02fe_inorg_ravalli_2005.tex
contamination near trigger →     mr_concentration_lag.tex  (nitrate 50%-MCL threshold)
  monitoring avoidance (MR)
mining → MR violations           (MR-substitution tables)
no violation record →            h3_inf_formal_d12.tex     (formal enforcement falls)
  nothing to formally enforce
regulator substitutes surveys →  h2_snsv_d12.tex           (sanitary visits rise,
  for sanctions                                              enforcement visits rise)
```

## 6. Competing explanations — unresolved

1. **Mechanical exposure vs. strategic avoidance** (for the ratchet link). A trigger-
   crossing quadruples *required* samples; MR probability rises mechanically even with
   unchanged per-sample compliance. Discriminating test (not yet run): per-required-sample
   MR rate before vs. after the trigger, or whether skip probability rises with how close
   the triggering reading was to the full MCL (avoidance predicts yes; mechanics no).
2. **Small-N inference on the trigger effect.** Only 3 downstream readings exceed 50% MCL;
   clustered SEs are unreliable with 3 treated observations. Fixes:
   (a) **national SYR2 nitrate sample — DONE (2026-07-14)**: all PWSIDs, 1,052,487
   nitrate readings 1998-2005, **119,092 readings above 50% MCL** (vs. 3 downstream).
   Scripts `build_mr_concentration_lag_national.py` / `mr_concentration_lag_national.r`
   → `output/reg/mr_concentration_lag_national.tex`. Result: near_mcl → nitrate MR
   within 1 yr = +0.0049** (SE 0.0022), within 6 mon = +0.0024*** (0.0009); past-window
   placebos ≈ 0 (0.0004, p=0.78; 0.0007, p=0.53). PWSID + YEAR FE, N = 1,041,124,
   SEs clustered by PWSID. The ratchet pattern replicates nationally with the correct
   temporal asymmetry. Note the national magnitude (~0.5 pp) is far below the downstream
   +0.59 — the downstream point estimate was driven by 3 observations and should be
   quoted with the national estimate as the credible magnitude. Caveat: mean_conc_z is
   significant even in the placebo columns (a level effect — high-concentration systems
   generically have more MR violations), so `near_mcl`, with its forward-only timing,
   is the identifying coefficient.
   (b) randomization inference on the downstream estimate (not yet run; less urgent now
   that the national estimate exists);
   (c) an IOC analogue at its correct threshold (detection level, not 50% MCL) — would
   turn the current placebo column into a second test of the mechanism (not yet run).
3. **PA dominance.** All downstream 2SLS results, including h3 formal enforcement, are
   driven by Pennsylvania alone, and PA is a *median*-enforcement state — which cuts
   against a simple "lax mining-state regulator" reading and is why the substitution story
   (missing violation records) is preferred over a forbearance story. Unchecked: whether
   the h2 sanitary-visit 2SLS is also PA-driven. If visits and enforcement move on the
   same PA variation, the substitution interpretation is coherent; if not, the two
   results are identified off different systems.
4. **Instrument timing.** post95 × sulfur coincides with the 1996 SDWA amendments'
   enforcement expansion. Year FE absorb national trends, but a sulfur-correlated
   differential enforcement ramp-up (e.g., a PA-specific post-96 program change) could
   mimic the h3 effect. The temporal-placebo apparatus is the appropriate check.
5. **Discretion/futility story as a complement, not competitor.** Even with full
   monitoring records, regulators may withhold formal action against systems whose
   contamination is externally caused. This is observationally similar to the
   missing-record mechanism in h3; the ratchet evidence (MR violations clustering at the
   trigger) is what distinguishes CWS-side avoidance from pure regulator-side discretion.

## 7. Regulatory citations

- 40 CFR 141.23(d)(2) — nitrate ≥ 50% MCL → quarterly monitoring (the trigger used in
  `mr_concentration_lag.tex`).
- 40 CFR 141.23(f)(2), (i)(3) — nitrate single-sample + 24-hr confirmation compliance.
- 40 CFR 141.23(i)(1) — running annual average for systems monitoring more than annually.
- 40 CFR 141.23(i)(2) — single sample > MCL is a violation for annually-monitored systems.
- 40 CFR 141.23(c)(2), (c)(4), (c)(7) — waiver conditions and post-exceedance quarterly
  ratchet.
- Source text: https://www.law.cornell.edu/cfr/text/40/141.23 (Phase II rule,
  56 FR 3526, Jan. 30, 1991).

## 8. One-line version for the paper

Cross-sectional means confound selection (bad systems get everything) and era effects
(the late-90s enforcement ramp); within-CWS, mining raises regulator *attention* (surveys,
investigations) but lowers formal *sanctions*, consistent with trigger-avoidance
destroying the monitoring record that formal enforcement requires — and even the raw
means agree once the mining split inside the MR+visit cell is read correctly
(22.2% → 17.8%).
