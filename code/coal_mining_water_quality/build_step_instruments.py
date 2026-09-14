# ============================================================
# Script: build_step_instruments.py
# Purpose: PWSID x year x arm x k instrument/exposure table for the
#          instrument-imputation x step-depth grid. Builds sulfur_meancov
#          (mean over covered linked HUCs only) and sulfur_mean0 (mean over
#          all linked HUCs, uncovered imputed to 0) at every flow-step depth
#          k=1..8, for both the main (treated) and placebo (falsification)
#          arms. Per project decision (2026-09-13): a linked HUC's sulfur
#          reading counts even when that HUC carries zero coal mines — sulfur
#          is a geological trait of the watershed, not solely an
#          attribute of the mine itself. This matches how the existing
#          `sulfur_upstream_sum` in the production pipeline is built (mean
#          over all upstream tributary HUCs with a nonzero reading, not
#          restricted to HUCs classified as a mine), and required widening
#          the borehole-to-HUC spatial match beyond the small ~2,000-HUC
#          universe in huc_coal_charac_geom_match.csv to cover every HUC
#          reachable within 8 steps of a mine-adjacent candidate HUC.
#          `num_coal_mines_linked_sum` / `production_linked_sum` (the
#          endogenous regressor) still sum only genuine mine production —
#          those are unaffected by this widening, since non-mine HUCs
#          contribute zero mines/production regardless of sulfur coverage.
# Inputs:
#   clean_data/huc_step_distance.parquet          (Step 1 output)
#   clean_data/huc_coal_charac_geom_match.csv      (minehuc classification)
#   clean_data/coal_huc_prod.csv                   (HUC x year production)
#   raw_data/coal_qual/CQ2025101314323_sampledetails.CSV
#   raw_data/coal_qual/CQ20251013152532_proximateultimate.CSV
#   Z:/ek559/sdwa_violations/WBD_HUC12_CONUS_pulled10262020/*.shp
#     (tohuc attrs for the network walk; full geometry for the widened
#      borehole sjoin, read once and filtered to the needed HUC subset)
#   Z:/ek559/water_instrument/cws_intake_hucs/PWS_Loctations_HUC12_A_I_2022Q2.xlsx
#   Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_FACILITIES.csv
#   Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_PUB_WATER_SYSTEMS.csv
# Outputs:
#   clean_data/huc_sulfur_extended.parquet   (cached widened borehole match)
#   clean_data/cws_data/step_instruments.parquet
# Author: EK  Date: 2026-09-13
# ============================================================

import pandas as pd
import geopandas as gpd
from shapely.geometry import Point
import numpy as np
from pathlib import Path
from collections import deque

ROOT      = Path("Z:/ek559/mining_wq")
HUC_SHP   = Path("Z:/ek559/sdwa_violations/WBD_HUC12_CONUS_pulled10262020/WBD_HUC12_CONUS_pulled10262020.shp")
HUC_CSV   = ROOT / "clean_data/huc_coal_charac_geom_match.csv"
PROD_CSV  = ROOT / "clean_data/coal_huc_prod.csv"
DIST_PQ   = ROOT / "clean_data/huc_step_distance.parquet"
SULFUR_EXT_PQ = ROOT / "clean_data/huc_sulfur_extended.parquet"
INTAKE_XL = Path("Z:/ek559/water_instrument/cws_intake_hucs/PWS_Loctations_HUC12_A_I_2022Q2.xlsx")
SDWA_DIR  = Path("Z:/ek559/sdwa_violations/SDWA_latest_downloads")
OUT_PATH  = ROOT / "clean_data/cws_data/step_instruments.parquet"
MAX_K     = 8

# ── Network attrs (tohuc walk; cheap, attrs only) ───────────────────────
print("Reading HUC network attrs (huc12, tohuc only)...")
huc_net = gpd.read_file(str(HUC_SHP), columns=["huc12", "tohuc"])
huc_net = pd.DataFrame(huc_net[["huc12", "tohuc"]]).copy()
huc_net["huc12"] = huc_net["huc12"].astype(str).str.strip()
huc_net["tohuc"] = huc_net["tohuc"].astype(str).str.strip()
all_hucs  = set(huc_net["huc12"])
tohuc_map = dict(zip(huc_net["huc12"], huc_net["tohuc"]))
upstream_map = {}
for h, to in tohuc_map.items():
    if to in all_hucs:
        upstream_map.setdefault(to, []).append(h)

def is_terminal(h):
    return h not in all_hucs

