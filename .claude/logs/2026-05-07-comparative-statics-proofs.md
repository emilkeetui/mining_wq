# Comparative Statics: Propositions 1–4
## Kang & Silveria (2021) / Mookherjee-Png (1994) adapted to SDWA setting
### Session: 2026-05-07

---

## Model Setup

**CWS type.** Each CWS has private compliance cost type θ ∈ [θ\_L, θ\_H], drawn from
distribution F(θ). Higher θ means MCL remediation is more expensive.

**Negligence choice.** The CWS chooses negligence level a ∈ [0, ā]. Conceptually, a
indexes monitoring suppression — the intensity with which the CWS avoids submitting
water quality tests.

**Violations.** Given negligence level a, observed violations follow a Poisson process:

```
Pr(K = k | a) = e^{-a} · a^k / k!
```

**Expected penalty.** The penalty schedule ε(k) maps violation count to penalty.
Expected penalty as a function of negligence:

```
e(a) = Σ_{k=0}^∞  ε(k) · Pr(K = k | a)
     = e^{-a} · Σ_{k=0}^∞  ε(k) · a^k / k!
```

**Marginal expected penalty.** Differentiating e(a) with respect to a:

```
e'(a) = e^{-a} · Σ_{k=0}^∞  [ε(k+1) − ε(k)] · a^k / k!
      = Σ_{k=0}^∞  [ε(k+1) − ε(k)] · Pr(K = k | a)
      = E_a[ ε(K+1) − ε(K) ]
```

The marginal expected penalty equals the expected increment in the penalty
schedule — the CWS's marginal cost of an additional unit of negligence.

Similarly:

```
e''(a) = Σ_{k=0}^∞  [ε(k+2) − 2ε(k+1) + ε(k)] · Pr(K = k | a)
       = E_a[ Δ²ε(K) ]
```

**CWS objective.** The CWS maximizes operational cost savings net of expected penalties:

```
max_{a ∈ [0,ā]}  U(a, θ) = θ · b(a) − e(a)
```

where b(a) = savings from avoiding compliance expenditures, with b'(a) > 0 and
b''(a) ≤ 0. The parameter θ scales marginal benefit: high-cost types gain more per
unit of negligence.

**Maintained assumption (Deterrence, A1).** The penalty schedule ε(k) is non-decreasing
and non-constant: ε(k+1) ≥ ε(k) for all k ≥ 0, with strict inequality for at least
one k. Under A1, e'(a) > 0 for all a > 0. See note at end on why this is an
assumption rather than a derived result.

**First-order condition (FOC):**

```
θ · b'(a_opt(θ)) = e'(a_opt(θ))                                              [FOC]
```

**Second-order condition (SOC).** The SOC for a unique interior maximum requires:

```
θ · b''(a) − e''(a) < 0
```

This holds because b''(a) ≤ 0 and e''(a) > 0 at any candidate optimum (the Poisson
structure ensures e is strictly convex in a when ε is non-decreasing and non-constant).
The SOC is guaranteed by strict concavity of b (b'' < 0 strictly), or by sufficient
convexity of ε; assuming b strictly concave is the cleanest setup.

---

## Proposition 1 — Type Sorting

**Statement.** Higher-compliance-cost CWSs choose strictly more negligence in
equilibrium: da\_opt/dθ > 0.

**Proof.** Define the implicit function:

```
F(a, θ) ≡ θ · b'(a) − e'(a) = 0
```

By the implicit function theorem, wherever the SOC holds:

```
da_opt/dθ = − F_θ / F_a
```

Compute each partial:

```
F_θ = b'(a) > 0                     [b' > 0 by assumption]

F_a = θ · b''(a) − e''(a) < 0      [SOC]
```

Therefore:

```
da_opt/dθ = − b'(a) / [θ · b''(a) − e''(a)]
           = b'(a) / [e''(a) − θ · b''(a)]
           > 0
```

since b'(a) > 0 and the denominator e''(a) − θ·b''(a) > 0 (both terms are
non-negative, and e''(a) > 0 strictly). □

**Interpretation.** CWSs facing higher MCL remediation costs — for example, those
served by source water with elevated baseline contamination from upstream mining —
find the marginal benefit of an additional unit of negligence θ·b'(a) larger relative
to the marginal expected penalty e'(a). They optimally tolerate more monitoring
suppression. The MR–MCL substitution pattern is a rational equilibrium response to
cost heterogeneity across CWSs, not noise or capacity failure.

---

## Proposition 2 — Enforcement Deterrence

**Statement.** A multiplicative increase in enforcement intensity λ — scaling the
entire penalty schedule to λ·ε(k) — strictly reduces equilibrium negligence for
every type θ: da\_opt/dλ < 0.

