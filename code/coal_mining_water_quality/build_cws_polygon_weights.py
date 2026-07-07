# ============================================================
# Script: build_cws_polygon_weights.py
# Purpose: Compute areal-interpolation weights w_{b,i} = area(block/BG b in
#          PWSID i's exposure geography) / area(b), for every downstream-of-
#          mine PWSID at each decennial Census vintage (1990/2000/2010/2020).
#          These weights are the reusable "backbone" for both the residential
#          population apportionment (Step 1) and the EJ demographic
#          apportionment (Q4) in writeup/cws_exposure_backcasting.tex.
# Inputs:  clean_data/cws_data/downstream_mine_exposure_geo.parquet
#          raw_data/census/<year>/{block,blockgroup,county}/*.shp
# Outputs: clean_data/cws_data/cws_block_weights.parquet
#          clean_data/cws_data/cws_bg_weights.parquet
# Author: EK  Date: 2026-07-06
# ------------------------------------------------------------
# See plan Z:\Users\ek559\.claude\plans\cws-geopop-backcast-ej.md.
# County-fips derivation per vintage mirrors download_census_nhgis.py's
# find_county_fips_column()/derive_county_fips_from_gisjoin() pattern, but the
# filtered shapefiles here already carry the raw STATE/COUNTY columns
# per-vintage (confirmed empirically), so no GISJOIN fallback is needed.
# ============================================================

from pathlib import Path

import geopandas as gpd
import pandas as pd

PROJECT_ROOT = Path(__file__).resolve().parents[2]
CENSUS_ROOT = PROJECT_ROOT / "raw_data" / "census"
EXPOSURE_PARQUET = PROJECT_ROOT / "clean_data" / "cws_data" / "downstream_mine_exposure_geo.parquet"
BLOCK_WEIGHTS_OUT = PROJECT_ROOT / "clean_data" / "cws_data" / "cws_block_weights.parquet"
BG_WEIGHTS_OUT = PROJECT_ROOT / "clean_data" / "cws_data" / "cws_bg_weights.parquet"

TARGET_CRS = "EPSG:5070"
YEARS = (1990, 2000, 2010, 2020)

# County-FIPS column candidates per vintage. Column names are NOT consistent
# between the block and block-group shapefiles of the same vintage (confirmed
# empirically: 2020 block has STATEFP20/COUNTYFP20, but 2020 block group has
# STATEFP/COUNTYFP with no suffix) so this tries each candidate combined name,
# then each candidate state+county pair, and reports which one matched rather
# than assuming a single fixed name per year.
COMBINED_CANDIDATES = ["FIPSSTCO"]
STATE_COUNTY_CANDIDATES = [
    ("STATEFP10", "COUNTYFP10"), ("STATEFP20", "COUNTYFP20"), ("STATEFP", "COUNTYFP"),
]


def derive_county_fips(gdf: gpd.GeoDataFrame, year: int) -> pd.Series:
    for combined_col in COMBINED_CANDIDATES:
        if combined_col in gdf.columns:
            print(f"  [{year}] county_fips derived from combined column {combined_col!r}")
            return gdf[combined_col].astype(str).str.zfill(5)
    for state_col, county_col in STATE_COUNTY_CANDIDATES:
        if state_col in gdf.columns and county_col in gdf.columns:
            print(f"  [{year}] county_fips derived from {state_col!r} + {county_col!r}")
            return gdf[state_col].astype(str).str.zfill(2) + gdf[county_col].astype(str).str.zfill(3)
    raise SystemExit(
        f"[{year}] No recognized county-FIPS column pair found. Available columns: {list(gdf.columns)}"
    )


def load_crosswalk() -> gpd.GeoDataFrame:
    gdf = gpd.read_parquet(EXPOSURE_PARQUET)
    gdf["PWSID"] = gdf["PWSID"].astype(str)
    gdf = gdf[gdf["geo_tier"] != "unmatched"].copy()
    assert gdf.crs is not None and str(gdf.crs).endswith("5070") or gdf.crs.to_epsg() == 5070, \
        f"Exposure crosswalk CRS unexpected: {gdf.crs}"
    return gdf


def build_year_exposure_polygons(crosswalk: gpd.GeoDataFrame, year: int) -> gpd.GeoDataFrame:
    """Rebuild the per-year exposure geometry: 239 service-area polygons
    (geometry fixed, reused across all 4 vintages) + 127 county-tier PWSIDs'
    county polygon *for this specific vintage* (county boundaries shift
    slightly across decades). Mirrors download_census_nhgis.py's
    build_blockbg_exposure_gdf, but reconstructed here since the filtered
    census outputs on disk don't retain the exposure polygon's own geometry."""
    county_shp = CENSUS_ROOT / str(year) / "county" / f"county_{year}.shp"
    county_gdf = gpd.read_file(county_shp).to_crs(TARGET_CRS)
    assert "county_fip" in county_gdf.columns, f"county_fip column missing in {county_shp}"
    county_gdf = county_gdf.rename(columns={"county_fip": "county_fips"})

    service_area = crosswalk.loc[crosswalk["geo_tier"] == "service_area", ["PWSID", "geo_tier", "geometry"]].copy()

    county_tier = crosswalk.loc[crosswalk["geo_tier"] == "county", ["PWSID", "geo_tier", "county_fips"]].copy()
    county_tier = county_tier.merge(county_gdf[["county_fips", "geometry"]], on="county_fips", how="left")
    missing = county_tier[county_tier["geometry"].isna()]
    if len(missing):
        print(f"  [{year}] WARNING: {len(missing)} county-tier PWSIDs have no matching "
              f"county polygon this vintage: {missing['PWSID'].tolist()}")
    county_tier = county_tier.dropna(subset=["geometry"])

    exposure = pd.concat(
        [service_area[["PWSID", "geo_tier", "geometry"]], county_tier[["PWSID", "geo_tier", "geometry"]]],
        ignore_index=True,
    )
    return gpd.GeoDataFrame(exposure, geometry="geometry", crs=TARGET_CRS)


