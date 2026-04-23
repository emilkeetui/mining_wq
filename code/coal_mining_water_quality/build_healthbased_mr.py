# ============================================================
# Script: build_healthbased_mr.py
# Purpose: Build regular vs. confirmation MR decomposition variables (PWSID × year)
#          and all-states robustness panel for temporal sequencing test (Test 1)
# Inputs:
#   Z:/ek559/mining_wq/clean_data/cws_data/prod_vio_sulfur.parquet
#   Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.csv
#   Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_PUB_WATER_SYSTEMS.csv
# Outputs:
#   Z:/ek559/mining_wq/clean_data/cws_data/prod_vio_sulfur_hb.parquet
#   Z:/ek559/mining_wq/clean_data/cws_data/prod_vio_allstates.parquet
# Author: EK  Date: 2026-04-22
# ============================================================
#
# NOTE on IS_HEALTH_BASED_IND (confirmed 2026-04-22):
#   IS_HEALTH_BASED_IND == "N" for 100% of mining-rule (331-340) MR violations.
#   No health-based variation exists; the field cannot support the intended decomposition.
#   FALLBACK: classify by VIOLATION_CODE:
#     "03" = "Monitoring, Regular"              → mining_MR_regular_share_days
#     "04" = "Monitoring, Check/Repeat/Confirm" → mining_MR_confirm_share_days
#   Counts in full violations file: code "03" ≈99.5%, code "04" ≈0.5% of mining MR rows.
# ============================================================

import pandas as pd
import numpy as np
from pathlib import Path

PARQUET_PATH = Path("Z:/ek559/mining_wq/clean_data/cws_data/prod_vio_sulfur.parquet")
VIO_PATH     = Path("Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.csv")
PWS_PATH     = Path("Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_PUB_WATER_SYSTEMS.csv")
OUT_HB       = Path("Z:/ek559/mining_wq/clean_data/cws_data/prod_vio_sulfur_hb.parquet")
OUT_ALL      = Path("Z:/ek559/mining_wq/clean_data/cws_data/prod_vio_allstates.parquet")

MINING_RULES    = {331, 332, 333, 340}
NONMINING_RULES = {110, 111, 121, 122, 123, 140, 310, 320}
YEAR_MIN, YEAR_MAX = 1985, 2005
EXCLUDE_PWSID   = "WV3303401"


def parse_date_col(df, col):
    df[col] = df[col].replace('--->', pd.NaT)
    df[col] = pd.to_datetime(df[col], format='mixed', errors='coerce')
    return df


def year_split_shares(df, id_cols):
    """
    Expand violation records to PWSID × year level, splitting violations that
    span multiple calendar years. Returns a DataFrame with id_cols + 'year' + 'share'.
    Uses vectorized path for single-year violations, loop for multi-year.
    """
    df = df.dropna(subset=['begin_date', 'end_date']).copy()
    df = df[df['begin_date'] <= df['end_date']].copy()
    df['begin_year'] = df['begin_date'].dt.year.astype(int)
    df['end_year']   = df['end_date'].dt.year.astype(int)

    # Single-year violations: vectorized
    single = df[df['begin_year'] == df['end_year']].copy()
    single['year']  = single['begin_year']
    single['share'] = (single['end_date'] - single['begin_date']).dt.days / 365.0

    # Multi-year violations: loop (typically a small fraction)
    multi = df[df['begin_year'] != df['end_year']].copy()
    rows = []
    for _, row in multi.iterrows():
        for yr in range(int(row['begin_year']), int(row['end_year']) + 1):
            yr_start  = pd.Timestamp(f'{yr}-01-01')
            yr_end    = pd.Timestamp(f'{yr}-12-31')
            eff_start = max(row['begin_date'], yr_start)
            eff_end   = min(row['end_date'],   yr_end)
            share_val = (eff_end - eff_start).days / 365.0
            r = {c: row[c] for c in id_cols}
            r['year']  = yr
            r['share'] = share_val
            rows.append(r)

    multi_exp = (pd.DataFrame(rows, columns=id_cols + ['year', 'share'])
                 if rows else
                 pd.DataFrame(columns=id_cols + ['year', 'share']))

    result = pd.concat(
        [single[id_cols + ['year', 'share']], multi_exp],
        ignore_index=True
    )
    return result


