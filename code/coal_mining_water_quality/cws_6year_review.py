# ============================================================
# Script: cws_6year_review.py
# Purpose: Build a PWSID-level panel from EPA 6-Year Review
#          data (SYR2 .mdb files + SYR3 .txt files) and merge
#          to the main 2SLS dataset. User only sets CHEMICALS.
#          A single detection-rate filter is applied: chemicals
#          whose national share of records above the LOD is below
#          DETECT_RATE_MIN are dropped (presence/absence chemicals
#          are exempt).
# Inputs:  - raw_data/6_year_review_epa/six-year-review 2/**/*.mdb
#          - raw_data/6_year_review_epa/six-year-review 3/**/*.txt
#          - clean_data/cws_data/prod_vio_sulfur.parquet
# Outputs: - clean_data/cws_6year_review_chemicals.parquet         (standard, pre-merge)
#          - clean_data/cws_6year_review.parquet                   (standard, merged to 2SLS)
#          - clean_data/cws_6year_review_chemicals_ravalli.parquet (Ravalli, pre-merge)
#          - clean_data/cws_6year_review_ravalli.parquet           (Ravalli, merged to 2SLS)
# Author: EK  Date: 2026-05-27
# ============================================================

import math
import pathlib
import re
import pyodbc
import pandas as pd

PROJECT_ROOT  = pathlib.Path(r"Z:\ek559\mining_wq")
SYR2_ROOT     = PROJECT_ROOT / "raw_data" / "6_year_review_epa" / "six-year-review 2"
SYR3_ROOT     = PROJECT_ROOT / "raw_data" / "6_year_review_epa" / "six-year-review 3"
MAIN_DATASET  = PROJECT_ROOT / "clean_data" / "cws_data" / "prod_vio_sulfur.parquet"
CHEM_OUTPUT          = PROJECT_ROOT / "clean_data" / "cws_6year_review_chemicals.parquet"
MERGED_OUTPUT        = PROJECT_ROOT / "clean_data" / "cws_6year_review.parquet"
CHEM_OUTPUT_RAVALLI  = PROJECT_ROOT / "clean_data" / "cws_6year_review_chemicals_ravalli.parquet"
MERGED_OUTPUT_RAVALLI= PROJECT_ROOT / "clean_data" / "cws_6year_review_ravalli.parquet"

# MDL / MDL_UNITS carry the record-specific detection limit for the Ravalli pipeline.
# SYR2: MDL = VALUE when DETECT==0 (per SYR2 data dictionary, VALUE stores the MRL for non-detects).
# SYR3: MDL = "Detection Limit Value"; MDL_UNITS = "Detection Limit Unit".
KEEP_COLS = ["PWSID", "CHEMID_name", "DETECT", "VALUE", "UNITS", "YEAR", "MDL", "MDL_UNITS"]

# Detection-rate filter threshold: chemicals whose national share of records
# above the LOD (DETECT == 1) is below this value are dropped. Presence/absence
# chemicals (total coliform) are exempt. Set to 0.0 to keep all chemicals.
DETECT_RATE_MIN = 0.10

# SYR3 chemicals where VALUE is always NaN and presence is encoded in
# "Presence Indicator Code" (P = present, A = absent).  For these, read_syr3_txt
# derives VALUE = 1.0 (P) / 0.0 (A) and sets UNITS = "binary".
PRESENCE_ABSENCE_CHEMS: set[str] = {"total coliform"}

