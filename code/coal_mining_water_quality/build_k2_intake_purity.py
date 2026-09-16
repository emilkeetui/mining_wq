# ============================================================
# Script: build_k2_intake_purity.py
# Purpose: Classify each k=2 main-arm utility's intake HUC12s as downstream,
#          upstream, or unclassified (via k-step linkage distances), and
#          build three nested utility samples for a robustness comparison:
#          status quo (SQ, the k2 main arm), no-upstream (A1), and
#          downstream-only (A2).
# Inputs:
#   clean_data/cws_data/step_instruments.parquet   (k2 main-arm PWSID universe)
#   clean_data/huc_coal_charac_geom_match.csv       (minehuc classification)
#   clean_data/huc_step_distance.parquet            (k-step distance to mine)
#   Z:/ek559/water_instrument/cws_intake_hucs/PWS_Loctations_HUC12_A_I_2022Q2.xlsx
#   Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_FACILITIES.csv
#   Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_PUB_WATER_SYSTEMS.csv
# Outputs:
#   clean_data/cws_data/k2_intake_purity.parquet
# Author: EK  Date: 2026-09-15
# ============================================================

import pandas as pd
from pathlib import Path

ROOT      = Path("Z:/ek559/mining_wq")
HUC_CSV   = ROOT / "clean_data/huc_coal_charac_geom_match.csv"
DIST_PQ   = ROOT / "clean_data/huc_step_distance.parquet"
INTAKE_XL = Path("Z:/ek559/water_instrument/cws_intake_hucs/PWS_Loctations_HUC12_A_I_2022Q2.xlsx")
SDWA_DIR  = Path("Z:/ek559/sdwa_violations/SDWA_latest_downloads")
OUT_PATH  = ROOT / "clean_data/cws_data/k2_intake_purity.parquet"

if OUT_PATH.exists():
    print(f"WARNING: {OUT_PATH} already exists — overwriting")

# ── k=2 main-arm PWSID universe ──────────────────────────────────────────
si = pd.read_parquet(ROOT / "clean_data/cws_data/step_instruments.parquet", engine="pyarrow")
main_k2 = si[(si["arm"] == "main") & (si["k"] == 2) & (si["n_mine_hucs_linked"] >= 1)]
main_k2_pwsids = set(main_k2["PWSID"].unique())
print(f"k=2 main-arm universe (SQ): {len(main_k2_pwsids):,} PWSIDs")

huc_csv = pd.read_csv(HUC_CSV, dtype={"huc12": str, "fromhuc": str, "tohuc": str})
mine_hucs = set(huc_csv.loc[huc_csv["minehuc"] == "mine", "huc12"].unique())
print(f"Mine HUCs (CSV): {len(mine_hucs)}")

# ── intake_link — verbatim copy of build_step_huc_links_k2.py:75-109 ────
#    (CWS filter -> intake workbook join SDWA_FACILITIES -> deactivation-year
#    expansion -> drop utilities with any intake in a mine HUC -> years
#    1985-2005 -> drop WV3303401). Deliberately does NOT apply the
#    candidate_hucs filter, which would silently drop unclassified intakes —
#    exactly what sample A2 needs to detect.
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

# ── Restrict to k=2 main-arm PWSIDs ──────────────────────────────────────
intake_link = intake_link[intake_link["PWSID"].isin(main_k2_pwsids)]
print(f"  Restricted to k=2 main-arm PWSIDs: {len(intake_link):,} rows, "
      f"{intake_link['PWSID'].nunique():,} PWSIDs")

# ── Classify each distinct intake HUC via k-step distance ──────────────
#    Priority: downstream > upstream > unclassified (matches the static CSV
#    convention: HUCs within 2 steps in both directions are labelled downstream).
huc_dist = pd.read_parquet(DIST_PQ, engine="pyarrow")
intake_hucs = pd.DataFrame({"huc12": sorted(intake_link["huc12"].unique())})
intake_hucs = intake_hucs.merge(
    huc_dist[["huc12", "n_mine_hucs_within_2_up", "n_mine_hucs_within_2_down"]],
    on="huc12", how="left",
)

