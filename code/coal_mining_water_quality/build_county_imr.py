# ============================================================
# Script: build_county_imr.py
# Purpose: Build county x year infant mortality rate from
#          NCHS Linked Birth/Infant Death cohort files and
#          merge to county-level coal mining data.
# Inputs:  raw_data/county_infant_data/linkco{year}us_den.csv.zip
#          raw_data/county_infant_data/linkco{year}us_num.csv.zip
#          clean_data/coal_county_prod.csv
#          clean_data/county_mining_downstream.parquet
# Outputs: clean_data/county_imr.parquet
#          clean_data/county_imr_mining.parquet
# Author: EK  Date: 2026-04-07
# ============================================================

import zipfile
import pandas as pd
import numpy as np
from pathlib import Path

DATA_DIR  = Path("Z:/ek559/mining_wq/raw_data/county_infant_data")
CLEAN_DIR = Path("Z:/ek559/mining_wq/clean_data")

# ── State abbreviation → 2-digit numeric FIPS (for 2003-2004 files) ──────────
STATE_ABBREV_TO_FIPS = {
    "AL": "01", "AK": "02", "AZ": "04", "AR": "05", "CA": "06",
    "CO": "08", "CT": "09", "DE": "10", "DC": "11", "FL": "12",
    "GA": "13", "HI": "15", "ID": "16", "IL": "17", "IN": "18",
    "IA": "19", "KS": "20", "KY": "21", "LA": "22", "ME": "23",
    "MD": "24", "MA": "25", "MI": "26", "MN": "27", "MS": "28",
    "MO": "29", "MT": "30", "NE": "31", "NV": "32", "NH": "33",
    "NJ": "34", "NM": "35", "NY": "36", "NC": "37", "ND": "38",
    "OH": "39", "OK": "40", "OR": "41", "PA": "42", "RI": "44",
    "SC": "45", "SD": "46", "TN": "47", "TX": "48", "UT": "49",
    "VT": "50", "VA": "51", "WA": "53", "WV": "54", "WI": "55",
    "WY": "56",
}

# ── Year-specific county field configuration ──────────────────────────────────
# Returns (county_col, year_col, state_col) for each year cohort.
# county_col = None means county data is fully suppressed (skip year).
def get_year_config(year):
    if year <= 1988:
        # cntyresb: string "01049" (1983) or numeric 1049 (1984-1988)
        # datayear field holds the birth year
        return dict(county_col="cntyresb", year_col="datayear", state_col=None, fmt="5digit_int")
    elif year <= 2002:
        # cntyrfpb: numeric 5-digit (e.g., 1073 = state 01, county 073)
        # biryr field holds the birth year
        return dict(county_col="cntyrfpb", year_col="biryr", state_col=None, fmt="5digit_int")
    elif year <= 2004:
        # mrstatefips (2-letter abbrev) + mrcntyfips (3-digit county int)
        # dob_yy holds the birth year
        return dict(county_col="mrcntyfips", year_col="dob_yy", state_col="mrstatefips", fmt="state_county_split")
    else:
        # 2005+: county fully suppressed
        return dict(county_col=None, year_col=None, state_col=None, fmt=None)


def parse_fips5(series, fmt, state_series=None):
    """Convert raw county identifier to 5-digit FIPS string. Returns Series."""
    if fmt == "5digit_int":
        # Could be string "01049" or numeric 1049; normalize to 5-char string
        s = series.astype(str).str.strip().str.replace(r"\.0$", "", regex=True)
        s = s.str.zfill(5)
        return s
    elif fmt == "state_county_split":
        state_fips = state_series.map(STATE_ABBREV_TO_FIPS)
        cnty = series.astype(str).str.strip().str.replace(r"\.0$", "", regex=True)
        cnty = cnty.str.zfill(3)
        return state_fips.fillna("??") + cnty
    else:
        raise ValueError(f"Unknown fmt: {fmt}")


def is_suppressed(fips5):
    """True for observations where county is coded as suppressed (ends in 999)."""
    return fips5.str[-3:] == "999"


def is_invalid(fips5):
    """True for observations where fips5 cannot be determined."""
    return fips5.str.startswith("??") | (fips5 == "nan00") | (fips5 == "nan999")


# ── Count births by county (denominator) ─────────────────────────────────────
def count_births(year, config, chunksize=200_000):
    """Return DataFrame with columns [fips5, year, births] for one year."""
    fname = DATA_DIR / f"linkco{year}us_den.csv.zip"
    if not fname.exists():
        print(f"  {year}: denominator file not found, skipping")
        return None

    county_col  = config["county_col"]
    year_col    = config["year_col"]
    state_col   = config["state_col"]
    fmt         = config["fmt"]

    # Columns to read: only what we need
    use_cols = [c for c in [county_col, year_col, state_col] if c is not None]

    z = zipfile.ZipFile(fname)
    inner = z.open(z.namelist()[0])

    chunks = []
    for chunk in pd.read_csv(inner, usecols=use_cols, chunksize=chunksize,
                              encoding="latin-1", low_memory=False):
        fips5 = parse_fips5(chunk[county_col], fmt,
                            chunk[state_col] if state_col else None)
        mask = ~is_suppressed(fips5) & ~is_invalid(fips5)
        fips5 = fips5[mask]
        agg = fips5.value_counts().rename("births").reset_index()
        agg.columns = ["fips5", "births"]
        chunks.append(agg)

    if not chunks:
        return None

    df = pd.concat(chunks).groupby("fips5", as_index=False)["births"].sum()
    df["year"] = year
    return df


