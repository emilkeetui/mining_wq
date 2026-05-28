# ============================================================
# Script: cws_intake_huc02.py
# Purpose: Build PWSID → HUC02 lookup from intake HUC12 data.
#          Uses modal HUC02 for the 2 PWSIDs that span >1 HUC02
#          (tie-break alphabetically on HUC02 code).
# Inputs:  Z:/ek559/water_instrument/cws_intake_hucs/PWS_Loctations_HUC12_A_I_2022Q2.xlsx
# Outputs: clean_data/cws_data/pwsid_huc02.parquet
# Author: EK  Date: 2026-05-27
# ============================================================

import pathlib
import pandas as pd

PROJECT_ROOT = pathlib.Path(r"Z:\ek559\mining_wq")
INTAKE_XLSX  = pathlib.Path(r"Z:\ek559\water_instrument\cws_intake_hucs\PWS_Loctations_HUC12_A_I_2022Q2.xlsx")
OUTPUT_PATH  = PROJECT_ROOT / "clean_data" / "cws_data" / "pwsid_huc02.parquet"

print(f"Reading: {INTAKE_XLSX}")
intake = pd.read_excel(INTAKE_XLSX, dtype={"PWSID": str, "HUC_12": str})
print(f"Raw rows: {len(intake):,}")

# Drop rows missing HUC_12 or PWSID
intake = intake.dropna(subset=["PWSID", "HUC_12"]).copy()
intake["HUC_12"] = intake["HUC_12"].astype(str).str.zfill(12)
intake["huc02"]  = intake["HUC_12"].str[:2]

# Per-PWSID HUC02 stats
grp      = intake.groupby("PWSID")
n_intake = grp["HUC_12"].nunique().rename("n_intake_hucs")
n_h02    = grp["huc02"].nunique().rename("n_distinct_huc02")

# Modal HUC02 per PWSID (tie-break: alphabetically lowest HUC02 code)
mode_huc02 = (
    intake.groupby(["PWSID", "huc02"]).size().rename("k").reset_index()
    .sort_values(["PWSID", "k", "huc02"], ascending=[True, False, True])
    .drop_duplicates("PWSID", keep="first")[["PWSID", "huc02"]]
)

out = (
    mode_huc02
    .merge(n_intake, on="PWSID")
    .merge(n_h02,    on="PWSID")
)
out["multi_huc02_flag"] = (out["n_distinct_huc02"] > 1).astype("int64")

# Type guards
out["PWSID"]            = out["PWSID"].astype(str)
out["huc02"]            = out["huc02"].astype(str)
out["n_intake_hucs"]    = out["n_intake_hucs"].astype("int64")
out["n_distinct_huc02"] = out["n_distinct_huc02"].astype("int64")
out["multi_huc02_flag"] = out["multi_huc02_flag"].astype("int64")

print(out.dtypes)
print(f"Rows: {len(out):,}  |  multi-HUC02 PWSIDs: {out['multi_huc02_flag'].sum():,}")
print("Top HUC02 frequencies:")
print(out["huc02"].value_counts().head(10))

if OUTPUT_PATH.exists():
    print(f"WARNING: {OUTPUT_PATH} already exists — overwriting")

out.to_parquet(OUTPUT_PATH, index=False, engine="pyarrow")

verify = pd.read_parquet(OUTPUT_PATH, engine="pyarrow")
print(f"Verified: {len(verify):,} rows × {verify.shape[1]} cols written to {OUTPUT_PATH}")
