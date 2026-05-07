# Structural Model Analysis: Penalty-Stage-Only Approach
## Session: 2026-05-06

---

## Objective

Evaluate whether the Duflo, Greenstone, Pande & Ryan (2018) structural model of
regulator–firm enforcement interactions can be adapted to the coal mining × drinking
water quality setting, and if so, in what form. Determine what comparative statics
are available and how to structure the full paper.

---

## Key Findings: What Duflo et al. (2018) Does

The paper combines a **field experiment** (randomized doubling of inspection rates for
960 industrial plants in Gujarat, India) with a **two-stage structural model** of
regulator–plant interactions. The experiment is not just reduced-form evidence — it
is used directly to identify key structural parameters:

- The **targeting stage** parameters (how aggressively the regulator concentrates
  inspections on high-pollution plants) are identified by comparing the distribution
  of inspections in the discretionary control group vs. the randomly-assigned treatment
  group. The gap reveals the regulator's private information (σ₁² vs σ₂²).
- The **abatement efficacy** parameter (φ₂) and **abatement cost** distribution are
  identified by the distribution of pollution outcomes across treatment and control.
- Andrews, Gentzkow & Shapiro (2017) sensitivity analysis confirms the experimental
  variation is the primary driver of these parameter estimates.

Counterfactuals show that discretionary inspections cause 3× more abatement than
randomly-assigned inspections at the same inspection budget — the core policy result.

---

## Mapping to the Coal Mining × Water Quality Setting

### What maps well

| Duflo et al. | This project |
|---|---|
| Industrial plant | Community Water System (CWS) |
| GPCB (regulator) | EPA / state drinking water authority |
| Inspection | Sanitary survey |
| Abatement decision | CWS compliance investment |
| MR/MCL substitution | Strategic MR violations to avoid MCL enforcement |
| Penalty stage (warn→punish→accept chain) | Enforcement chain H3 (violation→enforcement→RTC) |
| Plant dynamic compliance problem | CWS MR-vs-MCL dynamic choice |

### Why the full two-stage model is not feasible

The ARP × sulfur instrument generates exogenous variation in **the regulated entity's
contamination burden** — not in the **regulator's inspection rate**. Identifying the
targeting stage (how the regulator allocates sanitary surveys based on private
information) requires quasi-experimental variation in inspection allocation. That
variation does not exist in this setting.

---

## Comparative Statics: Why Duflo Cannot Provide Them, and How K&S Can

### Why the Duflo penalty-stage adaptation yields no analytical comparative statics

The Duflo penalty stage is a **dynamic discrete choice (DDC) model**. The CWS's
value function is defined implicitly by the Bellman equation:

```
V(s) = max_a { u(s,a) + β · E[V(s')|s,a] }
```

There is no closed-form expression for V(s). Attempting to differentiate with respect
to a parameter ψ gives:

```
∂V/∂ψ = (∂u/∂ψ) + β·(∂E[V']/∂a*)·(∂a*/∂ψ) + β·(∂E[V']/∂ψ)
```

The term ∂a\*/∂ψ depends on the curvature of V, which itself depends on ∂V/∂ψ —
the system is circular. No closed-form resolution is available without parametric
assumptions that would trivialize the model.

**What the Duflo model provides instead:** numerical counterfactuals. Estimate the
model, change a parameter, re-solve computationally, compare equilibria. These are
quantitative policy simulations, not theorems. They tell you *how much* compliance
changes, but cannot generate propositions that can be stated and proved before
estimation.

### Kang & Silveria (2021) as the source of comparative statics

K&S uses the **Mookherjee-Png (1994) static screening model**, which has a
well-defined facility first-order condition:

```
θ · b'(a(θ)) = e'(a(θ))          [K&S eq. 3]
```

where:
- θ = CWS compliance cost type (private information; higher θ = more expensive to
  treat contaminated water to meet MCL standards)
- a ∈ [0, ā] = negligence level (continuous; maps to the choice to suppress
  monitoring rather than report MCL-level contamination)
