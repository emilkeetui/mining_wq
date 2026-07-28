# Session: 2026-07-27 — Continuous DiD estimators and parallel-trends diagnostics

## Objective

User asked whether R packages implement continuous difference-in-differences
estimators (citing Callaway, Goodman-Bacon & Sant'Anna, NBER w32117), with the
goal of testing parallel trends for
`output/reg/6yr_huc02fe_inorg_ravalli_2005.tex` — the 6-Year Review inorganic
chemicals regression on cumulative upstream coal production.

## Package survey

| Package | Status | Fit |
|---|---|---|
| `contdid` 0.1.1 | On CRAN; implements w32117 exactly | **Not feasible** — see below |
| `did` 2.5.1 | On CRAN | Binary treatment only |
| `didimputation`, `did2s` | On CRAN | Binary/staggered |
| `HonestDiD` 0.2.8 | On CRAN | Needs pre-period coefficients — unavailable |

None installed in `Z:/ek559/RPackages` (290 packages; has fixest, arrow, dplyr,
ggplot2). Nothing was installed this session.

### Why `contdid` cannot be used

Documented limitations at https://bcallaway11.github.io/contdid/ — the package
does **not** support time-varying doses, unbalanced panels, or covariate
adjustment. All three bind:

1. `dname` must be time-invariant. `coal_prod_upstream_cumsum_10mst` is a
   running cumsum that rises every year.
2. No covariate adjustment (`xformula = ~1` only) — would lose `num_facilities`.
3. Requires balanced panel. Arsenic 1998–2005: 117 CWSs, median 3 years each,
   only 9 balanced across 8 years.

Plus there is no `gname` (treatment-start year) in the current design.

## Check (1) — is an event date identifiable?

Ran a diagnostic on the downstream 6YR sample. **This is the binding constraint
for the whole exercise.**

G = first year of positive upstream production, estimation sample (225 CWSs):

| G | N |
|---|---|
| 1985 (left-censored) | 112 |
| 1986–1997 | 59 |
| 1998+ | 14 |
| Never | 40 |

Only **10 CWSs** show a genuine zero→positive onset within 1998–2005. Not enough
for an event study, let alone `cont_did()` with bootstrap bands.

Corrected an earlier wrong assumption: mining is **not** "always-on." 166 of 225
estimation-sample CWSs have zero upstream production throughout 1998–2005 —
mining is intermittent, and there is a genuine never-treated group.

Also noted (user deferred investigating): dose is heavily right-skewed —
median 0.031, mean 0.469, max 14.18 (10M ST), 47 CWSs at exactly zero.

## What was built

`code/coal_mining_water_quality/pt_diagnostics_6yr.r` → exit 0. Produces:

- `output/reg/pt_balance_6yr.tex`
- `output/reg/pt_eventstudy_violations.tex`
- `output/fig/pt_eventstudy_violations.png`

### (A) Cross-sectional balance test — 122 CWSs

Dose measured **1998–2005**, regressed on CWS characteristics. 4 columns:
cumulative dose and any-mining, each without and with HUC02 FE.

| | (1) no FE | (2) no FE | (3) HUC02 FE | (4) HUC02 FE |
|---|---|---|---|---|
| DV | Cumul. dose | Any mining | Cumul. dose | Any mining |
| Joint F | 1.206 | 5.672 | 0.576 | 4.008 |
| p | 0.308 | <0.001 | 0.748 | 0.001 |

**Intensive margin passes cleanly** (p = 0.31 / 0.75); no individual covariate
significant. **Extensive margin fails** (p < 0.001 / 0.001), driven by
`num_facilities` (0.095/0.093, p<0.01) and public ownership (p<0.10).

Since the table's regressor is continuous, the intensive margin is the relevant
one. `num_hucs` and `source_protected` drop for collinearity (constant on sample).

### (B) Continuous-dose event study on violations — 155 CWSs

Treated = onset 1986–1997 (89), plus never-treated (66). Dose is time-invariant
(mean annual upstream production over 5 years post-onset). N = 2,818.

| Outcome | Pre-trend joint F | p |
|---|---|---|
| Inorganic chemicals (any) | 1.275 | 0.272 |
| Inorganic chemicals (MCL) | 0.437 | 0.823 |
| Radionuclides (any) | 1.216 | 0.299 |

Pre-trends jointly insignificant for all three.

## Design decisions

| Decision | Rationale |
|---|---|
| Dose time-invariant in (B), not cumsum | Interacting event time with a cumsum trends upward mechanically — would "fail" under the null |
| Never-treated assigned to reference bin | `fixest::i()` drops NA event-time rows entirely; see bug below |
| Dose window 1998–2005 in (A) | Original 1985–2005 window meant 66% of dose accrued before the covariates were dated |
| Covariates limited to backcast pop + SYR2 | User instruction: only these are appropriate for this period |
| Report violations test with explicit caveats | User's objection (binarization + monitoring confound) is correct; it's a necessary-not-sufficient condition |

## Bugs caught and fixed

1. **Never-treated silently dropped (B).** First run lost all 1,190
   never-treated observations because `i()` discards NA event-time rows —
   estimation rested only on differential onset timing among treated units.
   Fixed by assigning never-treated to the reference bin (dose = 0, so all
   interactions are 0; they identify the FEs only). N went 1,632 → 2,818;
   pre-trend p-values shifted 0.339→0.272, 0.880→0.823, 0.135→0.299.

2. **Balance test had wrong dose timing.** Originally used 1985–2005 dose
   against 1997/SYR2 covariates — 66% of dose accrued *before* the covariates,
   so it was a contemporaneous association, not a balance test. Restricting to
   1998–2005 flipped the reading: intensive margin went p = 0.255 → 0.748
   (cleaner), extensive margin p = 0.079 → 0.001 (worse), and the driver
   changed from public ownership to `num_facilities`.

3. **Table notes overstated covariate timing.** Claimed the DV was measured
   "strictly after the covariates are dated." False for the SYR2 block — all 122
   CWSs draw their record from 1998–2005 (41 in 1998, rest later). Only
   `log_pop_1997` pre-dates the window, and it is itself interpolated between
   the 1990 and 2000 census anchors. Notes corrected; framing changed to
   "comparability check" rather than a test of selection on pre-determined
   characteristics. Mitigating fact verified: all five SYR2 attributes are
   perfectly time-invariant within CWS (0 of 122 vary), so the record year does
   not change the value — but time-invariant ≠ pre-determined, and
   `num_facilities` is the one plausibly responsive to mining.

## Sample overlap (verified against the published table)

Reproduced the table's per-column nobs exactly (334, 432, 322, 328, 319).

- Table union across 5 columns: **91 CWSs**; intersection: 62
- **(A) balance = 122 CWSs — superset of the table union, 0 missing** ✓
- **(B) event study = 155 CWSs — overlaps only 46 of 91** ✗

The 45 table CWSs absent from (B): 33 have G = 1985 (left-censored), 12 have
G ≥ 1998. Roughly half the table's CWSs are structurally incapable of appearing
in any pre-trends test.

## Verification

- [x] `pt_diagnostics_6yr.r` runs end-to-end, exit 0 (re-run 4×)
- [x] All three output files exist and are non-trivial
- [x] Table nobs reproduce the published table exactly
- [x] Sample overlap with target table quantified
- [x] Balance sample confirmed a superset of the table sample

## Open questions / caveats

- **Radionuclides column in (B) is not usable** — every coefficient ≈ ±4 with
  SE ≈ 1.9, flipping sign at k=0 and k=3. Near-collinear artifact from few
  high-dose CWSs (outcome 6.3% nonzero). Should be dropped from any write-up.
- **Inorganic MCL is very sparse** — 0.39% nonzero, 47 CWSs nationally ever
  positive 1985–2005. Its p = 0.823 is a low-power pass.
- **Extensive-margin columns in (A) rest on 27 CWSs** with positive post-1998
  dose. Fragile.
- **`num_facilities` is dropped for collinearity in every column of the
  published table** (absorbed by PWSID FE), so its balance failure does not
  contaminate the estimates.
- **PT for the concentration regression remains untestable.** No estimator fixes
  33 left-censored CWSs.
- Console prints `p = 0` for model 2 in (A) — `round(w$p, 4)` artifact, not a
  real zero. Cosmetic, log only.

## Next steps (not started)

- Dose skew investigation — user said "not now"
- No packages installed; if `contdid` is ever wanted, the design must be
  restructured (time-invariant dose, defined G, outcome extended pre-G)
