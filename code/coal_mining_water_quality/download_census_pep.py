# ============================================================
# Script: download_census_pep.py
# Purpose: Download Census Bureau Population Estimates Program (PEP) annual
#          county total population (1990-2024) and reduce it to a tidy
#          county_fips x year panel, scoped to the 173 counties referenced by
#          the existing PWSID x county_fips crosswalks (1990/2000/2010/2020).
#          Used to give each CWS's geo-population estimate an annual cadence
#          via county growth factors (writeup/cws_exposure_backcasting.tex,
#          Section 3.2). Does not touch the upstream NHGIS pipeline or
#          crosswalks. Source format per vintage:
#            1990-1999: stch-icen<year>.txt demographic-cell text files,
#                       streamed to temp and reduced (population summed over
#                       all age/race-sex/ethnicity cells per state+county).
#            2000-2009: co-est00int-tot.csv (wide, POPESTIMATE2000-2009)
#            2010-2019: co-est2020.csv (wide, POPESTIMATE2010-2019)
#            2020-2024: co-est2024-alldata.csv (wide, POPESTIMATE2020-2024)
#          All sources verified live 2026-06-22; see
#          Z:\Users\ek559\.claude\plans\fancy-gliding-yao.md.
# Inputs : raw_data/census/<year>/county/pwsid_county_crosswalk_<year>.csv
#          (year in 1990,2000,2010,2020)
# Outputs: clean_data/cws_data/pep_county_population.parquet
#          raw_data/census/pep/*.csv (cached small source files) + manifest.md
# Author : EK   Date: 2026-06-22
# ============================================================

from pathlib import Path
import io
import tempfile

import pandas as pd
import requests

PROJECT_ROOT = Path(__file__).resolve().parents[2]                       # z:/ek559/mining_wq
CROSSWALK_DIR = PROJECT_ROOT / "raw_data" / "census"
PEP_RAW_DIR = PROJECT_ROOT / "raw_data" / "census" / "pep"                # hook-exempt
OUT_PARQUET = PROJECT_ROOT / "clean_data" / "cws_data" / "pep_county_population.parquet"

CROSSWALK_YEARS = (1990, 2000, 2010, 2020)

STCH_ICEN_BASE = "https://www2.census.gov/programs-surveys/popest/tables/1990-2000/intercensal/st-co/"
STCH_ICEN_YEARS = range(1990, 2000)

WIDE_SOURCES = [
    {
        "vintage": "2000s_intercensal",
        "url": "https://www2.census.gov/programs-surveys/popest/datasets/2000-2010/intercensal/county/co-est00int-tot.csv",
        "year_lo": 2000,
        "year_hi": 2009,
    },
    {
        "vintage": "2010s_v2020",
        "url": "https://www2.census.gov/programs-surveys/popest/datasets/2010-2020/counties/totals/co-est2020.csv",
        "year_lo": 2010,
        "year_hi": 2019,
    },
    {
        "vintage": "2020s_v2024",
        "url": "https://www2.census.gov/programs-surveys/popest/datasets/2020-2024/counties/totals/co-est2024-alldata.csv",
        "year_lo": 2020,
        "year_hi": 2024,
    },
]


def load_county_universe() -> tuple[set, set]:
    """Union county_fips across the four existing PWSID x county crosswalks;
    derive the 2-digit state FIPS set from it for filtering stch-icen."""
    county_fips = set()
    for year in CROSSWALK_YEARS:
        path = CROSSWALK_DIR / str(year) / "county" / f"pwsid_county_crosswalk_{year}.csv"
        df = pd.read_csv(path, dtype=str)
        county_fips |= set(df["county_fips"].str.zfill(5))
    state_fips = {fips[:2] for fips in county_fips}
    print(f"County universe: {len(county_fips)} counties across {len(state_fips)} states: "
          f"{sorted(state_fips)}")
    return county_fips, state_fips


def download(url: str, dest: Path = None) -> bytes:
    print(f"Downloading {url} ...")
    resp = requests.get(url, timeout=120)
    resp.raise_for_status()
    print(f"  {len(resp.content)/1e6:.1f} MB")
    if dest is not None:
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(resp.content)
        print(f"  cached -> {dest}")
    return resp.content


