# ============================================================
# Script: map_huc12_main_sample.py
# Purpose: Map mine HUC12s by whether they are upstream of CWSs
#          in the main 2SLS sample (downstream CWSs only)
# Inputs:  clean_data/cws_data/prod_vio_sulfur.parquet
#          clean_data/cws_data/sdwa_facilities.csv
#          clean_data/huc_coal_charac_geom_match.parquet
#          Z:/ek559/sdwa_violations/WBD_HUC12_CONUS_pulled10262020/...shp
#          Z:/ek559/nys_algal_bloom/.../contiguous_states.shp
# Outputs: output/fig/map_huc12_main_sample.png
# Author: EK  Date: 2026-04-19
# ============================================================

import pandas as pd
import geopandas as gpd
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import pyogrio
from pathlib import Path
from collections import defaultdict, deque
from shapely.geometry import box

PROJECT_ROOT = Path("Z:/ek559/mining_wq")
HUC_SHP     = Path("Z:/ek559/sdwa_violations/WBD_HUC12_CONUS_pulled10262020/WBD_HUC12_CONUS_pulled10262020.shp")
STATES_SHP  = Path("Z:/ek559/nys_algal_bloom/NYS algal bloom/census_data/contiguous_states.shp")
OUT_PATH    = PROJECT_ROOT / "output/fig/map_huc12_main_sample.png"

# ── 1. Main 2SLS sample CWS IDs ──────────────────────────────────────────────
prod_vio = pd.read_parquet(
    PROJECT_ROOT / "clean_data/cws_data/prod_vio_sulfur.parquet", engine="pyarrow"
)
main_pws = set(
    prod_vio.loc[
        (prod_vio["minehuc_downstream_of_mine"] == 1) & (prod_vio["minehuc_mine"] == 0),
        "PWSID"
    ].unique()
)
print(f"Main 2SLS sample: {len(main_pws):,} CWSs")

# ── 2. HUC12s for main-sample CWSs ───────────────────────────────────────────
facilities = pd.read_csv(
    PROJECT_ROOT / "clean_data/cws_data/sdwa_facilities.csv",
    dtype={"huc12": str, "PWSID": str}
)
main_cws_huc12s = set(
    facilities.loc[facilities["PWSID"].isin(main_pws), "huc12"].dropna().unique()
)
print(f"Main-sample CWS HUC12s: {len(main_cws_huc12s):,}")

# ── 3. Mine HUC12s ────────────────────────────────────────────────────────────
huc_prod = pd.read_parquet(
    PROJECT_ROOT / "clean_data/huc_coal_charac_geom_match.parquet", engine="pyarrow"
)
mine_huc12s = set(huc_prod.loc[huc_prod["minehuc"] == "mine", "huc12"].unique())
print(f"Mine HUC12s: {len(mine_huc12s):,}")

# ── 4. Load full flow network (attributes only — fast via pyogrio) ────────────
print("Loading HUC12 flow network...")
flow_df = pyogrio.read_dataframe(str(HUC_SHP), columns=["huc12", "tohuc"], skip_geometry=True)
flow_df["huc12"]  = flow_df["huc12"].astype(str).str.strip()
flow_df["tohuc"]  = flow_df["tohuc"].astype(str).str.strip()
print(f"Flow network: {len(flow_df):,} HUC12s")

# Build reverse adjacency: tohuc → set of huc12s that drain into it
upstream_of = defaultdict(set)
for huc, to in zip(flow_df["huc12"], flow_df["tohuc"]):
    if to and to not in ("", "nan", "0"):
        upstream_of[to].add(huc)

# ── 5. BFS upstream from main-sample CWS HUC12s → classify mine HUC12s ───────
green_mines = set()
visited     = set(main_cws_huc12s)
queue       = deque(main_cws_huc12s)

while queue:
    current = queue.popleft()
    for up in upstream_of.get(current, ()):
        if up in mine_huc12s:
            green_mines.add(up)
        if up not in visited:
            visited.add(up)
            queue.append(up)

grey_mines = mine_huc12s - green_mines
print(f"  Green (upstream of main-sample CWS): {len(green_mines):,}")
print(f"  Grey  (no downstream main-sample CWS): {len(grey_mines):,}")

# ── 6. Load HUC12 geometries for mine HUC12s (bbox = Appalachian coal region) ─
# WGS84 bbox covering CONUS
COAL_BBOX = (-130, 24, -65, 50)
print("Loading HUC12 geometries (Appalachian bbox)...")
huc_geom = gpd.read_file(str(HUC_SHP), bbox=COAL_BBOX)
huc_geom["huc12"] = huc_geom["huc12"].astype(str).str.strip()

# Keep only mine HUC12s
mine_geom = huc_geom[huc_geom["huc12"].isin(mine_huc12s)].copy()
mine_geom["category"] = mine_geom["huc12"].map(
    lambda h: "green" if h in green_mines else "grey"
)
print(f"Mine HUC12 geometries loaded: {len(mine_geom):,}")

# ── 7. Reproject to Albers Equal Area ────────────────────────────────────────
CRS = "EPSG:5070"
mine_geom = mine_geom.to_crs(CRS)
states    = gpd.read_file(str(STATES_SHP)).to_crs(CRS)

# Clip extent to mine HUC12 bounding box + buffer
bounds = mine_geom.total_bounds          # minx, miny, maxx, maxy
buf    = 150_000                          # 150 km
extent = box(bounds[0]-buf, bounds[1]-buf, bounds[2]+buf, bounds[3]+buf)
states_clip = states.clip(extent)

# ── 8. Plot ───────────────────────────────────────────────────────────────────
fig, ax = plt.subplots(figsize=(10, 7))

states_clip.plot(ax=ax, color="#f5f5f5", edgecolor="#bbbbbb", linewidth=0.4, zorder=1)

mine_geom[mine_geom["category"] == "grey"].plot(
    ax=ax, color="#888888", edgecolor="none", alpha=0.85, zorder=2
)
mine_geom[mine_geom["category"] == "green"].plot(
    ax=ax, color="#2ca02c", edgecolor="none", alpha=0.85, zorder=3
)

states_clip.boundary.plot(ax=ax, color="#666666", linewidth=0.5, zorder=4)

ax.set_xlim(bounds[0]-buf, bounds[2]+buf)
ax.set_ylim(bounds[1]-buf, bounds[3]+buf)
ax.axis("off")

legend_handles = [
    mpatches.Patch(facecolor="#2ca02c", label="Mine HUC12 — upstream of main-sample CWS"),
    mpatches.Patch(facecolor="#888888", label="Mine HUC12 — no downstream main-sample CWS"),
    mpatches.Patch(facecolor="#f5f5f5", edgecolor="#bbbbbb", label="No mining"),
]
ax.legend(handles=legend_handles, loc="lower right", frameon=True, fontsize=9,
          framealpha=0.9, edgecolor="#cccccc")

plt.tight_layout()
plt.savefig(str(OUT_PATH), dpi=200, bbox_inches="tight")
print(f"Saved: {OUT_PATH}")