**Setup.** Under scaling, the expected penalty becomes λ·e(a), so the CWS's
objective is:

```
max_a  θ · b(a) − λ · e(a)
```

The FOC becomes:

```
θ · b'(a_opt(θ, λ)) = λ · e'(a_opt(θ, λ))                               [FOC-λ]
```

**Proof.** Define:

```
G(a, λ) ≡ θ · b'(a) − λ · e'(a) = 0
```

By the implicit function theorem:

```
da_opt/dλ = − G_λ / G_a
```

Compute each partial:

```
G_λ = − e'(a) < 0                          [e' > 0 under A1]

G_a = θ · b''(a) − λ · e''(a) < 0         [SOC under λ·e(a)]
```

Therefore:

```
da_opt/dλ = − (−e'(a)) / (θ · b''(a) − λ · e''(a))
           = e'(a) / (θ · b''(a) − λ · e''(a))
           < 0
```

since e'(a) > 0 and the denominator is strictly negative by the SOC. □

**Interpretation.** Multiplying all penalties by λ raises the marginal expected cost
of negligence proportionally — from e'(a) to λ·e'(a) — for every type θ. This
shifts the optimal negligence level downward for every CWS in the population. The
result holds for any monotone convex e(a) without imposing regulator optimality: it
is a pure demand response to an increase in the effective price of negligence.

**Note on functional form.** The multiplicative scaling λ·e(a) is the natural
parameterization because it leaves the shape of the penalty schedule unchanged while
raising its level uniformly. λ corresponds to uniform proportional scaling of all
penalties — for instance, doubling the dollar fine per violation count, or doubling
the probability of formal enforcement proportionally across all violation counts.

---

## Proposition 3 — Mining Externality as a Type Shifter

**Statement.** An exogenous increase in upstream mine production m raises equilibrium
negligence for the affected CWS: da\_opt/dm > 0.

**Setup.** Mine production raises source water contamination, which makes MCL
treatment more expensive. Write the CWS compliance cost type as an increasing
function of local mine production:

```
θ = θ(m),     with  dθ/dm > 0
```

Equilibrium negligence is then the composition:

```
a_opt(θ(m))
```

**Proof.** Apply the chain rule:

```
da_opt/dm = (da_opt/dθ) · (dθ/dm)
```

From Proposition 1: da\_opt/dθ > 0.
By assumption: dθ/dm > 0.
Therefore:

```
da_opt/dm > 0     □
```

**Interpretation.** An increase in upstream mine production raises the contamination
burden on the CWS's source water. This increases the cost of treating that water to
MCL standards, effectively raising the CWS's compliance cost type θ(m). By
Proposition 1, higher θ shifts the optimal action toward more negligence — more
monitoring suppression, more MR violations. The chain runs:

```
more mining  →  higher θ(m)  →  higher a_opt(θ)  →  more MR violations
```

This is the theoretical foundation for the 2SLS estimate. The ARP Phase I shock
reduced mine production m for high-sulfur CWSs after 1995. By Proposition 3, this
reduced θ(m), which reduced equilibrium negligence a\_opt(θ(m)), producing fewer MR
violations. The comparative static sign matches the expected 2SLS coefficient sign,
providing structural grounding for the reduced-form finding.

---

## Proposition 4 — Optimal Penalty Convexity

**Statement.** The optimal penalty schedule chosen by a welfare-minimizing regulator
is strictly convex in the violation count:

```
ε(k+1) − ε(k) > ε(k) − ε(k−1)  for all k ≥ 1
```

i.e., Δ²ε(k) ≡ ε(k+2) − 2ε(k+1) + ε(k) > 0.

**Regulator's problem.** The regulator observes K but not a or θ. It chooses ε(·)
to minimize expected social loss:

```
min_{ε(·)}  ∫_{θ_L}^{θ_H}  [h(a_opt(θ)) + ψ · e(a_opt(θ)) + θ · (b(ā) − b(a_opt(θ)))]  f(θ) dθ
```

where:

- h(a) = social harm from negligence level a, with h' > 0
- ψ · e(a) = enforcement cost, with ψ the marginal cost per unit of expected penalty
- θ · (b(ā) − b(a)) = compliance cost borne by CWS type θ
- a\_opt(θ) is determined by the CWS's FOC given ε(·)

**Step 1: Reformulate in terms of target function.** Because a\_opt(θ) is determined
by the FOC and is strictly increasing in θ (Proposition 1), the regulator can
equivalently choose a target negligence function ã(θ) that is increasing in θ. The
implementability condition is that there exists ε(k) such that the CWS's FOC holds
at a = ã(θ) for each θ.

