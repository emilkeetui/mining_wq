# ============================================================
# Script: build_msha_accidents.py
# Purpose: Parse MSHA Part 50 coal accident/injury/illness files (1985-2005)
#          into a record-level table and a mine x year panel, then sum
#          accidents at coal mines within 2 HUC12 flow steps upstream
#          (main arm) and downstream (placebo arm) of each CWS intake,
#          as a candidate instrument. Record-level data keeps every Part 50
#          field so future instruments (water-related accidents, shutdown-
#          type accidents, injuries, fatalities) can be rebuilt without
#          re-parsing.
# Inputs:
#   clean_data/msha_part50_raw/txt/CAIM{1985..2005}_5.txt  (coal mine operators)
#   clean_data/msha_part50_raw/txt/CCTI{1985..2005}_5.txt  (coal contractors)
#   clean_data/msha_part50_raw/Accidents_ogi.zip  (MSHA OGI 2000+, code labels + validation)
#   raw_data/msha/Mines.txt                        (mine coordinates, all MSHA mine IDs)
#   clean_data/coal_mine_prod_charac.parquet       (production-panel mine IDs, flag only)
#   clean_data/huc_coal_charac_geom_match.csv      (minehuc classification)
#   clean_data/huc_step_distance.parquet           (candidate-huc filter)
#   clean_data/cws_data/step_instruments.parquet   (universe cross-check)
#   Z:/ek559/sdwa_violations/WBD_HUC12_CONUS_pulled10262020/*.shp
#   Z:/ek559/water_instrument/cws_intake_hucs/PWS_Loctations_HUC12_A_I_2022Q2.xlsx
#   Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_FACILITIES.csv
#   Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_PUB_WATER_SYSTEMS.csv
# Outputs:
#   clean_data/msha_accidents_records.parquet      (one row per Part 50 report)
#   clean_data/msha_accidents_mine_year.parquet    (mine_id x year counts + huc12)
#   clean_data/cws_data/msha_accidents_k2.parquet  (PWSID x year, _upstream_k2 / _downstream_k2)
# Author: EK  Date: 2026-09-23
# ============================================================

import zipfile
from collections import deque
from pathlib import Path

import geopandas as gpd
import numpy as np
import pandas as pd

ROOT      = Path("Z:/ek559/mining_wq")
RAW_DIR   = ROOT / "clean_data/msha_part50_raw"
TXT_DIR   = RAW_DIR / "txt"
OGI_ZIP   = RAW_DIR / "Accidents_ogi.zip"
MINES_TXT = ROOT / "raw_data/msha/Mines.txt"
PROD_PQ   = ROOT / "clean_data/coal_mine_prod_charac.parquet"
HUC_SHP   = Path("Z:/ek559/sdwa_violations/WBD_HUC12_CONUS_pulled10262020/WBD_HUC12_CONUS_pulled10262020.shp")
HUC_CSV   = ROOT / "clean_data/huc_coal_charac_geom_match.csv"
DIST_PQ   = ROOT / "clean_data/huc_step_distance.parquet"
STEP_PQ   = ROOT / "clean_data/cws_data/step_instruments.parquet"
INTAKE_XL = Path("Z:/ek559/water_instrument/cws_intake_hucs/PWS_Loctations_HUC12_A_I_2022Q2.xlsx")
SDWA_DIR  = Path("Z:/ek559/sdwa_violations/SDWA_latest_downloads")

OUT_RECORDS   = ROOT / "clean_data/msha_accidents_records.parquet"
OUT_MINE_YEAR = ROOT / "clean_data/msha_accidents_mine_year.parquet"
OUT_K2        = ROOT / "clean_data/cws_data/msha_accidents_k2.parquet"

YEARS = range(1985, 2006)
K     = 2

