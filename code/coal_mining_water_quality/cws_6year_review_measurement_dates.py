# ============================================================
# Script: cws_6year_review_measurement_dates.py
# Purpose: Build a measurement-level (PWSID x contaminant x sample_date)
#          panel of SYR2 inorganic-chemical concentrations for the
#          downstream-only mining sample, with sample_date preserved
#          (no year collapse). Applies Ravalli et al. (2022) non-detect
#          imputation (record-specific MDL/sqrt(2), with an EPA
#          method-MDL fallback for unreliable/missing record-specific
#          LODs), unit normalization, the >10% detection-rate filter,
#          and the >100x MCL gross-outlier exclusion. Reuses (copies,
#          does not edit) reader/cleaning logic from cws_6year_review.py.
# Inputs:  - raw_data/6_year_review_epa/six-year-review 2/**/*.mdb (SYR2 only)
#          - clean_data/cws_data/prod_vio_sulfur.parquet (for downstream-only PWSID set)
# Outputs: - clean_data/cws_6year_review_measurement_level_syr2.parquet
# Author: EK  Date: 2026-06-23
# ============================================================

import math
import pathlib
import re

import pyodbc
import pandas as pd

PROJECT_ROOT = pathlib.Path(r"Z:\ek559\mining_wq")
SYR2_ROOT    = PROJECT_ROOT / "raw_data" / "6_year_review_epa" / "six-year-review 2"
MAIN_DATASET = PROJECT_ROOT / "clean_data" / "cws_data" / "prod_vio_sulfur.parquet"
OUTPUT       = PROJECT_ROOT / "clean_data" / "cws_6year_review_measurement_level_syr2.parquet"

# The 14 IOC chemicals (CLAUDE.md / plan code set). VOC/SOC/radionuclide/coliform dropped.
CHEMICALS = [
    "arsenic", "barium", "cadmium", "chromium", "cyanide", "fluoride",
    "mercury", "nitrate", "nitrite", "selenium", "antimony", "beryllium",
    "thallium", "asbestos",
]

# Chemical name -> SDWA CONTAMINANT_CODE (matches SYR2 filename _ChemNNNN suffix
# and SDWA_VIOLATIONS_ENFORCEMENT.CONTAMINANT_CODE, verified string match).
IOC_CODE: dict[str, str] = {
    "arsenic": "1005", "barium": "1010", "cadmium": "1015", "chromium": "1020",
    "cyanide": "1024", "fluoride": "1025", "mercury": "1035", "nitrate": "1040",
    "nitrite": "1041", "selenium": "1045", "antimony": "1074", "beryllium": "1075",
    "thallium": "1085", "asbestos": "1094",
}

DETECT_RATE_MIN = 0.10

# Sample date + MDL columns carried through for the lag-window match in step 2.
KEEP_COLS = ["PWSID", "CHEMID_name", "DETECT", "VALUE", "UNITS", "YEAR",
             "sample_date", "MDL", "MDL_UNITS"]

# ---------------------------------------------------------------------------
# MCL schedule (IOCs only) -- copied from cws_6year_review.py, restricted to
# the chemicals in CHEMICALS. Time-varying only for arsenic (Arsenic Rule,
# compliance Jan 23 2006); irrelevant here since SYR2 ends 2005.
# ---------------------------------------------------------------------------
_MCL_RECORDS: list[tuple] = [
    ("nitrate",   None, None, 10.000, "mg/L"),
    ("nitrite",   None, None,  1.000, "mg/L"),
    ("arsenic",   None, 2005,  0.050, "mg/L"),
    ("arsenic",   2006, None,  0.010, "mg/L"),
    ("barium",    None, None,  2.000, "mg/L"),
    ("cadmium",   None, None,  0.005, "mg/L"),
    ("chromium",  None, None,  0.100, "mg/L"),
    ("cyanide",   None, None,  0.200, "mg/L"),
    ("fluoride",  None, None,  4.000, "mg/L"),
    ("mercury",   None, None,  0.002, "mg/L"),
    ("selenium",  None, None,  0.050, "mg/L"),
    ("antimony",  None, None,  0.006, "mg/L"),
    ("beryllium", None, None,  0.004, "mg/L"),
    ("thallium",  None, None,  0.002, "mg/L"),
    ("asbestos",  None, None,  7.000, "mfl"),   # million fibers/L > 10 um
]

