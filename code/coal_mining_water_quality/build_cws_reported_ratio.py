# ============================================================
# Script: build_cws_reported_ratio.py
# Purpose: Backcasting Step 3 of writeup/cws_exposure_backcasting.tex. Builds a
#          PWSID-keyed panel of *reported* population served at the anchor years
#          (SYR2 ~1998-2005, CWSS 2006, SDWIS 2010/2011 freezes), computes the
#          capture ratio r_{i,a} = S_{i,a} / G_{i,a} against the Step-1/2
#          residential backbone, carries r to all years 1990-2024 (flat outside
#          the anchored range, linear interpolation between anchors, county-tier
#          median imputation where a system has no anchor), and forms the
#          reported-served exposure series E^S_t. Wholesale double-counting is
#          removed with the 2010 Buyers/Sellers crosswalk before aggregation.
# Inputs:  raw_data/6_year_review_epa/six-year-review 2/**/*.mdb   (SYR2 anchor)
#          raw_data/sdwa_cws_pop/cwss_2006_database_x/2006_CWSS_DB.mdb
#          raw_data/sdwa_cws_pop/sdwis2010_freeze_x/SDWIS2010_Freeze.accdb
#          raw_data/sdwa_cws_pop/sdwis2011_freeze_x/SDWIS2011_Freeze.accdb
#          raw_data/sdwa_cws_pop/sdwisbuyers_sellers_x/BuyersSellers.accdb
#          clean_data/cws_data/cws_geopop_annual.parquet
#          clean_data/cws_data/downstream_mine_exposure_geo.parquet
#          clean_data/cws_data/prod_vio_sulfur.parquet
# Outputs: clean_data/cws_data/cws_pop_anchors.parquet
#          clean_data/cws_data/cws_capture_ratio_annual.parquet
#          clean_data/cws_data/cws_reported_exposure_annual.parquet
# Author: EK  Date: 2026-07-27
# ------------------------------------------------------------
# Data note (verified on disk, not assumed): the SYR2 occurrence .mdb files carry
# PWSID + POPULATION + sample DATE, but POPULATION is a single inventory value
# stamped on every record of a system -- it does NOT vary across the 1998-2005
# sample years (0 of 49,473 systems show within-PWSID variation). SYR2 therefore
# yields ONE anchor per system, dated to that system's first sample year, not an
# annual 1998-2005 series. The same is true of each later source. The anchor set
# is thus a short irregular panel, which is what the interpolation below assumes.
#
# Anchors deliberately EXCLUDE the modern SDWIS snapshot carried in
# clean_data/cws_6year_review.parquet: its POPULATION_SERVED_COUNT is the 2024Q4
# value broadcast across all years, which is precisely the artifact this exercise
# exists to remove.
# ============================================================

import warnings
from pathlib import Path

import numpy as np
import pandas as pd
import pyodbc

warnings.filterwarnings("ignore", message=".*pandas only supports SQLAlchemy.*")

PROJECT_ROOT = Path(__file__).resolve().parents[2]
RAW = PROJECT_ROOT / "raw_data"
CLEAN_CWS = PROJECT_ROOT / "clean_data" / "cws_data"

SYR2_ROOT = RAW / "6_year_review_epa" / "six-year-review 2"
CWSS2006 = RAW / "sdwa_cws_pop" / "cwss_2006_database_x" / "2006_CWSS_DB.mdb"
FREEZE2010 = RAW / "sdwa_cws_pop" / "sdwis2010_freeze_x" / "SDWIS2010_Freeze.accdb"
FREEZE2011 = RAW / "sdwa_cws_pop" / "sdwis2011_freeze_x" / "SDWIS2011_Freeze.accdb"
BUYSELL = RAW / "sdwa_cws_pop" / "sdwisbuyers_sellers_x" / "BuyersSellers.accdb"

GEOPOP_ANNUAL = CLEAN_CWS / "cws_geopop_annual.parquet"
EXPOSURE_GEO = CLEAN_CWS / "downstream_mine_exposure_geo.parquet"
PROD_VIO_SULFUR = CLEAN_CWS / "prod_vio_sulfur.parquet"

ANCHORS_OUT = CLEAN_CWS / "cws_pop_anchors.parquet"
RATIO_OUT = CLEAN_CWS / "cws_capture_ratio_annual.parquet"
REPORTED_EXPOSURE_OUT = CLEAN_CWS / "cws_reported_exposure_annual.parquet"

