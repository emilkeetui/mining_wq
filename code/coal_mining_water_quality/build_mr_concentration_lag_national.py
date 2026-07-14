# ============================================================
# Script: build_mr_concentration_lag_national.py
# Purpose: National (all-PWSID, no downstream-of-mine restriction)
#          version of build_mr_concentration_lag.py, nitrate-only.
#          Power fix for the mr_concentration_lag near_mcl trigger
#          test: the downstream-only sample has only 3 SYR2 nitrate
#          readings crossing the 50% MCL quarterly-monitoring trigger
#          (40 CFR 141.23(d)(2)); the national SYR2 nitrate sample has
#          far more. Ratchet avoidance (MR violation following a
#          near-MCL reading) is a general SDWA mechanism, not specific
#          to mining HUCs, so the national sample is a valid test of
#          the same specification.
#          Reuses (copies, does not edit) the pyodbc SYR2 reader from
#          cws_6year_review_measurement_dates.py, the Ravalli
#          MDL/sqrt(2) + EPA-method-MDL-fallback non-detect imputation,
#          unit normalization, gross-outlier drop, and MCL-ratio logic
#          from the same script; and the MR forward/past window match
#          logic from build_mr_concentration_lag.py, vectorized via
#          per-PWSID np.searchsorted instead of a per-row Python loop
#          (the national row count precludes the per-row loop).
# Inputs:  - raw_data/6_year_review_epa/six-year-review 2/
#            nitrate-as-n-_chem1040_update_mdb/Nitrate (as N)_Chem1040_update.mdb
#          - Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.parquet
# Outputs: - clean_data/mr_concentration_lag_national_nitrate.parquet
# Author: EK  Date: 2026-07-14
# ============================================================

import math
import pathlib

import numpy as np
import pandas as pd
import pyodbc

PROJECT_ROOT = pathlib.Path(r"Z:\ek559\mining_wq")
NITRATE_MDB  = (PROJECT_ROOT / "raw_data" / "6_year_review_epa" / "six-year-review 2"
                 / "nitrate-as-n-_chem1040_update_mdb" / "Nitrate (as N)_Chem1040_update.mdb")
VIOL_INPUT   = pathlib.Path(r"Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.parquet")
OUTPUT       = PROJECT_ROOT / "clean_data" / "mr_concentration_lag_national_nitrate.parquet"

NITRATE_CODE   = "1040"
NITRATE_MCL    = 10.000   # mg/L
NITRATE_EPA_MDL_MGL   = 0.0100   # EPA method MDL, mg/L (Method 300.0)
UNRELIABLE_LOD_MGL    = 0.005    # Ravalli appendix p3: >5 ug/L LOD treated as unreliable

FWD_LOW_D,  FWD_HIGH_D  = 1, 365   # forward window: [s+1d, s+365d]
FWD6_LOW_D, FWD6_HIGH_D = 1, 182   # 6-month forward window: [s+1d, s+182d]
PAST_LOW_D, PAST_HIGH_D   = 365, 1 # past window:    [s-365d, s-1d]
PAST6_LOW_D, PAST6_HIGH_D = 182, 1 # 6-month past window: [s-182d, s-1d]

KEEP_COLS = ["PWSID", "CHEMID_name", "DETECT", "VALUE", "UNITS", "YEAR",
             "sample_date", "MDL", "MDL_UNITS"]

_UNIT_DIM: dict[str, tuple[str, float]] = {
    "mg/l": ("mass", 1.0),
    "ug/l": ("mass", 1e-3),
    "µg/l": ("mass", 1e-3),
    "ng/l": ("mass", 1e-6),
}


def _norm_unit(s) -> str:
    if s is None or (isinstance(s, float) and pd.isna(s)):
        return ""
    return str(s).strip().lower().replace(" ", "")