def compute_weights_for_geography(shp_path: Path, year: int, exposure_gdf: gpd.GeoDataFrame,
                                   unit_id_col: str = "GISJOIN") -> pd.DataFrame:
    raw = gpd.read_file(shp_path).to_crs(TARGET_CRS)
    unique_units = raw.drop_duplicates(subset=unit_id_col).copy()
    unique_units["county_fips"] = derive_county_fips(unique_units, year)
    unique_units["area_full"] = unique_units.geometry.area
    n_units = len(unique_units)
    print(f"  [{year}] {shp_path.name}: {len(raw)} raw rows (post coarse filter) -> "
          f"{n_units} unique units to overlay")

    pieces = gpd.overlay(
        unique_units[[unit_id_col, "county_fips", "geometry"]],
        exposure_gdf[["PWSID", "geo_tier", "geometry"]],
        how="intersection",
    )
    pieces["area_piece"] = pieces.geometry.area
    pieces = pieces.merge(
        unique_units[[unit_id_col, "area_full"]], on=unit_id_col, how="left"
    )
    pieces["w"] = pieces["area_piece"] / pieces["area_full"]
    # Guard against sliver overlaps producing w fractionally > 1 from floating-point
    # noise at shared boundaries; clip rather than silently keep an invalid weight.
    n_over = (pieces["w"] > 1.0 + 1e-6).sum()
    if n_over:
        print(f"  [{year}] WARNING: {n_over} weights > 1 before clipping (max {pieces['w'].max():.6f})")
    pieces["w"] = pieces["w"].clip(upper=1.0)

    out = pieces[[unit_id_col, "PWSID", "county_fips", "geo_tier", "w"]].rename(
        columns={unit_id_col: "GISJOIN"}
    )
    out.insert(2, "census_year", year)
    return out


def main():
    for out_path in (BLOCK_WEIGHTS_OUT, BG_WEIGHTS_OUT):
        if out_path.exists():
            raise SystemExit(
                f"{out_path} already exists — confirm with the user before overwriting "
                "(see CLAUDE.md data safeguards)."
            )

    crosswalk = load_crosswalk()
    print(f"Crosswalk: {len(crosswalk)} PWSIDs "
          f"({(crosswalk['geo_tier'] == 'service_area').sum()} service_area, "
          f"{(crosswalk['geo_tier'] == 'county').sum()} county)")

    block_frames, bg_frames = [], []
    for year in YEARS:
        print(f"[{year}] rebuilding exposure polygons ...")
        exposure_gdf = build_year_exposure_polygons(crosswalk, year)
        print(f"  [{year}] exposure_gdf: {len(exposure_gdf)} rows "
              f"({exposure_gdf['geo_tier'].value_counts().to_dict()})")

        block_shp = CENSUS_ROOT / str(year) / "block" / f"block_{year}.shp"
        bg_shp = CENSUS_ROOT / str(year) / "blockgroup" / f"blockgroup_{year}.shp"

        block_frames.append(compute_weights_for_geography(block_shp, year, exposure_gdf))
        bg_frames.append(compute_weights_for_geography(bg_shp, year, exposure_gdf))

    block_weights = pd.concat(block_frames, ignore_index=True)
    bg_weights = pd.concat(bg_frames, ignore_index=True)

    for name, df, out_path in (("block", block_weights, BLOCK_WEIGHTS_OUT), ("blockgroup", bg_weights, BG_WEIGHTS_OUT)):
        df["PWSID"] = df["PWSID"].astype(str)
        df["census_year"] = df["census_year"].astype("int64")
        df["county_fips"] = df["county_fips"].astype(str)
        df["geo_tier"] = df["geo_tier"].astype(str)
        df["w"] = df["w"].astype("float64")
        print(f"{name} weights dtypes:\n{df.dtypes}")
        df.to_parquet(out_path, index=False, engine="pyarrow")
        reread = pd.read_parquet(out_path, engine="pyarrow")
        print(f"Wrote {len(reread):,} rows to {out_path}")
        assert reread["PWSID"].dtype == object
        n_null_w = reread["w"].isna().sum()
        n_zero_w = (reread["w"] == 0).sum()
        print(f"  null w: {n_null_w} (expect 0); zero w: {n_zero_w}; "
              f"w range [{reread['w'].min():.6f}, {reread['w'].max():.6f}]")
        by_year = reread.groupby("census_year")["PWSID"].nunique()
        print(f"  distinct PWSIDs covered per year:\n{by_year}")


if __name__ == "__main__":
    main()
