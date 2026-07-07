# ============================================================
# Script: build_cws_geopop_backcast.py
# Purpose: Backcasting Steps 1-2 + Q4 of writeup/cws_exposure_backcasting.tex.
#          Step 1: decennial spatial apportionment of residential population
#          (geopop) and county-share weights (theta) per downstream-of-mine
#          PWSID, using the block-level areal weights from
#          build_cws_polygon_weights.py. Step 2: chain geopop forward/backward
#          to an annual (1990-2024) series using each PWSID's county-blended
#          PEP growth rate, re-anchoring at each decennial. Q4: apportion race,
#          age, and block-group median income into the same polygons to give
#          the exposed population's demographic composition per census year.
#          Also aggregates the annual series over the downstream roster D_t to
#          produce the residential exposure series E^G_t (Q1/Q2/Q3).
# Inputs:  clean_data/cws_data/cws_block_weights.parquet
#          clean_data/cws_data/cws_bg_weights.parquet
#          clean_data/cws_data/downstream_mine_exposure_geo.parquet
#          clean_data/cws_data/pep_county_population.parquet
#          clean_data/cws_data/prod_vio_sulfur.parquet (for D_t)
#          raw_data/census/<year>/{block,blockgroup}/*.csv
# Outputs: clean_data/cws_data/cws_geopop_decennial.parquet
#          clean_data/cws_data/cws_county_shares.parquet
#          clean_data/cws_data/cws_geopop_annual.parquet
#          clean_data/cws_data/cws_residential_exposure_annual.parquet
#          clean_data/cws_data/cws_demographics_decennial.parquet
# Author: EK  Date: 2026-07-06
# ------------------------------------------------------------
# See plan Z:\Users\ek559\.claude\plans\cws-geopop-backcast-ej.md. Variable
# codes below were verified live against the IPUMS NHGIS metadata API
# (ipumspy client.get_metadata(NhgisDataTableMetadata(...))) on 2026-07-06 for
# every dataset/table requested in download_census_nhgis.py's BLOCK_SPECS /
# BG_SPECS, not guessed from column position.
# ============================================================

from pathlib import Path

import numpy as np
import pandas as pd

PROJECT_ROOT = Path(__file__).resolve().parents[2]
CENSUS_ROOT = PROJECT_ROOT / "raw_data" / "census"
CLEAN_CWS = PROJECT_ROOT / "clean_data" / "cws_data"

BLOCK_WEIGHTS_PATH = CLEAN_CWS / "cws_block_weights.parquet"
BG_WEIGHTS_PATH = CLEAN_CWS / "cws_bg_weights.parquet"
EXPOSURE_PARQUET = CLEAN_CWS / "downstream_mine_exposure_geo.parquet"
PEP_PARQUET = CLEAN_CWS / "pep_county_population.parquet"
PROD_VIO_SULFUR = CLEAN_CWS / "prod_vio_sulfur.parquet"

GEOPOP_DECENNIAL_OUT = CLEAN_CWS / "cws_geopop_decennial.parquet"
COUNTY_SHARES_OUT = CLEAN_CWS / "cws_county_shares.parquet"
GEOPOP_ANNUAL_OUT = CLEAN_CWS / "cws_geopop_annual.parquet"
RESIDENTIAL_EXPOSURE_OUT = CLEAN_CWS / "cws_residential_exposure_annual.parquet"
DEMOGRAPHICS_OUT = CLEAN_CWS / "cws_demographics_decennial.parquet"

YEARS = (1990, 2000, 2010, 2020)
# (anchor_year, first_year, last_year) — the decade each decennial anchors,
# per writeup eq. 8's re-anchoring convention (2020 anchor carries through 2024).
DECADE_WINDOWS = [(1990, 1990, 1999), (2000, 2000, 2009), (2010, 2010, 2019), (2020, 2020, 2024)]

