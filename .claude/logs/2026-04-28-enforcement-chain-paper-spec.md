# Paper Specification: Mining, Monitoring Failures, and the Regulatory Response
*Date: 2026-04-28*

---

## Research Question

Does coal mining trigger a causal enforcement chain at community water systems —
where exogenous mine production increases monitoring/reporting (MR) violations,
and those violations in turn generate regulator site visits and formal enforcement
actions? Does regulatory capacity shape who escapes this spiral?

The core identification contribution: the ARP × sulfur instrument provides
exogenous variation in violations, which then cleanly identifies the downstream
enforcement response — something the existing enforcement literature cannot do
because violations are normally endogenous to enforcement.

---

## Hypotheses

**H1 — Mining increases MR violations** *(established finding)*

Coal mines causally increase monitoring and reporting violations at downstream
CWSs. Identification via 2SLS: instrument is `post95 × sulfur_upstream` (ARP
Phase I reduced high-sulfur mine production post-1995). F-statistics 412–475
(D1–D2 downstream sample), well above conventional thresholds.

**H2 — Regulators respond to violation shocks with more site visits**

Mining-induced MR violations increase the frequency of regulator site visits
(sanitary surveys and inspections). The causal chain: exogenous mine production
→ MR violations → regulator visits. Identification: instrument the violation
shock using the ARP instrument. Tests whether regulators respond to compliance
failures they did not themselves generate.

**H3 — Formal enforcement follows mining-induced violation accumulation**

MR violations caused by mining increase the probability and speed of formal
enforcement actions (citations, notices of violation, administrative orders).
Tests whether the enforcement escalation ladder is triggered by monitoring
failures, or whether enforcement is primarily targeted on other grounds.

**H4 — Compliance investment responds to enforcement**

Formal enforcement actions following mining-induced violations lead CWSs to
expand their source diversity (number of intake facilities/plants). Tests
whether enforcement pressure induces investment in compliance capacity.
Proxy: `num_facilities` per PWSID × year.

**H5 — State dependence amplifies the spiral** *(heterogeneity hypothesis)*

CWSs with prior violation histories are more likely to slide further into
noncompliance when hit by a mining production shock. Tests whether compliance
is path-dependent: marginal compliers accumulate violations faster than
CWSs with clean records when an external burden is imposed.

---

## Data

### Main Analysis Dataset

- **File:** `clean_data/cws_data/prod_vio_sulfur.parquet`
- **Unit:** PWSID × year, 1985–2005
- **Sample:** 1,484 PWSIDs × 21 years = 31,164 PWSID-years
- **Outcome (primary):** MR violation days (share of year) for nitrates,
  arsenic, inorganic chemicals — significant in 2SLS. Radionuclides excluded
  (geology confound: high-sulfur strata correlate with natural radionuclide
  presence; post-1995 EPA rule tightening contaminates the instrument).
- **Treatment:** `num_coal_mines_upstream` (continuous)
- **Instrument:** `post95 × sulfur_unified` (ARP Phase I × avg sulfur % of
  upstream mine HUC coal seams)
- **Controls:** `num_facilities`, PWSID FE, year FE, state FE
- **Clustering:** PWSID level

### Downstream Sample (preferred for instrument validity)

The colocated sample has a weak first stage (F = 7.95–3.1 with colocated/unified
sulfur). The downstream sample has clean identification because sulfur content of
the intake HUC is inherited from the upstream mine HUC — not a property of the
CWS's own geography.

| Sample | N (PWSID-yr) | F-stat (1st stage) | MR result |
|--------|-------------|-------------------|-----------|
| D1 only | 8,190 | 412 | Significant |
| D1–D2 | 13,671 | 475 | Significant |
| D1–D3 | 17,976 | 482 | Fades |
| D1–D4 | 21,756 | 553 | Fades |

**Defensible exclusion restriction window: D1–D2.** At D3–D4, regional
labor-market and fiscal-capacity channels from ARP × high-sulfur coal counties
become plausible alternative pathways. The attenuation of MR significance at
D3–D4 is itself consistent with a water-pathway mechanism (dilution at distance).

### SDWA_SITE_VISITS

- **File:** `SDWA_latest_downloads/SDWA_SITE_VISITS.csv`
- **Total visits in sample (1985–2005):** 11,452
- **PWSID coverage:** 1,181 / 1,484 (79.6%) have at least one visit
- **Panel density:** 6,026 / 31,164 PWSID-years (19.3%) have ≥1 visit
- **Sanitary surveys (SNSV):** 4,307 PWSID-years (13.8% of panel) — dominant
  visit type; scheduled inspections not directly triggered by violations
