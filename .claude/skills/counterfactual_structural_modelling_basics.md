# Counterfactual Structural Modelling — Basics

A simple worked example using two cellphone firms, logit demand, and a
Bertrand-Nash pricing equilibrium. The point of this note is to make explicit
the *mechanics* of estimation and counterfactual simulation in a structural
model, with the smallest setting that still contains all the moving parts.

---

## 1. Setup

### Consumers

A unit mass of consumers each pick one phone j ∈ {1, 2} or the outside good
j = 0. Utility from option j is:

    u_ij = δ_j + ε_ij,    with    δ_j = α·x_j − β·p_j,    δ_0 = 0

where x_j is a quality attribute (camera, screen), p_j is price, and ε_ij is
iid Type-I extreme value. Choice probabilities (= market shares) take the
standard logit form:

    s_j(p₁, p₂) = exp(α·x_j − β·p_j) / [1 + exp(α·x₁ − β·p₁) + exp(α·x₂ − β·p₂)]

### Firms

Each firm produces phone j using capital K_j and labor L_j via a Cobb-Douglas
technology, so total cost reduces to:

    C_j(q_j) = w·L_j + r·K_j = κ_j · q_j^γ

where q_j = M · s_j is units sold (M = market size), κ_j bundles input prices
(w, r) and the production constants, and γ governs returns to scale (γ < 1
means decreasing marginal cost; γ > 1 means increasing marginal cost).
Marginal cost:

    mc_j(q_j) = γ · κ_j · q_j^(γ−1)

### Bertrand-Nash pricing

Firm j chooses p_j to maximize profit, taking p_{-j} as given:

    π_j = (p_j − mc_j) · M · s_j(p₁, p₂)

The first-order condition gives the textbook logit-Bertrand markup formula:

    p_j − mc_j = 1 / [β · (1 − s_j)]      (★)

This is the equilibrium relationship between price and marginal cost when
firms set prices optimally under logit demand.

---

## 2. Estimation — recovering the primitives

You need (α, β) on the demand side and (γ, κ₁, κ₂) on the supply side. These
are the *deep parameters* — preferences and technology — that are assumed
invariant to the policy you will later perturb.

### Data requirement

Note that the logit inversion below is identified only with **many
observations** (a panel of markets × products, or individual-level choice
data). Two firms in one market is not enough — see Section 5.

### Demand side

With observed shares and prices, invert the logit equation:

    ln(s_j) − ln(s_0) = α·x_j − β·p_j + ξ_j

where ξ_j is the unobserved product quality (the BLP error term). Regress
the LHS on x_j and p_j across the panel of (product, market) cells.

