# ============================================================
# Script: download_census_nhgis.py
# Purpose: Download census BLOCK (pop/race/sex), BLOCK-GROUP (income), and
#          COUNTY boundary data for 1990/2000/2010/2020 from IPUMS NHGIS,
#          scoped to CWSs that are ever exactly one HUC12 downstream of a
#          coal mine. Processed one year at a time: submit -> download to a
#          temp dir -> spatially filter against the exposure geography ->
#          write only the filtered/attributed subset to raw_data/census/ ->
#          discard the temp dir before the next year. The full unfiltered
#          state-level extract never lands on disk.
# Inputs : IPUMS NHGIS API key (env IPUMS_API_KEY or .claude/.ipums_api_key)
#          clean_data/cws_data/downstream_mine_exposure_geo.parquet
#          (built by get_downstream_service_areas.py)
# Outputs: raw_data/census/<year>/{block,blockgroup,county}/... + manifest.md
# Author : EK   Date: 2026-06-20
# ------------------------------------------------------------
# Dataset/table/shapefile codes resolved against the live NHGIS metadata API
# on 2026-06-19/20. See .claude/logs/2026-06-19-census-block-download-handoff.md
# and .claude/logs/2026-06-20-census-scoped-to-downstream-cws.md for the
# scope pivot (33-state nationwide -> 18-state downstream-of-mine-only) and
# the metadata API verification (county/block-group shapefile names confirmed
# live; metadata catalog pages are dicts with a "data" list, not bare lists).
# ============================================================

from pathlib import Path
import argparse
import os
import json
import time
import zipfile
import tempfile

import geopandas as gpd
import pandas as pd
import ipumspy

PROJECT_ROOT = Path(__file__).resolve().parents[2]            # z:/ek559/mining_wq
OUT_ROOT = PROJECT_ROOT / "raw_data" / "census"                # hook-exempted dir
EXPOSURE_PARQUET = PROJECT_ROOT / "clean_data" / "cws_data" / "downstream_mine_exposure_geo.parquet"
TARGET_CRS = 5070  # project standard for area/distance, per CLAUDE.md

# Full postal -> FIPS lookup so the 18-state scope can be derived dynamically
# from the exposure crosswalk (not hardcoded) and stays correct if the
# upstream mining/HUC pipeline ever changes which states appear.
STATE_FIPS = {
    "AL": "01", "AK": "02", "AZ": "04", "AR": "05", "CA": "06", "CO": "08",
    "CT": "09", "DE": "10", "DC": "11", "FL": "12", "GA": "13", "HI": "15",
    "ID": "16", "IL": "17", "IN": "18", "IA": "19", "KS": "20", "KY": "21",
    "LA": "22", "ME": "23", "MD": "24", "MA": "25", "MI": "26", "MN": "27",
    "MS": "28", "MO": "29", "MT": "30", "NE": "31", "NV": "32", "NH": "33",
    "NJ": "34", "NM": "35", "NY": "36", "NC": "37", "ND": "38", "OH": "39",
    "OK": "40", "OR": "41", "PA": "42", "RI": "44", "SC": "45", "SD": "46",
    "TN": "47", "TX": "48", "UT": "49", "VT": "50", "VA": "51", "WA": "53",
    "WV": "54", "WI": "55", "WY": "56",
}