# ── Part 50 fixed-width layout (Part 50 User's Handbook, Figs 3.2/3.3) ──
# 1-indexed inclusive positions. Contractor files (CCTI) swap the first two
# fields (contractor 1-7, mine 8-14); all later positions are identical.
LAYOUT = [
    ("subunit_cd",            15,  16),
    ("month",                 17,  18),
    ("day",                   19,  20),
    ("accident_time",         21,  24),
    ("inspection_office_cd",  30,  33),
    ("fips_state_cd",         34,  35),
    ("fips_cnty_cd",          36,  38),
    ("sic_cd",                39,  43),
    ("canvass_cd",            45,  45),
    ("ug_location_cd",        46,  47),
    ("ug_mining_method_cd",   48,  49),
    ("equip_mfr_cd",          50,  52),
    ("mining_equip_cd",       54,  55),
    ("equip_model_no",        60,  70),
    ("shift_begin_time",      85,  88),
    ("classification_cd",     89,  90),
    ("accident_type_cd",      91,  92),
    ("no_injuries",           93,  95),
    ("document_no",           96, 107),
    ("sex_cd",               128, 128),
    ("age",                  137, 138),
    ("tot_exper",            139, 142),
    ("mine_exper",           143, 146),
    ("job_exper",            147, 150),
    ("occupation_cd",        151, 153),
    ("activity_cd",          159, 161),
    ("injury_source_cd",     162, 164),
    ("nature_injury_cd",     165, 167),
    ("inj_body_part_cd",     168, 170),
    ("degree_injury_cd",     171, 172),
    ("days_away_statutory",  173, 176),
    ("days_restrict",        177, 180),
    ("days_lost",            181, 184),
    ("perm_transfer_cd",     185, 185),
    ("return_to_work_dt",    186, 193),
    ("closed_doc_no",        194, 205),
    ("immed_notify_cd",      206, 207),
    ("invest_begin_dt",      208, 215),
]
NUMERIC_FIELDS = ["no_injuries", "age", "tot_exper", "mine_exper", "job_exper",
                  "days_away_statutory", "days_restrict", "days_lost"]

# Accident-category definitions (codes from MSHA OGI Accidents labels)
FATAL_DEGREE    = {"01"}
INJURY_DEGREES  = {"01", "02", "03", "04", "05", "06"}   # reportable injury, excl. accident-only/illness/non-employee
LOST_DAYS_DEGREES = {"01", "02", "03", "04", "05"}      # fatal, permanent disability, days away and/or restricted
ILLNESS_DEGREE  = {"07"}
ACC_ONLY_DEGREE = {"00"}
WATER_CLASS     = {"15", "16"}                          # impoundment, inundation
WATER_NOTIFY    = {"04", "10"}                          # inundation, impounding dam
# Immediately reportable accidents (30 CFR 50.2(h)) — trigger MSHA control
# orders over the affected area; used as the shutdown-type proxy. Excludes
# 12 (offsite injury) and 13 (not marked).
SERIOUS_NOTIFY  = {f"{i:02d}" for i in range(1, 12)}


def parse_file(path, is_contractor):
    with open(path, encoding="latin-1") as fh:
        lines = [l.rstrip("\r\n") for l in fh]
    header, body = lines[0], lines[1:]
    file_year = int(header[42:46])
    rows = []
    for l in body:
        l = l.ljust(255)
        if is_contractor:
            rec = {"contractor_id": l[0:7].strip(), "mine_id": l[7:14]}
        else:
            rec = {"mine_id": l[0:7], "contractor_id": l[7:14].strip()}
        for name, a, b in LAYOUT:
            rec[name] = l[a - 1:b].strip()
        rows.append(rec)
    df = pd.DataFrame(rows)
    df["year"] = file_year
    df["source_file"] = path.name
    df["is_contractor"] = int(is_contractor)
    return df


# ── 1. Parse all Part 50 files ────────────────────────────────────────
print("Parsing Part 50 coal files...")
parts = []
for y in YEARS:
    for prefix, is_contr in [("CAIM", False), ("CCTI", True)]:
        f = TXT_DIR / f"{prefix}{y}_5.txt"
        if not f.exists():
            raise FileNotFoundError(f)
        d = parse_file(f, is_contr)
        assert (d["year"] == y).all(), f"header year mismatch in {f.name}"
        parts.append(d)
rec = pd.concat(parts, ignore_index=True)
rec["contractor_id"] = rec["contractor_id"].replace("", np.nan)
for c in NUMERIC_FIELDS:
    rec[c] = pd.to_numeric(rec[c], errors="coerce")
rec["accident_dt"] = pd.to_datetime(
    rec["year"].astype(str) + rec["month"] + rec["day"], format="%Y%m%d", errors="coerce")
print(f"  Parsed {len(rec):,} records, {rec['mine_id'].nunique():,} mine IDs")
print(rec.groupby("year").size().to_string())
bad_dt = rec["accident_dt"].isna().sum()
print(f"  Records with unparseable accident date: {bad_dt}")

