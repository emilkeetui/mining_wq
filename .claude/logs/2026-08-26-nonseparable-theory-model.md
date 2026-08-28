# Session: 2026-08-26 — Non-separable theoretical model

## Objective
Write a companion version of `lit/theoretical_model.tex` (the additively separable
benchmark, $q(a,m) = \varphi(a) + \psi(m)$) that instead treats $q(a,m)$ as a general
non-separable function, without assuming a sign on the cross partial $q^{am}$ ($=q^{ma}$
by Young's theorem, since $q$ is $C^2$). Derive the analogous propositions with clear
steps, in a LaTeX file that compiles to PDF.

## Changes Made
- `lit/theoretical_model_nonseparable.tex` (new): full model rebuilt with general $q(a,m)$.
  - Assumption 1 (regularity, non-separable): drops separability, keeps $q^a,q^m>0$ and
    strict concavity in $a$; explicitly does not sign $q^{am}$.
  - Regime jump $a_{MR}(m,\theta) > a_{SR}(m,\theta)$: proved unconditional — never used
    $q^{am}$.
  - Within-regime drift $\partial a_\rho/\partial m = N\rho\,q^{am}/D_\rho$: now generically
    nonzero, sign $= -\mathrm{sign}(q^{am})$ — genuinely ambiguous without a sign assumption.
  - Added an explicit envelope-theorem lemma to keep $\Delta'(m) = -N\Omega(m)$ tractable
    despite $a_\rho$ depending on $m$.
  - Added a mean-value-theorem lemma showing sanction dominance ($\Omega(m)>0$) is automatic
    when $q^{am}\le 0$ but requires a new, explicitly optional **Assumption 2** when
    $q^{am}>0$ can occur.
  - Restated Propositions 1–3 (negligence, MR violations, masking) with every term's sign
    traced back to $\Omega(m)$ and to $q_\rho'(m)$ individually; added a corollary showing
    $q^{am}\le 0$ recovers every sharp separable-model conclusion, and $q^{am}>0$ with
    $\Omega(m)<0$ is the one case that can flip the model's predictions.
- Compiled via pdflatex → biber → pdflatex → pdflatex. Final PDF: 11 pages, no errors,
  no unresolved warnings. Deleted intermediate compile/biber log scratch files after
  confirming success (kept the standard `.aux/.bbl/.bcf/.blg/.log/.run.xml` byproducts,
  matching the existing benchmark file's directory contents).
- Sent the compiled PDF to the user via SendUserFile.

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| Kept identical institutional/setup narrative and citations (`mookherjee1994marginal`, `kaplow1994optimal`) | User asked for "a version of" the existing model, not a new framing — only the separability assumption on $q$ changes |
| Used `\usepackage{enumitem}` with `label=(\roman*)` rather than the base `enumerate` package's `[(i)]` shorthand | Original attempt with `[(i)]` under `enumitem` threw `Package enumitem Error: (i) undefined` — enumitem requires the `label=` key form |
| Stated sanction dominance as an explicit, separately labeled "optional" Assumption 2 rather than folding into Assumption 1 | Mirrors exactly the qualification the separable benchmark's prose already anticipated ("signing $\Omega(m)$ required a separate assumption ... whenever $q^{am}>0$") |
| Proved every proposition's ambiguity by decomposing into a determinate channel (cost, sanction wedge) plus an indeterminate channel (concealment/behavioral, tied to $q^{am}$) rather than just asserting "ambiguous" | Matches the rigor level of the source document and gives the reader the exact sufficient condition ($q^{am}\le0$) that restores each separable-model conclusion |

## Verification Results
- [x] Script (tex) compiles end-to-end via pdflatex/biber with no errors
- [x] Output PDF exists at `lit/theoretical_model_nonseparable.pdf` (11 pages, ~198 KB)
- [x] No `Undefined references` or unresolved `Warning` lines in final `.log`
- [x] Delivered to user via SendUserFile

## Open Questions / Blockers
- None. This is a standalone theory document, not wired into the pipeline or `main.tex`.

## Note on tooling quirk (non-blocking, for future sessions)
The Bash tool's persisted cwd and the PowerShell tool's persisted cwd appear to share
the same underlying state in this environment: a `cd` in one tool changes what the other
sees as its working directory. When cwd drifts away from the project root, the
`protect-raw-data.py` PreToolUse hook (which is invoked with a relative path,
`.claude/hooks/protect-raw-data.py`) fails to find itself and blocks *every* tool call
(Bash, Edit, Write) with a "can't open file" error — not just the one that moved the
directory. Fix: run `Set-Location`/`cd` back to the project root (either tool works,
since state is shared) before the next call, or wrap multi-step shell work in a single
`(cd dir && ...)` subshell so the outer persisted cwd never changes.

## Next Steps
- None requested. Available if the user wants a merged/side-by-side version comparing
  the separable and non-separable propositions directly, or wants the non-separable
  model's predictions tied back into the empirical identification strategy.
