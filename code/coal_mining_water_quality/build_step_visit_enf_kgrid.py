# ============================================================
# Script: build_step_visit_enf_kgrid.py
# Purpose: Build visit-type (5 flags) and enforcement-type (formal/
#          informal/any) aggregates over the FULL k=1..8 A-full step-grid
#          universe (both arms, all k). The `_steps` caches carry only 2
#          visit flags and lack `any_enf`; the `_k2` caches cover only the
#          k=2 universe. This cache supplies the 4 missing outcomes
#          (any_tech, any_smpl, any_insp, no_enf) for the full k-grid.
#          Read-only against raw SDWA sources and step_instruments.parquet;
#          never touches sdwa_visit_agg_steps.parquet, sdwa_enf_agg_steps.parquet,
#          sdwa_visit_agg_k2.parquet, or sdwa_enf_agg_k2.parquet.
# Inputs:
#   clean_data/cws_data/step_instruments.parquet
#   Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_SITE_VISITS.csv
#   Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.parquet
#   clean_data/cws_data/sdwa_visit_agg_steps.parquet   (read-only, consistency check)
#   clean_data/cws_data/sdwa_enf_agg_steps.parquet     (read-only, consistency check)
#   clean_data/cws_data/sdwa_visit_agg_k2.parquet      (read-only, consistency check)
#   clean_data/cws_data/sdwa_enf_agg_k2.parquet        (read-only, consistency check)
# Outputs:
#   clean_data/cws_data/sdwa_visit_agg_kgrid.parquet
#   clean_data/cws_data/sdwa_enf_agg_kgrid.parquet
# Author: EK  Date: 2026-09-15
# ============================================================

import pandas as pd
from pathlib import Path

ROOT     = Path("Z:/ek559/mining_wq")
SDWA_DIR = Path("Z:/ek559/sdwa_violations/SDWA_latest_downloads")
OUT_DIR  = ROOT / "clean_data/cws_data"

visit_out = OUT_DIR / "sdwa_visit_agg_kgrid.parquet"
enf_out   = OUT_DIR / "sdwa_enf_agg_kgrid.parquet"
for p in [visit_out, enf_out]:
    if p.exists():
        print(f"WARNING: {p} already exists — overwriting")

# ── Universe: full A-full step-grid universe (all arms, all k) ──────────
# Same rule as build_step_outcome_cache.py:32-33.
si = pd.read_parquet(OUT_DIR / "step_instruments.parquet", engine="pyarrow")
eligible = si[si["n_mine_hucs_linked"] >= 1]
universe = sorted(eligible["PWSID"].unique())
print(f"kgrid universe (>=1 mine huc linked, any arm/k, 1985-2005): {len(universe):,} PWSIDs")
if len(universe) == 0:
    raise RuntimeError("Empty kgrid universe from step_instruments.parquet — stop and report.")

# ── Site visits (column-projected + PWSID-filtered) ─────────────────────
print("\nReading SDWA_SITE_VISITS.csv (355 MB, usecols + PWSID filter)...")
sv = pd.read_csv(
    SDWA_DIR / "SDWA_SITE_VISITS.csv", low_memory=False,
    usecols=["PWSID", "VISIT_DATE", "VISIT_REASON_CODE", "AGENCY_TYPE_CODE"]
)
sv = sv[sv["PWSID"].isin(universe)].copy()
sv["VISIT_DATE"] = sv["VISIT_DATE"].astype(str).str.strip()
sv["year"] = sv["VISIT_DATE"].str[-4:]
sv = sv[sv["year"].str.isdigit()]
sv["year"] = sv["year"].astype(int)
sv = sv[(sv["year"] >= 1985) & (sv["year"] <= 2005)]
print(f"  Site visit rows in kgrid universe (1985-2005): {len(sv):,}")

sv_agg = sv.groupby(["PWSID", "year"]).agg(
    n_visits=("VISIT_REASON_CODE", "size"),
    any_snsv=("VISIT_REASON_CODE", lambda s: int(s.isin(["SNSV", "SSVF"]).any())),
    any_tech=("VISIT_REASON_CODE", lambda s: int(s.isin(["TECH", "ENGR", "OM"]).any())),
    any_enfvisit=("VISIT_REASON_CODE", lambda s: int(s.isin(["FENF", "INVG", "EMRG"]).any())),
    any_smpl=("VISIT_REASON_CODE", lambda s: int((s == "SMPL").any())),
    any_insp=("VISIT_REASON_CODE", lambda s: int(s.isin(["SITE", "RSCH", "INFI"]).any())),
).reset_index()

sv_agg["PWSID"] = sv_agg["PWSID"].astype(str)
sv_agg["year"]  = sv_agg["year"].astype("int64")
print(f"  Visit-aggregate PWSID-years: {len(sv_agg):,}")
del sv

# ── Enforcement (column-projected parquet + PWSID-filtered) ─────────────
print("\nReading SDWA_VIOLATIONS_ENFORCEMENT.parquet (column-projected + PWSID filter)...")
enf_cols = ["PWSID", "NON_COMPL_PER_BEGIN_DATE", "ENF_ACTION_CATEGORY"]
enf_raw = pd.read_parquet(SDWA_DIR / "SDWA_VIOLATIONS_ENFORCEMENT.parquet", columns=enf_cols, engine="pyarrow")
enf_raw = enf_raw[enf_raw["PWSID"].isin(universe)].copy()
print(f"  Rows in kgrid universe: {len(enf_raw):,}")