# ── 2. Code labels + validation against MSHA OGI (2000-2005 overlap) ──
print("\nLoading MSHA OGI Accidents file for labels and validation...")
with zipfile.ZipFile(OGI_ZIP) as z:
    ogi = pd.read_csv(z.open("Accidents.txt"), sep="|", encoding="latin-1",
                      dtype=str, low_memory=False)
ogi = ogi[ogi["COAL_METAL_IND"] == "C"]

label_pairs = {
    "degree_injury_cd":  "DEGREE_INJURY",
    "classification_cd": "CLASSIFICATION",
    "accident_type_cd":  "ACCIDENT_TYPE",
    "immed_notify_cd":   "IMMED_NOTIFY",
    "subunit_cd":        "SUBUNIT",
    "nature_injury_cd":  "NATURE_INJURY",
    "injury_source_cd":  "INJURY_SOURCE",
    "inj_body_part_cd":  "INJ_BODY_PART",
    "occupation_cd":     "OCCUPATION",
    "activity_cd":       "ACTIVITY",
    "mining_equip_cd":   "MINING_EQUIP",
    "ug_location_cd":    "UG_LOCATION",
    "ug_mining_method_cd": "UG_MINING_METHOD",
}
for code_col, lab in label_pairs.items():
    ogi_code = lab + "_CD" if lab + "_CD" in ogi.columns else None
    if ogi_code is None:
        continue
    lut = (ogi[[ogi_code, lab]].dropna().drop_duplicates(subset=ogi_code)
           .rename(columns={ogi_code: code_col, lab: code_col.replace("_cd", "")}))
    rec = rec.merge(lut, on=code_col, how="left")

val = rec[rec["year"] >= 2000].merge(
    ogi[["DOCUMENT_NO", "MINE_ID", "DEGREE_INJURY_CD", "CLASSIFICATION_CD",
         "ACCIDENT_TYPE_CD", "IMMED_NOTIFY_CD", "NO_INJURIES", "DAYS_LOST", "ACCIDENT_DT"]],
    left_on="document_no", right_on="DOCUMENT_NO", how="inner")
n_overlap = (rec["year"] >= 2000).sum()
print(f"  2000-2005 records: {n_overlap:,}; matched to OGI by document number: {len(val):,} "
      f"({len(val) / n_overlap:.1%})")
checks = {
    "mine_id":           (val["mine_id"], val["MINE_ID"].str.zfill(7)),
    "degree_injury_cd":  (val["degree_injury_cd"], val["DEGREE_INJURY_CD"]),
    "classification_cd": (val["classification_cd"], val["CLASSIFICATION_CD"]),
    "accident_type_cd":  (val["accident_type_cd"], val["ACCIDENT_TYPE_CD"]),
    "immed_notify_cd":   (val["immed_notify_cd"], val["IMMED_NOTIFY_CD"]),
    "no_injuries":       (val["no_injuries"], pd.to_numeric(val["NO_INJURIES"], errors="coerce")),
    "days_lost":         (val["days_lost"], pd.to_numeric(val["DAYS_LOST"], errors="coerce")),
    "accident_dt":       (val["accident_dt"], pd.to_datetime(val["ACCIDENT_DT"], errors="coerce")),
}
for name, (a, b) in checks.items():
    agree = ((a == b) | (a.isna() & b.isna())).mean()
    print(f"    field agreement {name:18s}: {agree:.1%}")

# ── 3. Record-level category flags ───────────────────────────────────
rec["fatality"]      = rec["degree_injury_cd"].isin(FATAL_DEGREE).astype("int64")
rec["injury"]        = rec["degree_injury_cd"].isin(INJURY_DEGREES).astype("int64")
rec["lost_days_injury"] = rec["degree_injury_cd"].isin(LOST_DAYS_DEGREES).astype("int64")
rec["illness"]       = rec["degree_injury_cd"].isin(ILLNESS_DEGREE).astype("int64")
rec["accident_only"] = rec["degree_injury_cd"].isin(ACC_ONLY_DEGREE).astype("int64")
rec["water_related"] = (rec["classification_cd"].isin(WATER_CLASS)
                        | rec["immed_notify_cd"].isin(WATER_NOTIFY)).astype("int64")
rec["serious_reportable"] = rec["immed_notify_cd"].isin(SERIOUS_NOTIFY).astype("int64")