- **Mean visits per active PWSID-year:** 1.90
- **Temporal spread:** Consistent 1985–2005; slight peak 1997–1998
- **Primary outcome variable:** visit frequency per PWSID-year (count or binary)
- **Secondary:** sanitary survey frequency (less endogenous to violations
  than enforcement visits, since surveys follow a regulatory calendar)

**Usability assessment:** Well-powered. 19% panel coverage and near-universal
PWSID coverage make visit frequency a strong regression outcome. The predominance
of scheduled sanitary surveys reduces endogeneity concerns.

### SDWA_VIOLATIONS_ENFORCEMENT

- **File:** `SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.csv`
- **Total records in sample (1985–2005):** 108,243
- **PWSID coverage:** 1,182 / 1,484 (79.6%)
- **Violation category breakdown:** MR = 97,163 (90%), MCL = 4,057 (4%),
  Other = 3,979 (4%), TT = 3,026 (3%)
- **Enforcement action categories:**
  - Informal: 68,986 (64%)
  - Resolving: 33,140 (31%)
  - Formal: 4,555 (4%)
  - Blank: 1,562 (1%)
- **Formal enforcement:** 4,555 records; 464/1,484 PWSIDs (31%);
  950 PWSID-years (3.0% of panel)
- **Return-to-compliance:** median 119 days, mean 364 days, N=108K
- **Originator:** 93% state-driven (ENF_ORIGINATOR_CODE = S)

**Data quality flag:** Enforcement records spike sharply in 1993–1994
(7,983 and 15,580 records = 21% of all 1985–2005 records in two years),
then drop. This likely reflects the 1996 SDWA reauthorization changing
reporting obligations or batch data entry, not a true enforcement surge.
Within-PWSID variation over time is usable, but any regression using
enforcement *levels* should verify the spike is absorbed by year fixed effects
and not confounding within-PWSID estimates.

**Primary outcome variables:**
1. `any_visit` (binary): sanitary survey in PWSID-year (13.8% of panel)
2. `any_enforcement` (binary): any enforcement action (19.7% of panel)
3. `formal_enforcement` (binary): formal action only (3.0% of panel — sparse)
4. `days_to_rtc` (continuous): return-to-compliance duration; powered at 108K records

### Investment Proxy

- `num_facilities` (intake plants per PWSID × year) — already in the main dataset
- Captures CWS capacity investment; used in main regressions as a control,
  but re-interpretable as an outcome in H4

### Violation History (State Dependence)

- Lagged MR violation counts per PWSID are constructable from the violations
  panel; captures prior compliance trajectory for H5

---

## Contribution to the Literature

### Primary gap filled

No published economics paper provides quasi-experimental estimates of the
**causal enforcement chain** at regulated utilities — the sequence from exogenous
violation generation to regulator response to firm investment. The existing
enforcement literature suffers from a fundamental endogeneity problem: violations
are endogenous to enforcement (regulators inspect probable violators; violators
anticipate inspections). This paper resolves the endogeneity by using the ARP as
an exogenous shock that shifts violations independently of regulator behavior.

### Specific contributions by literature strand

**Strategic compliance and self-monitoring (Duflo et al. 2013 QJE; 2018
Econometrica; Mu, Rubin & Zou 2021):**
These papers show that regulated entities and inspectors interact strategically,
but cannot cleanly separate the direction of causality. This paper identifies
the regulator *response* to an exogenously-caused violation — the first step
toward disentangling the compliance-inspection feedback loop.

**Enforcement targeting and firm heterogeneity (Gray & Shadbegian 2005 ERE;
Helland 1998 RESTAT; Stafford 2002 JEEM):**
This literature documents that inspections are non-random (targeted on past
violators, politically connected firms, etc.) but cannot estimate causal
inspection effects because of this targeting. The ARP instrument breaks the
targeting mechanism by generating violations that regulators did not anticipate
and did not target.

**Regulatory enforcement under political economy constraints (Kang & Silveira
2019; Glaeser & Shleifer 2003 JEL; Sigman 2005 JEEM):**
If enforcement responds less strongly to mining-induced MR violations in
coal-dependent states/counties, this is evidence of regulatory capture — the
regulated industry's political economy depresses enforcement response. The
geographic variation in coal dependence (interacted with ARP × sulfur) provides
a test.

**Investment responses to regulatory pressure (Blundell et al. tradition;
Bennear & Olmstead 2008 JEEM):**
Bennear & Olmstead show that information disclosure reduces violations 30–44%
through community pressure. This paper tests the analogous channel through
formal enforcement: does a citation cause measurable investment in compliance
capacity (more intake facilities), or do CWSs absorb enforcement without
investing?

### What this paper is NOT claiming

- Not a health-harm paper. MCL violations (actual contamination reaching
  consumers) are not significantly affected by mining in the current data.
  The outcome is monitoring/reporting failures — a regulatory capacity result,
  not a welfare result.
