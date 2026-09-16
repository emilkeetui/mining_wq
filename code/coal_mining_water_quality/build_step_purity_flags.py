# ============================================================
# Script: build_step_purity_flags.py
# Purpose: Classify every candidate utility's intake HUC12 portfolio at each
#          flow-step depth k=1..8 and flag whether it is "A2 pure": every
#          intake HUC correctly classified in that arm's direction, none
#          unclassified and none classified the wrong direction. main arm =
#          downstream-only (mine within k steps upstream of every intake);
#          placebo arm = mirror upstream-only (mine within k steps
#          downstream of every intake, none upstream). This A2 screen
#          becomes the estimation sample going forward, replacing the "at
#          least one qualifying intake" (n_mine_hucs_linked >= 1) screen
#          alone.
# Inputs:
#   clean_data/cws_data/step_instruments.parquet  (per-arm/k candidate universe)
#   clean_data/huc_coal_charac_geom_match.csv      (minehuc classification)
#   clean_data/huc_step_distance.parquet           (k-step distance to mine)
#   Z:/ek559/water_instrument/cws_intake_hucs/PWS_Loctations_HUC12_A_I_2022Q2.xlsx
#   Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_FACILITIES.csv
#   Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_PUB_WATER_SYSTEMS.csv
# Outputs:
#   clean_data/cws_data/step_purity_flags.parquet
# Author: EK  Date: 2026-09-15
# ============================================================

import pandas as pd
from pathlib import Path

ROOT      = Path("Z:/ek559/mining_wq")
HUC_CSV   = ROOT / "clean_data/huc_coal_charac_geom_match.csv"
DIST_PQ   = ROOT / "clean_data/huc_step_distance.parquet"
INTAKE_XL = Path("Z:/ek559/water_instrument/cws_intake_hucs/PWS_Loctations_HUC12_A_I_2022Q2.xlsx")
SDWA_DIR  = Path("Z:/ek559/sdwa_violations/SDWA_latest_downloads")
SI_PQ     = ROOT / "clean_data/cws_data/step_instruments.parquet"
OUT_PATH  = ROOT / "clean_data/cws_data/step_purity_flags.parquet"

K_VALUES = list(range(1, 9))

# Expected A2 utility counts from the read-only probe
# (plan a2-intake-purity-sample-pipeline.md) -- the hard gate below.
EXPECTED_A2 = {
    1: {"main": 340,  "placebo": 370},
    2: {"main": 582,  "placebo": 607},
    3: {"main": 764,  "placebo": 784},
    4: {"main": 925,  "placebo": 969},
    5: {"main": 1088, "placebo": 1166},
    6: {"main": 1216, "placebo": 1365},
    7: {"main": 1342, "placebo": 1521},
    8: {"main": 1426, "placebo": 1646},
}

if OUT_PATH.exists():
    print(f"WARNING: {OUT_PATH} already exists — overwriting")

si = pd.read_parquet(SI_PQ, engine="pyarrow")
si["PWSID"] = si["PWSID"].astype(str)

huc_csv = pd.read_csv(HUC_CSV, dtype={"huc12": str, "fromhuc": str, "tohuc": str})
mine_hucs = set(huc_csv.loc[huc_csv["minehuc"] == "mine", "huc12"].unique())

huc_dist = pd.read_parquet(DIST_PQ, engine="pyarrow")
candidate_hucs = set(
    huc_dist.loc[
        (huc_dist["steps_to_mine_upstream"] != -1) | (huc_dist["steps_to_mine_downstream"] != -1),
        "huc12",
    ]
)
print(f"Candidate HUCs (mine within 8 steps, either direction): {len(candidate_hucs):,}")

# ── intake_link — verbatim copy of build_step_instruments.py:189-223 ────
#    (CWS filter -> intake workbook join SDWA_FACILITIES -> deactivation-year
#    expansion -> drop utilities with any intake in a mine HUC -> years
#    1985-2005 -> drop WV3303401). Line 224's candidate_hucs filter is
#    deliberately omitted -- it silently drops unclassified intakes, exactly
#    what the A2 screen must detect.
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
print(f"  After year/PWSID/mine-exclusion filters: "
      f"{len(intake_link):,} rows, {intake_link['PWSID'].nunique():,} PWSIDs")

pwsid_huc = intake_link[["PWSID", "huc12"]].drop_duplicates()
print(f"  Distinct (PWSID, intake huc12) pairs: {len(pwsid_huc):,}, "
      f"{pwsid_huc['huc12'].nunique():,} distinct intake HUCs")

# ── Classify each distinct intake HUC at every k, aggregate to utility level ──
#    Priority: downstream > upstream > unclassified (matches the static CSV
#    convention: a HUC within k steps in both directions is labelled downstream).
#    "downstream" = mine within k steps upstream of this HUC (water flows mine -> intake).
#    "upstream"   = mine within k steps downstream of this HUC (intake -> mine).
distinct_hucs = pwsid_huc[["huc12"]].drop_duplicates()
classified_hucs_any_k = set()
agg_records = []

for k in K_VALUES:
    up_col, down_col = f"n_mine_hucs_within_{k}_up", f"n_mine_hucs_within_{k}_down"
    dist_k = huc_dist[["huc12", up_col, down_col]]
    hucs_k = distinct_hucs.merge(dist_k, on="huc12", how="left")

    is_down = hucs_k[up_col].fillna(0) >= 1
    is_up   = ~is_down & (hucs_k[down_col].fillna(0) >= 1)
    hucs_k["intake_class"] = "unclassified"
    hucs_k.loc[is_down, "intake_class"] = "downstream"
    hucs_k.loc[is_up, "intake_class"] = "upstream"

    classified_hucs_any_k |= set(hucs_k.loc[is_down | is_up, "huc12"])

    linked = pwsid_huc.merge(hucs_k[["huc12", "intake_class"]], on="huc12", how="left")
    agg = linked.groupby("PWSID").agg(
        n_intake_hucs=("huc12", "nunique"),
        n_down=("intake_class", lambda s: (s == "downstream").sum()),
        n_up=("intake_class", lambda s: (s == "upstream").sum()),
        n_uncl=("intake_class", lambda s: (s == "unclassified").sum()),
    ).reset_index()
    agg["k"] = k
    agg_records.append(agg)