# ── 4. Mine coordinates -> HUC12 (all Part 50 mine IDs) ──────────────
print("\nLocating mines (Mines.txt coordinates -> HUC12 spatial join)...")
mines = pd.read_csv(MINES_TXT, sep="|", dtype=str, encoding="latin-1", low_memory=False)
mines.columns = mines.columns.str.lower()
mines["mine_id"] = mines["mine_id"].str.zfill(7)
mines = mines[mines["mine_id"].isin(set(rec["mine_id"]))]
mines["latitude"]  = pd.to_numeric(mines["latitude"], errors="coerce")
mines["longitude"] = pd.to_numeric(mines["longitude"], errors="coerce")
mines = mines[mines["latitude"].notna() & mines["longitude"].notna() & (mines["latitude"] != 0)]
mines = mines[["mine_id", "current_mine_type", "latitude", "longitude"]].drop_duplicates("mine_id")
mine_pts = gpd.GeoDataFrame(mines, geometry=gpd.points_from_xy(mines["longitude"], mines["latitude"]),
                            crs="EPSG:4326")

huc_geo = gpd.read_file(str(HUC_SHP), columns=["huc12", "tohuc"])
huc_geo["huc12"] = huc_geo["huc12"].astype(str).str.strip()
huc_geo["tohuc"] = huc_geo["tohuc"].astype(str).str.strip()
mine_pts = mine_pts.to_crs(huc_geo.crs)
print(f"  Left CRS: {mine_pts.crs}")
print(f"  Right CRS: {huc_geo.crs}")
assert mine_pts.crs == huc_geo.crs, "CRS mismatch — reproject before joining"
mine_huc = mine_pts.sjoin(huc_geo[["huc12", "geometry"]], how="left", predicate="intersects")
mine_huc = (pd.DataFrame(mine_huc)[["mine_id", "current_mine_type", "latitude", "longitude", "huc12"]]
            .drop_duplicates("mine_id"))
print(f"  Mine IDs in Part 50: {rec['mine_id'].nunique():,}; with coordinates: {len(mines):,}; "
      f"assigned a HUC12: {mine_huc['huc12'].notna().sum():,}")

prod = pd.read_parquet(PROD_PQ, engine="pyarrow", columns=["mine_id", "huc12"])
prod["mine_id"] = prod["mine_id"].astype(str).str.replace(r"\.0$", "", regex=True).str.zfill(7)
prod_ids = set(prod["mine_id"])
chk = mine_huc.merge(prod.dropna().drop_duplicates("mine_id"), on="mine_id", suffixes=("", "_prod"))
if len(chk):
    print(f"  HUC12 agreement with production panel ({len(chk):,} shared mines): "
          f"{(chk['huc12'] == chk['huc12_prod'].astype(str)).mean():.1%}")

# ── 5. Mine x year panel ─────────────────────────────────────────────
print("\nAggregating to mine x year...")
agg_spec = dict(
    n_records=("document_no", "size"),
    n_injuries=("injury", "sum"),
    n_fatalities=("fatality", "sum"),
    n_lost_days_injuries=("lost_days_injury", "sum"),
    n_illnesses=("illness", "sum"),
    n_accident_only=("accident_only", "sum"),
    n_water_related=("water_related", "sum"),
    n_serious_reportable=("serious_reportable", "sum"),
    days_lost=("days_lost", "sum"),
    days_restrict=("days_restrict", "sum"),
)
mine_year = rec.groupby(["mine_id", "year"], as_index=False).agg(**agg_spec)
contr = (rec[rec["is_contractor"] == 1].groupby(["mine_id", "year"], as_index=False)
         .agg(n_records_contractor=("document_no", "size")))
mine_year = mine_year.merge(contr, on=["mine_id", "year"], how="left")
mine_year["n_records_contractor"] = mine_year["n_records_contractor"].fillna(0).astype("int64")
mine_year = mine_year.merge(mine_huc, on="mine_id", how="left")
mine_year["in_prod_panel"] = mine_year["mine_id"].isin(prod_ids).astype("int64")
print(f"  mine x year rows: {len(mine_year):,}; share of records at production-panel mines: "
      f"{mine_year.loc[mine_year['in_prod_panel'] == 1, 'n_records'].sum() / mine_year['n_records'].sum():.1%}")

# ── 6. CWS x year k=2 windows (mirrors build_step_instruments.py) ────
print("\nBuilding k=2 upstream/downstream HUC links (mirrors build_step_instruments.py)...")
huc_net = pd.DataFrame(huc_geo[["huc12", "tohuc"]])
all_hucs  = set(huc_net["huc12"])
tohuc_map = dict(zip(huc_net["huc12"], huc_net["tohuc"]))
upstream_map = {}
for h, to in tohuc_map.items():
    if to in all_hucs:
        upstream_map.setdefault(to, []).append(h)

