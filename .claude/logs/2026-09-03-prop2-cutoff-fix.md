# Session: 2026-09-03 — Theoretical model audit and Proposition 2 cutoff fix

## Objective
Audit the theoretical model in `main.tex` §Theoretical model for errors, then implement
"fix (b)": correct the under-reporting cutoff in Proposition 2 while preserving the
Channel A / Channel B decomposition the empirics rely on.

## The error found
The utility's objective is not globally concave. The `min` in eq. (2) puts a kink where
ĉ(a) = c, and because r > ps the marginal penalty *drops* there, so U′ jumps up. Two
local maxima survive, a_SR(θ) < a_MR(θ), and both are self-consistent for
c ∈ (ĉ(a_MR), ĉ(a_SR)). The old eq. (5) defined the cutoff as c*(θ) = ĉ(a_SR(θ)) — the
*top* of that interval, not the switching point. MR(m) therefore understated
under-reporting.

Verified numerically (b=√a, q=κa, r=1, s=1.5, p=0.5, t=0.4, κ=0.5, ā=2):

| θ | ĉ(a_MR) | old c*(θ) = ĉ(a_SR) | true cutoff |
|---|---------|---------------------|-------------|
| 0.6 | 0.3200 | 0.3550 | 0.3400 |
| 0.9 | 0.2200 | 0.2988 | 0.2650 |
| 1.2 | 0.1500 | 0.2200 | 0.1729 |

At c = 0.999·c*(θ) the global argmax is a_MR — i.e. the utility under-reports while the
old eq. (5) counted it as a self-reporter.

## The fix
Correct cutoff, via W(ρ;θ) ≡ max_a {θb(a) − Nρq(a)} and the envelope theorem
∂W/∂ρ = −N q(a(ρ;θ)):

    c*(θ) = t + [W(r;θ) − W(ps;θ)]/N = t − ∫[ps→r] q(a(ρ;θ)) dρ

Existence/uniqueness needs no selection assumption: the self-report payoff is linear
decreasing in c at rate N, the under-report payoff does not contain c, so the difference
crosses zero exactly once.

Closed form verified against brute-force maximization: exact to 6 decimals at every θ
(0.340000, 0.265000, 0.172944, 0.150000).

## Changes Made
- `writeup/.../main.tex` §Setup: moved `r > ps` and `t ≥ (r−ps)q(ā)` up from Prop 3 into
  the Setup as maintained assumptions; `r > ps` was previously *used* at eq. (1) but only
  stated 14 lines later (its earlier statement was commented out).
- §Optimal negligence: "Assuming r > ps" → "Because r > ps".
- Proposition 1: removed the "globally increasing … within each region" contradiction;
  removed the false claim that the SOC is *assumed* (it follows from b″<0, q″≥0);
  added the upward jump at the region switch.
- Proposition 2: replaced eq. (5) with the integral cutoff above plus the
  non-concavity / unique-crossing paragraph. Replaced the c*′(θ) derivation with the
  envelope argument c*′(θ) = [b(a_SR) − b(a_MR)]/N < 0.
- Proposition 3: dropped the false C*(λ) = λ·ĉ(a_λ) proportionality; replaced with
  C*(λ) = λt − ∫[λps→λr] q(a(u;θ))du and the one-line bound
  dC*/dλ = t − [r·q(a(λr)) − ps·q(a(λps))] ≥ t − (r−ps)q(ā) ≥ 0.
  Verified numerically: closed form = brute force, derivative formula = numeric
  derivative, bound holds at λ ∈ {0.8, 1.0, 1.4}.
  "enforcement scale/intensity" → "penalty scale" (λ scales (r,s,t); p is held fixed).

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| Fix (b) over fix (a) (choosing a before drawing c) | (a) removes the kink but makes the marginal sanction ρ̄(a;m) depend on m, which breaks the clean Channel A/B split, requires a new bounded-density-of-g assumption for the SOC, and forces a rewrite of Prop 3. (b) touches one equation and one derivative. |
| Keep eq. (9) ĉ_λ(a) = λĉ(a) | Still a true statement about the per-event reporting *rule*; only the equilibrium cutoff C*(λ) fails to scale proportionally. Relabelled "per-event reporting rule". |
| Reuse existing t ≥ (r−ps)q(ā) | It is exactly what signs c*(θ) ≥ 0 *and* dC*/dλ ≥ 0 under the corrected cutoff. No new assumption needed. |

## Verification Results
- [x] `latexmk -pdf main.tex` exits 0
- [x] All theory-section labels resolve in `main.aux` (eq:chat, eq:cstar, eq:MRm,
      eq:split, eq:channelB, eq:chat_lambda)
- [x] 3 undefined references remain (`2ndstage2slsreg`,
      `tab:mr_mcl_incidence_summary`, `tab:sanitary_visit_timing_formal_enforcement_rate`)
      — confirmed pre-existing: those labels are defined nowhere in `main.tex`, before or
      after the edit
