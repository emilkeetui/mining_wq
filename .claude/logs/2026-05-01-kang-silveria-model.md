# Session: 2026-05-01 — Kang & Silveria (2019) Model Walkthrough

## Objective
Understand the regulator-regulated equilibrium model in Kang & Silveria (2019, JPE)
and how to derive testable predictions from it.

## Comparative Statics Covered

| CS | Equation | Sign | Meaning |
|---|---|---|---|
| da*/dθ | Facility FOC | + | Higher-cost types violate more |
| da*/dψ | Regulator FOC | Ambiguous | Depends on (1-F)/f vs θ |
| da/dt, t·ε(k) | Facility FOC | − | Proportional penalty increase deters negligence |

## Key Points
- Testable predictions (signs) are separate from structural estimation (counterfactuals)
- e'(·) is a function not a scalar — need shift parameter t for IFT to apply
- Multiplicative shift t·ε(k) natural because ε(k) is the legislatable object
- Additive vs multiplicative shifts both valid; same qualitative sign

## Mining Channels Through the Model

Mining affects the equilibrium through two channels that oppose each other:

| Channel | Object affected | CS sign | Direction |
|---|---|---|---|
| Higher baseline pollution → harder to comply | θ ↑ | da*/dθ > 0 | More violations |
| Higher pollution → violations more harmful | h'(·) ↑ via t·h(a) | da/dt < 0 | Fewer violations |

Net effect ambiguous — depends on which dominates.

Key distinction: b(·) is unchanged by mining. b(a) = cost savings from skipping tests
= cost of running tests, independent of what tests find. θ is the right channel because
it captures compliance difficulty (how hard it is to meet the standard), not input costs.

Implication: reduced-form finding that mining increases violations is consistent with
θ channel dominating, OR with regulator failing to respond to h'(·) increase (capture/
inattention). The H2/H3 enforcement chain analysis tests whether the h'(·) channel
is active — if regulators do not tighten enforcement in response to mining, the channel
is closed and θ alone drives the positive 2SLS coefficients.

---

## Session: 2026-05-06 — Data Feasibility for Full Structural Estimation

### What K&S Actually Need (and What We Have)

K&S identify b'(·) entirely from observed **violations** and **penalty amounts**, using
the facility's first-order condition θb'[a(θ)] = e'[a(θ)]. Their three estimation steps:

1. Estimate penalty schedules e_pre(·) and e_post(·) from violations + penalty dollars
   via a Tobit model (their eq. 13–14), before and after a 2006 enforcement regime shift.
2. Recover the negligence distribution G(·) from observed violation counts (Poisson).
3. Plug penalty schedule and distribution into the FOC to back out b'(·) — no compliance
   cost data needed, only violations and penalties.

Their exogenous variation: 2006 California institutional changes (launch of CIWQS tracking
system + Office of Enforcement), which shifted e(·) without changing b(·).

Our analog for the enforcement regime shift: ARP Phase I (post95 × sulfur_unified), which
changed the production environment and therefore the effective regulatory pressure on
CWSs in high-sulfur watersheds. However, ARP shifts production, not the penalty schedule
directly — so it plays the role of the instrument for mine count in our 2SLS, not a shift
in e(·) per se.

### The Missing Piece: No Dollar Amount in SDWA/ECHO

**Confirmed: SDWA ECHO downloads contain no penalty dollar amount field anywhere.**

The enforcement file (SDWA_VIOLATIONS_ENFORCEMENT.csv) fields are:
ENFORCEMENT_ID, ENFORCEMENT_DATE, ENFORCEMENT_ACTION_TYPE_CODE,
ENF_ACTION_CATEGORY, ENF_ORIGINATOR_CODE, ENF_FIRST_REPORTED_DATE,
ENF_LAST_REPORTED_DATE.

No PENALTY_AMOUNT, no FINE_AMOUNT, nothing numeric attached to enforcement actions.
Dollar amounts would require state enforcement databases or EPA ICIS-SDWA case
management files, which are not publicly released in bulk.

### What We Can Use to Proxy for the Penalty Schedule e(k)

**Enforcement action type codes** (from SDWA_VIOLATIONS_ENFORCEMENT.csv, ~1.4M MR and
~117K MCL records in our sample):