huc_csv = pd.read_csv(HUC_CSV, dtype={"huc12": str, "fromhuc": str, "tohuc": str})
mine_hucs = set(huc_csv.loc[huc_csv["minehuc"] == "mine", "huc12"].unique()) & all_hucs
print(f"Mine HUCs (structural, 'ever a mine' classification): {len(mine_hucs)}")

coal_prod = pd.read_csv(PROD_CSV, dtype={"huc12": str})
coal_prod["year"] = coal_prod["year"].astype("int64")

huc_dist = pd.read_parquet(DIST_PQ, engine="pyarrow")
candidate_hucs = set(
    huc_dist.loc[
        (huc_dist["steps_to_mine_upstream"] != -1) | (huc_dist["steps_to_mine_downstream"] != -1),
        "huc12",
    ]
)
print(f"Candidate HUCs (mine within {MAX_K} steps, either direction): {len(candidate_hucs):,}")

# ── Identity-level (candidate_huc, linked_huc, distance) pair tables ───
# main direction:    ancestors of the candidate huc (mine upstream of it)
# placebo direction: descendants of the candidate huc (mine downstream of it)
print("Building candidate-huc <-> linked-huc identity tables (both directions)...")

main_rows = []
placebo_rows = []
for h in candidate_hucs:
    seen = {h: 0}
    q = deque([h])
    while q:
        cur = q.popleft()
        d = seen[cur]
        if d >= MAX_K:
            continue
        for parent in upstream_map.get(cur, []):
            if parent not in seen:
                seen[parent] = d + 1
                q.append(parent)
    for lh, d in seen.items():
        if lh != h:
            main_rows.append((h, lh, d))

    cur, d = h, 0
    visited_chain = {h}
    while d < MAX_K:
        nxt = tohuc_map.get(cur)
        if nxt is None or is_terminal(nxt) or nxt in visited_chain:
            break
        visited_chain.add(nxt)
        d += 1
        placebo_rows.append((h, nxt, d))
        cur = nxt

main_pairs    = pd.DataFrame(main_rows,    columns=["huc12", "linked_huc12", "distance"])
placebo_pairs = pd.DataFrame(placebo_rows, columns=["huc12", "linked_huc12", "distance"])
print(f"  main-direction (ancestor) pairs:    {len(main_pairs):,}")
print(f"  placebo-direction (descendant) pairs: {len(placebo_pairs):,}")

needed_hucs = set(main_pairs["linked_huc12"]) | set(placebo_pairs["linked_huc12"]) | candidate_hucs
print(f"  Union of HUCs needing a sulfur value: {len(needed_hucs):,}")

# ── Widened borehole-to-HUC sulfur match (cached) ───────────────────────
if SULFUR_EXT_PQ.exists():
    print(f"\nLoading cached widened sulfur match: {SULFUR_EXT_PQ}")
    huc_sulfur = pd.read_parquet(SULFUR_EXT_PQ, engine="pyarrow")
    missing = needed_hucs - set(huc_sulfur["huc12"])
    if missing:
        print(f"  Cache missing {len(missing)} needed HUCs — recomputing.")
        huc_sulfur = None
else:
    huc_sulfur = None

if huc_sulfur is None:
    print("\nComputing widened borehole-to-HUC sulfur match "
          f"(reading full HUC geometry once, filtering to {len(needed_hucs):,} HUCs)...")
    sample = pd.read_csv(ROOT / "raw_data/coal_qual/CQ2025101314323_sampledetails.CSV", nrows=7450)
    sample.columns = sample.columns.str.replace(" ", "").str.lower()
    ult = pd.read_csv(ROOT / "raw_data/coal_qual/CQ20251013152532_proximateultimate.CSV", nrows=7430)
    ult.columns = ult.columns.str.replace(" ", "").str.lower()
    samplelocation = pd.merge(ult, sample, on="sampleid")
    samplelocation = samplelocation[samplelocation["sulfur"].notna()]

    geometry = [Point(xy) for xy in zip(samplelocation["longitude"], samplelocation["latitude"])]
    sample_gdf = gpd.GeoDataFrame(samplelocation, geometry=geometry, crs="EPSG:4326").to_crs("EPSG:5070")
    sample_gdf = sample_gdf[["geometry", "sulfur", "btu"]]
    sample_gdf["geometry"] = sample_gdf.buffer(20000)

    huc_geom = gpd.read_file(str(HUC_SHP), columns=["huc12"])
    huc_geom["huc12"] = huc_geom["huc12"].astype(str).str.strip()
    huc_geom = huc_geom[huc_geom["huc12"].isin(needed_hucs)].to_crs("EPSG:5070")
    print(f"  HUC geometries loaded for sjoin: {len(huc_geom):,}")

    joined = huc_geom.sjoin(sample_gdf, how="left", predicate="intersects")
    joined = pd.DataFrame(joined)[["huc12", "sulfur", "btu"]]
    joined["sulfur"] = joined["sulfur"].astype(float)
    joined["btu"]    = joined["btu"].astype(float)
    huc_sulfur = joined.groupby("huc12", as_index=False).agg(
        sulfur_colocated=("sulfur", "mean"), btu_colocated=("btu", "mean")
    )
    huc_sulfur[["sulfur_colocated", "btu_colocated"]] = huc_sulfur[["sulfur_colocated", "btu_colocated"]].fillna(0)

    SULFUR_EXT_PQ.parent.mkdir(parents=True, exist_ok=True)
    huc_sulfur.to_parquet(str(SULFUR_EXT_PQ), index=False, engine="pyarrow")
    print(f"  Cached widened sulfur match: {len(huc_sulfur):,} rows -> {SULFUR_EXT_PQ}")