# --- Resolved dataset/table specs (verified against NHGIS metadata API) ----
# block-level pop/race/sex (100% / short form)
BLOCK_SPECS = {
    1990: {"dataset": "1990_STF1", "tables": ["NP1", "NP6", "NP13"]},
    # SF1a is "areas larger than block groups" — does NOT include block.
    # SF1b is the block + block-group file.
    2000: {"dataset": "2000_SF1b", "tables": ["NP001A", "NP007A", "NP012B"]},
    2010: {"dataset": "2010_SF1a", "tables": ["P1", "P3", "P12"]},
    2020: {"dataset": "2020_DHCa", "tables": ["P1", "P3", "P12"]},  # has DP noise
}
# block-group income
BG_SPECS = {
    1990: {"dataset": "1990_STF3", "tables": ["NP80A"]},
    # SF3a is "areas larger than block groups" — does NOT include block group.
    2000: {"dataset": "2000_SF3b", "tables": ["NP053A"]},
    2010: {"dataset": "2006_2010_ACS5a", "tables": ["B19013"]},
    2020: {"dataset": "2016_2020_ACS5a", "tables": ["B19013"]},
}
# shapefile base names (TIGER/Line basis matched to each vintage)
BLOCK_SHAPE_BASE = {
    1990: "block_1990_tl2000",
    2000: "block_2000_tl2000",
    2010: "block_2010_tl2010",
    2020: "block_2020_tl2020",
}
BG_SHAPE_BASE = {
    1990: "blck_grp_1990_tl2000",
    2000: "blck_grp_2000_tl2000",
    2010: "blck_grp_2010_tl2010",
    2020: "blck_grp_2020_tl2020",
}
# national county boundary shapefile — confirmed via metadata API: no
# state-clipped county product exists, so this is requested once per year
# (not per-state) at negligible added cost (~3,100 polygons nationally).
COUNTY_SHAPE_NAME = {
    1990: "us_county_1990_tl2000",
    2000: "us_county_2000_tl2000",
    2010: "us_county_2010_tl2010",
    2020: "us_county_2020_tl2020",
}

YEARS = (1990, 2000, 2010, 2020)


def get_api_key() -> str:
    key = os.environ.get("IPUMS_API_KEY")
    if key:
        return key.strip()
    key_file = PROJECT_ROOT / ".claude" / ".ipums_api_key"
    if key_file.exists():
        return key_file.read_text(encoding="utf-8").strip()
    raise SystemExit(
        "No IPUMS API key. Set env IPUMS_API_KEY or create .claude/.ipums_api_key "
        "(gitignored). Generate at https://account.ipums.org/api_keys"
    )


def ensure_dirs():
    for year in YEARS:
        for geog in ("block", "blockgroup", "county"):
            (OUT_ROOT / str(year) / geog).mkdir(parents=True, exist_ok=True)
    (OUT_ROOT / "extract_definitions").mkdir(parents=True, exist_ok=True)
    (OUT_ROOT / "manifest_data").mkdir(parents=True, exist_ok=True)


def load_exposure_crosswalk():
    gdf = gpd.read_parquet(EXPOSURE_PARQUET)
    gdf["PWSID"] = gdf["PWSID"].astype(str)
    return gdf


def derive_states_and_extents(crosswalk: gpd.GeoDataFrame):
    states = sorted(crosswalk.loc[crosswalk["geo_tier"] != "unmatched", "state"].dropna().unique())
    unknown = [s for s in states if s not in STATE_FIPS]
    if unknown:
        raise SystemExit(f"States {unknown} not in STATE_FIPS lookup — add them before proceeding.")
    extent_codes = sorted(f"{STATE_FIPS[s]}0" for s in states)
    return states, extent_codes


def build_extract(year: int, extent_codes: list[str]) -> ipumspy.AggregateDataExtract:
    block_shapefiles = [f"{code}_{BLOCK_SHAPE_BASE[year]}" for code in extent_codes]
    bg_shapefiles = [f"{code}_{BG_SHAPE_BASE[year]}" for code in extent_codes]
    county_shapefile = [COUNTY_SHAPE_NAME[year]]
    return ipumspy.AggregateDataExtract(
        collection="nhgis",
        datasets=[
            ipumspy.NhgisDataset(
                name=BLOCK_SPECS[year]["dataset"],
                data_tables=BLOCK_SPECS[year]["tables"],
                geog_levels=["block"],
            ),
            ipumspy.NhgisDataset(
                name=BG_SPECS[year]["dataset"],
                data_tables=BG_SPECS[year]["tables"],
                geog_levels=["blck_grp"],
            ),
        ],
        shapefiles=block_shapefiles + bg_shapefiles + county_shapefile,
        geographic_extents=extent_codes,
        description=(
            f"Coal mining WQ project — {year} block pop/race/sex + bg income + "
            f"county boundaries, 18 downstream-of-mine states"
        ),
    )