huc_csv = pd.read_csv(HUC_CSV, dtype={"huc12": str, "fromhuc": str, "tohuc": str})
mine_hucs = set(huc_csv.loc[huc_csv["minehuc"] == "mine", "huc12"].unique()) & all_hucs
huc_dist = pd.read_parquet(DIST_PQ, engine="pyarrow")
candidate_hucs = set(huc_dist.loc[(huc_dist["steps_to_mine_upstream"] != -1)
                                  | (huc_dist["steps_to_mine_downstream"] != -1), "huc12"])

up_rows, dn_rows = [], []
for h in candidate_hucs:
    seen = {h: 0}
    q = deque([h])
    while q:
        cur = q.popleft()
        if seen[cur] >= K:
            continue
        for parent in upstream_map.get(cur, []):
            if parent not in seen:
                seen[parent] = seen[cur] + 1
                q.append(parent)
    up_rows += [(h, lh, d) for lh, d in seen.items() if lh != h]
    cur, d, visited = h, 0, {h}
    while d < K:
        nxt = tohuc_map.get(cur)
        if nxt is None or nxt not in all_hucs or nxt in visited:
            break
        visited.add(nxt)
        d += 1
        dn_rows.append((h, nxt, d))
        cur = nxt
up_pairs = pd.DataFrame(up_rows, columns=["huc12", "linked_huc12", "distance"])
dn_pairs = pd.DataFrame(dn_rows, columns=["huc12", "linked_huc12", "distance"])
print(f"  upstream pairs: {len(up_pairs):,}; downstream pairs: {len(dn_pairs):,}")

# PWSID -> intake HUC12, year-aware (identical rules to build_step_instruments.py)
pws_type = pd.read_csv(SDWA_DIR / "SDWA_PUB_WATER_SYSTEMS.csv", low_memory=False,
                       usecols=["PWSID", "PWS_TYPE_CODE"])
cws_pwsids = set(pws_type.loc[pws_type["PWS_TYPE_CODE"] == "CWS", "PWSID"].unique())
intake = pd.read_excel(INTAKE_XL, dtype={"HUC_12": str, "FACILITY_ID": str})[
    ["HUC_12", "PWSID", "FACILITY_ID"]].rename(columns={"HUC_12": "huc12"}).drop_duplicates()
intake["huc12"] = intake["huc12"].astype(str).str.strip()
intake = intake[intake["PWSID"].isin(cws_pwsids)]
facility = pd.read_csv(SDWA_DIR / "SDWA_FACILITIES.csv", low_memory=False,
                       usecols=["PWSID", "FACILITY_ID", "FACILITY_DEACTIVATION_DATE"])
facility = facility.merge(intake, on=["PWSID", "FACILITY_ID"], how="inner")
facility["FACILITY_DEACTIVATION_DATE"] = pd.to_datetime(facility["FACILITY_DEACTIVATION_DATE"], errors="coerce")
facility = facility[(facility["FACILITY_DEACTIVATION_DATE"] >= "1983-01-01")
                    | facility["FACILITY_DEACTIVATION_DATE"].isna()].drop_duplicates()
facility["year_deactivated"] = facility["FACILITY_DEACTIVATION_DATE"].dt.year
facility_yr = facility.merge(pd.DataFrame({"year": list(range(1983, 2025))}), how="cross")
facility_yr = facility_yr[~(facility_yr["year_deactivated"] < facility_yr["year"])]
intake_link = facility_yr[["PWSID", "huc12", "year"]].drop_duplicates()
pwsids_in_mine = set(intake_link.loc[intake_link["huc12"].isin(mine_hucs), "PWSID"].unique())
intake_link = intake_link[~intake_link["PWSID"].isin(pwsids_in_mine)]
intake_link = intake_link[(intake_link["year"] >= 1985) & (intake_link["year"] <= 2005)]
intake_link = intake_link[intake_link["PWSID"] != "WV3303401"]
intake_link = intake_link[intake_link["huc12"].isin(candidate_hucs)]
print(f"  Intake linkage: {len(intake_link):,} rows, {intake_link['PWSID'].nunique():,} CWSs")

