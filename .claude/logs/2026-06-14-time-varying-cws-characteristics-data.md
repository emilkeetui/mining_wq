# Session: 2026-06-14 — Time-varying CWS characteristics data sources

## Objective
Find web sources for **time-varying** Community Water System (CWS) characteristic
data (e.g. population served / number of customers per CWS over time) to convert the
current single-snapshot `POPULATION_SERVED_COUNT` control into a genuine panel
control for the 1985–2005 sample.

## Key finding
Population served (and the other CWS characteristics in SDWIS — system type,
ownership, primary source) is natively a **snapshot**, not a time series. EPA
overwrites these fields as systems report updates, so there is no single "panel"
download. A sparse time-varying panel must be built by **stacking EPA's archived
snapshots**, optionally supplemented with a periodic survey.

## Sources (ranked for the 1985–2005 sample)

### 1. SDWIS "Freeze" files via the Six-Year Review (best for a stackable panel)
For each Six-Year Review, EPA archives a frozen full-inventory snapshot of SDWIS —
including population served, system type, ownership, primary source per PWSID.
Stacking the freezes yields a panel at ~5-year intervals.

| Freeze | Snapshot year | Where |
|---|---|---|
| SYR1 | ~1998 | SYR1/SYR2 archive pages |
| **2005 Freeze** (3.1 MB) | 2005 | Supplemental Data for SYR3 |
| 2010 Freeze (38 MB), 2011 Freeze (44 MB) | 2010, 2011 | same SYR3 page |

The **2005 Freeze** is directly useful for the end of the sample. Combined with the
SYR1-era freeze it gives two clean inventory snapshots inside 1985–2005, keyed by
PWSID so they merge straight into `prod_vio_sulfur.parquet`.

### 2. Community Water System Survey (CWSS)
EPA's periodic survey of CWS — population served, water production, financials,
treatment, sources, ownership. Conducted in **1995, 2000, 2006** (earlier rounds
too). Stratified **sample**, not a census, so partial coverage, but the richest set
of time-varying characteristics. Linked from "Data for Economic Analysis of Drinking
Water Standards."

### 3. ECHO SDWA quarterly downloads
`SDWA_PUB_WATER_SYSTEMS.csv` is keyed by `SUBMISSIONYEARQUARTER` + `PWSID`, so it
looks longitudinal — but EPA confirms it is a **refreshed current snapshot**
(published 2021 onward), not a deep historical archive. Useful only for recent
years, not this sample.

## The catch for 1985–1992
No system-level population-served snapshot from EPA before ~1993 — SDWIS/FED
reliable inventory starts around then. For the early years, interpolate: anchor each
CWS to its place/county and scale with decennial Census population (1980/1990/2000),
or hold the earliest available freeze value fixed.

## Recommendation
Pull the **2005 Freeze** + the **SYR1 freeze** for two PWSID-level inventory
snapshots; optionally add **CWSS 1995/2000** for richer characteristics; then
linearly interpolate population served between snapshots and back-cast pre-1993 with
Census place population. This turns the single-snapshot `POPULATION_SERVED_COUNT`
into a time-varying control.

## Links
- Supplemental Data for Six-Year Review 3 (freeze files): https://www.epa.gov/dwsixyearreview/supplemental-data-six-year-review-3
- Six-Year Review 2 Contaminant Occurrence Data (1998–2005): https://www.epa.gov/dwsixyearreview/six-year-review-2-contaminant-occurrence-data-1998-2005
- Data for Economic Analysis of Drinking Water Standards (CWSS): https://www.epa.gov/sdwa/data-economic-analysis-drinking-water-standards
- SDWA Data Download Summary (ECHO): https://echo.epa.gov/tools/data-downloads/sdwa-download-summary
- SDWIS Federal Reporting Services: https://www.epa.gov/ground-water-and-drinking-water/safe-drinking-water-information-system-sdwis-federal-reporting

## Next steps
- [ ] Download 2005 Freeze and inspect schema; confirm PWSID merge with prod_vio_sulfur.parquet
- [ ] Locate SYR1 freeze file URL
- [ ] Decide interpolation/back-cast strategy for pre-1993 years