| Code | Description | Share (MR mining / MCL mining) | Cost basis |
|------|-------------|-------------------------------|------------|
| SFM  | State Administrative Penalty assessed | 1.2% / 0.1% | Direct — penalty occurred; no amount |
| SFO  | State Admin/Compliance Order with penalty | 1.1% / 0.2% | Direct — penalty occurred; no amount |
| SID  | State Site Visit for enforcement | 0.2% / 0.6% | Imputable: inspector wage × visit day |
| SIE/SIF | Public notification requested/received | ~18–25% / ~15–25% | Imputable: mail cost × POPULATION_SERVED_COUNT |
| SFL  | Admin/Compliance Order without penalty | 0.8% / 3.5% | Imputable: EPA RIA staff cost estimates |
| SFK  | Bilateral Compliance Agreement | 0.4% / 7.3% | Imputable: similar to SFL |
| SFJ  | Formal Notice of Violation | 18.6% / 9.2% | Low; letter drafting |
| SIA  | Violation/Reminder Notice | 12.8% / 13.7% | Minimal; postage + staff |

**Site visit evaluation codes** (SDWA_SITE_VISITS.csv — separate file):
These give ordinal ratings (N/M/R/S/X/Z/D = None/Minor/Recs/Significant/Not evaluated/
N-A/Sanitary defect) across multiple dimensions:
- FINANCIAL_EVAL_CODE — financial condition of the CWS (direct proxy for compliance cost type θ)
- TREATMENT_EVAL_CODE — treatment system adequacy
- COMPLIANCE_EVAL_CODE — overall compliance
- MANAGEMENT_OPS_EVAL_CODE — management quality
- SOURCE_WATER_EVAL_CODE — source water condition

**Violation measurement fields**:
- VIOL_MEASURE — actual measured contaminant concentration
- FEDERAL_MCL / STATE_MCL — the MCL exceeded
- Exceedance ratio = VIOL_MEASURE / MCL proxies compliance cost: a system at 10× MCL
  faces a larger abatement cost than one at 1.1× MCL.

### Feasible Adaptation: Enforcement Cost Index as e(k)

Rather than dollar penalties, construct a weighted **enforcement cost index** per
violation-period as the proxy for e(k):

**Component 1 — Direct monetary indicator** (anchor):
- Indicator for SFM or SFO (penalty assessed). Even without dollar amounts, the
  probability of formal penalty as a function of k is estimable from the Tobit.
  SFM/SFO probability varies with violation count, providing the nonlinearity K&S need.

**Component 2 — Imputed unit costs** (bulk of the index):
- Public notification cost = (SIE or SIF indicator) × POPULATION_SERVED_COUNT × unit_mail_cost
  Unit_mail_cost: USPS bulk mail rate (~$0.20/piece) + newspaper notice (~$200 flat).
  This scales naturally with system size and is the dominant enforcement action for MCL violations.
- Site visit cost = SID × (BLS state environmental inspector daily wage ~$300–600)
- Compliance order cost = (SFL or SFK) × EPA RIA administrative staff cost (~$2,000–5,000)

**Component 3 — Violation severity** (continuous measure of compliance cost distance):
- Exceedance ratio: VIOL_MEASURE / FEDERAL_MCL for MCL violations.
- Provides continuous within-violation-type variation in how costly compliance would be.

### Identification Challenge

K&S's key identification lever is a regime shift that changes e(·) but not b(·):
- Their shift: 2006 institutional changes → penalty schedule tightened, compliance costs stable.
- Our potential shift: ARP 1995 → mines close in high-sulfur areas → regulatory pressure
  on remaining CWSs may change.

However, ARP does not obviously shift the penalty schedule e(k) for CWSs — it shifts
the treatment burden (b via θ). A cleaner enforcement regime shift for the K&S estimation
would be something like the 1996 SDWA reauthorization or the 1998 Consumer Confidence
Rule, which changed reporting/notification requirements and thus shifted enforcement
costs without directly changing contamination levels.

**Alternative: Use the K&S framework for comparative statics only (not full structural
estimation).** The reduced-form 2SLS gives β̂ (effect of mine count on violations). The
K&S model provides a structural interpretation: β̂ reflects the θ-channel (mining raises
compliance cost type), attenuated or amplified by the h'(·) channel (regulator response).
The enforcement chain results (H2/H3) test whether the h'(·) channel is active.
Full structural estimation of b'(·) and F(·) requires the penalty schedule, which we
cannot cleanly estimate without dollar amounts.

### Recommended Path Forward

