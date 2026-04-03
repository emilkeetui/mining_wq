# ============================================================
# Script: county_mining_downstream.py
# Purpose: Classify M+ counties as mining, downstream-neighbor, or other
#          based on HUC12 flow network and MSHA mine production (1985-2005).
#          M+ = mining counties + their spatial neighbors.
#          Downstream = first county entered when tracing HUC12 flow out
#          of a mining county (immediate downstream neighbor only).
#          Mine-to-county assignment uses spatial join of mine lat/lon to
#          county polygons (not MSHA-reported FIPS codes).
#          Map of M+ counties and HUC12 boundaries saved to output/fig/.
# Inputs:
#   - clean_data/coal_mine_prod_charac.parquet
#   - Z:/ek559/sdwa_violations/WBD_HUC12_CONUS_pulled10262020/
#       WBD_HUC12_CONUS_pulled10262020.shp
#   - raw_data/county_boundaries_1990/data_EPSG_4326/co1990p020.shp
# Outputs:
#   - clean_data/county_mining_downstream.parquet
#   - output/fig/mplus_county_huc12_map.png
# Author: EK  Date: 2026-04-03
# ============================================================

import time
import warnings
warnings.filterwarnings('ignore')

import pandas as pd
import geopandas as gpd
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from collections import deque

t0 = time.time()

MINE_PARQUET = "Z:/ek559/mining_wq/clean_data/coal_mine_prod_charac.parquet"
HUC_SHP      = ("Z:/ek559/sdwa_violations/WBD_HUC12_CONUS_pulled10262020/"
                 "WBD_HUC12_CONUS_pulled10262020.shp")
COUNTY_SHP   = ("Z:/ek559/mining_wq/raw_data/county_boundaries_1990/"
                 "data_EPSG_4326/co1990p020.shp")
OUT_PARQUET  = "Z:/ek559/mining_wq/clean_data/county_mining_downstream.parquet"
OUT_FIG      = "Z:/ek559/mining_wq/output/fig/mplus_county_huc12_map.png"
PROJ         = 'EPSG:5070'  # Albers Equal Area — used for map display

def elapsed():
    return f"{time.time()-t0:.1f}s"

# ── Step 1: Load mine production data ────────────────────────────────────────
print("Step 1: Loading mine production data...", flush=True)
mines = pd.read_parquet(MINE_PARQUET)
active = mines[
    (mines['year'] >= 1985) &
    (mines['year'] <= 2005) &
    (mines['coal_metal_ind'] == 'C') &
    (mines['production_short_tons'] > 0)
].copy()

# One record per mine (for spatial join and map dots)
mines_unique = active.drop_duplicates(subset='mine_id').copy()
mines_unique = mines_unique[mines_unique['latitude'].notna() & mines_unique['longitude'].notna()]

# HUC12s containing active mines (from minegeomatch spatial assignment)
mining_hucs = set(active['huc12'].dropna().astype(str).unique())

print(f"  Active mine-year records: {len(active)}")
print(f"  Unique active mines with coordinates: {len(mines_unique)}")
print(f"  Mining HUC12s: {len(mining_hucs)}")
print(f"  [{elapsed()}]", flush=True)

# ── Step 2: Load and dissolve county shapefile ────────────────────────────────
print("\nStep 2: Loading county shapefile...", flush=True)
counties_raw = gpd.read_file(COUNTY_SHP)  # EPSG:4326
counties = (
    counties_raw
    .dissolve(by='FIPS')
    .reset_index()
    [['FIPS', 'STATE', 'COUNTY', 'geometry']]
    .rename(columns={'FIPS': 'fips5', 'STATE': 'state', 'COUNTY': 'county_name'})
)
print(f"  Counties after dissolve: {len(counties)}")
print(f"  [{elapsed()}]", flush=True)

# ── Step 3: Spatial join mine points → counties → mining_counties ─────────────
# Use mine lat/lon coordinates (not MSHA-reported FIPS) so that county
# classification and map dot placement are consistent.
print("\nStep 3: Spatially joining mine points to counties...", flush=True)
mines_gdf = gpd.GeoDataFrame(
    mines_unique[['mine_id']],
    geometry=gpd.points_from_xy(mines_unique['longitude'], mines_unique['latitude']),
    crs='EPSG:4326'   # same CRS as county shapefile — no reprojection needed
)

mine_county_join = gpd.sjoin(
    mines_gdf,
    counties[['fips5', 'geometry']],
    how='left',
    predicate='within'
)[['mine_id', 'fips5']]

mining_counties = set(mine_county_join['fips5'].dropna().unique())
n_unmatched = mine_county_join['fips5'].isna().sum()

