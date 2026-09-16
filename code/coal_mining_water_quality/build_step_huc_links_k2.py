# ============================================================
# Script: build_step_huc_links_k2.py
# Purpose: Rebuild the (PWSID -> linked HUC12, distance) pair table for the
#          k=2 A-full main arm only, needed by the
#          scatterhuccoalsulfur_pooled_k2 figure. step_instruments.parquet
#          persists only PWSID-level aggregates, not the underlying pair
#          table, so this is a cheap, depth-2-only reimplementation of the
#          relevant slice of build_step_instruments.py (read-only; that
#          script is not modified).
# Inputs:
#   clean_data/cws_data/step_instruments.parquet   (k2 main-arm PWSID universe)
#   clean_data/huc_coal_charac_geom_match.csv       (minehuc classification)
#   clean_data/huc_step_distance.parquet            (candidate-huc filter)
#   Z:/ek559/sdwa_violations/WBD_HUC12_CONUS_pulled10262020/*.shp  (huc12, tohuc attrs)
#   Z:/ek559/water_instrument/cws_intake_hucs/PWS_Loctations_HUC12_A_I_2022Q2.xlsx
#   Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_FACILITIES.csv
#   Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_PUB_WATER_SYSTEMS.csv
# Outputs:
#   clean_data/cws_data/step_huc_links_k2.parquet   (PWSID, linked_huc12, distance)
# Author: EK  Date: 2026-09-14
# ============================================================

import pandas as pd
import geopandas as gpd
from pathlib import Path
from collections import deque

ROOT      = Path("Z:/ek559/mining_wq")
HUC_SHP   = Path("Z:/ek559/sdwa_violations/WBD_HUC12_CONUS_pulled10262020/WBD_HUC12_CONUS_pulled10262020.shp")
HUC_CSV   = ROOT / "clean_data/huc_coal_charac_geom_match.csv"
DIST_PQ   = ROOT / "clean_data/huc_step_distance.parquet"
INTAKE_XL = Path("Z:/ek559/water_instrument/cws_intake_hucs/PWS_Loctations_HUC12_A_I_2022Q2.xlsx")
SDWA_DIR  = Path("Z:/ek559/sdwa_violations/SDWA_latest_downloads")
PURITY_PQ = ROOT / "clean_data/cws_data/step_purity_flags.parquet"
OUT_PATH  = ROOT / "clean_data/cws_data/step_huc_links_k2.parquet"
K = 2

if OUT_PATH.exists():
    print(f"WARNING: {OUT_PATH} already exists — overwriting")

# ── k=2 main-arm PWSID universe (A2 intake-purity screened) ─────────────
si = pd.read_parquet(ROOT / "clean_data/cws_data/step_instruments.parquet", engine="pyarrow")
purity = pd.read_parquet(PURITY_PQ, engine="pyarrow")
a2_main_k2 = set(purity.loc[(purity["arm"] == "main") & (purity["k"] == K) & (purity["a2_pure"] == 1), "PWSID"])
main_k2 = si[(si["arm"] == "main") & (si["k"] == K) & (si["n_mine_hucs_linked"] >= 1)
             & (si["PWSID"].isin(a2_main_k2))]
main_k2_pwsids = set(main_k2["PWSID"].unique())
print(f"k=2 main-arm universe (A2 intake-purity screened): {len(main_k2_pwsids):,} PWSIDs")

# ── HUC network attrs (tohuc walk; cheap, attrs only) ────────────────────
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

huc_csv = pd.read_csv(HUC_CSV, dtype={"huc12": str, "fromhuc": str, "tohuc": str})
mine_hucs = set(huc_csv.loc[huc_csv["minehuc"] == "mine", "huc12"].unique()) & all_hucs
print(f"Mine HUCs: {len(mine_hucs)}")

huc_dist = pd.read_parquet(DIST_PQ, engine="pyarrow")
candidate_hucs = set(
    huc_dist.loc[
        (huc_dist["steps_to_mine_upstream"] != -1) | (huc_dist["steps_to_mine_downstream"] != -1),
        "huc12",
    ]
)
print(f"Candidate HUCs (mine within 8 steps, either direction): {len(candidate_hucs):,}")

# ── intake_link — verbatim copy of build_step_instruments.py:186-226 ────
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

# ── Restrict to k=2 main-arm PWSIDs ──────────────────────────────────────
intake_link = intake_link[intake_link["PWSID"].isin(main_k2_pwsids)]
print(f"  Restricted to k=2 main-arm PWSIDs: {len(intake_link):,} rows, "
      f"{intake_link['PWSID'].nunique():,} PWSIDs")

# ── BFS upstream (ancestors) to depth <= 2 for each distinct intake huc12 ──
print("\nBFS upstream to depth <= 2 for each distinct intake huc12...")
intake_hucs = sorted(intake_link["huc12"].unique())
pair_rows = []
for h in intake_hucs:
    seen = {h: 0}
    q = deque([h])
    while q:
        cur = q.popleft()
        d = seen[cur]
        if d >= K:
            continue
        for parent in upstream_map.get(cur, []):
            if parent not in seen:
                seen[parent] = d + 1
                q.append(parent)
    for lh, d in seen.items():
        if lh != h:
            pair_rows.append((h, lh, d))

pairs = pd.DataFrame(pair_rows, columns=["huc12", "linked_huc12", "distance"])
print(f"  (intake_huc, linked_huc, distance) pairs: {len(pairs):,}")

# ── Join back to PWSIDs; collapse to PWSID-level distinct linked HUCs ───
pwsid_huc = intake_link[["PWSID", "huc12"]].drop_duplicates()
long = pwsid_huc.merge(pairs, on="huc12", how="inner")
out = long.groupby(["PWSID", "linked_huc12"], as_index=False)["distance"].min()

out["PWSID"] = out["PWSID"].astype(str)
out["linked_huc12"] = out["linked_huc12"].astype(str)
out["distance"] = out["distance"].astype("int64")

print("\nDtypes before write:")
print(out.dtypes)
OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
out.to_parquet(str(OUT_PATH), index=False, engine="pyarrow")

result = pd.read_parquet(OUT_PATH, engine="pyarrow")
print(f"\nWritten {len(result):,} rows to {OUT_PATH} "
      f"({result['PWSID'].nunique():,} PWSIDs)")

# ── Sanity gate: distinct linked HUC12 count must equal n_hucs_linked ────
print("\nSanity gate: distinct linked-HUC12 count vs step_instruments.parquet n_hucs_linked (k=2)...")
check_pwsids = sorted(main_k2_pwsids & set(result["PWSID"].unique()))[:50]
n_checked, n_mismatch = 0, 0
si_k2_max = main_k2.groupby("PWSID")["n_hucs_linked"].max()
for pid in check_pwsids:
    built_n = result.loc[result["PWSID"] == pid, "linked_huc12"].nunique()
    ref_n = si_k2_max.get(pid, None)
    n_checked += 1
    if ref_n is None or built_n != ref_n:
        n_mismatch += 1
        print(f"  MISMATCH {pid}: built={built_n}, step_instruments n_hucs_linked={ref_n}")
print(f"  Checked {n_checked} PWSIDs, {n_mismatch} mismatches")
assert n_mismatch == 0, "HUC-link walk diverges from step_instruments.parquet universe — stop and report."
print("Sanity gate PASSED.")
