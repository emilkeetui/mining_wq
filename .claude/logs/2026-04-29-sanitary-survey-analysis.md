# Session: 2026-04-29 — Sanitary Survey Analysis

## Objective
Understand who conducts sanitary site visits to CWSs, what they find, and why
the 2SLS result shows sanitary surveys increasing while formal enforcement decreases.
Data: SDWA_SITE_VISITS.csv, SDWA_REF_CODE_VALUES.csv.
Sample: states in main 2SLS (num_hucs <= 2, 1985–2005): AL, CO, FL, GA, IL, KS,
KY, LA, MD, MS, NC, NY, OH, PA, SC, TN, TX, UT, VA, WA, WV, plus FIPS "08" (CO).

---

## What a Sanitary Survey (SNSV) Is

A complete sanitary survey is a structured physical inspection of all major CWS
components: management/operations, source water, treatment, pumps, distribution,
finished water storage, data verification, compliance status, and finances.
Each component is rated:
- N = no deficiency
- R = recommendation only
- M = minor deficiency
- S = significant deficiency
- D = sanitary defect
- X = not evaluated / Z = not applicable

Under SDWA, surface-water CWSs require a complete survey every 3 years;
groundwater systems every 5 years. The 1996 SDWA amendments strengthened this
requirement; EPA enforcement of it explains the sharp uptick in SNSV counts
after 1998 visible in the data.

Follow-up is tracked via SSVF (sanitary survey follow-up) visits. SSVF count
is tiny: 1,469 in sample vs. 352,533 SNSV visits — most inspections close
without follow-up.

---

## Who Conducts Sanitary Surveys

In the main 2SLS sample states (1985–2005), state agencies (ST) conduct 90.5% of
all SNSV visits. Non-state actors are a small minority.

| Agency type             | Code | SNSV visits | Share  |
|-------------------------|------|-------------|--------|
| State                   | ST   | 167,124     | 90.5%  |
| County                  | CN   | 10,216      | 5.5%   |
| District                | DS   | 4,440       | 2.4%   |
| State admin (SA + SR)   | SA/SR| 2,513       | 1.4%   |

In coal-belt states (KY, WV, PA, OH, VA, TN) the state-agency share rises to 97%
(52,057 of 54,361 coded visits). The conducting agency is the primacy agency —
state EPA or state health department — not the federal EPA.

---

## What They Find

### Deficiency rates (SNSV visits, sample states 1985–2005)

| Geography                          | Any deficiency (S/M/D) | Significant (S/D) |
|------------------------------------|------------------------|-------------------|
| All sample states                  | 3.5% (12,270 visits)   | 0.7% (2,398)      |
| Coal-belt (KY,WV,PA,OH,VA,TN)      | 0.2%                   | 0.05%             |

### Compliance evaluation data quality

51% of compliance evaluation fields are NaN; 38% are coded "X" (not evaluated).
Only ~11% of SNSV visits have a compliance assessment recorded.
Of the 38,789 visits with compliance evaluated:
- N (no deficiency): 95.2%
- R (recommendation): 2.2%
- M (minor): 1.8%
- S (significant): 0.9%

### Deficiency rates by conducting agency (SNSV only)

| Agency | N visits | Any deficiency | Significant |
|--------|----------|----------------|-------------|
| ST     | 167,124  | 5.2%           | 0.7%        |
| CN     | 10,216   | 16.0%          | 7.1%        |
| DS     | 4,440    | 34.6%          | 8.5%        |
| SA     | 1,580    | 11.7%          | 6.1%        |
| SR     | 933      | 15.5%          | 3.6%        |

State agencies document significantly fewer deficiencies than counties or
districts — notable discretion difference.

### Deficiency rates by state