# ---------------------------------------------------------------------------
# MCL schedule and unit conversions
# ---------------------------------------------------------------------------
#
# MCL source citations (for independent verification):
#   Phase I VOCs  — 52 FR 25690 (Jul 8 1987); 40 CFR 141.61(a); effective Jan 9 1989
#   Phase II IOCs/SOCs — 56 FR 3526 (Jan 30 1991); 40 CFR 141.61(c) & 141.62(b);
#       compliance Jan 1 1993 (≥ 10,000 service connections), Jan 1 1994 (smaller)
#   Arsenic rule  — 66 FR 6976 (Jan 22 2001); 40 CFR 141.62(b); compliance Jan 23 2006
#   Uranium rule  — 65 FR 76708 (Dec 7 2000); 40 CFR 141.66(b); compliance Dec 8 2003
#   Total Coliform Rule (TCR) — 54 FR 27544 (Jun 29 1989); 40 CFR 141.63;
#       effective Dec 31 1990; individual-sample encoding: P = present (above MCL),
#       A = absent (below MCL); replaced by RTCR Apr 1 2016 (outside study window)
#
# Each record: (CHEMID_name, year_min, year_max, mcl_value, mcl_unit)
# year_min / year_max = None means open-ended (earliest / latest data).
# Omitting a chemical entirely means no MCL applies → above_mcl = NaN.
# To add a time-varying change, append a new record with the new year range.
_MCL_RECORDS: list[tuple] = [
    # ---- Nitrate ----
    # 40 CFR 141.62(b); Phase II; stable
    ("nitrate",               None, None, 10.000, "mg/L"),

    # ---- Arsenic ----
    # 40 CFR 141.62(b); Phase II then Arsenic rule
    # 0.05 mg/L until end of 2005; 0.01 mg/L from 2006 (compliance date Jan 23 2006)
    ("arsenic",               None, 2005,  0.050, "mg/L"),
    ("arsenic",               2006, None,  0.010, "mg/L"),

    # ---- IOCs: Phase II rule, 40 CFR 141.62(b); all stable 1997–2011 ----
    # 56 FR 3526 (Jan 30 1991); compliance Jan 1 1993
    ("barium",                None, None,  2.000, "mg/L"),
    ("cadmium",               None, None,  0.005, "mg/L"),
    ("chromium",              None, None,  0.100, "mg/L"),  # total chromium
    ("mercury",               None, None,  0.002, "mg/L"),  # inorganic mercury
    ("selenium",              None, None,  0.050, "mg/L"),
    ("thallium",              None, None,  0.002, "mg/L"),
    # Silver: no primary NPDWR MCL (40 CFR 143.3 Secondary MCL only); excluded.

    # ---- SOCs: Phase II rule, 40 CFR 141.61(c); all stable 1997–2011 ----
    # 56 FR 3526 (Jan 30 1991); compliance Jan 1 1993
    ("2,4-D",                 None, None,  0.070, "mg/L"),
    ("2,4,5-TP (Silvex)",     None, None,  0.050, "mg/L"),
    ("endrin",                None, None,  0.002, "mg/L"),
    ("lindane",               None, None,  0.0002,"mg/L"),
    ("methoxychlor",          None, None,  0.040, "mg/L"),
    ("toxaphene",             None, None,  0.003, "mg/L"),

    # ---- VOCs: Phase I rule, 40 CFR 141.61(a); all stable 1997–2011 ----
    # 52 FR 25690 (Jul 8 1987); effective Jan 9 1989
    ("benzene",               None, None,  0.005, "mg/L"),
    ("carbon tetrachloride",  None, None,  0.005, "mg/L"),
    ("1,2-dichloroethane",    None, None,  0.005, "mg/L"),
    ("p-dichlorobenzene",     None, None,  0.075, "mg/L"),  # 1,4-dichlorobenzene
    ("1,1-dichloroethylene",  None, None,  0.007, "mg/L"),
    ("1,1,1-trichloroethane", None, None,  0.200, "mg/L"),
    ("trichloroethylene",     None, None,  0.005, "mg/L"),
    ("vinyl chloride",        None, None,  0.002, "mg/L"),

    # ---- Radionuclides ----
    ("alpha particles",       None, None, 15.000, "pCi/L"),
    # Gross beta: EPA 50 pCi/L screening level (Sr-90 proxy for 4 mrem/yr)
    ("beta particles",        None, None, 50.000, "pCi/L"),
    ("radium",                None, None,  5.000, "pCi/L"),   # combined Ra-226 + Ra-228
    # Uranium: no federal MCL before compliance date Dec 8 2003 → first full year = 2004
    ("uranium",               2004, None,  0.030, "mg/L"),

    # ---- Total Coliforms ----
    # 40 CFR 141.63; TCR effective Dec 31 1990.
    # VALUE is encoded as 1.0 = present (P), 0.0 = absent (A); units = "binary".
    # above_mcl = 1 if VALUE > 0 (any coliform detected).
    ("total coliform",        None, None,  0.0,   "binary"),
]

# Conversion factors: (from_unit_normalized, to_unit_normalized) → multiply VALUE by factor.
# Normalized = lowercase with all whitespace removed.
# Only same-dimension pairs are listed; incompatible unit pairs return NaN (no comparison).
_UNIT_CONV: dict[tuple[str, str], float] = {
    ("mg/l",    "mg/l"):    1.0,
    ("ug/l",    "mg/l"):    1e-3,
    ("µg/l",    "mg/l"):    1e-3,
    ("ng/l",    "mg/l"):    1e-6,
    ("pci/l",   "pci/l"):   1.0,
    ("mrem/yr", "mrem/yr"): 1.0,
    ("binary",  "binary"):  1.0,   # total coliform presence indicator
}