# Cross-check against the existing small-universe sulfur_colocated values.
existing_sulfur = huc_csv[["huc12", "sulfur_colocated"]].drop_duplicates(subset="huc12")
chk = existing_sulfur.merge(huc_sulfur, on="huc12", suffixes=("_existing", "_new"))
if len(chk) > 0:
    max_diff = (chk["sulfur_colocated_existing"] - chk["sulfur_colocated_new"]).abs().max()
    print(f"\nCross-check widened sulfur vs existing huc_csv sulfur_colocated: "
          f"{len(chk):,} overlapping HUCs, max abs diff = {max_diff:.6f}")

mine_sulfur_map = dict(zip(huc_sulfur["huc12"], huc_sulfur["sulfur_colocated"]))

# ── PWSID -> intake HUC12 linkage (facilities join workbook, year-aware) ──
print("\nBuilding PWSID x huc12 x year intake linkage (facilities-join-workbook rule)...")

pws_type = pd.read_csv(SDWA_DIR / "SDWA_PUB_WATER_SYSTEMS.csv", low_memory=False,
                        usecols=["PWSID", "PWS_TYPE_CODE"])
cws_pwsids = set(pws_type.loc[pws_type["PWS_TYPE_CODE"] == "CWS", "PWSID"].unique())

intake = pd.read_excel(INTAKE_XL, dtype={"HUC_12": str, "FACILITY_ID": str})[
    ["HUC_12", "PWSID", "FACILITY_ID"]
].rename(columns={"HUC_12": "huc12"}).drop_duplicates()
intake["huc12"] = intake["huc12"].astype(str).str.strip()
intake = intake[intake["PWSID"].isin(cws_pwsids)]

facility = pd.read_csv(SDWA_DIR / "SDWA_FACILITIES.csv", low_memory=False,
                        usecols=["PWSID", "FACILITY_ID", "FACILITY_DEACTIVATION_DATE"])
facility = facility.merge(intake, on=["PWSID", "FACILITY_ID"], how="inner")
facility["FACILITY_DEACTIVATION_DATE"] = pd.to_datetime(facility["FACILITY_DEACTIVATION_DATE"], errors="coerce")
facility = facility[
    (facility["FACILITY_DEACTIVATION_DATE"] >= "1983-01-01") | facility["FACILITY_DEACTIVATION_DATE"].isna()
]
facility = facility.drop_duplicates()
facility["year_deactivated"] = facility["FACILITY_DEACTIVATION_DATE"].dt.year

df_years = pd.DataFrame({"year": list(range(1983, 2025))})
facility_yr = facility.merge(df_years, how="cross")
facility_yr = facility_yr[~(facility_yr["year_deactivated"] < facility_yr["year"])]

intake_link = facility_yr[["PWSID", "huc12", "year"]].drop_duplicates()
print(f"  Raw intake linkage rows: {len(intake_link):,}  PWSIDs: {intake_link['PWSID'].nunique():,}")

n_before = intake_link["PWSID"].nunique()
pwsids_in_mine = set(intake_link.loc[intake_link["huc12"].isin(mine_hucs), "PWSID"].unique())
intake_link = intake_link[~intake_link["PWSID"].isin(pwsids_in_mine)]
print(f"  Dropped {len(pwsids_in_mine)} PWSIDs with an intake HUC that is itself a mine HUC "
      f"({n_before} -> {intake_link['PWSID'].nunique()} PWSIDs)")