| Goal | Feasibility | What's needed |
|------|-------------|---------------|
| Use K&S model for structural interpretation of 2SLS coefficients | High | Model already mapped; current results sufficient |
| Estimate enforcement cost index as proxy for e(k) | Medium | Imputation of unit costs; defensible for reduced-form heterogeneity analysis |
| Recover b'(·) and F(·) via full structural estimation | Low | Requires penalty dollar amounts; not in ECHO; would need state-level FOIA or ICIS data |
| Use FINANCIAL_EVAL_CODE from site visits as proxy for θ distribution | Medium | Requires merging SDWA_SITE_VISITS.csv; visit coverage may be sparse pre-2000 |

---

## Session: 2026-05-06 — Full Feasibility Assessment of Structural Estimation

This section assesses each component of the K&S estimation procedure against the
data available in this project. The appendix (Appendix C) specifies a 4-step
procedure; each step is assessed in turn.

---

### The K&S Estimation Procedure (Appendix C Summary)

**Step 1.** Estimate penalty schedules e_pre(·) and e_post(·) via MLE of a bivariate
Tobit on penalty dollar amount as a function of violation count k and facility
attributes x — separately for the pre- and post-regime periods. Compute the
marginal penalty schedule ê'_j(a|x) by differentiating the estimated e_j(a|x).

**Step 2.** Estimate the negligence distribution G_j(·|x) by MLE of a negative
binomial regression of violation counts K_{i,t} on facility attributes z_{i,t}.
The Poisson-Gamma mixture structure implies:
  mean     = exp(β_{0,j} + β_1 x_{i,t})
  variance = mean × [1 + Δ(z_{i,t})^{-1} × mean]
where Δ(z) = exp(z δ) is the overdispersion parameter.

**Step 3.** Recover regulator preference parameters {γ_{j,r}, ψ_j} by solving the
system of equations (A.5) and (A.6) at the identified type values {θ_l} from
Step 2. Uses the ratio of e'_post to e'_pre evaluated at G^{-1}(u) quantiles —
requires both e'_j(·) from Step 1 and G_j(·) from Step 2.

**Step 4.** Recover F(·|x) (type distribution) and b'(a|x) (marginal compliance cost)
from the quantile function:
  b̂'_j(a|x) ≡ ê'_j(a|x) / Q̂_j[Ĝ_j(a|x)|x]
where Q̂_j is the quantile function of F estimated in Step 3.
Numerically integrate to obtain b̂_j(a|x).

---

### Component-by-Component Feasibility

#### Component 1 — Penalty Schedule e(k): BLOCKED

**What K&S need:** Dollar penalty amount per violation record, used to estimate
a bivariate Tobit:
  ε*_{1,i,t} = x_{i,t}φ_{1,x} + 1_{t>2006}φ_{1,post} + φ_{1,k}k_{i,t} + u_{1,i,t}
  log ε*_{2,i,t} = log[exp(x_{i,t}φ_{2,x})k_{i,t} + φ_{2,k²}k²_{i,t}] + u_{2,i,t}
  ε_{i,t} = ε_{2,i,t} if ε*_{1,i,t} ≥ 0, else 0

**What we have:** ENFORCEMENT_ACTION_TYPE_CODE (categorical), no dollar amounts
anywhere in SDWA ECHO (confirmed: data dictionary has no PENALTY_AMOUNT or
FINE_AMOUNT field in any file).

**Impact:** Cannot estimate e_pre(·) or e_post(·). Since Steps 3 and 4 both
require e'_j(·), this single gap blocks the entire structural estimation chain.

**Workaround assessed:**
- Imputed cost index (public notification × population + site visit + compliance order)
  gives an ordinal enforcement burden measure, not a dollar penalty schedule.
  The Tobit requires a continuous dollar outcome with a mass at zero; the imputed
  index is a constructed weighted sum with no natural censoring structure.
- Probability of formal action Pr(SFM or SFO | k, x) is estimable and gives the
  slope of a binary penalty indicator. This is a monotone function of k and
  provides the nonlinearity K&S need in e(·), but the scale is dimensionless
  (probability, not dollars) — so b'(·) recovered from the FOC would be a
  cost-per-unit-probability-of-penalty, not a dollar cost.
- **Verdict:** Imputation gives a structurally interpretable proxy only if one
  is willing to redefine the "penalty" as expected enforcement burden rather
  than expected dollar fine. The structural interpretation of b'(·) and γ changes.

#### Component 2 — Negligence Distribution G(·): FEASIBLE WITH ADAPTATION

**What K&S need:** Quarterly violation counts per facility, estimated via
negative binomial MLE on facility characteristics. K&S sample: 228 facilities
× ~60 quarters ≈ 13,000 facility-quarter observations (8,429 used for
negligence estimation per Table A5).

