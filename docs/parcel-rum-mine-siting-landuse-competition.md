# Parcel-Level RUM of Mine Siting under Land-Use Competition

**Status:** Design drafted — no code written yet.
**Author:** EK   **Created:** 2026-06-03   **Last updated:** 2026-06-03
**Related main project:** coal mining → drinking water quality (2SLS w/ ARP instrument). This is a
*siting / first-stage-mechanism* sub-study: it asks where mines locate and why, which underpins the
exclusion-restriction story (mining is non-randomly placed on low-opportunity-cost land).

---

## 0. How to resume (read this first)

- **Where I left off:** theory + lit + data-source inventory settled; pipeline is specified but not
  built. Next concrete action = **Step 1 of the pipeline** (build the choice frame / grid).
- **Decision locked:** unit of observation is the **parcel = grid cell**, not HUC12 (departs from the
  main pipeline's HUC12 unit on purpose — the RUM theory is parcel-level).
- **Decisions still open:** see §7. The two that block Step 1 are (a) grid resolution and (b) the
  geographic universe (CONUS coal states vs. Central Appalachia only for the SkyTruth annual panel).
- **Existing assets to reuse:** `minegeomatch.py` (mine→geometry matching), `spatial_kriging.r` /
  `kriging_sulfur.py` (sulfur surface), NCRA coal-field shapefiles (`raw_data/ncra_coal/`), MSHA mine
  locations (`raw_data/msha/`), CoalQual sulfur/BTU (`raw_data/coal_qual/`).

---

## 1. Research question

**What land-use competition determines the location of coal mines in the contiguous US?**

Operationally: among parcels where coal extraction is geologically feasible, which are actually mined,
and how does the decision trade off the **resource rent from coal** against the **opportunity-cost rent
of competing surface uses** (farming, forest, settlement)?

Sub-questions:
1. Do mines locate on **low-opportunity-cost land** (low farm rent, steep/forested, far from towns)?
2. What is the marginal trade-off — how much competing-use rent must a parcel forgo before coal wins?
3. Does the siting gradient differ by mine type (surface vs. underground) and by coal quality (sulfur)?

**Why it matters for the main chapter:** the 2SLS exclusion restriction (high-sulfur HUCs saw larger
post-ARP production declines) is more credible if siting is explained by land economics + geology rather
than by unobservables correlated with water-system outcomes. This sub-study characterizes the selection.

---

## 2. Theoretical model — parcel-level random-utility bid-rent

### 2.1 Bid-rent foundation (von Thünen / Ricardian)
Each parcel l is allocated to the use j that bids the most for it. Use j yields land rent =
residual profit after non-land inputs and transport to market:

```
R_j(l) = p_j(l)·y_j(l)  —  w(l)·x_j  —  τ_j·D(l)
          [revenue]         [inputs]      [access/transport]
```

Observed use = argmax_j R_j(l); land value = upper envelope R(l) = max_j R_j(l).
"Competing-use rent" = the set of R_j(l) for non-mining uses; it is the **opportunity cost of mining** l.

A parcel is mined iff:
```
R_mine(l)  >  max{ R_ag(l), R_forest(l), R_dev(l), R_idle(l) }
```

**Key asymmetry:** mining rent is a **Hotelling resource rent** (expected discounted in-situ value of the
seam, net of extraction cost) — a one-time exhaustible draw — competing against **perpetual Ricardian
flow rents**. Coal endowment / seam thickness / sulfur / BTU enter R_mine on the revenue side; terrain
(slope, overburden → surface vs. deep) enters on the extraction-cost side. The asymmetry is why mining
wins on cheap surface land (steep, forested, low farm rent).

### 2.2 Random-utility specification (the estimable model)
Add an iid Type-I EV shock ε_j(l) to each rent. Parcel l chooses use j with prob:

```
Pr(use_l = j) = exp(V_j(l)) / Σ_k exp(V_k(l))            (McFadden conditional logit)
```

where V_j(l) is the deterministic rent index. For the **siting** question we collapse to the feasible
universe (cells with positive coal endowment) and the binary/multinomial margin "mine vs. surface uses":

```
Pr(mine_l = 1 | feasible) = Λ( coal endowment, slope/overburden, distance-to-rail,
                                R_ag, R_forest, R_dev )
```

Coefficients on the competing rents (R_ag, R_forest, R_dev) directly answer the RQ. Restricting to the
**feasible set** (positive coal endowment + buffer) is essential — elsewhere R_mine = −∞ and the cell is
mechanically never mined, which would bias the rent coefficients toward geology rather than competition.

### 2.3 Optional dynamic extension (irreversibility)
Mining is irreversible, so a forward-looking owner mines only when resource rent clears surface rent
**plus an option premium**. Two ways to capture this without a full dynamic discrete-choice (DDC) solve:
- **Hazard / duration model** of time-to-first-mining on the feasible set (Irwin–Bockstael; Vance–Geoghegan).
  Lightweight; captures option value through the timing margin. **Recommended robustness layer.**
- Full **DDC** (De Pinto–Nelson 2009 style; Rust 1987 / Hotz–Miller / Aguirregabiria–Mira). The frontier;
  large estimation lift; **not** needed for the baseline — cite as the ceiling we don't climb.

---

## 3. Literature

### 3.1 Workable baseline (adopt)
| Cite | Role | In `lit/`? |
|---|---|---|
| **Lubowski, Plantinga & Stavins (2008, JEEM)** "What Drives Land-Use Change in the US?" | Canonical econometric RUM of conversion on net returns by use. **The template.** | ✗ acquire |
| **Chomitz & Gray (1996, WBER)** "Roads, Land Use, and Deforestation" | Parcel-level RUM, Pr(use=j) ~ net returns + geophysical. | ✗ acquire |
| **Nelson & Hellerstein (1997, AJAE)** | Spatially-explicit land-use RUM. | ✗ acquire |
| **Capozza & Helsley (1989, JUE)** "Fundamentals of land prices and urban growth" | von Thünen rent gradient + conversion option. Theoretical frame. | ✗ acquire |

### 3.2 Irreversibility / dynamics (robustness)
| Cite | Role | In `lit/`? |
|---|---|---|
| **Irwin & Bockstael (2002)** | Survival/duration framing of land conversion. | ✗ acquire |
| **Vance & Geoghegan (2002)** | Hazard model of conversion timing. | ✗ acquire |
| **Capozza & Helsley (1990)** "The stochastic city" | Option value / irreversibility in conversion. | ✗ acquire |

### 3.3 Frontier (cite, do not implement for baseline)
| Cite | Role | In `lit/`? |
|---|---|---|
| **De Pinto & Nelson (2009, Env Resource Econ)** | Dynamic discrete-choice land-use w/ option value, NPL estimation. | ✓ `De Pinto and Nelson 2009.pdf` |
| **Aguirregabiria & Mira (2002/2010)** | NPL estimator for DDC. | ✓ `Aguirregabiria and Mira 2010.pdf` |
| **Rust (1987)** | Foundational DDC. | ✗ (well known) |

**Lit gap to fill before writing:** acquire the §3.1 + §3.2 PDFs (none currently in `lit/`). The bid-rent
RUM canon is the backbone of the writeup and is entirely missing from the local library.

---

## 4. Data sources

### 4.1 Outcome — observed land use & mine extent
| Layer | Source | Res / years | Use |
|---|---|---|---|
| **LCMAP** (or Annual NLCD) | USGS | 30 m, **1985–present annual** | Observed use per cell-year (competing-use classes); aligns w/ 1985–2005 sample. |
| **SkyTruth / Pericak (2018)** | SkyTruth, GEE | 30 m, **1985–2015 annual**, Central Appalachia | True annual mine-footprint panel → mine onset. **Best treatment layer.** |
| **Maus et al. (2022) v2** | PANGAEA | polygons, snapshot | CONUS mine polygons (filter ISO3=USA). Snapshot, not panel. |
| **Tang & Werner (2023)** | Nature Comms E&E / GEE | polygons | Complementary mine polygons; union w/ Maus. |
| **MSHA mine locations** | `raw_data/msha/` | points, w/ open dates | Mine-onset timing; already in pipeline. |

### 4.2 Coal resource rent (R_mine) covariates
| Layer | Source | Use |
|---|---|---|
| NCRA coal fields | `raw_data/ncra_coal/` | Feasible-universe mask (positive endowment + buffer). |
| CoalQual boreholes | `raw_data/coal_qual/` | Sulfur %, BTU → seam quality; krige to surface (`spatial_kriging.r`). |
| EIA mine production | `raw_data/eia/` | Coal price / production scale context. |
| Seam thickness | USGS NCRA / state geol. surveys | Extraction economics (acquire if available). |
| Rail network | BTS / NTAD | Distance-to-rail = access cost for coal haul. |

### 4.3 Competing-use rents
| Rent | Layer | Source |
|---|---|---|
| **Ag** (R_ag) | County cash rent / farm real-estate value; CDL crop mix; soil quality (LCC, productivity index) | USDA NASS; gSSURGO/SSURGO |
| **Forest** (R_forest) | Timber site index / productivity; forest type; stumpage | USFS FIA; NLCD/LCMAP forest classes |
| **Development** (R_dev) | Distance-to-city; settlement intensity; housing/pop density gradient | Census places/TIGER; GHSL built-up; NLCD developed |
| **Idle/other** | residual category | — |

### 4.4 Geophysical controls
| Layer | Source | Use |
|---|---|---|
| Slope, elevation | USGS 3DEP / SRTM DEM | Extraction cost + ag/forest productivity. |
| Soil | gSSURGO | Ag productivity, drainage. |

---

## 5. Data pipeline outline

Target unit: **parcel (grid cell) × year**, restricted to the coal-feasible universe.
All outputs → `clean_data/` (never `raw_data/`). New scripts in `code/coal_mining_water_quality/`.
Python = venv path in CLAUDE.md; R = `C:\Program Files\R\R-4.6.1\bin\Rscript.exe`.

```
Step 1 — BUILD CHOICE FRAME
  • Generate regular grid over the feasible universe (NCRA coal fields + buffer).
  • Resolution + geographic extent = OPEN DECISIONS (§7).
  • Output: clean_data/siting/parcel_grid.parquet  (cell_id, geometry, lon/lat, state)
  • Reuse: NCRA shapefile load pattern from minegeomatch.py.

Step 2 — ASSIGN OUTCOME (land use + mine onset)
  • Zonal/point overlay of LCMAP (or Annual NLCD) → observed use per cell-year.
  • Mine cells from SkyTruth annual (Appalachia) ∪ Maus/Tang polygons ∪ MSHA points → mine_onset_year.
  • Output: clean_data/siting/parcel_landuse_panel.parquet  (cell_id, year, landuse, mined, onset_year)

Step 3 — COAL ENDOWMENT / RESOURCE RENT COVARIATES
  • NCRA field membership; krige CoalQual sulfur/BTU to cell centroids (reuse spatial_kriging.r).
  • Distance-to-rail (NTAD); seam thickness if acquired.
  • Output: merge into parcel frame → coal_endowment, sulfur_cell, btu_cell, dist_rail.

Step 4 — TERRAIN
  • DEM (3DEP/SRTM) → slope, elevation per cell.
  • Output: merge slope, elevation.

Step 5 — COMPETING-USE RENTS
  • R_ag: NASS county cash rent/value + gSSURGO soil productivity (+ CDL crop mix post-2008).
  • R_forest: FIA site index / forest-type productivity.
  • R_dev: distance-to-city (TIGER places) + GHSL/NLCD developed intensity.
  • Output: merge R_ag, R_forest, R_dev, dist_city.

Step 6 — ASSEMBLE ANALYSIS PANEL
  • Join Steps 2–5 on cell_id (× year where time-varying).
  • Choice-based sampling: keep ALL mined cells + random sample of non-mined feasible cells
    (rare-events; apply King–Zeng correction in estimation).
  • Schema enforcement before parquet write (cell_id str, year int64) — cross-language rule.
  • Output: clean_data/siting/parcel_rum_analysis.parquet

Step 7 — ESTIMATE RUM (new R script, fixest/mlogit/survival)
  • Baseline: conditional/multinomial logit, mine vs. surface uses on feasible set.
  • Robustness: hazard model of time-to-mining (irreversibility).
  • Spatially-clustered SEs.
  • Outputs: output/reg/siting_rum_*.tex, output/fig/siting_*.png  (wrap_for_beamer on every .tex).
```

---

## 6. Identification & estimation notes
- **Feasible-set restriction is the crux** — defines the choice set so coefficients measure *competition*,
  not mere geology. Sensitivity to buffer width should be reported.
- **Choice-based / rare-events sampling**: mined cells are a tiny share; oversample them and correct
  (King & Zeng 2001 prior correction, or weights).
- **Endogeneity of rents**: realized land values near mines may be contaminated by mining itself — prefer
  **pre-period / ex-ante** rent proxies (soil capability, site index, distance-to-city) over post-mining
  observed values, mirroring the "lag the land cover" caution from the data-discovery discussion.
- **Mine-type split**: estimate separately for surface vs. underground (terrain coefficient should flip
  in importance).

---

## 7. Open decisions (resolve before Step 1)
1. **Grid resolution** — 30 m (matches LCMAP, huge N) vs. 480 m / 1 km aggregated cell (tractable RUM).
   Leaning ~1 km sampled, à la NRI-point designs.
2. **Geographic universe** — Central Appalachia only (gets the SkyTruth *annual* panel, cleanest onset)
   vs. all CONUS coal states (broader external validity, but onset only from polygons/MSHA dates).
3. **Static RUM vs. hazard as the headline** — cross-sectional conditional logit first; hazard as robustness.
4. **Rent proxies**: imputed net-returns (build) vs. observed land values (acquire) — leaning imputed,
   ex-ante, to avoid mining contamination.
5. **Earth Engine vs. local rasters** — GEE for LCMAP/SkyTruth zonal extraction vs. download + local.

---

## 8. Immediate next steps
1. Acquire §3.1–3.2 lit PDFs (Lubowski–Plantinga–Stavins, Chomitz–Gray, Nelson–Hellerstein,
   Capozza–Helsley, Irwin–Bockstael) into `lit/`.
2. Resolve §7 decisions 1–2 (resolution + extent) — these block the choice-frame build.
3. Build Step 1 (`parcel_grid.parquet`) and sanity-check feasible-cell counts.
