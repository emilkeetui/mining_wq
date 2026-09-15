# Pairs Cluster Bootstrap — k2 MCL Table Robustness Check

## Why bootstrapping was needed

`output/reg/2sls_dwnstrm_minevio_mcl_ivsum_binvio_k2.tex` (the k2 MCL table,
embedded at `main.tex:761`) shows a significant 2SLS coefficient on arsenic MCL
violations (0.07\* col 3, 0.19\*\* col 4) despite the identifying variation
resting on almost no events: only **5 utility-years** out of 12,492
(666 utilities) ever record an arsenic MCL violation, and all 5 are in
Pennsylvania in 2005.

Leave-one-out checks showed this asymptotic result is fragile — the p-value
crosses 0.05 when any single one of those 5 violating utilities is dropped.
With effectively a handful of clusters driving the result, the usual
clustered-SE asymptotics are suspect, so a resampling-based check was needed.

**First attempt — wild cluster bootstrap (`fwildclusterboot`):** installed
from GitHub (neither `fwildclusterboot` nor its dependency `summclust` is on
CRAN for this R version) and fixed three real package bugs along the way
(character `PWSID` cluster variable, unused factor levels after singleton
drop, fixest's `^` FE-interaction shorthand). This produced usable OLS/RF
results for the base FE spec (PWSID + year), but:

- **2SLS failed on every column** — `object 'X' not found` inside
  `preprocess2.fixest`/`transform_fe`, a `fwildclusterboot`-dev-build /
  `fixest` 0.14.2 incompatibility reproduced on a synthetic dataset unrelated
  to this project. Not fixable without patching package internals.
- **The state×year FE spec failed entirely** — numerically singular for the
  bootstrap machinery (~100+ state-year FE cells relative to a handful of
  events), even after the factor-level fixes.

Since the wild bootstrap could not be estimated for most of the
coefficients that actually matter (2SLS, and anything under the state×year
spec), it was dropped in favor of a **pairs cluster bootstrap**, which
resamples whole utilities rather than working through `fwildclusterboot`'s
internals, and so is agnostic to model type (OLS/RF/2SLS) and FE spec.

## Method

**Sample:** `k2_common.r::build_k2_panel("main")`, filtered per outcome the
same way `render_panel_k2()` does (`dat[!is.na(dat[[oc]]), ]`).

**Outcomes:** `nitrates_MCL_bin`, `arsenic_MCL_bin`,
`inorganic_chemicals_MCL_bin` (0/100-coded binary, ×100-scaled per
project convention).

**FE specs:** `PWSID + year` and `PWSID + year + STATE_CODE^year`.

**Formulas** (`coalvar = num_coal_mines_linked_sum`,
`instrument = post95:sulfur_mean0`, `control = num_facilities`):

```r
f_ols <- y ~ num_coal_mines_linked_sum + num_facilities | <FE>
f_rf  <- y ~ post95:sulfur_mean0 + num_facilities | <FE>
f_iv  <- y ~ num_facilities | <FE> | num_coal_mines_linked_sum ~ post95:sulfur_mean0
```

**Algorithm** (Cameron & Miller, "A Practitioner's Guide to Cluster-Robust
Inference"):

1. Take the unique `PWSID` values in the outcome-filtered sample.
2. For each of `B` replications, sample that many utilities **with
   replacement**.
3. Build the replicate panel from all rows of each sampled utility, but
   relabel `PWSID` per draw slot (`paste0(PWSID, "__", i)`) so a utility
   drawn twice becomes two distinct FE groups — otherwise `fixest` collapses
   the repeated cluster into one FE level and the resampling variation is
   lost.
4. Refit on the replicate panel with no clustering (the loop builds the
   bootstrap distribution of the point estimate itself, not per-replicate
   SEs). Wrapped in `tryCatch`; failed replicates (singleton FE explosion,
   collinear instrument draws) are skipped and counted, not treated as
   errors.
5. Collect the coefficient of interest per replicate — `num_coal_mines_linked_sum`
   for OLS, `post95:sulfur_mean0` for RF, `fit_num_coal_mines_linked_sum` for
   2SLS (via `k2_common.r::get_term()`).
6. Report bootstrap SE (`sd()` of replicate estimates), percentile 95% CI
   (`quantile(., c(.025, .975))`), and a two-sided bootstrap p-value
   `p = 2 * min(mean(boot_est <= 0), mean(boot_est >= 0))`, capped at 1.

`B = 999`, `set.seed()` per outcome×FE column for reproducibility. Script is
scratch-only (not part of the pipeline, not committed) per task guardrails —
lives at
`pairs_bootstrap_k2_mcl.r` in the session scratchpad, not under
`code/coal_mining_water_quality/`.

## Results

Runtime: ~23 minutes total for all 6 outcome × FE-spec columns (OLS + RF +
2SLS each). Failure rate was small everywhere (0–6 of 999 replicates per
column, in both FE specs) — notably the pairs bootstrap did **not** break
down on the state×year 2SLS spec the way the wild bootstrap did.

| Outcome | FE spec | Model | Asymptotic p | Wild-boot p (base FE only) | **Pairs-boot p** | Pairs-boot 95% CI |
|---|---|---|---|---|---|---|
| Nitrates MCL | base | OLS | 0.237 | 0.247 | 0.221 | [−0.039, 0.005] |
| Nitrates MCL | base | RF | 0.570 | 0.890 | 0.765 | [−0.193, 0.068] |
| Nitrates MCL | base | 2SLS | 0.572 | — (failed) | 0.765 | [−0.184, 0.512] |
| **Arsenic MCL** | base | OLS | 0.596 | 0.741 | 0.706 | [−0.099, 0.036] |
| **Arsenic MCL** | base | **RF** | 0.049 | 0.050 | **0.008** | [−0.055, −0.006] |
| **Arsenic MCL** | base | **2SLS** | 0.059 | — (failed) | **0.008** | [0.014, 0.150] |
| Arsenic MCL | state×yr | OLS | 0.829 | — (failed) | 0.759 | [−0.065, 0.076] |
| Arsenic MCL | state×yr | RF | 0.033 | — (failed) | **0.000** | [−0.184, −0.021] |
| Arsenic MCL | state×yr | 2SLS | 0.036 | — (failed) | **0.000** | [0.044, 0.409] |
| Inorganic chemicals MCL | base | OLS/RF/2SLS | 0.43 / 0.65 / 0.65 | 0.47 / 0.67 / — (failed) | 0.43 / 0.65 / 0.65 | all straddle 0 |
| Inorganic chemicals MCL | state×yr | OLS/RF/2SLS | 0.45 / 0.59 / 0.59 | — (failed) | 0.42 / 0.58 / 0.58 | all straddle 0 |

### Key finding

The pairs bootstrap **cuts against** the fragility story suggested by the
leave-one-out checks. Rather than widening the CI toward insignificance, the
arsenic MCL RF and 2SLS coefficients come back **tighter and more
significant** than the asymptotic result in both FE specs (p = 0.008 base
FE; p ≈ 0.000 state×year FE, vs. asymptotic 0.033–0.059). Nitrates MCL and
inorganic chemicals MCL are unaffected and stay insignificant throughout,
consistent with both the asymptotic and (where estimable) wild-bootstrap
results.

**Why the two robustness checks disagree:** with only ~5 distinct
arsenic-violating utilities out of 666, resampling utilities with
replacement drops *all* violators from a replicate only rarely (a naive
iid-draw approximation puts this around 0.7%), so the large majority of the
999 replicates retain at least one violator and the point estimate stays
consistently positive. Pairs-cluster bootstrapping and single-cluster
leave-one-out are answering different robustness questions — average
resampling variability vs. worst-case single-cluster deletion — and here
they point in different directions.

## Caveat for write-up use

If this result is reported, state both checks rather than citing only the
one that is more favorable to significance: the pairs bootstrap supports the
arsenic MCL result under resampling variability, but the leave-one-out
finding that a single utility's removal flips significance still stands as
a legitimate concern about how much of the identifying variation comes from
a small number of Pennsylvania utility-years in 2005.