# Unit dimension + factor to that dimension's base unit (mass conc base = mg/L,
# radionuclide base = pCi/L). Used by normalize_units.
_UNIT_DIM: dict[str, tuple[str, float]] = {
    "mg/l":    ("mass",   1.0),
    "ug/l":    ("mass",   1e-3),
    "µg/l":    ("mass",   1e-3),
    "ng/l":    ("mass",   1e-6),
    "pci/l":   ("radio",  1.0),
    "mrem/yr": ("dose",   1.0),
    "binary":  ("binary", 1.0),
}


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

def _norm_unit(s) -> str:
    if s is None or (isinstance(s, float) and pd.isna(s)):
        return ""
    return str(s).strip().lower().replace(" ", "")


def _unit_dim_factor(units: pd.Series) -> tuple[pd.Series, pd.Series]:
    """Map a units Series → (dimension Series, factor-to-base Series)."""
    n = units.map(_norm_unit)
    dim = n.map(lambda x: _UNIT_DIM.get(x, (None, float("nan")))[0])
    fac = n.map(lambda x: _UNIT_DIM.get(x, (None, float("nan")))[1]).astype(float)
    return dim, fac


# ---------------------------------------------------------------------------
# Name normalization and catalog building
# ---------------------------------------------------------------------------

def normalize_chem(s: str) -> str:
    """
    Reduce a chemical name or filename stem to a spaceless lowercase key
    for fuzzy matching across SYR2 and SYR3 naming conventions.

    Handles:
      - SYR2 _ChemNNNN[_update] suffixes
      - Qualifiers: (as N), (Gross beta), (inorganic), (total), _combined
      - Square vs round brackets (Benzo[a]pyrene vs benzo(a)pyrene)
      - CamelCase run-together names (CarbonTetrachloride)
      - Radium-226_228 series numbers
      - Underscore / hyphen / space separator variants
    """
    s = s.lower()
    s = re.sub(r"_chem\d+.*$", "", s)                    # strip _Chem1005[_update]
    s = re.sub(r"\s*\(gross\s+beta\)", "", s)             # strip (Gross beta)
    s = re.sub(r"\s*\(as\s+[a-z]+\)", "", s)              # strip (as n), (as nitrogen)
    s = re.sub(r"\s*\((inorganic|total|combined)\)", "", s)
    s = re.sub(r"[_\-]?(combined|total)\s*$", "", s)      # trailing _combined / -total
    s = re.sub(r"[\[\]\(\)]", "", s)                      # strip all brackets
    s = re.sub(r"\b\d{2,}\b", "", s)                      # strip 2+ digit numbers (226, 228)
    s = re.sub(r"[-_,\s]+", " ", s)                       # normalize all separators → space
    return s.strip().replace(" ", "")                     # spaceless key for substring matching


def _build_catalog(root: pathlib.Path, glob: str) -> dict[str, pathlib.Path]:
    catalog: dict[str, pathlib.Path] = {}
    for p in root.rglob(glob):
        key = normalize_chem(p.stem)
        if key in catalog:
            print(f"  [WARN] duplicate normalized key '{key}': "
                  f"{catalog[key].name} vs {p.name} — keeping first")
        else:
            catalog[key] = p
    return catalog


def find_file(
    chem_name: str,
    catalog: dict[str, pathlib.Path],
    source: str,
) -> pathlib.Path | None:
    """
    Three-pass matching:
      1. Exact normalized key
      2. Query key is a substring of a catalog key   (e.g. "radium" in "combinedradium")
      3. Catalog key is a substring of the query key (e.g. "uranium" in "uraniumcombined")
    Returns None and prints a warning if nothing matches.
    """
    query_key = normalize_chem(chem_name)

    if query_key in catalog:
        return catalog[query_key]

    hits = [k for k in catalog if query_key in k]
    if not hits:
        hits = [k for k in catalog if k in query_key]

    if not hits:
        return None
    if len(hits) > 1:
        print(f"  [WARN] '{chem_name}' matches multiple {source} entries: "
              f"{[catalog[k].name for k in hits]}. Using first.")
    return catalog[hits[0]]


# ---------------------------------------------------------------------------
# File readers — both return a DataFrame with exactly KEEP_COLS
# ---------------------------------------------------------------------------