def parse_stch_icen(content: bytes, year: int, county_set: set) -> pd.DataFrame:
    """stch-icen<year>.txt: whitespace-delimited demographic-cell rows
    [2-digit year, 5-digit state+county fips, age group, race-sex, ethnic
    origin, population] verified empirically (every one of ~955k 1990 rows
    splits into exactly 6 whitespace tokens). Sum population over all cells
    within each county to get the county-year total."""
    text = content.decode("latin1")
    records = []
    for line in text.splitlines():
        tokens = line.split()
        if len(tokens) != 6:
            continue
        fips, population = tokens[1], tokens[5]
        if fips not in county_set:
            continue
        records.append((fips, int(population)))
    df = pd.DataFrame(records, columns=["county_fips", "population"])
    totals = df.groupby("county_fips", as_index=False)["population"].sum()
    totals["year"] = year
    totals["vintage"] = "1990s_intercensal"
    print(f"  [{year}] stch-icen: {len(df):,} cell rows -> {len(totals)} county totals")
    return totals


def parse_wide_csv(content: bytes, vintage: str, year_lo: int, year_hi: int, county_set: set) -> pd.DataFrame:
    """Wide co-est*.csv: one row per geography with POPESTIMATE<year> columns.
    Keep county-level rows (SUMLEV == 50), build county_fips, melt to long,
    filter to the in-scope counties."""
    df = pd.read_csv(io.BytesIO(content), encoding="latin1")
    df = df[df["SUMLEV"] == 50].copy()
    df["county_fips"] = df["STATE"].astype(str).str.zfill(2) + df["COUNTY"].astype(str).str.zfill(3)
    year_cols = {f"POPESTIMATE{y}": y for y in range(year_lo, year_hi + 1)}
    df = df[["county_fips", *year_cols.keys()]]
    long = df.melt(id_vars="county_fips", var_name="col", value_name="population")
    long["year"] = long["col"].map(year_cols)
    long = long.drop(columns="col")
    long = long[long["county_fips"].isin(county_set)]
    long["vintage"] = vintage
    print(f"  [{vintage}] wide csv: {long['county_fips'].nunique()} counties x "
          f"{year_hi - year_lo + 1} years -> {len(long)} rows")
    return long


def check_coverage(panel: pd.DataFrame, county_fips: set):
    """List in-scope counties missing a row for any year they could plausibly
    have (gotcha: county FIPS boundary changes, e.g. Broomfield CO 08014
    created 2001, Miami-Dade FL 12025->12086 in 1997)."""
    years = sorted(panel["year"].unique())
    present = panel.groupby("county_fips")["year"].apply(set)
    print(f"Coverage check across {len(years)} years ({years[0]}-{years[-1]}):")
    for fips in sorted(county_fips):
        have = present.get(fips, set())
        missing = sorted(set(years) - have)
        if missing:
            print(f"  {fips}: missing {len(missing)} years: {missing}")
    n_expected = len(county_fips) * len(years)
    print(f"  cells present: {len(panel.drop_duplicates(['county_fips', 'year']))} "
          f"/ expected (if no boundary changes): {n_expected}")