enf_raw["NON_COMPL_PER_BEGIN_DATE"] = enf_raw["NON_COMPL_PER_BEGIN_DATE"].astype(str).str.strip()
enf_raw["enf_year"] = enf_raw["NON_COMPL_PER_BEGIN_DATE"].str[-4:]
enf_valid = enf_raw[enf_raw["enf_year"].str.isdigit()].copy()
enf_valid["enf_year"] = enf_valid["enf_year"].astype(int)
enf_valid = enf_valid[(enf_valid["enf_year"] >= 1985) & (enf_valid["enf_year"] <= 2005)]

enf_agg = enf_valid.groupby(["PWSID", "enf_year"]).agg(
    any_formal=("ENF_ACTION_CATEGORY", lambda s: int((s == "Formal").any())),
    any_informal=("ENF_ACTION_CATEGORY", lambda s: int((s == "Informal").any())),
).reset_index().rename(columns={"enf_year": "year"})
# any_enf: matches enforcement_chain_d12.r's construction — a PWSID-year
# group exists iff it has >=1 enforcement record, so any_enf is TRUE for
# every grouped row (zero-filled to 0 downstream for absent PWSID-years).
enf_agg["any_enf"] = 1

enf_agg["PWSID"] = enf_agg["PWSID"].astype(str)
enf_agg["year"]  = enf_agg["year"].astype("int64")
print(f"  Enforcement-aggregate PWSID-years: {len(enf_agg):,}")
del enf_raw, enf_valid

# ── Consistency gate 1: against the existing _steps caches ──────────────
print("\nConsistency check against sdwa_visit_agg_steps.parquet / sdwa_enf_agg_steps.parquet...")
sv_steps = pd.read_parquet(OUT_DIR / "sdwa_visit_agg_steps.parquet", engine="pyarrow")
enf_steps = pd.read_parquet(OUT_DIR / "sdwa_enf_agg_steps.parquet", engine="pyarrow")

sv_check = sv_agg.merge(sv_steps, on=["PWSID", "year"], how="inner", suffixes=("_kgrid", "_steps"))
for col in ["n_visits", "any_snsv", "any_enfvisit"]:
    mism = (sv_check[f"{col}_kgrid"] != sv_check[f"{col}_steps"]).sum()
    print(f"  {col}: {len(sv_check):,} shared rows, {mism} mismatches")
    assert mism == 0, f"Visit aggregate mismatch on {col} — builder diverged from build_step_outcome_cache.py."

enf_check = enf_agg.merge(enf_steps, on=["PWSID", "year"], how="inner", suffixes=("_kgrid", "_steps"))
for col in ["any_formal", "any_informal"]:
    mism = (enf_check[f"{col}_kgrid"] != enf_check[f"{col}_steps"]).sum()
    print(f"  {col}: {len(enf_check):,} shared rows, {mism} mismatches")
    assert mism == 0, f"Enforcement aggregate mismatch on {col} — builder diverged from build_step_outcome_cache.py."
print("Consistency gate 1 (vs _steps) PASSED.")

# ── Consistency gate 2: against the _k2 caches (k2 universe subset check) ─
print("\nConsistency check against sdwa_visit_agg_k2.parquet / sdwa_enf_agg_k2.parquet...")
sv_k2 = pd.read_parquet(OUT_DIR / "sdwa_visit_agg_k2.parquet", engine="pyarrow")
enf_k2 = pd.read_parquet(OUT_DIR / "sdwa_enf_agg_k2.parquet", engine="pyarrow")

sv_k2_check = sv_k2.merge(sv_agg, on=["PWSID", "year"], how="left", suffixes=("_k2", "_kgrid"), indicator=True)
missing_sv = (sv_k2_check["_merge"] != "both").sum()
print(f"  visit: {len(sv_k2):,} k2 rows, {missing_sv} not found in kgrid cache (must be 0)")
assert missing_sv == 0, "k2 visit universe is not a subset of the kgrid universe."
shared_cols = ["n_visits", "any_snsv", "any_enfvisit", "any_tech", "any_smpl", "any_insp"]
for col in shared_cols:
    mism = (sv_k2_check[f"{col}_k2"] != sv_k2_check[f"{col}_kgrid"]).sum()
    print(f"  {col}: {mism} mismatches")
    assert mism == 0, f"Visit aggregate mismatch on {col} vs _k2 cache."

enf_k2_check = enf_k2.merge(enf_agg, on=["PWSID", "year"], how="left", suffixes=("_k2", "_kgrid"), indicator=True)
missing_enf = (enf_k2_check["_merge"] != "both").sum()
print(f"  enforcement: {len(enf_k2):,} k2 rows, {missing_enf} not found in kgrid cache (must be 0)")
assert missing_enf == 0, "k2 enforcement universe is not a subset of the kgrid universe."
for col in ["any_formal", "any_informal", "any_enf"]:
    mism = (enf_k2_check[f"{col}_k2"] != enf_k2_check[f"{col}_kgrid"]).sum()
    print(f"  {col}: {mism} mismatches")
    assert mism == 0, f"Enforcement aggregate mismatch on {col} vs _k2 cache."
print("Consistency gate 2 (vs _k2, subset check) PASSED.")

# ── Write ─────────────────────────────────────────────────────────────
print("\nDtypes (visit aggregate):")
print(sv_agg.dtypes)
sv_agg.to_parquet(str(visit_out), index=False, engine="pyarrow")

print("\nDtypes (enforcement aggregate):")
print(enf_agg.dtypes)
enf_agg.to_parquet(str(enf_out), index=False, engine="pyarrow")

sv_check_rt = pd.read_parquet(visit_out, engine="pyarrow")
enf_check_rt = pd.read_parquet(enf_out, engine="pyarrow")
print(f"\nWritten {len(sv_check_rt):,} rows to {visit_out}")
print(f"Written {len(enf_check_rt):,} rows to {enf_out}")
