# Session: 2026-08-28 — Point main.tex exhibits at output/ directly

## Objective
Stop maintaining duplicate copies of tables/figures inside the writeup folder.
`main.tex` should `\input`/`\includegraphics` pipeline products straight from
`output/`, so re-running the pipeline updates the paper with no file copying.

## Changes Made
- `writeup/The_Effect_of_Contamination_on_Contamination_Limit_Regulation__US_Coal_Mining_and_Drinking_Water_Utilities/main.tex`:
  - Added a preamble block defining `\outputdir` (`../../output`) plus
    `\outsum{}`, `\outreg{}`, `\outfig[width]{}` wrappers, with usage comments.
  - Re-pointed 36 of 41 exhibit references (22 active, 14 commented-out) to
    `output/sum/`, `output/reg/`, `output/fig/` via those macros.
  - Left 5 references on their local copies, each annotated inline with why.

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| Compare files after normalizing CRLF→LF and trailing whitespace | Overleaf writes LF, the pipeline writes CRLF; a raw hash said 31/31 tex files "differ" when only 3 actually did |
| Macro wrappers rather than literal `../../output/...` paths | One place to change if the writeup folder moves; makes "path from output/" the obvious default for new exhibits |
| No `\graphicspath` | Explicit `\outfig` keeps resolution unambiguous and avoids a macro inside `\graphicspath` |
| Rewrite commented-out `\input`s too | They pull from `output/` when uncommented later |
| Left 5 refs local | Only rewrite when the two files are byte-identical, per the request |

## Files intentionally NOT re-pointed
| Ref | Reason |
|---|---|
| `reg/2sls_dwnstrm_minevio_allcat` (commented) | Local copy has hand-edited caption ("IOC violations" vs "mining violations") and "CWS fixed effects" vs "PWSID fixed effects" row label; pipeline version is stale |
| `reg/2sls_dwnstrm_minevio_mcl` (commented) | Same two hand edits |
| `reg/6yr_huc02fe_inorg_ravalli_2005` (active) | Notes text differs — local says columns show mean concentration *and* share of samples exceeding the MCL; `output/` version mentions only mean concentration |
| `plots/coal_summary_plot.png` (active) | Binary differs; local copy is newer (2026-08-28) than `output/fig/` (2026-04-21) |
| `plots/data_cleaning/eia_msha_mine_huc12s.png` (active) | No counterpart anywhere in `output/` |
| `img/WBD_Base_HUStructure_small.png` (active) | Not a pipeline product (USGS schematic) — correctly stays in `img/` |

## Verification Results
- [x] `pdflatex` on the edited `main.tex` — exit 0, no `!` errors, 59-page PDF
- [x] Control compile of the pre-edit backup — exit 0, no errors, 59 pages (identical)
- [x] Log confirms all 22 active exhibits read from `../../output/{sum,reg,fig}/`
- [x] No new "file not found" entries (only the pre-existing missing `main.bbl`)

## Open Questions / Blockers
- **Pre-existing, unrelated:** `\citet` is undefined in this document — `biblatex`
  is loaded without `natbib=true`, so a plain `pdflatex` run dies at the
  `\citet{montielolea2013robust}` on the Montiel Olea–Pflueger F-statistic line.
  Both compiles above stubbed `\citet` to get past it. Fix is one option in the
  `\usepackage[...]{biblatex}` call, but it was out of scope here.
- The 5 local-copy exceptions above each need a pipeline re-run (or a decision on
  which version is authoritative) before they can be re-pointed.
- Relative `../../output` assumes the *whole repo* is what gets synced to
  Overleaf. If only the paper subfolder is synced, these paths break there.

## Next Steps
- Regenerate the 4 stale/divergent exhibits from the pipeline, then swap their
  `\input`/`\includegraphics` to `\outreg`/`\outfig` and delete the inline notes.
- Optionally delete the now-unused `reg/`, `sum/`, `plots/` copies in the writeup
  folder once every exhibit is re-pointed.

---

## Follow-up: fixed the `\citet` compile failure

`\citet` is a natbib command; this document loads `biblatex` (authoryear) without
`natbib=true`, so `\citet` was never defined and `pdflatex` died on it.

