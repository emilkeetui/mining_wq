# ============================================================
# Script: build_2step_sample.py
# Purpose: Build PWSID×year panel for CWSs whose intake HUC12 is exactly
#          2 steps downstream of a coal mine HUC12 (D2 = D1's tohuc).
#          Produces prod_vio_sulfur_2step.parquet with the same column schema
#          as prod_vio_sulfur.parquet, plus minehuc_downstream_of_mine_2step=1.
# Inputs:
#   clean_data/huc_coal_charac_geom_match.csv  (D1 fromhuc=mine linkage)
#   clean_data/coal_huc_prod.csv               (mine HUC × year production)
#   Z:/ek559/sdwa_violations/WBD_HUC12_CONUS_pulled10262020/*.shp  (HUC flow network)
#   Z:/ek559/water_instrument/cws_intake_hucs/PWS_Loctations_HUC12_A_I_2022Q2.xlsx
#   Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.csv
#   Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_PUB_WATER_SYSTEMS.csv
#   Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_FACILITIES.csv
# Outputs:
#   clean_data/cws_data/prod_vio_sulfur_2step.parquet
# Author: EK  Date: 2026-04-22
# ============================================================

import pandas as pd
import geopandas as gpd
import numpy as np
from pathlib import Path

ROOT      = Path("Z:/ek559/mining_wq")
HUC_SHP   = Path("Z:/ek559/sdwa_violations/WBD_HUC12_CONUS_pulled10262020/WBD_HUC12_CONUS_pulled10262020.shp")
INTAKE_XL = Path("Z:/ek559/water_instrument/cws_intake_hucs/PWS_Loctations_HUC12_A_I_2022Q2.xlsx")
SDWA_DIR  = Path("Z:/ek559/sdwa_violations/SDWA_latest_downloads")
OUT_PATH  = ROOT / "clean_data/cws_data/prod_vio_sulfur_2step.parquet"

# ── Step 1: Identify 2-step downstream HUC12s ─────────────────────────────
print("Step 1: Identifying 2-step downstream HUCs...")

huc_csv = pd.read_csv(
    ROOT / "clean_data/huc_coal_charac_geom_match.csv",
    dtype={"huc12": str, "fromhuc": str, "tohuc": str}
)

mine_hucs     = set(huc_csv.loc[huc_csv["minehuc"] == "mine",              "huc12"].unique())
upstream_hucs = set(huc_csv.loc[huc_csv["minehuc"] == "upstream_of_mine",  "huc12"].unique())
d1_hucs       = set(huc_csv.loc[huc_csv["minehuc"] == "downstream_of_mine","huc12"].unique())

print(f"  Mine HUCs: {len(mine_hucs)}  Upstream: {len(upstream_hucs)}  D1: {len(d1_hucs)}")

# D1 → mine mapping:  fromhuc in the CSV for downstream rows = the mine HUC feeding D1
d1_mine = (
    huc_csv[huc_csv["minehuc"] == "downstream_of_mine"][["huc12", "fromhuc"]]
    .rename(columns={"huc12": "D1_huc12", "fromhuc": "mine_huc12"})
    .drop_duplicates()
)

# Load HUC flow network to get each D1's downstream neighbor (= D2)
print("  Loading HUC shapefile for D1->D2 flow links...")
huc_net = gpd.read_file(str(HUC_SHP), include_fields=["huc12", "tohuc"])
huc_net = pd.DataFrame(huc_net[["huc12", "tohuc"]]).copy()
huc_net["huc12"] = huc_net["huc12"].astype(str).str.strip()
huc_net["tohuc"] = huc_net["tohuc"].astype(str).str.strip()

# D1's tohuc = D2
d1_to_d2 = (
    huc_net[huc_net["huc12"].isin(d1_hucs)][["huc12", "tohuc"]]
    .rename(columns={"huc12": "D1_huc12", "tohuc": "D2_huc12"})
    .dropna(subset=["D2_huc12"])
)
d1_to_d2 = d1_to_d2[d1_to_d2["D2_huc12"].str.len() > 0]

# Exclude D2s that are already mine, upstream, or D1
exclude_hucs = mine_hucs | upstream_hucs | d1_hucs
d1_to_d2 = d1_to_d2[~d1_to_d2["D2_huc12"].isin(exclude_hucs)]

two_step_hucs = set(d1_to_d2["D2_huc12"].unique())
print(f"  2-step HUC12s (D2): {len(two_step_hucs)}")