print(f"  Mining counties (spatial): {len(mining_counties)}")
print(f"  Mines without county match: {n_unmatched} / {len(mines_gdf)}")
print(f"  [{elapsed()}]", flush=True)

# ── Step 4: M+ = mining counties + spatial neighbors ─────────────────────────
print("\nStep 4: Finding spatial neighbors of mining counties...", flush=True)
mining_gdf = counties[counties['fips5'].isin(mining_counties)][['fips5', 'geometry']].copy()

joined = gpd.sjoin(
    counties[['fips5', 'geometry']],
    mining_gdf.rename(columns={'fips5': 'mining_fips5'}),
    how='inner',
    predicate='intersects'
)
neighbor_counties = set(joined['fips5'].unique()) - mining_counties
mplus = mining_counties | neighbor_counties

print(f"  Mining: {len(mining_counties)}, Neighbors: {len(neighbor_counties)}, M+: {len(mplus)}")
print(f"  [{elapsed()}]", flush=True)

# ── Step 5: Load HUC12 shapefile ─────────────────────────────────────────────
print("\nStep 5: Loading HUC12 shapefile (1.8 GB — patience)...", flush=True)
huc_full = gpd.read_file(HUC_SHP)
huc_full['huc12'] = huc_full['huc12'].astype(str).str.strip()
huc_full['tohuc'] = huc_full['tohuc'].astype(str).str.strip()
print(f"  HUC12 polygons loaded: {len(huc_full)}")
print(f"  [{elapsed()}]", flush=True)

# Build flow lookup before dropping geometry
terminals = {'OCEAN', 'CLOSED BASIN', '0', ''}
flow = {}
for h, t in zip(huc_full['huc12'], huc_full['tohuc']):
    if t.upper().strip() not in terminals:
        flow[str(h)] = str(t)
print(f"  Flow graph edges: {len(flow)}")

# Clip HUC12 to M+ area now (used later for map) — while geometry is still loaded
print("  Clipping HUC12 to M+ boundary for map...", flush=True)
mplus_counties_gdf = counties[counties['fips5'].isin(mplus)].to_crs(PROJ)
mplus_union_proj   = mplus_counties_gdf.geometry.union_all()
huc_mplus = huc_full.to_crs(PROJ)
huc_mplus = huc_mplus[huc_mplus.geometry.intersects(mplus_union_proj)].copy()
print(f"  HUC12s in M+: {len(huc_mplus)}")

# Compute centroids in equal-area CRS, reproject back to HUC native CRS (EPSG:4269)
print("  Computing centroids (projecting to EPSG:5070)...", flush=True)
huc_native_crs = huc_full.crs
huc_attrs = huc_full[['huc12', 'areasqkm']].copy()
centroids_5070 = huc_full.to_crs('EPSG:5070').geometry.centroid
huc_centroids = gpd.GeoDataFrame(huc_attrs, geometry=centroids_5070, crs='EPSG:5070')
huc_centroids = huc_centroids.to_crs(huc_native_crs)
del huc_full  # free ~2 GB memory
print(f"  [{elapsed()}]", flush=True)

# ── Step 6: Assign each HUC12 to its primary county (centroid-in-polygon) ────
print("\nStep 6: Assigning HUC12 centroids to counties...", flush=True)
counties_4269 = counties.to_crs('EPSG:4269')
huc_county = gpd.sjoin(
    huc_centroids[['huc12', 'areasqkm', 'geometry']],
    counties_4269[['fips5', 'geometry']],
    how='left',
    predicate='within'
)[['huc12', 'areasqkm', 'fips5']].rename(columns={'fips5': 'primary_county'})

n_assigned = huc_county['primary_county'].notna().sum()
print(f"  HUC12s assigned to a county: {n_assigned} / {len(huc_county)}")
print(f"  [{elapsed()}]", flush=True)

huc_to_county = dict(zip(huc_county['huc12'], huc_county['primary_county']))

# ── Step 7: County-level flow edges ──────────────────────────────────────────
print("\nStep 7: Building county-level flow edges...", flush=True)
county_flow_edges = set()
for huc_id, dest_huc in flow.items():
    src_county = huc_to_county.get(str(huc_id))
    dst_county = huc_to_county.get(str(dest_huc))
    if src_county and dst_county and src_county != dst_county:
        county_flow_edges.add((src_county, dst_county))

county_flow_df = pd.DataFrame(list(county_flow_edges), columns=['src_county', 'dst_county'])
print(f"  County-to-county flow edges: {len(county_flow_df)}")
print(f"  [{elapsed()}]", flush=True)

