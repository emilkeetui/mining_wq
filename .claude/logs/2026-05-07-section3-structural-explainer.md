# Section 3 Structural Estimation — Pedagogical Explainer

**Audience:** PhD economist who has not forward-simulated a transition matrix, run
a binary-logit CCP, or used Arcidiacono–Miller. Written 2026-05-07 to accompany
`2026-05-06-structural-model-analysis.md`.

---

## What the section is doing, in one paragraph

Each year a CWS picks **comply** or **MR violate**. That choice has an immediate
cost (compliance effort vs. risk of getting caught) AND changes the probability
the CWS faces an enforcement action next year. To recover *k_MR* — the
implicit cost the CWS attaches to an MR violation — we need to disentangle
"what they pay today" from "what they expect to pay tomorrow." That's why this
is dynamic and not just a logit on cross-sectional violation rates.

---

## Step 1 — The 2-state regulatory response function

### The state space

Each CWS-year is in one of two enforcement states:
- `no_enf`: no active enforcement action
- `enf`: currently under enforcement

### The action-conditional transition matrices

In SDWA, enforcement is triggered by violations, so transitions are *not*
exogenous. We estimate two 2×2 matrices, one for each action a ∈ {comply, MR}:

```
                      next year
                  no_enf      enf
P(·|·, comply):
   no_enf       [ p_00^c    p_01^c ]
      enf       [ p_10^c    p_11^c ]

P(·|·, MR):
   no_enf       [ p_00^m    p_01^m ]
      enf       [ p_10^m    p_11^m ]
```

Each row sums to 1. Estimate by counting: of all PWSID-years where the state
was `no_enf` AND the CWS complied, what fraction transitioned to `enf` the
next year? That's p_01^c. Pure tabulation — no fancy MLE.

The dynamic deterrence channel is the gap

```
Δπ(s) ≡ Pr(enf' | s, MR) − Pr(enf' | s, comply)
```

which is positive: violating raises tomorrow's enforcement probability. Without
action-conditional transitions, Δπ(s) = 0 and the model collapses to static logit.

### Forward simulating V₀(s)

V₀(s) is the **expected present-discounted future cost** of being in state s
today, assuming the CWS plays its optimal policy forever. Discount factor β=0.95.

If c(s) is the per-period enforcement cost — set c(no_enf)=0, c(enf)=1 as a
**normalization** — and P is the optimal-policy-implied transition matrix, then
V₀ solves the Bellman equation:

```
V₀(s) = c(s) + β · Σ_{s'} P(s' | s) · V₀(s')
```

For 2 states this is two linear equations:

```
V₀(no_enf) = 0 + β·[ p_00·V₀(no_enf) + p_01·V₀(enf) ]
V₀(enf)    = 1 + β·[ p_10·V₀(no_enf) + p_11·V₀(enf) ]
```

Solve the linear system. In matrix form: **V₀ = (I − βP)⁻¹ · c**. That's the
"forward simulation" — for a 2-state model it's a closed-form matrix inverse.
Larger models use Monte Carlo trajectories; you don't need to.

### Do you need explicit dollar costs of c(s)?

**No.** c(s) is a normalization. With c(no_enf)=0 and c(enf)=1, the recovered
k_MR is in units of "one period of being under enforcement." That is the
natural and defensible unit: k_MR = 0.4 means a CWS treats an MR violation as
costing 40% as much as one period of active enforcement.

If you wanted dollar-denominated k_MR you would need an external calibration
(administrative records on legal/operational cost of being under enforcement,
or compliance-cost estimates from EPA technical reports). That is a separate
exercise — not required for the headline counterfactual. The within-model
**ratio** k_MR / c(enf) is identified and is what counterfactuals operate on,
which is why c(enf) = 1 is a valid normalization choice.

### Why V₀ matters

What enters the CWS's decision is the *option value* of being in `no_enf`
rather than `enf`: the difference V₀(no_enf) − V₀(enf), which equals
the discounted stream of future costs the CWS escapes by avoiding enforcement.
That is the dynamic incentive holding it back from violating today.

---

## Step 2 — Binary logit CCP