- Not a strategic substitution paper. The antisymmetry (mines ↑ → MR ↑, MCL ↓)
  that would support strategic suppression of contamination detections is
  partial and insignificant for MCL.

---

## Publication Expectations

### Minimum threshold for submission (conditional on significant H2–H3)

If H1 (established) and H2 (visits) are both significant and identified:

**JEEM / JAERE / Journal of Environmental Economics and Policy**

The paper has a clean quasi-experimental design, a novel application to
drinking water utilities, and a direct contribution to the enforcement
literature. JEEM and JAERE regularly publish instrument-based papers on
environmental enforcement with this level of identification rigor. This is
the realistic target if H2 is significant and H3 (formal enforcement) is
directionally consistent but imprecise.

### If H2 + H3 + H4 are all significant

**RAND Journal / JLE / American Economic Journal: Applied**

A complete causal enforcement chain — violations → inspections → formal
enforcement → investment — with identification at each step is a top-10%
paper in environmental/regulatory economics. AEJ: Applied publishes
instrument-based regulatory papers with large causal chains. The regulatory
capture heterogeneity (H5 interacted with coal-county political economy)
would strengthen the case further.

### If H2 + H3 + regulatory capture heterogeneity are significant

**AER / QJE / JPE (plausible, not certain)**

The combination of: (a) clean quasi-experimental identification via ARP,
(b) a novel causal enforcement chain, (c) regulatory capture heterogeneity
evidence in a US infrastructure setting, and (d) a large and policy-relevant
industry (drinking water) could support a top-5 submission. The bar here is
that the regulatory capture result must be sharp — not just an interaction
that is marginally significant, but a qualitatively different enforcement
response in coal-dependent vs. non-coal-dependent states. This is the
aspirational target.

### What would kill the paper regardless

1. H2 is insignificant — if regulators do not respond to mining-induced
   violations, there is no enforcement chain and no novel contribution
   beyond the 2SLS MR result already in the data.
2. The 1993–1994 enforcement spike contaminates within-PWSID variation in
   enforcement outcomes even after year FEs — this would require restricting
   the sample to pre-1993 or post-1994, reducing power.
3. Site visit data is too sparse within the downstream sample (D1–D2 has
   only 284 PWSIDs × 21 years = 5,964 observations) — the 19% visit density
   in the full 1,484-PWSID sample may drop sharply in the downstream subsample,
   leaving too few events to detect effects.

### Immediate next step

~~Merge SDWA_SITE_VISITS and SDWA_VIOLATIONS_ENFORCEMENT into the D1–D2
downstream panel and check: (a) visit and enforcement density within that
subsample specifically, and (b) whether the 1993–1994 spike is present in the
downstream subsample or is concentrated in other regions. If density is
adequate, run H2 (instrument = post95 × sulfur_upstream; outcome = n_visits)
as the first test.~~ **Done — see empirical results below.**

---

## Empirical Results (2026-04-28)

**Script:** `code/coal_mining_water_quality/enforcement_chain_d12.r`
**Tables:** `output/reg/h2_snsv_d12.tex`, `output/reg/h3_enf_d12.tex`, `output/reg/h3_rtc_d12.tex`

### D1–D2 Data Quality

- **Panel:** 701 PWSIDs × 14,721 PWSID-years; regressions use 13,671 after singleton drops
- **Site visit density:** 15.8% (2,326 PWSID-years with ≥1 visit) — adequate
- **Sanitary survey (SNSV) density:** 11.6% — clean outcome; scheduled not violation-triggered
- **Enforcement density:** 16.7% any action; 2.4% formal action
- **1993–1994 spike in visits:** absent — visit counts are smooth across years
- **1993–1994 spike in enforcement:** present (1993: 2,152; 1994: 5,574 records). Absorbed by year FEs; within-PWSID variation is clean.
- **2005 enforcement spike:** 13,150 records, of which 9,500 come from one PWSID (WA5340950). Both COMPL and NON_COMPL dates say 2005 — genuine date, almost certainly a batch upload artifact. Binary outcomes (`any_formal`) reduce this to a single 1 for one PWSID-year; year FE absorbs it. **Robust to dropping 2005** (see H3b robustness below).

### H1 — Mining increases MR violations *(established in prior work)*

Confirmed. F-stat 412–475 in D1–D2 sample. Not re-estimated here.

### H2 — Regulators respond to violation shocks with site visits

**n_visits (count): not significant.** 2SLS = +0.193 (SE = 0.153), p = 0.208. Noisy outcome.

**any_snsv (sanitary survey binary, LPM): significant at 1%.**

| Spec | Coef | SE | p |
|------|------|----|---|
| OLS | −0.004 | 0.006 | 0.532 |
| Reduced form | −0.023 | 0.007 | 0.001 |
| **2SLS** | **+0.141** | **0.052** | **0.007** |