def unzip_flat(zip_path: Path, dest_dir: Path):
    dest_dir.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(zip_path) as z:
        z.extractall(dest_dir)


def unpack_shape_zip(shape_zip: Path, dest_dir: Path):
    """Top-level shape zip extracts into a subdirectory containing one inner
    zip per shapefile (per-state for block/bg, single national one for
    county). Extract each inner zip flatly into dest_dir so files are named
    e.g. 010_block_1990_tl2000.shp regardless of nesting depth."""
    unzip_flat(shape_zip, dest_dir)
    inner_zips = list(dest_dir.rglob("*.zip"))
    print(f"  shape zip inner zip count: {len(inner_zips)}; sample: {[p.name for p in inner_zips[:5]]}")
    for inner_zip in inner_zips:
        with zipfile.ZipFile(inner_zip) as z:
            z.extractall(dest_dir)
    shp_files = sorted(dest_dir.rglob("*.shp"))
    print(f"  after inner unzip, {len(shp_files)} .shp files found; sample: {[p.name for p in shp_files[:5]]}")


def derive_county_fips_from_gisjoin(gisjoin: pd.Series) -> pd.Series:
    """NHGIS county-level GISJOIN = 'G' + 2-digit state FIPS + '0' + 3-digit
    county FIPS. GISJOIN is NHGIS's stable join key across all TIGER vintages
    (unlike raw STATEFP/COUNTYFP fields, which vary by vintage) — this is
    exactly why NHGIS created it. Verified against a real sample below before
    use; if the slice is wrong the printed sample will make it obvious."""
    sample = gisjoin.iloc[0]
    print(f"  GISJOIN sample: {sample!r} (len={len(sample)})")
    return gisjoin.str[1:3] + gisjoin.str[4:7]


def find_county_fips_column(gdf: gpd.GeoDataFrame) -> pd.Series:
    cols_upper = {c.upper(): c for c in gdf.columns}
    if "STATEA" in cols_upper and "COUNTYA" in cols_upper:
        print(f"  county_fips derived from STATEA+COUNTYA columns: {gdf[cols_upper['STATEA']].iloc[0]}/{gdf[cols_upper['COUNTYA']].iloc[0]}")
        return gdf[cols_upper["STATEA"]].astype(str).str.zfill(2) + gdf[cols_upper["COUNTYA"]].astype(str).str.zfill(3)
    if "GISJOIN" in cols_upper:
        return derive_county_fips_from_gisjoin(gdf[cols_upper["GISJOIN"]].astype(str))
    raise SystemExit(
        f"No STATEA/COUNTYA or GISJOIN column found in county shapefile. "
        f"Available columns: {list(gdf.columns)}"
    )


def classify_shapefiles(shape_dir: Path) -> dict:
    """NHGIS delivers shapefiles named like AL_block_1990.shp / AL_blck_grp_1990.shp
    (2-letter postal code, not the FIPS extent code used to *request* them; no
    TIGER-vintage suffix) for per-state block/block-group geographies, and a
    single national file containing 'county' in the name for the county
    geography. Confirmed empirically on the 1990 smoke test — the requested
    extent-code-based names (e.g. 010_block_1990_tl2000) are not the delivered
    filenames. Classify by content rather than guessing exact names so this
    holds across vintages."""
    buckets = {"block": [], "blockgroup": [], "county": []}
    for shp in shape_dir.rglob("*.shp"):
        name = shp.stem.lower()
        if "county" in name:
            buckets["county"].append(shp)
        elif "blck_grp" in name or "blockgroup" in name or "_bg_" in name:
            buckets["blockgroup"].append(shp)
        elif "block" in name:
            buckets["block"].append(shp)
    return buckets


