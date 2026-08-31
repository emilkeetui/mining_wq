# Session: 2026-08-31 — Downstream-of-intake placebo: hop relaxation & sample purity

## Objective
Investigate why the downstream-of-intake placebo first stage is weak (F = 1.82) and
whether relaxing the one-hop restriction (summing mines within N hops downstream of
intake) restores instrument strength comparable to the main D1 spec (F = 27.52).

## Method
Read-only diagnostics, all outputs to scratchpad — nothing written to `clean_data/`
or `output/`. Scripts: `hop_diag.py`, `hop_fs.r`, `purity_check.py`,
`deep_exposed_pwsids.py`, `hop_fs_pure.r`, `placebo_pure_2sls.r`,
`placebo_diagnose.r`, `placebo_vs_main.r`.

## Findings

### 1. The "many-to-one aggregation" explanation was wrong
Earlier hypothesis: the main spec's first stage is strong because multiple mine HUCs
drain into each D1 HUC, while an intake has only one downstream neighbour.
**Disconfirmed.** `tohuc` is single-valued (0 HUCs with >1 successor), but the main
sample's upstream branching factor is only **1.16** (340 of 395 D1 HUCs have exactly
one mine HUC upstream, max 3). Aggregation is not the difference.

### 2. The N-hop relaxation does work — but is not needed
Holding the CWS sample fixed and accumulating mines down the chain ("deepen"):
F = 1.82 (N=1) → 6.81 (N=2) → 14.11 (N=3) → 18.60 (N=4), sample essentially unchanged
(6,111 → 6,321 obs). Admitting farther CWSs ("widen") pushes F to 45–120, but that is
mostly sample growth (291 → 1,470 CWSs).

### 3. Root cause: the placebo sample is contaminated
The purity filter in `build_placebo_downstream_intake.py` excludes only CWSs in mine
HUCs or D1 HUCs (exactly one hop below a mine). It does **not** exclude CWSs 2+ hops
below a mine. **76 of 431 placebo CWSs (17.6%) are genuinely downstream of a coal
mine** (2–8 hops). 1,012 HUCs are mine-exposed at 2–8 hops but unclassified.

Dropping them at N=1, with no hop relaxation at all:
| | coef | se | F |
|---|---|---|---|
| as published | −0.0550 | 0.0408 | 1.82 |
| purity-corrected | −0.2602 | 0.0460 | **32.02** |
| main D1 benchmark | −0.2404 | 0.0458 | 27.52 |

The instrument was never weak. Contamination attenuated the coefficient ~4.7×.

### 4. The corrected placebo FAILS
Purity-corrected placebo 2SLS is significant and the same magnitude as the main
estimates, on samples sharing zero CWSs:

| outcome | placebo (se) | main D1 (se) | z | p |
|---|---|---|---|---|
| Nitrates MR | 8.32 (3.67) | 9.93 (3.73) | 0.31 | 0.76 |
| Arsenic MR | 8.39 (3.61) | 7.43 (3.05) | −0.20 | 0.84 |
| IOC MR | 8.80 (3.68) | 7.07 (3.23) | −0.36 | 0.72 |
| Nitrates MCL | −0.52 (0.53) | −0.02 (0.02) | 0.95 | 0.34 |

MR effects are statistically indistinguishable between the two samples. MCL is null in
both. The same MR-not-MCL pattern appears where contamination is hydrologically
impossible, which points to the instrument capturing a regional coal-economy /
utility-capacity channel rather than waterborne contamination.

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| All diagnostics to scratchpad | Exploratory; avoids overwriting production panels |
| First stage only for hop sweep | Doesn't need violation data — skips the slow CSV read |
| 8-hop ceiling for exposure screen | Arbitrary; effect attenuates with distance |
| Read shapefile attrs only (pyogrio) | Skips 1.9 GB of geometry |

## Verification Results
- [x] Scripts run end-to-end, exit 0
- [x] `tohuc` single-successor property confirmed empirically
- [x] Placebo/main CWS sets confirmed disjoint (0 shared PWSIDs)
- [x] Main D1 benchmark reproduces the published F = 27.52 exactly

### 5. RETRACTED — the MR/MCL contrast is uninformative
Finding 4 originally read the MR-significant / MCL-null split as evidence for a
capacity channel over a contamination channel. **This does not hold.** MCL violations
are rare events: base rates are 0.07% (nitrates MCL), 0.01% (arsenic MCL), 0.39%
(IOC MCL) versus 4.5–6.1% for MR. The minimum detectable effect for placebo nitrates
MCL is 1.47 pp against a 0.07 pp base rate — a null there is a power artifact, not
evidence of no contamination. The MR/MCL contrast cannot discriminate the readings.

### 6. State × year FE: partial, not decisive
Absorbing state-level time shocks halves the placebo effect but barely moves the main:

