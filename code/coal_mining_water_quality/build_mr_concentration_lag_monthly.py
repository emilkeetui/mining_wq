# ============================================================
# Script: build_mr_concentration_lag_monthly.py
# Purpose: Reshape measurement-level SYR2 data to a CWS-month panel
#          for regressing MR violation indicators on lagged contaminant
#          concentration ratios. Unit: PWSID × contaminant_code × year_month.
#          Months with no contaminant reading have NaN lags (not 0).
# Inputs:  clean_data/mr_concentration_lag_measurement.parquet
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.parquet
# Outputs: clean_data/mr_concentration_lag_monthly.parquet
# Author: EK  Date: 2026-06-30
# ============================================================

import pathlib

import numpy as np
import pandas as pd

PROJECT_ROOT = pathlib.Path(r"Z:\ek559\mining_wq")
MEAS_INPUT   = PROJECT_ROOT / "clean_data" / "mr_concentration_lag_measurement.parquet"
VIOL_INPUT   = pathlib.Path(r"Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.parquet")
OUTPUT       = PROJECT_ROOT / "clean_data" / "mr_concentration_lag_monthly.parquet"

INORGANIC_CHEMICALS_RULE_CODE = 333.0
SAMPLE_START = "1998-01"
SAMPLE_END   = "2005-12"


# ── Step 1: Load measurements (already filtered to downstream-only sample) ──────
meas = pd.read_parquet(MEAS_INPUT, engine="pyarrow")
meas["PWSID"] = meas["PWSID"].astype(str)
meas["year_month"] = meas["sample_date"].dt.to_period("M")

print(f"Loaded {len(meas):,} measurements")
print(f"Unique PWSID: {meas['PWSID'].nunique()}")
print(f"Contaminants: {sorted(meas['contaminant_code'].unique())}")
print(f"Date range: {meas['sample_date'].min().date()} – {meas['sample_date'].max().date()}\n")

# ── Step 2: Monthly aggregates: mean ratio and near_mcl ─────────────────────────
monthly_meas = (
    meas.groupby(["PWSID", "contaminant_code", "year_month"])
    .agg(ratio=("ratio", "mean"), near_mcl=("near_mcl", "mean"))
    .reset_index()
)
print(f"Monthly measurement aggregates: {len(monthly_meas):,} rows")

# ── Step 3: Full balanced grid: unique (PWSID, contaminant_code) × all months ───
# Only include PWSID × contaminant_code pairs that have ≥1 measurement in the sample,
# to avoid inflating the panel with contaminants never tested at a given CWS.
pwsid_contam_pairs = meas[["PWSID", "contaminant_code"]].drop_duplicates().copy()
all_months = pd.period_range(start=SAMPLE_START, end=SAMPLE_END, freq="M")
grid = (
    pwsid_contam_pairs.assign(_key=1)
    .merge(pd.DataFrame({"year_month": all_months, "_key": 1}), on="_key")
    .drop(columns="_key")
)
print(f"Balanced grid: {len(grid):,} rows "
      f"({len(pwsid_contam_pairs):,} PWSID×contaminant pairs × {len(all_months)} months)")

# ── Step 4: Left-join measurements → NaN where no reading in that month ─────────
grid = grid.merge(monthly_meas, on=["PWSID", "contaminant_code", "year_month"], how="left")
pct_no_reading = grid["ratio"].isna().mean()
print(f"Month-contaminant cells with no reading: {pct_no_reading:.1%}\n")

# ── Step 5: 1-month lags within PWSID × contaminant_code ────────────────────────
# Balanced grid guarantees each month is present so .shift(1) gives a true 1-month lag.
grid = grid.sort_values(["PWSID", "contaminant_code", "year_month"]).reset_index(drop=True)
grid["ratio_lag1"]    = grid.groupby(["PWSID", "contaminant_code"])["ratio"].shift(1)
grid["near_mcl_lag1"] = grid.groupby(["PWSID", "contaminant_code"])["near_mcl"].shift(1)

# 1-month leads for placebo table
grid["ratio_lead1"]    = grid.groupby(["PWSID", "contaminant_code"])["ratio"].shift(-1)
grid["near_mcl_lead1"] = grid.groupby(["PWSID", "contaminant_code"])["near_mcl"].shift(-1)

print(f"ratio_lag1 NaN rate (no prior-month reading): {grid['ratio_lag1'].isna().mean():.3f}")
print(f"near_mcl_lag1 NaN rate:                       {grid['near_mcl_lag1'].isna().mean():.3f}\n")

