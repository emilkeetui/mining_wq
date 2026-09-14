# Session: 2026-09-14 — Top-3 step-grid cells: enforcement, visits, concentration

## Objective
For the top-3 ranked cells from `.claude/logs/2026-09-14-step-grid-ranking-and-fstat-mechanism.md`
(k=2, k=7, k=8; main arm, A-full column, PWSID+year+state x year FE), test how results move
for regulator enforcement, regulator visits, and mean measured contaminant concentration, on
the main sample. Terminal-only diagnostic, no production pipeline changes.

## Approach
- Part A (enforcement/visits): query existing `step_grid_results.parquet` /
  `step_grid_firststage.parquet` — no re-estimation, those cells were already computed in the
  2026-09-13 run.
- Part B (concentration): new estimation. Ported the sample construction and specification
  from `cws_6year_review_huc02fe.r`'s `6yr_huc02fe_inorg_ravalli_2005` table (arsenic,
  nitrate, barium, selenium; `VALUE ~ cumulative upstream coal dose + num_facilities |
  PWSID + huc02^year`, cluster PWSID), swapping the step-grid k-linkage in for that table's
  fixed one-step-downstream sample filter.

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| Concentration outcome uses OLS on cumulative dose, not the grid's IV | `post95:sulfur_mean0` is degenerate on the concentration sample — every non-missing VALUE observation at or before 2005 falls in 1998-2005, so post95≡1 and is absorbed by the PWSID FE; sulfur_mean0 is time-invariant within PWSID×arm×k. Verified empirically before planning. |
| Chemicals restricted to arsenic/nitrate/barium/selenium | Matches the published `_ravalli_2005` table exactly; chromium/thallium already excluded/filtered there and confirmed zero rows in the joined step-grid sample. |
| k=1 included as reproduction anchor | Confirms the ported construction reproduces the original table's sign/magnitude before trusting k=2/7/8. |

## Correction made mid-session
**`STATE_CODE` column collision.** First run of `build_dose_sample()` left-joined a
`STATE_CODE` lookup from `cws_covariates_steps.parquet` onto `d6r`, but
`cws_6year_review_ravalli.parquet` already carries its own `STATE_CODE` column — the join
silently produced `STATE_CODE.x`/`STATE_CODE.y` and every `PWSID + STATE_CODE^year` model
errored (caught, not silently wrong: printed as `--`/`NA` for all 16 chem×k cells). Fixed by
dropping the redundant join and using `d6r`'s own `STATE_CODE` directly.

## Verification Results
- [x] Script runs end-to-end, exit 0
- [x] Part A F-stats at k=2/7/8 match 50.01/46.44/53.30 (2026-09-14 log) — reproduced exactly
- [x] Part B k=1 coefficients match published table exactly under huc02^year FE (arsenic
  0.0023***, nitrate 0.0572, barium 0.0171*, selenium 0.0033**)
- [x] Row counts match planning estimates (k=1: 1,558/122 CWS; k=2: 1,716/132; k=7: 2,127/159; k=8: 2,183/161)

## Findings

### Part A — enforcement & visits move together, and the state x year FE matters a lot
Across k=2/7/8 (main, A-full), all four outcomes hold the same sign as at k=1 and mostly
strengthen: more sanitary/enforcement visits, less formal/informal enforcement (i.e. more
regulator attention, less punitive follow-through) as k grows. But magnitudes shrink
sharply once state x year FE is added — e.g. sanitary visits at k=8 go from 1.20*** (PWSID+
year) to 0.34** (+state x year), and enforcement-visit/formal-enforcement significance is
touch-and-go at conventional levels under the fuller FE. The placebo arm is *not* clean here:
at k=7 and k=8 under PWSID+year alone, placebo enforcement-visit and formal-enforcement
coefficients are similarly or more significant than main — only when state x year FE is
added does the placebo's formal/informal enforcement coefficients go to null while main
stays marginally significant (k=7: main -0.48*** vs placebo 0.43 n.s.; k=8: main -0.39** vs
placebo 0.43 n.s.). So the same "state x year FE is what makes the top-3 cells clean"
pattern that drove the original MR-outcome ranking recurs here.

### Part B — concentration levels do not confirm the violation-share result
Under OLS cumulative-dose (not IV — infeasible here, see note above), only nitrate and
selenium show significant coefficients at k=2 (nitrate 0.088***, selenium 0.0004**, both
FE specs), and both go to null by k=7/k=8. Arsenic and barium are null at every k>=2 despite
being the cleanest MR-violation outcomes in the original ranking. This is a real divergence
worth flagging: the violation-share grid says arsenic is the cleanest signal, but arsenic's
own measured concentration shows no dose-response in this (much smaller, SYR2-restricted,
1998-2005-only) sample. Plausible reasons not yet investigated: the concentration sample is
an order of magnitude smaller (122-161 CWSs vs 666-1703 in the violation grid) and restricted
to systems large enough to trigger SYR2 monitoring, so this is not the same population as the
violation-share result, and violation *shares* can move via monitoring/reporting behavior
independent of the underlying analyte level.

## Coverage check (follow-up)
Checked what share of each k's main arm actually has SYR2 concentration coverage (not done
in the original run). Match rate to the target-chemical, non-missing-VALUE, arm-year-overlap
sample declines sharply as k grows: k=1 31.7% (122/385), k=2 19.8% (132/666), k=7 9.9%
(159/1599), k=8 9.5% (161/1703) — because SYR2 monitoring coverage plateaus around 340-409
PWSIDs regardless of k while the arm itself balloons via upstream fan-out. The k=7/8
concentration estimates are drawn from an increasingly unrepresentative, likely
larger-utility-skewed slice of the arm; the k=2 concentration read is more trustworthy for
that reason.

## Part C — mr_concentration_lag_ols spec re-run on k=2 main arm (follow-up, new script)
New script `code/coal_mining_water_quality/run_mr_concentration_lag_ols_k2.r`. Reproduces
`mr_concentration_lag_ols.r`'s nitrate MR-violation-following-a-near-MCL-reading regression
(`mr_same_fwd`/`mr_same_fwd6mon` ~ `near_mcl` + `mean_conc_z` | PWSID + YEAR, cluster PWSID),
swapping that script's fixed national downstream-of-mine PWSID set for the k=2 main-arm set.
Window-matching logic (build_mr_concentration_lag.py's mr_same_fwd/fwd6mon construction)
ported inline rather than imported, restricted to nitrate-only since that's all this spec
uses (no rule333/anyioc machinery needed). No clean_data/ or output/ writes.

Result: near-identical to the published national table (near_mcl 58.93* (24.55) vs published
58.97** (24.60) at 1-yr; 26.07* (10.51) vs 26.11** (10.53) at 6-mon; N=835 vs 851). The k=2
main arm (666 CWSs) evidently contains nearly the same identifying PWSIDs as the production
downstream-of-mine sample — expected, since only 3 `near_mcl==1` readings exist in the k=2
sample at all, so the coefficient is driven by a handful of the same observations regardless
of which upstream/downstream sample definition is used. Significance drops from ** to * here
only because of the slightly smaller effective cluster count (82 vs the published sample's
underlying PWSID count), not because the estimate moved.

## Open Questions / Blockers
None blocking. Two substantive questions for the user, not pipeline defects: (1) the Part
A/Part B divergence on arsenic (violation-share says clean, concentration-level says null),
and (2) whether the sharply declining SYR2 coverage at high k should disqualify k=7/8 from
the concentration comparison entirely.

## Next Steps
None initiated pending user follow-up on the arsenic divergence and coverage caveat.
