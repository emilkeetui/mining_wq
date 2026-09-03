# Session: 2026-09-03 — Replace Corollary 1 with kappa-bounded exceedance assumptions

## Objective
Started as a conceptual question about `main.tex`: if Channel B = 0 and MR violations rise
with mining, does that mean utilities aren't concealing exceedances? Answer was no, which
exposed a defect in the existing Corollary 1. Ended with Corollary 1 deleted and replaced
by three primitive assumptions.

## The defect found
The published Corollary 1 assumed `q(a_SR(theta)) = q_bar`, constant across types. But
Prop 1 gives `a_SR'(theta) > 0` strictly and the setup gives `q' > 0` strictly, so
`q(a_SR(theta))` is strictly increasing in theta and **cannot** be constant at an interior
optimum — for any q_bar, not just zero. The hypothesis was unsatisfiable. Allowing q a flat
spot doesn't rescue it either: `q'(a)=0` makes the FOC `theta*b'(a) = N*rho*q'(a)`
unsatisfiable with `b' > 0`, pushing those types to a corner.

## Approaches tried and rejected
1. **Corner solution (Assumption Q0)** forcing `a_SR(theta) = 0` for all theta — user
   caught that this collapses Prop 1 (`da_SR/dtheta = 0`, not `> 0`). Correct.
2. **epsilon-scaling `q_eps(a) = eps*q(a)`, take `eps -> 0`** — Opus verification found
   this fails too: as eps -> 0 the FOC `theta*b'(a) = N*r*eps*q'(a)` has no interior
   solution (LHS bounded below by `theta*b_min > 0`, RHS -> 0), so every type corners at
   `a = a_bar`. The corner moved from 0 to a_bar, it wasn't eliminated. The Sonnet claim
   "Props 1-3 hold at every eps with no corner" was false.
3. **Rely on `s > r` alone** — doesn't work. The wedge is `(r - ps)`; killing it needs
   `p >= r/s`, a condition on the *investigation probability*, not on s. And that route is
   blocked by the paper's own enforcement results (visits up, formal enforcement down,
   line 555 says regulators don't uncover hidden MCLs = **low p**), which imply the wedge
   is wide open. Also would make "cost not concealment" an assumption, not a finding.

## Resolution adopted (user's idea, and it's the right one)
Assume q is small in **level**, not in slope. Level and slope do opposite things:
- `q(a_bar) <= kappa` small ⟹ wedge `(r-ps)*q(a)` small ⟹ cutoff ≈ t ⟹ cost-driven. This
  is what the empirical claim needs.
- `q'` small ⟹ corner ⟹ Prop 1 dies. So never shrink the slope.

A1 and A2 coexist because `q'' >= 0` (already assumed) makes q convex: it can sit below
kappa across most of [0, a_bar] and climb steeply near a_bar. With `q(a) = kappa*(a/a_bar)^n`,
`q(a_bar) = kappa` is fixed while `q'(a_bar) = n*kappa/a_bar` grows without bound in n, so A2
is satisfiable for any kappa however small.

## Changes made to main.tex
- **Setup (after line 218):** added Assumption 1 (`q(a_bar) <= kappa`, treatment headroom),
  Assumption 2 (`theta_bar*b'(a_bar) < N*ps*q'(a_bar)`, keeps negligence interior — stated
  with ps not r since ps < r is the binding region), Assumption 3 (reporting-cost density
  and its m-response bounded by g_bar; needed for the MVT bound, was being used implicitly
  and never stated).
- **Corollary 1 and its proof: deleted.** Replaced by a kappa-bound continuation of Prop 2's
  derivation — cutoff bound `|c*(theta) - t| <= (r-ps)*kappa`, the Leibniz step retained,
  MVT + A3 giving `|Channel B| <= g_bar*(r-ps)*kappa*int|df/dm|`, and
  `dMR/dm = -dG(t;m)/dm + O(kappa) >= 0`.
- **Prop 3 (line 387):** side condition `t >= (r-ps)*q(a_bar)` now *derived* from A1 rather
  than assumed separately.
- **Discussion (lines 577-579):** rewritten to argue from kappa instead of from `q'(a_SR)=0`
  and Corollary 1. Added the point that concealment isn't ruled out because it wouldn't pay
  — with p low it would — but because there's nothing to conceal.
- Propositions 1, 2, 3 statements themselves are unchanged.

## Verification Results
- [x] `latexmk -pdf` compiles, 67 pages
- [x] Zero LaTeX errors in main.log (no `!`, no undefined control sequences, no runaway args)
- [x] `grep -i corollary main.tex` returns nothing — fully removed
- [x] Prose junction at lines 332/334 flows correctly

## Pre-existing issues found, NOT fixed (unrelated to this work)
- 5 unresolved references: `2ndstage2slsreg` (x3, lines 572/578/582) and
  `tab:mr_mcl_incidence_summary`, `tab:sanitary_visit_timing_formal_enforcement_rate`.
  `\label{2ndstage2slsreg}` exists in `main.tex.preformat.bak`, `csquip_draft.tex`, and
  `richer_sanitary_visit_model.tex` but **not** in `main.tex` — the label was dropped in an
  earlier reformat. The two table labels live in `sum/*.tex` files not input where referenced.
- Line 563 has a broken sentence: "If coal mining affects contamination exceedances then
  this provides evidence of ." — pre-existing, left alone.

## Gotcha for future sessions
Do not `cd` in the Bash tool. It moves the session cwd, and the `protect-raw-data` PreToolUse
hook resolves its script path relatively, so every subsequent Bash and Write call is blocked
with a "can't open file" error. Recovery: the PowerShell tool is not hooked and shares the
same cwd — use `Set-Location <project root>` there to unstick it. Use absolute paths in Bash.

## Next Steps
- `job_talk.tex` still has 6 Corollary 1 references (lines 265, 281, 408, 437, 498, 504),
  including a full statement+proof appendix slide at 498-504 built on the old `q_bar`
  version. All now orphaned. Needs resyncing to the kappa framing — see
  [[2026-08-31-job-talk-corollary-1]].
- Consider fixing the 5 dangling refs above in a separate pass.