# ── Step 8: Downstream neighbor counties ─────────────────────────────────────
print("\nStep 8: Identifying downstream neighbor counties...", flush=True)
downstream_edges = county_flow_df[county_flow_df['src_county'].isin(mining_counties)].copy()
all_downstream_counties = set(downstream_edges['dst_county'].unique())

downstream_of = (
    downstream_edges
    .groupby('dst_county')['src_county']
    .apply(lambda x: '|'.join(sorted(x)))
    .rename('downstream_of_mining_fips')
    .reset_index()
    .rename(columns={'dst_county': 'fips5'})
)

print(f"  Downstream neighbor counties: {len(all_downstream_counties)}")
print(f"  [{elapsed()}]", flush=True)

# ── Step 9: Area fractions via two-phase BFS ──────────────────────────────────
# frac_area_mining:     share of county HUC12 area in mining HUC12s
# frac_area_downstream: share of county HUC12 area reachable from mining HUC12s,
#   traversing through mining-county HUC12s then continuing within the first
#   downstream county until the county boundary is exited.
print("\nStep 9: Computing area fractions via two-phase BFS...", flush=True)

# Phase 1: BFS from mining HUC12s through mining-county HUC12s to find
#          the first entry HUC12 in each downstream county
entry_by_county = {}
visited_p1 = set(str(h) for h in mining_hucs)
queue = deque(str(h) for h in mining_hucs)

while queue:
    h = queue.popleft()
    next_h = flow.get(h)
    if next_h is None or next_h in visited_p1:
        continue
    visited_p1.add(next_h)

    next_county = huc_to_county.get(next_h)
    if next_county is None:
        continue

    if next_county in mining_counties:
        queue.append(next_h)
    elif next_county in all_downstream_counties:
        entry_by_county.setdefault(next_county, set()).add(next_h)

# Phase 2: From each entry HUC12, BFS within the downstream county
downstream_reachable_hucs = set()
for d_county, entry_hucs in entry_by_county.items():
    inner_visited = set(entry_hucs)
    inner_queue = deque(entry_hucs)
    while inner_queue:
        h = inner_queue.popleft()
        downstream_reachable_hucs.add(h)
        next_h = flow.get(h)
        if next_h is None or next_h in inner_visited:
            continue
        inner_visited.add(next_h)
        if huc_to_county.get(next_h) == d_county:
            inner_queue.append(next_h)

print(f"  Downstream-reachable HUC12s (Phase 1+2): {len(downstream_reachable_hucs)}")

county_total_area = (
    huc_county[huc_county['primary_county'].notna()]
    .groupby('primary_county')['areasqkm'].sum()
    .rename('total_huc_area_sqkm')
)
mining_huc_area = (
    huc_county[huc_county['huc12'].isin(mining_hucs) & huc_county['primary_county'].notna()]
    .groupby('primary_county')['areasqkm'].sum()
    .rename('mining_huc_area_sqkm')
)
downstream_huc_area = (
    huc_county[huc_county['huc12'].isin(downstream_reachable_hucs) & huc_county['primary_county'].notna()]
    .groupby('primary_county')['areasqkm'].sum()
    .rename('downstream_huc_area_sqkm')
)

area_df = pd.concat([county_total_area, mining_huc_area, downstream_huc_area], axis=1).fillna(0)
area_df['frac_area_mining']     = (area_df['mining_huc_area_sqkm']
                                    / area_df['total_huc_area_sqkm'].replace(0, np.nan))
area_df['frac_area_downstream'] = (area_df['downstream_huc_area_sqkm']
                                    / area_df['total_huc_area_sqkm'].replace(0, np.nan))
area_df = area_df.reset_index().rename(columns={'primary_county': 'fips5'})
print(f"  [{elapsed()}]", flush=True)

# ── Step 10: Assemble and save ────────────────────────────────────────────────
print("\nStep 10: Assembling final dataset...", flush=True)
result = counties[counties['fips5'].isin(mplus)].copy()

result = result.merge(
    area_df[['fips5', 'frac_area_mining', 'frac_area_downstream',
             'mining_huc_area_sqkm', 'downstream_huc_area_sqkm', 'total_huc_area_sqkm']],
    on='fips5', how='left'
)
result['frac_area_mining']     = result['frac_area_mining'].fillna(0)
result['frac_area_downstream'] = result['frac_area_downstream'].fillna(0)
result = result.merge(downstream_of, on='fips5', how='left')

result['is_mining_county']       = result['fips5'].isin(mining_counties)
result['is_downstream_neighbor'] = result['fips5'].isin(all_downstream_counties)
result['is_strictly_downstream'] = result['is_downstream_neighbor'] & ~result['is_mining_county']
result['ambiguous']              = result['is_downstream_neighbor'] & result['is_mining_county']