# D2 → mine_huc12 pairs (for coal characteristic assignment)
d2_mine = d1_to_d2.merge(d1_mine, on="D1_huc12")  # cols: D2_huc12, D1_huc12, mine_huc12

# ── Step 2: Coal characteristics for each (D2, year) ──────────────────────
print("Step 2: Assigning coal characteristics to D2...")

coal_prod = pd.read_csv(ROOT / "clean_data/coal_huc_prod.csv", dtype={"huc12": str})
coal_prod = coal_prod.rename(columns={"huc12": "mine_huc12"})

# Time-invariant sulfur/BTU from mine rows of the CSV (mean across duplicate borehole rows)
mine_sulfur = (
    huc_csv[huc_csv["minehuc"] == "mine"][["huc12", "sulfur_colocated", "btu_colocated"]]
    .drop_duplicates()
    .rename(columns={"huc12": "mine_huc12"})
    .groupby("mine_huc12")
    .agg(sulfur_colocated=("sulfur_colocated", "mean"),
         btu_colocated=("btu_colocated", "mean"))
    .reset_index()
)

d2_chars = d2_mine.merge(mine_sulfur, on="mine_huc12", how="left")
d2_chars = d2_chars.merge(coal_prod, on="mine_huc12", how="left")  # adds year, num_coal_mines, production

# Aggregate across all mine HUCs feeding each D2 (mean per D2 × year)
d2_chars = (
    d2_chars.groupby(["D2_huc12", "year"])
    .agg(
        sulfur_upstream=("sulfur_colocated",                     "mean"),
        btu_upstream=("btu_colocated",                           "mean"),
        num_coal_mines_upstream=("num_coal_mines",               "mean"),
        production_short_tons_coal_upstream=("production_short_tons_coal", "mean"),
    )
    .reset_index()
    .rename(columns={"D2_huc12": "huc12"})
)

# D2 has no colocated mines
d2_chars["sulfur_colocated"]                     = 0.0
d2_chars["btu_colocated"]                        = 0.0
d2_chars["num_coal_mines_colocated"]             = 0.0
d2_chars["production_short_tons_coal_colocated"] = 0.0

# Unified = upstream (since colocated = 0)
d2_chars["sulfur_unified"]                       = d2_chars["sulfur_upstream"]
d2_chars["btu_unified"]                          = d2_chars["btu_upstream"]
d2_chars["num_coal_mines_unified"]               = d2_chars["num_coal_mines_upstream"]
d2_chars["production_short_tons_coal_unified"]   = d2_chars["production_short_tons_coal_upstream"]
d2_chars["post95"]                               = (d2_chars["year"] >= 1995).astype(int)

print(f"  D2×year rows with coal data: {len(d2_chars)}")

# ── Step 3: Identify 2-step downstream CWSs via intake file ───────────────
print("Step 3: Identifying 2-step downstream CWSs...")

intake = pd.read_excel(
    INTAKE_XL,
    dtype={"HUC_12": str, "FACILITY_ID": str}
)[["PWSID", "FACILITY_ID", "HUC_12"]].rename(columns={"HUC_12": "huc12"}).drop_duplicates()
intake["huc12"] = intake["huc12"].astype(str).str.strip()

# Restrict to CWS-type PWS IDs (mirrors existing pipeline which filters water_sys to CWS)
pws_type = pd.read_csv(SDWA_DIR / "SDWA_PUB_WATER_SYSTEMS.csv", low_memory=False,
                       usecols=["PWSID", "PWS_TYPE_CODE"])
cws_pwsids = set(pws_type.loc[pws_type["PWS_TYPE_CODE"] == "CWS", "PWSID"].unique())
intake = intake[intake["PWSID"].isin(cws_pwsids)]

cws_2step   = set(intake.loc[intake["huc12"].isin(two_step_hucs),  "PWSID"].unique())
cws_in_mine = set(intake.loc[intake["huc12"].isin(mine_hucs),      "PWSID"].unique())
cws_in_d1   = set(intake.loc[intake["huc12"].isin(d1_hucs),        "PWSID"].unique())
cws_in_up   = set(intake.loc[intake["huc12"].isin(upstream_hucs),  "PWSID"].unique())

# Drop CWSs with any intake in mine, existing 1-step downstream, or upstream HUCs
cws_2step_pure = cws_2step - cws_in_mine - cws_in_d1 - cws_in_up