_UNIT_CONV: dict[tuple[str, str], float] = {
    ("mg/l", "mg/l"): 1.0,
    ("ug/l", "mg/l"): 1e-3,
    ("µg/l", "mg/l"): 1e-3,
    ("ng/l", "mg/l"): 1e-6,
    ("mfl",  "mfl"):  1.0,
}

_UNIT_DIM: dict[str, tuple[str, float]] = {
    "mg/l": ("mass",     1.0),
    "ug/l": ("mass",     1e-3),
    "µg/l": ("mass",     1e-3),
    "ng/l": ("mass",     1e-6),
    "mfl":  ("fibercnt", 1.0),
}

# EPA method detection limits (MDL, mg/L) -- fallback for non-detect records with
# no reliable record-specific LOD (Ravalli et al. 2022 appendix p3-4: LOD missing,
# reported in non-mass units, or LOD > 5 ug/L = 0.005 mg/L are treated as unreliable).
# Representative values from EPA method validation studies: Method 200.8 Rev. 5.4
# (trace metals, ICP-MS), Method 300.0 Rev. 2.1 (anions, ion chromatography),
# Method 245.1 Rev. 3.0 (mercury, CVAA), Method 335.4 Rev. 1.0 (cyanide, colorimetric).
# Approximate -- actual published MDLs vary by lab/method revision; chemicals not
# listed here (asbestos, measured in MFL not mass) keep the standard non-detect path.
EPA_METHOD_MDL_MGL: dict[str, float] = {
    "arsenic":   0.0014,
    "barium":    0.0010,
    "cadmium":   0.0001,
    "chromium":  0.0007,
    "selenium":  0.0016,
    "antimony":  0.0006,
    "beryllium": 0.0002,
    "thallium":  0.0002,
    "mercury":   0.0002,
    "cyanide":   0.0050,
    "fluoride":  0.0100,
    "nitrate":   0.0100,
    "nitrite":   0.0050,
}
# Unreliable-LOD threshold per Ravalli appendix p3: > 5 ug/L = 0.005 mg/L.
UNRELIABLE_LOD_MGL = 0.005


def _norm_unit(s) -> str:
    if s is None or (isinstance(s, float) and pd.isna(s)):
        return ""
    return str(s).strip().lower().replace(" ", "")


def normalize_chem(s: str) -> str:
    s = s.lower()
    s = re.sub(r"_chem\d+.*$", "", s)
    s = re.sub(r"\s*\(gross\s+beta\)", "", s)
    s = re.sub(r"\s*\(as\s+[a-z]+\)", "", s)
    s = re.sub(r"\s*\((inorganic|total|combined)\)", "", s)
    s = re.sub(r"[_\-]?(combined|total)\s*$", "", s)
    s = re.sub(r"[\[\]\(\)]", "", s)
    s = re.sub(r"\b\d{2,}\b", "", s)
    s = re.sub(r"[-_,\s]+", " ", s)
    return s.strip().replace(" ", "")


def _build_catalog(root: pathlib.Path, glob: str) -> dict[str, pathlib.Path]:
    catalog: dict[str, pathlib.Path] = {}
    for p in root.rglob(glob):
        key = normalize_chem(p.stem)
        if key in catalog:
            print(f"  [WARN] duplicate normalized key '{key}': "
                  f"{catalog[key].name} vs {p.name} -- keeping first")
        else:
            catalog[key] = p
    return catalog


def find_file(chem_name: str, catalog: dict[str, pathlib.Path]) -> pathlib.Path | None:
    query_key = normalize_chem(chem_name)
    if query_key in catalog:
        return catalog[query_key]
    hits = [k for k in catalog if query_key in k]
    if not hits:
        hits = [k for k in catalog if k in query_key]
    if not hits:
        return None
    if len(hits) > 1:
        print(f"  [WARN] '{chem_name}' matches multiple SYR2 entries: "
              f"{[catalog[k].name for k in hits]}. Using first.")
    return catalog[hits[0]]


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


