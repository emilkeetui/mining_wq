# ============================================================
# Script: build_step_outcome_cache.py
# Purpose: Rebuild the visit / enforcement / violation / covariate caches
#          over the FULL 8-step universe (both main and placebo arms),
#          since the existing `_d12` caches only cover k<=2 of the main
#          arm plus the legacy D1 sample. Read-only against raw SDWA
#          sources; never touches the existing `_d12` caches or
#          prod_vio_sulfur.parquet.
# Inputs:
#   clean_data/cws_data/step_instruments.parquet   (Step 2 output; universe)
#   Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.parquet
#   Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_SITE_VISITS.csv
#   Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_FACILITIES.csv
#   Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_PUB_WATER_SYSTEMS.csv
# Outputs:
#   clean_data/cws_data/sdwa_visit_agg_steps.parquet
#   clean_data/cws_data/sdwa_enf_agg_steps.parquet
#   clean_data/cws_data/sdwa_vio_agg_steps.parquet
#   clean_data/cws_data/cws_covariates_steps.parquet
# Author: EK  Date: 2026-09-13
# ============================================================

import pandas as pd
import numpy as np
from pathlib import Path

ROOT     = Path("Z:/ek559/mining_wq")
SDWA_DIR = Path("Z:/ek559/sdwa_violations/SDWA_latest_downloads")
OUT_DIR  = ROOT / "clean_data/cws_data"

step_instr = pd.read_parquet(OUT_DIR / "step_instruments.parquet", engine="pyarrow")
eligible = step_instr[step_instr["n_mine_hucs_linked"] >= 1]
universe = sorted(eligible["PWSID"].unique())
print(f"CWS universe (>=1 mine huc linked, any arm/k, 1985-2005): {len(universe):,} PWSIDs")

if len(universe) == 0:
    raise RuntimeError("Empty CWS universe from step_instruments.parquet — stop and report.")

# ── Site visits (371 MB CSV, column-projected + PWSID-filtered) ─────────
print("\nReading SDWA_SITE_VISITS.csv (371 MB, usecols + PWSID filter)...")
sv = pd.read_csv(
    SDWA_DIR / "SDWA_SITE_VISITS.csv", low_memory=False,
    usecols=["PWSID", "VISIT_DATE", "VISIT_REASON_CODE", "AGENCY_TYPE_CODE"]
)
sv = sv[sv["PWSID"].isin(universe)].copy()
sv["VISIT_DATE"] = sv["VISIT_DATE"].astype(str).str.strip()
sv["year"] = sv["VISIT_DATE"].str[-4:]
sv = sv[sv["year"].str.isdigit()]
sv["year"] = sv["year"].astype(int)
sv = sv[(sv["year"] >= 1985) & (sv["year"] <= 2005)]
print(f"  Site visit rows in universe (1985-2005): {len(sv):,}")

sv_flags = sv.groupby(["PWSID", "year"]).agg(
    any_snsv=("VISIT_REASON_CODE", lambda s: int(s.isin(["SNSV", "SSVF"]).any())),
    any_enfvisit=("VISIT_REASON_CODE", lambda s: int(s.isin(["FENF", "INVG", "EMRG"]).any())),
).reset_index()
sv_agg = sv.groupby(["PWSID", "year"], as_index=False).size().rename(columns={"size": "n_visits"})
sv_agg = sv_agg.merge(sv_flags, on=["PWSID", "year"], how="left")

sv_agg["PWSID"] = sv_agg["PWSID"].astype(str)
sv_agg["year"]  = sv_agg["year"].astype("int64")
print(f"  Visit-aggregate PWSID-years: {len(sv_agg):,}")
sv_agg.to_parquet(str(OUT_DIR / "sdwa_visit_agg_steps.parquet"), index=False, engine="pyarrow")
del sv

# ── Violations / enforcement (306 MB parquet, projected + filtered) ─────
print("\nReading SDWA_VIOLATIONS_ENFORCEMENT.parquet (column-projected + PWSID filter)...")
vio_cols = ["PWSID", "VIOLATION_ID", "COMPL_PER_BEGIN_DATE", "NON_COMPL_PER_BEGIN_DATE",
            "NON_COMPL_PER_END_DATE", "VIOLATION_CATEGORY_CODE", "RULE_CODE",
            "ENF_ACTION_CATEGORY", "CALCULATED_RTC_DATE"]
enf_raw = pd.read_parquet(SDWA_DIR / "SDWA_VIOLATIONS_ENFORCEMENT.parquet", columns=vio_cols, engine="pyarrow")
enf_raw = enf_raw[enf_raw["PWSID"].isin(universe)].copy()
print(f"  Rows in universe: {len(enf_raw):,}")