# ── Load base parquet ────────────────────────────────────────────────────────
print("Loading prod_vio_sulfur.parquet...")
base = pd.read_parquet(PARQUET_PATH, engine='pyarrow')
base['PWSID'] = base['PWSID'].astype(str)
base['year']  = base['year'].astype('int64')

sample_pwsids = set(base['PWSID'].unique())
downstream_states = set(
    base.loc[
        (base['minehuc_downstream_of_mine'] == 1) & (base['minehuc_mine'] == 0),
        'STATE_CODE'
    ].dropna().astype(str).unique()
)
print(f"  Sample PWSID count : {len(sample_pwsids):,}")
print(f"  Downstream states  : {sorted(downstream_states)}")

# ── Load violations ──────────────────────────────────────────────────────────
print("\nLoading violations file (this may take a moment)...")
ve_cols = [
    'PWSID', 'VIOLATION_ID', 'NON_COMPL_PER_BEGIN_DATE', 'NON_COMPL_PER_END_DATE',
    'VIOLATION_CATEGORY_CODE', 'RULE_CODE', 'VIOLATION_CODE', 'IS_HEALTH_BASED_IND'
]
ve = pd.read_csv(VIO_PATH, usecols=ve_cols, low_memory=False, na_values=['', 'NA'])
ve['PWSID']    = ve['PWSID'].astype(str)
ve['rule_num'] = pd.to_numeric(ve['RULE_CODE'], errors='coerce')
print(f"  Total rows loaded: {len(ve):,}")


# ────────────────────────────────────────────────────────────────────────────
# SECTION A: Regular vs. confirmation MR decomposition
#            Merges new columns onto prod_vio_sulfur.parquet
# ────────────────────────────────────────────────────────────────────────────
print("\n=== Section A: MR decomposition for 2-step downstream sample ===")

mr_mining = ve[
    (ve['VIOLATION_CATEGORY_CODE'] == 'MR') &
    (ve['rule_num'].isin(MINING_RULES)) &
    (ve['PWSID'].isin(sample_pwsids)) &
    (ve['PWSID'] != EXCLUDE_PWSID)
].copy()

print(f"  Mining MR rows (before dedup): {len(mr_mining):,}")
print(f"  IS_HEALTH_BASED_IND == 'Y'  : {(mr_mining['IS_HEALTH_BASED_IND'] == 'Y').sum():,} "
      f"({(mr_mining['IS_HEALTH_BASED_IND'] == 'Y').mean()*100:.1f}%)")
print("  --> Using VIOLATION_CODE fallback: '03'=regular, '04'=confirmation")

# Deduplicate on VIOLATION_ID (remove duplicate enforcement-action rows per violation)
mr_mining = mr_mining.drop_duplicates(subset=['VIOLATION_ID'])
print(f"  After dedup on VIOLATION_ID: {len(mr_mining):,}")

# Parse dates
mr_mining = parse_date_col(mr_mining, 'NON_COMPL_PER_BEGIN_DATE')
mr_mining = parse_date_col(mr_mining, 'NON_COMPL_PER_END_DATE')
mr_mining = mr_mining.rename(columns={
    'NON_COMPL_PER_BEGIN_DATE': 'begin_date',
    'NON_COMPL_PER_END_DATE':   'end_date'
})

# Classify by VIOLATION_CODE
mr_mining['viol_type'] = mr_mining['VIOLATION_CODE'].map({'03': 'regular', '04': 'confirm'})
mr_mining = mr_mining[mr_mining['viol_type'].notna()].copy()
print(f"  Code '03' (regular) : {(mr_mining['viol_type'] == 'regular').sum():,}")
print(f"  Code '04' (confirm) : {(mr_mining['viol_type'] == 'confirm').sum():,}")

# Year-split shares
print("  Computing year-split shares for Section A...")
id_cols_a = ['PWSID', 'viol_type']
shares_a  = year_split_shares(mr_mining, id_cols_a)
shares_a  = shares_a[
    (shares_a['year'] >= YEAR_MIN) & (shares_a['year'] <= YEAR_MAX)
].copy()
shares_a['share'] = shares_a['share'].clip(lower=0)

# Aggregate to PWSID × year × viol_type: max share
agg_a = (
    shares_a
    .groupby(['PWSID', 'year', 'viol_type'])['share']
    .max()
    .reset_index()
    .pivot(index=['PWSID', 'year'], columns='viol_type', values='share')
    .reset_index()
)
agg_a.columns.name = None