# ── Count deaths by county (numerator) ───────────────────────────────────────
def count_deaths(year, config):
    """Return DataFrame with columns [fips5, year, deaths] for one year."""
    fname = DATA_DIR / f"linkco{year}us_num.csv.zip"
    if not fname.exists():
        print(f"  {year}: numerator file not found, skipping")
        return None

    county_col  = config["county_col"]
    year_col    = config["year_col"]
    state_col   = config["state_col"]
    fmt         = config["fmt"]

    use_cols = [c for c in [county_col, year_col, state_col] if c is not None]

    z = zipfile.ZipFile(fname)
    df = pd.read_csv(z.open(z.namelist()[0]), usecols=use_cols,
                     encoding="latin-1", low_memory=False)

    fips5 = parse_fips5(df[county_col], fmt,
                        df[state_col] if state_col else None)
    mask = ~is_suppressed(fips5) & ~is_invalid(fips5)
    fips5 = fips5[mask]

    agg = fips5.value_counts().rename("deaths").reset_index()
    agg.columns = ["fips5", "deaths"]
    agg["year"] = year
    return agg


# ── Main: loop over all available years ──────────────────────────────────────
YEARS = list(range(1985, 1992)) + list(range(1995, 2006))

births_all = []
deaths_all = []

for year in YEARS:
    cfg = get_year_config(year)
    if cfg["county_col"] is None:
        print(f"{year}: county fully suppressed — skipping")
        continue
    print(f"{year}: counting births...", flush=True)
    b = count_births(year, cfg)
    if b is not None:
        births_all.append(b)
        print(f"  births: {b['births'].sum():,.0f} in {len(b)} counties")
    print(f"{year}: counting deaths...", flush=True)
    d = count_deaths(year, cfg)
    if d is not None:
        deaths_all.append(d)
        print(f"  deaths: {d['deaths'].sum():,.0f} in {len(d)} counties")

births = pd.concat(births_all, ignore_index=True)
deaths = pd.concat(deaths_all, ignore_index=True)

# ── Merge births and deaths, compute IMR ─────────────────────────────────────
panel = births.merge(deaths, on=["fips5", "year"], how="left")
panel["deaths"] = panel["deaths"].fillna(0).astype(int)
panel["imr"] = np.where(panel["births"] > 0, panel["deaths"] / panel["births"], np.nan)
panel["births"] = panel["births"].astype(int)
panel["year"]   = panel["year"].astype(int)

print(f"\nIMR panel: {len(panel):,} county-years, "
      f"{panel['year'].nunique()} years, {panel['fips5'].nunique()} counties")
print(f"  Total births: {panel['births'].sum():,.0f}")
print(f"  Total deaths: {panel['deaths'].sum():,.0f}")
print(f"  IMR range: {panel['imr'].min():.4f} – {panel['imr'].max():.4f}")

out1 = CLEAN_DIR / "county_imr.parquet"
panel.to_parquet(out1, index=False)
print(f"Saved: {out1}")

# ── Build mining/downstream county panel ──────────────────────────────────────
# Base: all counties that are mining or downstream of mining
downstream = pd.read_parquet(CLEAN_DIR / "county_mining_downstream.parquet")
if "geometry" in downstream.columns:
    downstream = downstream.drop(columns=["geometry"])

mining_counties = downstream[
    downstream["is_mining_county"] | downstream["is_downstream_neighbor"]
][["fips5", "state", "county_name", "frac_area_mining", "frac_area_downstream",
   "is_mining_county", "is_downstream_neighbor", "is_strictly_downstream"]].copy()

print(f"\nMining/downstream counties: {len(mining_counties)}")

# Cross with years to form county × year panel
years_df = pd.DataFrame({"year": YEARS})
base_panel = mining_counties.merge(years_df, how="cross")

# ── Merge coal production ─────────────────────────────────────────────────────
coal_prod = pd.read_csv(CLEAN_DIR / "coal_county_prod.csv")
coal_prod["fips5"] = (
    coal_prod["bom_state_cd"].astype(int).apply(lambda x: f"{x:02d}") +
    coal_prod["fips_cnty_cd"].astype(int).apply(lambda x: f"{x:03d}")
)
coal_prod["year"] = coal_prod["year"].astype(int)
coal_prod = coal_prod[["fips5", "year", "production_short_tons_coal", "num_coal_mines"]]

base_panel = base_panel.merge(coal_prod, on=["fips5", "year"], how="left")

# ── Merge county sulfur ───────────────────────────────────────────────────────
county_sulfur = pd.read_parquet(CLEAN_DIR / "county_sulfur.parquet",
                                columns=["fips5", "sulfur_county_pct", "n_boreholes"])
base_panel = base_panel.merge(county_sulfur, on="fips5", how="left")

# ── Merge IMR (large counties only — small counties stay NaN) ─────────────────
base_panel = base_panel.merge(panel[["fips5", "year", "births", "deaths", "imr"]],
                               on=["fips5", "year"], how="left")

n_with_imr    = base_panel["imr"].notna().sum()
n_suppressed  = base_panel["imr"].isna().sum()
print(f"  County-years with IMR data:    {n_with_imr:,}")
print(f"  County-years with IMR missing: {n_suppressed:,} (suppressed small counties)")

out2 = CLEAN_DIR / "county_imr_mining.parquet"
base_panel.to_parquet(out2, index=False)
print(f"Saved: {out2}")
print(base_panel[["fips5","county_name","state","year","births","deaths","imr",
                   "is_mining_county","is_downstream_neighbor"]].head(10).to_string())