def read_shapefiles(shp_paths: list[Path]) -> gpd.GeoDataFrame:
    """Read and concatenate the per-state shapefiles for one geography (block
    or block group), reprojecting to TARGET_CRS."""
    if not shp_paths:
        raise SystemExit("No shapefiles found for this geography.")
    parts = [gpd.read_file(p) for p in shp_paths]
    combined = gpd.GeoDataFrame(pd.concat(parts, ignore_index=True), crs=parts[0].crs)
    return combined.to_crs(TARGET_CRS)


def read_county_shapefile(shp_paths: list[Path]) -> gpd.GeoDataFrame:
    if len(shp_paths) != 1:
        raise SystemExit(f"Expected exactly 1 county shapefile, found {len(shp_paths)}: {shp_paths}")
    gdf = gpd.read_file(shp_paths[0]).to_crs(TARGET_CRS)
    gdf["county_fips"] = find_county_fips_column(gdf)
    return gdf


def build_blockbg_exposure_gdf(crosswalk: gpd.GeoDataFrame, county_gdf: gpd.GeoDataFrame) -> gpd.GeoDataFrame:
    """239 service_area polygons + the 127 county-tier PWSIDs' single matched
    county polygon for this year's vintage, each kept as its own PWSID-
    attributed row (not collapsed), per the plan."""
    service_area = crosswalk[crosswalk["geo_tier"] == "service_area"][["PWSID", "geo_tier", "geometry"]].copy()

    county_tier = crosswalk.loc[crosswalk["geo_tier"] == "county", ["PWSID", "geo_tier", "county_fips"]].copy()
    county_tier = county_tier.merge(
        county_gdf[["county_fips", "geometry"]], on="county_fips", how="left"
    )
    missing = county_tier[county_tier["geometry"].isna()]
    if len(missing):
        print(f"  WARNING: {len(missing)} county-tier PWSIDs have no matching county polygon this vintage: "
              f"{missing['PWSID'].tolist()}")
    county_tier = gpd.GeoDataFrame(county_tier.dropna(subset=["geometry"]), geometry="geometry", crs=county_gdf.crs)

    exposure = pd.concat(
        [service_area[["PWSID", "geo_tier", "geometry"]], county_tier[["PWSID", "geo_tier", "geometry"]]],
        ignore_index=True,
    )
    return gpd.GeoDataFrame(exposure, geometry="geometry", crs=service_area.crs)


def build_county_crosswalk(crosswalk: gpd.GeoDataFrame, county_gdf: gpd.GeoDataFrame) -> pd.DataFrame:
    """Universal PWSID x county_fips crosswalk for all matched PWSIDs (service
    areas spatially joined against counties; county-tier PWSIDs appended
    directly since their county is already known)."""
    service_area = crosswalk[crosswalk["geo_tier"] == "service_area"][["PWSID", "geometry"]]
    sa_county = gpd.sjoin(
        service_area, county_gdf[["county_fips", "geometry"]], predicate="intersects", how="inner"
    )[["PWSID", "county_fips"]]

    county_tier_direct = crosswalk.loc[crosswalk["geo_tier"] == "county", ["PWSID", "county_fips"]]

    combined = pd.concat([sa_county, county_tier_direct], ignore_index=True).drop_duplicates()
    return combined


def filter_census_gdf(census_gdf: gpd.GeoDataFrame, exposure_gdf: gpd.GeoDataFrame) -> gpd.GeoDataFrame:
    """Keep only census units intersecting the exposure geography, attributing
    the matching PWSID + geo_tier. A unit intersecting multiple PWSIDs'
    geographies appears once per match."""
    joined = gpd.sjoin(census_gdf, exposure_gdf[["PWSID", "geo_tier", "geometry"]], predicate="intersects", how="inner")
    return joined