**What we have:** Annual PWSID × year violation counts, 1985–2005, for ~56,842
CWSs (mining subsample much smaller — several thousand CWSs in HUCs with
mine exposure). Facility characteristics: POPULATION_SERVED_COUNT, PRIMARY_SOURCE_CODE,
OWNER_TYPE_CODE, num_facilities, num_hucs.

**Adaptation required:**
- Annual rather than quarterly Poisson rate. The model works at any time unit;
  just reinterprets a (negligence) as annual rate rather than quarterly rate.
- CWS characteristics are thinner than K&S's CWNS-augmented attribute vector
  (no treatment technology, no capacity utilization rate, no design flow).
  FINANCIAL_EVAL_CODE and TREATMENT_EVAL_CODE from SDWA_SITE_VISITS.csv could
  partially substitute but site visit coverage is sparse pre-2000.
- Violation rates in SDWA are much lower than NPDES MMP violation rates:
  K&S's average facility has 1.39 violations/quarter in the pre-period.
  SDWA CWSs have much sparser violations — most PWSID × years are zero even
  in the mining sample. This creates a severe zero-inflation problem that the
  negative binomial can handle but with lower precision on G(·).

**Verdict:** Step 2 is the one component that is feasible with available data.
Estimating G(·) from annual violation counts is doable and novel for SDWA.
The zero-inflation is manageable but will produce wide confidence intervals
on the tails of G(·), which propagates to imprecision in Steps 3 and 4.

#### Component 3 — Regime Shift (Identification): PARTIALLY FEASIBLE

**What K&S need:** An exogenous shift in the penalty schedule e(·) that does
not change b(·) or F(·). Their shift: 2006 California institutional changes
(CIWQS launch + Office of Enforcement). Verified by:
  (a) Penalties and compliance rates both increase post-2006 conditional on
      facility attributes (Table A1, Appendix A.1)
  (b) Past violations do not predict current penalties, ruling out dynamic
      enforcement (Table A2, Appendix A.2)
  (c) Compliance cost structure stable: 95% of facilities pre-date 2004,
      capital investment constant at ~$1.87B/year (Appendix A.1 footnote 30)

**What we have:** Three candidate shifts, none as clean:

1. **1996 SDWA Reauthorization** — strengthened public notification requirements,
   added right-to-know, increased EPA oversight. Changed the structure of MR
   violations (what must be reported, to whom, with what public notice). Plausibly
   shifts e(·) — more violation types are penalizable — while leaving treatment
   costs b(·) unchanged. Problem: the reauth also changed the MCL standards for
   some contaminants (e.g., disinfection byproducts), which could shift b(·)
   for some systems via treatment technique requirements.

2. **2001 Arsenic Rule** — reduced the MCL for arsenic from 50 ppb to 10 ppb,
   effective 2006 (compliance date). Created a wave of arsenic MCL violations.
   This clearly shifts b(·) — the cost of complying with arsenic standard increased
   substantially — so it is the wrong kind of shift for K&S identification.

3. **ARP Phase I (post95 × sulfur_unified)** — our main instrument. Shifts coal
   production → changes CWS compliance cost environment via water quality (θ
   channel). This is a shift in b(·) via θ, not a shift in e(·). Does NOT work
   as a K&S-style regime shift.

**Verdict:** The 1996 SDWA reauth is the best candidate for an enforcement regime
shift in our setting. It changed what constitutes a reportable violation and what
public notification is required, effectively tightening the enforcement function
e(·), without mechanically changing treatment technology requirements b(·).
However, the assumption that b(·) is unchanged is harder to verify than in K&S's
setting (no continuous water quality measure to control for ambient trends).
Feasibility: moderate, with appropriate robustness checks.

#### Component 4 — Regulator Preferences γ and ψ: BLOCKED (pending Step 1)

**What K&S need:** e'_j(·) from Step 1, evaluated at quantiles of G_j from
Step 2, to solve the system (A.5)-(A.6). The system recovers:
  γ_{j,r} — social cost weight on violations (linear in a: h(a) = γ·a)
  ψ_j — marginal enforcement cost per unit of expected penalty

**What we have:** Cannot estimate γ or ψ without e'_j(·). The enforcement
cost index proxy changes the interpretation: with a probability-of-formal-action
proxy for e, γ would reflect the social cost of violations per unit of escalation
probability, not per dollar of penalty.

**Verdict:** Blocked by Step 1. Even with the imputed enforcement burden index,
the system (A.5)-(A.6) can be solved formally, but the recovered γ and ψ are
not comparable to K&S's parameters and cannot be used for welfare comparisons
without external calibration of the dollar scale.

