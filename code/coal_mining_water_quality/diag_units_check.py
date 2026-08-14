# ============================================================
# Script: diag_units_check.py
# Purpose: Check string-"nan" vs actual NaN in UNITS field of 6-Year Review
#          chemicals data, and flag DETECT/VALUE inconsistencies vs MCL
# Inputs: clean_data/cws_6year_review_chemicals.parquet
# Outputs: none (diagnostic prints only)
# Author: EK  Date: 2026-08-13
# ============================================================
import pandas as pd

df = pd.read_parquet(
    r"Z:\ek559\mining_wq\clean_data\cws_6year_review_chemicals.parquet",
    engine="pyarrow"
)

for chem in ["arsenic", "nitrate"]:
    sub = df[df["CHEMID_name"] == chem].copy()
    sub["syr"] = sub["YEAR"].apply(lambda y: "SYR2" if y <= 2005 else "SYR3")

    # String "nan" vs actual NaN — .astype(str) on NaN produces "nan"
    str_nan = (sub["UNITS"] == "nan").sum()
    act_nan = sub["UNITS"].isna().sum()
    print(f"{chem}:  string-'nan' UNITS={str_nan:,}  actual-NaN UNITS={act_nan:,}")

    # Are string-nan UNITS concentrated in non-detections?
    det0 = sub[sub["DETECT"] == 0]
    det1 = sub[sub["DETECT"] == 1]
    print(f"  DETECT=0: string-nan UNITS={(det0['UNITS']=='nan').sum():,} / {len(det0):,}")
    print(f"  DETECT=1: string-nan UNITS={(det1['UNITS']=='nan').sum():,} / {len(det1):,}")

    # By source
    print(f"  SYR2 string-nan: {(sub[sub['syr']=='SYR2']['UNITS']=='nan').sum():,}")
    print(f"  SYR3 string-nan: {(sub[sub['syr']=='SYR3']['UNITS']=='nan').sum():,}")

    # DETECT=0 but VALUE > MCL (data quality check)
    mcl = {"arsenic": 0.05, "nitrate": 10.0}[chem]
    suspicious = det0[det0["VALUE"].notna() & (det0["VALUE"] > mcl)]
    print(f"  DETECT=0 rows with VALUE > MCL ({mcl}): {len(suspicious):,}")
    if len(suspicious) > 0:
        print(f"    VALUE range: {suspicious['VALUE'].min():.4f} - {suspicious['VALUE'].max():.4f}")
        print(f"    By source:  {suspicious.groupby('syr').size().to_dict()}")

    # DETECT=1 exceedance rate
    exceed = det1[det1["VALUE"] > mcl]
    print(f"  DETECT=1 rows with VALUE > MCL ({mcl}): {len(exceed):,} / {len(det1):,} "
          f"({len(exceed)/max(len(det1),1):.1%})")
    print()