**Fix chosen:** converted the 2 `\citet` uses to `\textcite` rather than loading
the natbib compatibility layer. The document is already biblatex-native
everywhere else -- `\parencite` x41, `\textcite` x12 -- so 2 stray natbib calls
did not justify a package option. Both uses are author-prominent ("F-statistic
of ...", "proposed by ..."), which is exactly what `\textcite` renders.

- main.tex:393 `\citet{montielolea2013robust}`      -> `\textcite{...}`
- main.tex:396 `\citet{staigerstock1997instrumental}` -> `\textcite{...}`

### Verification
- [x] Full `pdflatex` -> `biber` -> `pdflatex` x2 chain, no `\citet` stub
- [x] Exit 0 on every pass, zero `!` TeX errors, 64-page PDF
- [x] Rendered text confirms "Montiel Olea and Pflueger (2013)" and
      "Staiger and Stock (1997)"; both resolve in the bibliography

### Remaining bibliography warnings (separate defects, NOT fixed -- need a decision)
1. **`\textcite{mu2024s}` at main.tex:149 has no entry in citation.bib.** It
   renders as a bold literal "mu2024s" in the PDF. Context is strategic shutdowns
   of pollution monitors (alongside `zou2021unwatched`). Almost certainly
   Mu/Rubin/Zou on strategic pollution-monitor shutdowns, but the entry was not
   invented here -- needs the real reference confirmed before adding.
2. **`li2024effect` is defined twice in citation.bib** (lines 344 and 507),
   byte-identical entries. Biber skips the second and warns. Safe to delete
   one, left alone as out of scope.
3. `christensen2023flint` has `month={February}` as a string, not an integer --
   biber warns it may not sort correctly. Cosmetic.
---

## Follow-up 2: bibliography fixes

All three items from the previous section addressed in `citation.bib`.

| # | Fix |
|---|-----|
| 1 | Added the `mu2024s` entry supplied by the user (Mu, Rubin & Zou, RESTAT), placed next to `zou2021unwatched`, which it is cited alongside. Trimmed the Google-Scholar `publisher` artifact ("MIT Press 255 Main Street, 9th Floor, ... USA~...") down to "MIT Press". |
| 2 | Deleted the second, byte-identical `li2024effect` entry (kept the first). |
| 3 | Converted month-name strings to integers: `christensen2023flint` and `sanders2022` `{February}` -> `{2}`, `Andarge2025lead` `{September}` -> `{9}`. Only the first was cited and warning, but all three are the same defect. |

### Verification
- [x] Full `pdflatex` -> `biber` -> `pdflatex` x2, exit 0 on every pass
- [x] **Zero biber warnings** (was 3), zero `!` TeX errors, zero undefined citations
- [x] 64-page PDF; `mu2024s` renders in text and in the reference list

### NEW issue found by the clean build -- needs a decision
`mu2024s` and the pre-existing `10.1162/rest_a_01477` are **the same paper**. The
bib already carried the published version (RESTAT 108(3), pp. 597-612, 2026, doi
10.1162/rest_a_01477); `mu2024s` is the 2024 working-paper version. The paper now
cites it under both keys and it appears twice in the reference list:

- main.tex:137 `\parencite{zou2021unwatched, 10.1162/rest_a_01477}`  -> renders "(... Mu, Rubin, and Zou 2026)"
- main.tex:145 `\parencite{wallsten2008effects, foster2019arsenic, zou2021unwatched, 10.1162/rest_a_01477}` -> "2026"
- main.tex:149 `\textcite{mu2024s}` -> renders "Mu, Rubin, and Zou (2024)"
- main.tex:157 `\textcite{mu2024s}` -> "2024"

**Recommendation:** point both `\textcite{mu2024s}` at `10.1162/rest_a_01477` and
delete the `mu2024s` entry, so the paper is cited once, as the published version.
Not done -- the user explicitly supplied `mu2024s`, so the choice of which key
survives is theirs.
---

## Follow-up 3: consolidated the duplicate Mu reference

Resolved the duplicate flagged above. The paper is now cited under one key only,
as the published version.

- main.tex:149 and :157 -- `\textcite{mu2024s}` -> `\textcite{10.1162/rest_a_01477}`
- citation.bib -- `mu2024s` entry deleted (the pre-existing published entry,
  RESTAT 108(3), pp. 597-612, 2026, doi 10.1162/rest_a_01477, is kept)

Note: main.tex:157 sits inside a commented-out draft paragraph, so only the
:149 citation is actually typeset. Retargeted both so the commented one is
correct whenever it is restored.

### Verification
- [x] Full `pdflatex` -> `biber` -> `pdflatex` x2, exit 0 on every pass
- [x] Zero biber warnings, zero `!` TeX errors, zero undefined citations
- [x] 64-page PDF unchanged in length
- [x] Rendered PDF: 2 parenthetical "(... Mu, Rubin, and Zou 2026)", 1 in-text
      "Mu, Rubin, and Zou (2026)", 0 remaining "(2024)", and exactly 1 entry for
      this paper in the reference list
- [x] No `mu2024s` string remains in main.tex or citation.bib

## Final state of the writeup folder
`main.tex` and `citation.bib` are the only two modified files. The document
builds clean from scratch with all pipeline exhibits sourced from `output/`.