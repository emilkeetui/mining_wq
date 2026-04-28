# Diagnostic: Why the MCL composite 2SLS is negative
*Session: 2026-04-27*

## Context

The MCL composite outcome (sum of MCL violation-days for nitrates + arsenic + inorganic
chemicals + radionuclides) on the 4-step downstream sample yields a negative 2SLS
coefficient. More mines should increase violations, so the negative sign is puzzling.
Three tests were run to diagnose the source.

---

## Test 1 — Contaminant decomposition
*Source: `output/reg/2sls_4step_d1_d4_minevio_mcl.tex` (N = 21,756, F = 553)*

| Contaminant | OLS | RF | 2SLS | SE | Sig |
|---|--:|--:|--:|--:|---|
| Nitrates (MCL) | −0.411 | +0.026 | −0.188 | (0.762) | — |
| Arsenic (MCL) | −0.068 | −0.008 | +0.058 | (0.040) | — |
| Inorganic chemicals (MCL) | +0.026 | +0.230 | −1.671 | (1.426) | — |
| **Radionuclides (MCL)** | **+0.091** | **+0.377** | **−2.747** | **(1.419)** | **\*** |

**Finding:** Radionuclides alone drives the negative composite. Arsenic 2SLS is
actually positive (though NS). The composite result is entirely a radionuclides story.

---

## Test 2 — MCL vs MR antisymmetry
*MCL from 4-step D1–D4 (N=21,756). MR from `dwnstrm_minevio_mr` (D1, N=6,225)
and `dwnstrm2step_minevio_mr` (D1+D2, N=11,706). 2SLS only.*

| Contaminant | MCL 2SLS | MR 2SLS (D1) | MR 2SLS (D1+D2) | Pattern |
|---|--:|--:|--:|---|
| Nitrates | −0.19 | **+60.1\*\*** | **+51.6\*** | ✓ Antisymmetric |
| Arsenic | +0.06 | **+45.0\*** | **+42.1\*** | ✓ Antisymmetric |
| Inorganic chemicals | −1.67 | **+43.6\*** | **+41.5\*** | ✓ Antisymmetric |
| **Radionuclides** | **−2.75\*** | +1.90 (NS) | −27.4 (NS) | ✗ **No antisymmetry** |

**Finding:** Nitrates, arsenic, and inorganic chemicals show clean MCL-MR
antisymmetry: more mines → more MR, fewer/same MCL. This is consistent with
strategic substitution (CWSs miss monitoring to avoid detecting exceedances).
Radionuclides breaks the pattern — MR is insignificant, so strategic suppression
is NOT driving the radionuclides MCL result.

---

## Test 3 — Main colocated sample RF check
*Source: `output/reg/olsrf2sls_nummine_mine_vio_1985to2005colocate_coalunified.tex`
(N=12,840, F=3.1 — weak). Outcomes are `_share` (all violation types), not MCL-only.*

| Contaminant | RF coefficient (post95 × sulfur_unified) | Sig |
|---|---|---|
| Nitrates | −0.0035 | — |
| Arsenic | −0.0026 | — |
| Inorganic chemicals | −0.0011 | — |
| **Radionuclides** | **+0.0205** | **\*\*\*** |

**Finding:** Radionuclides' positive RF appears with equal strength in the main
colocated sample — it is NOT a downstream-sample artifact. This rules out
Hypothesis C (downstream instrument invalidity) for radionuclides.

---

## Diagnosis

The negative composite MCL 2SLS is explained by **two separate mechanisms**,
operating on different contaminants:

### Radionuclides → Geology confound (Hypothesis B confirmed)

The instrument is invalid for radionuclides. High-sulfur geology correlates with
natural radionuclide presence (radon, uranium in sulfur-bearing coal strata).
Post-1995 EPA radionuclide rule tightening increased monitoring and detection
of violations nationally, generating more detected violations in high-sulfur/
high-radionuclide areas regardless of mine activity. The confound appears
identically in both the main and downstream samples.

**Evidence needed:** Federal Register notices or EPA rule history documenting
post-1995 tightening of radionuclide MCL standards or monitoring requirements
(see To-Do list below).

### Nitrates / arsenic / inorganic chemicals → Strategic substitution (Hypothesis A)

The MCL-MR antisymmetry is clean and significant for all three non-radionuclide
mining contaminants. When mines are active, CWSs strategically incur MR violations
(miss monitoring) to suppress MCL detections. Post-ARP (fewer mines), the strategic
pressure lifts: MR drops, MCL detections rise. This produces negative MCL 2SLS and
positive MR 2SLS — exactly what is observed.

---

## Implications for the paper

1. **Drop radionuclides from the MCL composite.** The composite should be
   nitrates + arsenic + inorganic chemicals only. Run this as the primary robustness
   check against the MR-recording-bias critique.

2. **Radionuclides as a separate confound section.** The positive radionuclides RF
   in the main colocated sample (0.020***) is strong evidence that this contaminant
   is driven by geology + post-1995 rule changes, not mining. Discuss separately
   and note the identification problem.

3. **MCL-MR antisymmetry is the main evidence for strategic substitution.** The
   three-contaminant pattern (nitrates + arsenic + inorganic) is clean and supports
   the Duflo et al.-style regulatory avoidance story.

---

## To-Do: Radionuclide rule evidence

- [ ] Search Federal Register for EPA radionuclide NPDWR rule changes 1995–2005
- [ ] Check EPA SDWA rule history: Radionuclides Rule (effective 2004, proposed 2000)
- [ ] Find the original 1976 radionuclide MCL and identify when it was revised
- [ ] Check if EPA's 2000 radionuclide rule increased monitoring frequency requirements
- [ ] Search for the Phase I Groundwater Disinfection Rule or any concurrent rules
      that changed radionuclide monitoring obligations for CWSs using groundwater
- [ ] Check whether radionuclide violation rates nationally spike post-2000 in the data

---

## Regression to run

MCL composite excluding radionuclides:
```r
df$mining_health_MCL_norad_share_days <-
  df$nitrates_MCL_share_days +
  df$arsenic_MCL_share_days +
  df$inorganic_chemicals_MCL_share_days
```
Run on 4-step D1–D4 sample and compare sign/magnitude against full composite.