def classify(row):
    if pd.notna(row["n_mine_hucs_within_2_up"]) and row["n_mine_hucs_within_2_up"] >= 1:
        return "downstream"
    if pd.notna(row["n_mine_hucs_within_2_down"]) and row["n_mine_hucs_within_2_down"] >= 1:
        return "upstream"
    return "unclassified"

intake_hucs["intake_class"] = intake_hucs.apply(classify, axis=1)
print("\nIntake HUC classification counts:")
print(intake_hucs["intake_class"].value_counts())

intake_link = intake_link.merge(intake_hucs[["huc12", "intake_class"]], on="huc12", how="left")

# ── Collapse to utility level ────────────────────────────────────────────
pwsid_huc = intake_link[["PWSID", "huc12", "intake_class"]].drop_duplicates()
agg = pwsid_huc.groupby("PWSID").agg(
    n_intake_hucs=("huc12", "nunique"),
    n_down=("intake_class", lambda s: (s == "downstream").sum()),
    n_up=("intake_class", lambda s: (s == "upstream").sum()),
    n_uncl=("intake_class", lambda s: (s == "unclassified").sum()),
).reset_index()
agg["has_up"] = agg["n_up"] > 0
agg["has_uncl"] = agg["n_uncl"] > 0

# ── Attach sample flags ──────────────────────────────────────────────────
agg["in_sq"] = agg["PWSID"].isin(main_k2_pwsids)
agg["in_a1"] = agg["in_sq"] & ~agg["has_up"]
agg["in_a2"] = agg["in_sq"] & ~agg["has_up"] & ~agg["has_uncl"]

# ── Gates ─────────────────────────────────────────────────────────────
missing_sq = main_k2_pwsids - set(agg.loc[agg["in_sq"], "PWSID"])
assert not missing_sq, f"SQ PWSIDs missing from purity table: {sorted(missing_sq)[:10]}"

bad_no_down = agg.loc[agg["in_sq"] & (agg["n_down"] < 1), "PWSID"].tolist()
assert not bad_no_down, (
    f"{len(bad_no_down)} SQ PWSIDs have zero downstream intake HUCs — classification "
    f"disagrees with build_step_instruments.py: {bad_no_down[:10]}"
)

n_sq = int(agg["in_sq"].sum())
n_a1 = int(agg["in_a1"].sum())
n_a2 = int(agg["in_a2"].sum())
print(f"\nSample counts: SQ={n_sq}  A1 (no upstream)={n_a1}  A2 (downstream only)={n_a2}")

sq = agg.loc[agg["in_sq"]]
print("\nCross-tab of has_up x has_uncl within SQ:")
print(pd.crosstab(sq["has_up"], sq["has_uncl"]))

# Diagnostic only: stricter alternative upstream definition ignoring priority
huc_dist_up_only = huc_dist[["huc12", "n_mine_hucs_within_2_down"]].rename(
    columns={"n_mine_hucs_within_2_down": "n_down2"})
diag = pwsid_huc.merge(huc_dist_up_only, on="huc12", how="left")
diag_has_up_strict = diag.groupby("PWSID")["n_down2"].apply(lambda s: (s.fillna(0) >= 1).any())
n_strict_up = int(diag_has_up_strict.reindex(sq["PWSID"]).fillna(False).sum())
print(f"\nDiagnostic: SQ utilities with >=1 intake within 2 steps downstream-of-mine "
      f"(regardless of priority): {n_strict_up}")

# ── Enforce types, write ─────────────────────────────────────────────────
agg["PWSID"] = agg["PWSID"].astype(str)
print("\nDtypes before write:")
print(agg.dtypes)

OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
agg.to_parquet(OUT_PATH, index=False, engine="pyarrow")

result = pd.read_parquet(OUT_PATH, engine="pyarrow")
print(f"\nWritten {len(result):,} rows x {result.shape[1]} columns to {OUT_PATH}")
