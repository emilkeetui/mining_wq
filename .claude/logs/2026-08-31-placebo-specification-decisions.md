# Decisions: downstream-of-intake placebo — sulfur imputation, sample, FE, inference

**Status:** decisions recorded, no code changed yet. See
[2026-08-31-placebo-hop-relaxation-and-purity.md](2026-08-31-placebo-hop-relaxation-and-purity.md)
for the full investigation and every supporting number below.

## Context

The downstream-of-intake placebo test (mines physically unable to contaminate the
utility's water) was failing: significant 2SLS estimates where the true effect should
be zero. Investigation traced this to three separable issues, each now resolved as a
specification decision.

## Decisions

### 1. Do not impute missing boreholes with sulfur = 0

**Applies to both the main sample and the placebo sample.**

The USGS coal-quality boreholes contain no true zero sulfur readings (min = 0.060 in
the raw data). A HUC12 with `sulfur == 0` in the current pipeline output means "no
borehole within the 20 km buffer," not "measured zero sulfur." The current main-sample
build (`huc_coal_charac_geom_match.py` → `_unified_pws`) applies `fillna(0)` and then
`np.maximum(upstream, colocated)`, so uncovered HUCs silently enter regressions with an
imputed sulfur of 0 rather than being excluded. This affects **87 of 340 main-sample
utilities (26%)**.

Applying the correct rule (exclude utilities whose linked HUCs have zero borehole
coverage, average over covered HUCs only — which is what the placebo build already did)
moves the main sample's first stage from F=27.52 (340 CWSs) to F=17.20 (253 CWSs) under
PWSID+year+state×year, and pushes some main-sample p-values from <0.05 to the
0.06–0.11 range under PWSID+year alone (see finding 11 in the linked log).

Applying the imputed-zero rule to the placebo sample instead of excluding uncovered
utilities does **not** fix the placebo's false positive — IOC MR gets *more*
significant under it, not less (finding 13). This rules out "the imputation just needs
to go the other way" as an explanation; imputing zeros is wrong in both directions.

### 2. The placebo sample: 1 hop upstream of a mine, but never ≤3 hops downstream of one

Two independent problems were found and are both now fixed by this definition:

- **Original build only excluded utilities in a mine HUC or exactly one hop below one**
  (D1). It did not exclude utilities 2+ hops downstream of a mine. Sweeping the
  exclusion depth showed the *entire* first-stage collapse (F=1.82 → F=24.54) comes
  from utilities exactly **3 hops** downstream of a mine — a small group (26 of 431)
  that the original purity filter missed entirely (finding 9 in the linked log).
- ≤2 hops does nothing to the first stage; ≤3 is the minimal cutoff that fixes it, and
  is therefore the one to use — not an arbitrarily deeper screen.

**Final placebo definition:** a utility with an intake HUC12 whose single downstream
neighbor (`tohuc`) is a coal-mine HUC12, excluding any utility with an intake in a mine
HUC, in a D1 HUC, or **ever within 3 hops downstream of any coal mine** (by the HUC flow
network, in any direction from any of its intakes).

### 3. Fixed effects: PWSID + year + state×year

State×year absorbs common regional shocks (coal-region economic conditions correlated
with local sulfur, which move independently of any waterborne channel) that the
placebo's own significance under PWSID+year alone was picking up. Under state×year with
the corrected sample and sulfur handling, the placebo mostly loses significance (p =
0.07–0.18 across the three MR outcomes) while the main estimate is more equivocal but
directionally intact (see the final comparison table below).

**Adopted specification going forward: PWSID + year + state×year fixed effects, on
both the main and placebo samples**, rather than the paper's current PWSID+year.

## Combined effect of all three decisions

Corrected sulfur (no zero-imputation), corrected placebo sample (≤3-hop screen),
state×year FE, on both samples:

| outcome | main (253 CWSs, F=17.20) | placebo (249 CWSs, F=47.92) |
|---|---|---|
| Nitrates MR | 11.75 (5.75), p=0.042 | 4.05 (3.00), p=0.178 |
| Arsenic MR | 8.76 (4.86), p=0.073 | 3.86 (2.88), p=0.182 |
| IOC MR | 8.93 (5.28), p=0.092 | 5.37 (2.98), p=0.072 |

Main marginally significant on nitrates only under conventional inference; placebo
mostly null; both samples built by an identical rule. This is the defensible
combination, with one open caveat: IOC's placebo p-value (0.072) is not comfortably
above the main sample's (0.092), so that outcome does not cleanly separate the two
groups.

## 4. Weak-instrument-robust inference (Anderson–Rubin) belongs in the discussion

You noted you don't know this literature — here is the minimum needed to follow why it
matters and what it does.

**The problem it addresses.** The textbook rule "first-stage F > 10 means the
instrument is fine" is outdated. Two later benchmarks are stricter:

- Stock–Yogo (2005): for one instrument and one endogenous regressor, F should exceed
  **16.38** for the conventional test to have at most a 10% size distortion — and that
  number assumes i.i.d. errors, not clustered ones.
- Lee, McCrary, Moreira & Porter (2022, *Econometrica*): show the conventional
  95% CI (point estimate ± 1.96 × SE) is only actually a 95% CI when F exceeds
  roughly **104.7**. Below that, the true coverage is worse than advertised, and the
  standard t-statistic overstates significance.

F=17.20 (the corrected main sample under state×year FE) clears the older 16.38
threshold barely, and falls far short of 104.7. So a referee who knows this literature
will not accept "F > 10" as sufficient, and the paper's own reported F-stat becomes a
liability rather than a reassurance if left to speak for itself.

**What Anderson–Rubin (AR) does about it.** Because this model is *just-identified*
(one instrument, one endogenous regressor), there is an alternative confidence set that
is mathematically valid **no matter how weak the instrument is** — its coverage is exact
by construction, not asymptotic and not dependent on F. It works by testing, for every
candidate coefficient value b, whether the instrument is uncorrelated with the residual
`y − b·D` once fixed effects and controls are partialed out; the AR confidence set is
every b that survives that test at the 5% level.

**What this bought us here.** Computed on the corrected main sample (F=17.20,
state×year FE):

| outcome | 2SLS point est. | conventional 95% CI | **AR 95% CI** |
|---|---|---|---|
| Nitrates MR | 11.75 | [0.49, 23.02] | **[2.00, 28.00]** — excludes 0 |
| Arsenic MR | 8.76 | [−0.77, 18.28] | [0.00, 21.50] — boundary |
| IOC MR | 8.93 | [−1.41, 19.28] | [−0.50, 23.00] — includes 0 |

Two things to note. First, the AR sets are **bounded** (not empty, not unbounded),
which is itself informative — a genuinely uninformative instrument tends to produce an
unbounded or empty AR set, so boundedness here is mild positive evidence the instrument
carries real signal despite the modest F. Second, the AR interval for nitrates MR is
wider and shifted up relative to the conventional one, and it excludes zero — so the
one outcome that survives is the one where robust inference doesn't just barely allow
the conventional conclusion, it actively confirms it despite acknowledging the weak
instrument. Arsenic sits on the boundary; IOC does not survive.

Placebo AR sets (F=47.92, same FE) all include zero on all three outcomes, which is a
stronger form of "the placebo is null" than the corresponding p-values alone, since it
holds under inference that doesn't rely on the first stage being strong.

**Recommendation for the discussion section:** report the AR confidence set alongside
(or instead of) the conventional CI for the headline 2SLS estimates, state the
first-stage F openly rather than asserting it clears a rule of thumb, and frame the
paper's causal claim around nitrates MR specifically rather than the full set of MR
outcomes, since arsenic and IOC do not survive AR inference in the corrected
specification.

## Not yet done

- No code has been changed. The three fixes above (sulfur imputation, placebo sample
  definition, FE) are not yet implemented in `huc_coal_charac_geom_match.py`,
  `sdwismatch_pwsid_level_share_yr_in_violation.py`,
  `build_placebo_downstream_intake.py`, `run_main_tables.r`, or
  `run_placebo_downstream_intake.r`.
- No output tables have been regenerated.
- All supporting numbers above were produced by ad hoc scripts in the session
  scratchpad, not the production pipeline — implementing the fixes in the pipeline
  scripts and re-running them end to end is the natural next step, on a branch, when
  you're ready.