### The big idea (Hotz–Miller 1993)

To estimate a dynamic discrete choice model the brute-force way, you would
write the full Bellman, solve for value functions everywhere, plug into a
likelihood. Hotz and Miller noticed that under T1EV (logit) errors, **choice
probabilities and value functions are linked by a closed-form invertible
mapping**. So instead of solving the model, you can **read the value functions
off the observed choice probabilities**. "CCP" = Conditional Choice Probability.

Concretely, under T1EV errors, in any state s:

```
Pr(MR | s) / Pr(comply | s) = exp( ΔU(s) )
```

where ΔU(s) is the difference in (flow utility + discounted continuation value)
between MR and comply. Take logs:

```
log[ Pr(MR | s) / Pr(comply | s) ] = ΔU(s)
```

The left side you **observe** — empirical log-odds of MR within state s. The
right side is structural. Decompose ΔU(s), then run a regression.

### Decomposing ΔU(s)

Action a=1 means MR violate, a=0 means comply. Flow utility difference is
(k_comply − k_MR), normalized by the logit scale σ_ε. Continuation value
difference is β times the V₀ gap weighted by how the action shifts transitions:

```
ΔU(s) = (k_comply − k_MR) / σ_ε                              ← flow utility
        + (β / σ_ε) · [V₀(enf) − V₀(no_enf)] · Δπ(s)         ← dynamic incentive
        + γ · v̂_t                                            ← control function
```

- V₀(enf) − V₀(no_enf) < 0 (enforcement is costly).
- Δπ(s) > 0 (MR raises future enforcement probability).
- Their product enters with a negative sign in ΔU(s) — the deterrence channel.
- v̂_t is the residual from the first-stage regression of contamination on
  the ARP × sulfur instrument, included via the control-function approach
  (Petrin–Train 2010, Wooldridge 2015) to handle nonlinear IV.

### What is the "contamination state"?

The plan operationalizes the contamination state as **quartiles of
`production_short_tons_coal_upstream`** — upstream coal production tonnage
facing the CWS. Combined with the 2 enforcement states this gives the 8 state
cells (~780 obs each).

**Terminology fix:** call it the **mining-exposure state**, not the
contamination state. Actual raw-water concentrations of nitrates, arsenic, etc.
are not observed — they are only revealed *when a violation occurs*, which is
endogenous to the CWS's choice. What you observe is mining exposure, which in
the K&S mapping is m, feeding into θ(m), the effective compliance cost. The
mechanism is mining → contamination burden → higher cost of meeting MR
requirements; the structural state is the upstream tonnage, not the
(unobserved) downstream concentration. Refer to the object as "mining-exposure
state" in the paper to avoid a referee snagging on the imprecision.

### Estimation

After Step 1 produces V₀ and Δπ(s) is computed from the data, the right side
is linear in the structural parameters. Within each state cell s (4
mining-exposure quartiles × 2 enforcement states = 8 cells, ≈780 obs each),
compute observed log-odds. Regress these on:
- a constant (identifies (k_comply − k_MR)/σ_ε)
- the constructed regressor [V₀(enf) − V₀(no_enf)] · Δπ(s) (coefficient pins β/σ_ε; with β fixed at 0.95, identifies σ_ε)
- v̂_t (control function residual)

Normalize σ_ε = 1 (or equivalently fix the scale by setting c(enf) = 1) and
read off k_MR from the intercept.

### Is ARP × sulfur a valid instrument for the control function v̂_t?

Conceptually yes — the same instrument that powers the 2SLS reduced form
identifies the structural model. Post-1995 ARP Phase I differentially shocked
high-sulfur upstream mine production, generating CWS-level variation in mining
exposure that is plausibly exogenous to the CWS's compliance decision.
Relevance is satisfied (F = 13.6). The Petrin–Train (2010) / Wooldridge (2015)
result is that in a binary-logit choice equation with a continuous endogenous
regressor, including v̂_t (the first-stage residual) in the choice equation
absorbs the component of the structural error correlated with that regressor,
restoring consistency.

Three caveats you must address explicitly in the paper:

