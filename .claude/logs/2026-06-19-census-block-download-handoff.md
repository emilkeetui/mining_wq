# Handoff: Census block/block-group download via IPUMS NHGIS

**Date:** 2026-06-19 · **Author:** EK (spec by Opus) · **Executor:** Claude Sonnet
**Goal:** Download, into `raw_data/census/`, the inputs the backcasting note
(`writeup/cws_exposure_backcasting.pdf`, §3.2 / §4.2) needs for the G backbone and
EJ analysis: census **block** polygons + population/race/sex, and **block-group**
income, for **1990, 2000, 2010, 2020**, limited to coal-relevant states.

---

## 0. What the user must provide before you can run anything

- **IPUMS NHGIS API key** (string). User has an NHGIS account; key is generated at
  https://account.ipums.org/api_keys . Do NOT hardcode it. Read it from env var
  `IPUMS_API_KEY`, or prompt the user to paste it and store it in a gitignored file
  `.claude/.ipums_api_key` (add to `.gitignore` first). Never commit the key.

That is the ONLY external input needed. Everything else is specified below.

---

## 1. Decisions already locked (do not re-ask)

| Decision | Value |
|---|---|
| Scope | **Coal-relevant states only** (list in §2), not national |
| Income geography | **Block group** (block-level income does not exist) |
| Write target | **`raw_data/census/`** — hook exemption already added (see §6) |
| Source | **IPUMS NHGIS** (API) |

## 1a. The availability finding already reported to the user

- Population, race, sex → available at **census block** all four years (100% short form).
- **Income → NOT available at block level any year.** Finest is **block group**
  (1990 STF3, 2000 SF3, 2010 ACS 2006–2010 5yr, 2020 ACS 2016–2020 5yr).
- **2020** block counts (PL94-171 / DHC) carry **differential-privacy noise**;
  2020 sex-by-age lives in the **DHC** (2023 release), not PL94-171.
- 1990 sex is in STF1 at block — confirm on download.

---

## 2. Geographic scope — coal-relevant states (union of both rosters)

Derived from `clean_data/cws_data/prod_vio_sulfur.parquet`
(`minehuc_downstream_of_mine==1 | minehuc_mine==1`) UNION
`clean_data/county_mining_downstream.parquet`. The `'0'` junk state code was dropped.

33 states (postal → FIPS):

```
AL 01  AZ 04  CA 06  CO 08  FL 12  GA 13  ID 16  IL 17  IN 18
KS 20  KY 21  LA 22  MD 24  MI 26  MO 29  MS 28  NC 37  NE 31
NJ 34  NM 35  NY 36  OH 39  OK 40  OR 41  PA 42  SC 45  TN 47
TX 48  UT 49  VA 51  WA 53  WV 54  WY 56
```

NHGIS block-level extracts require a **geographic extent** selection — pass these
state FIPS as the extent. Block-group and shapefile requests take the same extent.

---

## 3. Exactly what to request from NHGIS

For each census year, two geographies:

### A. BLOCK level — population, race, sex (100% / short form)

| Year | NHGIS dataset (verify via metadata API) | Tables to pull |
|---|---|---|
| 1990 | `1990_STF1`     | total population; race; sex (or sex-by-age) |
| 2000 | `2000_SF1a`     | total population (P1); race (P3); sex-by-age (P12) |
| 2010 | `2010_SF1a`     | total population (P1); race (P3); sex-by-age (P12) |
| 2020 | `2020_DHCa`     | total population; race; sex-by-age — **DHC**, has DP noise |

(2020 population+race also exist in `2020_PL94171`; sex requires DHC. Pull DHC so
all three come from one dataset; note the DP-noise caveat in the manifest.)

### B. BLOCK GROUP level — income

| Year | NHGIS dataset | Table |
|---|---|---|
| 1990 | `1990_STF3`        | median household income (+ income distribution if cheap) |
| 2000 | `2000_SF3a`        | median household income (P053) |
| 2010 | `2006_2010_ACS5a`  | median household income (B19013) |
| 2020 | `2016_2020_ACS5a`  | median household income (B19013) |

### C. Boundary shapefiles (GIS files)

