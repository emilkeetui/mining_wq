# Session: 2026-07-27 — Population backcasting section for main.tex

## Objective
Write up the population-backcasting technique and results as a separate .tex
document, \input{} into `writeup/Mining_and_Water_Quality (1)/main.tex`.
Requested results: (1) how many CWSs one HUC12 directly downstream of coal mines
had population recovered, (2) which years, (3) summary statistics of population
across the sample, (4) average change from the earliest date to 2005.

## Context
The methodology already existed in `writeup/cws_exposure_backcasting.tex` (a
methods-only note, no results) and was implemented in the 2026-07-06 session
(`build_cws_polygon_weights.py` + `build_cws_geopop_backcast.py`, branch
`cws-geopop-backcast-ej`). That session's log flagged exactly this as a next
step: "Consider updating with a Results subsection once the user has reviewed
these numbers." Only Steps 1-2 (geopop backbone) are built; Step 3 (the reported
capture ratio r) is not, so all results are residential population G, not
reported-served S. Stated explicitly in the writeup.

## Changes Made
- `code/coal_mining_water_quality/backcast_results_tables.py` (new): generates
  4 LaTeX tables into `writeup/Mining_and_Water_Quality (1)/sum/`.
- `writeup/Mining_and_Water_Quality (1)/population_backcasting.tex` (new):
  the section — procedure (identity, 2-tier scope, areal apportionment, PEP
  chaining, roster aggregation), validation, results, limitations.
- `writeup/Mining_and_Water_Quality (1)/sum/backcast_{recovery,popsum,
  change_9005,exposure_series}.tex` (new, generated).
- `main.tex`: added `\input{population_backcasting}` after the ARP exposure
  figures (line ~318); reworded the line-289 caveat about the Q3-2024 SDWIS
  snapshot to cross-reference the new section instead of just conceding the gap.

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| Section enters as `\subsection` of "Identification Strategy", internal heads demoted to `\subsubsection` | main.tex's hierarchy is `\section`/`\subsection`; inserting a `\section` mid-way through Identification Strategy would have silently closed that section |
| Report residential G, not reported-served S | Step 3 (ratio r) is not built; claiming "population served" would misdescribe the estimand |
| Keep service-area and county tiers separate in every table | County-tier systems (127/366) inherit a whole county's population — levels are upper bounds. They contribute 84% of the 1990 exposed total, so pooled levels are dominated by the coarser tier |
| Report median % change, explicitly discount the mean | Mean pct change is +40.2%, driven by tiny systems growing off a near-zero base (max +4,407%: 1 resident -> 47). Median +0.48% is the honest central tendency |
| Panel A (balanced) vs Panel B (roster-weighted) split | This *is* the result: intensive margin is flat (+1.5%), aggregate falls 51.8% — entirely extensive margin |
| Tables written by a script, not hand-typed | Reproducible; numbers re-derive from parquet on re-run |

## Key Results
- **Recovery:** 366 of 367 ever-downstream CWSs (99.7%), 18 states. 239 via EPA
  SABS service-area polygon, 127 via county fallback (57 counties), 1 dropped
  (`SC2460011`). Balanced panel 366 x 35 = 12,810 system-years, 0 nulls.
- **Years:** 1990-2024. Four decennial anchors (1990/2000/2010/2020) + 31
  PEP-chained intercensal years. 1983-1989 of the roster NOT recovered (no
  nationwide block geography before the 1990 TIGER/Line release).
- **Summary stats (pooled):** mean 53,947, median 3,993 — bimodal by tier.
  Service-area: mean 10,234, median 480, p25 61. County: mean 136,209.
- **Change 1990->2005:** balanced set flat (19.32M -> 19.61M, +1.47%; median
  system +0.48%; 47.3% shrank). Roster-weighted: 15.13M -> 7.30M, **-51.8%**.
  340 downstream in 1990 -> 278 in 2005: 62 exits, **0 entries**; the 278
  stayers gained only 1.29%. The whole decline is the extensive margin.

## Verification Results
- [x] `backcast_results_tables.py` runs end-to-end, exit 0
- [x] All 4 .tex tables written and non-trivially populated
- [x] Internal consistency: 340 = 278 stayers + 62 exiters; tier counts
      239+127+1 = 367; Panel A tier totals sum to the all-systems row
- [x] Compiles under MiKTeX pdflatex with main.tex's preamble — exit 0, PDF
      produced, all `\ref`s resolve on 2nd pass, tables render correctly
      (inspected rendered PDF pages 4-6)
- [x] Test artifacts removed (`_test_backcast.tex`, stray `$out/` dir)

## Claims corrected against data during drafting
Four figures I initially drafted were wrong and were fixed by querying the
parquet directly — worth noting since they were all plausible-sounding:
1. "roughly a sixth of service areas straddle a county line" -> actually 57/239
   = 23.8%, just under a quarter.
2. Service-area median "about 1,000" -> actually 480 pooled (418 in the 1990
   cross-section); p25 "roughly 170" -> actually 61.
3. County tier "87% of the 1990 total" -> 87.4% of the *balanced* total but
   83.9% of the *Panel B roster* total, which is what the sentence referred to.
   Corrected to 84%.
4. "decline is steady rather than concentrated in a single break" -> E^G_t is
   NOT monotone (rises in 2006, 2008, 2018, 2022, 2024) and has a -22.8% drop in
   2017 and -15.8% in 1992. Only `n_systems` is monotone. Rewritten.

## Open Questions / Blockers
- Pre-existing, unrelated: `main.tex` does not currently compile to completion —
  `sum/npdwr_changes.tex:29` uses `\begin{tablenotes}` but `threeparttable` is
  not loaded in main.tex's preamble. This is at line ~544, downstream of the new
  section, and predates this session. Fix is `\usepackage{threeparttable}`.
  Not touched, since it is outside the scope of this task.
- Step 3 (capture ratio r -> reported-served exposure E^S_t) still unbuilt, so
  the section reports residential population only.
- Leave-one-decade-out validation (predict 2000 from 1990+2010) not yet run;
  noted as a limitation in the text rather than claimed.

## Next Steps
- User review of the numbers and framing.
- If E^S_t is wanted, build Step 3 (SYR2/SYR3/CWSS2006/2010-2011 anchors +
  buyers/sellers dedup) per the original plan.