ODBC_DRIVER = r"DRIVER={Microsoft Access Driver (*.mdb, *.accdb)};DBQ="
YEAR_MIN, YEAR_MAX = 1990, 2024

# Winsorization bounds for the capture ratio. A ratio far from 1 reflects a
# polygon/reporting mismatch rather than a real service pattern; clip rather than
# drop so the system still contributes.
RATIO_FLOOR, RATIO_CEIL = 0.05, 5.0

# CRITICAL (verified empirically, see the ratio diagnostic in the session log):
# the capture ratio is only interpretable for the service-area tier, where the
# polygon actually delineates the utility's footprint (median r ~1.5, and the
# median system's r varies by only 1.10x across its anchors). For county-tier
# systems the denominator G is the population of an ENTIRE COUNTY, so
# r = S/G ~ 0.001 measures the utility's share of its county, not a capture rate.
# Multiplying that r back by G would merely reproduce the reported number while
# throwing away the county backbone -- circular, and it would silently make E^S_t
# a sum of raw reported values for 127 of 366 systems.
#
# Therefore: for county-tier systems the reported population is used DIRECTLY as
# the anchor level and carried through time by the county's growth factor (the
# same PEP trajectory already embedded in geopop_hat), rather than via a ratio.
# This is the honest use of a county-tier system: level from the report, trend
# from the county.
SERVICE_TIER = "service_area"
COUNTY_TIER = "county"


def connect(path: Path) -> pyodbc.Connection:
    return pyodbc.connect(ODBC_DRIVER + str(path) + ";")


def norm_pwsid(s: pd.Series) -> pd.Series:
    return s.astype(str).str.strip().str.upper()


def load_syr2_anchor(targets: set) -> pd.DataFrame:
    """One anchor per system: POPULATION from SYR2, dated to first sample year.

    POPULATION is constant within PWSID across every chemical file (verified), so
    the value is taken once and the year is the earliest sample date observed.
    """
    mdbs = sorted(SYR2_ROOT.glob("**/*.mdb"))
    print(f"[SYR2] scanning {len(mdbs)} occurrence databases ...")
    frames = []
    for m in mdbs:
        try:
            con = connect(m)
            table = [t.table_name for t in con.cursor().tables(tableType="TABLE")][0]
            d = pd.read_sql(f"SELECT PWSID,PWSTYPE,POPULATION,DATE FROM [{table}]", con)
            con.close()
        except Exception as exc:
            print(f"  [SYR2] WARNING: could not read {m.name}: {type(exc).__name__}")
            continue
        d["PWSID"] = norm_pwsid(d["PWSID"])
        d = d[d["PWSID"].isin(targets) & (d["PWSTYPE"] == "C")]
        if len(d):
            frames.append(d[["PWSID", "POPULATION", "DATE"]])
    if not frames:
        return pd.DataFrame(columns=["PWSID", "year", "pop_reported", "source"])

    syr2 = pd.concat(frames, ignore_index=True)
    syr2["year"] = pd.to_datetime(syr2["DATE"], errors="coerce").dt.year
    syr2 = syr2.dropna(subset=["year"])

    n_multi = (syr2.groupby("PWSID")["POPULATION"].nunique() > 1).sum()
    if n_multi:
        print(f"  [SYR2] NOTE: {n_multi} systems report >1 distinct POPULATION across "
              f"chemical files; taking the median")

    out = syr2.groupby("PWSID").agg(
        year=("year", "min"), pop_reported=("POPULATION", "median")
    ).reset_index()
    out["source"] = "SYR2"
    print(f"  [SYR2] {len(out)} target systems anchored, "
          f"years {int(out['year'].min())}-{int(out['year'].max())}")
    return out


def load_cwss2006(targets: set) -> pd.DataFrame:
    con = connect(CWSS2006)
    d = pd.read_sql("SELECT pwsid,retailpop,totalpop FROM [cwssframe]", con)
    con.close()
    d["PWSID"] = norm_pwsid(d["pwsid"])
    d = d[d["PWSID"].isin(targets)]
    # retailpop is the raw retail population served; popserv is categorical and unusable.
    d["pop_reported"] = pd.to_numeric(d["retailpop"], errors="coerce")
    d = d.dropna(subset=["pop_reported"])
    d = d[d["pop_reported"] > 0]
    out = d.groupby("PWSID", as_index=False)["pop_reported"].median()
    out["year"], out["source"] = 2006, "CWSS2006"
    print(f"  [CWSS2006] {len(out)} target systems anchored")
    return out


