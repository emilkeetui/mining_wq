# ============================================================
# Script: build_placebo_downstream_intake.py
# Purpose: Build PWSID x year panel for the downstream-of-intake placebo test.
#          Placebo treatment = coal mines located in the HUC12 immediately
#          DOWNSTREAM of a CWS intake (mine is one flow-step below the intake).
#          Contamination cannot flow upstream, so these mines cannot affect
#          the CWS's water; this is minehuc_upstream_of_mine==1 geography in
#          the existing classification, but all new columns use the
#          _downstream_intake suffix to avoid confusion with
#          minehuc_downstream_of_mine (CWS downstream of mine = treated group).
# Inputs:
#   clean_data/huc_coal_charac_geom_match.csv  (minehuc classification + sulfur_colocated)
#   clean_data/coal_huc_prod.csv               (mine HUC x year production)
#   Z:/ek559/sdwa_violations/WBD_HUC12_CONUS_pulled10262020/*.shp  (HUC flow network)
#   Z:/ek559/water_instrument/cws_intake_hucs/PWS_Loctations_HUC12_A_I_2022Q2.xlsx
#   Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.csv
#   Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_PUB_WATER_SYSTEMS.csv
#   Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_FACILITIES.csv
# Outputs:
#   clean_data/cws_data/prod_vio_sulfur_placebo_downstream_intake.parquet
# Author: EK  Date: 2026-08-28
# ============================================================

import pandas as pd
import geopandas as gpd
import numpy as np
from pathlib import Path

ROOT      = Path("Z:/ek559/mining_wq")
HUC_SHP   = Path("Z:/ek559/sdwa_violations/WBD_HUC12_CONUS_pulled10262020/WBD_HUC12_CONUS_pulled10262020.shp")
INTAKE_XL = Path("Z:/ek559/water_instrument/cws_intake_hucs/PWS_Loctations_HUC12_A_I_2022Q2.xlsx")
SDWA_DIR  = Path("Z:/ek559/sdwa_violations/SDWA_latest_downloads")
OUT_PATH  = ROOT / "clean_data/cws_data/prod_vio_sulfur_placebo_downstream_intake.parquet"

# ── Step 1a: Build the intake -> downstream-mine HUC linkage ─────────────
print("Step 1a: Identifying intakes with a mine HUC immediately downstream...")

huc_csv = pd.read_csv(
    ROOT / "clean_data/huc_coal_charac_geom_match.csv",
    dtype={"huc12": str, "fromhuc": str, "tohuc": str}
)

mine_hucs     = set(huc_csv.loc[huc_csv["minehuc"] == "mine",               "huc12"].unique())
upstream_hucs = set(huc_csv.loc[huc_csv["minehuc"] == "upstream_of_mine",   "huc12"].unique())
d1_hucs       = set(huc_csv.loc[huc_csv["minehuc"] == "downstream_of_mine", "huc12"].unique())

print(f"  Mine HUCs: {len(mine_hucs)}  Upstream: {len(upstream_hucs)}  D1: {len(d1_hucs)}")

print("  Loading HUC shapefile for intake->mine flow links...")
huc_net = gpd.read_file(str(HUC_SHP), include_fields=["huc12", "tohuc"])
huc_net = pd.DataFrame(huc_net[["huc12", "tohuc"]]).copy()
huc_net["huc12"] = huc_net["huc12"].astype(str).str.strip()
huc_net["tohuc"] = huc_net["tohuc"].astype(str).str.strip()

# PLACEBO LINKAGE: intake HUC -> its tohuc, keep only where tohuc is a MINE HUC.
# This is the mine one step DOWNSTREAM of the intake.
intake_to_mine = (
    huc_net[huc_net["tohuc"].isin(mine_hucs)][["huc12", "tohuc"]]
    .rename(columns={"huc12": "intake_huc12", "tohuc": "mine_huc12"})
    .drop_duplicates()
)
intake_to_mine = intake_to_mine[intake_to_mine["intake_huc12"].str.len() > 0]

print(f"  intake -> downstream-mine HUC pairs: {len(intake_to_mine)}")
if len(intake_to_mine) == 0:
    raise RuntimeError("No intake HUCs with a mine HUC immediately downstream — check HUC flow network.")

# ── Step 1b: Aggregate coal characteristics to intake HUC x year ─────────
print("Step 1b: Assigning coal characteristics to downstream-mine HUCs...")