- Block boundaries: 1990, 2000, 2010, 2020 (for the block tables).
- Block-group boundaries: matching vintage for each income year.
- NHGIS ships these as separate shapefile products in the same extract
  (`shapefiles=[...]`). Select the basenames whose year + geog level match.

> **IMPORTANT — codes drift.** Do not trust the dataset/table codes above blindly.
> First hit the NHGIS metadata endpoints to resolve current codes:
> `GET /metadata/datasets`, `GET /metadata/datasets/{dataset}/data_tables`,
> `GET /metadata/shapefiles`. Match on description (e.g. "Median Household Income",
> "Sex by Age", "Race") and the right year + geog level, then build the extract.

---

## 4. Output layout (write here)

```
raw_data/census/
  manifest.md                      # what was pulled, dataset+table codes, row counts, caveats
  extract_definitions/            # the JSON extract spec(s) submitted to NHGIS (reproducibility)
  1990/
    block/        nhgis_1990_block_pop_race_sex.csv        + codebook
    block/shape/  nhgis_1990_block.{shp,shx,dbf,prj}
    blockgroup/   nhgis_1990_bg_income.csv                 + codebook
    blockgroup/shape/ ...
  2000/ ... 2010/ ... 2020/ ...   # same structure
```

Keep NHGIS codebooks (`.txt`) — they document table cell codes and the DP/sample notes.

## 4a. Cross-language note for downstream use

These are *raw* downloads (read-only source). The pipeline that builds `G_{i,t}`
(spatial apportionment, §4.2 of the note) will read them later and write to
`clean_data/`. Do not transform-in-place here. When a downstream parquet is built
from these, enforce the project schema rule (PWSID str, year int64, drop geometry,
print dtypes) — but that is a *later* step, not part of this download.

---

## 5. Suggested execution path

1. `pip install ipumspy` into the project venv
   (`"Z:/ek559/nys_algal_bloom/NYS algal bloom/code2/Scripts/python.exe" -m pip install ipumspy`),
   OR use the NHGIS REST API directly with `requests` (geopandas + requests already present).
2. Resolve dataset/table/shapefile codes via the metadata API (§3 IMPORTANT box).
3. Build ONE extract per census year (block dataset + bg income dataset + both
   shapefiles + state-FIPS extent), or batch — NHGIS queues then returns a zip.
4. Poll the extract status, download the zip, unzip into the §4 layout.
5. Write `manifest.md` with: dataset/table codes used, N rows per file, and the
   2020 DP-noise + income-is-blockgroup caveats.
6. **Cost flag (per project rule):** 33 states × 4 years × block geography is large
   (block CSVs + shapefiles likely several GB total). Estimate the zip size from the
   NHGIS extract summary and report it to the user BEFORE downloading if > ~500 MB.

A scaffold is provided at
`code/coal_mining_water_quality/download_census_nhgis.py` — fill the TODOs.

## 6. Environment / guardrails already set up by Opus

- `protect-raw-data.py` now exempts `raw_data/census/` (added to `EXEMPT_DIRS` and
  the `check_bash` regex). Verified: census writes allowed; other `raw_data/` writes
  still hard-blocked; destructive ops inside census still blocked. **Note:** the hook
  does not treat `curl -o` as a write verb, so Bash downloads aren't auto-blocked —
  prefer writing via Python (Write tool / file objects), which the hook *does* gate.
- venv: geopandas 1.0.1, pandas 2.2.3, requests present; **ipumspy NOT installed**.

## 7. Validation checklist before declaring done

- [ ] Each year has block pop/race/sex CSV + block shapefile, and bg income CSV + bg shapefile.
- [ ] Row counts plausible (millions of blocks nationally → hundreds of thousands across 33 states).
- [ ] Shapefile loads in geopandas; CRS logged (NHGIS ships EPSG:4326 or a USGS Albers — record it).
- [ ] `manifest.md` lists exact dataset/table codes + caveats.
- [ ] No write landed outside `raw_data/census/`.
- [ ] Report to user: any feature/year that came back empty or coarser than expected.
```

---
**[COMPACTION NOTE � 2026-06-20T16:11:30Z]**  
Auto-compact triggered. Active plan: `none`.  
Resume by reading CLAUDE.md + most recent plan + `git log --oneline -5`.
---