def read_syr2_mdb(path: pathlib.Path, chem_name: str) -> pd.DataFrame:
    """Read a SYR2 Access .mdb file via pyodbc."""
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
    df["YEAR"]       = pd.to_datetime(df["DATE"]).dt.year
    df["CHEMID_name"] = chem_name
    df["PWSID"]      = df["PWSID"].astype(str).str.strip()
    df["UNITS"]      = df["UNITS"].astype(str).str.strip().where(lambda s: s != "nan")
    df["DETECT"]     = pd.to_numeric(df["DETECT"], errors="coerce")
    df["VALUE"]      = pd.to_numeric(df["VALUE"],  errors="coerce")
    # SYR2 data dictionary: VALUE stores the MRL when DETECT==0.
    # MDL = that MRL; MDL_UNITS = same UNITS as the measured VALUE.
    df["MDL"]       = df["VALUE"].where(df["DETECT"] == 0)
    df["MDL_UNITS"] = df["UNITS"]
    return df[KEEP_COLS].copy()


def read_syr3_txt(path: pathlib.Path, chem_name: str) -> pd.DataFrame:
    """
    Read a SYR3 tab-delimited .txt file.

    SYR3 column mapping → KEEP_COLS:
      PWSID                  → PWSID
      Sample Collection Date → YEAR  (extract year)
      Detect                 → DETECT  (0 = non-detect, 1 = detect)
      Value                  → VALUE   (blank for non-detections)
      Unit                   → UNITS

    For chemicals in PRESENCE_ABSENCE_CHEMS (e.g. total coliform), the Detect
    column is always 0 and Value is always NaN.  VALUE and DETECT are instead
    derived from the "Presence Indicator Code" column: P → 1.0, A → 0.0.
    UNITS is set to "binary" so the MCL comparison in assign_mcl_and_above works.
    """
    df = pd.read_csv(path, sep="\t", low_memory=False)

    df = df.rename(columns={
        "Sample Collection Date": "_DATE",
        "Detect": "DETECT",
        "Value":  "VALUE",
        "Unit":   "UNITS",
        "Detection Limit Value": "MDL",
        "Detection Limit Unit":  "MDL_UNITS",
    })
    df["YEAR"]       = pd.to_datetime(df["_DATE"]).dt.year
    df["CHEMID_name"] = chem_name
    df["PWSID"]      = df["PWSID"].astype(str).str.strip()
    df["UNITS"]      = df["UNITS"].astype(str).str.strip().where(lambda s: s != "nan")
    df["DETECT"]     = pd.to_numeric(df["DETECT"], errors="coerce")
    df["VALUE"]      = pd.to_numeric(df["VALUE"],  errors="coerce")

    # SYR3 detection-limit columns (may not be present in all file versions)
    if "MDL" in df.columns:
        df["MDL"] = pd.to_numeric(df["MDL"], errors="coerce")
    else:
        df["MDL"] = float("nan")
    if "MDL_UNITS" in df.columns:
        df["MDL_UNITS"] = df["MDL_UNITS"].astype(str).str.strip().where(lambda s: s != "nan")
    else:
        df["MDL_UNITS"] = None

    if chem_name in PRESENCE_ABSENCE_CHEMS and "Presence Indicator Code" in df.columns:
        pic = df["Presence Indicator Code"].astype(str).str.strip()
        df["VALUE"]  = pic.map({"P": 1.0, "A": 0.0})
        df["DETECT"] = df["VALUE"]
        df["UNITS"]  = "binary"
        # Presence/absence encoding has no detection limit; clear MDL columns
        df["MDL"]       = float("nan")
        df["MDL_UNITS"] = None
        n_p = int((df["VALUE"] == 1.0).sum())
        n_a = int((df["VALUE"] == 0.0).sum())
        print(f"    [presence-absence] P={n_p:,}  A={n_a:,}  "
              f"unresolved={int(df['VALUE'].isna().sum()):,}")

    return df[KEEP_COLS].copy()


# ---------------------------------------------------------------------------
# Core pipeline
# ---------------------------------------------------------------------------