print(f"  2-step CWSs (before exclusions): {len(cws_2step)}")
print(f"  2-step CWSs (after exclusions):  {len(cws_2step_pure)}")

if len(cws_2step_pure) == 0:
    raise RuntimeError("No 2-step downstream CWSs found after exclusions — check HUC flow network.")

# PWSID → D2 huc12 (for coal characteristic lookup)
pwsid_huc = (
    intake[intake["PWSID"].isin(cws_2step_pure) & intake["huc12"].isin(two_step_hucs)]
    [["PWSID", "huc12"]].drop_duplicates()
)

# ── Step 4: Violation data for 2-step CWSs ────────────────────────────────
print("Step 4: Loading violation data for 2-step CWSs (chunked read)...")

vio_cols = ["PWSID", "VIOLATION_ID", "NON_COMPL_PER_BEGIN_DATE",
            "NON_COMPL_PER_END_DATE", "RULE_CODE", "RULE_FAMILY_CODE",
            "VIOLATION_CATEGORY_CODE", "IS_MAJOR_VIOL_IND"]

vio_chunks = []
for chunk in pd.read_csv(
    SDWA_DIR / "SDWA_VIOLATIONS_ENFORCEMENT.csv",
    low_memory=False, chunksize=200_000, usecols=vio_cols
):
    filtered = chunk[chunk["PWSID"].isin(cws_2step_pure)]
    if len(filtered) > 0:
        vio_chunks.append(filtered)

violation_raw = pd.concat(vio_chunks, ignore_index=True) if vio_chunks else pd.DataFrame(columns=vio_cols)
print(f"  Raw violation rows: {len(violation_raw)}")

# Drop rows with no begin date; cap open-ended violations at end of 2024
violation_raw = violation_raw[~violation_raw["NON_COMPL_PER_BEGIN_DATE"].isna()].copy()
violation_raw["NON_COMPL_PER_END_DATE"] = np.where(
    violation_raw["NON_COMPL_PER_END_DATE"] == "--->",
    "12-31-2024",
    violation_raw["NON_COMPL_PER_END_DATE"]
)

# Deduplicate by violation identity
violation_raw = violation_raw.drop_duplicates(
    subset=["PWSID", "VIOLATION_ID", "NON_COMPL_PER_BEGIN_DATE", "NON_COMPL_PER_END_DATE"]
)

# One-hot encode violation category and rule code
violation_raw = pd.get_dummies(violation_raw, columns=["VIOLATION_CATEGORY_CODE"], dummy_na=True, dtype=int)
violation_raw = pd.get_dummies(violation_raw, columns=["RULE_CODE"],               dummy_na=True, dtype=int)

# Map rule codes to contaminant indicators (mirrors existing pipeline)
def flag_contam(df, colname, rule_codes):
    df[colname] = 0
    for rc in rule_codes:
        col = f"RULE_CODE_{rc}"
        if col in df.columns:
            df.loc[df[col] == 1, colname] = 1
    return df

violation_raw = flag_contam(violation_raw, "nitrates",                  ["331.0"])
violation_raw = flag_contam(violation_raw, "arsenic",                   ["332.0"])
violation_raw = flag_contam(violation_raw, "inorganic_chemicals",       ["333.0"])
violation_raw = flag_contam(violation_raw, "radionuclides",             ["340.0"])
violation_raw = flag_contam(violation_raw, "lead_copper_rule",          ["350.0"])
violation_raw = flag_contam(violation_raw, "total_coliform",            ["110.0", "111.0"])
violation_raw = flag_contam(violation_raw, "surface_ground_water_rule", ["121.0", "122.0", "123.0", "140.0"])
violation_raw = flag_contam(violation_raw, "dbpr",                      ["210.0", "220.0", "230.0"])
violation_raw = flag_contam(violation_raw, "voc",                       ["310.0"])
violation_raw = flag_contam(violation_raw, "soc",                       ["320.0"])

VIO_CONTAM = ["nitrates", "arsenic", "inorganic_chemicals", "radionuclides", "lead_copper_rule",
              "total_coliform", "surface_ground_water_rule", "dbpr", "voc", "soc"]