intake_link = intake_link[(intake_link["year"] >= 1985) & (intake_link["year"] <= 2005)]
intake_link = intake_link[intake_link["PWSID"] != "WV3303401"]
intake_link = intake_link[intake_link["huc12"].isin(candidate_hucs)]
print(f"  After year/PWSID/mine-exclusion/candidate-huc filters: "
      f"{len(intake_link):,} rows, {intake_link['PWSID'].nunique():,} PWSIDs")

if intake_link["PWSID"].nunique() == 0:
    raise RuntimeError("Intake linkage produced zero candidate PWSIDs — stop and report.")

# ── Per-PWSID-year mine linkage at every distance ───────────────────────
print("\nLinking PWSID x year to all reachable HUCs (both directions)...")

def link_to_hucs(pairs_df, label):
    long = intake_link.merge(pairs_df, on="huc12", how="inner")
    long = long.groupby(["PWSID", "year", "linked_huc12"], as_index=False)["distance"].min()
    print(f"  {label}: {len(long):,} (PWSID, year, linked_huc) links")
    return long

main_long    = link_to_hucs(main_pairs,    "main (linked hucs upstream of intake)")
placebo_long = link_to_hucs(placebo_pairs, "placebo (linked hucs downstream of intake)")

def attach_chars(long_df):
    long_df = long_df.copy()
    long_df["sulfur_colocated"] = long_df["linked_huc12"].map(mine_sulfur_map)
    long_df = long_df.merge(
        coal_prod.rename(columns={"huc12": "linked_huc12"})[["linked_huc12", "year", "num_coal_mines",
                                                               "production_short_tons_coal"]],
        on=["linked_huc12", "year"], how="left"
    )
    long_df["num_coal_mines"] = long_df["num_coal_mines"].fillna(0)
    long_df["production_short_tons_coal"] = long_df["production_short_tons_coal"].fillna(0)
    long_df["covered"]  = long_df["sulfur_colocated"].fillna(0) != 0
    long_df["is_mine"]  = long_df["linked_huc12"].isin(mine_hucs)
    return long_df

main_long    = attach_chars(main_long)
placebo_long = attach_chars(placebo_long)

# ── Build the PWSID x year x arm x k table ──────────────────────────────
print("Aggregating to PWSID x year x arm x k...")

def build_k_table(long_df, k, arm_name):
    sub = long_df[long_df["distance"] <= k]
    if len(sub) == 0:
        return pd.DataFrame(columns=[
            "PWSID", "year", "arm", "k", "n_hucs_linked", "n_hucs_covered", "cov_share",
            "sulfur_meancov", "sulfur_mean0", "num_coal_mines_linked_sum",
            "production_linked_sum", "n_mine_hucs_linked",
        ])
    counts = sub.groupby(["PWSID", "year"], as_index=False).agg(
        n_hucs_linked=("linked_huc12", "nunique"),
        n_hucs_covered=("covered", "sum"),
        num_coal_mines_linked_sum=("num_coal_mines", "sum"),
        production_linked_sum=("production_short_tons_coal", "sum"),
    )
    n_mine = (
        sub[sub["is_mine"]].groupby(["PWSID", "year"], as_index=False)["linked_huc12"].nunique()
        .rename(columns={"linked_huc12": "n_mine_hucs_linked"})
    )
    sulfur_mean0 = (
        sub.assign(sulfur0=sub["sulfur_colocated"].fillna(0))
        .groupby(["PWSID", "year"], as_index=False)["sulfur0"].mean()
        .rename(columns={"sulfur0": "sulfur_mean0"})
    )
    covered_only = sub[sub["covered"]]
    if len(covered_only) > 0:
        sulfur_meancov = (
            covered_only.groupby(["PWSID", "year"], as_index=False)["sulfur_colocated"].mean()
            .rename(columns={"sulfur_colocated": "sulfur_meancov"})
        )
    else:
        sulfur_meancov = pd.DataFrame(columns=["PWSID", "year", "sulfur_meancov"])
    out = counts.merge(n_mine, on=["PWSID", "year"], how="left")
    out["n_mine_hucs_linked"] = out["n_mine_hucs_linked"].fillna(0).astype("int64")
    out = out.merge(sulfur_mean0, on=["PWSID", "year"], how="left")
    out = out.merge(sulfur_meancov, on=["PWSID", "year"], how="left")
    out["cov_share"] = out["n_hucs_covered"] / out["n_hucs_linked"]
    out["arm"] = arm_name
    out["k"] = k
    return out

tables = []
for k in range(1, MAX_K + 1):
    tables.append(build_k_table(main_long,    k, "main"))
    tables.append(build_k_table(placebo_long, k, "placebo"))

step_instr = pd.concat(tables, ignore_index=True)