def build_chemical_panel(chemicals: list[str]) -> pd.DataFrame:
    """
    Auto-discover SYR2 (.mdb) and SYR3 (.txt) files for each chemical,
    read and stack into a sample-level DataFrame with columns KEEP_COLS.
    Both rounds are included when available; time windows do not overlap
    (SYR2 ≈ 1998–2005, SYR3 ≈ 2006–2011).
    """
    syr2_catalog = _build_catalog(SYR2_ROOT, "*.mdb")
    syr3_catalog = _build_catalog(SYR3_ROOT, "*.txt")
    print(f"Catalog: {len(syr2_catalog)} SYR2 files, {len(syr3_catalog)} SYR3 files\n")

    frames: list[pd.DataFrame] = []

    for chem_name in chemicals:
        syr2_path = find_file(chem_name, syr2_catalog, "SYR2")
        syr3_path = find_file(chem_name, syr3_catalog, "SYR3")

        if syr2_path is None and syr3_path is None:
            print(f"  [WARN] '{chem_name}': no file found in SYR2 or SYR3 — skipped")
            continue

        print(f"  {chem_name}:")
        if syr2_path:
            df2 = read_syr2_mdb(syr2_path, chem_name)
            print(f"    SYR2 {syr2_path.name}: {len(df2):,} rows | "
                  f"years {df2['YEAR'].min()}–{df2['YEAR'].max()}")
            frames.append(df2)
        else:
            print(f"    SYR2: not found")

        if syr3_path:
            df3 = read_syr3_txt(syr3_path, chem_name)
            print(f"    SYR3 {syr3_path.name}: {len(df3):,} rows | "
                  f"years {df3['YEAR'].min()}–{df3['YEAR'].max()}")
            frames.append(df3)
        else:
            print(f"    SYR3: not found")

    if not frames:
        raise RuntimeError("No chemical data loaded. Check CHEMICALS list and raw data paths.")

    master = pd.concat(frames, ignore_index=True)
    master["PWSID"] = master["PWSID"].astype(str)
    master["YEAR"]  = master["YEAR"].astype("int64")

    print(f"\nSample-level panel: {len(master):,} rows × {master.shape[1]} columns")
    print(f"Chemicals loaded:   {sorted(master['CHEMID_name'].unique())}")
    print(f"Year range:         {master['YEAR'].min()}–{master['YEAR'].max()}")
    return master


def normalize_units(df: pd.DataFrame) -> pd.DataFrame:
    """
    Convert mass-concentration readings to mg/L and radionuclide readings to
    pCi/L, rewriting UNITS to the base unit. Non-detect rows (VALUE / UNITS NaN)
    are untouched. Normalizing to a single base unit per dimension prevents
    spurious mixed-unit drops in collapse_to_pwsid_year.
    """
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


def report_detection_rates(df: pd.DataFrame, min_rate: float) -> pd.DataFrame:
    """
    Compute, per chemical, the national share of records above the LOD
    (DETECT == 1) and drop chemicals below min_rate. Presence/absence
    chemicals (total coliform) are exempt. Set min_rate = 0 to keep all.
    """
    above = (df["DETECT"] == 1).astype(float)
    rates = above.groupby(df["CHEMID_name"]).mean().sort_values()

    print("\nDetection rates (share of records above LOD):")
    drop: list[str] = []
    for chem, r in rates.items():
        below = (r < min_rate) and (chem not in PRESENCE_ABSENCE_CHEMS)
        flag = "   <-- below threshold (dropped)" if below else ""
        print(f"  {chem:28s} {100 * r:5.1f}%{flag}")
        if below:
            drop.append(chem)

    if drop:
        print(f"\nDetection-rate filter (< {100 * min_rate:.0f}%): dropping {len(drop)} "
              f"chemicals: {drop}")
        df = df.loc[~df["CHEMID_name"].isin(drop)].copy()
    return df


def assign_mcl_and_above(df: pd.DataFrame) -> pd.DataFrame:
    """
    Add above_mcl flag to sample-level data using the time-varying _MCL_RECORDS schedule.

    Algorithm:
      1. For each MCL record, mark matching rows (by chemical + year range) with the MCL value
         and its unit.
      2. Normalize both UNITS and mcl_unit to lowercase-no-spaces, look up a conversion
         factor from _UNIT_CONV.  Pairs with incompatible dimensions produce NaN → excluded.
      3. above_mcl = 1.0  if VALUE (converted to MCL units) > mcl
                   = 0.0  if VALUE ≤ mcl
                   = NaN  if VALUE or mcl is missing, or units are incompatible.

    To add a new chemical or a regulatory change, append a record to _MCL_RECORDS.
    """
    df = df.copy()
    df["mcl"]      = float("nan")
    df["mcl_unit"] = None

    for chem_name, y_min, y_max, mcl_val, mcl_unit in _MCL_RECORDS:
        mask = df["CHEMID_name"] == chem_name
        if y_min is not None:
            mask = mask & (df["YEAR"] >= y_min)
        if y_max is not None:
            mask = mask & (df["YEAR"] <= y_max)
        df.loc[mask, "mcl"]      = mcl_val
        df.loc[mask, "mcl_unit"] = mcl_unit

    def _norm(s: pd.Series) -> pd.Series:
        return s.fillna("").str.lower().str.replace(r"\s+", "", regex=True)

    data_unit_norm = _norm(df["UNITS"])
    mcl_unit_norm  = _norm(df["mcl_unit"].astype(str).where(df["mcl_unit"].notna()))

    conv_factor = pd.Series(
        [_UNIT_CONV.get((d, m), float("nan"))
         for d, m in zip(data_unit_norm, mcl_unit_norm)],
        index=df.index, dtype=float,
    )

    df["above_mcl"] = float("nan")
    has_valid = df["VALUE"].notna() & df["mcl"].notna() & conv_factor.notna()
    value_adj = df.loc[has_valid, "VALUE"] * conv_factor[has_valid]
    df.loc[has_valid, "above_mcl"] = (value_adj > df.loc[has_valid, "mcl"]).astype(float)

    n_valid = int(has_valid.sum())
    n_above = int((df["above_mcl"] == 1.0).sum())
    print(f"\nMCL assignment: {n_valid:,} readings with valid MCL comparison; "
          f"{n_above:,} ({100 * n_above / max(n_valid, 1):.1f}%) exceed MCL")

    return df.drop(columns=["mcl", "mcl_unit"])


