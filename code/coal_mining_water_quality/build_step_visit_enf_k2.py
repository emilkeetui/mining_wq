# ============================================================
# Script: build_step_visit_enf_k2.py
# Purpose: Build visit-type (5 flags) and enforcement-type (formal/
#          informal/any) aggregates over the k=2 A-full step-grid
#          universe (main + purity-screened placebo arms). The existing
#          `_steps` caches carry only 2 visit flags and lack `any_enf`,
#          which the k2 h2/h3 tables need. Read-only against raw SDWA
#          sources and against step_instruments.parquet; never touches
#          sdwa_visit_agg_steps.parquet or sdwa_enf_agg_steps.parquet.
# Inputs:
#   clean_data/cws_data/step_instruments.parquet
#   Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_SITE_VISITS.csv
#   Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.parquet
#   clean_data/cws_data/sdwa_visit_agg_steps.parquet   (read-only, consistency check)
#   clean_data/cws_data/sdwa_enf_agg_steps.parquet     (read-only, consistency check)
# Outputs:
#   clean_data/cws_data/sdwa_visit_agg_k2.parquet
#   clean_data/cws_data/sdwa_enf_agg_k2.parquet
# Author: EK  Date: 2026-09-14
# ============================================================

import pandas as pd
from pathlib import Path

ROOT     = Path("Z:/ek559/mining_wq")
SDWA_DIR = Path("Z:/ek559/sdwa_violations/SDWA_latest_downloads")
OUT_DIR  = ROOT / "clean_data/cws_data"

visit_out = OUT_DIR / "sdwa_visit_agg_k2.parquet"
enf_out   = OUT_DIR / "sdwa_enf_agg_k2.parquet"
for p in [visit_out, enf_out]:
    if p.exists():
        print(f"WARNING: {p} already exists — overwriting")

# ── Universe: union of k=2 main arm + purity-screened k=2 placebo arm ───
si = pd.read_parquet(OUT_DIR / "step_instruments.parquet", engine="pyarrow")
main_k2 = si[(si["arm"] == "main") & (si["k"] == 2) & (si["n_mine_hucs_linked"] >= 1)]
main_ids = set(main_k2["PWSID"].unique())
plac_k2 = si[(si["arm"] == "placebo") & (si["k"] == 2) & (si["n_mine_hucs_linked"] >= 1)
             & (~si["PWSID"].isin(main_ids))]

universe = sorted(main_ids | set(plac_k2["PWSID"].unique()))
print(f"k2 universe (main {len(main_ids):,} + purity-screened placebo "
      f"{plac_k2['PWSID'].nunique():,}): {len(universe):,} PWSIDs")
if len(universe) == 0:
    raise RuntimeError("Empty k2 universe from step_instruments.parquet — stop and report.")

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
print(f"  Site visit rows in k2 universe (1985-2005): {len(sv):,}")

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
print(f"  Rows in k2 universe: {len(enf_raw):,}")

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

# ── Consistency gate against the existing _steps caches ─────────────────
print("\nConsistency check against sdwa_visit_agg_steps.parquet / sdwa_enf_agg_steps.parquet...")
sv_steps = pd.read_parquet(OUT_DIR / "sdwa_visit_agg_steps.parquet", engine="pyarrow")
enf_steps = pd.read_parquet(OUT_DIR / "sdwa_enf_agg_steps.parquet", engine="pyarrow")

sv_check = sv_agg.merge(sv_steps, on=["PWSID", "year"], how="inner", suffixes=("_k2", "_steps"))
for col in ["n_visits", "any_snsv", "any_enfvisit"]:
    mism = (sv_check[f"{col}_k2"] != sv_check[f"{col}_steps"]).sum()
    print(f"  {col}: {len(sv_check):,} shared rows, {mism} mismatches")
    assert mism == 0, f"Visit aggregate mismatch on {col} — builder diverged from build_step_outcome_cache.py."

enf_check = enf_agg.merge(enf_steps, on=["PWSID", "year"], how="inner", suffixes=("_k2", "_steps"))
for col in ["any_formal", "any_informal"]:
    mism = (enf_check[f"{col}_k2"] != enf_check[f"{col}_steps"]).sum()
    print(f"  {col}: {len(enf_check):,} shared rows, {mism} mismatches")
    assert mism == 0, f"Enforcement aggregate mismatch on {col} — builder diverged from build_step_outcome_cache.py."
print("Consistency gate PASSED.")

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
