# ============================================================
# Script: cws_6year_review_measurement_dates_full.py
# Purpose: Build a measurement-level (PWSID x chemical x sample_date) panel
#          of SYR2 readings for the main 2SLS downstream-only CWS sample
#          (minehuc_downstream_of_mine==1 & minehuc_mine==0) and the 5 IOC
#          contaminants that survive the detection-rate filter (arsenic,
#          barium, chromium, nitrate, selenium), preserving the exact
#          sample_date instead of collapsing to PWSID x chemical x year, so
#          a rolling 12-month window can be built from the exact test date.
#          Standard (non-Ravalli) pipeline — matches
#          clean_data/cws_6year_review.parquet's cleaning, just without the
#          year-collapse step. SYR2 only: the downstream R scripts that
#          consume this file filter to year<=2005, entirely inside the SYR2
#          window, so SYR3 (2006-2011) is not read. Reuses (copies, does not
#          edit) reader/cleaning logic from cws_6year_review.py.
# Inputs:  raw_data/6_year_review_epa/six-year-review 2/**/*.mdb (SYR2 only)
#          clean_data/cws_data/prod_vio_sulfur.parquet (for downstream-only PWSID set)
# Outputs: clean_data/cws_6year_review_measurement_level_full.parquet
# Author: EK  Date: 2026-07-11
# ============================================================

import pathlib
import re

import pyodbc
import pandas as pd

PROJECT_ROOT = pathlib.Path(r"Z:\ek559\mining_wq")
SYR2_ROOT    = PROJECT_ROOT / "raw_data" / "6_year_review_epa" / "six-year-review 2"
MAIN_DATASET = PROJECT_ROOT / "clean_data" / "cws_data" / "prod_vio_sulfur.parquet"
OUTPUT       = PROJECT_ROOT / "clean_data" / "cws_6year_review_measurement_level_full.parquet"

# 5 IOC contaminants used in the main 2SLS sample (downstream-only).
CHEMICALS = ["arsenic", "barium", "chromium", "nitrate", "selenium"]

PRESENCE_ABSENCE_CHEMS: set[str] = set()
DETECT_RATE_MIN = 0.10

KEEP_COLS = ["PWSID", "CHEMID_name", "DETECT", "VALUE", "UNITS", "YEAR", "sample_date"]

# ---------------------------------------------------------------------------
# MCL schedule + unit tables, copied verbatim from cws_6year_review.py
# (needed only for the >100x MCL gross-outlier drop), trimmed to the 5 IOCs.
# ---------------------------------------------------------------------------
_MCL_RECORDS: list[tuple] = [
    ("nitrate",   None, None, 10.000, "mg/L"),
    ("arsenic",   None, 2005,  0.050, "mg/L"),
    ("arsenic",   2006, None,  0.010, "mg/L"),
    ("barium",    None, None,  2.000, "mg/L"),
    ("chromium",  None, None,  0.100, "mg/L"),
    ("selenium",  None, None,  0.050, "mg/L"),
]

_UNIT_CONV: dict[tuple[str, str], float] = {
    ("mg/l", "mg/l"): 1.0,
    ("ug/l", "mg/l"): 1e-3,
    ("µg/l", "mg/l"): 1e-3,
    ("ng/l", "mg/l"): 1e-6,
}

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


def _unit_dim_factor(units: pd.Series) -> tuple[pd.Series, pd.Series]:
    n = units.map(_norm_unit)
    dim = n.map(lambda x: _UNIT_DIM.get(x, (None, float("nan")))[0])
    fac = n.map(lambda x: _UNIT_DIM.get(x, (None, float("nan")))[1]).astype(float)
    return dim, fac


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
    """Read a SYR2 Access .mdb file via pyodbc, keeping the exact sample date."""
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
    df["sample_date"] = pd.to_datetime(df["DATE"])
    df["YEAR"]        = df["sample_date"].dt.year
    df["CHEMID_name"] = chem_name
    df["PWSID"]       = df["PWSID"].astype(str).str.strip()
    df["UNITS"]       = df["UNITS"].astype(str).str.strip().where(lambda s: s != "nan")
    df["DETECT"]      = pd.to_numeric(df["DETECT"], errors="coerce")
    df["VALUE"]       = pd.to_numeric(df["VALUE"],  errors="coerce")

    if chem_name in PRESENCE_ABSENCE_CHEMS and "Presence Indicator Code" in df.columns:
        pic = df["Presence Indicator Code"].astype(str).str.strip()
        df["VALUE"]  = pic.map({"P": 1.0, "A": 0.0})
        df["DETECT"] = df["VALUE"]
        df["UNITS"]  = "binary"

    return df[KEEP_COLS].copy()