def _attach_mcl(df: pd.DataFrame) -> tuple[pd.Series, pd.Series]:
    """
    Look up the applicable MCL (and unit) per row from _MCL_RECORDS and return
    (value_adj, mcl), where value_adj is VALUE converted into the MCL's units
    (NaN where units are incompatible or VALUE missing). Used by drop_gross_outliers.
    """
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
    """
    Drop records whose concentration exceeds factor × MCL (default 100×), treated
    as likely data-entry errors. Only rows with a valid MCL and a compatible unit
    are eligible; all others are kept.
    """
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


def impute_nondetects_ravalli(df: pd.DataFrame) -> pd.DataFrame:
    """
    Ravalli et al. (2022) cleaning: replace non-detect records with MDL / sqrt(2).

    This method is used by the US CDC and other federal agencies when reporting
    geometric or arithmetic means of environmental biomarkers (Ravalli et al.
    Lancet Planet Health 2022; 6: e320-30, appendix 2 p 3).

    SYR2: VALUE already stores the MRL for DETECT==0 records (per SYR2 data
          dictionary).  MDL = VALUE_original; imputed VALUE = MDL / sqrt(2).
    SYR3: VALUE is NaN for non-detects; MDL comes from 'Detection Limit Value'.
          UNITS is also NaN for non-detects and is set from 'Detection Limit Unit'
          so that the subsequent normalize_units() call can convert correctly.

    Presence/absence chemicals (total coliform) are skipped — their VALUE
    is a binary 0/1 indicator rather than a concentration.
    """
    df = df.copy()
    mask = (
        (df["DETECT"] == 0)
        & df["MDL"].notna()
        & ~df["CHEMID_name"].isin(PRESENCE_ABSENCE_CHEMS)
    )
    n_imputed = int(mask.sum())
    df.loc[mask, "VALUE"] = df.loc[mask, "MDL"] / math.sqrt(2)

    # For SYR3 non-detects UNITS is NaN; fill from MDL_UNITS so normalize_units works
    units_filled = mask & df["UNITS"].isna() & df["MDL_UNITS"].notna()
    df.loc[units_filled, "UNITS"] = df.loc[units_filled, "MDL_UNITS"]

    print(
        f"\nRavalli MDL/sqrt(2) imputation: {n_imputed:,} non-detect records imputed "
        f"({int(units_filled.sum()):,} SYR3 records had UNITS filled from MDL_UNITS)"
    )
    return df