def load_freeze(path: Path, table: str, year: int, targets: set) -> pd.DataFrame:
    con = connect(path)
    d = pd.read_sql(f"SELECT PWSID,PWSTypeCode,RetPopSrvd FROM [{table}]", con)
    con.close()
    d["PWSID"] = norm_pwsid(d["PWSID"])
    d = d[(d["PWSTypeCode"] == "C") & d["PWSID"].isin(targets)]
    d["pop_reported"] = pd.to_numeric(d["RetPopSrvd"], errors="coerce")
    d = d.dropna(subset=["pop_reported"])
    d = d[d["pop_reported"] > 0]
    out = d.groupby("PWSID", as_index=False)["pop_reported"].median()
    out["year"], out["source"] = year, f"SDWIS{year}"
    print(f"  [SDWIS{year}] {len(out)} target systems anchored")
    return out


def load_wholesale_sellers(targets: set) -> set:
    """PWSIDs that sell water to another system in the roster.

    A seller's reported population includes people the buying system also
    reports, so summing both double-counts them. The seller is flagged and its
    reported population is not added to E^S_t when its buyer is also downstream.
    """
    con = connect(BUYSELL)
    d = pd.read_sql(
        "SELECT SELLER_PWSID,BUYER_PWSID FROM [tblPWSBuy-Sell]", con
    )
    con.close()
    d["SELLER_PWSID"] = norm_pwsid(d["SELLER_PWSID"])
    d["BUYER_PWSID"] = norm_pwsid(d["BUYER_PWSID"])
    both = d[d["SELLER_PWSID"].isin(targets) & d["BUYER_PWSID"].isin(targets)]
    sellers = set(both["SELLER_PWSID"])
    print(f"  [BuyersSellers] {len(d):,} pairs; {len(both)} pairs where both sides are "
          f"downstream -> {len(sellers)} sellers flagged for dedup")
    return sellers


def build_anchor_panel(targets: set) -> pd.DataFrame:
    parts = [
        load_syr2_anchor(targets),
        load_cwss2006(targets),
        load_freeze(FREEZE2010, "SDWIS2010_Freeze", 2010, targets),
        load_freeze(FREEZE2011, "SDWIS2011_Freeze", 2011, targets),
    ]
    anchors = pd.concat(parts, ignore_index=True)
    anchors["year"] = anchors["year"].astype("int64")
    # One anchor per (system, year): if two sources land on the same year, average.
    anchors = anchors.groupby(["PWSID", "year"], as_index=False).agg(
        pop_reported=("pop_reported", "mean"),
        source=("source", lambda s: "+".join(sorted(set(s)))),
    )
    return anchors


def compute_ratios(anchors: pd.DataFrame, annual: pd.DataFrame) -> pd.DataFrame:
    """r_{i,a} = S_{i,a} / G_{i,a} at each anchor year.

    Computed for every anchor so the diagnostic is visible, but only the
    service-area tier's ratio is used downstream (see the note at the top).
    """
    merged = anchors.merge(
        annual[["PWSID", "year", "geopop_hat", "geo_tier"]], on=["PWSID", "year"], how="left"
    )
    n_nogeo = merged["geopop_hat"].isna().sum()
    if n_nogeo:
        print(f"  WARNING: {n_nogeo} anchors fall outside the {YEAR_MIN}-{YEAR_MAX} "
              f"backbone window and are dropped")
        merged = merged.dropna(subset=["geopop_hat"])
    merged = merged[merged["geopop_hat"] > 0]
    merged["ratio_raw"] = merged["pop_reported"] / merged["geopop_hat"]
    merged["ratio"] = merged["ratio_raw"].clip(RATIO_FLOOR, RATIO_CEIL)

    for tier, g in merged.groupby("geo_tier"):
        n_clip = (g["ratio_raw"] != g["ratio"]).sum()
        print(f"  [{tier}] {len(g)} anchors, {n_clip} winsorized; raw r quantiles "
              f"{g['ratio_raw'].quantile([.25, .5, .75]).round(3).to_dict()}")

    # Ratio-drift diagnostic (writeup 3.8): how much does a system's own r move
    # across its anchors? Reported for the service tier, where r is meaningful.
    sa = merged[merged["geo_tier"] == SERVICE_TIER]
    spread = sa.groupby("PWSID")["ratio"].agg(["count", "min", "max"])
    spread = spread[spread["count"] > 1]
    if len(spread):
        rel = (spread["max"] / spread["min"].replace(0, np.nan)).dropna()
        print(f"  [drift] {len(rel)} service-area systems with >1 anchor; "
              f"max/min r quantiles {rel.quantile([.5, .75, .9]).round(2).to_dict()}")
    return merged


