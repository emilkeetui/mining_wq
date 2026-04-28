# Publication Readiness Assessment
*Date: 2026-04-28*

## State of the evidence

### What holds up

**Coal mining increases MR violations in the main sample.** This result appears
significant and survives the IV strategy. It is a real finding — mines cause
monitoring and reporting failures at downstream CWSs.

### What does not hold up

**The strategic substitution story is not supported by the data.**

Strategic substitution requires a clean antisymmetry: mines↑ → MR↑ *and*
mines↑ → MCL↓, both significant. What you have is:

| Contaminant | MR 2SLS | MCL 2SLS | Antisymmetric? |
|---|---|---|---|
| Nitrates | positive, sig | negative, NS | Partial at best |
| Arsenic | positive, sig | positive, NS | No — same direction |
| Inorganic chemicals | positive, sig | negative, NS | Partial at best |
| Radionuclides | NS | negative, sig | Reversed — MCL moves, MR doesn't |

Arsenic alone breaks the story: if CWSs were strategically suppressing MCL
detections via MR violations, arsenic MCL should be negative when MR is positive.
It isn't. The antisymmetry needed to claim substitution is absent for one of four
contaminants and insignificant for the other three.

**MCL violations are not significantly affected by mining.** The no-radionuclides
composite is also insignificant. Without significant MCL results, there is no
evidence of actual health harm from mining, and no statistical basis for claiming
suppression of MCL detections.

**The radionuclides MCL result is a confound, not a finding.** Its positive RF
appears identically in the main colocated sample and the downstream sample. It is
the only significant MCL result and it breaks the substitution pattern. It cannot
anchor any causal claim.

**MR violations are a weak outcome for a health-focused paper.** MR measures
monitoring failures — a CWS that does not test its water has zero recorded
violations, which is observationally indistinguishable from a CWS with clean
water that tests regularly. The MR result is consistent with mines creating
administrative burden that leads to missed sampling deadlines, not with strategic
contamination suppression.

---

## Publication readiness

**Not ready for a top field journal in current form.** The core problems are:

1. **No welfare story.** MCL violations — the measure of actual contamination
   reaching consumers — are insignificant. A paper about coal mining and drinking
   water quality that cannot show effects on water quality standards (MCL) has a
   missing welfare link.

2. **The mechanism is underpowered.** Strategic substitution is the novel
   contribution, but it requires both MR and MCL to move in opposite directions.
   Only half of the prediction is in the data.

3. **The downstream sample adds noise, not signal.** The 4-step analysis was
   designed to expand power, but the radionuclides confound contaminates the main
   robustness check and the MCL results there are also insignificant.

4. **The instrument is weak in the main colocated sample.** F = 7.95 with
   colocated sulfur, F = 3.1 with unified sulfur. These are below conventional
   thresholds. The downstream sample has stronger first-stage F but the exclusion
   restriction is harder to defend at 3–4 HUC steps.

---

## Honest paths forward

Three directions that could make this publishable, in order of difficulty:

**Option 1 — Reframe around regulatory failure, not health harm.**
Drop the health story. The finding is: coal mines cause CWSs to miss monitoring
requirements. This is a regulatory capacity / regulatory capture result in the
tradition of Blundell et al. and others on environmental enforcement. It is a
narrower but defensible claim. Requires rewriting the framing and dropping the
strategic substitution mechanism.

**Option 2 — Find a better-powered sample for MCL.**
The colocated sample (N≈12,000) with a weak first stage is underpowered to detect
small MCL effects. If there is a larger or longer panel, or a sharper instrument
(e.g., using mine opening/closing events rather than ARP), MCL results might become
detectable. The current design does not have enough statistical power to find the
effect even if it exists.

**Option 3 — Refocus on total violations (MR + MCL combined) in a lower-ranked outlet.**
The combined violation share (any violation type) may be significant and is a
legitimate outcome. A regional or environmental economics journal might accept a
result showing mines increase total SDWA violations without requiring the strategic
substitution mechanism. This is a lower bar but achievable with current data.

---

## Bottom line

The paper has a real finding — mines increase MR violations — but it cannot support
the causal health claim or the strategic substitution mechanism that would make it a
top-journal contribution. The honest summary: the instrument works for MR but the
MCL effects are too small to detect, and without MCL significance the welfare and
mechanism claims are unsubstantiated.
