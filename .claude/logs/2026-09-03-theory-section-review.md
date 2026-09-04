# Session: 2026-09-03 — theoretical model review and N removal

## Objective

Check the theoretical model section of `main.tex` for correctness, then apply the
subset of fixes the user approved: the interiority gap, the leftovers from the
Proposition 2 cutoff fix (commit cbea29a), and the exposition items. Afterwards,
remove `N` from the model entirely.

## Verification performed

Re-derived every step by hand and checked numerically against brute-force global
maximization of the (non-concave) objective. All three propositions are correct as
stated:

| Claim | Result |
|---|---|
| Eq. (1) `chat(a) = t - (r-ps)q(a)` | correct |
| Prop 1 `da/dtheta` | matches numeric derivative to 9 dp, both branches |
| Prop 2 `c*(theta)` | integral form, `W`-difference form, and brute-force global max agree to 7 dp |
| cbea29a cutoff fix | `c*` sits strictly inside `[chat(a_MR), chat(a_SR)]` — confirms the old `chat(a_SR)` was the top of the hysteresis band |
| Channel A + Channel B | equals `dMR/dm` numerically; both channels >= 0 |
| Eq. (7) integration by parts | matches direct computation; boundary terms vanish |
| Prop 3 | `dC*/dlambda >= t-(r-ps)q(abar) >= 0`, `da/dlambda <= 0` |

## Changes Made

- `main.tex` theory section (~lines 208-365) and Discussion line 563.

### Substantive
- Added a third maintained assumption: optimal negligence is interior. Prop 1's
  derivative, the strict `a_SR < a_MR`, and `c*'(theta) < 0` all require it. At a
  corner both branches select the same negligence and those inequalities go weak;
  Prop 2 is unaffected because it uses only `dh/dtheta >= 0`.

### Leftovers from the Proposition 2 cutoff fix
- FOC display relabelled from `chat(a)`-delimited "regions" to reporting "branches";
  "region" -> "branch" throughout.
- Rewrote the paragraph that framed the partition by `chat(a)` — it is `c*(theta)`
  that partitions types, and it lies between `chat` at the two candidate negligence
  levels.
- Discussion: `chat(a) = t - (r-ps)q(a)` -> `c*(theta) = t - int_{ps}^{r} q(a(rho;theta)) drho`.

### Exposition
- Restored the commented-out Channel B derivation (varphi substitution, integration
  by parts, boundary term vanishing because `F(0;m)=0` and `F(thetabar;m)=1` for
  every `m`) and the Channel A intuition sentence.
- `h'(theta)` -> `dh(theta,m)/dtheta` in all rendered math.
- `e(a)` -> `e(a;c)`, relabelled "expected annual cost" (it contains `c`, a resource
  cost, not a penalty).
- Deleted the dangling "By assumption dF/dm <= 0." fragment.
- "number of utilities" -> "share" in Props 2 and 3 and the `MR(m)` lead-in.
- Stated the support of `c` as `[0, cbar]`, fixed in `m`.
- `chat(a)` -> `chat_lambda(a)`; `C*(lambda)` -> `C*(lambda;theta)`.
- Prop 3 now aggregates over types: `SR(lambda) = int G(C*(lambda;theta);m) f dtheta`.

### N removal
Removed `N` from every equation and every mention in the theory section.

## Design Decisions

| Decision | Rationale |
|---|---|
| Remove `N` entirely | `N` enters only via the product `N*rho`, so `a(rho;theta)|_N = a(rho;theta/N)|_{N=1}` and `c*_N(theta) = c*_1(theta/N)`, verified to 12 dp for N in {1,2,4,7.5}. `theta` is a free random variable with an unrestricted distribution, so `N` is not separately identified from the units of `theta` — it is a normalization, not a parameter. `MR(m)` is unchanged under the change of variable `theta/N`. |
| `c` is the *annual* self-reporting cost | Keeps the intensive margin without `N`: `c` encapsulates total annual testing cost, agnostic as to whether cost-per-test rose or the number of required tests rose. One word ("annual") carries the interpretation without committing the paper to it. |
| Keep line 216's "regulators require more sampling" sentence | With `c` an annual total, more required tests raise `c`, which *is* the `dG/dm <= 0` assumption. Removing `N` closes this gap rather than sidestepping it. |
| Left the Discussion gap unfixed (user's call) | The Discussion infers "MR up, recorded MCL flat => cost channel, not concealment". In the model, recorded MCL rates are `q(a_SR)` for reporters and `p*q(a_MR)` for under-reporters; since `a_MR > a_SR`, that inference needs `p*q(a_MR) < q(a_SR)`, which does NOT follow from `r > ps`. A grid search over `p` in `(0, r/s)` and `theta` found 72 violating pairs. Flagged, not fixed. |

## Verification Results

- [x] All three propositions re-verified numerically after `N` removal
- [x] `main.tex` compiles, exit 0, zero LaTeX errors, 66 pages
- [x] No `N` remains anywhere in lines 200-370 (regex scan)
- [x] Only pre-existing undefined refs remain (`tab:mr_mcl_incidence_summary`,
      `2ndstage2slsreg`), both in empirical sections
- [x] The 3.5pt theory-section overfull hbox (pre-existing at HEAD, confirmed by
      compiling the HEAD version) is gone as a side effect of the shorter prose

## Open Questions / Blockers

- The Discussion gap above is unresolved by choice. If it is ever addressed, it
  wants either an added assumption or its own proposition, since it carries the
  paper's central empirical distinction.
- Pre-existing prose bugs left untouched: line 557 has an unfinished sentence
  ("provides evidence of ."), and line 567 has a `\section{...}` jammed onto the end
  of a paragraph, uncapitalized.

## Next Steps

- Decide whether to state the `p*q(a_MR) < q(a_SR)` condition explicitly.
- Fix the two prose bugs at lines 557 and 567.