def build_chemical_panel(
    chemicals: list[str], ds_pwsids: set[str]
) -> tuple[pd.DataFrame, dict[str, float]]:
    """Read SYR2-only files for each chemical. The national (pre-downstream-filter)
    detection rate is computed from the full read of each chemical's file, since the
    >10% detection-rate filter (report_detection_rates) is meant to reflect national
    reliability, not the small downstream-only subsample. The working panel used for
    all subsequent cleaning/output is filtered to downstream-only PWSIDs immediately
    after each read. Matches the pattern in cws_6year_review_measurement_dates.py."""
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
              f"{len(df):,} downstream-only rows | "
              f"years {df['YEAR'].min()}-{df['YEAR'].max()}")
        frames.append(df)

    if not frames:
        raise RuntimeError("No chemical data loaded. Check CHEMICALS list and raw data paths.")

    master = pd.concat(frames, ignore_index=True)
    master["PWSID"] = master["PWSID"].astype(str)
    master["YEAR"]  = master["YEAR"].astype("int64")
    print(f"\nDownstream-only measurement-level panel: {len(master):,} rows x {master.shape[1]} columns")
    print(f"Chemicals loaded: {sorted(master['CHEMID_name'].unique())}")
    print(f"Year range: {master['YEAR'].min()}-{master['YEAR'].max()}")
    return master, national_detect_rates


def normalize_units(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()
    dim, fac = _unit_dim_factor(df["UNITS"])
    is_mass  = dim.eq("mass")
    is_radio = dim.eq("radio")
    df.loc[is_mass,  "VALUE"] = df.loc[is_mass,  "VALUE"] * fac[is_mass]
    df.loc[is_mass,  "UNITS"] = "mg/L"
    df.loc[is_radio, "VALUE"] = df.loc[is_radio, "VALUE"] * fac[is_radio]
    df.loc[is_radio, "UNITS"] = "pCi/L"
    print(f"\nUnit normalization: {int(is_mass.sum()):,} mass->mg/L, "
          f"{int(is_radio.sum()):,} radio->pCi/L")
    return df


def report_detection_rates(
    df: pd.DataFrame, min_rate: float, national_detect_rates: dict[str, float]
) -> pd.DataFrame:
    """Apply the >10% detection-rate filter using NATIONAL (pre-downstream-filter)
    detection rates, not the rate within the small downstream-only subsample -- a
    chemical's reliability is a property of the assay nationally, and the
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


def _attach_mcl(df: pd.DataFrame) -> tuple[pd.Series, pd.Series]:
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

    def _norm(s: pd.Series) -> pd.Series:
        return s.fillna("").str.lower().str.replace(r"\s+", "", regex=True)

    data_unit_norm = _norm(df["UNITS"])
    mcl_unit_norm  = _norm(mcl_unit.astype(str).where(mcl_unit.notna()))

    conv_factor = pd.Series(
        [_UNIT_CONV.get((d, m), float("nan")) for d, m in zip(data_unit_norm, mcl_unit_norm)],
        index=df.index, dtype=float,
    )
    value_adj = df["VALUE"] * conv_factor
    return value_adj, mcl


def drop_gross_outliers(df: pd.DataFrame, factor: float = 100.0) -> pd.DataFrame:
    value_adj, mcl = _attach_mcl(df)
    gross = value_adj.notna() & mcl.notna() & (value_adj > factor * mcl)
    n = int(gross.sum())
    if n:
        by = df.loc[gross].groupby("CHEMID_name").size()
        print(f"\nGross-outlier drop (> {factor:g}x MCL): {n:,} rows")
        print(by.to_string())
    else:
        print(f"\nGross-outlier drop (> {factor:g}x MCL): 0 rows")
    return df.loc[~gross].copy()


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
    master = normalize_units(master)
    master = report_detection_rates(master, DETECT_RATE_MIN, national_detect_rates)
    master = drop_gross_outliers(master)

    master = master[["PWSID", "CHEMID_name", "sample_date", "YEAR", "VALUE", "DETECT", "UNITS"]].copy()
    master["PWSID"]       = master["PWSID"].astype(str)
    master["YEAR"]        = master["YEAR"].astype("int64")
    master["sample_date"] = pd.to_datetime(master["sample_date"])

    print(f"\nFinal dtypes:\n{master.dtypes}")
    print(f"Final row count: {len(master):,}")

    if OUTPUT.exists():
        print(f"\nWARNING: {OUTPUT} already exists -- overwriting")
    master.to_parquet(OUTPUT, index=False, engine="pyarrow")
    v = pd.read_parquet(OUTPUT, engine="pyarrow")
    print(f"Written {len(v):,} rows x {v.shape[1]} columns to {OUTPUT}")