If p_j is correlated with ξ_j (it usually is — firms charge more for things
consumers like that the econometrician doesn't see), instrument p_j with
cost shifters (input prices, BLP-style rival-product characteristics).
Estimating logit demand without an instrument is fine only when price is
plausibly exogenous to unobserved demand shocks — e.g., when prices are
regulated.

### Supply side

The trick: you don't observe marginal cost directly, but you can *construct*
it from the demand-side FOC. Given α̂ and β̂, invert equation (★) to get a
constructed marginal-cost column:

    m̂c_j = p_j − 1 / [β̂ · (1 − s_j)]      ← a number for every observation

This is a number you can compute for every (j, market) cell, even though no
firm reported its marginal cost.

Now use the **cost-function expression** for marginal cost:

    mc_j = γ · κ_j · q_j^(γ−1)

Equating the two expressions and taking logs:

    ln(m̂c_j) = ln(γ·κ_j) + (γ − 1)·ln(q_j)
    └─ dep. var ─┘    └─ const. ─┘   └ regressor ┘

Why two expressions for mc? They come from different sources and must agree
in equilibrium:

- (★) comes from the **firm's FOC** (optimal pricing behavior). It contains no
  cost parameters — it's an accounting identity given Bertrand-Nash behavior.
  This is how you *construct* the LHS variable.
- mc = γ·κ·q^(γ−1) comes from the **cost function** (technology). It contains
  the structural parameter γ you want to estimate. This is the regression
  equation.

You regress ln(m̂c_j) on ln(q_j). Because q_j is endogenous (the firm picked
it in response to a cost shock ε_j you don't observe), instrument ln(q_j)
with input-price shocks (sudden changes in w or r) or other cost shifters
that don't affect demand. Run 2SLS or GMM. Out come γ̂ and κ̂_j.

### What you have at the end of estimation

A full set of primitives: α̂, β̂, γ̂, κ̂_j. These are preferences and
technology — they are assumed to NOT change when policy changes. That's the
key assumption that makes counterfactuals possible.

---

## 3. Pick a counterfactual

Examples:
- **Merger:** firms 1 and 2 become a single multi-product firm.
- **Per-unit tax t on phone 1:** government adds a tax to product 1.
- **Input price shock:** rental rate r doubles (capital becomes expensive,
  shifting κ_j upward).
- **Entry/exit:** firm 2 leaves the market; firm 1 becomes a monopolist.

For concreteness, let's work through the **per-unit tax t on phone 1**. The
firm-1 FOC becomes:

    p₁ − mc₁ − t = 1 / [β̂ · (1 − s₁)]

Firm 2's FOC is unchanged.

---

## 4. Solve for the new equilibrium (the fixed point)

You now have a system of 2 equations (the two FOCs) in 2 unknowns (p₁, p₂),
where shares s_j and marginal costs mc_j(q_j) = mc_j(M·s_j) both depend on
(p₁, p₂). Solve by iteration:

    Initialize:    p₁⁽⁰⁾, p₂⁽⁰⁾ = observed prices
    Repeat:
      1. Given p₁⁽ⁿ⁾, p₂⁽ⁿ⁾, compute new shares s_j from the logit formula.
      2. Compute new quantities q_j = M·s_j and new marginal costs
         mc_j = γ̂·κ̂_j·q_j^(γ̂−1).
      3. Update prices from the FOCs:
           p₁⁽ⁿ⁺¹⁾ = mc₁ + t + 1 / [β̂·(1 − s₁)]
           p₂⁽ⁿ⁺¹⁾ = mc₂     + 1 / [β̂·(1 − s₂)]
      4. Stop when |p⁽ⁿ⁺¹⁾ − p⁽ⁿ⁾| < tolerance.

At convergence p* = (p₁*, p₂*) is the new Bertrand-Nash equilibrium under
the tax. The shares s_j* and quantities q_j* generated in the final
iteration are internally consistent with p* by construction (they're not a
separate calculation — just the values from the converged loop).

### Welfare

Consumer surplus in logit has a closed form (the "log-sum"):

    CS = (1/β̂) · ln[1 + exp(α̂·x₁ − β̂·p₁*) + exp(α̂·x₂ − β̂·p₂*)]

Profits are π_j* = (p_j* − mc_j*) · q_j*. Government revenue is t · q₁*.

Compare to the baseline (no-tax) equilibrium:

    ΔW = [CS* − CS⁰] + [π₁* − π₁⁰] + [π₂* − π₂⁰] + t·q₁*

---

## 5. The key principle

Counterfactuals work because the *primitives* (α, β, γ, κ) are assumed
invariant to the policy change. The policy alters one piece of the firm's
optimization problem — here, an extra t in the FOC — and the model tells
you how everything else (prices, shares, costs, welfare) rearranges in
response.

The pattern is always the same:

1. **Specify** a model of behavior with deep parameters.
2. **Estimate** the deep parameters from observed equilibrium data.
3. **Perturb** the environment (a policy, a price, a shock).
4. **Re-solve** the equilibrium with the same parameters and the new
   environment — this is typically a fixed-point computation.
5. **Compare** outcomes (welfare, prices, quantities) to the baseline.

### A note on demand vs supply identification

The side of the market that *chooses* the regressor of interest is the side
that needs instruments. Consumers don't choose prices — they react to them
— so demand can sometimes be estimated by MLE or OLS on the logit
inversion. Firms *do* choose quantities (and prices) in response to costs
the econometrician doesn't observe, so the supply side almost always needs
instruments (cost shifters that move firm choices without moving demand).

### A note on the data dimension

The toy model above has 2 products in 1 market — that's enough to describe
the *theory* but not enough to *estimate* it. Real estimation requires
either:

- A panel of (product × market) observations (BLP-style), or
- Individual-level choice data with N consumers each picking among the
  alternatives (the approach Navarro takes for mode choice).

---

## 6. Implementing with individual-level data

The sections above use **aggregate market shares** to invert logit demand. With
individual-level choice data you skip the inversion and write the likelihood
directly. The supply side and counterfactual fixed point are essentially unchanged.

### Data structure

One row per (consumer i, alternative j), or one row per consumer with a
chosen-alternative column.

| field | meaning |
|---|---|
| `i` | consumer ID |
| `m` | market / time period (so prices and choice sets vary) |
| `j ∈ {0, 1, 2}` | alternative (0 = outside good) |
| `y_ij ∈ {0,1}` | 1 if i chose j |
| `p_jm`, `x_jm` | price and attributes of j in market m |
| `z_i` (optional) | demographics, for interactions with α, β |

You need variation across **markets** (or time) in p and x — otherwise α and β
aren't separately identified from a constant.

### Demand estimation — MLE instead of share inversion

Each consumer's choice probability is the same logit formula:

    P(i picks j | p_m, x_m) = exp(α x_jm − β p_jm) / [1 + Σ_k exp(α x_km − β p_km)]

Log-likelihood over the sample:

    ℓ(α, β) = Σ_i Σ_j  y_ij · log P(i picks j)

Maximize numerically (e.g. `mlogit` in R, `statsmodels` / `PyLogit` in Python,
or hand-rolled via `optim` / `scipy.optimize`). With demographics, let
β_i = β₀ + β₁ z_i to get heterogeneous price sensitivity — this is where
individual data pays off relative to aggregate BLP, since you observe *who* chose
*what*.

**Endogeneity of price.** Same issue as the aggregate case: if p_jm correlates
with an unobserved demand shock ξ_jm, MLE is biased. Two fixes:

- **Control function** (Petrin–Train): first-stage regress p on cost shifters, get
  residual v̂, include v̂ in the utility, then MLE.
- **BLP with micro moments** (Berry–Levinsohn–Pakes + Petrin): match individual
  choice moments and aggregate share moments jointly.

If prices are regulated or otherwise plausibly exogenous (Navarro's case — Santiago
bus fares are set by a regulator), plain MLE on individual choices is fine.

### Supply estimation — virtually unchanged

The supply side still operates at the **product × market** level. After estimating
(α̂, β̂):

1. Compute predicted market shares ŝ_jm by averaging individual probabilities:
   `ŝ_jm = (1/N_m) Σ_i P̂(i picks j)`.
2. Build the constructed marginal cost: `m̂c_jm = p_jm − 1 / [β̂ (1 − ŝ_jm)]`.
3. Run the log-cost regression `ln(m̂c_jm) = ln(γ κ_j) + (γ−1) ln(q_jm) + u_jm`,
   instrumenting `ln q_jm` with cost shifters.

The only difference from the aggregate case is that ŝ_jm comes from averaging
individual probabilities rather than being read off aggregate market data.

### Counterfactual — fixed point is identical

The Bertrand-Nash fixed point in (p₁, p₂) runs exactly as in Section 4. The only
choice: when computing new shares at each iteration, either

- **Plug new p into individual probabilities** and average across the sample
  (preserves heterogeneity in β_i if estimated), or
- **Use the closed-form logit share** with the average α, β (loses heterogeneity
  but is faster).

For welfare, consumer surplus is computed **per consumer** and summed:

    CS_i = (1/β̂_i) · log[1 + Σ_j exp(α̂ x_j − β̂_i p_j*)]
    ΔCS  = Σ_i (CS_i* − CS_i⁰)

Heterogeneous β_i means the tax burden falls unequally across consumers — the
distributional question that individual data answers and aggregate BLP cannot.

### Concrete R sketch

```r
library(mlogit); library(fixest); library(data.table)

# demand: long format, one row per (i, j)
dt_long <- mlogit.data(dt, choice = "y", shape = "long",
                       alt.var = "j", chid.var = "i", id.var = "i")
dem <- mlogit(y ~ p + x | 0, data = dt_long)   # coef(dem) gives α, β

# predicted shares per (j, m)
shares <- dt[, .(s_hat = mean(predict(dem, .SD))), by = .(j, m)]

# supply: construct mc, regress
shares[, mc_hat := p - 1 / (coef(dem)["p"] * (1 - s_hat))]
shares[, q := M * s_hat]
sup <- feols(log(mc_hat) ~ 1 | 0 | log(q) ~ cost_shifter, data = shares)
gamma_hat <- 1 + coef(sup)["fit_log(q)"]

# counterfactual: iterate FOC until ||Δp|| < tol
p_new <- p_obs
repeat {
  s <- logit_shares(p_new, alpha_hat, beta_hat, x)
  mc <- gamma_hat * kappa_hat * (M * s)^(gamma_hat - 1)
  p_next <- mc + 1 / (beta_hat * (1 - s))
  p_next[1] <- p_next[1] + t          # per-unit tax on product 1
  if (max(abs(p_next - p_new)) < 1e-8) break
  p_new <- p_next
}
```

### Summary: what changes vs. aggregate data

| Step | Aggregate (BLP-style) | Individual-level |
|---|---|---|
| Demand estimation | Invert shares; IV regression | MLE on choice probabilities; control function for endogeneity |
| Shares at new prices | Closed-form logit formula | Average individual probabilities (or same formula if homogeneous β) |
| Welfare | Log-sum at market level | Log-sum per consumer; summed |
| Distributional effects | Not identified | Identified via β_i × z_i interactions |
| Supply estimation | Identical | Identical |
| Counterfactual fixed point | Identical | Identical |

---

## 7. Applied real example: Navarro (2025), *On the Right Track*

Navarro's job market paper applies exactly this template to public transit
contracts in Santiago, Chile. The mapping is:

| Toy model component                | Navarro analogue                                                                 |
|------------------------------------|----------------------------------------------------------------------------------|
| Consumer picks phone 1, 2, or 0    | Traveler picks transit route, car, or walking (outside option)                   |
| Logit utility u = δ + ε            | Mode choice logit + route choice with exponential wait-time shocks               |
| Quality attribute x_j              | In-vehicle time, wait time, fare, transfer penalty                               |
| Price coefficient β                | α_price (marginal utility of money)                                              |
| Firm produces with K, L            | Bus operator produces service with labor (γ), regularity effort (φ), depots (ρ) |
| Cost C_j(q_j) = κ_j · q_j^γ        | C_rdkt = w·(f·L/s)^γ · CV^(−φ) · |R|^ρ · ε                                       |
| Firm FOC for price (Bertrand-Nash) | Operator FOCs for frequency f and headway regularity CV                          |
| Markup formula p − mc = 1/[β(1−s)] | Operator FOC equates marginal cost to passenger revenue + per-km revenue −      |
|                                    | marginal penalty (more complicated because there are two attribute choices,      |
|                                    | not one price)                                                                   |
| Demand estimation                  | Simulated MLE on individual mode-and-route choices (no IV needed because         |
|                                    | fares are regulated and FE absorb route unobservables)                           |
| Supply estimation                  | GMM on the log-marginal-cost equation; instruments are bus breakdowns (for f),  |
|                                    | monitoring intensity (for CV), depot reallocations (for |R|), free-flow          |
|                                    | nighttime speeds (for s)                                                         |
| Counterfactual: a tax              | Counterfactuals: stricter quality targets τ, alternative route bundling, fully  |
|                                    | regulated planner, unregulated monopoly                                          |
| Fixed-point in (p₁, p₂)            | Fixed-point in (firm service attributes, traveler choices, road congestion)     |
| Welfare comparison                 | ΔW across regimes, decomposed into CS, PS, externalities                         |

### Where Navarro is more complex than the toy model

1. **Multiple choice dimensions per firm.** Firms don't just pick a price —
   they pick frequency f and regularity CV for each route. So there are two
   FOCs per route, and the cost equation has both ln(f) and ln(CV) on the
   right-hand side. This is why his GMM stacks two equations (one per
   attribute) and uses multiple instruments.

2. **Network effects in demand.** A traveler's utility on route r depends on
   service attributes of *other* routes (transfer options). The fixed-point
   loop in counterfactuals must account for these cross-route spillovers.

3. **Congestion feedback.** Travel times depend on traffic flows, and
   traffic flows depend on mode choices, and mode choices depend on travel
   times. The counterfactual must iterate over road congestion as well as
   firm/consumer behavior.

4. **Regulator design questions.** The counterfactuals don't just compare
   two equilibria — they search over policy parameters (the penalty τ for
   wait-time deviations) to find the welfare-maximizing setting.

### Where Navarro is exactly the same as the toy model

- Estimate primitives (preferences, costs) under observed policy regime.
- Hold primitives fixed; change the policy (penalty strength, bundling).
- Re-solve the equilibrium as a fixed point in firms' and consumers'
  choices.
- Compute welfare under each regime and compare.

The mental model is identical. Once you understand the two-firm logit-
Bertrand example, Navarro's framework is just the same thing with more
products, more choice dimensions per firm, and a congestion equation
layered on top.