| outcome | main, PWSID+year | main, +state×year | placebo, PWSID+year | placebo, +state×year |
|---|---|---|---|---|
| Nitrates MR | 9.93 (3.73) | 11.32 (5.38) | 8.32 (3.67) | 4.80 (2.83) |
| Arsenic MR | 7.43 (3.05) | 8.01 (4.40) | 8.39 (3.61) | 4.46 (2.76) |
| IOC MR | 7.07 (3.23) | 6.99 (4.64) | 8.80 (3.68) | 5.62 (2.84) |

So roughly half the placebo effect is state-level regional variation. Placebo first
stage strengthens to F = 48.88 under state×year FE.

### 7. RETRACTED — the main-vs-placebo difference test is uninformative
Findings 4 and 6 cited main vs placebo being "statistically indistinguishable"
(nitrates z ≈ 1.07, p ≈ 0.28) as if it supported the placebo effect being the same
size as the main effect. **That is the failure-to-reject fallacy and the claim should
not be made.** For nitrates MR under state×year FE: difference 6.52, SE 6.08, 95% CI
[−5.40, 18.44]. The smallest difference detectable at 80% power is **17.02 pp**. The
test equally cannot reject "placebo = 0" (difference 11.32, inside the CI). It rejects
nothing and should not be cited in either direction. Same for all three outcomes under
both FE specs (MDE 13.2–17.0 pp against observed differences of 1.0–6.5 pp).

### 8. What the placebo evidence actually supports
| spec | main nitrates MR | placebo nitrates MR |
|---|---|---|
| PWSID + year | 9.93 [2.62, 17.23], p=0.008 | 8.32 [1.13, 15.51], p=0.024 |
| + state×year | 11.32 [0.78, 21.86], p=0.036 | 4.80 [−0.75, 10.36], p=0.092 |

Under the paper's current FE spec the corrected placebo is significantly positive on
all three outcomes (p = 0.017–0.024) — a real problem. Under state×year FE the placebo
falls to ~42% of the main estimate with a CI covering zero, while the main effect
survives (IOC MR loses significance, p = 0.13). This pattern favours state-level
regional variation over a confound that also contaminates the main estimate, but does
not clear the exclusion restriction.

### 9. The 3-hop screen localizes the bug
Varying the purity-screen depth shows the entire first-stage collapse is caused by CWSs
*exactly 3 hops* below a mine — 26 systems (406 → 380):

| screen | F | nitrates MR (se) | p |
|---|---|---|---|
| none | 1.82 | 23.79 (20.20) | 0.240 |
| ≤2 | 2.28 | 24.25 (18.02) | 0.179 |
| **≤3** | **24.54** | **8.45 (4.22)** | **0.046** |
| ≤4 | 31.83 | 8.30 (3.70) | 0.026 |
| ≤8 | 32.02 | 8.32 (3.67) | 0.024 |

≤3 is the minimal and most defensible cutoff; the 8-hop screen was unnecessary. Why hop
3 specifically is unexplained and may reflect how `downstream_of_mine` is classified.
`num_facilities` does no work (nitrates MR 8.32→8.83, p 0.024→0.016 when dropped).

### 10. DDD using upstream systems as controls — the water channel does not show up
Pooling both groups (589 CWSs: 340 downstream, 249 upstream controls, ≤3 screen) and
estimating the reduced form
`viol ~ b1*(post95 × sulfur) + b2*(post95 × sulfur × downstream) + FE`:

| outcome | b1 common (se) | p | b2 DDD (se) | p |
|---|---|---|---|---|
| **PWSID + year** | | | | |
| Nitrates MR | −1.923 (0.668) | 0.0042 | −0.293 (0.845) | 0.729 |
| Arsenic MR | −1.946 (0.649) | 0.0028 | 0.347 (0.789) | 0.660 |
| IOC MR | −1.935 (0.661) | 0.0036 | 0.327 (0.824) | 0.692 |
| **+ state×year** | | | | |
| Nitrates MR | −2.061 (0.874) | 0.0188 | −0.792 (0.887) | 0.372 |
| Arsenic MR | −1.947 (0.832) | 0.0196 | −0.125 (0.812) | 0.878 |
| IOC MR | −1.940 (0.850) | 0.0228 | −0.265 (0.856) | 0.757 |

The ARP–sulfur shock moves MR violations by ~2 pp and moves them *identically* for
systems upstream and downstream of mines. No differential downstream effect, both signs
across specs. b1 is negative and the first stage is negative, which is why the levels
2SLS came out positive — consistent, but the association has nothing to do with flow
direction. Power: SE on b2 ≈ 0.85 pp against a common effect of ~1.9 pp, so the test can
detect a differential ~1.25× the common effect — better powered than the naive
main-vs-placebo difference test (finding 7) but not decisive against small effects.

### 11. Sulfur coverage: the placebo was right, the main sample is not
Recomputed HUC12 sulfur from the USGS boreholes without the `fillna(0)` in
`huc_coal_charac_geom_match.py:132`, which conflates "measured zero" with "no borehole
within 20 km".

**There are no true measured zeros.** Minimum borehole sulfur is 0.060; exactly 0
readings equal zero. All 123 mine HUCs (11.0%) carrying `sulfur_colocated == 0` are
genuinely uncovered. So the placebo's `!= 0` filter was already dropping precisely the
no-coverage HUCs — the rebuilt sulfur is **numerically identical** for all 291 utilities.
The requested fix is a no-op on the placebo side.

