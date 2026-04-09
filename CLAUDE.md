# CLAUDE.md — Impact of coal mining on drinking water quality

## Project Overview

This project estimates the causal effects of coal mining on drinking water
quality at CWS. Drinking water quality is measured as violations of the 
Safe Drinking Water Act.
---

## Directory Structure

```
Project Structure

mining_wq/
├── raw_data/              # Source data, read-only
│   ├── msha/              # Mine Safety and Health Administration — mine locations & production
│   ├── eia/               # Energy Information Administration — coal production by mine
│   ├── coal_qual/         # USGS coal quality boreholes (sulfur %, BTU)
│   ├── ncra_coal/         # USGS National Coal Resource Assessment — coal field shapefiles
│   ├── huc/               # HUC12 watershed boundaries (pulled from sdwa_violations folder)
│   └── ...                # Other datasets not used in main analysis
│
├── clean_data/            # Intermediate pipeline outputs
│   ├── coal_mine_prod_charac.parquet   # mine × year: production + sulfur/BTU
│   ├── coal_huc_prod.csv               # HUC12 × year: aggregate production
│   ├── huc_coal_charac_geom_match.parquet  # HUC12 × year: production + sulfur + minehuc type
│   └── cws_data/
│       ├── prod_vio_sulfur.parquet     # PWSID × year: main analysis dataset (input to didhet.r)
│       └── violation.csv              # raw violation records for distributional plots
│
├── code/coal_mining_water_quality/    # All analysis scripts
│   ├── readmshatxt.r          # step 1: parse MSHA raw text → parquet/csv
│   ├── minegeomatch.py        # step 2: match mines to HUC12s, assign sulfur
│   ├── huc_coal_charac_geom_match.py  # step 3: build HUC-level panel
│   ├── sdwismatch*.py         # step 4: match SDWIS facilities/PWS to HUCs
│   ├── match_prod_vio_sulfur.py       # step 5: merge production, violations, sulfur
│   ├── didhet.r               # step 6: main analysis — all regressions, tables, figures
│   ├── mining_reg.r           # regression utilities
│   ├── spatial_kriging.r      # sulfur interpolation
│   └── kriging_sulfur.py
│
└── output/
    ├── fig/               # .png figures
    ├── reg/               # regression .tex tables
    └── sum/               # summary stat .tex tables
```

---

## DATA SAFEGUARDS — READ CAREFULLY

### raw_data/ is strictly read-only
- **Never write to, modify, overwrite, or delete any file in `raw_data/`.**
- Never run `rm`, `unlink()`, `file.remove()`, or any destructive operation
  targeting `raw_data/`.
- All cleaning and transformation must write outputs to `clean_data/`.

### Before any file operation
- When an intermediate or cleaned data file is needed in another file
  check that it exists already and do not create the file if it already exists.
- Only create an intermediate or cleaned data file that already exists if important
  changes to the build file have been made and subsequent analysis files rely
  on variables of the structure of the new build file to run.
- Never overwrite an existing file in `clean_data/` without first confirming
  the user wants to replace it and suggest what will change about the file if overwritten.

### Git discipline
- Before any multi-file editing session, check `git status`. If there are
  uncommitted changes, flag this and ask whether to commit first.
- Suggest a `git branch` before major transformations. Merge branch
  to main after user confirms they are satisfied with the actions of the branch

---

## COST ESTIMATION — REQUIRED BEFORE LARGE OPERATIONS

Before running any operation that is computationally expensive or uses a large amount of 
tokens (i.e. a high /cost), **estimate and report the expected cost/time first**, then
wait for the user to approve before executing.

### How to estimate
- Install and load any R packages needed to run the scripts without my permission.
- For file sizes: check with `file.info()` or `du -sh` before loading.
- Flag if an operation will produce output >1 GB.
- If an API or external data call is involved, estimate the number of requests
  and any associated rate limits.

---

## Coding Conventions

### Language & packages
- **R** or **Python**

### Python environment
There is no system Python on PATH. Always use the full path to the project virtualenv:
```bash
"Z:/ek559/nys_algal_bloom/NYS algal bloom/code2/Scripts/python.exe" script.py
# or inline:
"Z:/ek559/nys_algal_bloom/NYS algal bloom/code2/Scripts/python.exe" -c "..."
```
Do **not** use `python`, `python3`, or `py` — they will not be found.

### Style
- Snake_case for all object and variable names
- Every script should have a header block:
  ```r
  # ============================================================
  # Script: [name].R
  # Purpose: [one-line description]
  # Inputs: [files read]
  # Outputs: [files written]
  # Author: [initials]  Date: [YYYY-MM-DD]
  # ============================================================
  ```
- Save cleaned datasets as `.rds` (faster) or `.parquet` (for large files).
  Never overwrite raw data with `write.csv()`.

---

## Project-Specific Variable Names & Concepts