def collapse_to_pwsid_year(df: pd.DataFrame) -> pd.DataFrame:
    """
    Collapse sample-level data to PWSID × CHEMID_name × YEAR.
    VALUE           = mean of all samples that year.
    DETECT          = 1 if any sample that year was a detection.
    UNITS           = the common unit for all readings (after mixed-unit filter).
    share_above_mcl = share of readings exceeding the applicable MCL (NaN if no MCL applies).

    Groups where more than one distinct non-null unit appears within a
    PWSID × chemical × year cell are dropped before collapsing, since averaging
    values in incompatible units is undefined. NaN units are treated as absent
    unit information and do not themselves cause a group to be dropped.
    """
    # Count distinct non-null units per group (nunique excludes NaN by default)
    unit_nunique = (
        df.groupby(["PWSID", "CHEMID_name", "YEAR"])["UNITS"]
        .nunique()
        .reset_index(name="_unit_nunique")
    )
    df = df.merge(unit_nunique, on=["PWSID", "CHEMID_name", "YEAR"])

    mixed = df["_unit_nunique"] > 1
    if mixed.any():
        n_groups = df.loc[mixed, ["PWSID", "CHEMID_name", "YEAR"]].drop_duplicates().shape[0]
        n_rows   = int(mixed.sum())
        print(f"\n  [WARN] dropping {n_groups:,} PWSID×chemical×year groups "
              f"({n_rows:,} rows) with mixed units:")
        summary = (
            df.loc[mixed]
            .groupby(["CHEMID_name", "UNITS"])
            .size()
            .reset_index(name="n_rows")
        )
        print(summary.to_string(index=False))

    df = df.loc[~mixed].drop(columns=["_unit_nunique"])

    agg_spec: dict = dict(
        VALUE            = ("VALUE",  "mean"),
        VALUE_max        = ("VALUE",  "max"),
        DETECT           = ("DETECT", "max"),   # 1 if any sample that year was a detection
        detect_share     = ("DETECT", "mean"),  # share of the year's samples that were detections
        UNITS            = ("UNITS",  "first"),   # all non-null units in group are identical after filter
        num_measurements = ("VALUE",  "count"),
    )
    if "above_mcl" in df.columns:
        agg_spec["share_above_mcl"] = ("above_mcl", "mean")

    collapsed = (
        df.groupby(["PWSID", "CHEMID_name", "YEAR"], as_index=False)
        .agg(**agg_spec)
    )

    out_cols = ["PWSID", "CHEMID_name", "DETECT", "detect_share", "VALUE", "VALUE_max", "UNITS", "YEAR", "num_measurements"]
    if "share_above_mcl" in collapsed.columns:
        out_cols.append("share_above_mcl")
    collapsed = collapsed[out_cols].copy()

    print(f"\nCollapsed: {len(collapsed):,} PWSID × chemical × year rows")
    if "share_above_mcl" in collapsed.columns:
        n_mcl = collapsed["share_above_mcl"].notna().sum()
        print(f"  share_above_mcl non-null for {n_mcl:,} rows "
              f"({100 * n_mcl / max(len(collapsed), 1):.1f}%)")
    return collapsed


def merge_to_2sls(df_chem: pd.DataFrame) -> pd.DataFrame:
    """
    Left-join the chemical panel onto the main 2SLS dataset.
    The 2SLS dataset is expanded to one row per PWSID × year × chemical
    so that every combination is present; VALUE/DETECT are NaN where no
    chemical observation exists for that PWSID-year.
    """
    print(f"\nReading 2SLS dataset: {MAIN_DATASET}")
    main_df = pd.read_parquet(MAIN_DATASET, engine="pyarrow")
    print(f"  {len(main_df):,} rows × {main_df.shape[1]} columns | "
          f"years {main_df['year'].min()}–{main_df['year'].max()}")

    main_df["PWSID"] = main_df["PWSID"].astype(str)
    main_df["year"]  = main_df["year"].astype("int64")
    df_chem["PWSID"] = df_chem["PWSID"].astype(str)
    df_chem["YEAR"]  = df_chem["YEAR"].astype("int64")

    unique_chems  = df_chem[["CHEMID_name"]].drop_duplicates()
    main_expanded = main_df.merge(unique_chems, how="cross")
    print(f"\nExpanded 2SLS: {len(main_expanded):,} rows "
          f"({len(main_df):,} PWSID-years × {len(unique_chems):,} chemicals)")

    merged = main_expanded.merge(
        df_chem,
        left_on=["PWSID", "year", "CHEMID_name"],
        right_on=["PWSID", "YEAR", "CHEMID_name"],
        how="left",
    ).drop(columns=["YEAR"], errors="ignore")

    n_miss = merged["VALUE"].isna().sum()
    print(f"\nMerged: {len(merged):,} rows × {merged.shape[1]} columns")
    print(f"  VALUE missing (no 6yr-review obs): {n_miss:,} "
          f"({100 * n_miss / len(merged):.1f}%)")

    right_dup = (main_df.groupby(["PWSID", "year"]).size() > 1).sum()
    if right_dup > 0:
        print(f"  [WARN] {right_dup:,} duplicate (PWSID, year) keys in 2SLS dataset")

    return merged


# ---------------------------------------------------------------------------
# Entry point — edit CHEMICALS and run
# ---------------------------------------------------------------------------