def filter_csv_by_gisjoin(csv_path: Path, gisjoins: set) -> pd.DataFrame:
    df = pd.read_csv(csv_path, dtype=str, low_memory=False)
    cols_upper = {c.upper(): c for c in df.columns}
    gj_col = cols_upper.get("GISJOIN")
    if gj_col is None:
        raise SystemExit(f"No GISJOIN column found in {csv_path.name}. Columns: {list(df.columns)}")
    return df[df[gj_col].isin(gisjoins)]


def write_manifest(rows, states):
    lines = [
        "# Census NHGIS download manifest",
        "",
        f"Downloaded via IPUMS NHGIS API. Scope: CWSs ever exactly one HUC12 "
        f"downstream of a coal mine (367 PWSIDs; 239 matched to an EPA SABS "
        f"service-area polygon, 127 falling back to county FIPS, 1 unmatched "
        f"and excluded). 18-state union of those geographies: {', '.join(states)}. "
        f"1990/2000/2010/2020.",
        "",
        "## Caveats",
        "- **2020 block pop/race/sex comes from the DHC (`2020_DHCa`) and carries "
        "differential-privacy noise** (small counts at the block level are perturbed).",
        "- **Income is block-group level for all years, never block level** — "
        "the Census Bureau has never tabulated household income below block group.",
        "- 2000 block data is `2000_SF1b` / `2000_SF3b` (the \"blocks & block groups\" "
        "files) — NOT `SF1a`/`SF3a`, which only go down to areas larger than block groups.",
        "- County boundaries are NHGIS's national `us_county_<year>_tl<basis>` product "
        "(no state-clipped county shapefile exists), filtered post-download to the "
        "counties appearing in the PWSID x county_fips crosswalk.",
        "- Each surviving census unit is attributed to the PWSID(s) whose exposure "
        "geography it intersects; a unit intersecting multiple PWSIDs appears once per match.",
        "",
        "## Per-year extract contents and filtered row counts",
        "",
        "| Year | Block dataset | BG dataset | Block rows (raw -> filtered) | "
        "BG rows (raw -> filtered) | County rows (raw -> filtered) |",
        "|---|---|---|---|---|---|",
    ]
    for r in rows:
        lines.append(
            f"| {r['year']} | {r['block_dataset']} | {r['bg_dataset']} | "
            f"{r['block_raw_rows']} -> {r['block_filtered_rows']} | "
            f"{r['blockgroup_raw_rows']} -> {r['blockgroup_filtered_rows']} | "
            f"{r['county_raw_rows']} -> {r['county_filtered_rows']} |"
        )
    lines.append("")
    (OUT_ROOT / "manifest.md").write_text("\n".join(lines), encoding="utf-8")


