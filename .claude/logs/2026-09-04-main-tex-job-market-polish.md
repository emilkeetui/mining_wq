# Session: 2026-09-04 — main.tex job-market polish

## Objective

Prepare `writeup/The_Effect_of_Contamination.../main.tex` for circulation with job
applications: error-free compile, grammar and clarity edits in the author's voice,
hyperlinked cross-references, broken-reference audit, removal of uncited exhibits,
theory-model math check, intro/conclusion updates, JEL codes + keywords +
acknowledgments block, and CWS → utility terminology (line 186 exempt).

Branch: `jmp-polish-main-tex`.

## Changes Made

- `main.tex` preamble: added `hyperref` (loaded last, `colorlinks`, dark navy
  `linknavy`), PDF metadata.
- `main.tex` title page: `\thanks` acknowledgments placeholder on the author,
  Keywords + JEL block under the abstract, abstract set `\singlespacing` so the
  block fits on page 1 (body spacing untouched — the second `\onehalfspacing`
  after `\newpage` still governs).
- `main.tex` intro: new model paragraph, new road-map paragraph (section
  `\label`s added so section numbers are not hardcoded), numeric alignment with
  the results (7–10 pp MR effect, 26/59 pp nitrate trigger, −5.7 pp formal
  enforcement, +3.7 pp enforcement visits), 1997 → 1998 SYR2 window, `\parencite`
  → `\textcite` at sentence starts, several rewritten literature sentences.
- `main.tex` conclusion: added the MR/MCL magnitudes, the nitrate cost-channel
  evidence, and the visits-vs-formal-enforcement magnitudes. Voice preserved.
- `main.tex` theory: corrected the max/min interchange in Proposition 2 (see
  Design Decisions), clarified that $G$'s *support* is what is fixed in $m$.
- `main.tex` throughout: hyphenation normalised (`self-report*`, `under-report*`,
  `self-monitoring`, `non-compliance`); duplicated sentence in the background
  section removed; ~40 grammar/clarity fixes.
- `main.tex`: `\text{num_mines}` → `\text{NumMines}` (8×) to match the equation
  notation.
- Exhibits: commented out `mr_concentration_lag_national_downstream_states`,
  the violation-length histogram, and the mine-HUC12 data-cleaning map (no body
  citation). Restored `\outsum{mr_mcl_incidence_summary}` — it *is* cited, and
  was the only undefined reference in the document.
- Generated exhibits + their R sources (`run_main_tables.r`,
  `mr_concentration_lag_ols.r`, `mr_mcl_incidence_summary.r`): CWS/community
  water system → utility in reader-facing captions and notes for the tables
  main.tex inputs; repaired "utilities fixed effects" / "the utilities level"
  grammar left by an earlier blanket rename.

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| Fixed the Prop 2 max/min interchange rather than only flagging it | `max_a min{A,B}` = `min{max_a A, max_a B}` is false in general, and the "smaller of two per-branch maxima" selected the wrong branch. The inner `min` enters with a minus sign, so it is a `max` over branches, and two maxima commute. The propositions' *statements* and `c*(θ)` were already correct — only this exposition step was wrong. |
| Left every numeric/logical inconsistency unedited | User asked for contradictions to be flagged, not changed. Six are listed in the hand-off. |
| Edited the generated `.tex` **and** the R source strings | Editing only the `.tex` would regress on the next pipeline run; editing only the R would leave the current PDF inconsistent. |
| Scoped the CWS rename to exhibits main.tex actually inputs | A repo-wide rename touches many tables not in the paper and risks the `cws_data` paths. Remaining CWS wording in the pipeline is noted as follow-up. |
| Abstract set to `\singlespacing` | Only way to get Keywords/JEL onto the title page without a near-empty page 2. Affects the abstract only. |
| Section `\label`s for the road map | Hardcoded "Section 7" breaks silently if a section is added. |

## Verification Results