# ── Step 6: Load MR violations for downstream PWSIDs ────────────────────────────
ds_pwsids = set(meas["PWSID"].unique())
cols = ["PWSID", "NON_COMPL_PER_BEGIN_DATE", "VIOLATION_CATEGORY_CODE",
        "CONTAMINANT_CODE", "RULE_CODE"]
viol = pd.read_parquet(VIOL_INPUT, engine="pyarrow", columns=cols)
print(f"Raw violations loaded: {len(viol):,} rows")

viol = viol[
    (viol["VIOLATION_CATEGORY_CODE"] == "MR") &
    (viol["PWSID"].astype(str).isin(ds_pwsids))
].copy()
viol["PWSID"] = viol["PWSID"].astype(str)
print(f"MR violations, downstream PWSIDs: {len(viol):,} rows")

viol["viol_date"] = pd.to_datetime(
    viol["NON_COMPL_PER_BEGIN_DATE"], format="%m/%d/%Y", errors="coerce"
)
n_bad = viol["viol_date"].isna().sum()
viol = viol[
    viol["viol_date"].notna() &
    (viol["viol_date"].dt.year >= 1998) &
    (viol["viol_date"].dt.year <= 2005)
].copy()
print(f"Dropped {n_bad:,} unparseable dates; {len(viol):,} MR violations in 1998-2005\n")

viol["year_month"]       = viol["viol_date"].dt.to_period("M")
viol["CONTAMINANT_CODE"] = viol["CONTAMINANT_CODE"].astype(str)

# ── Step 7: Same-contaminant DV — any MR vio for PWSID × contaminant × month ───
same_viol = (
    viol.groupby(["PWSID", "CONTAMINANT_CODE", "year_month"])
    .size()
    .gt(0)
    .astype(int)
    .reset_index(name="mr_same_month")
    .rename(columns={"CONTAMINANT_CODE": "contaminant_code"})
)

# ── Step 8: IOC DV — any RULE_CODE==333.0 MR vio per PWSID × month ─────────────
ioc_viol_agg = (
    viol[viol["RULE_CODE"] == INORGANIC_CHEMICALS_RULE_CODE]
    .groupby(["PWSID", "year_month"])
    .size()
    .gt(0)
    .astype(int)
    .reset_index(name="mr_ioc_month")
)

# ── Step 9: Join DVs → fill NaN (no violation in month) with 0 ──────────────────
grid = grid.merge(same_viol,  on=["PWSID", "contaminant_code", "year_month"], how="left")
grid["mr_same_month"] = grid["mr_same_month"].fillna(0).astype(int)

grid = grid.merge(ioc_viol_agg, on=["PWSID", "year_month"], how="left")
grid["mr_ioc_month"] = grid["mr_ioc_month"].fillna(0).astype(int)

print(f"mr_same_month mean: {grid['mr_same_month'].mean():.4f}")
print(f"mr_ioc_month mean:  {grid['mr_ioc_month'].mean():.4f}")

# ── Step 10: Add calendar columns and convert period to string ───────────────────
grid["YEAR"]          = grid["year_month"].dt.year.astype("int64")
grid["month"]         = grid["year_month"].dt.month.astype("int64")
grid["year_month_str"] = grid["year_month"].astype(str)   # "YYYY-MM" factor for FEs in R

# Drop the raw (non-lagged) ratio/near_mcl; keep only lags and leads for analysis
grid = grid.drop(columns=["year_month", "ratio", "near_mcl"])

out_cols = [
    "PWSID", "contaminant_code", "YEAR", "month", "year_month_str",
    "ratio_lag1", "near_mcl_lag1", "ratio_lead1", "near_mcl_lead1",
    "mr_same_month", "mr_ioc_month",
]
grid = grid[out_cols].copy()

# ── Step 11: Schema check and save ───────────────────────────────────────────────
grid["PWSID"]           = grid["PWSID"].astype(str)
grid["contaminant_code"] = grid["contaminant_code"].astype(str)
grid["YEAR"]            = grid["YEAR"].astype("int64")
grid["month"]           = grid["month"].astype("int64")

print(f"\nFinal dtypes:\n{grid.dtypes}")
print(f"\nFinal row count: {len(grid):,}")
print(f"\nSample (first 3 rows):\n{grid.head(3)}")

if OUTPUT.exists():
    print(f"\nWARNING: {OUTPUT} already exists -- overwriting")
grid.to_parquet(OUTPUT, index=False, engine="pyarrow")

v = pd.read_parquet(OUTPUT, engine="pyarrow")
print(f"\nWritten {len(v):,} rows × {v.shape[1]} columns to {OUTPUT}")