# -- Enforcement aggregate (any_formal / any_informal) by NON_COMPL year --
enf_raw["NON_COMPL_PER_BEGIN_DATE"] = enf_raw["NON_COMPL_PER_BEGIN_DATE"].astype(str).str.strip()
enf_raw["enf_year"] = enf_raw["NON_COMPL_PER_BEGIN_DATE"].str[-4:]
enf_valid = enf_raw[enf_raw["enf_year"].str.isdigit()].copy()
enf_valid["enf_year"] = enf_valid["enf_year"].astype(int)
enf_valid = enf_valid[(enf_valid["enf_year"] >= 1985) & (enf_valid["enf_year"] <= 2005)]

enf_agg = enf_valid.groupby(["PWSID", "enf_year"]).agg(
    any_formal=("ENF_ACTION_CATEGORY", lambda s: int((s == "Formal").any())),
    any_informal=("ENF_ACTION_CATEGORY", lambda s: int((s == "Informal").any())),
).reset_index().rename(columns={"enf_year": "year"})
enf_agg["PWSID"] = enf_agg["PWSID"].astype(str)
enf_agg["year"]  = enf_agg["year"].astype("int64")
print(f"  Enforcement-aggregate PWSID-years: {len(enf_agg):,}")
enf_agg.to_parquet(str(OUT_DIR / "sdwa_enf_agg_steps.parquet"), index=False, engine="pyarrow")

# -- Binary violation outcomes (nitrates/arsenic/inorganic_chemicals x MR/MCL) --
print("\nBuilding binary violation share-day outcomes (year-share expansion)...")
vio = enf_raw.dropna(subset=["NON_COMPL_PER_BEGIN_DATE"]).copy()
vio["NON_COMPL_PER_END_DATE"] = np.where(
    vio["NON_COMPL_PER_END_DATE"].astype(str).str.strip() == "--->",
    "12-31-2024",
    vio["NON_COMPL_PER_END_DATE"]
)
vio = vio.drop_duplicates(subset=["PWSID", "VIOLATION_ID", "NON_COMPL_PER_BEGIN_DATE", "NON_COMPL_PER_END_DATE"])

rule_map = {"331.0": "nitrates", "332.0": "arsenic", "333.0": "inorganic_chemicals"}
vio["RULE_CODE"] = vio["RULE_CODE"].astype(str)
vio = vio[vio["RULE_CODE"].isin(rule_map.keys())].copy()
vio["contam"] = vio["RULE_CODE"].map(rule_map)

vio["NON_COMPL_PER_BEGIN_DATE"] = pd.to_datetime(vio["NON_COMPL_PER_BEGIN_DATE"], format="mixed", errors="coerce")
vio["NON_COMPL_PER_END_DATE"]   = pd.to_datetime(vio["NON_COMPL_PER_END_DATE"],   format="mixed", errors="coerce")
vio = vio.dropna(subset=["NON_COMPL_PER_BEGIN_DATE", "NON_COMPL_PER_END_DATE"])

def year_share_expand(df):
    starts = df["NON_COMPL_PER_BEGIN_DATE"].values
    ends   = df["NON_COMPL_PER_END_DATE"].values
    s_yr = df["NON_COMPL_PER_BEGIN_DATE"].dt.year.values
    e_yr = df["NON_COMPL_PER_END_DATE"].dt.year.values
    rows = []
    for i in range(len(df)):
        s, e, sy, ey = starts[i], ends[i], s_yr[i], e_yr[i]
        s = pd.Timestamp(s); e = pd.Timestamp(e)
        if ey < sy:
            continue
        for yr in range(sy, ey + 1):
            if sy == ey:
                share = (e - s).days / 365
            elif yr == sy:
                share = (pd.Timestamp(f"{yr}-12-31") - s).days / 365
            elif yr == ey:
                share = ((e - pd.Timestamp(f"{yr}-01-01")).days + 1) / 365
            else:
                share = 1.0
            rows.append((i, yr, share))
    exp = pd.DataFrame(rows, columns=["_idx", "year", "share_yr_violation"])
    return exp

print(f"  Expanding {len(vio):,} violation records over their year span...")
df_reset = vio.reset_index(drop=True)
exp = year_share_expand(df_reset)
exp = exp[exp["share_yr_violation"] >= 0]
exp = exp.merge(df_reset[["PWSID", "contam", "VIOLATION_CATEGORY_CODE"]], left_on="_idx", right_index=True, how="left")
exp = exp[(exp["year"] >= 1985) & (exp["year"] <= 2005)]

for cat in ["MCL", "MR"]:
    exp[f"is_{cat}"] = (exp["VIOLATION_CATEGORY_CODE"] == cat).astype(int)