def build_chemical_panel(
    chemicals: list[str], ds_pwsids: set[str]
) -> tuple[pd.DataFrame, dict[str, float]]:
    """Read SYR2-only files for each chemical. The national (pre-downstream-filter)
    detection rate is computed from the full read of each chemical's file, since the
    >10% Ravalli detection-rate filter (report_detection_rates) is meant to reflect
    national reliability, not the small downstream-only subsample. The working panel
    used for all subsequent cleaning/output is still filtered to downstream-only
    PWSIDs immediately after each read (cuts data ~99% before heavy cleaning)."""
    syr2_catalog = _build_catalog(SYR2_ROOT, "*.mdb")
    print(f"Catalog: {len(syr2_catalog)} SYR2 files\n")

    frames: list[pd.DataFrame] = []
    national_detect_rates: dict[str, float] = {}
    for chem_name in chemicals:
        syr2_path = find_file(chem_name, syr2_catalog)
        if syr2_path is None:
            print(f"  [WARN] '{chem_name}': no SYR2 file found -- skipped")
            continue
        df = read_syr2_mdb(syr2_path, chem_name)
        n_raw = len(df)
        national_detect_rates[chem_name] = float((df["DETECT"] == 1).mean())

        df = df[df["PWSID"].isin(ds_pwsids)].copy()
        print(f"  {chem_name}: {syr2_path.name}: {n_raw:,} raw rows "
              f"(national detect rate {100 * national_detect_rates[chem_name]:.1f}%) -> "
              f"{len(df):,} downstream-only rows")
        frames.append(df)

    if not frames:
        raise RuntimeError("No chemical data loaded. Check CHEMICALS list and raw data paths.")

    master = pd.concat(frames, ignore_index=True)
    master["PWSID"] = master["PWSID"].astype(str)
    master["YEAR"]  = master["YEAR"].astype("int64")
    print(f"\nDownstream-only SYR2 panel: {len(master):,} rows x {master.shape[1]} columns")
    print(f"Chemicals loaded: {sorted(master['CHEMID_name'].unique())}")
    print(f"Year range: {master['YEAR'].min()}-{master['YEAR'].max()}")
    return master, national_detect_rates


def impute_nondetects_ravalli(df: pd.DataFrame) -> pd.DataFrame:
    """Step 1.5a: record-specific MDL/sqrt(2) imputation (Ravalli et al. 2022)."""
    df = df.copy()
    mask = (df["DETECT"] == 0) & df["MDL"].notna()
    n_imputed = int(mask.sum())
    df.loc[mask, "VALUE"] = df.loc[mask, "MDL"] / math.sqrt(2)
    print(f"\nRavalli MDL/sqrt(2) imputation (record-specific): {n_imputed:,} records imputed")
    return df