CHEMICALS = [
    # Inorganic Chemicals (IOCs) — 40 CFR 141.62(b)
    "arsenic",
    "nitrate",
    "thallium",
    "barium",
    "cadmium",
    "chromium",
    "mercury",
    "selenium",
    "silver",           # no SYR2/SYR3 data — secondary MCL only (40 CFR 143.3); skipped
    # Synthetic Organic Chemicals (SOCs) — 40 CFR 141.61(c)
    "2,4-D",
    "2,4,5-TP (Silvex)",
    "endrin",
    "lindane",
    "methoxychlor",
    "toxaphene",
    # Volatile Organic Chemicals (VOCs) — 40 CFR 141.61(a)
    "benzene",
    "carbon tetrachloride",
    "1,2-dichloroethane",
    "p-dichlorobenzene",
    "1,1-dichloroethylene",
    "1,1,1-trichloroethane",
    "trichloroethylene",
    "vinyl chloride",
    # Radionuclides
    "alpha particles",
    "beta particles",
    "radium",
    "uranium",
    # Total Coliforms — SYR3 only (2006–2008); 40 CFR 141.63
    "total coliform",
]

if __name__ == "__main__":
    # Step 1: read all SYR2 + SYR3 files (shared across both pipelines)
    master = build_chemical_panel(CHEMICALS)

    # ── Standard pipeline (no MDL imputation) ─────────────────────────────
    print("\n" + "=" * 60)
    print("STANDARD PIPELINE (no MDL imputation)")
    print("=" * 60)

    master_std = normalize_units(master)
    master_std = report_detection_rates(master_std, DETECT_RATE_MIN)
    master_std = assign_mcl_and_above(master_std)
    master_std = drop_gross_outliers(master_std)
    collapsed_std = collapse_to_pwsid_year(master_std)

    if CHEM_OUTPUT.exists():
        print(f"\nWARNING: {CHEM_OUTPUT} already exists — overwriting")
    print(collapsed_std.dtypes)
    collapsed_std.to_parquet(CHEM_OUTPUT, index=False, engine="pyarrow")
    v = pd.read_parquet(CHEM_OUTPUT, engine="pyarrow")
    print(f"Written {len(v):,} rows × {v.shape[1]} columns to {CHEM_OUTPUT}")

    merged_std = merge_to_2sls(collapsed_std)
    if MERGED_OUTPUT.exists():
        print(f"\nWARNING: {MERGED_OUTPUT} already exists — overwriting")
    merged_std["PWSID"] = merged_std["PWSID"].astype(str)
    merged_std["year"]  = merged_std["year"].astype("int64")
    print(merged_std.dtypes)
    merged_std.to_parquet(MERGED_OUTPUT, index=False, engine="pyarrow")
    v2 = pd.read_parquet(MERGED_OUTPUT, engine="pyarrow")
    print(f"Written {len(v2):,} rows × {v2.shape[1]} columns to {MERGED_OUTPUT}")

    # ── Ravalli et al. (2022) pipeline (MDL/sqrt(2) imputation) ───────────
    print("\n" + "=" * 60)
    print("RAVALLI ET AL. (2022) PIPELINE: MDL/sqrt(2) imputation for non-detects")
    print("=" * 60)

    master_rav = impute_nondetects_ravalli(master)
    master_rav = normalize_units(master_rav)
    master_rav = report_detection_rates(master_rav, DETECT_RATE_MIN)
    master_rav = assign_mcl_and_above(master_rav)
    master_rav = drop_gross_outliers(master_rav)
    collapsed_rav = collapse_to_pwsid_year(master_rav)

    if CHEM_OUTPUT_RAVALLI.exists():
        print(f"\nWARNING: {CHEM_OUTPUT_RAVALLI} already exists — overwriting")
    print(collapsed_rav.dtypes)
    collapsed_rav.to_parquet(CHEM_OUTPUT_RAVALLI, index=False, engine="pyarrow")
    v3 = pd.read_parquet(CHEM_OUTPUT_RAVALLI, engine="pyarrow")
    print(f"Written {len(v3):,} rows × {v3.shape[1]} columns to {CHEM_OUTPUT_RAVALLI}")

    merged_rav = merge_to_2sls(collapsed_rav)
    if MERGED_OUTPUT_RAVALLI.exists():
        print(f"\nWARNING: {MERGED_OUTPUT_RAVALLI} already exists — overwriting")
    merged_rav["PWSID"] = merged_rav["PWSID"].astype(str)
    merged_rav["year"]  = merged_rav["year"].astype("int64")
    print(merged_rav.dtypes)
    merged_rav.to_parquet(MERGED_OUTPUT_RAVALLI, index=False, engine="pyarrow")
    v4 = pd.read_parquet(MERGED_OUTPUT_RAVALLI, engine="pyarrow")
    print(f"Written {len(v4):,} rows × {v4.shape[1]} columns to {MERGED_OUTPUT_RAVALLI}")

    print("\nDone.")
