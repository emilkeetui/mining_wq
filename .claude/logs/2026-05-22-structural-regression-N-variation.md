# Session: 2026-05-22 — Structural CCP regression: N and variation

## Objective
Clarify the sample size and source of variation in the estimating equation
log[Pr(MR|x)/Pr(comply|x)] = (k_comply − k_MR) + β[V̄(1) − V̄(0)]·Δπ(x) + γ·v̂_t
(section3_model_setup.tex:302–308).

## Key clarifications
- State space x has 8 cells (2 enforcement × 4 upstream-production quartiles),
  ~780 obs per cell → ~6,240 PWSID×year obs total.
- Within a cell, Pr(MR|x), Pr(comply|x), and Δπ(x) are constants by construction.
- Across cells: 8 distinct LHS values, 8 distinct Δπ(x) values — this is the
  variation that identifies the slope β[V̄(1) − V̄(0)] and the intercept.
- β[V̄(1) − V̄(0)] is a single scalar constructed once from CCPs and transitions
  via the AM (2011) inversion — no variation in the regression.
- v̂_t varies at PWSID×year but the LHS is constant within cell — so v̂_t has
  nothing to explain at the cell level.

## Specification problem surfaced
The estimating equation can't simultaneously
  (a) be estimated on cell-level log-odds (N=8, identifies slope from cross-cell
      variation), and
  (b) include a PWSID×year control-function residual v̂_t.
Either the regression is N=8 with no v̂_t, or it must be re-cellularized at
(x, t) or (x, z-bin) so the LHS varies along the dimension v̂ varies on.
This sharpens Caveat 1 in 2026-05-07-section3-structural-explainer.md.

## Open questions
- Refine cells to (x, year) so LHS varies at year level and v̂_t is meaningful?
  Cell sizes drop to ~780/21 ≈ 37 obs per (cell, year) — noisy CCPs.
- Alternative: continuous-state CCP specification where v̂_t enters at obs level.
- Or: drop v̂_t from the structural CCP regression entirely and rely on the
  reduced-form 2SLS as the IV-validity exercise.

## Diagnosis of the three resolutions

### A. Refine cells to (x, year)
**Regression.** Cells = 8 × 21 ≈ 168. LHS log-odds tabulated within each (x, t).
  log[P̂(MR|x,t)/P̂(comply|x,t)] = (k_comply − k_MR) + β[V̄(1)−V̄(0)]·Δπ(x) + γ v̂_t + u_{x,t}
**Data.** Same panel re-tabulated. Cell size shrinks to ~37 — many cells will be
0/37 or 37/37 → log-odds undefined; need Laplace smoothing or drop cells.
**Counterfactuals.** Same as baseline 8-cell: re-solve 2-state Bellman with k̂_MR
and a counterfactual primitive (transition prob, enforcement cost); aggregate
change in MR-share. No new counterfactual capability.
**Pros.** Smallest change to existing structure; closed-form V̄ inversion intact;
every term varies at the (x, t) level.
**Cons.** Sparse cells inflate CCP sampling error ~5× over baseline; zero/one
cells force ad-hoc fixes; v̂_t still requires aggregation to (x, t)-mean,
losing cross-PWSID-within-year identification.
**Precedent.** Standard — Hotz–Miller–Sanders–Smith (1994), Aguirregabiria–Mira
(2002, 2007), Kang & Silveria (2021) all use tabulated finite states. Adding
a t index to the cell is conventional when policy environment is non-stationary.

### B. Continuous-state CCP
**Regression.** At PWSID × year:
  log[P̂(MR|enf_it,m_it)/P̂(comply|enf_it,m_it)]
    = (k_comply − k_MR) + β[V̄(1,m_it)−V̄(0,m_it)]·Δπ(enf_it,m_it) + γ v̂_t + u_it
m = continuous `production_short_tons_coal_upstream`. CCPs and action-conditional
transitions estimated as smooth functions (flexible logit / sieve / kernel).
V̄(x,m) solved on a grid via AM inversion + interpolation.
**Data.** Adds bandwidth/sieve-order choice, V̄-grid resolution, defensible
support of m (density in tails).
**Counterfactuals.** Strictly richer:
- ∂P̂(MR)/∂m at any point (marginal effects);
- distribution-shift counterfactuals — replace F(m) with F'(m), integrate ΔP̂(MR);
- continuous policy thresholds (optimal m at which enforcement activates).
A and C only permit bin-reassignment counterfactuals.
**Pros.** Resolves aggregation mismatch + Caveat 1 (discretization) in one move;
unlocks the richer counterfactual menu; v̂_t enters at natural level.
**Cons.** Loses the "tabulation + 2×2 solve + OLS, no fixed point" rhetorical
pitch; V̄ becomes a grid computation (still no nested fixed point, but no
closed form either); first-stage CCP precision drops in policy-relevant tails;
adds bandwidth/grid choices referees probe.
**Precedent.** Well-established. Bajari–Benkard–Levin (2007) canonical;
Aguirregabiria–Mira (2010) survey; Kasahara–Shimotsu (2009) identification.
Applied: Timmins (2002) resource extraction; Ryan (2012) cement industry.
K&S discretize, so this is a methodological extension over the source paper.

### C. Drop v̂_t from the structural regression
**Regression.** Back to cell-level, N = 8:
  log[P̂(MR|x)/P̂(comply|x)] = (k_comply − k_MR) + β[V̄(1)−V̄(0)]·Δπ(x) + u_x
IV concerns handled separately by reduced-form 2SLS in section 4.
**Data.** Nothing beyond baseline 8-cell tabulation.
**Counterfactuals.** Same as A — bin-reassignment, dynamic-deterrence
decomposition (static-cost vs. discounted-future-penalty share of comply margin).
**Pros.** Honest about what 8 cells can identify; preserves the section 3 pitch;
avoids defending a CF that Petrin–Train derived for static logit, not dynamic
DC (Caveat 3 in 2026-05-07 explainer); IV machinery lives in 2SLS where it's
strongest; most literature-conformant.
**Cons.** Concedes k̂_MR is potentially biased if m correlates with unobserved
compliance costs; defense is verbal (same identifying variation enters via
CCPs and Δπ) not statistical; loses diagnostic (iii) — k̂_MR with vs. without
v̂_t; hostile referee can claim structural adds nothing over 2SLS.
**Precedent.** This is the standard Hotz–Miller (1993) / HMSS (1994) approach.
Arcidiacono–Miller (2011) also do not include a CF for the endogenous state.
CF residuals in dynamic CCP are newer and contested — Blundell–Powell (2003,
2004); Berry–Haile (2014); Bajari–Chernozhukov–Hong–Nekipelov (2009).

## Recommendation
- If structural payoff = richer counterfactual menu → **B**.
- If structural payoff = decomposition of comply margin into static-cost vs.
  dynamic-deterrence components → **C**, cleanest and most literature-conformant.
- **A** is minimum-viable but inherits small-N noise (from A's refinement) plus
  C's IV concerns — least attractive of the three.

## Next steps
- Choose A / B / C before writing section 3 estimation subsection.
- If staying with the current equation, footnote the aggregation mismatch.
