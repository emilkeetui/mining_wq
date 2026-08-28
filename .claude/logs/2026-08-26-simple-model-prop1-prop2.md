# Session: 2026-08-26 — Simple theoretical model: Proposition 1 fix + Proposition 2 derivation

## Objective
Check and fix the comparative-static total derivative in Proposition 1 of
`lit/simple_theoretical_model.tex`, then derive Proposition 2 (effect of mining
contamination $m$ on the aggregate MR-violation rate) step by step and write the
full derivation into the file.

## Changes Made
- `lit/simple_theoretical_model.tex`:
  - **Proposition 1** (was already fixed by the user before this session's Q&A
    started): $\partial a/\partial\theta = b'(a) / [-\theta b''(a) + N\rho q''(a)]$.
    Verified via implicit function theorem on the FOC $\theta b'(a) = N\rho q'(a)$;
    confirmed sign via the second-order condition ($N\rho q''(a) - \theta b''(a) \ge 0$
    is exactly $-U''(a) \ge 0$) combined with $b'(a) > 0$.
  - **Setup** (line 24): added the missing FOSD-in-$m$ assumption for the
    compliance-cost distribution $\Theta(\cdot;m) \equiv F(\cdot;m)$, with density
    $f(\cdot;m)$ — needed once the user clarified that $m$ shifts $\theta$'s
    distribution too, not just the self-report cost distribution $G(\cdot;m)$.
  - **Proposition 2** (lines 66-104, new): full derivation of $\partial MR/\partial m \ge 0$.
    - Defined the $m$-invariant switching cutoff $c^*(\theta) = \hat c(a_{SR}(\theta))$.
    - Wrote aggregate $MR(m) = \int [1-G(c^*(\theta);m)]\,f(\theta;m)\,d\theta \equiv \int h(\theta,m) f(\theta;m)\,d\theta$.
    - Split $\partial MR/\partial m$ into two channels via the product rule (Channel A:
      cost-distribution shift holding type fixed; Channel B: type-distribution shift).
    - Channel A signed directly via FOSD in $c$.
    - Channel B required integration by parts to convert an unsigned term
      ($\partial f/\partial m$, no assumed sign) into a signed one ($\partial F/\partial m \le 0$
      by FOSD), which mechanically moves the derivative onto $h$, requiring $h'(\theta)\ge 0$.
      Signed $h'(\theta)$ using $c^{*\prime}(\theta) < 0$, itself derived by chaining
      Proposition 1's $a_{SR}'(\theta) > 0$ through $c^*(\theta) = t-(r-ps)q(a_{SR}(\theta))$.
    - Both channels $\ge 0 \Rightarrow \partial MR/\partial m \ge 0$, reinforcing.
  - Compiled via `latexmk -pdf` (pdflatex + biber): 4 pages, no errors, no
    `Undefined references`/`Overfull`/`Underfull` warnings. Sent PDF to user.

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| Kept $F(\cdot;m)$ as the compliance-cost CDF symbol (matching the file's pre-existing, if sloppy, use of $F(\cdot)$ for $\Theta$) rather than introducing a new letter | Minimizes notation churn in a file the user is actively iterating on; flagged the original $\Theta$/$F$ overload to the user rather than silently renaming |
| Derived Channel B via integration by parts instead of asserting the FOSD monotonicity result | User pushed back twice (once on the reversed Prop 1 fraction, once questioning why $h'(\theta)$ appears when the raw expression has $\partial f/\partial m$) — showing the mechanical integration-by-parts step rather than citing the stochastic-dominance lemma as a black box was necessary to satisfy the question |
| Two-channel decomposition (rather than one) | User corrected the initial single-channel version by pointing out "m touches $\theta$ too" — $\Theta(\cdot;m)$'s own $m$-dependence was already in the file's notation (line 24) but had been dropped in the first derivation attempt |

## Verification Results
- [x] File compiles end-to-end via latexmk/pdflatex/biber with no errors
- [x] Output PDF exists (`lit/simple_theoretical_model.pdf`, 4 pages)
- [x] No undefined references or overfull/underfull box warnings in the `.log`
- [x] Delivered to user via SendUserFile

## Open Questions / Blockers
- None. Standalone theory note, not wired into `main.tex` or the empirical pipeline.

## Note on recurring tooling quirk
Reconfirmed the cwd-sharing issue already logged in
`2026-08-26-nonseparable-theory-model.md`: running `cd "lit" && latexmk ...` in Bash
left the persisted cwd inside `lit/`, so a subsequent Bash `grep` invoked the
`protect-raw-data.py` PreToolUse hook with its relative path and failed to find it,
blocking the call. Recovered by using the `Grep` tool (absolute path) instead of Bash.
Fix for next time: avoid bare `cd` in Bash calls in this project; use a subshell
`(cd dir && ...)` or pass absolute paths to the LaTeX tools directly.

## Next Steps
- None requested. Available if the user wants Proposition 2 cross-referenced back
  against the non-separable model (`theoretical_model_nonseparable.tex`) from the
  earlier session, or wants the propositions tied into the empirical IV strategy.
