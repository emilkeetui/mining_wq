# ============================================================
# Script: build_4step_sample.py
# Purpose: Build PWSID×year panel for CWSs whose intake HUC12 is at most
#          4 steps downstream of a coal mine HUC12 (D1–D4). Produces
#          prod_vio_sulfur_4step.parquet with the same column schema as
#          prod_vio_sulfur_2step.parquet, plus downstream_step (1–4) and
#          minehuc_downstream_of_mine_4step=1.
# Inputs:
#   clean_data/huc_coal_charac_geom_match.csv  (mine/D1 HUC linkages)
#   clean_data/coal_huc_prod.csv               (mine HUC × year production)
#   Z:/ek559/sdwa_violations/WBD_HUC12_CONUS_pulled10262020/*.shp
#   Z:/ek559/water_instrument/cws_intake_hucs/PWS_Loctations_HUC12_A_I_2022Q2.xlsx
#   Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.csv
#   Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_PUB_WATER_SYSTEMS.csv
#   Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_FACILITIES.csv
# Outputs:
#   clean_data/cws_data/prod_vio_sulfur_4step.parquet
# Author: EK  Date: 2026-04-27
# ============================================================

import pandas as pd
import geopandas as gpd
import numpy as np
from pathlib import Path

ROOT      = Path("Z:/ek559/mining_wq")
HUC_SHP   = Path("Z:/ek559/sdwa_violations/WBD_HUC12_CONUS_pulled10262020/WBD_HUC12_CONUS_pulled10262020.shp")
INTAKE_XL = Path("Z:/ek559/water_instrument/cws_intake_hucs/PWS_Loctations_HUC12_A_I_2022Q2.xlsx")
SDWA_DIR  = Path("Z:/ek559/sdwa_violations/SDWA_latest_downloads")
OUT_PATH  = ROOT / "clean_data/cws_data/prod_vio_sulfur_4step.parquet"

MAX_STEPS = 4

# ── Step 1: Build HUC chain D1 → D2 → D3 → D4 ───────────────────────────────
print("Step 1: Building downstream HUC chain D1–D4...")

huc_csv = pd.read_csv(
    ROOT / "clean_data/huc_coal_charac_geom_match.csv",
    dtype={"huc12": str, "fromhuc": str, "tohuc": str}
)

mine_hucs     = set(huc_csv.loc[huc_csv["minehuc"] == "mine",              "huc12"].unique())
upstream_hucs = set(huc_csv.loc[huc_csv["minehuc"] == "upstream_of_mine",  "huc12"].unique())
d1_hucs       = set(huc_csv.loc[huc_csv["minehuc"] == "downstream_of_mine","huc12"].unique())

print(f"  Mine: {len(mine_hucs)}  Upstream: {len(upstream_hucs)}  D1: {len(d1_hucs)}")

# D1 → mine mapping (fromhuc in CSV identifies the mine HUC feeding each D1)
d1_mine = (
    huc_csv[huc_csv["minehuc"] == "downstream_of_mine"][["huc12", "fromhuc"]]
    .rename(columns={"huc12": "D1_huc12", "fromhuc": "mine_huc12"})
    .drop_duplicates()
)

# Load HUC flow network
print("  Loading HUC shapefile for flow network...")
huc_net = gpd.read_file(str(HUC_SHP), columns=["huc12", "tohuc"])
huc_net = pd.DataFrame(huc_net[["huc12", "tohuc"]]).copy()
huc_net["huc12"] = huc_net["huc12"].astype(str).str.strip()
huc_net["tohuc"] = huc_net["tohuc"].astype(str).str.strip()
huc_map = dict(zip(huc_net["huc12"], huc_net["tohuc"]))

# step_hucs[k] = set of HUC12s that are exactly k steps downstream
step_hucs = {1: d1_hucs}
# step_mine[k] = DataFrame with cols (Dk_huc12, mine_huc12) for coal char lookup
step_mine = {1: d1_mine.rename(columns={"D1_huc12": "Dk_huc12"})}

all_classified = mine_hucs | upstream_hucs | d1_hucs