def carry_ratio(ratios: pd.DataFrame, annual: pd.DataFrame) -> pd.DataFrame:
    """Build the annual reported-served estimate, branching by geography tier.

    Service-area tier: interpolate r between anchors, hold flat outside, then
      S_hat = r_hat * geopop_hat.
    County tier: r is not interpretable (see module note), so interpolate the
      reported LEVEL between anchors and carry it outside the anchored range on
      the county's own growth factor, which geopop_hat already tracks:
      S_hat_t = S_a * (geopop_hat_t / geopop_hat_a).
    """
    years = pd.DataFrame({"year": range(YEAR_MIN, YEAR_MAX + 1)})
    systems = annual[["PWSID", "geo_tier"]].drop_duplicates()
    grid = systems.merge(years, how="cross").merge(
        annual[["PWSID", "year", "geopop_hat"]], on=["PWSID", "year"], how="left"
    )
    grid = grid.merge(
        ratios[["PWSID", "year", "ratio", "pop_reported"]], on=["PWSID", "year"], how="left"
    ).sort_values(["PWSID", "year"])

    grid["n_anchors"] = grid.groupby("PWSID")["pop_reported"].transform(lambda s: s.notna().sum())

    # --- Service-area tier: carry the ratio ---
    grid["ratio_hat"] = grid.groupby("PWSID")["ratio"].transform(
        lambda s: s.interpolate(method="linear", limit_area="inside").ffill().bfill()
    )

    # --- County tier: carry the reported level on the county growth factor ---
    # geopop_hat_a at each system's own anchor years, forward/back filled, gives
    # the denominator of the growth factor.
    grid["geo_at_anchor"] = grid["geopop_hat"].where(grid["pop_reported"].notna())
    grid["pop_anchor_ff"] = grid.groupby("PWSID")["pop_reported"].transform(
        lambda s: s.interpolate(method="linear", limit_area="inside").ffill().bfill()
    )
    grid["geo_anchor_ff"] = grid.groupby("PWSID")["geo_at_anchor"].transform(
        lambda s: s.interpolate(method="linear", limit_area="inside").ffill().bfill()
    )
    county_level = grid["pop_anchor_ff"] * (
        grid["geopop_hat"] / grid["geo_anchor_ff"].replace(0, np.nan)
    )

    is_county = grid["geo_tier"] == COUNTY_TIER
    grid["pop_served_hat"] = np.where(
        is_county, county_level, grid["ratio_hat"] * grid["geopop_hat"]
    )

    # --- Systems with no anchor at all: impute from same-tier anchored systems ---
    grid["imputed"] = grid["n_anchors"] == 0
    if grid["imputed"].any():
        # Service tier: median ratio. County tier: median ratio of county-tier
        # systems, which is the utility's typical share of its county.
        tier_med = (
            grid.loc[~grid["imputed"]]
            .assign(implied=lambda d: d["pop_served_hat"] / d["geopop_hat"].replace(0, np.nan))
            .groupby(["geo_tier", "year"])["implied"].median()
            .rename("tier_median").reset_index()
        )
        grid = grid.merge(tier_med, on=["geo_tier", "year"], how="left")
        grid.loc[grid["imputed"], "pop_served_hat"] = (
            grid.loc[grid["imputed"], "tier_median"] * grid.loc[grid["imputed"], "geopop_hat"]
        )

    n_imputed = grid.loc[grid["imputed"], "PWSID"].nunique()
    print(f"  carried to {len(grid):,} system-years; {n_imputed} systems have no anchor "
          f"and use the same-tier median")
    for tier, g in grid.groupby("geo_tier"):
        print(f"  [{tier}] implied S/G quantiles "
              f"{(g['pop_served_hat'] / g['geopop_hat']).quantile([.25, .5, .75]).round(3).to_dict()}")
    return grid[["PWSID", "year", "geo_tier", "ratio", "ratio_hat", "pop_reported",
                 "pop_served_hat", "n_anchors", "imputed"]]


