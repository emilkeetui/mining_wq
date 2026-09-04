# Session: 2026-09-04 — Introduction restructure against Head's formula

## Objective
Assess `main.tex`'s introduction against Keith Head's introduction formula
(hook / question / antecedents / value-added / road-map) and implement the fixes.

## Changes Made
- `writeup/.../main.tex` §Introduction (lines 169–213): full restructure.
  - **New hook paragraph.** Replaced the generic opening ("Environmental regulation
    often seeks to induce firms...") with the undercount puzzle: 9–34M Americans
    counted as served by violating utilities, count built from self-reports,
    contamination rises but recorded violations do not. Pulls the headline result
    forward and states the stakes (85% of US households).
  - **Question consolidated** to the abstract's single formulation; dropped the two
    redundant restatements. Generalizability sentence (income tax) moved to the end
    of the value-added paragraph as external validity.
  - **Antecedents moved before value-added** and compressed 5 paragraphs → 4:
    drinking water + point source merged; coal-mining geochemistry cut from 6
    citations to 2 (rest already cited in §Institutional background line ~242);
    monitoring/self-reporting and enforcement split into their own paragraphs,
    each ending on the gap rather than on an "I find" claim.
  - **New consolidated value-added paragraph** with three numbered contributions:
    (1) cost-of-self-reporting channel (led with, strongest), (2) first to identify
    effect of contamination on monitoring/enforcement, (3) first causal estimates of
    coal mining → treated drinking water.
  - **Citation churn removed**: `zou2021unwatched` / `10.1162/rest_a_01477` were
    cited three times in the intro; now once in antecedents (plus the TRI example
    in the setting paragraph).
  - **Sanitary-visit paragraph cleaned**: the "I cannot distinguish these two
    explanations" concession and `mi2026technology` moved to §Discussion so the
    intro does not end an evidence paragraph on a limitation.
  - Paragraph order now: hook → question → mechanism → antecedents ×4 →
    value-added → setting → endogeneity → instrument/data → model → results ×5 →
    road-map.

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| Instrument credited to `stratford2015coalprod` (Douglas & Wiggins 2015), not claimed as novel | User correction; §5 already says "I adapt the IV from". Value-added now claims only the novel *application* to upstream watersheds of utility intakes. |
| Kept all four Trump policy citations in the coal-mining antecedent paragraph rather than moving to the hook | Keeps the hook focused on the self-reporting undercount puzzle; policy timeliness reads better next to the mining literature. |
| Dropped geochem citations from intro but they remain at line ~242 | No bibliography entries orphaned; verified via biber (no undefined/unused warnings). |
| Intro grew 2,151 → 2,287 words | Value-added paragraph is new and the hook is longer; offset by antecedent compression. |

## Verification Results
- [x] `latexmk -pdf` compiles clean — 64 pages, `main.pdf` written
- [x] No undefined citations or references in `main.log`
- [x] No biber WARN/ERROR in `main.blg`
- [x] Section/label structure unchanged (all `\ref{sec:...}` in road-map resolve)

## Open Questions / Blockers
- Not committed yet; branch is `jmp-polish-main-tex` with other pending changes
  (table `.tex` files, `run_main_tables.r`).

## Next Steps
- User review of the new hook and value-added wording.
- Consider whether the abstract should be re-synced with the sharper hook framing.