# --- NHGIS variable codes, verified live via the metadata API (2026-07-06) ---
TOTAL_POP_VAR = {1990: "ET1001", 2000: "FXS001", 2010: "H7V001", 2020: "U7H001"}

RACE_VARS = {
    1990: {"white": "EUY001", "black": "EUY002", "aian": "EUY003", "asian_pi": "EUY004", "other": "EUY005"},
    2000: {"white": "FYE001", "black": "FYE002", "aian": "FYE003", "asian": "FYE004",
           "nhpi": "FYE005", "other": "FYE006", "two_or_more": "FYE007"},
    2010: {"white": "H7X002", "black": "H7X003", "aian": "H7X004", "asian": "H7X005",
           "nhpi": "H7X006", "other": "H7X007", "two_or_more": "H7X008"},
    2020: {"white": "U7J002", "black": "U7J003", "aian": "U7J004", "asian": "U7J005",
           "nhpi": "U7J006", "other": "U7J007", "two_or_more": "U7J008"},
}
# 1990 has no combined "Asian"/"NHPI" split (single "asian_pi" category) and no
# "two or more races" category (not introduced until Census 2000) — a genuine
# definitional break documented in the writeup's threats-to-validity section,
# not a bug here.

# Sex-by-age tables: under-18 and 65-plus variable codes, hand-derived from the
# verified age-bin descriptions returned by the metadata API (bin boundaries
# differ by vintage; see session log for the full bin-by-bin listing).
UNDER18_VARS = {
    1990: [f"ET5{i:03d}" for i in range(1, 13)] + [f"ET5{i:03d}" for i in range(32, 44)],
    2000: [f"FYM{i:03d}" for i in range(1, 5)] + [f"FYM{i:03d}" for i in range(24, 28)],
    2010: [f"H76{i:03d}" for i in range(3, 7)] + [f"H76{i:03d}" for i in range(27, 31)],
    2020: [f"U7S{i:03d}" for i in range(3, 7)] + [f"U7S{i:03d}" for i in range(27, 31)],
}
SENIOR65_VARS = {
    1990: [f"ET5{i:03d}" for i in range(27, 32)] + [f"ET5{i:03d}" for i in range(58, 63)],
    2000: [f"FYM{i:03d}" for i in range(18, 24)] + [f"FYM{i:03d}" for i in range(41, 47)],
    2010: [f"H76{i:03d}" for i in range(20, 26)] + [f"H76{i:03d}" for i in range(44, 50)],
    2020: [f"U7S{i:03d}" for i in range(20, 26)] + [f"U7S{i:03d}" for i in range(44, 50)],
}

# 2010/2020 income comes from ACS tables, whose NHGIS delivered CSV columns
# insert an "E" (estimate) between the table code and variable number (e.g.
# JOI001 -> JOIE001) that the metadata API's returned code doesn't show —
# confirmed against the actual CSV header, not guessed. 1990/2000 are
# decennial-count tables and carry no such suffix.
BG_INCOME_VAR = {1990: "E4U001", 2000: "HF6001", 2010: "JOIE001", 2020: "AMR8E001"}

BLOCK_CSV_GLOB = {
    1990: "nhgis0004_ds120_1990_block.csv", 2000: "nhgis0005_ds147_2000_block.csv",
    2010: "nhgis0006_ds172_2010_block.csv", 2020: "nhgis0007_ds258_2020_block.csv",
}
BG_CSV_GLOB = {
    1990: "nhgis0004_ds123_1990_blck_grp.csv", 2000: "nhgis0005_ds152_2000_blck_grp.csv",
    2010: "nhgis0006_ds176_20105_blck_grp.csv", 2020: "nhgis0007_ds249_20205_blck_grp.csv",
}