agg_by_k = pd.concat(agg_records, ignore_index=True)
print(f"\nUtility x k classification rows: {len(agg_by_k):,}")

# ── No-op invariant: every classified intake HUC is a candidate HUC ─────
not_candidate = classified_hucs_any_k - candidate_hucs
assert not not_candidate, (
    f"{len(not_candidate)} classified intake HUCs are missing from candidate_hucs -- "
    f"the no-op invariant is violated: {sorted(not_candidate)[:10]}"
)
print(f"No-op invariant OK: all {len(classified_hucs_any_k):,} classified intake HUCs "
      f"(across k=1..8) are in candidate_hucs.")

# ── Build (PWSID, arm, k) rows for each arm's unscreened candidate universe ──
out_chunks = []
for arm in ["main", "placebo"]:
    for k in K_VALUES:
        cand = set(si.loc[(si["arm"] == arm) & (si["k"] == k) & (si["n_mine_hucs_linked"] >= 1), "PWSID"])
        chunk = agg_by_k.loc[(agg_by_k["k"] == k) & (agg_by_k["PWSID"].isin(cand))].copy()
        chunk["arm"] = arm

        missing = cand - set(chunk["PWSID"])
        if missing:
            zero_rows = pd.DataFrame({
                "PWSID": sorted(missing), "n_intake_hucs": 0, "n_down": 0, "n_up": 0, "n_uncl": 0,
                "k": k, "arm": arm,
            })
            chunk = pd.concat([chunk, zero_rows], ignore_index=True)
        out_chunks.append(chunk)

flags = pd.concat(out_chunks, ignore_index=True)
flags["a2_pure"] = 0
flags.loc[
    (flags["arm"] == "main") & (flags["n_intake_hucs"] > 0) & (flags["n_down"] == flags["n_intake_hucs"]),
    "a2_pure",
] = 1
flags.loc[
    (flags["arm"] == "placebo") & (flags["n_intake_hucs"] > 0) & (flags["n_up"] == flags["n_intake_hucs"]),
    "a2_pure",
] = 1

flags = flags[["PWSID", "arm", "k", "n_intake_hucs", "n_down", "n_up", "n_uncl", "a2_pure"]]

# ── Gates ─────────────────────────────────────────────────────────────────
print("\nA2 counts per k (vs probe-table expectation):")
mismatches = []
for k in K_VALUES:
    for arm in ["main", "placebo"]:
        got = int(flags.loc[(flags["k"] == k) & (flags["arm"] == arm) & (flags["a2_pure"] == 1), "PWSID"].nunique())
        want = EXPECTED_A2[k][arm]
        flag = "OK" if got == want else "MISMATCH"
        print(f"  k={k} {arm:8s} got={got:5d} want={want:5d}  {flag}")
        if got != want:
            mismatches.append((k, arm, got, want))
assert not mismatches, f"A2 counts diverge from the probe table: {mismatches}"
print("A2 count gate PASSED.")

# A2-main subset of unscreened main; A2-placebo subset of today's
# disjointness-screened placebo, at every k. A2-main / A2-placebo disjoint.
for k in K_VALUES:
    unscreened_main = set(si.loc[(si["arm"] == "main") & (si["k"] == k) & (si["n_mine_hucs_linked"] >= 1), "PWSID"])
    unscreened_plac = set(si.loc[(si["arm"] == "placebo") & (si["k"] == k) & (si["n_mine_hucs_linked"] >= 1), "PWSID"])
    today_plac = unscreened_plac - unscreened_main

    a2_main = set(flags.loc[(flags["k"] == k) & (flags["arm"] == "main") & (flags["a2_pure"] == 1), "PWSID"])
    a2_plac = set(flags.loc[(flags["k"] == k) & (flags["arm"] == "placebo") & (flags["a2_pure"] == 1), "PWSID"])

    assert a2_main <= unscreened_main, f"k={k}: A2-main not subset of unscreened main"
    assert a2_plac <= today_plac, f"k={k}: A2-placebo not subset of today's disjointness-screened placebo"
    assert a2_main.isdisjoint(a2_plac), f"k={k}: A2-main and A2-placebo overlap"
print("Nesting / disjointness gates PASSED at every k.")

# ── Enforce types, write ─────────────────────────────────────────────────
flags["PWSID"] = flags["PWSID"].astype(str)
flags["k"] = flags["k"].astype("int64")
flags["n_intake_hucs"] = flags["n_intake_hucs"].astype("int64")
flags["n_down"] = flags["n_down"].astype("int64")
flags["n_up"] = flags["n_up"].astype("int64")
flags["n_uncl"] = flags["n_uncl"].astype("int64")
flags["a2_pure"] = flags["a2_pure"].astype("int64")

print("\nDtypes before write:")
print(flags.dtypes)

OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
flags.to_parquet(OUT_PATH, index=False, engine="pyarrow")

result = pd.read_parquet(OUT_PATH, engine="pyarrow")
print(f"\nWritten {len(result):,} rows x {result.shape[1]} columns to {OUT_PATH}")