for k in range(2, MAX_STEPS + 1):
    prev_hucs = step_hucs[k - 1]
    prev_mine = step_mine[k - 1]  # cols: Dk_huc12 (= D(k-1)), mine_huc12

    # Each D(k-1) HUC flows to a D(k) HUC via tohuc
    prev_to_curr = (
        huc_net[huc_net["huc12"].isin(prev_hucs)][["huc12", "tohuc"]]
        .rename(columns={"huc12": "prev_huc12", "tohuc": "Dk_huc12"})
        .dropna(subset=["Dk_huc12"])
    )
    prev_to_curr = prev_to_curr[prev_to_curr["Dk_huc12"].str.len() > 0]
    prev_to_curr = prev_to_curr[~prev_to_curr["Dk_huc12"].isin(all_classified)]

    dk_hucs = set(prev_to_curr["Dk_huc12"].unique())
    step_hucs[k] = dk_hucs
    all_classified |= dk_hucs

    # Propagate mine linkage: D(k-1) → mine, now via Dk → D(k-1) → mine
    dk_mine = (
        prev_to_curr
        .merge(
            prev_mine.rename(columns={"Dk_huc12": "prev_huc12"}),
            on="prev_huc12"
        )[["Dk_huc12", "mine_huc12"]]
        .drop_duplicates()
    )
    step_mine[k] = dk_mine

    print(f"  D{k} HUCs: {len(dk_hucs)}")

# ── Step 2: Coal characteristics per Dk × year ───────────────────────────────
print("Step 2: Assigning coal characteristics per step...")

coal_prod = pd.read_csv(ROOT / "clean_data/coal_huc_prod.csv", dtype={"huc12": str})
coal_prod = coal_prod.rename(columns={"huc12": "mine_huc12"})

mine_sulfur = (
    huc_csv[huc_csv["minehuc"] == "mine"][["huc12", "sulfur_colocated", "btu_colocated"]]
    .drop_duplicates()
    .rename(columns={"huc12": "mine_huc12"})
    .groupby("mine_huc12")
    .agg(sulfur_colocated=("sulfur_colocated", "mean"),
         btu_colocated=("btu_colocated", "mean"))
    .reset_index()
)

step_chars = {}  # step_chars[k] = DataFrame (huc12, year, coal cols...)

for k in range(1, MAX_STEPS + 1):
    dm = step_mine[k].copy()  # cols: Dk_huc12, mine_huc12
    dm = dm.merge(mine_sulfur, on="mine_huc12", how="left")
    dm = dm.merge(coal_prod, on="mine_huc12", how="left")

    chars = (
        dm.groupby(["Dk_huc12", "year"])
        .agg(
            sulfur_upstream=("sulfur_colocated",             "mean"),
            btu_upstream=("btu_colocated",                   "mean"),
            num_coal_mines_upstream=("num_coal_mines",       "mean"),
            production_short_tons_coal_upstream=("production_short_tons_coal", "mean"),
        )
        .reset_index()
        .rename(columns={"Dk_huc12": "huc12"})
    )

    chars["sulfur_colocated"]                     = 0.0
    chars["btu_colocated"]                        = 0.0
    chars["num_coal_mines_colocated"]             = 0.0
    chars["production_short_tons_coal_colocated"] = 0.0
    chars["sulfur_unified"]                       = chars["sulfur_upstream"]
    chars["btu_unified"]                          = chars["btu_upstream"]
    chars["num_coal_mines_unified"]               = chars["num_coal_mines_upstream"]
    chars["production_short_tons_coal_unified"]   = chars["production_short_tons_coal_upstream"]
    chars["post95"]                               = (chars["year"] >= 1995).astype(int)

    step_chars[k] = chars
    print(f"  D{k}: {len(chars):,} huc×year rows with coal data")

# ── Step 3: Identify downstream CWSs per step (non-overlapping) ──────────────
print("Step 3: Identifying downstream CWSs per step...")

intake = pd.read_excel(
    INTAKE_XL, dtype={"HUC_12": str, "FACILITY_ID": str}
)[["PWSID", "FACILITY_ID", "HUC_12"]].rename(columns={"HUC_12": "huc12"}).drop_duplicates()
intake["huc12"] = intake["huc12"].astype(str).str.strip()

pws_type = pd.read_csv(SDWA_DIR / "SDWA_PUB_WATER_SYSTEMS.csv", low_memory=False,
                       usecols=["PWSID", "PWS_TYPE_CODE"])
cws_pwsids = set(pws_type.loc[pws_type["PWS_TYPE_CODE"] == "CWS", "PWSID"].unique())
intake = intake[intake["PWSID"].isin(cws_pwsids)]

cws_mine_up = set(intake.loc[intake["huc12"].isin(mine_hucs | upstream_hucs), "PWSID"].unique())

assigned_pwsids = set()
step_cws     = {}   # step_cws[k]     = set of pure CWS PWSIDs for step k
step_pwsid_huc = {} # step_pwsid_huc[k] = DataFrame (PWSID, huc12)