# Ensure both columns exist even if one type had zero violations
for vtype in ['regular', 'confirm']:
    if vtype not in agg_a.columns:
        agg_a[vtype] = 0.0
    agg_a[vtype] = agg_a[vtype].fillna(0.0)

agg_a = agg_a.rename(columns={
    'regular': 'mining_MR_regular_share',
    'confirm': 'mining_MR_confirm_share'
})
agg_a['mining_MR_regular_share_days'] = agg_a['mining_MR_regular_share'] * 365
agg_a['mining_MR_confirm_share_days'] = agg_a['mining_MR_confirm_share'] * 365
agg_a['PWSID'] = agg_a['PWSID'].astype(str)
agg_a['year']  = agg_a['year'].astype('int64')
print(f"  Aggregated PWSID × year rows: {len(agg_a):,}")

# Merge onto base parquet (left join — fill zeros for non-matched PWSID-years)
hb_cols = [
    'mining_MR_regular_share', 'mining_MR_regular_share_days',
    'mining_MR_confirm_share',  'mining_MR_confirm_share_days'
]
out_hb = base.merge(agg_a[['PWSID', 'year'] + hb_cols], on=['PWSID', 'year'], how='left')
for col in hb_cols:
    out_hb[col] = out_hb[col].fillna(0.0)

out_hb['PWSID'] = out_hb['PWSID'].astype(str)
out_hb['year']  = out_hb['year'].astype('int64')
# Drop geometry column if this is a GeoDataFrame
if 'geometry' in out_hb.columns:
    out_hb = out_hb.drop(columns='geometry')

print("\nSection A output dtypes (key columns):")
print(out_hb[['PWSID', 'year'] + hb_cols].dtypes)

if OUT_HB.exists():
    print(f"\nWARNING: {OUT_HB} already exists — overwriting")
out_hb.to_parquet(OUT_HB, index=False, engine='pyarrow')
verify_a = pd.read_parquet(OUT_HB, engine='pyarrow')
print(f"Written {len(verify_a):,} rows × {verify_a.shape[1]} columns to {OUT_HB}")
print(f"  mining_MR_regular_share_days mean : {verify_a['mining_MR_regular_share_days'].mean():.4f}")
print(f"  mining_MR_confirm_share_days mean  : {verify_a['mining_MR_confirm_share_days'].mean():.4f}")
n_reg = (verify_a['mining_MR_regular_share_days'] > 0).sum()
n_con = (verify_a['mining_MR_confirm_share_days'] > 0).sum()
print(f"  PWSID-years with any regular MR   : {n_reg:,}")
print(f"  PWSID-years with any confirm MR   : {n_con:,}")


# ────────────────────────────────────────────────────────────────────────────
# SECTION B: All-states robustness panel (OLS temporal sequencing, Test 1)
#            Uses begin-year assignment with capped shares (faster than full
#            year-split; appropriate for robustness table).
# ────────────────────────────────────────────────────────────────────────────
print("\n=== Section B: All-states robustness panel ===")

# All CWSs in downstream states
pws = pd.read_csv(
    PWS_PATH,
    usecols=['PWSID', 'PWS_TYPE_CODE', 'PRIMACY_AGENCY_CODE'],
    low_memory=False, na_values=['', 'NA']
)
pws = pws[
    (pws['PWS_TYPE_CODE'] == 'CWS') &
    (pws['PRIMACY_AGENCY_CODE'].astype(str).isin(downstream_states))
].copy()
pws['PWSID'] = pws['PWSID'].astype(str)
pws = pws.drop_duplicates(subset='PWSID')
all_pwsids = set(pws['PWSID'].unique()) - {EXCLUDE_PWSID}
print(f"  CWSs in downstream states: {len(all_pwsids):,}")

# Filter violations to all-states CWSs, mining + non-mining rules, MR + MCL only
ve_b = ve[
    (ve['PWSID'].isin(all_pwsids)) &
    (ve['VIOLATION_CATEGORY_CODE'].isin(['MR', 'MCL']))
].copy()
ve_b = ve_b.drop_duplicates(subset=['VIOLATION_ID'])
print(f"  Unique violations in all-states sample: {len(ve_b):,}")

