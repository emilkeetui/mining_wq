# ============================================================
# Script: get_downstream_service_areas.py
# Purpose: Build a two-tier exposure-geography crosswalk for CWSs that are
#          ever exactly one HUC12 downstream of a coal mine
#          (minehuc_downstream_of_mine==1) — EPA SABS service-area polygon
#          where available, county FIPS fallback otherwise.
# Inputs : clean_data/cws_data/prod_vio_sulfur.parquet
#          raw_data/CWS_Boundaries_Latest/EPA_CWS_V1/EPA_CWS_V1.shp
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_GEOGRAPHIC_AREAS.csv
# Outputs: clean_data/cws_data/downstream_mine_exposure_geo.parquet
# Author : EK   Date: 2026-06-20
# ------------------------------------------------------------
# See plan Z:\Users\ek559\.claude\plans\humble-snuggling-mist.md (Step 1) and
# .claude/logs/2026-06-20-census-scoped-to-downstream-cws.md for the full
# rationale behind the two-tier (service_area / county) design.
# ============================================================

from pathlib import Path

import geopandas as gpd
import pandas as pd

PROJECT_ROOT = Path(__file__).resolve().parents[2]                 # z:/ek559/mining_wq
PROD_VIO_SULFUR = PROJECT_ROOT / "clean_data" / "cws_data" / "prod_vio_sulfur.parquet"
SABS_SHP = PROJECT_ROOT / "raw_data" / "CWS_Boundaries_Latest" / "EPA_CWS_V1" / "EPA_CWS_V1.shp"
GEO_AREAS_CSV = Path("Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_GEOGRAPHIC_AREAS.csv")
OUT_PATH = PROJECT_ROOT / "clean_data" / "cws_data" / "downstream_mine_exposure_geo.parquet"

# Postal -> 2-digit state FIPS, used to build the 5-digit county FIPS for the
# county-fallback tier (PWSID prefix is the 2-letter postal code for these
# CWSs; SDWA_GEOGRAPHIC_AREAS' ANSI_ENTITY_CODE is the 3-digit county suffix).
STATE_FIPS = {
    "AL": "01", "AZ": "04", "CA": "06", "CO": "08", "FL": "12", "GA": "13",
    "ID": "16", "IL": "17", "IN": "18", "KS": "20", "KY": "21", "LA": "22",
    "MD": "24", "MI": "26", "MO": "29", "MS": "28", "NC": "37", "NE": "31",
    "NJ": "34", "NM": "35", "NY": "36", "OH": "39", "OK": "40", "OR": "41",
    "PA": "42", "SC": "45", "TN": "47", "TX": "48", "UT": "49", "VA": "51",
    "WA": "53", "WV": "54", "WY": "56",
}

TARGET_CRS = "EPSG:5070"


