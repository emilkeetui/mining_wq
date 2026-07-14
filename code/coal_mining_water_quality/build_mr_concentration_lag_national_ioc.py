# ============================================================
# Script: build_mr_concentration_lag_national_ioc.py
# Purpose: National (all-PWSID) IOC extension of
#          build_mr_concentration_lag_national.py. Tests the same
#          ratchet-avoidance mechanism for arsenic, barium, and
#          selenium: a reading at 50-100% of the MCL puts a system at
#          risk of triggering quarterly monitoring (40 CFR 141.23(c)(7),
#          IOC exceedance) or, for arsenic pre-2006, mandatory
#          confirmation sampling (old 40 CFR 141.23(m)); near_mcl here
#          proxies ratchet risk rather than a strict sub-MCL trigger
#          (unlike nitrate's 141.23(d)(2), the IOC/arsenic trigger sits
#          at the MCL itself). Reuses (copies, does not edit) the
#          pyodbc SYR2 reader, Ravalli MDL/sqrt(2) + EPA-method-MDL
#          fallback non-detect imputation, unit normalization,
#          gross-outlier drop, and MCL-ratio logic from
#          build_mr_concentration_lag_national.py and
#          cws_6year_review_measurement_dates.py; and the vectorized
#          MR forward/past window match (per-PWSID np.searchsorted),
#          run separately per chemical so matches stay same-contaminant.
# Inputs:  - raw_data/6_year_review_epa/six-year-review 2/
#            sixyearreview_2_dh_part2_1/Arsenic_Chem1005.mdb
#          - raw_data/6_year_review_epa/six-year-review 2/
#            sixyearreview_2_dh_part2_1/Barium_Chem1010.mdb
#          - raw_data/6_year_review_epa/six-year-review 2/
#            sixyearreview_2_dh_part5_0/Selenium_Chem1045.mdb
#          - Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.parquet
# Outputs: - clean_data/mr_concentration_lag_national_ioc.parquet
# Author: EK  Date: 2026-07-14
# ============================================================

import math
import pathlib

import numpy as np
import pandas as pd
import pyodbc

PROJECT_ROOT = pathlib.Path(r"Z:\ek559\mining_wq")
SYR2         = PROJECT_ROOT / "raw_data" / "6_year_review_epa" / "six-year-review 2"
VIOL_INPUT   = pathlib.Path(r"Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.parquet")
OUTPUT       = PROJECT_ROOT / "clean_data" / "mr_concentration_lag_national_ioc.parquet"

# name -> (mdb path, contaminant code, MCL mg/L [1993-2005], EPA method MDL mg/L)
CHEMS: dict[str, tuple[pathlib.Path, str, float, float]] = {
    "arsenic":  (SYR2 / "sixyearreview_2_dh_part2_1" / "Arsenic_Chem1005.mdb",  "1005", 0.050, 0.0014),
    "barium":   (SYR2 / "sixyearreview_2_dh_part2_1" / "Barium_Chem1010.mdb",   "1010", 2.000, 0.0010),
    "selenium": (SYR2 / "sixyearreview_2_dh_part5_0" / "Selenium_Chem1045.mdb", "1045", 0.050, 0.0016),
}

UNRELIABLE_LOD_MGL = 0.005   # Ravalli appendix p3: >5 ug/L LOD treated as unreliable
GROSS_OUTLIER_FACTOR = 100.0

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
# Step 1: read the SYR2 .mdb for a single chemical (copied read_syr2_mdb
# logic from build_mr_concentration_lag_national.py / cws_6year_review_
# measurement_dates.py)
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
# Step 2: cleaning chain (copied from build_mr_concentration_lag_national.py,
# parameterized per chemical for MCL and EPA method MDL)
# ---------------------------------------------------------------------------
def impute_nondetects_ravalli(df: pd.DataFrame) -> pd.DataFrame:
    """Record-specific MDL/sqrt(2) imputation (Ravalli et al. 2022)."""
    df = df.copy()
    mask = (df["DETECT"] == 0) & df["MDL"].notna()
    n_imputed = int(mask.sum())
    df.loc[mask, "VALUE"] = df.loc[mask, "MDL"] / math.sqrt(2)
    print(f"  Ravalli MDL/sqrt(2) imputation (record-specific): {n_imputed:,} records imputed")
    return df