The main pipeline handles the same zeros the opposite way: `_unified_pws` takes
`np.maximum(up, co)`, so uncovered HUCs enter the regression with sulfur imputed to 0.
**87 of 340 main-sample utilities (26%) carry an imputed sulfur of 0.**

Applying the placebo's coverage rule to the main sample:

| | main as published | main + coverage rule |
|---|---|---|
| **PWSID + year** | 340 CWSs, F = 27.52 | 253 CWSs, F = **12.29** |
| Nitrates MR | 9.93 (3.73) p=0.008 | 10.85 (5.83) p=**0.064** |
| Arsenic MR | 7.43 (3.05) p=0.015 | 7.72 (4.72) p=**0.104** |
| IOC MR | 7.07 (3.23) p=0.030 | 7.98 (5.00) p=**0.112** |
| **+ state×year** | 340 CWSs, F = 22.74 | 253 CWSs, F = 17.20 |
| Nitrates MR | 11.32 (5.38) p=0.036 | 11.75 (5.75) p=0.042 |
| Arsenic MR | 8.01 (4.40) p=0.069 | 8.76 (4.86) p=0.073 |
| IOC MR | 6.99 (4.64) p=0.133 | 8.93 (5.28) p=0.092 |

Under the paper's headline FE the main results lose conventional significance once
sulfur is no longer imputed. Under state×year they are stable to it.

### 12. The one configuration where everything is consistent
Coverage rule applied to BOTH samples, ≤3-hop purity screen, state×year FE:

| outcome | main (253 CWSs, F=17.20) | placebo (249 CWSs, F=47.92) |
|---|---|---|
| Nitrates MR | 11.75 (5.75) p=0.042 | 4.05 (3.00) p=0.178 |
| Arsenic MR | 8.76 (4.86) p=0.073 | 3.86 (2.88) p=0.182 |
| IOC MR | 8.93 (5.28) p=0.092 | 5.37 (2.98) p=0.072 |

Main marginally significant, placebo mostly null, both instruments strong, both
constructed identically. This is the defensible specification. Caveat: for IOC the
placebo (p=0.072) is more significant than the main (p=0.092).

### 13. Placebo with sulfur imputed to 0 (matching main pipeline's fillna(0))
Same placebo sample (1 hop, <=3-hop purity screen), only the treatment of the 131
utilities with no borehole coverage changes: coverage-rule drops them, imputed-0 keeps
them with sulfur set to 0 (obs rises 5,229 -> 7,980 under PWSID+year FE).

| outcome | coverage rule (drop) | imputed to 0 (keep) |
|---|---|---|
| **PWSID + year** | | |
| Nitrates MR | 8.45 (4.22) p=0.046 | 6.93 (4.61) p=0.134 |
| Arsenic MR | 8.45 (4.12) p=0.042 | 8.22 (4.51) p=0.070 |
| IOC MR | 9.23 (4.21) p=0.029 | 10.44 (4.89) p=0.033 |
| F | 24.54 | 24.84 |
| **+ state x year** | | |
| Nitrates MR | 4.05 (3.00) p=0.178 | 6.78 (4.66) p=0.147 |
| Arsenic MR | 3.86 (2.88) p=0.182 | 8.20 (4.58) p=0.074 |
| IOC MR | 5.37 (2.98) p=0.072 | 10.48 (4.92) p=0.034 |
| F | 47.92 | 36.83 |

Imputing to 0 does not clean up the placebo - if anything IOC MR gets *more*
significant (p=0.029 -> 0.033 stays similar; under state x year it goes from p=0.072 to
p=0.034). Nitrates MR is the only outcome that becomes less significant. This is the
opposite of what would be needed to justify keeping the main pipeline's imputation: the
placebo fails at least as badly, sometimes worse, when built the way the main sample is
currently built. This is independent evidence (not just symmetry/fairness) that the
main pipeline's fillna(0) imputation should be fixed.

## Open Questions
- Surface-water split is underpowered (59 CWSs, F = 1.34) — could not rule out the
  groundwater-adjacency channel directly. 83% of the placebo sample is groundwater,
  and HUC12 boundaries are surface-water divides that do not bound aquifers.
- 8-hop screen is arbitrary; sensitivity to the cutoff untested.
- **Best remaining discriminator: distance decay.** If the placebo effect is physical
  leakage it should decay as the downstream mine gets farther from the intake; if it is
  a regional confound it should be flat in hop distance. Requires rebuilding the
  widened panel with violation outcomes (the expensive chunked CSV read).
- Main-sample composition looks odd for a coal study: PA 44.2%, **GA 12.9%**, VA 9.7%,
  WV 7.4%, KY 4.3%. Worth confirming the GA systems are correctly classified.

## Next Steps
- Decide whether to fix the purity filter in `build_placebo_downstream_intake.py`.
- If the regional-shock reading holds, the MR-based main results need a
  utility-capacity control or reframing; MCL results are null throughout.