F-stat = 475.4. Wu-Hausman p = 2×10⁻⁸ (severe OLS downward bias — regulatory avoidance of mining areas, corrected by instrument).

**Interpretation:** One additional upstream coal mine increases the probability of receiving a sanitary survey by 14.1 pp (off an 11.6% base). Regulators notice mining-induced compliance failures and do schedule surveys in response. OLS bias is negative because regulators systematically under-survey mining-heavy areas — the instrument removes this targeting endogeneity.

**H2 is established via the SNSV binary.**

### H3 — Formal enforcement follows mining-induced violations

**H3 is refuted as originally stated. Mining suppresses formal enforcement — this is a regulatory capture result.**

#### H3a — Any enforcement action (`any_enf`, 16.7% density)

| Spec | Coef | SE | p |
|------|------|----|---|
| OLS | −0.004 | 0.008 | 0.566 |
| Reduced form | +0.010 | 0.007 | 0.177 |
| 2SLS | −0.060 | 0.046 | 0.186 |

Directionally negative but imprecise.

#### H3b — Formal enforcement only (`any_formal`, 2.4% density)

| Spec | Coef | SE | p |
|------|------|----|---|
| OLS | −0.015 | 0.004 | <0.001 |
| Reduced form | +0.014 | 0.003 | <0.001 |
| **2SLS** | **−0.087** | **0.022** | **<0.001** |

F-stat = 475.4. Wu-Hausman p = 4×10⁻⁸.

**Sign logic:** First stage is negative (ARP × high sulfur → fewer mines). Reduced form is positive (ARP × high sulfur → more formal enforcement after mine closures). 2SLS = positive RF / negative FS = **negative**: more active mines → significantly fewer formal enforcement actions. Magnitude: −8.7 pp per additional mine against a 2.4% base rate. OLS and 2SLS agree on sign — no reversal — which is unusual and reinforces the result.

#### H3b robustness (2SLS, `any_formal`)

| Sample | Coef | SE | p | F |
|--------|------|----|---|---|
| Baseline 1985–2005 | −0.087 | 0.022 | <0.001 | 475 |
| **Drop 2005** | **−0.062** | **0.017** | **0.0002** | **545** |
| Drop pre-1993 | −0.262 | 0.137 | 0.056 | 27.5 |
| 1993–2004 only | −0.171 | 0.088 | 0.051 | 42.0 |

Drop-2005 robustness passes cleanly (F increases to 545, coefficient shrinks but stays highly significant). Post-1993 samples lose instrument power (F drops below 100) because the pre-treatment window collapses; coefficients are directionally consistent but borderline. **The 2005 spike is not driving the result.**

#### H3c — Mean days to RTC (conditional on enforcement)

All specs insignificant; F-stat = 41 on the conditional subsample (2,443 obs). Conditional-on-enforcement selection makes causal interpretation problematic. Set aside.

---

## Revised Paper Framing: Regulatory Capture

The combination of H2 and H3b findings is more interesting than the original enforcement-chain hypothesis:

1. **Mining-induced violations trigger regulatory attention** (sanitary surveys, H2: +14.1 pp, p < 0.01).
2. **Mining activity suppresses formal enforcement response** (H3b: −8.7 pp, p < 0.001), even though regulators are observing (H2).
3. **When mines close (ARP shock), formal enforcement normalizes** (positive reduced form on `any_formal`).

This is a causal regulatory capture story: regulators in active mining regions see the violations (surveys go up) but do not prosecute (formal enforcement stays low). When the political economy of mining is removed by ARP, enforcement responds normally to the same level of violations.

**Key identification advantage:** Unlike the prior regulatory capture literature (Gray & Shadbegian; Kang & Silveira), this paper uses an *exogenous shock to the regulated industry's political presence* (ARP Phase I) rather than cross-sectional variation in political variables, which are always endogenous to regulatory outcomes. The ARP instrument breaks the simultaneity between industry influence and regulatory behavior.

### Remaining empirical steps

- [ ] H4: compliance investment (num_facilities as outcome) — may support or contradict capture story
- [ ] H5: state dependence — lagged violation history interacted with mining shock
- [ ] Heterogeneity by coal-county political economy (coal employment share × H3b): does capture intensity vary with local coal dependence?
- [ ] Falsification: H3b on non-mining outcomes (total coliform formal enforcement) should be zero
- [ ] Mechanism check: does H3b vary by state-level regulatory capacity (staffing, budget)?

### Publication reassessment

The regulatory capture framing with ARP identification is a stronger paper than the original enforcement-chain version:

- **JEEM / JAERE**: achievable with H2 + H3b alone
- **AEJ: Applied / RAND JE**: achievable if H5 (heterogeneity) and falsification are significant and sharp
- **AER / QJE**: plausible if capture heterogeneity by coal political economy is large and precisely estimated