# Expand violations to one row per calendar year they span (year_share logic)
def year_share_expand(df):
    df = df.copy()
    df["NON_COMPL_PER_BEGIN_DATE"] = pd.to_datetime(df["NON_COMPL_PER_BEGIN_DATE"], format="mixed")
    df["NON_COMPL_PER_END_DATE"]   = pd.to_datetime(df["NON_COMPL_PER_END_DATE"],   format="mixed", errors="coerce")
    df = df.dropna(subset=["NON_COMPL_PER_END_DATE"])

    rows = []
    for _, r in df.iterrows():
        start, end = r["NON_COMPL_PER_BEGIN_DATE"], r["NON_COMPL_PER_END_DATE"]
        s_yr, e_yr = start.year, end.year
        for yr in range(s_yr, e_yr + 1):
            if s_yr == e_yr:
                share = (end - start).days / 365
            elif yr == s_yr:
                share = (pd.Timestamp(f"{yr}-12-31") - start).days / 365
            elif yr == e_yr:
                share = ((end - pd.Timestamp(f"{yr}-01-01")).days + 1) / 365
            else:
                share = 1.0
            row = r.to_dict()
            row["share_yr_violation"] = share
            row["year"] = yr
            rows.append(row)
    return pd.DataFrame(rows)

print(f"  Running year_share on {len(violation_raw)} rows...")
violation_yr = year_share_expand(violation_raw)
violation_yr = violation_yr[violation_yr["share_yr_violation"] >= 0]

# Ensure MCL/MR/TT dummy columns exist
for cat_col in ["VIOLATION_CATEGORY_CODE_MCL", "VIOLATION_CATEGORY_CODE_MR",
                "VIOLATION_CATEGORY_CODE_TT"]:
    if cat_col not in violation_yr.columns:
        violation_yr[cat_col] = 0

# Compute share variables
for vv in VIO_CONTAM:
    violation_yr[f"{vv}_share"]     = violation_yr[vv] * violation_yr["share_yr_violation"]
    violation_yr[f"{vv}_MCL_share"] = violation_yr[f"{vv}_share"] * violation_yr["VIOLATION_CATEGORY_CODE_MCL"]
    violation_yr[f"{vv}_MR_share"]  = violation_yr[f"{vv}_share"] * violation_yr["VIOLATION_CATEGORY_CODE_MR"]
    violation_yr[f"{vv}_TT_share"]  = violation_yr[f"{vv}_share"] * violation_yr["VIOLATION_CATEGORY_CODE_TT"]

# Collapse to PWSID × year (max share within year = worst violation)
share_cols = [c for c in violation_yr.columns if c.endswith("_share")]
vio_agg = (
    violation_yr.groupby(["PWSID", "year"])
    .agg(**{c: (c, "max") for c in share_cols})
    .reset_index()
)

# Convert shares to days
for sc in share_cols:
    vio_agg[f"{sc}_days"] = vio_agg[sc] * 365

print(f"  PWSID×year violation rows: {len(vio_agg)}")

# ── Step 5: Build PWSID × year panel ──────────────────────────────────────
print("Step 5: Building PWSID×year panel...")

# CWS characteristics from PUB_WATER_SYSTEMS
water_sys = pd.read_csv(SDWA_DIR / "SDWA_PUB_WATER_SYSTEMS.csv", low_memory=False)
water_sys = water_sys[(water_sys["PWS_TYPE_CODE"] == "CWS") &
                      (water_sys["PWSID"].isin(cws_2step_pure))]
water_sys["PWS_DEACTIVATION_DATE"] = pd.to_datetime(water_sys["PWS_DEACTIVATION_DATE"], errors="coerce")
water_sys = water_sys[
    (water_sys["PWS_DEACTIVATION_DATE"] >= "1983-01-01") |
    (water_sys["PWS_DEACTIVATION_DATE"].isna())
]
water_sys = water_sys[["PWSID", "STATE_CODE", "POPULATION_SERVED_COUNT",
                        "OWNER_TYPE_CODE", "PRIMARY_SOURCE_CODE"]].drop_duplicates("PWSID")

# Facilities for num_facilities per PWSID × year
facilities = pd.read_csv(SDWA_DIR / "SDWA_FACILITIES.csv", low_memory=False)
facilities = facilities[facilities["PWSID"].isin(cws_2step_pure)].copy()
facilities["FACILITY_DEACTIVATION_DATE"] = pd.to_datetime(
    facilities["FACILITY_DEACTIVATION_DATE"], errors="coerce"
)

