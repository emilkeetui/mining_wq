# Session: 2026-08-31 — job_talk.tex (beamer version of main.tex)

## Objective
Build `job_talk.tex`, a 25–30 slide beamer job talk from `main.tex`, styled after
`narea_presentation.tex`, using the `*_present.tex` tables for every table, and
following `lit/applied_micro_slides.pdf` (Shapiro), `lit/aea_how_to_present.pdf`
(CSWEP), and `lit/Effective_Economics_Presentations.pdf`.

## Changes Made
- `writeup/The_Effect_.../job_talk.tex` (new): 30-slide main deck + 9 appendix slides
  + references. Sections: Setting and data / Does coal mining contaminate utility
  water? / Do utilities keep self-reporting? / How do regulators respond?

## Design Decisions
| Decision | Rationale |
|---|---|
| Takeaway-style frame titles ("Mining makes utilities stop reporting") | Shapiro: always be telling the story; the title carries the claim |
| Results previewed on slide 6, before any method | AEA rule 1 and Shapiro "Preview of Findings" — assume the audience is about to leave |
| Table captions swallowed, frame title carries them | Avoids duplicating the caption text on a slide |
| Chemical placebos absent | Deprecated per CLAUDE.md; geographic (strictly-downstream) cut used instead |
| Enforcement/visit summary, SYR2 selection, sumstats, instrument balance → appendix | Keeps the main deck at 30 slides; each is referenced in the main narrative |
| `mr_concentration_lag` (downstream) used on the mechanism slide, not the national version | Matches the magnitude quoted in the main.tex introduction (26 pp) |

## Beamer/table plumbing (the non-obvious part)
The `*_present.tex` files are article floats (`\begin{table}[htbp]` + `\caption`),
which beamer has no float mechanism for, and which cannot be wrapped in
`adjustbox` (raises `! LaTeX Error: Not in outer par mode.`). Solution in the
preamble:
1. `\renewenvironment{table}[1][]{\par\centering}{\par}` neutralises the float and
   eats the `[htbp]`.
2. `\renewcommand{\caption}[2][]{}` swallows the caption.
3. `\slidetableinput` boxes the body in `varwidth{17cm}` (so multi-panel files
   still line-break *between* panels instead of setting them side by side — the
   generated files rely on a fixed-width minipage to force that break), then
   `\adjustbox{max width=\textwidth, max totalheight=0.80\textheight, center}`.
4. Optional first argument overrides the width key, for source files that hardcode
   a narrow box (`fs_dwnstrm_minevio_ivsum` uses `width = 0.45\textwidth` and needs
   scaling **up**; `max width` only ever shrinks).

Two other fixes worth remembering:
- `\takeaway{}` wraps the one-line comment under each table as
  `{\footnotesize #1\par}` — the size group must close **after** `\par` or the
  paragraph's first line inherits the outer font's `\baselineskip`.
- `epaarsenicbat` and `epaviolationreliability` have no author field, so
  `\cite` under authoryear printed the entire report title mid-sentence. Replaced
  with literal "(US EPA, 2011)" / "(US EPA, 2000)" on the slides.

## Verification Results
- [x] `latexmk -pdf` exits 0
- [x] `job_talk.pdf` written, 44 pages (30 main + appendix divider + 9 appendix + 3 refs)
- [x] 0 undefined citations, 0 undefined references
- [x] 0 overfull vboxes (nothing runs off the bottom of a slide); 1 overfull hbox
- [x] Every table slide rendered and visually inspected: panels stack correctly,
      scaled to fit, notes legible

## Open Questions / Blockers
- `main.tex` §"robustness test of contamination and MR and MCL violations" (line 542)
  quotes 0.5 pp / 0.2 pp, which are the coefficients from
  `mr_concentration_lag_national_downstream_states`, while the introduction (line 145)
  quotes 26 pp, from `mr_concentration_lag`. The two tables are different samples.
  The slide uses the downstream table (26 pp / 59 pp) to match the introduction.
  The paper body should be reconciled.

## Next Steps
- Decide the talk length and cut/promote appendix slides accordingly.
- Consider a figure-based version of the MR result (coefficient plot) — Shapiro
  prefers figures to tables for the headline result.
