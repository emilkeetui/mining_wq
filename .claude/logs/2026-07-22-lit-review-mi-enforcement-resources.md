# Session: 2026-07-22 — Literature review update (Mi et al. enforcement resources strand)

## Objective
Update the project's literature review to fit the current draft (`writeup/Mining_and_Water_Quality (1)/main.tex`)
and incorporate Mi, Zhang & Liu (2026, JEEM) on technology, enforcement resource allocation,
and environmental performance.

## Changes Made
- `writeup/.../citation.bib`: appended 5 verified entries — `mi2026technology`,
  `greenstone2022technology`, `zou2021unwatched`, `yang2024achieving`, `browne2023man`.
  All metadata pulled from Crossref API (not from memory).
- `writeup/.../literature_review.tex`: NEW standalone document. Four-strand review:
  (1) coal mining environmental consequences, (2) strategic self-monitoring,
  (3) US drinking water / SDWA, (4) monitoring technology + enforcement resource allocation.
- `writeup/.../literature_review.pdf`: compiled output, 9 pages.
- `main.tex`: **not modified** (edits made mid-session were fully reverted at user request).

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| Mi et al. as a new 4th strand, not folded into existing strand 2 | Strand 2 is about entities hiding *own* emissions; Mi et al. is about regulator-side resource allocation. Distinct margin. |
| Framed contribution as "same margin, opposite direction" | In Mi/Greenstone, measurement shifts to regulator via deliberate tech adoption. Here it shifts via *failure* of self-reporting, no tech change. This is the paper's actual novelty against that strand. |
| Added Zou (2021) + Mu (2024) as "unwatched interval" analogue | MR violations = periods with no reading at all. Direct precedent for treating the *absence* of an observation as the manipulated object. |
| Did not assert specific Mi et al. findings/effect sizes | Abstract unavailable (paywalled, absent from Crossref/OpenAlex/S2). Characterized only at the level the title + 59-item reference list support. |
| Standalone doc kept preamble-complete | Compiles independently; header comment explains how to `\input{}` it into main.tex instead. |

## Corrections logged
- **Author order**: user gave "Mi, Shuying, Mengdi Liu, and Bing Zhang". Crossref shows
  **Mi; Zhang; Liu** (Zhang second, Liu third). BibTeX uses the Crossref order.
- Mid-session the user redirected: write to a separate document, do not edit `main.tex`.
  All `main.tex` edits reverted and verified (0 traces of new keys, "three strands" restored).

## Verification Results
- [x] `literature_review.tex` compiles: pdflatex -> biber -> pdflatex x2, exit clean
- [x] No "Citation undefined" / "LaTeX Error" / "Undefined control sequence" in log
- [x] All 5 new keys RESOLVED in `.bbl`
- [x] PDF exists, 106,433 bytes, 9 pages
- [x] `main.tex` restored — verified by grep (0 new keys, "three strands")
- [x] Crossref-verified metadata for Duflo 2013/2018, Zou 2021, Greenstone 2022

## Open Questions / Blockers
- Mi et al. (2026) abstract is paywalled and not in Crossref/OpenAlex/Semantic Scholar.
  The characterization is inferred from title + reference list (CEMS/China/enforcement).
  **Should be checked against the full text** once accessible via Cornell library, in case
  the empirical setting differs from the inferred one.
- Pre-existing (unrelated) bug found: `sum/npdwr_changes.tex` uses `\begin{tablenotes}`
  but `main.tex` does not load `threeparttable` — `main.tex` currently fails to compile.
  Not touched, since out of scope. Fix = add `\usepackage{threeparttable}` to preamble.

## Next Steps
- User decides whether to `\input{literature_review}` into main.tex or keep it separate.
- Fix the `threeparttable` preamble issue if a compiling main.tex is wanted.
