# Session: 2026-07-27 — Backcasting Step 3 (reported-served layer)

## Objective
Build Step 3 of the backcasting methodology (`writeup/cws_exposure_backcasting.tex`
§3.5): calibrate the capture ratio r = S/G against observed reported population,
carry it to all years, and form the reported-served exposure series E^S_t.

## Changes Made
- `code/coal_mining_water_quality/build_cws_reported_ratio.py` (new): anchor panel,
  ratio calibration, tier-aware carry, wholesale dedup, E^S_t.
- `code/coal_mining_water_quality/backcast_step3_tables.py` (new): 3 result tables.
- `clean_data/cws_data/cws_pop_anchors.parquet` (new, 1,120 anchors)
- `clean_data/cws_data/cws_capture_ratio_annual.parquet` (new, 12,810 rows)
- `clean_data/cws_data/cws_reported_exposure_annual.parquet` (new, 35 rows)
- `writeup/.../sum/backcast_{anchors,ratio,reported_exposure}.tex` (new)
- `writeup/.../population_backcasting.tex`: added the Step 4 subsection (reported
  layer), added the 4th validation check (ratio drift), rewrote the estimand
  paragraph to report both measures, **corrected the Results section** so the
  51.8% residential decline is no longer presented as the headline, and rewrote
  three limitations.

## Anchor sources (all verified on disk, PWSID-linkable)
| Source | Year(s) | Targets covered (of 366) |
|---|---|---|
| SYR2 occurrence .mdb (69 files) | 1998–2005 | 140 |
| CWSS 2006 `cwssframe` | 2006 | 259 |
| SDWIS 2010 freeze | 2010 | 360 |
| SDWIS 2011 freeze | 2011 | 361 |
| **Any anchor** | | **361** (5 imputed) |

Read via `pyodbc` + "Microsoft Access Driver (*.mdb, *.accdb)" — available on
this machine. SYR2 `POPULATION` lives in each per-chemical .mdb alongside PWSID.

## Critical findings (both changed the design/results)

### 1. SYR2 POPULATION is NOT an annual series
`POPULATION` is a single inventory value stamped on every sample record: 0 of
49,473 systems show any within-PWSID variation across 1998–2005. So SYR2 gives
ONE anchor per system (dated to first sample year), not an 8-year panel. Same for
every other source. The anchor panel is short and irregular (≤4 dates per system).

Also confirmed: `clean_data/cws_6year_review.parquet`'s POPULATION_SERVED_COUNT is
the 2024Q4 snapshot broadcast across ALL years (0 of 1,507 PWSIDs vary). It is NOT
a usable anchor — it is the artifact the backcast exists to remove. Excluded.

### 2. The capture ratio is only meaningful for the service-area tier
First implementation applied r = S/G uniformly and winsorized. Diagnostic showed
that was wrong:

| Tier | median raw r | interpretation |
|---|---|---|
| service_area | 1.53 | genuine capture rate; drift max/min = 1.15x median |
| county | 0.001 | utility's share of its COUNTY — not a capture rate |

Applying r to county-tier systems and multiplying back by G is circular: it just
returns the reported number while discarding the backbone, silently making E^S_t
a sum of raw reported values for 127 of 366 systems.

**Fix:** tier-aware carry. Service-area: S_hat = r_hat * G_hat. County-tier: take
reported population as the LEVEL, county growth as the TREND,
S_hat_t = S_a * (G_hat_t / G_hat_a). Verified: county-tier reproduces reported
values exactly at anchor years (max rel err 0.0).

## Headline result — and a correction to the Step 1–2 writeup
E^S_t falls 2.28M (1990) → 2.12M (2005) = **−7.3%**, against E^G_t's −51.8%.
Ratio E^S/E^G climbs 0.159 → 0.321.

Cause: of the 62 systems exiting the roster 1990→2005, **61 are county-tier and
only 1 is service-area**, median reported population **60 people**. They contribute
7.92M residents to E^G_1990 but only 50,436 reported customers.

So the 51.8% residential decline reported earlier today is **substantially an
artifact of the county fallback geography**. Direction survives (both decline,
roster contracts 340→278) but magnitude changes by an order of magnitude. The
writeup's Results section was corrected accordingly — this is the kind of thing
that would have been a referee's first objection.

## Verification Results
- [x] `build_cws_reported_ratio.py` runs end-to-end, exit 0
- [x] `backcast_step3_tables.py` runs end-to-end, exit 0
- [x] County-tier S_hat == S_reported at anchors (max rel err 0.0)
- [x] Decomposition rows reconcile with series rows (2,284,077 / 313 both bases)
      after persisting `is_seller` so tables use the same deduped basis
- [x] Wholesale dedup: 39,885 pairs → 39 both-downstream → 27 sellers removed
- [x] Section compiles under MiKTeX with main.tex's preamble, exit 0, refs
      resolve on 2nd pass; rendered tables inspected
- [x] Test artifacts removed

## Open Questions / Blockers
- 1990–1997 remains unanchored (no PWSID-linkable pop before SYR2 ~1998). r is
  held flat there, so pre-1998 movement in S_hat is pure Census trend.
- Pre-existing, unrelated: `main.tex` still fails to compile at
  `sum/npdwr_changes.tex:29` (`tablenotes` needs `threeparttable`). Untouched.

## Next backcasting steps (in recommended priority order)
1. **Leave-one-anchor-out validation** (writeup §3.8, now the biggest gap):
   withhold e.g. the 2006 anchor, predict it from the others, compare aggregate
   and per-system. 226 systems have 2–3 anchors and 134 have 4, so this is
   feasible for most of the sample.
2. **Leave-one-decade-out validation** of the geopop backbone: predict the 2000
   apportionment by PEP-scaling from 1990 and 2010, compare to the true 2000
   block apportionment. Tests the κ-constant assumption independently of any
   reported figure.
3. **Shrink the county tier.** 127 of 366 systems on county fallback is what
   drives the E^G/E^S divergence. Options: older SABS/state service-area
   vintages, or place/county-subdivision geography instead of whole counties.
   Highest-value improvement to the residential measure.
4. **ACS intercensal apportionment** (2009+) to replace PEP chaining in the
   modern period — writeup already promises this ("where an annual ACS
   apportionment is available, it is used directly"), but it is not implemented.
5. **EJ analysis (Q4)** — demographics are already built
   (`cws_demographics_decennial.parquet`) but never written up.
6. **Q3 no-coal counterfactual** with intensity weighting (by upstream mines /
   production / sulfur) — currently E_t is the trivial "relieved population".
7. **ML robustness layer** (writeup §3.9) — lowest priority; the deterministic
   backbone already carries the variation, and this is explicitly a sensitivity.