# ---------------------------------------------------------------------------
# Step 1: read the SYR2 nitrate .mdb (copied read_syr2_mdb logic from
# cws_6year_review_measurement_dates.py)
# ---------------------------------------------------------------------------
def read_syr2_mdb(path: pathlib.Path, chem_name: str) -> pd.DataFrame:
    """Read a SYR2 Access .mdb file via pyodbc, keeping the sample date."""
    conn_str = r"DRIVER={Microsoft Access Driver (*.mdb, *.accdb)};DBQ=" + str(path)
    conn = pyodbc.connect(conn_str)
    cursor = conn.cursor()
    tables = [r.table_name for r in cursor.tables(tableType="TABLE")]
    if not tables:
        conn.close()
        raise RuntimeError(f"No tables in {path}")
    cursor.execute(f"SELECT * FROM [{tables[0]}]")
    cols = [d[0] for d in cursor.description]
    rows = cursor.fetchall()
    conn.close()

    df = pd.DataFrame.from_records(rows, columns=cols)
    df["sample_date"]  = pd.to_datetime(df["DATE"])
    df["YEAR"]         = df["sample_date"].dt.year
    df["CHEMID_name"]  = chem_name
    df["PWSID"]        = df["PWSID"].astype(str).str.strip()
    df["UNITS"]        = df["UNITS"].astype(str).str.strip().where(lambda s: s != "nan")
    df["DETECT"]       = pd.to_numeric(df["DETECT"], errors="coerce")
    df["VALUE"]        = pd.to_numeric(df["VALUE"],  errors="coerce")
    # SYR2 data dictionary: VALUE stores the MRL when DETECT==0.
    df["MDL"]       = df["VALUE"].where(df["DETECT"] == 0)
    df["MDL_UNITS"] = df["UNITS"]
    return df[KEEP_COLS].copy()


# ---------------------------------------------------------------------------
# Step 2: cleaning chain (copied from cws_6year_review_measurement_dates.py,
# specialized to a single chemical -- nitrate -- so no per-chemical dict
# lookups are needed)
# ---------------------------------------------------------------------------
def impute_nondetects_ravalli(df: pd.DataFrame) -> pd.DataFrame:
    """Record-specific MDL/sqrt(2) imputation (Ravalli et al. 2022)."""
    df = df.copy()
    mask = (df["DETECT"] == 0) & df["MDL"].notna()
    n_imputed = int(mask.sum())
    df.loc[mask, "VALUE"] = df.loc[mask, "MDL"] / math.sqrt(2)
    print(f"\nRavalli MDL/sqrt(2) imputation (record-specific): {n_imputed:,} records imputed")
    return df


def impute_nondetects_epa_fallback(df: pd.DataFrame) -> pd.DataFrame:
    """EPA method-MDL/sqrt(2) fallback for non-detects with no reliable
    record-specific LOD -- MDL missing, MDL_UNITS not a mass unit, or
    MDL > 5 ug/L (0.005 mg/L), per Ravalli et al. 2022 appendix p3."""
    df = df.copy()
    is_nondetect = df["DETECT"] == 0

    mdl_unit_norm = df["MDL_UNITS"].map(_norm_unit)
    mdl_is_mass   = mdl_unit_norm.isin(["mg/l", "ug/l", "µg/l", "ng/l"])
    mdl_mgl = pd.Series(float("nan"), index=df.index)
    fac = {"mg/l": 1.0, "ug/l": 1e-3, "µg/l": 1e-3, "ng/l": 1e-6}
    for u, f in fac.items():
        m = mdl_unit_norm.eq(u) & df["MDL"].notna()
        mdl_mgl.loc[m] = df.loc[m, "MDL"] * f

    unreliable = (
        is_nondetect
        & (df["MDL"].isna() | ~mdl_is_mass | (mdl_mgl >= UNRELIABLE_LOD_MGL))
    )

    can_fallback = unreliable  # nitrate always has an EPA MDL (0.0100 mg/L)
    df.loc[can_fallback, "VALUE"] = NITRATE_EPA_MDL_MGL / math.sqrt(2)
    df.loc[can_fallback, "UNITS"] = "mg/L"

    print(f"\nEPA method-MDL fallback: {int(can_fallback.sum()):,} "
          f"unreliable-LOD non-detects imputed via EPA method MDL/sqrt(2) "
          f"(nitrate MDL={NITRATE_EPA_MDL_MGL} mg/L, unreliable threshold={UNRELIABLE_LOD_MGL} mg/L)")
    return df