coal_prod = pd.read_csv(ROOT / "clean_data/coal_huc_prod.csv", dtype={"huc12": str})
coal_prod = coal_prod.rename(columns={"huc12": "mine_huc12"})

def _mean_nonzero(s):
    s2 = s[s != 0]
    return s2.mean() if len(s2) > 0 else 0.0

mine_sulfur = (
    huc_csv[huc_csv["minehuc"] == "mine"][["huc12", "sulfur_colocated", "btu_colocated"]]
    .drop_duplicates()
    .rename(columns={"huc12": "mine_huc12"})
    .groupby("mine_huc12")
    .agg(sulfur_colocated=("sulfur_colocated", "mean"),
         btu_colocated=("btu_colocated", "mean"))
    .reset_index()
)

chars = intake_to_mine.merge(mine_sulfur, on="mine_huc12", how="left")
chars = chars.merge(coal_prod, on="mine_huc12", how="left")   # adds year, num_coal_mines, production
chars = chars.drop_duplicates(subset=["intake_huc12", "mine_huc12", "year"])

print(f"  intake_huc12 x mine_huc12 x year rows with coal data: {len(chars)}")

# ── Step 1c/1d: Map to PWSID, dedup mine HUCs, apply placebo sample exclusions ──
print("Step 1c: Identifying downstream-of-intake placebo CWSs via intake file...")

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

# Step 1d: sample exclusions — keep a CWS only if it has NO real mining exposure.
cws_placebo = set(intake.loc[intake["huc12"].isin(set(intake_to_mine["intake_huc12"])), "PWSID"].unique())
cws_in_mine = set(intake.loc[intake["huc12"].isin(mine_hucs), "PWSID"].unique())
cws_in_d1   = set(intake.loc[intake["huc12"].isin(d1_hucs),   "PWSID"].unique())
cws_placebo_pure = cws_placebo - cws_in_mine - cws_in_d1

print(f"  Placebo CWSs (before exclusions): {len(cws_placebo)}")
print(f"  Placebo CWSs (after exclusions):  {len(cws_placebo_pure)}")

if len(cws_placebo_pure) == 0:
    raise RuntimeError("No downstream-of-intake placebo CWSs found after exclusions — check HUC flow network.")

# PWSID -> intake_huc12 lookup, restricted to placebo CWSs and their linked intakes
pwsid_huc = (
    intake[intake["PWSID"].isin(cws_placebo_pure) & intake["huc12"].isin(set(intake_to_mine["intake_huc12"]))]
    [["PWSID", "huc12"]].rename(columns={"huc12": "intake_huc12"}).drop_duplicates()
)

# Unique (PWSID, mine_huc12) pairs — a mine reachable from two of a system's
# intakes is counted once in the _sum aggregates.
pws_mine = (
    pwsid_huc.merge(intake_to_mine, on="intake_huc12", how="inner")
    [["PWSID", "mine_huc12"]]
    .drop_duplicates()
)
mines_sum_df = (
    pws_mine.merge(coal_prod, on="mine_huc12", how="left")
    .groupby(["PWSID", "year"], as_index=False)
    .agg(num_coal_mines_downstream_intake_sum=("num_coal_mines", "sum"),
         production_short_tons_coal_downstream_intake_sum=("production_short_tons_coal", "sum"))
)
sulfur_sum_df = (
    pws_mine.merge(mine_sulfur, on="mine_huc12", how="left")
    .pipe(lambda d: d[d["sulfur_colocated"].fillna(0) != 0])
    .groupby(["PWSID"], as_index=False)
    .agg(sulfur_downstream_intake_sum=("sulfur_colocated", "mean"))
)

# ── Step 1e: Violation data for placebo CWSs ──────────────────────────────
print("Step 1e: Loading violation data for placebo CWSs (chunked read)...")

vio_cols = ["PWSID", "VIOLATION_ID", "NON_COMPL_PER_BEGIN_DATE",
            "NON_COMPL_PER_END_DATE", "RULE_CODE", "RULE_FAMILY_CODE",
            "VIOLATION_CATEGORY_CODE", "IS_MAJOR_VIOL_IND"]

vio_chunks = []
for chunk in pd.read_csv(
    SDWA_DIR / "SDWA_VIOLATIONS_ENFORCEMENT.csv",
    low_memory=False, chunksize=200_000, usecols=vio_cols
):
    filtered = chunk[chunk["PWSID"].isin(cws_placebo_pure)]
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