def build_reported_exposure(grid, annual, sellers) -> pd.DataFrame:
    """E^S_t = sum over the downstream roster of r_hat * geopop_hat, wholesale-deduped."""
    df = annual.merge(grid, on=["PWSID", "year", "geo_tier"], how="left")

    pv = pd.read_parquet(
        PROD_VIO_SULFUR, columns=["PWSID", "year", "minehuc_downstream_of_mine"], engine="pyarrow"
    )
    pv["PWSID"] = norm_pwsid(pv["PWSID"])
    roster = pv.loc[pv["minehuc_downstream_of_mine"] == 1, ["PWSID", "year"]].drop_duplicates()

    merged = roster.merge(df, on=["PWSID", "year"], how="inner")
    merged["is_seller"] = merged["PWSID"].isin(sellers)
    # Wholesale dedup: a seller's population is already reported by its downstream
    # buyer, so exclude the seller from the reported-served total.
    kept = merged[~merged["is_seller"]]

    exposure = kept.groupby("year").agg(
        E_S=("pop_served_hat", "sum"),
        E_G=("geopop_hat", "sum"),
        n_systems=("PWSID", "nunique"),
        n_imputed=("imputed", "sum"),
    ).reset_index()
    dropped = merged.groupby("year")["is_seller"].sum().rename("n_wholesale_dropped").reset_index()
    exposure = exposure.merge(dropped, on="year", how="left")
    return exposure, df


def main():
    outputs = [ANCHORS_OUT, RATIO_OUT, REPORTED_EXPOSURE_OUT]
    existing = [p for p in outputs if p.exists()]
    if existing:
        raise SystemExit(
            "The following outputs already exist — confirm with the user before "
            f"overwriting: {[str(p) for p in existing]}"
        )

    annual = pd.read_parquet(GEOPOP_ANNUAL, engine="pyarrow")
    annual["PWSID"] = norm_pwsid(annual["PWSID"])
    targets = set(annual["PWSID"].unique())
    print(f"Target downstream systems with a residential backbone: {len(targets)}")

    print("\n--- Building anchor panel ---")
    anchors = build_anchor_panel(targets)
    print(f"Anchor panel: {len(anchors)} (system, year) anchors covering "
          f"{anchors['PWSID'].nunique()} systems")
    print(anchors.groupby("source")["PWSID"].nunique().to_string())

    print("\n--- Capture ratios ---")
    ratios = compute_ratios(anchors, annual)

    print("\n--- Carrying r to all years ---")
    grid = carry_ratio(ratios, annual)

    print("\n--- Wholesale dedup ---")
    sellers = load_wholesale_sellers(targets)

    print("\n--- Reported-served exposure ---")
    exposure, ratio_panel = build_reported_exposure(grid, annual, sellers)

    anchors_out = anchors.merge(
        ratios[["PWSID", "year", "geopop_hat", "ratio_raw", "ratio"]], on=["PWSID", "year"], how="left"
    )
    # Persist the wholesale-seller flag so downstream table code can reproduce
    # exactly the deduped basis E^S_t is summed over.
    grid["is_seller"] = grid["PWSID"].isin(sellers)
    for df, path, name in (
        (anchors_out, ANCHORS_OUT, "cws_pop_anchors"),
        (grid, RATIO_OUT, "cws_capture_ratio_annual"),
        (exposure, REPORTED_EXPOSURE_OUT, "cws_reported_exposure_annual"),
    ):
        if "PWSID" in df.columns:
            df["PWSID"] = df["PWSID"].astype(str)
        if "year" in df.columns:
            df["year"] = df["year"].astype("int64")
        df.to_parquet(path, index=False, engine="pyarrow")
        reread = pd.read_parquet(path, engine="pyarrow")
        print(f"Wrote {len(reread):,} rows x {reread.shape[1]} cols to {path}")

    print("\n--- E^S_t vs E^G_t ---")
    show = exposure[exposure["year"].between(1990, 2006)]
    print(show.to_string(index=False))


if __name__ == "__main__":
    main()