for k in range(1, MAX_STEPS + 1):
    in_dk = set(intake.loc[intake["huc12"].isin(step_hucs[k]), "PWSID"].unique())
    pure  = in_dk - cws_mine_up - assigned_pwsids
    step_cws[k] = pure
    assigned_pwsids |= pure

    step_pwsid_huc[k] = (
        intake[intake["PWSID"].isin(pure) & intake["huc12"].isin(step_hucs[k])]
        [["PWSID", "huc12"]].drop_duplicates()
    )
    print(f"  D{k}: {len(pure)} CWSs")

all_downstream = assigned_pwsids
print(f"  Total D1–D4 CWSs: {len(all_downstream)}")

# ── Step 4: Violation data for all downstream CWSs ───────────────────────────
print("Step 4: Loading violation data (chunked read)...")

vio_cols = ["PWSID", "VIOLATION_ID", "NON_COMPL_PER_BEGIN_DATE",
            "NON_COMPL_PER_END_DATE", "RULE_CODE", "RULE_FAMILY_CODE",
            "VIOLATION_CATEGORY_CODE", "IS_HEALTH_BASED_IND", "IS_MAJOR_VIOL_IND"]

vio_chunks = []
for chunk in pd.read_csv(
    SDWA_DIR / "SDWA_VIOLATIONS_ENFORCEMENT.csv",
    low_memory=False, chunksize=200_000, usecols=vio_cols
):
    filtered = chunk[chunk["PWSID"].isin(all_downstream)]
    if len(filtered) > 0:
        vio_chunks.append(filtered)

violation_raw = pd.concat(vio_chunks, ignore_index=True) if vio_chunks else pd.DataFrame(columns=vio_cols)
print(f"  Raw violation rows: {len(violation_raw)}")

violation_raw = violation_raw[~violation_raw["NON_COMPL_PER_BEGIN_DATE"].isna()].copy()
violation_raw["NON_COMPL_PER_END_DATE"] = np.where(
    violation_raw["NON_COMPL_PER_END_DATE"] == "--->",
    "12-31-2024",
    violation_raw["NON_COMPL_PER_END_DATE"]
)
violation_raw = violation_raw.drop_duplicates(
    subset=["PWSID", "VIOLATION_ID", "NON_COMPL_PER_BEGIN_DATE", "NON_COMPL_PER_END_DATE"]
)

violation_raw["health_based"] = (violation_raw["IS_HEALTH_BASED_IND"].fillna("N") == "Y").astype(int)

violation_raw = pd.get_dummies(violation_raw, columns=["VIOLATION_CATEGORY_CODE"], dummy_na=True, dtype=int)
violation_raw = pd.get_dummies(violation_raw, columns=["RULE_CODE"],               dummy_na=True, dtype=int)


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

for cat_col in ["VIOLATION_CATEGORY_CODE_MCL", "VIOLATION_CATEGORY_CODE_MR",
                "VIOLATION_CATEGORY_CODE_TT"]:
    if cat_col not in violation_yr.columns:
        violation_yr[cat_col] = 0

for vv in VIO_CONTAM:
    violation_yr[f"{vv}_share"]        = violation_yr[vv] * violation_yr["share_yr_violation"]
    violation_yr[f"{vv}_MCL_share"]    = violation_yr[f"{vv}_share"] * violation_yr["VIOLATION_CATEGORY_CODE_MCL"]
    violation_yr[f"{vv}_MR_share"]     = violation_yr[f"{vv}_share"] * violation_yr["VIOLATION_CATEGORY_CODE_MR"]
    violation_yr[f"{vv}_TT_share"]     = violation_yr[f"{vv}_share"] * violation_yr["VIOLATION_CATEGORY_CODE_TT"]
    violation_yr[f"{vv}_health_share"] = violation_yr[f"{vv}_share"] * violation_yr["health_based"]

share_cols = [c for c in violation_yr.columns if c.endswith("_share")]
vio_agg = (
    violation_yr.groupby(["PWSID", "year"])
    .agg(**{c: (c, "max") for c in share_cols})
    .reset_index()
)
for sc in share_cols:
    vio_agg[f"{sc}_days"] = vio_agg[sc] * 365

print(f"  PWSID×year violation rows: {len(vio_agg)}")

# ── Step 5: Build per-step panels and concatenate ────────────────────────────
print("Step 5: Building PWSID×year panels per step...")

water_sys = pd.read_csv(SDWA_DIR / "SDWA_PUB_WATER_SYSTEMS.csv", low_memory=False)
water_sys = water_sys[(water_sys["PWS_TYPE_CODE"] == "CWS") &
                      (water_sys["PWSID"].isin(all_downstream))]