def impute_nondetects_epa_fallback(df: pd.DataFrame, epa_mdl_mgl: float) -> pd.DataFrame:
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

    df.loc[unreliable, "VALUE"] = epa_mdl_mgl / math.sqrt(2)
    df.loc[unreliable, "UNITS"] = "mg/L"

    print(f"  EPA method-MDL fallback: {int(unreliable.sum()):,} "
          f"unreliable-LOD non-detects imputed via EPA method MDL/sqrt(2) "
          f"(MDL={epa_mdl_mgl} mg/L, unreliable threshold={UNRELIABLE_LOD_MGL} mg/L)")
    return df


def normalize_units(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()
    n = df["UNITS"].map(_norm_unit)
    dim = n.map(lambda x: _UNIT_DIM.get(x, (None, float("nan")))[0])
    fac = n.map(lambda x: _UNIT_DIM.get(x, (None, float("nan")))[1]).astype(float)
    is_mass = dim.eq("mass")
    df.loc[is_mass, "VALUE"] = df.loc[is_mass, "VALUE"] * fac[is_mass]
    df.loc[is_mass, "UNITS"] = "mg/L"
    print(f"  Unit normalization: {int(is_mass.sum()):,} mass->mg/L")
    return df


def drop_gross_outliers(df: pd.DataFrame, mcl: float, factor: float = GROSS_OUTLIER_FACTOR) -> pd.DataFrame:
    value_mgl = df["VALUE"].where(df["UNITS"].str.lower() == "mg/l")
    gross = value_mgl.notna() & (value_mgl > factor * mcl)
    n = int(gross.sum())
    print(f"  Gross-outlier drop (> {factor:g}x MCL): {n:,} rows")
    return df.loc[~gross].copy()


def compute_mcl_ratio(df: pd.DataFrame, mcl: float) -> pd.DataFrame:
    df = df.copy()
    value_mgl = df["VALUE"].where(df["UNITS"].str.lower() == "mg/l")
    df["mcl_mgL"]  = mcl
    df["ratio"]     = value_mgl / df["mcl_mgL"]
    df["near_mcl"]  = ((df["ratio"] >= 0.5) & (df["ratio"] < 1.0)).astype(int)
    df["above_mcl"] = (df["ratio"] >= 1.0).astype(int)
    n_valid = int(df["ratio"].notna().sum())
    print(f"  MCL ratio computed for {n_valid:,} rows; "
          f"near_mcl={int(df['near_mcl'].sum()):,}, above_mcl={int(df['above_mcl'].sum()):,}")
    return df


# ---------------------------------------------------------------------------
# Step 3: MR violation load + vectorized forward/past window match, run
# separately per chemical so matches stay same-contaminant (a barium
# reading must not be matched to an arsenic MR violation).
# ---------------------------------------------------------------------------
def load_violations_for_code(code: str) -> pd.DataFrame:
    cols = ["PWSID", "NON_COMPL_PER_BEGIN_DATE", "VIOLATION_CATEGORY_CODE", "CONTAMINANT_CODE"]
    df = pd.read_parquet(VIOL_INPUT, engine="pyarrow", columns=cols)

    contam_str = df["CONTAMINANT_CODE"].astype(str).str.strip()
    is_code = contam_str.isin([code, f"{code}.0"])

    df = df[(df["VIOLATION_CATEGORY_CODE"] == "MR") & is_code].copy()

    df["viol_date"] = pd.to_datetime(df["NON_COMPL_PER_BEGIN_DATE"], format="%m/%d/%Y", errors="coerce")
    n_unparseable = int(df["viol_date"].isna().sum())
    df = df[df["viol_date"].notna() & (df["viol_date"].dt.year >= 1990)].copy()
    print(f"  MR violations (code={code}): {len(df):,} rows "
          f"(dropped {n_unparseable:,} unparseable dates)")

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
    frames = []
    for chem_name, (mdb_path, code, mcl, epa_mdl) in CHEMS.items():
        print(f"\n=== {chem_name} (code={code}, MCL={mcl} mg/L) ===")
        print(f"Reading SYR2 .mdb: {mdb_path}")
        try:
            df = read_syr2_mdb(mdb_path, chem_name)
        except Exception as e:
            print(f"[ERROR] Failed to read SYR2 .mdb for {chem_name}: {type(e).__name__}: {e}")
            raise
        df["PWSID"] = df["PWSID"].astype(str)
        df["YEAR"]  = df["YEAR"].astype("int64")
        print(f"  Raw SYR2 rows: {len(df):,} | year range {df['YEAR'].min()}-{df['YEAR'].max()}")

        national_detect_rate = float((df["DETECT"] == 1).mean())
        print(f"  National detection rate: {100 * national_detect_rate:.1f}%")

        df = impute_nondetects_ravalli(df)
        df = impute_nondetects_epa_fallback(df, epa_mdl)
        df = normalize_units(df)
        df = drop_gross_outliers(df, mcl)
        df = compute_mcl_ratio(df, mcl)
        df["contaminant_code"] = code

        viol = load_violations_for_code(code)
        df = attach_mr_flags_vectorized(df, viol)

        frames.append(df)

    ioc = pd.concat(frames, ignore_index=True)

    out_cols = ["PWSID", "contaminant_code", "CHEMID_name", "sample_date", "YEAR",
                "VALUE", "mcl_mgL", "ratio", "near_mcl", "above_mcl", "DETECT",
                "mr_same_fwd", "mr_same_fwd6mon", "mr_same_past", "mr_same_past6mon"]
    ioc = ioc[out_cols].copy()
    ioc["PWSID"]       = ioc["PWSID"].astype(str)
    ioc["YEAR"]        = ioc["YEAR"].astype("int64")
    ioc["sample_date"] = pd.to_datetime(ioc["sample_date"])

    print("\n=== Pooled summary ===")
    print(f"Total rows: {len(ioc):,}")
    print(ioc.groupby("CHEMID_name").agg(
        n=("PWSID", "size"),
        n_pwsid=("PWSID", "nunique"),
        near_mcl=("near_mcl", "sum"),
        above_mcl=("above_mcl", "sum"),
    ))

    n_near_total = int(ioc["near_mcl"].sum())
    print(f"\n=== Pooled near_mcl==1 readings (50-100% of MCL): {n_near_total:,} ===")
    if n_near_total < 5000:
        print(f"[WARNING] Pooled near_mcl count ({n_near_total}) is below the "
              f"expected ~7,100 (power check ran short) -- investigate before proceeding.")
    zero_chem = ioc.groupby("CHEMID_name")["near_mcl"].sum()
    if (zero_chem == 0).any():
        print(f"[WARNING] Chemical(s) with zero near_mcl readings: "
              f"{zero_chem[zero_chem == 0].index.tolist()}")

    print("\nOutcome means:")
    print(ioc[["mr_same_fwd", "mr_same_fwd6mon", "mr_same_past", "mr_same_past6mon"]].mean())

    print(f"\nFinal dtypes:\n{ioc.dtypes}")
    print(f"\nFinal row count: {len(ioc):,}")

    if OUTPUT.exists():
        print(f"\nWARNING: {OUTPUT} already exists -- overwriting")
    ioc.to_parquet(OUTPUT, index=False, engine="pyarrow")
    v = pd.read_parquet(OUTPUT, engine="pyarrow")
    print(f"Written {len(v):,} rows x {v.shape[1]} columns to {OUTPUT}")