#### Component 5 — Type Distribution F(·) and Marginal Cost b'(·): BLOCKED

**What K&S need:** Both e'_j(·) and Q̂_j from Steps 1-3. The key formula is:
  b̂'_j(a|x) = ê'_j(a|x) / Q̂_j[Ĝ_j(a|x)|x]

**What we have:** Cannot compute b̂'_j without ê'_j. Even if a regime shift
(1996 reauth) identifies the ratio e'_post/e'_pre via the transforms T^H and T^V
(Propositions 2-3), the *levels* of e'_j are needed to recover b'(·) from the FOC.
The ratio alone identifies the shape of b'(·) up to a scale factor.

**Partial identification result:** The shape of b'(·) — whether it is concave or
convex, where the inflection point is — is identified from the ratio e'_post/e'_pre
and the regime-change transforms (Appendix B.1.4-B.1.5), even without the levels.
This means the *qualitative* comparative statics of the model (is the high-cost
type θ more or less likely to violate?) are identified, but counterfactual welfare
calculations (which require the dollar scale of b) are not.

**Verdict:** Shape of b'(·) is partially identified; levels and welfare calculations
are blocked. This partial identification result is actually the most novel
contribution of a K&S-style adaptation for our setting.

#### Component 6 — Environmental Harm h(·): PARTIALLY FEASIBLE

**What K&S need:** A continuous, time-varying measure of ambient environmental
conditions at the facility level to control for h(·). K&S use dissolved oxygen (DO)
saturation from STORET/NWIS — a direct measure of water quality impairment.

**What we have:**
- Rule code (331/332/333/340) identifies contaminant type, which proxies for which
  type of harm the violation causes (nitrate = health risk to infants; arsenic =
  cancer risk; radionuclides = long-term cancer; inorganic chemicals = mixed).
- VIOL_MEASURE / FEDERAL_MCL gives exceedance severity for MCL violations, but
  this is endogenous (it is a realized violation, not ambient conditions).
- Sulfur content of coal seams (sulfur_unified) proxies for acid mine drainage
  potential but not for the actual ambient water quality at the CWS intake.
- No equivalent of DO saturation available in the current project data.