def impute_nondetects_epa_fallback(df: pd.DataFrame) -> pd.DataFrame:
    """Step 1.5b (NEW): EPA method-MDL/sqrt(2) fallback for non-detects with no
    reliable record-specific LOD -- MDL missing, MDL_UNITS not a mass unit, or
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

    epa_mdl = df["CHEMID_name"].map(EPA_METHOD_MDL_MGL)
    can_fallback = unreliable & epa_mdl.notna()

    df.loc[can_fallback, "VALUE"] = epa_mdl[can_fallback] / math.sqrt(2)
    df.loc[can_fallback, "UNITS"] = "mg/L"

    no_fallback = unreliable & epa_mdl.isna()
    if no_fallback.any():
        by = df.loc[no_fallback, "CHEMID_name"].value_counts()
        print(f"\nEPA method-MDL fallback: no EPA MDL available for "
              f"{int(no_fallback.sum()):,} unreliable non-detects -- left as "
              f"standard non-detect:\n{by.to_string()}")

    print(f"\nEPA method-MDL fallback (Step 1.5b): {int(can_fallback.sum()):,} "
          f"unreliable-LOD non-detects imputed via EPA method MDL/sqrt(2)")
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


def report_detection_rates(
    df: pd.DataFrame, min_rate: float, national_detect_rates: dict[str, float]
) -> pd.DataFrame:
    """Apply the >10% Ravalli detection-rate filter using NATIONAL (pre-downstream-
    filter) detection rates, not the rate within the small downstream-only subsample
    -- a chemical's reliability is a property of the assay nationally, and the
    downstream-only sample is too small to estimate it on its own."""
    rates = pd.Series(national_detect_rates).sort_values()
    print("\nDetection rates (national, share of records above LOD):")
    drop: list[str] = []
    for chem, r in rates.items():
        if chem not in df["CHEMID_name"].unique():
            continue
        below = r < min_rate
        flag = "   <-- below threshold (dropped)" if below else ""
        print(f"  {chem:12s} {100 * r:5.1f}%{flag}")
        if below:
            drop.append(chem)
    if drop:
        print(f"\nDetection-rate filter (< {100 * min_rate:.0f}%, national): dropping "
              f"{len(drop)} chemicals: {drop}")
        df = df.loc[~df["CHEMID_name"].isin(drop)].copy()
    return df


def _attach_mcl(df: pd.DataFrame) -> tuple[pd.Series, pd.Series, pd.Series]:
    mcl      = pd.Series(float("nan"), index=df.index)
    mcl_unit = pd.Series(None, index=df.index, dtype="object")
    for chem_name, y_min, y_max, mcl_val, mcl_unit_v in _MCL_RECORDS:
        mask = df["CHEMID_name"] == chem_name
        if y_min is not None:
            mask = mask & (df["YEAR"] >= y_min)
        if y_max is not None:
            mask = mask & (df["YEAR"] <= y_max)
        mcl.loc[mask]      = mcl_val
        mcl_unit.loc[mask] = mcl_unit_v

    data_unit_norm = df["UNITS"].fillna("").str.lower().str.replace(r"\s+", "", regex=True)
    mcl_unit_norm  = mcl_unit.astype(str).where(mcl_unit.notna()).fillna("").str.lower().str.replace(r"\s+", "", regex=True)
    conv_factor = pd.Series(
        [_UNIT_CONV.get((d, m), float("nan")) for d, m in zip(data_unit_norm, mcl_unit_norm)],
        index=df.index, dtype=float,
    )
    value_adj = df["VALUE"] * conv_factor
    return value_adj, mcl, mcl_unit


def drop_gross_outliers(df: pd.DataFrame, factor: float = 100.0) -> pd.DataFrame:
    value_adj, mcl, _ = _attach_mcl(df)
    gross = value_adj.notna() & mcl.notna() & (value_adj > factor * mcl)
    n = int(gross.sum())
    if n:
        by = df.loc[gross].groupby("CHEMID_name").size()
        print(f"\nGross-outlier drop (> {factor:g}x MCL): {n:,} rows")
        print(by.to_string())
    else:
        print(f"\nGross-outlier drop (> {factor:g}x MCL): 0 rows")
    return df.loc[~gross].copy()


def compute_mcl_ratio(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()
    value_adj, mcl, mcl_unit = _attach_mcl(df)
    df["mcl_mgL"] = mcl.where(mcl_unit.astype(str).str.lower() == "mg/l")
    df["ratio"]   = value_adj / df["mcl_mgL"]
    df["near_mcl"]  = ((df["ratio"] >= 0.5) & (df["ratio"] < 1.0)).astype(int)
    df["above_mcl"] = (df["ratio"] >= 1.0).astype(int)
    n_valid = int(df["ratio"].notna().sum())
    print(f"\nMCL ratio computed for {n_valid:,} rows; "
          f"near_mcl={int(df['near_mcl'].sum()):,}, above_mcl={int(df['above_mcl'].sum()):,}")
    return df


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

    master, national_detect_rates = build_chemical_panel(CHEMICALS, ds_pwsids)
    master = impute_nondetects_ravalli(master)
    master = impute_nondetects_epa_fallback(master)
    master = normalize_units(master)
    master = report_detection_rates(master, DETECT_RATE_MIN, national_detect_rates)
    master = drop_gross_outliers(master)
    master = compute_mcl_ratio(master)
    master["contaminant_code"] = master["CHEMID_name"].map(IOC_CODE)

    out_cols = ["PWSID", "contaminant_code", "CHEMID_name", "sample_date", "YEAR",
                "VALUE", "mcl_mgL", "ratio", "near_mcl", "above_mcl", "DETECT"]
    master = master[out_cols].copy()
    master["PWSID"]       = master["PWSID"].astype(str)
    master["YEAR"]        = master["YEAR"].astype("int64")
    master["sample_date"] = pd.to_datetime(master["sample_date"])

    print(f"\nSurviving chemicals: {sorted(master['CHEMID_name'].unique())}")
    print(f"\nFinal dtypes:\n{master.dtypes}")
    print(f"\nFinal row count: {len(master):,}")

    if OUTPUT.exists():
        print(f"\nWARNING: {OUTPUT} already exists -- overwriting")
    master.to_parquet(OUTPUT, index=False, engine="pyarrow")
    v = pd.read_parquet(OUTPUT, engine="pyarrow")
    print(f"Written {len(v):,} rows x {v.shape[1]} columns to {OUTPUT}")