# Collapse to PWSID x year (max share within year = worst violation)
share_cols = [c for c in violation_yr.columns if c.endswith("_share")]
vio_agg = (
    violation_yr.groupby(["PWSID", "year"])
    .agg(**{c: (c, "max") for c in share_cols})
    .reset_index()
)

# Convert shares to days
for sc in share_cols:
    vio_agg[f"{sc}_days"] = vio_agg[sc] * 365

print(f"  PWSID x year violation rows: {len(vio_agg)}")

# ── Panel assembly ─────────────────────────────────────────────────────────
print("Building PWSID x year panel...")

# CWS characteristics from PUB_WATER_SYSTEMS
water_sys = pd.read_csv(SDWA_DIR / "SDWA_PUB_WATER_SYSTEMS.csv", low_memory=False)
water_sys = water_sys[(water_sys["PWS_TYPE_CODE"] == "CWS") &
                      (water_sys["PWSID"].isin(cws_placebo_pure))]
water_sys["PWS_DEACTIVATION_DATE"] = pd.to_datetime(water_sys["PWS_DEACTIVATION_DATE"], errors="coerce")
water_sys = water_sys[
    (water_sys["PWS_DEACTIVATION_DATE"] >= "1983-01-01") |
    (water_sys["PWS_DEACTIVATION_DATE"].isna())
]
water_sys = water_sys[["PWSID", "STATE_CODE", "POPULATION_SERVED_COUNT",
                        "OWNER_TYPE_CODE", "PRIMARY_SOURCE_CODE"]].drop_duplicates("PWSID")

# Facilities for num_facilities per PWSID x year
facilities = pd.read_csv(SDWA_DIR / "SDWA_FACILITIES.csv", low_memory=False)
facilities = facilities[facilities["PWSID"].isin(cws_placebo_pure)].copy()
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

# Full PWSID x year skeleton
cws_df = pd.DataFrame({"PWSID": list(cws_placebo_pure)})
panel  = cws_df.merge(df_years, how="cross")
panel  = panel.merge(water_sys, on="PWSID", how="left")
panel  = panel.merge(num_fac,   on=["PWSID", "year"], how="left")
panel["num_facilities"] = panel["num_facilities"].fillna(1)

panel = panel.merge(mines_sum_df,  on=["PWSID", "year"], how="left")
panel = panel.merge(sulfur_sum_df, on=["PWSID"],         how="left")
panel = panel.merge(vio_agg,       on=["PWSID", "year"], how="left")

# minehuc indicators reflecting placebo geography (CWS is upstream of the mine)
panel["minehuc_upstream_of_mine"]   = 1
panel["minehuc_mine"]               = 0
panel["minehuc_downstream_of_mine"] = 0
panel["post95"] = (panel["year"] >= 1995).astype(int)
panel["num_coal_mines_downstream_intake_sum"] = panel["num_coal_mines_downstream_intake_sum"].fillna(0)
panel["production_short_tons_coal_downstream_intake_sum"] = panel["production_short_tons_coal_downstream_intake_sum"].fillna(0)

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

print(f"  Final panel: {len(panel):,} rows x {panel.shape[1]} columns")
print(panel.dtypes)

# ── Write output ──────────────────────────────────────────────────────────
if OUT_PATH.exists():
    print(f"WARNING: {OUT_PATH} already exists — overwriting")

panel.to_parquet(str(OUT_PATH), index=False, engine="pyarrow")

result = pd.read_parquet(str(OUT_PATH), engine="pyarrow")
print(f"\nWritten {len(result):,} rows x {result.shape[1]} columns to {OUT_PATH}")
print(f"  Placebo CWSs:                          {result['PWSID'].nunique()}")
print(f"  sulfur_downstream_intake_sum > 0 rows: {(result['sulfur_downstream_intake_sum'].fillna(0) > 0).sum()}")
mcl_check = "nitrates_MCL_share_days"
if mcl_check in result.columns:
    print(f"  Nitrates MCL vio rows:  {(result[mcl_check] > 0).sum()}")

# Gate: fail loudly rather than silently proceeding to Step 2 with a broken sample.
if result["PWSID"].nunique() < 100:
    raise RuntimeError(
        f"Placebo panel has only {result['PWSID'].nunique()} CWSs (< 100) — stop and report."
    )
if (result["sulfur_downstream_intake_sum"].fillna(0) > 0).sum() == 0:
    raise RuntimeError("Placebo panel has zero rows with sulfur_downstream_intake_sum > 0 — stop and report.")