**Impact:** Without a continuous h(·) proxy, Proposition 3 (recovering γ from the
regulator's FOC) cannot condition on ambient pollution, so estimated γ would
conflate the regulator's perception of harm with actual ambient conditions.

**Verdict:** Partially feasible — contaminant type dummies provide a coarse
control for cross-sectional variation in h(·). Within-CWS time-series variation
in h(·) is not captured. This introduces attenuation in the γ estimates.

#### Component 7 — Static Enforcement Assumption: FEASIBLE

**What K&S need:** Penalty schedule is static — past violations do not predict
current penalties conditional on current violation count (verified in Table A2).
The argument is that compliance is mainly operational/maintenance, not capital
investment, so there is no history-dependent deterrence mechanism.

**Our setting:** SDWA CWS compliance is even more operational than NPDES wastewater
treatment. MR violations (monitoring/reporting) account for 88% of our sample and
require correct sampling and reporting procedures, not capital. MCL violations
for nitrates and arsenic reflect water quality and treatment operations. The
argument that compliance is short-term maintenance rather than long-term investment
applies directly. Moreover, Table 2 in K&S shows no dynamic enforcement for NPDES;
the same absence of dynamic enforcement is plausible for SDWA, where the MMP
equivalent (the formal enforcement escalation) is similarly rare.

**Verdict:** The static enforcement assumption is at least as defensible in our
setting as in K&S's. No blocker.

#### Component 8 — Counterfactual Analysis: BLOCKED

**What K&S need:** Full estimated model (F, b', γ, ψ) to compute violations and
penalties under alternative penalty schedules (uniform, linear, targeted).
For the uniform penalty counterfactual (Appendix D.1), requires:
  - b̂'(a|x) to solve for facility negligence given any ε̃
  - γ̂(x) and ψ̂(x) to define regulator's objective
  - F̂(·|x) to integrate over the type distribution

**What we have:** None of the above in estimated form.

**Verdict:** Fully blocked. Cannot compute welfare or policy counterfactuals
without the full model.

---

### Summary Feasibility Table

| K&S Component | Required inputs | We have | Feasibility |
|---|---|---|---|
| Step 1: Penalty schedule e_j(k) | Dollar penalty amounts | Action type codes only | **BLOCKED** |
| Step 2: Negligence distribution G_j(·) | Violation counts + facility chars | Annual PWSID counts + PWS file | **FEASIBLE** (adaptation) |
| Step 3: Regulator preferences γ, ψ | e'_j(·) from Step 1 + G_j from Step 2 | Blocked by Step 1 | **BLOCKED** |
| Step 4: b'(·) and F(·) | e'_j(·) + Q̂_j from Steps 1-3 | Blocked by Step 1 | **BLOCKED** |
| Regime shift identification | Shift in e(·), stable b(·) | 1996 SDWA reauth (weaker) | **PARTIAL** |
| Facility characteristics x | CWNS: treatment tech, capacity, flow | PWS file: size, source, ownership | **MOSTLY FEASIBLE** |
| Environmental harm h(·) | Continuous ambient quality measure | Contaminant type dummies only | **PARTIAL** |
| Static enforcement | No dynamic penalty history | Plausible for SDWA MR violations | **FEASIBLE** |
| Counterfactual welfare analysis | Full estimated model | Nothing | **BLOCKED** |

---

### What Can Be Implemented With Current Data

**Tier 1 — Already done / immediately feasible:**
Use K&S model for structural interpretation of the 2SLS β̂. The positive β̂
(mining increases violations) is consistent with the θ-channel dominating
(mining raises compliance costs). The enforcement chain H2/H3 results test
the h'(·)/γ channel. This is the cleanest contribution: a structural
interpretation of reduced-form results, with no additional estimation.

**Tier 2 — Feasible with ~1 week of estimation work:**
Estimate G_j(·|x) (Step 2) from annual PWSID × year violation counts using
negative binomial MLE — separately for "pre" (pre-1996) and "post" (post-1996
or post-2001 arsenic rule) regimes. This produces:
  - The distribution of negligence levels across CWSs by characteristics
  - The estimated overdispersion parameter δ (heterogeneity in compliance behavior)
  - A partial identification of the shape of b'(·) via the T^H and T^V transforms
This would be novel for the SDWA literature and publishable as a standalone result.

**Tier 3 — Feasible if penalty data can be obtained:**
Full Steps 1-4 if penalty dollar amounts can be obtained via FOIA from EPA ICIS-SDWA
or from state primacy agencies (e.g., PA DEP, WV DEQ, KY DOW) for the subset of
states in the sample. The mining states in our sample (WV, KY, PA, OH, VA) are
exactly the states where CWS violations are concentrated — a targeted FOIA
request for these states might yield sufficient coverage for Step 1.

---

### Single Sentence Verdict

Full structural estimation of the K&S model is infeasible with publicly available
SDWA data because no dollar penalty amounts are recorded anywhere in SDWA ECHO;
Step 2 (negligence distribution) is feasible and novel; structural *interpretation*
of existing 2SLS results via the K&S framework requires no additional data.

---

## Session: 2026-05-06 — Imputed Costs and ARP as Identification

### Question 1: Can imputed enforcement costs substitute for the penalty schedule?

**Short answer: Yes, with a unit caveat.**

The facility FOC is θb'[a*(θ)] = e'[a*(θ)]. This is an equation between two
functions; neither requires dollar units as long as both sides share the same
unit. If e*(·) is an imputed enforcement burden index rather than a dollar
penalty schedule, the FOC still holds — the recovered b'(·) is then in units
of "compliance cost per unit of enforcement burden," not dollars.

What is preserved under imputation:
- The ordinal ranking of CWS compliance cost types (which CWS has higher b')
- The shape of b'(·): concave, convex, inflection point location
- Comparative statics: da*/dθ, da*/dψ signs
- Counterfactual RANKINGS of CWSs under alternative enforcement policies

What requires external calibration to recover:
- The dollar magnitude of b'(·) — needs anchoring to at least one point where
  the dollar cost of a violation is known (e.g., a compliance order with a
  known cost estimate from EPA regulatory impact analysis)
- Welfare calculations in dollar units

The imputed e*(k) must satisfy the same structural requirements as K&S's e(k):
(i)  Increasing in k: more violations → higher enforcement burden. Satisfied
     by construction if e*(k) = Σ_action Pr(action | k, x) × unit_cost_action,
     since the probability of all enforcement actions is weakly increasing in k.
(ii) Convex in k: the marginal enforcement burden is increasing in violations.
     Plausible — going from 0 to 1 violation triggers a notice; going from 4 to 5
     may trigger formal action. The escalation structure of SDWA enforcement
     (informal → formal → administrative order → penalty) is convex by design.
(iii) Two regimes: e*_pre(a) < e*_post(a) for all a > 0. Requires a shift in
     the enforcement burden function — see Question 2 and regime shift discussion
     in the previous feasibility assessment section.

The ratio e*'_post(a) / e*'_pre(a) needed for T^V is identified as long as
the imputed cost index changes across regimes in a way that is estimable from
the data (i.e., enforcement escalation probabilities shift with the regime change).

**Verdict:** Imputation is a valid substitution if (a) a clean enforcement
regime shift can be found to shift e*(·), and (b) one accepts that b'(·) is
identified in enforcement-burden units. All qualitative conclusions about the
type distribution and compliance cost heterogeneity survive. Counterfactual
welfare in dollars requires external anchoring.

---

### Question 2: Can the ARP instrument substitute for the regime shift?

**Short answer: No — and here is the precise reason why.**

#### What the regime shift does (precisely)

The regime shift changes e(·) while holding F(·) and b(·) constant. Under this
shift, the SAME type θ sets TWO different negligence levels:

    Pre-regime:  θ × b'[ā(θ, pre)]  = e'_pre[ā(θ, pre)]
    Post-regime: θ × b'[ā(θ, post)] = e'_post[ā(θ, post)]

Dividing the two equations:

    b'[ā(θ, post)] / b'[ā(θ, pre)] = e'_post[ā(θ, post)] / e'_pre[ā(θ, pre)]

The θ cancels on the left. The right side is observed from estimated penalty
schedules. This gives the RATIO of b' at two different negligence levels without
knowing θ — it traces the SHAPE of b'(·) independently of the unknown type.

The transforms formalize this:
- T^H(a) ≡ G^{-1}_pre[G_post(a)]: for negligence level a in the post regime,
  returns the level the SAME type would have set pre-regime. Identified from
  violation distributions alone — no penalty data required.
- T^V(θ, a) ≡ [e'_post(a)/e'_pre(a)] × θ: given a type and pre-regime level,
  returns the type setting that level in the post regime. Requires e'_post/e'_pre.

Together they generate a recursive sequence (θ_0 → a_1 → θ_1 → a_2 → ...) of
identified (θ_l, a_l^pre, a_l^post) triples. At each triple, b'(a_l) is pinned
down from the FOC given θ_l. F(θ_l) = G_post(a_l^post). This is what K&S call
"partial identification" via the regime shift.

#### What ARP does (precisely)

ARP (post95 × sulfur_unified) shifts the TYPE θ while holding e(·) and b(·)
constant. Mine closures in high-sulfur areas after 1995 reduce the compliance
difficulty (lower ambient contamination), moving CWSs from a higher type θ_H
to a lower type θ_L < θ_H. The SAME penalty schedule applies before and after.

Two FOC equations for the same CWS before and after ARP:

    Pre-1995 (high-sulfur):  θ_H × b'[ā(θ_H)] = e'[ā(θ_H)]
    Post-1995 (high-sulfur): θ_L × b'[ā(θ_L)] = e'[ā(θ_L)]

Dividing:

    [θ_H / θ_L] × [b'[ā(θ_H)] / b'[ā(θ_L)]] = e'[ā(θ_H)] / e'[ā(θ_L)]

Now there are TWO unknowns on the left: the type ratio θ_H/θ_L AND the ratio
of b' at two different points. The right side is observed if e(·) is known.
But θ_H/θ_L is the thing being identified — it cannot also serve as known
information. There is one equation and two unknowns: unidentified.

#### The geometric intuition

Think of the b'(·) curve in (a, b') space. The regime shift gives you the same
type θ at two DIFFERENT horizontal positions (two negligence levels), letting you
read off two points on the curve. ARP gives you two DIFFERENT types at different
horizontal positions — you're moving along the type distribution G(·) (different
θ values), not tracing the b'(·) curve for a fixed θ. You cannot separate the
contribution of the type change from the curvature of b'(·).

#### What ARP CAN identify within the K&S framework

ARP identifies the SHIFT IN THE TYPE DISTRIBUTION F(·). Specifically:

- In high-sulfur areas, the ARP-induced mine closures reduce θ by a known
  mechanism (reduced acid mine drainage → lower ambient sulfide concentration
  → lower treatment cost to meet MCL). The 2SLS reduced form already captures
  this: β̂ = (∂a*/∂θ) × E[θ_H - θ_L | complier].
- This means ARP variation identifies the SUPPORT of F(·) that was affected
  by ARP: the quantiles of the type distribution that correspond to CWSs in
  high-sulfur, mine-adjacent watersheds.
- More formally: ARP shifts G(·) — the negligence distribution — by shifting
  the type distribution F(·) in affected HUCs. This is Step 2 variation, not
  Steps 3-4 variation.

ARP does not construct T^H because T^H requires the SAME F(·) in both periods
(same types, different negligence). ARP violates this: F_pre ≠ F_post in
high-sulfur areas. G^{-1}_pre[G_post(a)] no longer maps the same type across
regimes — it maps different types, breaking Lemma 2's logic.

#### Correction: ARP affects all CWSs, not a treatment subgroup

A critical error in the earlier analysis: the instrument is post95 × sulfur_unified,
which is CONTINUOUS and shifts both high-sulfur and low-sulfur CWSs simultaneously
in OPPOSITE directions. High-sulfur mines face the largest cost increases from ARP
Phase I and contract most; low-sulfur mines face less competition and may expand.
Consequently:

- High-sulfur CWSs: mines close → less contamination → θ falls (easier to comply)
- Low-sulfur CWSs: mines expand → more contamination → θ rises (harder to comply)

There is NO subgroup of CWSs whose type distribution F(·) is stable after 1995.
The instrument generates a continuous rotation of F(·) across the sulfur spectrum,
not a treatment/control split. The earlier suggestion to use low-sulfur CWSs as
a "control" for the K&S T^H/T^V identification was therefore wrong: low-sulfur
CWSs also experience a shift in F(·), just in the opposite direction.

This means ARP cannot be combined with an enforcement regime shift in the way
described — the K&S enforcement shift identification requires F(·) constant
across regimes, but ARP ensures F(·) is not constant for any subgroup.

#### What β̂ actually captures (corrected)

The causal chain is: ARP → mine production → water quality → θ → a*(θ) → violations

So the 2SLS β̂ is:

    β̂ = (∂a*/∂θ) × (∂θ/∂mine)

This is the PRODUCT of two structural objects:
1. (∂a*/∂θ): the structural sensitivity of equilibrium negligence to the
   compliance cost type — the K&S object of interest
2. (∂θ/∂mine): the production-to-type link — how much mine activity raises
   the compliance cost of the CWS (via water quality degradation)

The 2SLS does NOT separate these two components. It recovers their product
at the complier margin (CWSs whose mine exposure changed due to ARP variation
in sulfur content × post-1995 timing). Earlier statements that β̂ captures
"(∂a*/∂θ) × Δθ" were an oversimplification — Δθ is itself (∂θ/∂mine) × Δmine,
so β̂ = (∂a*/∂θ) × (∂θ/∂mine) is the correct compound derivative.

#### What ARP identifies within K&S (corrected)

ARP generates continuous variation in the compliance cost type θ across CWSs
indexed by sulfur content × post-1995. The variation traces out the equilibrium
response of violations to changes in the production environment — the slope of
a*(θ) × the production-to-type link — at the complier margin.

ARP does NOT identify b'(·) for two reasons, not one:
1. It moves different types along a*(·) rather than moving the same type
   across two penalty schedules (the earlier reason — still correct)
2. It compounds (∂a*/∂θ) and (∂θ/∂mine) inseparably; the regime shift
   isolates (∂a*/∂θ) at known types θ_l through the FOC directly

#### Summary: What each source of variation identifies

| Source of variation | What shifts | What is held constant | What is identified |
|---|---|---|---|
| K&S 2006 regime shift | e(·) — same type, two levels | F(·) and b(·) | Shape of b'(·); F(·) at identified types |
| ARP (post95 × sulfur) | F(·) — continuously across sulfur spectrum | e(·) and b(·) | β̂ = (∂a*/∂θ) × (∂θ/∂mine); not b'(·) alone |
| 1996 SDWA reauth (proposed) | e*(·) enforcement burden | F(·) and b(·) | Shape of b'(·) in enforcement-burden units |

ARP and the enforcement regime shift are NOT complements in the K&S sense:
ARP destabilizes F(·) for all CWSs, breaking the constant-F assumption that
the T^H/T^V identification requires. They operate through different primitives
and cannot be combined as originally suggested.

#### Operational conclusion

The 2SLS result already extracts the maximum structural content ARP can deliver
within K&S: β̂ = (∂a*/∂θ) × (∂θ/∂mine), a compound of two structural objects
that cannot be further decomposed without additional variation. Full recovery of
b'(·) and F(·) requires an enforcement regime shift that changes e(·) while
holding F(·) and b(·) constant — a condition ARP cannot satisfy and cannot
substitute for.