def normalize_units(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()
    n = df["UNITS"].map(_norm_unit)
    dim = n.map(lambda x: _UNIT_DIM.get(x, (None, float("nan")))[0])
    fac = n.map(lambda x: _UNIT_DIM.get(x, (None, float("nan")))[1]).astype(float)
    is_mass = dim.eq("mass")
    df.loc[is_mass, "VALUE"] = df.loc[is_mass, "VALUE"] * fac[is_mass]
    df.loc[is_mass, "UNITS"] = "mg/L"
    print(f"\nUnit normalization: {int(is_mass.sum()):,} mass->mg/L")
    return df


def drop_gross_outliers(df: pd.DataFrame, factor: float = 100.0) -> pd.DataFrame:
    value_mgl = df["VALUE"].where(df["UNITS"].str.lower() == "mg/l")
    gross = value_mgl.notna() & (value_mgl > factor * NITRATE_MCL)
    n = int(gross.sum())
    print(f"\nGross-outlier drop (> {factor:g}x MCL): {n:,} rows")
    return df.loc[~gross].copy()


def compute_mcl_ratio(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()
    value_mgl = df["VALUE"].where(df["UNITS"].str.lower() == "mg/l")
    df["mcl_mgL"]  = NITRATE_MCL
    df["ratio"]     = value_mgl / df["mcl_mgL"]
    df["near_mcl"]  = ((df["ratio"] >= 0.5) & (df["ratio"] < 1.0)).astype(int)
    df["above_mcl"] = (df["ratio"] >= 1.0).astype(int)
    n_valid = int(df["ratio"].notna().sum())
    print(f"\nMCL ratio computed for {n_valid:,} rows; "
          f"near_mcl={int(df['near_mcl'].sum()):,}, above_mcl={int(df['above_mcl'].sum()):,}")
    return df


# ---------------------------------------------------------------------------
# Step 3: MR violation load + vectorized forward/past window match
# (logic copied from build_mr_concentration_lag.py; vectorized via
# per-PWSID np.searchsorted on arrays of sample dates, instead of a
# per-row Python loop, for national-scale row counts)
# ---------------------------------------------------------------------------
def load_violations_nitrate() -> pd.DataFrame:
    cols = ["PWSID", "NON_COMPL_PER_BEGIN_DATE", "VIOLATION_CATEGORY_CODE", "CONTAMINANT_CODE"]
    df = pd.read_parquet(VIOL_INPUT, engine="pyarrow", columns=cols)
    print(f"Raw violations: {len(df):,} rows")
    print(f"CONTAMINANT_CODE dtype: {df['CONTAMINANT_CODE'].dtype}")

    contam_str = df["CONTAMINANT_CODE"].astype(str).str.strip()
    # Handle both "1040" and "1040.0" style string representations.
    is_nitrate = contam_str.isin([NITRATE_CODE, f"{NITRATE_CODE}.0"])

    df = df[(df["VIOLATION_CATEGORY_CODE"] == "MR") & is_nitrate].copy()
    print(f"MR violations, nitrate (contaminant_code={NITRATE_CODE}): {len(df):,} rows")

    df["viol_date"] = pd.to_datetime(df["NON_COMPL_PER_BEGIN_DATE"], format="%m/%d/%Y", errors="coerce")
    n_unparseable = int(df["viol_date"].isna().sum())
    df = df[df["viol_date"].notna() & (df["viol_date"].dt.year >= 1990)].copy()
    print(f"Dropped {n_unparseable:,} unparseable dates; "
          f"{len(df):,} rows remain after year>=1990 filter")

    df["PWSID"] = df["PWSID"].astype(str)
    return df[["PWSID", "viol_date"]]


def attach_mr_flags_vectorized(meas: pd.DataFrame, viol: pd.DataFrame) -> pd.DataFrame:
    """For each PWSID, sort that PWSID's violation dates once, then use
    np.searchsorted (array form) against the full vector of that PWSID's
    sample dates simultaneously -- avoids a per-row Python loop."""
    meas = meas.reset_index(drop=True).copy()
    n = len(meas)
    mr_same_fwd      = np.zeros(n, dtype=int)
    mr_same_fwd6mon  = np.zeros(n, dtype=int)
    mr_same_past     = np.zeros(n, dtype=int)
    mr_same_past6mon = np.zeros(n, dtype=int)

    viol_by_pwsid: dict[str, np.ndarray] = {
        pwsid: np.sort(g["viol_date"].values) for pwsid, g in viol.groupby("PWSID")
    }

    day = np.timedelta64(1, "D")
    for pwsid, idx in meas.groupby("PWSID").indices.items():
        idx = np.asarray(idx)
        dates_v = viol_by_pwsid.get(pwsid)
        if dates_v is None or dates_v.size == 0:
            continue
        s = meas["sample_date"].values[idx]

        fwd_lower   = s + FWD_LOW_D  * day
        fwd_upper   = s + FWD_HIGH_D * day
        fwd6_upper  = s + FWD6_HIGH_D * day   # shares fwd_lower as the lower bound
        past_lower  = s - PAST_LOW_D  * day
        past_upper  = s - PAST_HIGH_D * day
        past6_lower = s - PAST6_LOW_D * day

        # forward 1-365d: count(dates_v in [fwd_lower, fwd_upper])
        i_lo = dates_v.searchsorted(fwd_lower, side="left")
        i_hi = dates_v.searchsorted(fwd_upper, side="right")
        mr_same_fwd[idx] = (i_hi - i_lo) > 0

        # forward 1-182d
        i_hi6 = dates_v.searchsorted(fwd6_upper, side="right")
        mr_same_fwd6mon[idx] = (i_hi6 - i_lo) > 0

        # past 365-1d: count(dates_v in [past_lower, past_upper])
        j_lo = dates_v.searchsorted(past_lower, side="left")
        j_hi = dates_v.searchsorted(past_upper, side="right")
        mr_same_past[idx] = (j_hi - j_lo) > 0

        # past 182-1d
        j_lo6 = dates_v.searchsorted(past6_lower, side="left")
        mr_same_past6mon[idx] = (j_hi - j_lo6) > 0

    meas["mr_same_fwd"]       = mr_same_fwd
    meas["mr_same_fwd6mon"]   = mr_same_fwd6mon
    meas["mr_same_past"]      = mr_same_past
    meas["mr_same_past6mon"]  = mr_same_past6mon
    return meas


if __name__ == "__main__":
    print(f"Reading SYR2 nitrate .mdb: {NITRATE_MDB}")
    try:
        nit = read_syr2_mdb(NITRATE_MDB, "nitrate")
    except Exception as e:
        print(f"[ERROR] Failed to read SYR2 nitrate .mdb: {type(e).__name__}: {e}")
        raise
    nit["PWSID"] = nit["PWSID"].astype(str)
    nit["YEAR"]  = nit["YEAR"].astype("int64")
    print(f"Raw nitrate SYR2 rows: {len(nit):,}")
    print(f"Year range: {nit['YEAR'].min()}-{nit['YEAR'].max()}")

    national_detect_rate = float((nit["DETECT"] == 1).mean())
    print(f"National nitrate detection rate: {100 * national_detect_rate:.1f}% "
          f"(no filter applied -- nitrate is always kept)")

    nit = impute_nondetects_ravalli(nit)
    nit = impute_nondetects_epa_fallback(nit)
    nit = normalize_units(nit)
    nit = drop_gross_outliers(nit)
    nit = compute_mcl_ratio(nit)
    nit["contaminant_code"] = NITRATE_CODE

    print(f"\nSYR2 nitrate panel after cleaning: {len(nit):,} rows")

    # ── MR violation match ─────────────────────────────────────────────────
    viol = load_violations_nitrate()
    nit = attach_mr_flags_vectorized(nit, viol)

    out_cols = ["PWSID", "contaminant_code", "CHEMID_name", "sample_date", "YEAR",
                "VALUE", "mcl_mgL", "ratio", "near_mcl", "above_mcl", "DETECT",
                "mr_same_fwd", "mr_same_fwd6mon", "mr_same_past", "mr_same_past6mon"]
    nit = nit[out_cols].copy()
    nit["PWSID"]       = nit["PWSID"].astype(str)
    nit["YEAR"]        = nit["YEAR"].astype("int64")
    nit["sample_date"] = pd.to_datetime(nit["sample_date"])

    n_near  = int(nit["near_mcl"].sum())
    n_above = int(nit["above_mcl"].sum())
    print(f"\n=== near_mcl==1 readings (50-100% of MCL): {n_near:,} ===")
    print(f"=== above_mcl==1 readings (>=100% of MCL): {n_above:,} ===")
    if n_near < 30:
        print(f"[WARNING] near_mcl count ({n_near}) is still small (<30) -- "
              f"national expansion may not have solved the power problem.")

    print("\nOutcome means:")
    print(nit[["mr_same_fwd", "mr_same_fwd6mon", "mr_same_past", "mr_same_past6mon"]].mean())

    print(f"\nFinal dtypes:\n{nit.dtypes}")
    print(f"\nFinal row count: {len(nit):,}")

    if OUTPUT.exists():
        print(f"\nWARNING: {OUTPUT} already exists -- overwriting")
    nit.to_parquet(OUTPUT, index=False, engine="pyarrow")
    v = pd.read_parquet(OUTPUT, engine="pyarrow")
    print(f"Written {len(v):,} rows x {v.shape[1]} columns to {OUTPUT}")