print(f"\n  M+ counties:          {len(result)}")
print(f"  Mining counties:      {result['is_mining_county'].sum()}")
print(f"  Downstream neighbors: {result['is_downstream_neighbor'].sum()}")
print(f"  Strictly downstream:  {result['is_strictly_downstream'].sum()}")
print(f"  Ambiguous:            {result['ambiguous'].sum()}")

result.to_parquet(OUT_PARQUET, index=False)
print(f"\n  Saved: {OUT_PARQUET}")
print(f"  [{elapsed()}]", flush=True)

# ── Step 11: Map ──────────────────────────────────────────────────────────────
print("\nStep 11: Producing map...", flush=True)

# Assign display category
def classify(row):
    if row['is_mining_county'] and row['is_downstream_neighbor']:
        return 'Ambiguous (mining + downstream)'
    elif row['is_mining_county']:
        return 'Mining county'
    elif row['is_strictly_downstream']:
        return 'Strictly downstream'
    else:
        return 'M+ neighbor (neither)'

result['category'] = result.apply(classify, axis=1)
result_proj = result.to_crs(PROJ)

# CONUS background counties (exclude AK, HI)
counties_conus = counties[~counties['state'].isin(['AK', 'HI'])].to_crs(PROJ)

# Mine points (spatially joined — dots are consistent with county classification)
mines_proj = mines_gdf.to_crs(PROJ)

cat_colors = {
    'Mining county':                    '#d62728',
    'Strictly downstream':              '#1f77b4',
    'Ambiguous (mining + downstream)':  '#9467bd',
    'M+ neighbor (neither)':            '#aec7e8',
}

fig, ax = plt.subplots(1, 1, figsize=(18, 11))

# Gray background
counties_conus.plot(ax=ax, color='#f0f0f0', edgecolor='#cccccc', linewidth=0.2)

# M+ counties by category (neighbors first, mining on top)
for cat in ['M+ neighbor (neither)', 'Strictly downstream',
            'Ambiguous (mining + downstream)', 'Mining county']:
    subset = result_proj[result_proj['category'] == cat]
    if len(subset):
        subset.plot(ax=ax, color=cat_colors[cat], edgecolor='white',
                    linewidth=0.4, alpha=0.85, zorder=2)

# M+ county borders
result_proj.boundary.plot(ax=ax, color='#555555', linewidth=0.5, zorder=3)

# HUC12 boundaries within M+
huc_mplus.boundary.plot(ax=ax, color='#333333', linewidth=0.25, alpha=0.45, zorder=4)

# Mine dots — same coordinates used for county classification
mines_proj.plot(ax=ax, color='black', markersize=3, marker='o', zorder=5)

# Legend
n_mine      = result['is_mining_county'].sum()
n_dwnstrm   = result['is_strictly_downstream'].sum()
n_ambig     = result['ambiguous'].sum()
n_nbr       = (~result['is_mining_county'] & ~result['is_downstream_neighbor']).sum()

legend_handles = [
    mpatches.Patch(color=cat_colors['Mining county'],
                   label=f'Mining county (n={n_mine})'),
    mpatches.Patch(color=cat_colors['Strictly downstream'],
                   label=f'Strictly downstream (n={n_dwnstrm})'),
    mpatches.Patch(color=cat_colors['Ambiguous (mining + downstream)'],
                   label=f'Ambiguous — mining + downstream (n={n_ambig})'),
    mpatches.Patch(color=cat_colors['M+ neighbor (neither)'],
                   label=f'M+ neighbor only (n={n_nbr})'),
    plt.Line2D([0], [0], color='#333333', linewidth=0.6, alpha=0.6,
               label='HUC12 boundaries'),
    plt.Line2D([0], [0], marker='o', color='w', markerfacecolor='black',
               markersize=4, label=f'Active coal mine 1985–2005 (n={len(mines_proj)})'),
]
ax.legend(handles=legend_handles, loc='lower left', fontsize=9,
          framealpha=0.9, edgecolor='#999999')

ax.set_title('M+ Counties: Coal Mining, Downstream Neighbors, and HUC12 Watersheds\n'
             '(MSHA active coal mines 1985–2005; M+ = mining counties + spatial neighbors;\n'
             'mine-to-county assignment via spatial join of mine coordinates)',
             fontsize=11, pad=12)
ax.set_axis_off()

plt.tight_layout()
plt.savefig(OUT_FIG, dpi=200, bbox_inches='tight')
plt.close()

print(f"  Saved: {OUT_FIG}")
print(f"\nTotal elapsed: {elapsed()}")