- [x] `latexmk -pdf` exits 0, 63 pages, **0 LaTeX errors, 0 LaTeX warnings**
- [x] Zero undefined references (was 1: `tab:mr_mcl_incidence_summary`)
- [x] Zero `??` in the rendered PDF text
- [x] 158 link annotations in the PDF — cross-references and citations are live
- [x] Every active `\outsum`/`\outreg`/figure is cited in the body; every body
      `\ref` resolves (audit script `scratchpad/audit.py`)
- [x] Only line 228 (was 186) retains "community water systems"
- [x] All empirical numbers in the prose re-checked against `output/reg/` and
      `output/sum/` (six mismatches found and flagged, not changed)
- [x] Propositions 1–3 re-derived by hand; all three correct as stated

## Open Questions / Blockers

Flagged for the author, not changed:
1. Discussion "visits up, enforcement down ⇒ not concealing" runs backwards in
   the model — lower `p` widens the wedge `(r−ps)q(a)` and *raises* concealment.
   Third independent derivation of this gap; see
   [[2026-09-04-discussion-enforcement-inference-gap]].
2. Discussion uses `ĉ(a)` where the model's operative cutoff is `c*(θ)`.
3. Model treats `(r,s,t,p)` as fixed in `m`, but the paper's finding is that
   enforcement *responds* to mining.
4. `q(a) → ε` in the Discussion is a level claim; needs the convexity sentence
   (small level, steep slope) that the old κ framing carried.
5. Arsenic effect described as "almost/approximately 100 percent" of the mean;
   0.0023/0.0029 = 79 percent.
6. "50 percent, 69 percent, and 24 percent, respectively" — three numbers, two
   contaminants; 50 matches nothing in the table.
7. Nitrate "5 percent increase" — 0.0572/0.752 = 7.6 percent.
8. "zero to 100 million short tons would push nitrate past 50 percent of the
   MCL" — the linear extrapolation needs ~743 million short tons.
9. "A utility would not exceed the MCL for arsenic ..." is true only of the
   pre-2006 0.050 mg/L MCL; the sample max of 0.0110 already exceeds the
   post-2006 0.010 mg/L MCL, as the paper itself notes earlier.

## Next Steps

- Author decides on items 1–9 above.
- Fill in the `\thanks` placeholders before circulating.
- Optional: finish the CWS → utility rename across the rest of the pipeline's
  table notes (`run_main_tables.r` and the `cws_6year_review_*.r` scripts still
  carry it for exhibits not currently in the paper).

## Follow-up: 2026-09-04 — numeric reconciliation (findings 5-9)

User asked to fix the five numeric mismatches flagged above rather than leave them
open. Applied, verified against `output/reg/6yr_huc02fe_inorg_ravalli_2005.tex` and
`output/sum/6yr_huc02fe_inorg_val_sumstats_ravalli_2005.tex`:

- Arsenic effect: "almost/approximately 100 percent" of the mean -> **79 percent**
  (0.0023/0.0029), both occurrences (intro paragraph, results paragraph).
- Barium effect: "24 percent" -> **23 percent** (0.0171/0.0748 = 22.9%), both
  occurrences.
- Trailing list "50 percent, 69 percent, and 24 percent" (three numbers for two
  contaminants, selenium+barium) -> **"69 percent and 23 percent"**, dropping the
  stray unattributable 50 percent.
- Nitrate effect: "5 percent increase" -> **7.6 percent** (0.0572/0.7520).
- Linear extrapolation to 50% of the nitrate MCL: "zero to 100 million short tons"
  -> **~743 million cumulative short tons** from the sample mean (0.752 mg/L to
  5.0 mg/L at 0.0572 mg/L per 10M ST), which is what the arithmetic actually gives.
- "A utility would not exceed the MCL for arsenic..." -> narrowed to barium,
  nitrates, selenium; arsenic carved out as an exception, since the sample max of
  0.0110 mg/L is below the pre-2006 MCL (0.050) but above the current one (0.010) —
  which the paper's own results section already states elsewhere.

Verification: `latexmk -pdf` exits 0, 63 pages, 0 errors, 0 warnings, 0 `??`;
`pdftotext` spot-check confirms all six rendered substitutions read correctly.
