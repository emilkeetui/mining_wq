# Session: 2026-09-08 — Advisor intro restructure (bus-reading copy)

## Objective
Produce a standalone `.tex` + `.pdf` version of `main.tex` that implements a reviewer's
comments on the JMP introduction, formatted for offline reading and side-by-side
comparison against the current `main.pdf`.

## Reviewer's comments (verbatim substance)
Follow the Keith Head "formula" ordering:
- **Hook / ¶1** — 9–34m Americans stat; environmental regulation leans on honest
  self-reporting; use the paragraph for the social-planner tension (contamination and
  monitoring costs rise together → perverse incentive to under-report). Don't give away
  the finding.
- **Question / ¶2** — state the research question; introduce the setting.
- **Antecedents / ¶3–4** — condense current ¶4–7; name the gap (prior work assumes
  under-reporting is pure concealment; this paper shows the *cost of reporting* drives it).
- **Value added / ¶5** — current ¶8 verbatim, "no edits, it is strong."
- **Roadmap** — cut current ¶9–17 (methods + results walk-through), go straight to roadmap.

## Changes Made
- `writeup/.../main_advisor_revision.tex` (new): full paper, restructured intro,
  per-paragraph annotation tags, editorial front matter + crosswalk appendix.
- `writeup/.../main_advisor_revision.pdf` (new): compiled, 69 pages.
- `main.tex` **untouched**.

## Design Decisions
| Decision | Rationale |
|---|---|
| Separate file, not an edit to `main.tex` | User wants to compare against current PDF |
| Annotate each new ¶ with a rust-coloured tag | Lets him read the prose clean or trace provenance |
| Keep the full body, not just the intro | He asked for a "version of main.tex"; enables page-by-page diff |
| Editorial appendix placed right after §1 | Everything reviewable sits in the first ~8 pages |
| Current ¶9 and ¶10 relocated into body, not deleted | Their content appears nowhere else in the paper (verified by grep) |
| Current ¶11–17 deleted outright | Verified body §3–§7 already state all of it, incl. the 26/59pp nitrate result and the 14/5.7/3.7pp enforcement results |
| Current ¶3 folded into new ¶1 | It was making the social-planner tension one paragraph late — exactly what the reviewer asked ¶1 to do |
| ¶8 reproduced verbatim | Reviewer explicitly said no edits |
| Abstract left untouched | Not in scope of the comments; flagged as a judgement call in the appendix |

## Verification Results
- [x] Paragraph numbering confirmed against `main.tex` L186–L220 (¶1–¶18 map exactly to
      the reviewer's numbering)
- [x] Body coverage of removed ¶11–17 confirmed by grep before deleting
- [x] Compiles via `latexmk -pdf`, no errors
- [x] PDF exists, 69 pages

## Gotchas hit
- Bash tool cwd persisted into `writeup/`, which broke the `protect-raw-data.py`
  PreToolUse hook (it resolves relative to cwd) and hard-blocked every Bash call.
  Recovered with `Set-Location` via the PowerShell tool. **Never leave the Bash cwd
  outside the project root.**
- `awk` with `NR==FNR{next}` guarded by an empty `/dev/null` first file truncated the
  output file — empty first file means `NR==FNR` stays true for the whole second file.
- Heredoc with LaTeX double-backtick quotes (` ``SDWA'' `) failed to parse in the Bash
  tool; used the Write tool for large LaTeX blobs instead.

## Open Questions
- How aggressively to withhold results: nothing quantitative now appears until ¶5.
  A softer reading would put one results sentence at the end of ¶2.
- Abstract still front-loads every headline number, so an abstract-first reader never
  experiences ¶1–¶4 as a puzzle.
- Condensing ¶4–7 halved the space given to the drinking-water and coal-mining
  literatures — the ones an applied committee member looks for.

## Next Steps
- User reviews on the bus; decide whether to fold the new intro back into `main.tex`.
- Reviewer noted none of this is needed for Cornerstone — it is journal-submission framing.
