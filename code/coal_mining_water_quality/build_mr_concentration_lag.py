# ============================================================
# Script: build_mr_concentration_lag.py
# Purpose: Match each SYR2 concentration measurement (downstream-only
#          mining sample) to MR (monitoring/reporting) violations in
#          a forward 1-365 day window (same-contaminant and RULE_CODE
#          ==333.0 any-IOC), plus a past 1-365 day placebo window, to
#          test whether high contaminant readings predict subsequent
#          MR violations (regulator-pivot / strategic avoidance
#          mechanism).
# Inputs:  - clean_data/cws_6year_review_measurement_level_syr2.parquet
#          - Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.parquet
#          - clean_data/cws_data/prod_vio_sulfur.parquet (downstream-only PWSID set)
# Outputs: - clean_data/mr_concentration_lag_measurement.parquet
# Author: EK  Date: 2026-06-23
# ============================================================

import pathlib

import numpy as np
import pandas as pd

PROJECT_ROOT = pathlib.Path(r"Z:\ek559\mining_wq")
MEAS_INPUT   = PROJECT_ROOT / "clean_data" / "cws_6year_review_measurement_level_syr2.parquet"
VIOL_INPUT   = pathlib.Path(r"Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.parquet")
MAIN_DATASET = PROJECT_ROOT / "clean_data" / "cws_data" / "prod_vio_sulfur.parquet"
OUTPUT       = PROJECT_ROOT / "clean_data" / "mr_concentration_lag_measurement.parquet"

# RULE_CODE for "Inorganic Chemicals" (Other IOC) -- same code used to build
# `inorganic_chemicals` in sdwismatch_pwsid_level_share_yr_in_violation.py /
# didhet.r, which feeds 2sls_dwnstrm_minevio_allcat_ivsum.tex. Note this rule
# code excludes arsenic (RULE_CODE 332.0) and nitrate (RULE_CODE 331.0), which
# have their own separate rule codes.
INORGANIC_CHEMICALS_RULE_CODE = 333.0

FWD_LOW_D,  FWD_HIGH_D  = 1, 365   # forward window: [s+1d, s+365d]
PAST_LOW_D, PAST_HIGH_D = 365, 1   # past window:    [s-365d, s-1d]

EMPTY = np.array([], dtype="datetime64[ns]")


def window_count(sorted_dates: np.ndarray, lower, upper, lower_incl: bool, upper_incl: bool) -> int:
    """Count entries of sorted_dates in the window bounded by (lower, upper),
    with inclusivity controlled by lower_incl / upper_incl."""
    if sorted_dates.size == 0:
        return 0
    lo_side = "left" if lower_incl else "right"
    hi_side = "right" if upper_incl else "left"
    i_lo = sorted_dates.searchsorted(np.datetime64(lower), side=lo_side)
    i_hi = sorted_dates.searchsorted(np.datetime64(upper), side=hi_side)
    return int(i_hi - i_lo)


def load_violations(ds_pwsids: set[str]) -> pd.DataFrame:
    cols = ["PWSID", "NON_COMPL_PER_BEGIN_DATE", "VIOLATION_CATEGORY_CODE", "CONTAMINANT_CODE", "RULE_CODE"]
    df = pd.read_parquet(VIOL_INPUT, engine="pyarrow", columns=cols)
    print(f"Raw violations: {len(df):,} rows")

    df = df[(df["VIOLATION_CATEGORY_CODE"] == "MR") & (df["PWSID"].astype(str).isin(ds_pwsids))].copy()
    print(f"MR violations, downstream-only PWSIDs: {len(df):,} rows")

    df["viol_date"] = pd.to_datetime(df["NON_COMPL_PER_BEGIN_DATE"], format="%m/%d/%Y", errors="coerce")
    n_unparseable = int(df["viol_date"].isna().sum())
    df = df[df["viol_date"].notna() & (df["viol_date"].dt.year >= 1990)].copy()
    print(f"Dropped {n_unparseable:,} unparseable dates; "
          f"{len(df):,} rows remain after year>=1990 filter")

    df = df.rename(columns={"CONTAMINANT_CODE": "contaminant_code"})
    df["PWSID"] = df["PWSID"].astype(str)
    return df[["PWSID", "contaminant_code", "RULE_CODE", "viol_date"]]


def build_date_indexes(viol: pd.DataFrame) -> tuple[dict, dict]:
    """pwsid_contam_dates: (PWSID, contaminant_code) -> sorted date array (any contaminant_code).
    pwsid_rule333_dates: PWSID -> sorted date array, restricted to RULE_CODE==333.0
    (Inorganic Chemicals / Other IOC -- same rule code used to build
    `inorganic_chemicals` for 2sls_dwnstrm_minevio_allcat_ivsum.tex)."""
    pwsid_contam_dates: dict[tuple[str, str], np.ndarray] = {}
    for key, g in viol.groupby(["PWSID", "contaminant_code"]):
        pwsid_contam_dates[key] = np.sort(g["viol_date"].values)

    viol_rule333 = viol[viol["RULE_CODE"] == INORGANIC_CHEMICALS_RULE_CODE]
    pwsid_rule333_dates: dict[str, np.ndarray] = {}
    for pwsid, g in viol_rule333.groupby("PWSID"):
        pwsid_rule333_dates[pwsid] = np.sort(g["viol_date"].values)

    return pwsid_contam_dates, pwsid_rule333_dates