# any_active_mine_in_window: 1 if num_coal_mines_linked_sum > 0 in >=1 year
# 1985-2005, computed within (PWSID, arm, k). Arm-sample membership itself
# (>=1 MINE huc within k, not just >=1 linked huc of any kind) uses
# n_mine_hucs_linked, computed structurally above (time-invariant "ever a
# mine huc" classification), so it does not depend on this window flag.
active_flag = (
    step_instr.groupby(["PWSID", "arm", "k"])["num_coal_mines_linked_sum"]
    .transform(lambda s: (s > 0).any())
    .astype(int)
)
step_instr["any_active_mine_in_window"] = active_flag

step_instr["n_hucs_covered"]     = step_instr["n_hucs_covered"].astype("int64")
step_instr["n_hucs_linked"]      = step_instr["n_hucs_linked"].astype("int64")
step_instr["n_mine_hucs_linked"] = step_instr["n_mine_hucs_linked"].astype("int64")

# ── Gate: k=1 main arm sulfur_meancov vs existing sulfur_upstream_sum ────
print("\nGATE: k=1 main-arm sulfur_meancov vs existing sulfur_upstream_sum (D1 sample)")
existing = pd.read_parquet(ROOT / "clean_data/cws_data/prod_vio_sulfur.parquet", engine="pyarrow")
existing = existing[
    (existing["minehuc_downstream_of_mine"] == 1) & (existing["minehuc_mine"] == 0)
    & (existing["year"] >= 1985) & (existing["year"] <= 2005) & (existing["PWSID"] != "WV3303401")
][["PWSID", "year", "sulfur_upstream_sum"]].drop_duplicates()

new_k1 = step_instr[(step_instr["arm"] == "main") & (step_instr["k"] == 1)][
    ["PWSID", "year", "sulfur_meancov"]
]
cmp = existing.merge(new_k1, on=["PWSID", "year"], how="inner")
print(f"  Matched (PWSID, year) rows: {len(cmp):,} / {len(existing):,} existing")
diff = (cmp["sulfur_upstream_sum"].fillna(0) - cmp["sulfur_meancov"].fillna(0)).abs()
print(f"  Max abs diff: {diff.max():.6f}   Mean abs diff: {diff.mean():.6f}   "
      f"Rows with diff>0.01: {(diff > 0.01).sum()}")

# ── Schema enforcement ───────────────────────────────────────────────
step_instr["PWSID"] = step_instr["PWSID"].astype(str)
step_instr["year"]  = step_instr["year"].astype("int64")
step_instr["k"]     = step_instr["k"].astype("int64")

print("\nDtypes before write:")
print(step_instr.dtypes)

if OUT_PATH.exists():
    print(f"WARNING: {OUT_PATH} already exists — overwriting")
OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
step_instr.to_parquet(str(OUT_PATH), index=False, engine="pyarrow")

result = pd.read_parquet(str(OUT_PATH), engine="pyarrow")
print(f"\nWritten {len(result):,} rows x {result.shape[1]} columns to {OUT_PATH}")
for arm in ["main", "placebo"]:
    for k in [1, 8]:
        sub = result[(result["arm"] == arm) & (result["k"] == k) & (result["n_mine_hucs_linked"] >= 1)]
        print(f"  {arm} k={k} (n_mine_hucs_linked>=1): {sub['PWSID'].nunique()} CWSs, {len(sub)} obs")

# ── Disjointness assertion (main vs placebo CWS sets at every k) ────────
# Arm membership is defined by n_mine_hucs_linked (a real mine within k),
# not n_hucs_linked (any huc within k, used only for sulfur aggregation).
print("\nAsserting main/placebo disjointness at every k...")
for k in range(1, MAX_K + 1):
    main_at_k    = result[(result["arm"] == "main")    & (result["k"] == k) & (result["n_mine_hucs_linked"] >= 1)]
    placebo_at_k = result[(result["arm"] == "placebo") & (result["k"] == k) & (result["n_mine_hucs_linked"] >= 1)]

    main_pwsids         = set(main_at_k["PWSID"].unique())
    placebo_candidate    = set(placebo_at_k["PWSID"].unique())
    placebo_pure_pwsids  = placebo_candidate - main_pwsids

    overlap = main_pwsids & placebo_pure_pwsids
    print(f"  k={k}: main sample={len(main_pwsids)}, placebo sample (purity-screened)={len(placebo_pure_pwsids)}, "
          f"overlap={len(overlap)}")
    if overlap:
        raise RuntimeError(
            f"Main/placebo overlap at k={k}: {len(overlap)} PWSIDs — arm definitions are not disjoint."
        )
