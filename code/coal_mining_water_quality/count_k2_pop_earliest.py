# ============================================================
# Script: count_k2_pop_earliest.py
# Purpose: Headline count of people served by the k2 main-sample utilities
#          (A2 intake-purity screened, 1985-2005), measured per utility from
#          the EARLIEST-dated source that reports it, cascading:
#            CWSS 1995 -> SYR2 inventory -> CWSS 2000 -> CWSS 2006
#            -> SDWIS 2010 freeze -> SDWIS 2011 freeze -> SDWIS 2024Q4.
# Inputs:  clean_data/cws_data/step_instruments.parquet
#          clean_data/cws_data/cws_covariates_steps.parquet
#          clean_data/cws_data/step_purity_flags.parquet
#          raw_data/sdwa_cws_pop/cwss_1995_database_x/1995CWSS_DB.accdb
#          raw_data/sdwa_cws_pop/cwss_2000_database_x/2000_CWSS_DB.mdb
#          + the SYR2 / CWSS 2006 / SDWIS 2010-2011 freeze / BuyersSellers
#            databases read through build_cws_reported_ratio.py's loaders
# Outputs: clean_data/cws_data/k2_pop_earliest.parquet
# Author: EK  Date: 2026-09-27
# ------------------------------------------------------------
# Data notes (verified on disk 2026-09-27, not assumed):
# - CWSS 1995 carries the PWSID (Screener C101) but population served only as
#   an 8-level size band (FPOPSERV); there is no numeric population field, so
#   it cannot supply a count. The loader reports its coverage and returns empty.
# - CWSS 2000 has numeric PeopleServiced by customer type, but systems are
#   keyed by an internal CWSID with no PWSID anywhere in the database (the
#   ~10% of CWSIDs that collide with 1995 survey IDs are coincidental: their
#   size bands do not agree). Unlinkable, so it returns empty.
# - The SDWIS July 2005 freeze on disk is a state x size-class pivot table,
#   not system-level, so it is not a source here.
# ============================================================

import sys
import warnings
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_cws_reported_ratio import (  # noqa: E402
    connect, norm_pwsid, load_syr2_anchor, load_cwss2006, load_freeze,
    load_wholesale_sellers, FREEZE2010, FREEZE2011,
)

warnings.filterwarnings("ignore", message=".*pandas only supports SQLAlchemy.*")

PROJECT_ROOT = Path(__file__).resolve().parents[2]
RAW = PROJECT_ROOT / "raw_data"
CLEAN_CWS = PROJECT_ROOT / "clean_data" / "cws_data"

CWSS1995 = RAW / "sdwa_cws_pop" / "cwss_1995_database_x" / "1995CWSS_DB.accdb"
CWSS2000 = RAW / "sdwa_cws_pop" / "cwss_2000_database_x" / "2000_CWSS_DB.mdb"

STEP_INSTRUMENTS = CLEAN_CWS / "step_instruments.parquet"
COVARIATES = CLEAN_CWS / "cws_covariates_steps.parquet"
PURITY = CLEAN_CWS / "step_purity_flags.parquet"
OUT = CLEAN_CWS / "k2_pop_earliest.parquet"

YEAR_MIN, YEAR_MAX = 1985, 2005
N_EXPECTED = 582  # unique utilities in build_k2_panel("main") (k2_common.r)

# Tie-break when two sources carry the same year (earlier survey wins).
SOURCE_PRIORITY = ["CWSS1995", "SYR2", "CWSS2000", "CWSS2006",
                   "SDWIS2010", "SDWIS2011", "SDWIS2024"]
EMPTY = pd.DataFrame(columns=["PWSID", "year", "pop_reported", "source"])


def build_roster() -> tuple[set, pd.DataFrame]:
    """Replicates build_k2_panel("main") (a2_only = TRUE) sample membership."""
    si = pd.read_parquet(STEP_INSTRUMENTS, engine="pyarrow",
                         columns=["PWSID", "year", "arm", "k", "n_mine_hucs_linked"])
    cov = pd.read_parquet(COVARIATES, engine="pyarrow")
    pur = pd.read_parquet(PURITY, engine="pyarrow")

    main = si[(si["arm"] == "main") & (si["k"] == 2) & (si["n_mine_hucs_linked"] >= 1)]
    main = main.merge(cov, on=["PWSID", "year"], how="inner")
    main = main.merge(pur.loc[pur["a2_pure"] == 1, ["PWSID", "arm", "k"]],
                      on=["PWSID", "arm", "k"], how="inner")
    main = main[main["year"].between(YEAR_MIN, YEAR_MAX)]

    targets = set(norm_pwsid(main["PWSID"]))
    print(f"k2 main A2 roster: {len(main):,} utility-years, {len(targets)} utilities")
    assert len(targets) == N_EXPECTED, f"roster has {len(targets)} utilities, expected {N_EXPECTED}"

    cov_t = cov[norm_pwsid(cov["PWSID"]).isin(targets)]
    return targets, cov_t


def load_cwss1995(targets: set) -> pd.DataFrame:
    """CWSS 1995 reports population only as a size band -> no count; log coverage."""
    con = connect(CWSS1995)
    scr = pd.read_sql("SELECT ID, C101 FROM [Screeener Data]", con)
    der = pd.read_sql("SELECT ID, FPOPSERV FROM [Derived Data Table #1]", con)
    con.close()
    scr["PWSID"] = norm_pwsid(scr["C101"])
    hit = scr[scr["PWSID"].isin(targets)].merge(der, on="ID", how="inner")
    print(f"  [CWSS1995] SKIPPED: population is a categorical size band only (FPOPSERV); "
          f"{hit['PWSID'].nunique()} target utilities responded")
    return EMPTY.copy()