# Parse dates
ve_b = parse_date_col(ve_b, 'NON_COMPL_PER_BEGIN_DATE')
ve_b = parse_date_col(ve_b, 'NON_COMPL_PER_END_DATE')

# Assign to begin year; cap duration at 365 days (begin-year allocation)
ve_b['year'] = ve_b['NON_COMPL_PER_BEGIN_DATE'].dt.year
ve_b = ve_b.dropna(subset=['year'])
ve_b['year'] = ve_b['year'].astype(int)
ve_b = ve_b[(ve_b['year'] >= YEAR_MIN) & (ve_b['year'] <= YEAR_MAX)].copy()

ve_b['days_in_vio'] = (
    ve_b['NON_COMPL_PER_END_DATE'] - ve_b['NON_COMPL_PER_BEGIN_DATE']
).dt.days.clip(lower=0, upper=365)
ve_b['share'] = ve_b['days_in_vio'].fillna(0) / 365.0

# Contaminant group flags
ve_b['is_mining']    = ve_b['rule_num'].isin(MINING_RULES).astype(int)
ve_b['is_nonmining'] = ve_b['rule_num'].isin(NONMINING_RULES).astype(int)

# Compute 4 share columns per record
for contam, flag in [('mining', 'is_mining'), ('nonmining', 'is_nonmining')]:
    for vcat in ['MR', 'MCL']:
        col = f'{contam}_{vcat}_share'
        ve_b[col] = (
            (ve_b['VIOLATION_CATEGORY_CODE'] == vcat) & (ve_b[flag] == 1)
        ).astype(float) * ve_b['share']

agg_cols_b = [
    'mining_MR_share', 'mining_MCL_share',
    'nonmining_MR_share', 'nonmining_MCL_share'
]

# Aggregate to PWSID × year using max share within each category
panel_b_vio = (
    ve_b.groupby(['PWSID', 'year'])[agg_cols_b]
    .max()
    .reset_index()
)

# Build full PWSID × year grid (fill zeros for years with no violations)
full_grid = (
    pd.DataFrame({'PWSID': list(all_pwsids)})
    .merge(pd.DataFrame({'year': list(range(YEAR_MIN, YEAR_MAX + 1))}), how='cross')
)
full_grid['PWSID'] = full_grid['PWSID'].astype(str)
full_grid['year']  = full_grid['year'].astype(int)

panel_b = full_grid.merge(panel_b_vio, on=['PWSID', 'year'], how='left')
for col in agg_cols_b:
    panel_b[col] = panel_b[col].fillna(0.0)
    panel_b[f'{col}_days'] = panel_b[col] * 365

# Add STATE_CODE from public water systems file
state_map = (
    pws[['PWSID', 'PRIMACY_AGENCY_CODE']]
    .rename(columns={'PRIMACY_AGENCY_CODE': 'STATE_CODE'})
    .drop_duplicates(subset='PWSID')
)
panel_b = panel_b.merge(state_map, on='PWSID', how='left')

panel_b['PWSID'] = panel_b['PWSID'].astype(str)
panel_b['year']  = panel_b['year'].astype('int64')
# Drop geometry if present
if 'geometry' in panel_b.columns:
    panel_b = panel_b.drop(columns='geometry')

print(f"  Panel rows        : {len(panel_b):,}")
print(f"  Unique PWSID count: {panel_b['PWSID'].nunique():,}")
print(f"  Years covered     : {panel_b['year'].min()} – {panel_b['year'].max()}")

print("\nSection B dtypes (key columns):")
print(panel_b[['PWSID', 'year', 'STATE_CODE',
               'mining_MR_share_days', 'mining_MCL_share_days']].dtypes)

if OUT_ALL.exists():
    print(f"\nWARNING: {OUT_ALL} already exists — overwriting")
panel_b.to_parquet(OUT_ALL, index=False, engine='pyarrow')
verify_b = pd.read_parquet(OUT_ALL, engine='pyarrow')
print(f"Written {len(verify_b):,} rows × {verify_b.shape[1]} columns to {OUT_ALL}")
print(f"  mining_MR_share_days mean  : {verify_b['mining_MR_share_days'].mean():.4f}")
print(f"  mining_MCL_share_days mean : {verify_b['mining_MCL_share_days'].mean():.4f}")

print("\n=== DONE ===")