**Unit of observation:** PWSID × year (1985–2005, main sample)

| Concept | Variable name |
|---|---|
| Public water system ID (always refer to the drinking water systems as Community Water Systems or CWS and not PWS) | `PWSID` |
| HUC12 watershed of CWS intake | `huc12` |
| HUC classification (mine/upstream/downstream) | `minehuc` |
| Mine HUC indicator | `minehuc_mine` (1/0) |
| Upstream-of-mine HUC indicator | `minehuc_upstream_of_mine` (1/0) |
| Downstream-of-mine HUC indicator | `minehuc_downstream_of_mine` (1/0) |
| N mines colocated in intake HUC | `num_coal_mines_colocated` |
| N mines in directly upstream HUC | `num_coal_mines_upstream` |
| N mines unified (avg if both nonzero, else max) | `num_coal_mines_unified` |
| Coal production tons, colocated | `production_short_tons_coal_colocated` |
| Coal production tons, upstream | `production_short_tons_coal_upstream` |
| Coal production tons, unified | `production_short_tons_coal_unified` |
| Avg sulfur % of coal seams, colocated | `sulfur_colocated` |
| Avg sulfur % of coal seams, upstream | `sulfur_upstream` |
| Avg sulfur %, unified | `sulfur_unified` |
| Avg BTU content, colocated/upstream/unified | `btu_colocated`, `btu_upstream`, `btu_unified` |
| Post-ARP Phase I indicator (year >= 1995) | `post95` |

Outcome variables are types of drinking water contaminants:
nitrates violation | `nitrates` |
arsenic violation | `arsenic` |
inorganic chemicals violation | `inorganic_chemicals` |
radionuclides violation | `radionuclides` |
total coliform violation | `total_coliform` |
surface/groundwater rule violation | `surface_ground_water_rule` |
VOC violation | `voc` |
SOC violation | `soc` |

**Units of Violations** share of year in violation: outcome name contains `_share`. Number of days of year in violation: outcome name contains `_days`.
 
**Violation categories:** MCL (max contaminant level), MR (monitoring/reporting), TT (treatment technique) — outcome name contains `_MCL`, `_MR`, `_TT`. If outcome name does not contain MCL, MR, or TT then violation measures the time (in share of year or number of days) that any violation occured.

**Mining vs. non-mining violations:** Nitrates, arsenic, inorganic chemicals, and radionuclides are the "mining-related" outcomes. Total coliform, surface/groundwater rule, VOCs, and SOCs are "non-mining" placebo outcomes.

| N intake facilities (main control) | `num_facilities` |
| N source HUC12s for the PWS | `num_hucs` |
| Population served | `POPULATION_SERVED_COUNT` |
| Ownership type | `OWNER_TYPE_CODE` |
| Primary water source type | `PRIMARY_SOURCE_CODE` |

**Unified variables:** `_unified` variables average the colocated and upstream values when both are nonzero, and take the nonzero value when only one exists. For downstream HUCs, `num_coal_mines_unified` = `num_coal_mines_upstream` by construction (colocated is always 0).

### Geography
- Unit of analysis: **PWSID × year**
- CWS intakes are matched to HUC12 sub-watersheds via spatial join (SDWIS facility coordinates → HUC12 shapefile)
- HUC12s are classified as `mine`, `upstream_of_mine`, or `downstream_of_mine` based on mine locations and the HUC flow network (`tohuc` column links each HUC to its downstream neighbor)
- Coal quality (sulfur %) assigned to HUC12s via spatial join with USGS borehole samples, using a 20 km buffer

### Empirical specification (2SLS)

**First stage** — effect of ARP on coal production:
```
CoalMines_ht = α(sulfur_h × post95_t) + η_PWSID + τ_year + ρ_state + ε_ht
```
The instrument is `post95 * sulfur_unified`. High-sulfur HUCs saw larger production declines after 1995 when ARP Phase I took effect.

**Second stage** — effect of coal mining on SDWA violations:
```
ViolationShare_pt = β·CoalMineŝ_ht + γ·num_facilities_pt + η_PWSID + τ_year + ρ_state + ε_pt
```

Fixed effects: PWSID, year, state. SEs clustered at PWSID level (`cluster = ~ PWSID`). Estimated with `fixest::feols`. Each table reports OLS, reduced form, and 2SLS side by side.

**Sample cuts used in regression tables:**
- Colocated only: `minehuc_mine == 1 & minehuc_downstream_of_mine == 0`
- Downstream only: `minehuc_downstream_of_mine == 1 & minehuc_mine == 0`
- Colocated + downstream: `minehuc_upstream_of_mine == 0`
- All HUCs: full sample

---

## What to Ask Before Acting

If any of the following apply, **stop and ask** rather than proceeding:

1. The task requires writing to `raw_data/`
2. The operation will take >10 minutes or produce >500 MB of output
3. A file already exists at the output path

---