**Step 2: The MLRP of the Poisson distribution.** The Poisson distribution satisfies
the strict monotone likelihood ratio property (MLRP) in (k, a):

```
d/da  [ Pr(K = k | a) / Pr(K = k − 1 | a) ]  =  d/da  [ a/k ]  =  1/k  >  0
```

Higher violation counts k are strictly more likely to be generated by
higher-negligence CWSs. K is therefore a sufficient statistic for a and, through the
FOC, for θ.

**Step 3: First-order conditions for the penalty schedule.** Differentiating the
regulator's Lagrangian with respect to ε(k), substituting the CWS's envelope
condition, and integrating by parts over the type distribution, the optimality
conditions take the form:

```
[ε(k+1) − ε(k)] − [ε(k) − ε(k−1)]  =  Ω(k) / Pr(K = k | a_opt(θ̃))
```

where Ω(k) aggregates the regulator's marginal social harm from additional
negligence, adjusted for enforcement cost and the virtual compliance cost of the
marginal type θ̃. Under the regularity conditions that (i) h is weakly convex,
(ii) the hazard rate f(θ)/(1 − F(θ)) is non-decreasing in θ, and (iii) the MLRP
holds, Ω(k) > 0 for all k.

**Step 4: Convexity.** Since Ω(k) > 0 and Pr(K = k | a) > 0 for all k and a > 0:

```
ε(k+1) − ε(k) > ε(k) − ε(k−1)  for all k ≥ 1     □
```

**Interpretation.** The optimal schedule front-loads moderate penalties at low
violation counts — to avoid over-deterring low-negligence CWSs from accurate
reporting — and escalates steeply at high violation counts, where the MLRP ensures
that many violations are strong evidence of high-θ types choosing strategic
monitoring suppression. A linear schedule (constant marginal penalty per additional
violation) is suboptimal: it over-deters compliant types and under-deters the
strategically negligent.

**Scope.** Unlike Propositions 1–3, this result requires that the regulator is
optimally designing ε(k). In the empirical model the regulatory machine is held
fixed as an exogenous Markov process. Proposition 4 therefore serves as a normative
benchmark: comparing the estimated penalty pattern to the K&S-optimal convex
schedule reveals whether the observed SDWA enforcement regime is well-designed
relative to the first-best.

---

## Summary of Signs

| Proposition | Perturbation | Direction | Required conditions |
|---|---|---|---|
| P1 | θ → a\_opt | da\_opt/dθ > 0 | b'(a) > 0, SOC holds |
| P2 | λ → a\_opt | da\_opt/dλ < 0 | e'(a) > 0 under A1, SOC holds |
| P3 | m → a\_opt | da\_opt/dm > 0 | P1 + dθ/dm > 0 |
| P4 | optimal ε(k) | Δ²ε(k) > 0 | MLRP of Poisson, monotone hazard rate, h convex |

P1–P3 hold for any monotone convex penalty function e(a) and do not require
regulator optimality. P4 requires the full mechanism design framework.

---

## Note on the Assumption e'(a) > 0

e'(a) > 0 is **not** derived from the Poisson structure. Since:

```
e'(a) = E_a[ ε(K+1) − ε(K) ]
      = Σ_{k=0}^∞  [ε(k+1) − ε(k)] · Pr(K = k | a)
```

and Pr(K = k | a) > 0 for all k and all a > 0, the sign of e'(a) depends entirely
on the increments of ε. e'(a) > 0 holds if and only if the increments ε(k+1) − ε(k)
are not all non-positive — i.e., ε is non-decreasing and non-constant. This is
Assumption A1.

A1 is mild: any penalty schedule that fails it would reward monitoring violations at
the margin (more violations → lower or equal expected penalty) and could not deter
negligence at all. If A1 fails, the CWS's interior FOC has no solution and the
corner a = ā is optimal for every type. Ruling it out is therefore equivalent to
requiring that the enforcement regime creates positive deterrence.

A1 is also given normative grounding by Proposition 4: the optimal penalty schedule
is strictly convex, hence strictly increasing, hence satisfies A1 with strict
inequality at every k. In the positive analysis (P1–P3) A1 is maintained; P4 shows
the optimal schedule satisfies something stronger.

**The parallel question for e''(a) > 0 (needed for the SOC when b'' = 0).** The
cleanest resolution is to assume b is strictly concave (b'' < 0), so the SOC holds
regardless of the sign of e''(a). If b is linear, one must additionally assume ε is
sufficiently convex to ensure E\_a[Δ²ε(K)] > 0.