huc_year = (mine_year.dropna(subset=["huc12"])
            .groupby(["huc12", "year"], as_index=False)
            .agg(n_accident_mines=("mine_id", "nunique"),
                 **{c: (c, "sum") for c in agg_spec}))
huc_year_prod = (mine_year[(mine_year["in_prod_panel"] == 1) & mine_year["huc12"].notna()]
                 .groupby(["huc12", "year"], as_index=False)
                 .agg(n_records_prodmines=("n_records", "sum"),
                      n_injuries_prodmines=("n_injuries", "sum")))
huc_year = huc_year.merge(huc_year_prod, on=["huc12", "year"], how="left")
acc_cols = [c for c in huc_year.columns if c not in ("huc12", "year")]
huc_year[acc_cols] = huc_year[acc_cols].fillna(0)


def window_sums(pairs, suffix):
    long = intake_link.merge(pairs, on="huc12", how="inner")
    long = long.groupby(["PWSID", "year", "linked_huc12"], as_index=False)["distance"].min()
    long = long.merge(huc_year.rename(columns={"huc12": "linked_huc12"}),
                      on=["linked_huc12", "year"], how="left")
    long[acc_cols] = long[acc_cols].fillna(0)
    out = long.groupby(["PWSID", "year"], as_index=False)[acc_cols].sum()
    return out.rename(columns={c: f"acc_{c}_{suffix}" for c in acc_cols})


up = window_sums(up_pairs, "upstream_k2")
dn = window_sums(dn_pairs, "downstream_k2")
k2 = intake_link[["PWSID", "year"]].drop_duplicates().merge(up, on=["PWSID", "year"], how="left") \
                                                    .merge(dn, on=["PWSID", "year"], how="left")
k2_cols = [c for c in k2.columns if c.startswith("acc_")]
k2[k2_cols] = k2[k2_cols].fillna(0)

# Universe cross-check against step_instruments (k=2 main arm, >=1 mine HUC)
si = pd.read_parquet(STEP_PQ, engine="pyarrow")
si2 = si[(si["arm"] == "main") & (si["k"] == 2) & (si["n_mine_hucs_linked"] >= 1)][["PWSID", "year"]]
cover = si2.merge(k2[["PWSID", "year"]], on=["PWSID", "year"], how="inner")
print(f"  k=2 main-arm analysis rows covered: {len(cover):,} / {len(si2):,}")

# ── 7. Schema enforcement + writes ───────────────────────────────────
rec["mine_id"] = rec["mine_id"].astype(str)
rec["year"]    = rec["year"].astype("int64")
mine_year["mine_id"] = mine_year["mine_id"].astype(str)
mine_year["year"]    = mine_year["year"].astype("int64")
for c in agg_spec:
    mine_year[c] = mine_year[c].fillna(0).astype("int64")
k2["PWSID"] = k2["PWSID"].astype(str)
k2["year"]  = k2["year"].astype("int64")
for c in k2_cols:
    k2[c] = k2[c].astype("int64")

for df, path in [(rec, OUT_RECORDS), (mine_year, OUT_MINE_YEAR), (k2, OUT_K2)]:
    print(f"\nDtypes before write ({path.name}):")
    print(df.dtypes)
    if path.exists():
        print(f"WARNING: {path} already exists — overwriting")
    df.to_parquet(str(path), index=False, engine="pyarrow")
    chk_df = pd.read_parquet(str(path), engine="pyarrow")
    print(f"Written {len(chk_df):,} rows x {chk_df.shape[1]} columns to {path}")

# ── 8. Summary ───────────────────────────────────────────────────────
print("\nNational coal totals by year (records / injuries / fatalities / water-related / serious):")
print(rec.groupby("year")[["injury", "fatality", "water_related", "serious_reportable"]].sum()
      .assign(records=rec.groupby("year").size()).to_string())
print("\nk=2 window summary (share of CWS-years with >0 / mean):")
for c in ["acc_n_records_upstream_k2", "acc_n_injuries_upstream_k2", "acc_n_fatalities_upstream_k2",
          "acc_n_water_related_upstream_k2", "acc_n_serious_reportable_upstream_k2",
          "acc_n_records_downstream_k2", "acc_n_injuries_downstream_k2",
          "acc_n_fatalities_downstream_k2", "acc_n_water_related_downstream_k2"]:
    print(f"  {c:42s} >0: {(k2[c] > 0).mean():6.1%}   mean: {k2[c].mean():8.2f}")