def main():
    if OUT_PATH.exists():
        raise SystemExit(
            f"{OUT_PATH} already exists — confirm with the user before overwriting "
            "(see CLAUDE.md data safeguards)."
        )

    df = pd.read_parquet(PROD_VIO_SULFUR, columns=["PWSID", "minehuc_downstream_of_mine", "STATE_CODE"])
    downstream = df.loc[df["minehuc_downstream_of_mine"] == 1, ["PWSID", "STATE_CODE"]].drop_duplicates(
        subset="PWSID"
    )
    downstream_pwsids = downstream["PWSID"].reset_index(drop=True)
    # State is read off the PWSID prefix (the standard SDWIS convention: 2-letter
    # postal code + 7-digit number), matching how the plan's verified tier counts
    # (239/127/1, 48 counties, 18 states) were derived. STATE_CODE (PRIMACY_AGENCY_CODE)
    # is not used as the primary source — it can diverge from the PWSID prefix for a
    # subset of PWSIDs (administrative primacy vs. physical state), which would have
    # pulled in extra states/counties not actually implied by the PWSID itself. It's
    # used only as a fallback for the one PWSID with an all-numeric prefix (080890001).
    prefix = downstream["PWSID"].str[:2]
    is_alpha_prefix = prefix.str.isalpha()
    state_series = prefix.where(is_alpha_prefix, downstream["STATE_CODE"])
    pwsid_to_state = pd.Series(state_series.values, index=downstream["PWSID"].values)
    print(f"Downstream-of-mine PWSIDs (ever): {len(downstream_pwsids)}")

    sabs = gpd.read_file(SABS_SHP)
    sabs = sabs[["PWSID", "State", "geometry"]].copy()
    sabs = sabs.to_crs(TARGET_CRS)

    matched_sabs = sabs[sabs["PWSID"].isin(downstream_pwsids)].drop_duplicates(subset="PWSID")
    service_area = pd.DataFrame({
        "PWSID": matched_sabs["PWSID"].values,
        "geo_tier": "service_area",
        "state": pwsid_to_state.loc[matched_sabs["PWSID"].values].values,
        "county_fips": None,
    })
    service_area_gdf = gpd.GeoDataFrame(
        service_area, geometry=matched_sabs["geometry"].values, crs=TARGET_CRS
    )
    print(f"Matched to SABS service-area polygon: {len(service_area_gdf)}")

    remaining = downstream_pwsids[~downstream_pwsids.isin(service_area_gdf["PWSID"])]

    geo_areas = pd.read_csv(GEO_AREAS_CSV, dtype=str, usecols=["PWSID", "AREA_TYPE_CODE", "ANSI_ENTITY_CODE"])
    county_rows = geo_areas[geo_areas["AREA_TYPE_CODE"] == "CN"][["PWSID", "ANSI_ENTITY_CODE"]].drop_duplicates()

    remaining_df = pd.DataFrame({"PWSID": remaining.values})
    remaining_df["state"] = pwsid_to_state.loc[remaining_df["PWSID"].values].values
    remaining_df["state_fips"] = remaining_df["state"].map(STATE_FIPS)

    county_matched = remaining_df.merge(county_rows, on="PWSID", how="inner")
    county_matched = county_matched.dropna(subset=["state_fips", "ANSI_ENTITY_CODE"])
    county_matched["county_fips"] = county_matched["state_fips"] + county_matched["ANSI_ENTITY_CODE"]
    county_matched = county_matched.drop_duplicates(subset="PWSID")

    county_tier = pd.DataFrame({
        "PWSID": county_matched["PWSID"].values,
        "geo_tier": "county",
        "state": county_matched["state"].values,
        "county_fips": county_matched["county_fips"].values,
    })
    print(f"Matched to county fallback: {len(county_tier)} "
          f"({county_tier['county_fips'].nunique()} distinct counties)")

    unmatched_pwsids = remaining[~remaining.isin(county_tier["PWSID"])]
    unmatched_tier = pd.DataFrame({
        "PWSID": unmatched_pwsids.values,
        "geo_tier": "unmatched",
        "state": pwsid_to_state.loc[unmatched_pwsids.values].values if len(unmatched_pwsids) else [],
        "county_fips": None,
    })
    if len(unmatched_tier):
        print(f"Unmatched (no SABS polygon, no county fallback): {len(unmatched_tier)} "
              f"-> {unmatched_tier['PWSID'].tolist()}")

    non_geo = pd.concat([county_tier, unmatched_tier], ignore_index=True)
    non_geo_gdf = gpd.GeoDataFrame(non_geo, geometry=[None] * len(non_geo), crs=TARGET_CRS)

    crosswalk = pd.concat(
        [service_area_gdf[["PWSID", "geo_tier", "state", "county_fips", "geometry"]], non_geo_gdf],
        ignore_index=True,
    )
    crosswalk = gpd.GeoDataFrame(crosswalk, geometry="geometry", crs=TARGET_CRS)
    crosswalk["PWSID"] = crosswalk["PWSID"].astype(str)

    states = sorted(crosswalk.loc[crosswalk["geo_tier"] != "unmatched", "state"].dropna().unique())
    print(f"Total matched (service_area + county): {crosswalk['geo_tier'].ne('unmatched').sum()}")
    print(f"States in scope ({len(states)}): {', '.join(states)}")

    crosswalk.to_parquet(OUT_PATH, index=False)
    print(f"Wrote {len(crosswalk):,} rows to {OUT_PATH}")

    reread = gpd.read_parquet(OUT_PATH)
    assert reread["PWSID"].dtype == object
    print("Verified: re-read OK, PWSID is string dtype, "
          f"{reread.geometry.notna().sum()} rows have geometry.")


if __name__ == "__main__":
    main()
