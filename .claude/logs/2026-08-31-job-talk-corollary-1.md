# Session: 2026-08-31 — Add Corollary 1 to job_talk.tex

## Objective
Make the job talk drive home that the headline mechanism is a **self-reporting cost**
plus **ineffective enforcement**, not concealment. Corollary 1 (already in `main.tex`)
is the piece that makes the two stories separable, so surface it in the deck.

## Changes Made
- `writeup/.../job_talk.tex`:
  - Split the old "three predictions" frame into two. New frame 12 ("Model: why the
    utility goes quiet") carries Prop 1, Prop 2 relabeled into **(A) cost** vs
    **(B) concealment**, and a new **Corollary 1** block. New frame 12b ("Model: the
    regulator has a lever, and it is not the limit") carries Prop 3 plus three bullets
    on why Channel A under-reporting is correctable and MCL tightening is not.
  - Frame 27 retitled "Reporting cost, not concealment: Corollary 1 in the data" — the
    50%-of-MCL nitrate monitoring step is presented as Corollary 1's constant-q
    condition met in the field (Channel B switched off).
  - MCL-null takeaway: added that a zero is also the wrong prediction for concealment.
  - Sanitary-visits takeaway: added that the price of silence never moves, the one
    lever Prop 3 identifies.
  - "What I find" and Conclusion bullets rewritten from "not only concealment" to
    "not concealment", tied to Corollary 1 and Prop 3.
  - New appendix slide (p. 42): formal statement + proof of Corollary 1 (Leibniz step),
    with a "why it matters" paragraph mapping it to the nitrate threshold test.

## Design Decisions
| Decision | Rationale |
|---|---|
| Split frame 12 rather than adding a 4th block | Four blocks + takeaway overflowed the frame; the split also matches the two-part story (firm mechanism, then regulator lever) |
| Corollary 1 stated inline on the slide, full proof in appendix | Keeps the main-body slide to the identifying logic; proof is available for Q&A |
| Dropped `\underbrace` from the slide's Corollary equation | Freed a line so the takeaway stopped clipping at the frame bottom |

## Verification Results
- [x] `latexmk -pdf` exits clean, 46 pages
- [x] 0 `Overfull \vbox`, 0 undefined citations/references in `job_talk.log`
- [x] Slides 12, 13, 27, 42 rendered to PNG and visually inspected — all fit

## Open Questions / Blockers
- None. `main.tex` was not touched; Corollary 1 there is unchanged.

## Next Steps
- If the deck gets retimed, frames 12/12b are now 2 slides where there was 1.