def load_block_csv(year: int) -> pd.DataFrame:
    path = CENSUS_ROOT / str(year) / "block" / BLOCK_CSV_GLOB[year]
    needed = ["GISJOIN", TOTAL_POP_VAR[year]] + list(RACE_VARS[year].values()) + \
        UNDER18_VARS[year] + SENIOR65_VARS[year]
    df = pd.read_csv(path, dtype=str, usecols=needed, low_memory=False)
    for col in needed[1:]:
        n_before = df[col].notna().sum()
        df[col] = pd.to_numeric(df[col], errors="coerce")
        n_bad = n_before - df[col].notna().sum()
        if n_bad:
            print(f"  [{year}] WARNING: {n_bad} non-numeric values coerced to NaN in {col}")
    df[needed[1:]] = df[needed[1:]].fillna(0)
    df["under18"] = df[UNDER18_VARS[year]].sum(axis=1)
    df["senior65"] = df[SENIOR65_VARS[year]].sum(axis=1)
    df = df.rename(columns={TOTAL_POP_VAR[year]: "total_pop", **{v: k for k, v in RACE_VARS[year].items()}})
    keep = ["GISJOIN", "total_pop", "under18", "senior65"] + list(RACE_VARS[year].keys())
    return df[keep]


def load_bg_income_csv(year: int) -> pd.DataFrame:
    path = CENSUS_ROOT / str(year) / "blockgroup" / BG_CSV_GLOB[year]
    col = BG_INCOME_VAR[year]
    df = pd.read_csv(path, dtype=str, usecols=["GISJOIN", col], low_memory=False)
    df[col] = pd.to_numeric(df[col], errors="coerce")
    n_invalid = (df[col].isna() | (df[col] <= 0)).sum()
    print(f"  [{year}] BG income: {n_invalid}/{len(df)} block groups have missing/non-positive median income")
    df.loc[df[col] <= 0, col] = np.nan
    return df.rename(columns={col: "median_income"})[["GISJOIN", "median_income"]]