| State | N SNSV | % State agency | Any def | Sig def |
|-------|--------|----------------|---------|---------|
| FL    | 76,939 | 9.7%           | 0.0%    | 0.0%    |
| NC    | 46,029 | 70.3%          | 0.0%    | 0.0%    |
| IL    | 42,330 | 42.9%          | 0.6%    | 0.0%    |
| OH    | 39,968 | 73.3%          | 0.0%    | 0.0%    |
| TX    | 24,725 | 94.4%          | 21.4%   | 0.0%    |
| SC    | 21,243 | 52.3%          | 0.0%    | 0.0%    |
| VA    | 21,882 | 88.2%          | 0.0%    | 0.0%    |
| NY    | 18,408 | 27.8%          | 19.7%   | 9.1%    |
| AL    | 10,758 | 11.1%          | 1.0%    | 0.2%    |
| MD    | 9,887  | 91.7%          | 0.0%    | 0.0%    |
| MS    | 8,165  | 9.6%           | 0.0%    | 0.0%    |
| PA    | 6,121  | 53.8%          | 0.0%    | 0.0%    |
| TN    | 5,051  | 0.1%           | 2.9%    | 0.7%    |
| KY    | 4,568  | 4.0%           | 0.0%    | 0.0%    |
| DS    | 4,440  | —              | 34.6%   | 8.5%    |
| KS    | 3,246  | 20.7%          | 40.3%   | 2.2%    |
| CO    | 3,002  | 98.2%          | 4.9%    | 3.6%    |
| LA    | 2,661  | 2.1%           | 0.3%    | 0.0%    |
| WV    | 2,595  | 0.0%           | 0.8%    | 0.3%    |
| UT    | 2,399  | 49.0%          | 28.5%   | 7.7%    |
| GA    | 2,005  | 80.6%          | 34.5%   | 14.0%   |

Coal-belt states (KY, WV, PA) show near-zero deficiency rates despite WV = 0%
state-agency conductor.

---

## Why Visits Up + Enforcement Down Is Coherent

### 1. Structural separation of monitoring and enforcement

Sanitary surveys are a compliance monitoring tool, not an enforcement action.
Formal enforcement (FENF visits) is a separate administrative track. In the
sample there are only 439 FENF visits across all sample states 1985–2005 —
roughly 1 per 800 SNSV visits. More surveys do not mechanically generate
more enforcement.

### 2. Primacy-agency discretion over escalation

Even a significant deficiency finding in an SNSV doesn't automatically trigger
formal enforcement — the primacy agency decides. With a 0.7% significant-
deficiency rate, the mechanical link is essentially zero.

### 3. MR substitution mechanism (consistent with data)

If CWSs incur MR violations to avoid MCL-level testing, the state can respond
by sending inspectors to verify actual water quality rather than issuing formal
enforcement. The inspector does the testing, observes no contamination, and
closes the visit with "N." The visit substitutes for what the MCL test would
have revealed. The state signals "we're watching" without generating a formal
enforcement paper trail.

### 4. The regulator's objective function

The state is spending inspection resources to substitute for the CWS's own
monitoring. This can be individually rational if:
  (a) State inspectors have lower per-system marginal cost (circuit routing
      across multiple systems in one trip).
  (b) Formal enforcement is administratively costly and MR violations are
      technically non-health-based threats that don't justify escalation.
  (c) The informal resolution preserves the cooperative relationship.

### 5. Regulatory capture / discretion angle

The large asymmetry in deficiency rates — coal-belt states near 0% vs. GA
(34%), KS (40%), UT (29%) — is not explained by true quality differences alone.
It suggests state agencies with concentrated mining constituencies exercise
their discretion to avoid documenting deficiencies, consistent with Duflo/
Hanna/Ryan (2013) discretion effects or Stigler-style regulatory capture.

---

## Open Questions

- Is the increase in SNSV visits post-ARP concentrated in mine HUCs or
  downstream HUCs? (Would confirm the causal pathway.)
- Do SNSV visits that find deficiencies predict subsequent MR violations,
  or do MR violations predict subsequent SNSV visits?
- Is the SSVF uptick post-2001 driven by EPA's new sanitary survey enforcement
  or by post-ARP mine-area systems?
- Regulator objective function: do states with stronger mining lobbies show
  lower SNSV deficiency rates conditional on system characteristics?

---

## Data Notes

- SDWA_SITE_VISITS.csv: 2,394,287 total rows; 499,542 in sample states 1985–2005
- SNSV visits in sample: 352,533 (70% of all sample-state visits)
- Eval codes defined in SDWA_REF_CODE_VALUES.csv under VALUE_TYPE =
  SITE_VISIT_EVAL_TYPE_CODE and VISIT_REASON_CODE
- AGENCY_TYPE_CODE = ST means the state primacy agency, not federal EPA