- b(a) = benefit function of negligence (operation cost savings; b' > 0, b'' ≤ 0)
- e(a) = expected penalty as a function of negligence (e' > 0, e'' > 0 at optimum)

The expected penalty given negligence level a, where violations follow Poisson(a):

```
e(a) = exp(-a) · Σ_k ε(k)/k! · aᵏ          [K&S eq. 1]
```

This single FOC in one unknown, as a function of two parameters, is implicitly
differentiable and yields clean comparative statics.

---

## The Four Comparative Statics Propositions

### Proposition 1 — Type sorting (selection mechanism)

Differentiate the FOC θ·b'(a) = e'(a) with respect to θ:

```
b'(a) + θ·b''(a)·(∂a/∂θ) = e''(a)·(∂a/∂θ)
∂a/∂θ = b'(a) / [e''(a) − θ·b''(a)]
```

Under the SOC (e''(a) − θ·b''(a) > 0) and b'(a) > 0:
**∂a/∂θ > 0** — higher-compliance-cost CWSs choose more negligence in equilibrium.

*Interpretation:* CWSs with more expensive MCL remediation (e.g., those facing
higher baseline contamination from upstream mining) optimally substitute toward MR
violations rather than bearing the MCL compliance cost. The MR-MCL substitution
pattern is a rational equilibrium response to cost heterogeneity, not noise.

*Does not require regulator optimality.* Holds for any enforcement function e(a).

### Proposition 2 — Enforcement deterrence

Suppose enforcement shifts upward: ẽ(a) = e(a) + λ·m(a), where λ is enforcement
intensity. Differentiate the FOC with respect to λ:

```
0 = [e''(a) + λ·m''(a)]·(∂a/∂λ) + m'(a)
∂a/∂λ = −m'(a) / [e''(a) + λ·m''(a)] < 0
```

**∂a/∂λ < 0** — stricter enforcement reduces negligence for every type θ.

*Interpretation:* Steeper penalty schedules (higher probability of formal enforcement
after MR violations, or higher penalty severity) cause CWSs to substitute away from
MR violations toward MCL compliance. The counterfactual of increasing sanitary survey
frequency or MR penalty transitions should produce compliance gains in all CWS types.

*Does not require regulator optimality.* Holds for any parametric shift in e(a).

### Proposition 3 — The mining externality as a type shifter

In this setting, θ is not fixed — it is partly determined by upstream mining
production. Higher mine production increases contamination burden, making MCL
compliance more expensive. Write θ = θ(m) where ∂θ/∂m > 0. By the chain rule:

```
∂a*/∂m = (∂a*/∂θ) · (∂θ/∂m) > 0
```

**More mining → higher effective compliance cost type → higher equilibrium
negligence → more MR violations.**

*Interpretation:* This is the theoretical foundation for the reduced-form 2SLS result.
The ARP shock reduces m for high-sulfur CWSs → reduces θ(m) → shifts a\*(θ) downward
→ fewer violations. The comparative static sign is the same as the 2SLS coefficient
sign, providing theoretical grounding for the empirical finding.

*Does not require regulator optimality.* Is a pure shift in the exogenous state.

### Proposition 4 — Optimal penalty convexity (normative benchmark only)

The regulator's problem (K&S eq. 4) minimizes expected compliance costs + environmental
harms + enforcement costs, choosing ε(k). The solution implies the optimal penalty
schedule is **strictly convex in the number of violations**: ε''(k) > 0. Each
additional violation triggers a larger marginal penalty increment.

*Interpretation:* The optimal schedule front-loads low penalties (to avoid deterring
compliant types from revealing themselves) and escalates steeply for high violation
counts (to deter high-negligence types). If the observed SDWA penalty schedule is
approximately linear or subconvex, it is suboptimal — this is a normative benchmark
for the counterfactual "what would the K&S-optimal enforcement schedule achieve?"

**IMPORTANT:** Proposition 4 requires imposing that the regulator is optimally
designing the penalty schedule (K&S's full mechanism design framework). Because the
empirical model holds the regulatory machine fixed as an exogenous, descriptively-
estimated Markov process, Proposition 4 cannot be presented as a testable prediction
of the estimated model. It is a normative benchmark for counterfactuals only.

---

## Compatibility: K&S Theory with Duflo Estimation

### What carries over from K&S to the dynamic Duflo model

Propositions 1–3 are driven by the **CWS's own optimization** — the FOC θ·b'(a) = e'(a).
This FOC does not depend on the regulator's optimality. In the dynamic Duflo model,
the CWS equates marginal benefit of negligence against the marginal increase in the
continuation value of being caught — the *direction* of all three comparative statics
is preserved:
- Higher θ → more negligence (Proposition 1: preserved, choice ordering by type holds
  in dynamic models)
- Higher enforcement → less negligence (Proposition 2: higher e(a) everywhere reduces
  the value of negligence at every state, shifting optimal policy toward compliance)
- More mining → higher θ(m) → more negligence (Proposition 3: exogenous shift,
  independent of dynamic structure)

### What does not carry over

Proposition 4 (optimal convexity) requires that the regulator solves the mechanism
design problem in K&S eq. 4. The dynamic model holds the regulatory machine
exogenous. Proposition 4 is only usable as a normative counterfactual benchmark.

### The K&S continuous action vs. Duflo discrete action mismatch

K&S has a continuous negligence level a ∈ [0, ā]. The Duflo adaptation uses discrete
actions (comply, MR violation, MCL violation). The FOC does not directly apply, but
the comparative static logic carries over via **revealed preference**: a CWS prefers
MR violation over compliance when θ is high because θ·[b(MCL) - b(MR)] > e(MR) - e(comply).
The ranking of choices by θ is preserved across the static-to-discrete translation.

### Standard practice for this mismatch

This gap between a tractable static theoretical model and a richer dynamic empirical
model is standard in applied micro. Ryan (2012 JPE) derives comparative statics from a
static entry game and estimates a dynamic model. K&S itself is static yet describes
multi-period processes. The framing:

*"We present a static model (K&S / Mookherjee-Png) to derive comparative statics
predictions. The empirical model extends this to a dynamic setting to capture the
multi-period enforcement chain. Propositions 1–3 hold qualitatively in both frameworks;
Proposition 4 serves as a normative benchmark."*

---

## Full Paper Architecture

### Section 1 — Theory (K&S / Mookherjee-Png, static)

**Goal:** Generate Propositions 1–4 with proofs. Provide theoretical grounding for
the empirical sections. Motivate the research question.

**Model elements to include:**
- CWS type θ (private compliance cost; known to CWS, distribution known to regulator)
- Negligence level a (continuous; maps conceptually to MR violation intensity)
- Violations K ~ Poisson(a)
- Expected penalty e(a) = exp(-a) · Σ_k ε(k)/k! · aᵏ
- CWS payoff: -θ[b(ā) - b(a)] - e(a)
- FOC: θ·b'(a(θ)) = e'(a(θ))
- Regulator cost: ∫[h(a(θ)) + ψe(a(θ)) + θ{b(ā) - b(a(θ))}]f(θ)dθ
  where h(·) = perceived harm from violations, ψ = marginal enforcement cost

**Adaptation to SDWA setting:**
- θ = CWS compliance cost type: determined partly by source water quality (sulfur
  contamination from mining), partly by treatment plant capacity, infrastructure age
- a = "monitoring suppression" — the CWS's choice of how aggressively to avoid
  submitting water quality tests (MR violations) vs. bearing MCL remediation cost
- e(a) = expected sanitary survey + enforcement sequence cost, estimated from SDWA data
- b(a) = operating cost savings from not running treatment equipment at full capacity

**Propositions to state and prove:**
- P1: ∂a/∂θ > 0 (type sorting — proof via implicit differentiation of FOC)
- P2: ∂a/∂λ < 0 (enforcement deterrence — proof via shift in e)
- P3: ∂a/∂m > 0 (mining externality — proof via chain rule through θ(m))
- P4: ε''(k) > 0 at optimum (normative benchmark — proof from regulator's problem)

**Implementation notes:**
- This section can be written before any data work; it is purely theoretical
- The discrete-vs-continuous action mismatch should be addressed in a footnote or
  remark: "The empirical model discretizes the action space; Propositions 1–3 hold
  in the discrete analogue via revealed preference arguments"
- The K&S environmental harm function h(a(θ)) maps to public health harms from
  contaminated drinking water — cite epidemiological literature on SDWA violations
  and health outcomes to calibrate the normative significance of h(·)

---

### Section 2 — Reduced Form (2SLS, ARP × sulfur instrument)

**Goal:** Test Proposition 3 empirically. Establish the causal effect of mining on
SDWA violations. Provide the reduced-form evidence that motivates the structural model.

**This section already exists** in the current paper (`didhet.r`, H1 results). The
structural paper reframes the existing 2SLS results as an empirical test of Proposition 3:

> *"Proposition 3 predicts that an exogenous increase in upstream mine production
> increases CWS negligence. We test this using ARP Phase I as an instrument for
> mine production. Consistent with Proposition 3, we find [coefficient sign and
> magnitude] — a [X]% increase in mine production increases the MR violation share
> by [Y] percentage points."*

**Additional reduced-form tests to add for the structural paper:**
- Separate first-stage regressions of MCL violation share and MR violation share on
  the instrument (to confirm the instrument hits the MR-MCL margin, not just total
  violations)
- Test whether the instrument shifts the MR share *more than* the MCL share —
  consistent with Proposition 1 (type-shifting moves CWSs along the MR-MCL cost frontier)
- Heterogeneity by CWS size / source water type: Proposition 1 predicts larger effects
  for CWSs with higher baseline compliance costs (surface water, small systems)

**Instrument validity reminders:**
- First stage: mine production ~ post95 × sulfur_unified (already estimated)
- Exclusion: ARP affects CWS violations only through mine production → water quality
  (no direct effect of coal prices/ARP on CWS regulatory compliance culture)
- Placebo: non-mining-related violations (total coliform, VOC, SOC) should not respond

---

### Section 3 — Structural Estimation (Duflo penalty stage, dynamic)

**Goal:** Recover the structural cost parameters k_MR and k_MCL(s) from CWS
violation choices. Estimate the regulatory machine transition matrix. These
parameters quantify the implicit costs CWSs place on different violation types.

#### Step 1: Estimate the regulatory machine

**What it is:** A Markov transition matrix estimated from SDWA administrative data
describing the regulator's response to CWS violations.

**State space for the regulatory machine:**
- States: {no violation, MR violation, MCL violation, informal notice, formal
  enforcement order, consent order, penalty assessed, RTC}
- Transitions: each pair of consecutive enforcement actions in the SDWA data is
  one observed transition

**Estimation method:** Maximum likelihood on the observed transition sequences.
For each state s, the MLE of the transition probability to state s' is:

```
π̂(s'|s) = (count of s → s' transitions) / (count of observations in state s)
```

Can condition on CWS characteristics X_j to allow the transition matrix to vary
by facility type (e.g., larger CWSs may face faster escalation).

**Output:** A transition matrix π(s'|s, X_j) and the forward-simulated value
function V₀(s, X_j) = expected discounted cost to CWS of entering enforcement
state s. This value function is the key input to Step 2.

**Data needed:** SDWA enforcement chain from ECHO. Need records with:
- PWSID, date, violation type (MR vs MCL), enforcement action type
- Minimum: at least 2 enforcement state transitions per CWS for MLE to work
- Verify density before building: load ECHO data, count complete chains

**R implementation sketch:**
```r
# Load ECHO enforcement data
echo <- arrow::read_parquet("clean_data/cws_data/echo_enforcement.parquet")

# Construct state transitions
chains <- echo |>
  arrange(PWSID, date) |>
  group_by(PWSID) |>
  mutate(state_t = action_type,
         state_t1 = lead(action_type)) |>
  filter(!is.na(state_t1))

# MLE transition matrix (simple version)
trans_matrix <- chains |>
  count(state_t, state_t1) |>
  group_by(state_t) |>
  mutate(pi = n / sum(n))

# Forward-simulate V0(s) using estimated transition matrix
# V0(s) = sum over t of beta^t * E[cost(s_t) | s_0 = s]
# Implement as matrix power series: V0 = (I - beta*Pi)^{-1} * c
# where c is the vector of per-period costs by state
```

#### Step 2: Estimate CWS compliance costs via CCP

**What it is:** The Hotz-Miller (1993) CCP estimator inverts observed violation
choice probabilities to recover structural cost parameters without solving the
full Bellman equation.

**Core identifying equation:**

```
log[ Pr(MR | s) / Pr(comply | s) ] = [ u(s, MR) - u(s, comply) ] / σ_ε
                                    + β · [ E[V'|s,MR] - E[V'|s,comply] ] / σ_ε
```

- Left side: constructed from observed MR violation shares and compliance rates
  in the data, conditional on state s
- Right side, second term: computed from Step 1 regulatory machine (V₀ differences)
- Unknown: u(s, MR) - u(s, comply) = k_comply(s) - k_MR (the per-period cost difference)

**Rearranging to solve for cost difference:**

```
k_comply(s) - k_MR = σ_ε · { log[Pr(MR|s)/Pr(comply|s)]
                              - β·[V₀(s_MR) - V₀(s_comply)] }
```

This gives the implied cost of compliance relative to MR violation for each
contamination state s. The ratio k_MR / k_MCL recovers how much cheaper CWSs
find monitoring suppression relative to MCL remediation.

**Handling contamination state endogeneity (the IV step):**

Observed contamination is endogenous — CWSs in dirtier areas differ on unobservables
that affect compliance. Solution: instrument the contamination state with
Z_t = post95_t × sulfur_unified_h.

Implementation as control function (Blundell-Smith approach):
1. First stage: regress mine production (or predicted contamination) on Z_t and
   controls; save residuals v̂_t
2. Second stage: include v̂_t as a control in the CCP equation; this absorbs the
   endogenous variation in contamination and identifies cost parameters off
   exogenous variation only

**State space discretization for CCP:**
- Discretize contamination exposure into bins (e.g., quartiles of
  `production_short_tons_coal_unified` within mining-exposed sample)
- Each bin defines a state s; Pr(MR|s) is the fraction of CWS-years in that bin
  with a positive MR violation share
- Minimum cell size: need at least ~50 CWS-years per state cell for stable CCP estimates

**Unobserved CWS heterogeneity:**
- If CWSs have unobserved fixed types (well-managed vs. resource-constrained),
  the CCP estimator without heterogeneity conflates type effects with state effects
- Solution: Arcidiacono-Miller (2011) finite mixture CCP — estimate a two-type
  mixture (low-cost vs. high-cost) jointly with the cost parameters
- Implementation: EM algorithm over type probabilities and CCP equations

**R implementation sketch:**
```r
# Step 1: regulatory machine value function (from above)
# V0_diff[s] = V0(s_MR) - V0(s_comply) for each state s

# Construct observed CCPs
ccp <- prod_vio |>
  mutate(s = ntile(production_short_tons_coal_unified, 4)) |>
  group_by(PWSID, s) |>
  summarize(pr_mr = mean(mr_share > 0),
            pr_comply = mean(mr_share == 0 & mcl_share == 0),
            pr_mcl = mean(mcl_share > 0 & mr_share == 0))

# Control function for contamination endogeneity
fs <- feols(production_short_tons_coal_unified ~
              post95:sulfur_unified + num_facilities |
              PWSID + year + state,
            data = prod_vio)
prod_vio$v_hat <- residuals(fs)

# CCP identifying equation (OLS on log odds)
ccp_eq <- feols(log(pr_mr / pr_comply) ~
                  V0_diff + v_hat + num_facilities + POPULATION_SERVED_COUNT |
                  PWSID + year,
                data = ccp)
# Coefficient on V0_diff identifies β/σ_ε
# Intercept + controls identify (k_comply - k_MR)/σ_ε
```

#### What the model recovers

- **k_MR / k_MCL:** The ratio of implicit cost of MR violation to MCL remediation.
  A ratio near zero means the enforcement regime creates almost no deterrence against
  monitoring suppression.
- **k_comply(s) as a function of contamination state:** How much MCL compliance costs
  rise with contamination burden — the structural analogue of the 2SLS coefficient.
- **Regulatory machine transition matrix:** Whether the regulator actually escalates
  after MR violations (do observed transition probabilities justify the CWS's
  strategic substitution choice?).

---

### Section 4 — Counterfactuals (numerical comparative statics from Duflo model)

**Goal:** Quantify Propositions 2 and 4 numerically. Simulate policy counterfactuals.
Answer: "what would compliance look like under an alternative enforcement regime?"

**Counterfactual 1: Increase MR enforcement stringency (test Proposition 2)**

Modify the regulatory machine: increase the transition probability from MR violation
to formal enforcement by X percentage points. Re-solve the CWS's dynamic problem
holding the cost parameters fixed. Compute:
- Change in MR violation share
- Change in MCL compliance rate
- Change in aggregate public health burden (requires mapping violations to health
  outcomes from epidemiological literature)

This directly quantifies ∂a/∂λ from Proposition 2 in the data — the theoretical
sign is known (negative), the structural model provides the magnitude.

**Counterfactual 2: Increase sanitary survey frequency for high-contamination CWSs**

Modify the targeting rule: increase the inspection rate for CWSs in the top
contamination quartile (highest `production_short_tons_coal_unified`). This is
the partial analogue of the Duflo targeting stage — it shifts the probability of
detection for high-θ CWSs. Compute:
- Change in MR violation share by contamination quartile
- Value of targeting (high-contamination) vs. random assignment of extra surveys

**Counterfactual 3: K&S-optimal penalty schedule (test Proposition 4 normatively)**

Replace the observed ε(k) schedule (from the regulatory machine) with the K&S-optimal
convex schedule derived from the estimated parameters. Compute:
- Change in compliance across CWS types
- Change in total enforcement cost (ψ·e(a) term)
- Fraction of the compliance gap attributable to suboptimal penalty schedule shape
  vs. insufficient enforcement intensity

This answers: "If the regulator used the Mookherjee-Png optimal convex schedule
rather than the observed schedule, how much more compliance would result?"

**R implementation sketch:**
```r
# Counterfactual 1: increase MR enforcement transition probability
pi_cf <- trans_matrix
pi_cf["MR_violation", "formal_enforcement"] <-
  pi_cf["MR_violation", "formal_enforcement"] * 1.5  # 50% increase

# Recompute V0 under counterfactual machine
V0_cf <- solve(diag(nrow(pi_cf)) - beta * pi_cf) %*% cost_vector

# Recompute CWS optimal actions under new V0
# Compare counterfactual choice probabilities to baseline
cf_choices <- compute_ccp(V0_cf, cost_params)
delta_compliance <- cf_choices$pr_comply - baseline_choices$pr_comply
```

---

## The Combined Paper Architecture (Summary)

| Section | Framework | Provides | Key output |
|---------|-----------|----------|------------|
| Theory | K&S / Mookherjee-Png (static) | Propositions 1–4 with proofs | Testable predictions, normative benchmark |
| Reduced form | 2SLS (ARP × sulfur) | Tests Proposition 3 | β̂ = causal effect of mining on MR violations |
| Structural estimation | Duflo penalty stage (dynamic) | Recovers k_MR / k_MCL; estimates π(s'|s) | Primitive cost parameters |
| Counterfactuals | Re-solve Duflo model | Quantifies Propositions 2 and 4 | Policy-relevant magnitudes |

---

## Publication Venues

### Core research question

*"What are the costs CWSs implicitly place on different violation types, and what
does this reveal about the effectiveness of the SDWA enforcement regime?"*

### Venue assessment

| Venue | Fit | Rationale |
|-------|-----|-----------|
| **AEJ: Applied Economics** | Very strong | Applied structural + quasi-experimental identification; exact archetype |
| **Journal of Public Economics** | Strong | Public regulation + environmental enforcement + SDWA understudied |
| **AER** | Possible | If counterfactual results are striking (current regime recovers X% of potential gains) |
| **JPE** | Stretch | Full two-stage model needed for JPE bar |
| **JEEM** | Strong fallback | Natural home for environmental enforcement structural models |
| **AEJ: Policy** | Strong fallback | Policy-relevant enforcement question; clean instrument |

### Methodological framing

The ARP × sulfur instrument is an advantage over Duflo et al.: clean identification
of compliance costs without a randomized experiment. Framing:
*"Quasi-experimental variation in the regulated entity's pollution burden — rather
than randomized inspections — is sufficient to identify structural compliance costs."*

Ceiling: **AEJ: Applied** or **JPublicEcon** for penalty-stage-only.
Genuine shot at **AER** if counterfactual policy results are striking.

---

## To-Do List: Next Steps

### Priority 0: Feasibility checks (do before any model-building)

- [ ] **Audit enforcement chain data density.** Load SDWA enforcement data from ECHO
      and count sequences of: violation → informal notice → formal action → consent
      order → penalty → RTC. Report: how many complete chains exist? How many CWSs
      have at least 2 enforcement state transitions? This determines whether Step 1
      (regulatory machine MLE) is estimable. If fewer than ~500 chains, Markov MLE
      will be unstable — consider pooling states or using a simpler 3-state machine.

- [ ] **Check sanitary survey frequency data availability.** Confirm whether the SDWA
      data includes sanitary survey dates at the CWS level. Needed as a state variable
      in the regulatory machine. If missing, the inspection rate must be imputed from
      other sources or dropped from the state space.

- [ ] **Map violation type granularity.** Confirm that `prod_vio_sulfur.parquet` allows
      clean separation of MCL vs. MR violations at the annual level. Check: are there
      enough CWSs with both MCL and MR violation observations (not all MCL or all MR)
      to identify the choice probabilities? The CCP estimator needs within-CWS variation
      across violation types over time.

- [ ] **Verify first-stage strength by violation type.** Run first-stage regressions
      of MCL violation share and MR violation share separately on `post95 × sulfur_unified`.
      If the instrument is strong for total violations but not for the MCL/MR split,
      the structural identification is weakened and the reduced-form section needs
      revision before proceeding.

### Priority 1: Theory section (can be written now, no data needed)

- [ ] **Write the theory section.** Adapt K&S / Mookherjee-Png to the SDWA setting.
      Derive Propositions 1–4 formally. The theory section needs:
      - Definition of the SDWA-adapted type space (θ as MCL compliance cost,
        determined partly by mining contamination burden)
      - The negligence-to-MR-violation mapping (a → monitoring suppression decision)
      - Proofs of P1–P3 via implicit differentiation
      - The regulator's problem and P4 derivation from K&S's mechanism design result
      - A remark on the static-to-dynamic translation (P1–P3 hold in discrete dynamic
        model via revealed preference)

- [ ] **Read Mookherjee and Png (1994)** — the original paper underlying K&S. Needed
      to write the theory section correctly and cite the right source for each result.
      K&S's paper is in `Z:\ek559\mining_wq\.claude\skills\Mookherjee and Png 1994.pdf`.

### Priority 2: Reduced form additions (builds on existing H2/H3 work)

- [ ] **Add MCL-vs-MR first-stage split to reduced form tables.** New regressions:
      instrument on MCL violation share separately from MR violation share. This tests
      the structural claim that the instrument shifts CWSs along the MR-MCL frontier.

- [ ] **Add heterogeneity by source water type.** Proposition 1 predicts larger effects
      for surface-water CWSs (more vulnerable to mining runoff). Interact the main
      2SLS specification with `PRIMARY_SOURCE_CODE == "SW"`.

- [ ] **Add heterogeneity by CWS size.** Small systems (< 500 population served) are
      likely higher-θ types (less treatment capacity). Test whether the reduced-form
      effect is larger for small CWSs.

### Priority 3: Literature

- [ ] **Read Ryan (2012) JPE** — "The Costs of Environmental Regulation in a
      Concentrated Industry." Static theory + dynamic estimation archetype. The Clean
      Air Act attainment-status instrument plays the role that ARP × sulfur plays here.

- [ ] **Read Hotz and Miller (1993) RES** — "Conditional Choice Probabilities and the
      Estimation of Dynamic Models." The CCP estimator used in Step 2. Core reference
      for the estimation approach.

- [ ] **Read Arcidiacono and Miller (2011) Econometrica** — extends Hotz-Miller to
      unobserved heterogeneity via EM algorithm. Needed if CWS unobserved type
      heterogeneity is quantitatively important (likely, given variation in management
      quality and infrastructure age across CWSs).

- [ ] **Read Rust (1987) Econometrica** — "Optimal Replacement of GMC Bus Engines."
      The original DDC paper. Conceptual foundation for the Bellman approach before
      using the Hotz-Miller shortcut.

### Priority 4: Model specification decisions (require user input before coding)

- [ ] **Decide on the state space.** What is the CWS's contamination state s_t?
      Options: (a) continuous — predicted contamination from first stage; (b) discrete
      bins — quartiles of `production_short_tons_coal_unified`; (c) indicator for
      being in active enforcement. Discrete bins are computationally simpler and
      more compatible with CCP methods. Recommended: 4 bins (quartiles) × 3 enforcement
      status levels = 12 states total.

- [ ] **Decide on discount factor β.** Calibrate at 0.95 (standard annual) or estimate
      jointly. Joint estimation requires additional exclusion restrictions; calibration
      is simpler and standard in the DDC literature.

- [ ] **Decide whether to model CWS unobserved heterogeneity.** Two-type finite
      mixture (low-cost vs. high-cost) is the simplest extension. If CWS fixed effects
      in the violation data are large, unobserved heterogeneity matters and Arcidiacono-
      Miller is needed. Check: regress violation share on PWSID fixed effects — R² from
      fixed effects alone tells you how much unobserved heterogeneity matters.

- [ ] **Decide on counterfactual policy exercises.** Recommended set:
      (1) 50% increase in MR enforcement transition probability (tests P2);
      (2) targeted sanitary surveys for top-quartile contamination CWSs;
      (3) K&S-optimal convex penalty schedule (tests P4 normatively).

### Priority 5: Implementation (after feasibility checks pass and spec decided)

- [ ] **Write regulatory machine estimation script** (`structural_penalty_machine.r`):
      load SDWA enforcement chains, construct state transition pairs, estimate
      transition matrix by MLE, forward-simulate to compute V₀(s) for each state.

- [ ] **Write CCP estimation script** (`structural_ccp.r`): construct observed choice
      probabilities from violation data by state bin, implement control function IV
      for contamination endogeneity (first stage: production on instrument), run CCP
      identifying equations (log-odds regression), recover k_MR / k_MCL cost ratio.

- [ ] **Write counterfactual simulation script** (`structural_counterfactuals.r`):
      modify transition matrix or penalty schedule, recompute V₀(s), recompute
      optimal CWS actions via CCP equations, compute counterfactual violation shares
      and compliance gains relative to baseline.