**Caveat 1 — Discretization mismatch.** The first stage is on *continuous*
upstream coal production, but the CCP regression uses *quartile* state
assignments. v̂_t is a residual from a continuous-on-continuous regression; it
controls for endogeneity in the *level* of mining exposure, not in the *bin
assignment*. Two clean fixes: (a) use continuous mining exposure as the
structural state and let θ(m) enter the CCP as a smooth function, or
(b) defend the discretization as a coarsening that doesn't change the CF logic
(cite Wooldridge on coarsened endogenous regressors). Option (a) is cleaner;
(b) is fine if you argue the cell-level CF residuals are a sufficient summary.
**Practical recommendation:** add a robustness column that uses the continuous
mining-exposure variable instead of quartile bins. If k_MR is stable across
the two specifications, the discretization isn't doing harm.

**Caveat 2 — Exclusion restriction is shared with the reduced form.**
post95 × sulfur identifies off a time-varying interaction. The SDWA 1996
Amendments hit roughly the same window (Check 2 noted sanitary survey
coverage collapsed 1992–1998). If the 1996 Amendments differentially affected
high-sulfur regions for reasons unrelated to coal production — e.g. coalfield
states had weaker pre-existing primacy enforcement that the Amendments
tightened — the exclusion fails. This is the same concern as in the
reduced-form chapter; carry the same defense forward (state × year FE,
placebo on non-mining contaminants, etc.). The CF inherits the validity of
the underlying IV.

**Caveat 3 — CF in dynamic discrete choice is not as clean as in static models.**
Petrin–Train was derived for static logit. In a dynamic model, the endogenous
regressor evolves over time, and an unobservable correlated with mining
exposure at t may also be correlated with future state transitions. The
standard approach assumes the unobservable enters flow utility additively and
is captured period-by-period by v̂_t — reasonable but worth flagging. Cleaner
literature references for IV in DDC are Blundell–Powell (2003, 2004) for the
CF logic and Berry–Haile (2014) or Bajari–Chernozhukov–Hong–Nekipelov (2009)
for IV in dynamic discrete choice. **Defensible position in the paper:**
invoke the additive-separability assumption explicitly, cite Blundell–Powell,
and treat dynamic-CF biases as a robustness concern rather than a primary
identification claim.

**Diagnostics to report.** (i) First stage from the structural sample (may
differ slightly from the 2SLS first stage if the structural sample differs in
selection); (ii) robustness column with continuous mining exposure;
(iii) k_MR with and without v̂_t included, to show how much endogeneity
correction matters quantitatively.

---

## Arcidiacono–Miller — only if needed

Hotz–Miller assumes all relevant state variables are observed, so empirical
choice frequencies are unbiased estimates of true CCPs. **Arcidiacono–Miller
(2011)** extends CCP to *unobserved permanent types* — e.g. "compliant-by-
culture" vs "non-compliant-by-culture" CWSs. They use an EM algorithm: alternate
between (i) assigning each CWS a posterior probability of being each type given
current parameters, (ii) re-estimating type-specific CCPs and structural
parameters weighted by those posteriors. Iterate to convergence.

Invoke this only if PWSID fixed effects in a simple OLS of MR-share explain a
lot of variance (R² ≥ 0.3 in the plan). High R² implies the 8-cell state
representation is missing a permanent unobserved component. If R² is modest,
the simpler Hotz–Miller estimator suffices.

---

## Putting it together — the full algorithm

1. Estimate P(s'|s, comply) and P(s'|s, MR) by counting transitions.
2. Solve V₀ = (I − βP)⁻¹ · c using the optimal-policy P. (Iterate Steps 1–2 if needed: optimal P depends on choices, choices depend on V₀.)
3. First-stage regression of contamination on ARP × sulfur; save residuals v̂_t.
4. Compute observed log-odds log[Pr(MR|s, z) / Pr(comply|s, z)] within each (state, z) cell.
5. Regress log-odds on the constructed continuation-value regressor and v̂_t. Intercept gives k_comply − k_MR.
6. (CF1) Plug k_MR into the Bellman with counterfactual P (e.g. doubled p_01)
   and re-solve for new optimal choice probabilities. Aggregate change in
   MR violation share is the headline number.