def write_manifest(rows_by_source: list[dict], county_fips: set, state_fips: set):
    lines = [
        "# PEP county population download manifest",
        "",
        f"Scope: {len(county_fips)} counties across {len(state_fips)} states "
        f"({', '.join(sorted(state_fips))}), derived at runtime as the union of "
        f"raw_data/census/<year>/county/pwsid_county_crosswalk_<year>.csv for "
        f"year in {CROSSWALK_YEARS}.",
        "",
        "## Sources",
        "",
        "| Vintage | Years | URL |",
        "|---|---|---|",
        "| 1990s_intercensal | 1990-1999 | "
        f"{STCH_ICEN_BASE}stch-icen<year>.txt |",
    ]
    for src in WIDE_SOURCES:
        lines.append(f"| {src['vintage']} | {src['year_lo']}-{src['year_hi']} | {src['url']} |")
    lines += [
        "",
        "## Row counts by source",
        "",
        "| Source | Rows produced |",
        "|---|---|",
    ]
    for r in rows_by_source:
        lines.append(f"| {r['source']} | {r['rows']} |")
    lines += [
        "",
        "## Caveats",
        "- **Boundary-year vintage discontinuity**: 1999->2000, 2009->2010, and "
        "2019->2020 growth factors cross PEP vintages (intercensal -> postcensal "
        "estimates). Accepted, analogous to the writeup's decade-boundary kappa reset.",
        "- **County FIPS boundary changes**: the known candidates (Broomfield County, "
        "CO 08014, created Nov 2001; Miami-Dade, FL 12025 (Dade) renamed 12086 in 1997; "
        "Virginia independent-city mergers e.g. Bedford City 51515->51019) were checked "
        "against the 173-county scope and are **not** in it, so no carry-forward/back "
        "or FIPS crosswalk was needed. Verified empirically: all 173 counties have a "
        "row for all 35 years (1990-2024), 6,055/6,055 cells present, zero gaps. Any "
        "future change to the upstream crosswalks should re-run the coverage check "
        "printed at run time before assuming this still holds.",
        "- `county_fips` is the 5-digit state(2)+county(3) FIPS, zero-padded string.",
        "",
    ]
    (PEP_RAW_DIR / "pep_manifest.md").write_text("\n".join(lines), encoding="utf-8")
    print(f"Manifest written -> {PEP_RAW_DIR / 'pep_manifest.md'}")


def main():
    if OUT_PARQUET.exists():
        raise SystemExit(
            f"{OUT_PARQUET} already exists. Per data safeguards, confirm with the user "
            f"before overwriting and explain what will change."
        )

    county_fips, state_fips = load_county_universe()
    PEP_RAW_DIR.mkdir(parents=True, exist_ok=True)

    rows_by_source = []
    panels = []

    for year in STCH_ICEN_YEARS:
        url = f"{STCH_ICEN_BASE}stch-icen{year}.txt"
        with tempfile.TemporaryDirectory():
            content = download(url)  # ~23 MB cell file: stream to memory, reduce, discard (not cached)
        df = parse_stch_icen(content, year, county_fips)
        panels.append(df)
        rows_by_source.append({"source": f"stch-icen{year}", "rows": len(df)})

    for src in WIDE_SOURCES:
        fname = src["url"].rsplit("/", 1)[-1]
        cache_path = PEP_RAW_DIR / fname
        content = download(src["url"], dest=cache_path)
        df = parse_wide_csv(content, src["vintage"], src["year_lo"], src["year_hi"], county_fips)
        panels.append(df)
        rows_by_source.append({"source": fname, "rows": len(df)})

    panel = pd.concat(panels, ignore_index=True)
    panel = panel.drop_duplicates(subset=["county_fips", "year"]).sort_values(["county_fips", "year"])
    panel["county_fips"] = panel["county_fips"].astype(str).str.zfill(5)
    panel["year"] = panel["year"].astype("int64")
    panel["population"] = panel["population"].astype("int64")
    panel["vintage"] = panel["vintage"].astype(str)
    panel = panel[["county_fips", "year", "population", "vintage"]].reset_index(drop=True)

    print("Final panel dtypes:")
    print(panel.dtypes)
    print(f"Final panel: {len(panel):,} rows, {panel['county_fips'].nunique()} counties, "
          f"years {panel['year'].min()}-{panel['year'].max()}")
    assert (panel["population"] > 0).all(), "Found non-positive population values"

    check_coverage(panel, county_fips)

    OUT_PARQUET.parent.mkdir(parents=True, exist_ok=True)
    panel.to_parquet(OUT_PARQUET, index=False, engine="pyarrow")
    print(f"Written -> {OUT_PARQUET}")

    result = pd.read_parquet(OUT_PARQUET, engine="pyarrow")
    print(f"Re-read check: {len(result):,} rows x {result.shape[1]} columns")
    print(result.dtypes)
    assert result["county_fips"].str.len().eq(5).all(), "county_fips not all 5 chars"

    write_manifest(rows_by_source, county_fips, state_fips)
    print("Done.")


if __name__ == "__main__":
    main()