water_sys["PWS_DEACTIVATION_DATE"] = pd.to_datetime(water_sys["PWS_DEACTIVATION_DATE"], errors="coerce")
water_sys = water_sys[
    (water_sys["PWS_DEACTIVATION_DATE"] >= "1983-01-01") |
    (water_sys["PWS_DEACTIVATION_DATE"].isna())
]
water_sys = water_sys[["PWSID", "STATE_CODE", "POPULATION_SERVED_COUNT",
                        "OWNER_TYPE_CODE", "PRIMARY_SOURCE_CODE"]].drop_duplicates("PWSID")

facilities = pd.read_csv(SDWA_DIR / "SDWA_FACILITIES.csv", low_memory=False)
facilities = facilities[facilities["PWSID"].isin(all_downstream)].copy()
facilities["FACILITY_DEACTIVATION_DATE"] = pd.to_datetime(
    facilities["FACILITY_DEACTIVATION_DATE"], errors="coerce"
)
df_years = pd.DataFrame({"year": list(range(1983, 2025))})
fac_yr = facilities.merge(df_years, how="cross")
fac_yr["year_deact"] = fac_yr["FACILITY_DEACTIVATION_DATE"].dt.year
fac_yr = fac_yr[~(fac_yr["year_deact"] < fac_yr["year"])]
num_fac = (
    fac_yr.groupby(["PWSID", "year"])["FACILITY_ID"]
    .count().reset_index()
    .rename(columns={"FACILITY_ID": "num_facilities"})
)

step_panels = []

for k in range(1, MAX_STEPS + 1):
    cws_k = step_cws[k]
    if len(cws_k) == 0:
        continue

    panel = pd.DataFrame({"PWSID": list(cws_k)}).merge(df_years, how="cross")
    panel = panel.merge(water_sys, on="PWSID", how="left")
    panel = panel.merge(num_fac,   on=["PWSID", "year"], how="left")
    panel["num_facilities"] = panel["num_facilities"].fillna(1)

    # Average coal characteristics across all Dk intakes per PWSID × year
    pwsid_coal = (
        step_pwsid_huc[k]
        .merge(step_chars[k], on="huc12", how="left")
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

    panel["downstream_step"]                      = k
    panel["minehuc_downstream_of_mine"]           = 1
    panel["minehuc_downstream_of_mine_4step"]     = 1
    panel["minehuc_mine"]                         = 0
    panel["minehuc_upstream_of_mine"]             = 0
    panel["minehuc_nan"]                          = 0
    panel["post95"] = (panel["year"] >= 1995).astype(int)

    step_panels.append(panel)
    print(f"  D{k}: {len(panel):,} PWSID×year rows")

final_panel = pd.concat(step_panels, ignore_index=True)

# ── Step 6: Violation outcome cleanup and pre-rule NaN encoding ───────────────
vio_out_cols = [c for c in final_panel.columns
                if any(c.startswith(vv) for vv in VIO_CONTAM)]
final_panel[vio_out_cols] = final_panel[vio_out_cols].fillna(0)

tc_cols   = [c for c in final_panel.columns if c.startswith("total_coliform")]
voc_cols  = [c for c in final_panel.columns if c.startswith("voc")]
soc_cols  = [c for c in final_panel.columns if c.startswith("soc")]
sgwr_cols = [c for c in final_panel.columns if c.startswith("surface_ground_water_rule")]
final_panel.loc[final_panel["year"] < 1991, tc_cols]   = np.nan
final_panel.loc[final_panel["year"] < 1990, voc_cols]  = np.nan
final_panel.loc[final_panel["year"] < 1987, soc_cols]  = np.nan
final_panel.loc[final_panel["year"] < 1990, sgwr_cols] = np.nan

# Schema enforcement
final_panel["PWSID"] = final_panel["PWSID"].astype(str)
final_panel["year"]  = final_panel["year"].astype("int64")

print(f"\n  Final panel: {len(final_panel):,} rows × {final_panel.shape[1]} columns")
print(final_panel.dtypes)

# ── Write output ──────────────────────────────────────────────────────────────
if OUT_PATH.exists():
    print(f"WARNING: {OUT_PATH} already exists — overwriting")

final_panel.to_parquet(str(OUT_PATH), index=False, engine="pyarrow")

result = pd.read_parquet(str(OUT_PATH), engine="pyarrow")
print(f"\nWritten {len(result):,} rows × {result.shape[1]} columns to {OUT_PATH}")
print(f"  CWSs by step: {result.groupby('downstream_step')['PWSID'].nunique().to_dict()}")
print(f"  sulfur_unified > 0: {(result['sulfur_unified'].fillna(0) > 0).sum()}")
mcl_check = "nitrates_MCL_share_days"
if mcl_check in result.columns:
    print(f"  Nitrates MCL vio rows: {(result[mcl_check] > 0).sum()}")