vio_long_rows = []
for contam in ["nitrates", "arsenic", "inorganic_chemicals"]:
    sub = exp[exp["contam"] == contam].copy()
    if len(sub) == 0:
        continue
    sub["share_MCL_col"] = sub["share_yr_violation"] * sub["is_MCL"]
    sub["share_MR_col"]  = sub["share_yr_violation"] * sub["is_MR"]
    g = sub.groupby(["PWSID", "year"], as_index=False).agg(
        share=("share_yr_violation", "max"),
        share_MCL=("share_MCL_col", "max"),
        share_MR=("share_MR_col", "max"),
    )
    g = g.rename(columns={
        "share": f"{contam}_share_days",
        "share_MCL": f"{contam}_MCL_share_days",
        "share_MR": f"{contam}_MR_share_days",
    })
    for c in [f"{contam}_share_days", f"{contam}_MCL_share_days", f"{contam}_MR_share_days"]:
        g[c] = g[c] * 365
    vio_long_rows.append(g.set_index(["PWSID", "year"]))

vio_agg = pd.concat(vio_long_rows, axis=1, join="outer").reset_index() if vio_long_rows else pd.DataFrame(columns=["PWSID", "year"])
vio_agg["PWSID"] = vio_agg["PWSID"].astype(str)
vio_agg["year"]  = vio_agg["year"].astype("int64")
print(f"  Violation-aggregate PWSID-years: {len(vio_agg):,}")
vio_agg.to_parquet(str(OUT_DIR / "sdwa_vio_agg_steps.parquet"), index=False, engine="pyarrow")
del enf_raw, vio, exp

# ── Covariates + full PWSID x year skeleton ─────────────────────────────
print("\nBuilding covariates (num_facilities, STATE_CODE, etc.) + full skeleton...")

pws = pd.read_csv(SDWA_DIR / "SDWA_PUB_WATER_SYSTEMS.csv", low_memory=False,
                   usecols=["PWSID", "PWS_TYPE_CODE", "PWS_DEACTIVATION_DATE", "STATE_CODE",
                             "POPULATION_SERVED_COUNT", "OWNER_TYPE_CODE", "PRIMARY_SOURCE_CODE"])
pws = pws[(pws["PWS_TYPE_CODE"] == "CWS") & (pws["PWSID"].isin(universe))].copy()
pws["PWS_DEACTIVATION_DATE"] = pd.to_datetime(pws["PWS_DEACTIVATION_DATE"], errors="coerce")
pws = pws[(pws["PWS_DEACTIVATION_DATE"] >= "1983-01-01") | pws["PWS_DEACTIVATION_DATE"].isna()]
pws = pws[["PWSID", "STATE_CODE", "POPULATION_SERVED_COUNT", "OWNER_TYPE_CODE",
           "PRIMARY_SOURCE_CODE"]].drop_duplicates("PWSID")

facilities = pd.read_csv(SDWA_DIR / "SDWA_FACILITIES.csv", low_memory=False,
                          usecols=["PWSID", "FACILITY_ID", "FACILITY_DEACTIVATION_DATE"])
facilities = facilities[facilities["PWSID"].isin(universe)].copy()
facilities["FACILITY_DEACTIVATION_DATE"] = pd.to_datetime(facilities["FACILITY_DEACTIVATION_DATE"], errors="coerce")

df_years = pd.DataFrame({"year": list(range(1985, 2006))})
fac_yr = facilities.merge(df_years, how="cross")
fac_yr["year_deact"] = fac_yr["FACILITY_DEACTIVATION_DATE"].dt.year
fac_yr = fac_yr[~(fac_yr["year_deact"] < fac_yr["year"])]
num_fac = fac_yr.groupby(["PWSID", "year"])["FACILITY_ID"].count().reset_index().rename(
    columns={"FACILITY_ID": "num_facilities"}
)

skeleton = pd.DataFrame({"PWSID": universe}).merge(df_years, how="cross")
skeleton = skeleton.merge(pws, on="PWSID", how="left")
skeleton = skeleton.merge(num_fac, on=["PWSID", "year"], how="left")
skeleton["num_facilities"] = skeleton["num_facilities"].fillna(1)
skeleton["PWSID"] = skeleton["PWSID"].astype(str)
skeleton["year"]  = skeleton["year"].astype("int64")

n_missing_fac = skeleton["num_facilities"].isna().sum()
print(f"  Skeleton rows: {len(skeleton):,}  (missing num_facilities: {n_missing_fac})")
skeleton.to_parquet(str(OUT_DIR / "cws_covariates_steps.parquet"), index=False, engine="pyarrow")

print("\nDtypes (covariates):")
print(skeleton.dtypes)
print(f"\nWritten:")
print(f"  sdwa_visit_agg_steps.parquet:   {len(sv_agg):,} rows")
print(f"  sdwa_enf_agg_steps.parquet:     {len(enf_agg):,} rows")
print(f"  sdwa_vio_agg_steps.parquet:     {len(vio_agg):,} rows")
print(f"  cws_covariates_steps.parquet:   {len(skeleton):,} rows")