def load_cwss2000(targets: set) -> pd.DataFrame:
    """CWSS 2000 has numeric population but no PWSID to link on; log and skip."""
    con = connect(CWSS2000)
    cols = list(pd.read_sql("SELECT TOP 1 * FROM [tblWaterSystem]", con).columns)
    con.close()
    if not any(c.lower() == "pwsid" for c in cols):
        print("  [CWSS2000] SKIPPED: systems keyed by internal CWSID, no PWSID to link on")
        return EMPTY.copy()
    raise RuntimeError("CWSS2000 unexpectedly has a PWSID column -- implement the loader")


def load_sdwis2024(cov_t: pd.DataFrame) -> pd.DataFrame:
    """Current SDWIS (2024Q4) population, constant within PWSID -- last resort."""
    d = cov_t[["PWSID", "POPULATION_SERVED_COUNT"]].copy()
    d["PWSID"] = norm_pwsid(d["PWSID"])
    d["pop_reported"] = pd.to_numeric(d["POPULATION_SERVED_COUNT"], errors="coerce")
    out = d.groupby("PWSID", as_index=False)["pop_reported"].max()
    out = out.dropna(subset=["pop_reported"])
    out["year"], out["source"] = 2024, "SDWIS2024"
    print(f"  [SDWIS2024] {len(out)} target systems anchored")
    return out


def main():
    if OUT.exists():
        raise SystemExit(f"{OUT} already exists -- confirm with the user before overwriting")

    targets, cov_t = build_roster()

    print("\n--- Loading sources ---")
    parts = [
        load_cwss1995(targets),
        load_syr2_anchor(targets),
        load_cwss2000(targets),
        load_cwss2006(targets),
        load_freeze(FREEZE2010, "SDWIS2010_Freeze", 2010, targets),
        load_freeze(FREEZE2011, "SDWIS2011_Freeze", 2011, targets),
        load_sdwis2024(cov_t),
    ]
    allsrc = pd.concat([p for p in parts if len(p)], ignore_index=True)
    allsrc["pop_reported"] = pd.to_numeric(allsrc["pop_reported"], errors="coerce")
    allsrc = allsrc.dropna(subset=["pop_reported"])
    allsrc = allsrc[allsrc["pop_reported"] > 0]
    allsrc["year"] = allsrc["year"].astype("int64")

    # Cascade: earliest year first, source priority breaks ties.
    allsrc["prio"] = allsrc["source"].map({s: i for i, s in enumerate(SOURCE_PRIORITY)})
    earliest = (allsrc.sort_values(["PWSID", "year", "prio"])
                .drop_duplicates("PWSID", keep="first")
                .drop(columns="prio").reset_index(drop=True))

    print("\n--- Wholesale dedup ---")
    sellers = load_wholesale_sellers(targets)
    earliest["is_wholesale_seller"] = earliest["PWSID"].isin(sellers)

    # --- Report ---
    total = earliest["pop_reported"].sum()
    net = earliest.loc[~earliest["is_wholesale_seller"], "pop_reported"].sum()
    missing = sorted(targets - set(earliest["PWSID"]))
    print("\n=== Earliest-dated population served, k2 main sample ===")
    print(f"Utilities with a value: {len(earliest)} of {len(targets)}")
    print(f"Gross total people served:            {total:,.0f}")
    print(f"Wholesale-adjusted (sellers dropped): {net:,.0f}  "
          f"({earliest['is_wholesale_seller'].sum()} sellers whose buyer is also in sample)")

    by_src = earliest.groupby("source").agg(
        n_utilities=("PWSID", "size"), population=("pop_reported", "sum"),
        year_min=("year", "min"), year_max=("year", "max"))
    by_src["share_of_total"] = (by_src["population"] / total).round(3)
    by_src = by_src.reindex([s for s in SOURCE_PRIORITY if s in by_src.index])
    print("\nBy source:")
    print(by_src.to_string(formatters={"population": "{:,.0f}".format}))

    q = earliest["pop_reported"]
    print(f"\nUtility size: median {q.median():,.0f}, mean {q.mean():,.0f}, max {q.max():,.0f}")
    print(f"Utilities with no population in any source: {len(missing)} {missing}")

    # Sanity: same roster valued at 2024 SDWIS.
    p24 = allsrc[allsrc["source"] == "SDWIS2024"]["pop_reported"].sum()
    print(f"\nSanity: 2024 SDWIS total for the same roster: {p24:,.0f} "
          f"(earliest / 2024 = {total / p24:.3f})")

    # Spot-check: the three largest utilities across every source.
    top = earliest.nlargest(3, "pop_reported")["PWSID"]
    print("\nSpot-check, largest 3 utilities across sources:")
    print(allsrc[allsrc["PWSID"].isin(top)].drop(columns="prio")
          .sort_values(["PWSID", "year"]).to_string(index=False))

    # --- Write ---
    earliest["PWSID"] = earliest["PWSID"].astype(str)
    earliest["year"] = earliest["year"].astype("int64")
    earliest["pop_reported"] = earliest["pop_reported"].astype("float64")
    earliest = earliest[["PWSID", "year", "pop_reported", "source", "is_wholesale_seller"]]
    print("\n", earliest.dtypes, sep="")
    earliest.to_parquet(OUT, index=False, engine="pyarrow")
    reread = pd.read_parquet(OUT, engine="pyarrow")
    assert reread["PWSID"].is_unique
    print(f"Written {len(reread):,} rows x {reread.shape[1]} columns to {OUT}")


if __name__ == "__main__":
    main()