- [x] No "Step 2"/"Step 4" dangling references remain
- [x] Downstream of the change (h, eqs. 6–8, Channel A, Channel B, integration by parts,
      Prop 2's conclusion) is unchanged, as intended — c*(θ) is still m-independent and
      still strictly decreasing in θ

## Open Questions / Blockers
Deliberately left out of scope (flagged in the audit, not fixed):
- The integration-by-parts derivation for eq. (8) and the Channel A interpretation are
  still inside commented-out blocks, so Prop 2's proof has visible gaps as compiled.
- `e(a)` is called "the expected penalty" but contains c, a technology cost; it is also a
  function of c and should be `e(a;c)`.
- The narrative motivating ∂G/∂m ≤ 0 ("regulators require utilities to increase
  sampling") is about N, which is held fixed and m-independent. If N = N(m), there is an
  offsetting channel: N↑ ⇒ a↓ ⇒ q(a)↓ ⇒ ĉ↑ ⇒ *more* self-reporting.
- `MR(m)` is called a "number" but eq. (6) is a share.
- **Corollary 1 is absent from `main.tex`** (added in `0123cdb`, removed in `69be972`)
  but the Discussion's central claim — cost avoidance, not concealment — *is* the
  Corollary 1 argument. `job_talk.tex:504` still carries the older knife-edge
  type-invariance version that `0123cdb` replaced. Paper and deck are out of sync.
- `main.tex` Discussion has an unfinished sentence: "then this provides evidence of ."

## Next Steps
- Decide whether to restore the small-κ Corollary 1 to `main.tex` or rewrite the
  Discussion so it does not depend on an unstated result; sync `job_talk.tex` either way.

## Addendum (2026-09-04): why single-crossing holds, and why it matters

Follow-up question after the fix: does the paper prove the self-report/under-report
payoff difference crosses zero exactly once (rather than checking it numerically), and
what does single-crossing actually buy the argument. Folded the proof into `main.tex`
(the `\max_a \min\{\cdot,\cdot\} = \min\{\max_a(\cdot), \max_a(\cdot)\}` step, ~line 267);
this addendum keeps the economic interpretation, which does not belong in the paper body
but would otherwise only live in chat history.

**The proof (non-numerical).** Rewrite the utility's problem as a maximization by pulling
the $\min$ over branches outside the $\max$ over $a$:
$\max_a \min\{c+rq(a),\,t+ps\,q(a)\} = \min\{\max_a[\theta b(a)-c-rq(a)],\ \max_a[\theta
b(a)-t-ps\,q(a)]\}$, valid because neither branch's maximizer depends on the other
branch's value. Each per-branch objective is strictly concave ($b''<0$, $q''\ge 0$), so
each has a unique maximizer $a(\rho;\theta)$, $\rho \in \{r,ps\}$ — this is what rules out
every negligence level besides $a_{SR}(\theta)$ and $a_{MR}(\theta)$ as ever being
optimal, for any $c$ (the gap in the pre-addendum text: it asserted these two "can
satisfy the FOC" without showing no third candidate exists). Writing
$W(\rho;\theta)=\max_a\{\theta b(a)-\rho q(a)\}$, the self-report payoff is
$W(r;\theta)-\theta b(\bar a)-c$ and the under-report payoff is $W(ps;\theta)-\theta
b(\bar a)-t$. Their difference $\Delta(c) = N[c^*(\theta)-c]$ is affine in $c$ with
nonzero slope, so it has exactly one root — no distributional assumption on $c$ needed,
just that $c$ enters the self-report payoff linearly and does not enter the under-report
payoff at all (a utility that skips testing never pays the testing cost, and neither
branch's negligence choice depends on $c$).

**What "crosses zero once" means.** The reporting decision is a threshold rule in $c$:
one cutoff $c^*(\theta)$ splits the cost distribution, everyone below self-reports,
everyone above under-reports, nobody switches back. If $\Delta$ crossed more than once,
the under-reporting set would be a union of disjoint intervals rather than an upper set,
and three things break:
- Eq. (6)'s $h(\theta,m) = 1-G(c^*(\theta);m)$ representation requires exactly one
  boundary; a union of intervals needs $\sum_k[G(b_k)-G(a_k)]$ and no single $c^*(\theta)$
  to differentiate.
- Channel A's sign, $\partial h/\partial m = -\partial G/\partial m \ge 0$, uses only FOSD
  ($\partial G/\partial m \le 0$) across *one* boundary. FOSD says nothing about how mass
  redistributes across a union of intervals moving in different directions.
- Channel B's sign, $h'(\theta) = -g(c^*)c^{*\prime}(\theta)$, presumes one boundary
  moving one way as $\theta$ rises.

So single-crossing is what lets Channel A and Channel B be signed using only the
maintained FOSD assumption on $G$ and $F$ — without it the model would need to know the
shape of $g$, not just its direction of shift. It is also what removes any need for an
ad hoc selection rule when the utility is indifferent: with a unique crossing there is at
most one $c$ where that occurs, a measure-zero event.