Practical scope: a 2×2 matrix solve, an OLS, and a forward-simulation routine.
The conceptual lifting is in Hotz–Miller's representation theorem — read
section 3.1 of Arcidiacono–Miller (2011) once before coding.

---

## Citations

### Required

- **Hotz and Miller (1993)** *Review of Economic Studies* — the CCP
  representation theorem. This is the methodological foundation; cite directly
  when introducing the inversion mapping log[Pr(MR)/Pr(comply)] = ΔU.
- **Kang and Silveria (2021)** — the structural model is *adapted* from theirs;
  the dynamic enforcement / firm-cost-recovery framework is theirs. Cite when
  describing the model's primitives, P1–P4, and the second-best penalty
  benchmark.
- **Mookherjee and Png (1994)** — marginal deterrence framework underlying
  K&S; cite for theoretical lineage of P1–P3.
- **Rust (1987)** *Econometrica* — conceptual foundation for dynamic discrete
  choice and the Bellman setup. Standard citation when introducing the dynamic
  programming structure even when not solving the full nested fixed point.

### Conditional

- **Arcidiacono and Miller (2011)** *Econometrica* — cite **only if** unobserved
  heterogeneity is invoked (R² ≥ 0.3 from PWSID FE). If you stick with
  Hotz–Miller, citing AM is optional but useful as a "we considered this and
  ruled it out based on diagnostic X" footnote.
- **Petrin and Train (2010)** *J Marketing Research* or **Wooldridge (2015)**
  *J Human Resources* — cite for the control function approach to nonlinear IV
  when introducing v̂_t.
- **Bajari, Benkard, and Levin (2007)** *Econometrica* — optional, sometimes
  cited as the canonical reference for two-step structural estimation in
  discrete games. Probably overkill for a single-agent binary choice; skip
  unless a referee asks.

### On Duflo, Greenstone, Pande, Ryan (2018) — *The Value of Regulatory Discretion*

**Cite as motivation and related literature, NOT as the structural template.**
The Duflo et al. setup differs in important ways:

| Dimension | Duflo et al. (2018) | This paper |
|---|---|---|
| Identification source | Randomized inspection assignment | ARP × sulfur instrument |
| Object of interest | Regulator's preferences over inspection allocation and reporting (the regulator is the strategic actor with hidden discretion) | Firm's (CWS's) implicit cost k_MR |
| Model class | Two-sided model with regulator-as-agent | Single-agent dynamic discrete choice (CWS) with exogenously evolving enforcement response function |
| Inspection process | Random / experimentally manipulated → genuinely exogenous | Endogenous to firm violations → action-conditional P(s'|s,a) |

What you cite Duflo et al. for:
- Establishing structural estimation of regulator–firm interactions as a
  productive research agenda
- Motivating the value of recovering primitives (preferences, costs) from
  enforcement data, beyond reduced-form effects
- A reference point for "structural model with environmental enforcement
  data" in the JPubEcon/AEJ:Applied audience

What you do **not** cite Duflo et al. for:
- The CCP estimator (that is Hotz–Miller / Arcidiacono–Miller)
- The model setup itself (that is K&S / Mookherjee–Png)
- "Regulatory machine" framing — their inspection process is randomized; ours is endogenous, so the machine metaphor is inappropriate. Refer to your object as a "regulatory response function."

A defensible Section 3 citation cluster looks like:

> "We estimate a single-agent dynamic discrete choice model in the spirit of
> Rust (1987), using the conditional choice probability representation of
> Hotz and Miller (1993). The model adapts the static enforcement framework of
> Kang and Silveria (2021) and Mookherjee and Png (1994) to a dynamic setting.
> The control function adjustment for endogenous contamination follows
> Petrin and Train (2010). [If AM invoked: We allow for unobserved permanent
> heterogeneity across CWSs following Arcidiacono and Miller (2011).] Our
> approach is complementary to Duflo et al. (2018), who recover regulator
> preferences from a randomized inspection experiment in Indian environmental
> enforcement; we instead recover firm-side compliance costs from a
> quasi-experimental shock to firm-level pollution burden."
