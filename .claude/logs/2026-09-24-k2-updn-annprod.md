# Session: 2026-09-24 — k2 joint-instrument (up/down) annual-production robustness

## Objective
Add annual-production versions of the joint upstream/downstream instrument tables (MR violations,
enforcement, visits) and link them as backup slides from the matching mine-count slides in
`job_talk_robustness.tex`. Plan: `~/.claude/plans/k2-updn-annual-production-robustness.md`
(renamed from auto-generated `dynamic-crunching-bumblebee.md` at user request, step 0).

## Changes Made
- Git: stashed msha-accident-build WIP (main.pdf, hook counters, untracked job_talk_robustness.pdf)
  as `stash@{0}` with `-u` (instead of moving the PDF to scratchpad: stash is durable, scratchpad is temp).
  Branched `k2-updn-annprod` off `k2-event-study-rf` (a604e6a).

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| Stash (not commit) the msha-accident-build WIP | Reversible; avoids committing a compiled PDF |
| Renderer copied from run_k2_updn_tables.r; only the F-note noun changed to "coal production" | The note text inside the renderer hardcodes "coal mines" |

## Verification Results
- [ ] Script runs end-to-end
- [ ] 6 outputs in output/reg/
- [ ] Anchor + stable-sample gates pass
- [ ] Slides compile

## Open Questions / Blockers
-

## Next Steps
-

## Run results (2026-09-24)
- Wrote code/coal_mining_water_quality/run_k2_updn_annprod_tables.r. It runs with exit 0; all 6 tables are in output/reg/, with no scientific notation.
- Anchor gate PASSED (19.39/18.58/15.02; 10,641 obs / 565 utilities). Stable-sample gate PASSED for MR, visit and enforcement.
- The downstream 2SLS coefficient is not significant at 10% in 0 of 17 columns.
- **WEAK INSTRUMENTS (stop point per plan):** the joint first-stage F is 11.25 upstream / 5.55 downstream with utility + year FE, and 5.89 / 5.48 with state x year FE. Only 94 of 574 utilities ever have downstream production > 0, and 92.8% of downstream production values are zero.
  Adding downstream production also drops the upstream 2SLS below significance with state x year FE (e.g. IOC 4.05 (10.03), vs 15.02 single-IV).
- Slides (Step 3) are NOT edited yet; waiting for the user's decision.

## User decision + slides (2026-09-24)
- User chose option 1: add backup slides with an honest low-power takeaway (F ~ 5.5 downstream).
- job_talk_robustness.tex: 3 new frames (updnmrannprod / updnenfannprod / updnvisitannprod) after updnbal; backuplinks added on updnmr, updnvisit, updnenf.
- Compiled (pdflatex+biber+2x pdflatex): exit 0, 77 pages, no undefined refs. The only overfull vboxes are at lines 212 and 393, in frames that were already there. Spot-checked pages 59, 61 and 63.
- Committed on branch k2-updn-annprod (not merged; the user should review the slides first).
- Reminder: msha-accident-build WIP is in the stash ("msha-accident-build WIP: ...").