def attach_mr_flags(meas: pd.DataFrame, pwsid_contam_dates: dict, pwsid_rule333_dates: dict) -> pd.DataFrame:
    n = len(meas)
    mr_same_fwd  = np.zeros(n, dtype=int)
    mr_anyioc_fwd  = np.zeros(n, dtype=int)
    mr_same_past = np.zeros(n, dtype=int)
    mr_anyioc_past = np.zeros(n, dtype=int)

    day = pd.Timedelta(days=1)
    for i, (pwsid, code, s) in enumerate(zip(meas["PWSID"], meas["contaminant_code"], meas["sample_date"])):
        dates_same    = pwsid_contam_dates.get((pwsid, code), EMPTY)
        dates_rule333 = pwsid_rule333_dates.get(pwsid, EMPTY)

        fwd_lower  = s + FWD_LOW_D * day
        fwd_upper  = s + FWD_HIGH_D * day
        past_lower = s - PAST_LOW_D * day
        past_upper = s - PAST_HIGH_D * day

        mr_same_fwd[i]    = 1 if window_count(dates_same,    fwd_lower, fwd_upper, True, True) > 0 else 0
        mr_anyioc_fwd[i]  = 1 if window_count(dates_rule333, fwd_lower, fwd_upper, True, True) > 0 else 0
        mr_same_past[i]   = 1 if window_count(dates_same,    past_lower, past_upper, True, True) > 0 else 0
        mr_anyioc_past[i] = 1 if window_count(dates_rule333, past_lower, past_upper, True, True) > 0 else 0

    meas = meas.copy()
    meas["mr_same_fwd"]    = mr_same_fwd
    meas["mr_anyioc_fwd"]  = mr_anyioc_fwd
    meas["mr_same_past"]   = mr_same_past
    meas["mr_anyioc_past"] = mr_anyioc_past
    return meas


if __name__ == "__main__":
    print(f"Reading downstream-only PWSID set from: {MAIN_DATASET}")
    main_df = pd.read_parquet(MAIN_DATASET, engine="pyarrow")
    ds_pwsids = set(
        main_df.loc[
            (main_df["minehuc_downstream_of_mine"] == 1) & (main_df["minehuc_mine"] == 0),
            "PWSID",
        ].astype(str)
    )
    print(f"Downstream-only PWSIDs: {len(ds_pwsids):,}\n")

    meas = pd.read_parquet(MEAS_INPUT, engine="pyarrow")
    meas["PWSID"] = meas["PWSID"].astype(str)
    print(f"Step-1 measurements loaded: {len(meas):,} rows")
    print(f"Chemicals present: {sorted(meas['CHEMID_name'].unique())}\n")

    viol = load_violations(ds_pwsids)
    pwsid_contam_dates, pwsid_rule333_dates = build_date_indexes(viol)

    meas = attach_mr_flags(meas, pwsid_contam_dates, pwsid_rule333_dates)

    out_cols = ["PWSID", "contaminant_code", "CHEMID_name", "sample_date", "YEAR",
                "VALUE", "ratio", "near_mcl", "above_mcl", "DETECT",
                "mr_same_fwd", "mr_anyioc_fwd", "mr_same_past", "mr_anyioc_past"]
    meas = meas[out_cols].copy()
    meas["PWSID"]       = meas["PWSID"].astype(str)
    meas["YEAR"]        = meas["YEAR"].astype("int64")
    meas["sample_date"] = pd.to_datetime(meas["sample_date"])

    print("\nOutcome means by chemical:")
    print(meas.groupby("CHEMID_name")[["mr_same_fwd", "mr_anyioc_fwd", "mr_same_past", "mr_anyioc_past"]].mean())
    print(f"\nOverall mr_same_fwd mean:    {meas['mr_same_fwd'].mean():.4f}")
    print(f"Overall mr_anyioc_fwd mean:  {meas['mr_anyioc_fwd'].mean():.4f}")
    print(f"Overall mr_same_past mean:   {meas['mr_same_past'].mean():.4f}")
    print(f"Overall mr_anyioc_past mean: {meas['mr_anyioc_past'].mean():.4f}")

    print(f"\nFinal dtypes:\n{meas.dtypes}")
    print(f"\nFinal row count: {len(meas):,}")

    if OUTPUT.exists():
        print(f"\nWARNING: {OUTPUT} already exists -- overwriting")
    meas.to_parquet(OUTPUT, index=False, engine="pyarrow")
    v = pd.read_parquet(OUTPUT, engine="pyarrow")
    print(f"Written {len(v):,} rows x {v.shape[1]} columns to {OUTPUT}")