df_years = pd.DataFrame({"year": list(range(1983, 2025))})
fac_yr = facilities.merge(df_years, how="cross")
fac_yr["year_deact"] = fac_yr["FACILITY_DEACTIVATION_DATE"].dt.year
fac_yr = fac_yr[~(fac_yr["year_deact"] < fac_yr["year"])]
num_fac = (
    fac_yr.groupby(["PWSID", "year"])["FACILITY_ID"]
    .count()
    .reset_index()
    .rename(columns={"FACILITY_ID": "num_facilities"})
)

# Full PWSID × year skeleton
cws_df = pd.DataFrame({"PWSID": list(cws_2step_pure)})
panel  = cws_df.merge(df_years, how="cross")
panel  = panel.merge(water_sys, on="PWSID", how="left")
panel  = panel.merge(num_fac,   on=["PWSID", "year"], how="left")
panel["num_facilities"] = panel["num_facilities"].fillna(1)

# Average coal characteristics across all D2 intakes per PWSID × year
pwsid_coal = (
    pwsid_huc.merge(d2_chars, on="huc12", how="left")
    .groupby(["PWSID", "year"])
    .agg(
        sulfur_colocated=("sulfur_colocated",                     "mean"),
        sulfur_upstream=("sulfur_upstream",                       "mean"),
        sulfur_unified=("sulfur_unified",                         "mean"),
        btu_colocated=("btu_colocated",                           "mean"),
        btu_upstream=("btu_upstream",                             "mean"),
        btu_unified=("btu_unified",                               "mean"),
        num_coal_mines_colocated=("num_coal_mines_colocated",     "mean"),
        num_coal_mines_upstream=("num_coal_mines_upstream",       "mean"),
        num_coal_mines_unified=("num_coal_mines_unified",         "mean"),
        production_short_tons_coal_colocated=("production_short_tons_coal_colocated", "mean"),
        production_short_tons_coal_upstream=("production_short_tons_coal_upstream",   "mean"),
        production_short_tons_coal_unified=("production_short_tons_coal_unified",     "mean"),
    )
    .reset_index()
)

panel = panel.merge(pwsid_coal, on=["PWSID", "year"], how="left")
panel = panel.merge(vio_agg,   on=["PWSID", "year"], how="left")

# minehuc indicators
panel["minehuc_downstream_of_mine"]       = 1
panel["minehuc_downstream_of_mine_2step"] = 1
panel["minehuc_mine"]                     = 0
panel["minehuc_upstream_of_mine"]         = 0
panel["minehuc_nan"]                      = 0
panel["post95"] = (panel["year"] >= 1995).astype(int)

# Fill missing violation outcomes with 0 then apply pre-rule NaN encoding
vio_out_cols = [c for c in panel.columns
                if any(c.startswith(vv) for vv in VIO_CONTAM)]
panel[vio_out_cols] = panel[vio_out_cols].fillna(0)

tc_cols   = [c for c in panel.columns if c.startswith("total_coliform")]
voc_cols  = [c for c in panel.columns if c.startswith("voc")]
soc_cols  = [c for c in panel.columns if c.startswith("soc")]
sgwr_cols = [c for c in panel.columns if c.startswith("surface_ground_water_rule")]
panel.loc[panel["year"] < 1991, tc_cols]   = np.nan
panel.loc[panel["year"] < 1990, voc_cols]  = np.nan
panel.loc[panel["year"] < 1987, soc_cols]  = np.nan
panel.loc[panel["year"] < 1990, sgwr_cols] = np.nan

# Schema enforcement for cross-language parquet read
panel["PWSID"] = panel["PWSID"].astype(str)
panel["year"]  = panel["year"].astype("int64")

print(f"  Final panel: {len(panel):,} rows × {panel.shape[1]} columns")
print(panel.dtypes)

# ── Write output ──────────────────────────────────────────────────────────
if OUT_PATH.exists():
    print(f"WARNING: {OUT_PATH} already exists — overwriting")

panel.to_parquet(str(OUT_PATH), index=False, engine="pyarrow")

result = pd.read_parquet(str(OUT_PATH), engine="pyarrow")
print(f"\nWritten {len(result):,} rows × {result.shape[1]} columns to {OUT_PATH}")
print(f"  2-step CWSs:            {result['PWSID'].nunique()}")
print(f"  sulfur_unified > 0:     {(result['sulfur_unified'].fillna(0) > 0).sum()}")
mcl_check = "nitrates_MCL_share_days"
if mcl_check in result.columns:
    print(f"  Nitrates MCL vio rows:  {(result[mcl_check] > 0).sum()}")