def process_year(client, year: int, crosswalk: gpd.GeoDataFrame, states: list[str], extent_codes: list[str],
                  reuse_extract_id: int = None) -> dict:
    if reuse_extract_id is not None:
        extract_id = reuse_extract_id
        print(f"[{year}] reusing already-submitted extract #{extract_id}")
    else:
        extract = build_extract(year, extent_codes)
        submitted = client.submit_extract(extract)
        extract_id = submitted._id
        print(f"[{year}] submitted extract #{extract_id}")
        (OUT_ROOT / "extract_definitions" / f"{year}_extract.json").write_text(
            json.dumps(extract.build(), indent=2), encoding="utf-8"
        )
        print(f"[{year}] waiting for extract #{extract_id} ...")
        client.wait_for_extract(extract_id, collection="nhgis", timeout=10800)

    # wait_for_extract only polls the lightweight status endpoint and returns as
    # soon as status flips to "completed" — downloadLinks can lag up to roughly a
    # minute behind that (confirmed empirically on the 1990 smoke test: a KeyError
    # on "tableData" immediately after wait_for_extract returned, still empty after
    # 30s of retries, but fully populated ~1 min later). Retry with a longer budget
    # rather than failing on that race.
    dl = None
    for attempt in range(30):
        info = client.get_extract_info(extract_id, collection="nhgis")
        dl = info.get("downloadLinks", {})
        if "tableData" in dl and "gisData" in dl:
            break
        print(f"  downloadLinks not ready yet (attempt {attempt + 1}/30), retrying in 5s ...")
        time.sleep(5)
    else:
        raise SystemExit(f"[{year}] downloadLinks never populated for extract #{extract_id}: {dl}")
    csv_bytes = dl["tableData"]["bytes"]
    shape_bytes = dl["gisData"]["bytes"]
    print(f"[{year}] completed — data {csv_bytes/1e6:.1f} MB, shapefiles {shape_bytes/1e6:.1f} MB")

    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        client.download_extract(extract_id, collection="nhgis", download_dir=td)
        zips = list(td.glob("*.zip"))
        csv_zip = next(z for z in zips if z.name.endswith("_csv.zip"))
        shape_zip = next(z for z in zips if z.name.endswith("_shape.zip"))

        csv_dir, shape_dir = td / "csv", td / "shape"
        unzip_flat(csv_zip, csv_dir)
        unpack_shape_zip(shape_zip, shape_dir)
        csv_files = sorted(csv_dir.rglob("*.csv"))
        print(f"  csv zip: {len(csv_files)} .csv files found; sample: {[p.name for p in csv_files[:6]]}")

        shp_buckets = classify_shapefiles(shape_dir)
        print(f"  shapefile classification: block={len(shp_buckets['block'])}, "
              f"blockgroup={len(shp_buckets['blockgroup'])}, county={len(shp_buckets['county'])} "
              f"(expect {len(extent_codes)}/{len(extent_codes)}/1)")

        print(f"[{year}] loading county shapefile ...")
        county_gdf = read_county_shapefile(shp_buckets["county"])
        print(f"  county_gdf columns: {list(county_gdf.columns)}")
        print(f"  {len(county_gdf)} counties nationally, CRS={county_gdf.crs}")

        print(f"[{year}] building county crosswalk ...")
        county_crosswalk = build_county_crosswalk(crosswalk, county_gdf)
        n_pwsid_covered = county_crosswalk["PWSID"].nunique()
        print(f"  county crosswalk: {len(county_crosswalk)} rows, {n_pwsid_covered} distinct PWSIDs "
              f"(expect >= 366)")
        kept_fips = set(county_crosswalk["county_fips"])
        county_filtered = county_gdf[county_gdf["county_fips"].isin(kept_fips)].copy()
        county_out_dir = OUT_ROOT / str(year) / "county"
        county_filtered.to_file(county_out_dir / f"county_{year}.shp")
        county_crosswalk.to_csv(county_out_dir / f"pwsid_county_crosswalk_{year}.csv", index=False)
        print(f"  county: {len(county_gdf)} raw -> {len(county_filtered)} filtered")

        print(f"[{year}] building block/block-group exposure geography ...")
        exposure_gdf = build_blockbg_exposure_gdf(crosswalk, county_gdf)
        print(f"  exposure_gdf: {len(exposure_gdf)} rows ({exposure_gdf['geo_tier'].value_counts().to_dict()})")

        results = {"year": year,
                   "block_dataset": BLOCK_SPECS[year]["dataset"], "bg_dataset": BG_SPECS[year]["dataset"],
                   "county_raw_rows": len(county_gdf), "county_filtered_rows": len(county_filtered)}

        for geog, specs in (
            ("block", BLOCK_SPECS[year]),
            ("blockgroup", BG_SPECS[year]),
        ):
            print(f"[{year}] loading {geog} shapefiles ...")
            census_gdf = read_shapefiles(shp_buckets[geog])
            raw_rows = len(census_gdf)
            print(f"  {geog}: {raw_rows} raw rows across {len(extent_codes)} states")

            print(f"[{year}] spatially filtering {geog} against exposure geography ...")
            filtered_gdf = filter_census_gdf(census_gdf, exposure_gdf)
            filtered_rows = len(filtered_gdf)
            n_null_pwsid = filtered_gdf["PWSID"].isna().sum()
            print(f"  {geog}: {raw_rows} raw -> {filtered_rows} filtered, "
                  f"{n_null_pwsid} null PWSID (expect 0)")

            cols_upper = {c.upper(): c for c in filtered_gdf.columns}
            gj_col = cols_upper.get("GISJOIN")
            if gj_col is None:
                raise SystemExit(f"No GISJOIN column in filtered {geog} shapefile. Columns: {list(filtered_gdf.columns)}")
            surviving_gisjoins = set(filtered_gdf[gj_col].astype(str))

            out_dir = OUT_ROOT / str(year) / geog
            filtered_gdf.to_file(out_dir / f"{geog}_{year}.shp")

            csv_candidates = [f for f in csv_dir.rglob("*.csv")
                               if ("bg" in f.name.lower() or "blck_grp" in f.name.lower()) == (geog == "blockgroup")]
            for csv_file in csv_candidates:
                filtered_csv = filter_csv_by_gisjoin(csv_file, surviving_gisjoins)
                filtered_csv.to_csv(out_dir / csv_file.name, index=False)
                print(f"  {csv_file.name}: {len(pd.read_csv(csv_file, dtype=str, low_memory=False))} raw -> "
                      f"{len(filtered_csv)} filtered rows")

            results[f"{geog}_raw_rows"] = raw_rows
            results[f"{geog}_filtered_rows"] = filtered_rows
            results[f"{geog}_tables"] = specs["tables"]

    (OUT_ROOT / "manifest_data" / f"{year}.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
    return results


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--years", type=str, default=None,
                         help="Comma-separated subset of years to run, e.g. 1990 for a smoke test. "
                              "Defaults to all of 1990,2000,2010,2020.")
    parser.add_argument("--reuse-extract", type=int, default=None,
                         help="Skip submitting a new extract and reuse this already-completed NHGIS "
                              "extract number instead. Only valid with a single --years value.")
    args = parser.parse_args()
    years = tuple(int(y) for y in args.years.split(",")) if args.years else YEARS
    if args.reuse_extract is not None and len(years) != 1:
        raise SystemExit("--reuse-extract requires exactly one year via --years")

    api_key = get_api_key()
    ensure_dirs()
    client = ipumspy.IpumsApiClient(api_key)

    crosswalk = load_exposure_crosswalk()
    states, extent_codes = derive_states_and_extents(crosswalk)
    print(f"Exposure scope: {len(states)} states ({', '.join(states)}), "
          f"{(crosswalk['geo_tier'] != 'unmatched').sum()} matched PWSIDs "
          f"({(crosswalk['geo_tier'] == 'service_area').sum()} service_area, "
          f"{(crosswalk['geo_tier'] == 'county').sum()} county)")
    print(f"Running years: {years}")

    for year in years:
        process_year(client, year, crosswalk, states, extent_codes, reuse_extract_id=args.reuse_extract)

    # Manifest is rebuilt from every per-year result on disk, not just the years
    # run this invocation, so running years incrementally (e.g. 1990 alone, then
    # 2000/2010/2020 later) still produces a complete cumulative manifest.
    manifest_rows = []
    for year in YEARS:
        result_file = OUT_ROOT / "manifest_data" / f"{year}.json"
        if result_file.exists():
            manifest_rows.append(json.loads(result_file.read_text(encoding="utf-8")))
    write_manifest(manifest_rows, states)
    print("Done. See raw_data/census/manifest.md")


if __name__ == "__main__":
    main()
