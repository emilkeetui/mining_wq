# Session: 2026-09-04 — flagging an unresolved gap in the Discussion's enforcement inference

## Objective

Answer whether the theoretical-model discussion from this chat is fully captured in
`main.tex`, and if not, persist what isn't before the session closes.

## Context

This continues the theory-section thread from `2026-09-03-theory-section-review.md`.
Between that log and this one, a separate session (not this chat) substantially revised
the model: fixed the Proposition 2 cutoff, removed the `N` normalization, and restored
the full Channel A/B derivation (commits `cbea29a`, `423e0b6`, `fa361a0`, `b2ffc59`,
`1a51fd8`). That work is fully captured in `main.tex` and in its own log — no risk there.

## Finding not yet written anywhere else

`main.tex` line 559 (current HEAD `1a51fd8`) argues:

> "the combined evidence that coal mining causes regulators to conduct more sanitary
> visits while issuing less enforcement suggests that utilities are not concealing
> contaminant exceedances."

This runs backward relative to the model's own cutoff. From the Setup (line ~235):

```
c <= chat(a) = t - (r - ps) q(a)
```

`p` enters only through the product `ps`. Lower `p` (fewer/weaker enforcement actions
following a visit) *lowers* `ps`, which *raises* the wedge `(r-ps)q(a)`, which *lowers*
`chat(a)` — fewer utilities clear the self-report threshold, i.e. **more** under-reporting
is optimal *for concealment reasons* precisely when enforcement is weak. So "visits up,
enforcement down" does not distinguish the cost channel from the concealment channel; if
anything the model says weak enforcement should amplify concealment-driven under-reporting,
the opposite of what the sentence claims.

This is the same soft spot the 09-03 log already flagged from a different angle: recorded
MCL rates are `q(a_SR)` for reporters and `p*q(a_MR)` for under-reporters, and the "MR up,
MCL flat => cost not concealment" inference needs `p*q(a_MR) < q(a_SR)`, which a grid
search found violated at 72 `(p, theta)` pairs. Two independent derivations now land on
the same unresolved gap: **the enforcement/visits evidence in the Discussion cannot
currently be used to rule out concealment**; only the SYR2 headroom argument (line 551,
`q(a) -> epsilon`) can.

## Status

Not fixed. Flagged for the next pass on the Discussion section, alongside the two prose
bugs already noted in the 09-03 log (line ~557's dangling sentence fragment moved; a
`\section{...}` jammed onto a paragraph end was fixed by the intervening session, still
worth a final check).

## Next Steps

- Decide whether to cut the "visits up, enforcement down => not concealing" claim from
  line 559, or restate it correctly (weak enforcement is uninformative about concealment,
  or actively suggestive of it, under the model).
- If keeping an enforcement-based argument, it needs the `p*q(a_MR) < q(a_SR)` condition
  stated and defended, not asserted.