def step1_decennial(block_weights: pd.DataFrame, crosswalk: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    """Returns (geopop_decennial, county_shares, demographics_decennial)."""
    geopop_rows, shares_rows, demo_rows = [], [], []
    bg_weights = pd.read_parquet(BG_WEIGHTS_PATH, engine="pyarrow")

    for year in YEARS:
        print(f"[{year}] Step 1: loading block data and apportioning ...")
        block_data = load_block_csv(year)
        bw = block_weights[block_weights["census_year"] == year]
        merged = bw.merge(block_data, on="GISJOIN", how="left", indicator=True)
        n_unmatched = (merged["_merge"] == "left_only").sum()
        if n_unmatched:
            print(f"  [{year}] WARNING: {n_unmatched} weight rows have no matching block CSV row "
                  f"(treated as 0 population)")
        merged = merged.drop(columns="_merge").fillna(
            {"total_pop": 0, "under18": 0, "senior65": 0, **{k: 0 for k in RACE_VARS[year]}}
        )
        value_cols = ["total_pop", "under18", "senior65"] + list(RACE_VARS[year].keys())
        for col in value_cols:
            merged[f"{col}_contrib"] = merged[col] * merged["w"]

        # geopop per PWSID (Step 1 anchor)
        geopop = merged.groupby("PWSID")["total_pop_contrib"].sum().reset_index()
        geopop["census_year"] = year
        geopop = geopop.rename(columns={"total_pop_contrib": "geopop"})
        geopop_rows.append(geopop)

        # county shares theta_{i,c} at this decennial
        county_sum = merged.groupby(["PWSID", "county_fips"])["total_pop_contrib"].sum().reset_index()
        pwsid_total = county_sum.groupby("PWSID")["total_pop_contrib"].transform("sum")
        county_sum["theta"] = county_sum["total_pop_contrib"] / pwsid_total.replace(0, np.nan)
        county_sum["census_year"] = year
        shares_rows.append(county_sum[["PWSID", "county_fips", "census_year", "theta"]])

        # Q4 demographics: race + age shares from block; income from block group
        demo = merged.groupby("PWSID")[[f"{c}_contrib" for c in value_cols]].sum().reset_index()
        demo["census_year"] = year
        race_cols = list(RACE_VARS[year].keys())
        for c in race_cols:
            demo[f"share_{c}"] = demo[f"{c}_contrib"] / demo["total_pop_contrib"].replace(0, np.nan)
        demo["share_under18"] = demo["under18_contrib"] / demo["total_pop_contrib"].replace(0, np.nan)
        demo["share_65plus"] = demo["senior65_contrib"] / demo["total_pop_contrib"].replace(0, np.nan)
        demo = demo.rename(columns={"total_pop_contrib": "pop_total"})

        print(f"[{year}] Q4: computing population-weighted block-group median income ...")
        bg_income = load_bg_income_csv(year)
        bg_len = bw_gisjoin_len = bg_weights.loc[bg_weights["census_year"] == year, "GISJOIN"].str.len().mode()[0]
        merged["bg_gisjoin"] = merged["GISJOIN"].str[:bg_len]
        pwsid_bg_pop = merged.groupby(["PWSID", "bg_gisjoin"])["total_pop_contrib"].sum().reset_index()
        pwsid_bg_pop = pwsid_bg_pop.merge(
            bg_income, left_on="bg_gisjoin", right_on="GISJOIN", how="left"
        )
        valid = pwsid_bg_pop.dropna(subset=["median_income"])
        income_num = valid.groupby("PWSID").apply(
            lambda g: (g["total_pop_contrib"] * g["median_income"]).sum(), include_groups=False
        )
        income_den = valid.groupby("PWSID")["total_pop_contrib"].sum()
        income_pwavg = (income_num / income_den.replace(0, np.nan)).rename("median_income_pwavg").reset_index()
        demo = demo.merge(income_pwavg, on="PWSID", how="left")

        demo = demo.merge(crosswalk[["PWSID", "geo_tier"]], on="PWSID", how="left")
        keep_cols = ["PWSID", "census_year", "geo_tier", "pop_total"] + \
            [f"share_{c}" for c in race_cols] + ["share_under18", "share_65plus", "median_income_pwavg"]
        demo_rows.append(demo[keep_cols])

    geopop_decennial = pd.concat(geopop_rows, ignore_index=True).merge(
        crosswalk[["PWSID", "geo_tier"]], on="PWSID", how="left"
    )
    county_shares = pd.concat(shares_rows, ignore_index=True)
    demographics = pd.concat(demo_rows, ignore_index=True)
    return geopop_decennial, county_shares, demographics


def step2_annual(geopop_decennial: pd.DataFrame, county_shares: pd.DataFrame) -> pd.DataFrame:
    pep = pd.read_parquet(PEP_PARQUET, engine="pyarrow")
    rows = []
    for anchor_year, start_year, end_year in DECADE_WINDOWS:
        print(f"Step 2: chaining decade window {start_year}-{end_year} (anchor {anchor_year}) ...")
        theta = county_shares[county_shares["census_year"] == anchor_year].copy()
        renorm = theta.groupby("PWSID")["theta"].transform("sum")
        theta["theta"] = theta["theta"] / renorm.replace(0, np.nan)

        years_in_window = pd.DataFrame({"year": range(start_year, end_year + 1)})
        blend = theta.merge(years_in_window, how="cross")
        blend = blend.merge(pep, on=["county_fips", "year"], how="left")
        n_missing_pep = blend["population"].isna().sum()
        if n_missing_pep:
            print(f"  WARNING: {n_missing_pep} (PWSID, county, year) rows have no PEP population "
                  f"— dropped from the blend (theta effectively renormalizes over remaining counties)")
        blend["contrib"] = blend["theta"] * blend["population"]
        p_blend = blend.groupby(["PWSID", "year"])["contrib"].sum().reset_index().rename(columns={"contrib": "p_blend"})

        anchor_geopop = geopop_decennial[geopop_decennial["census_year"] == anchor_year][["PWSID", "geopop", "geo_tier"]]
        p_blend_anchor = p_blend[p_blend["year"] == anchor_year][["PWSID", "p_blend"]].rename(
            columns={"p_blend": "p_blend_anchor"}
        )
        window_df = p_blend.merge(anchor_geopop, on="PWSID", how="inner").merge(
            p_blend_anchor, on="PWSID", how="inner"
        )
        window_df["geopop_hat"] = window_df["geopop"] * window_df["p_blend"] / window_df["p_blend_anchor"].replace(0, np.nan)
        window_df["anchor_year"] = anchor_year
        rows.append(window_df[["PWSID", "year", "geopop_hat", "geo_tier", "anchor_year"]])

    annual = pd.concat(rows, ignore_index=True)
    return annual


def step2b_residential_exposure(annual: pd.DataFrame) -> pd.DataFrame:
    roster = pd.read_parquet(
        PROD_VIO_SULFUR, columns=["PWSID", "year", "minehuc_downstream_of_mine"], engine="pyarrow"
    )
    roster["PWSID"] = roster["PWSID"].astype(str)
    downstream = roster[roster["minehuc_downstream_of_mine"] == 1][["PWSID", "year"]]
    merged = downstream.merge(annual, on=["PWSID", "year"], how="left")
    n_missing = merged["geopop_hat"].isna().sum()
    if n_missing:
        print(f"  WARNING: {n_missing} downstream (PWSID, year) roster rows have no geopop_hat "
              f"(outside 1990-2024 backcast window or the 1 unmatched PWSID) — excluded from E_G")
    merged = merged.dropna(subset=["geopop_hat"])
    exposure = merged.groupby("year").agg(E_G=("geopop_hat", "sum"), n_systems=("PWSID", "nunique")).reset_index()
    return exposure


def main():
    outputs = [GEOPOP_DECENNIAL_OUT, COUNTY_SHARES_OUT, GEOPOP_ANNUAL_OUT,
               RESIDENTIAL_EXPOSURE_OUT, DEMOGRAPHICS_OUT]
    existing = [p for p in outputs if p.exists()]
    if existing:
        raise SystemExit(
            f"The following outputs already exist — confirm with the user before overwriting: "
            f"{[str(p) for p in existing]}"
        )

    block_weights = pd.read_parquet(BLOCK_WEIGHTS_PATH, engine="pyarrow")
    crosswalk = pd.read_parquet(EXPOSURE_PARQUET, engine="pyarrow", columns=["PWSID", "geo_tier"])
    crosswalk["PWSID"] = crosswalk["PWSID"].astype(str)

    geopop_decennial, county_shares, demographics = step1_decennial(block_weights, crosswalk)
    annual = step2_annual(geopop_decennial, county_shares)
    exposure = step2b_residential_exposure(annual)

    for df, path, name in (
        (geopop_decennial, GEOPOP_DECENNIAL_OUT, "geopop_decennial"),
        (county_shares, COUNTY_SHARES_OUT, "county_shares"),
        (annual, GEOPOP_ANNUAL_OUT, "geopop_annual"),
        (exposure, RESIDENTIAL_EXPOSURE_OUT, "residential_exposure_annual"),
        (demographics, DEMOGRAPHICS_OUT, "demographics_decennial"),
    ):
        if "PWSID" in df.columns:
            df["PWSID"] = df["PWSID"].astype(str)
        if "year" in df.columns:
            df["year"] = df["year"].astype("int64")
        if "census_year" in df.columns:
            df["census_year"] = df["census_year"].astype("int64")
        print(f"{name} dtypes:\n{df.dtypes}")
        df.to_parquet(path, index=False, engine="pyarrow")
        reread = pd.read_parquet(path, engine="pyarrow")
        print(f"Wrote {len(reread):,} rows x {reread.shape[1]} cols to {path}")

    print("\n--- Residential exposure series E^G_t (head/tail) ---")
    print(exposure.sort_values("year").head(5))
    print(exposure.sort_values("year").tail(5))


if __name__ == "__main__":
    main()
