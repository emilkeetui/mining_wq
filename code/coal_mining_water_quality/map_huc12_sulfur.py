# ============================================================
# Script: map_huc12_sulfur.py
# Purpose: Map HUC12 watersheds containing coal mines, colored by
#          mean coal sulfur content (% of coal weight)
# Inputs:  clean_data/huc_coal_charac_geom_match.parquet
#          Z:/ek559/sdwa_violations/WBD_HUC12_CONUS_pulled10262020/...shp
#          Z:/ek559/nys_algal_bloom/.../contiguous_states.shp
# Outputs: output/fig/map_huc12_sulfur.png
# Author: EK  Date: 2026-09-16
# ============================================================

import pandas as pd
import geopandas as gpd
import matplotlib.pyplot as plt
from matplotlib.ticker import FormatStrFormatter
from pathlib import Path
from shapely.geometry import box

PROJECT_ROOT = Path("Z:/ek559/mining_wq")
HUC_SHP      = Path("Z:/ek559/sdwa_violations/WBD_HUC12_CONUS_pulled10262020/WBD_HUC12_CONUS_pulled10262020.shp")
STATES_SHP   = Path("Z:/ek559/nys_algal_bloom/NYS algal bloom/census_data/contiguous_states.shp")
OUT_PATH     = PROJECT_ROOT / "output/fig/map_huc12_sulfur.png"

if OUT_PATH.exists():
    print(f"WARNING: {OUT_PATH} already exists — overwriting")

# ── 1. Mean coal sulfur content by mine HUC12 ────────────────────────────────
huc_prod = pd.read_parquet(
    PROJECT_ROOT / "clean_data/huc_coal_charac_geom_match.parquet", engine="pyarrow"
)
mine_huc = huc_prod.loc[huc_prod["minehuc"] == "mine", ["huc12", "sulfur_colocated"]].copy()
mine_huc["huc12"] = mine_huc["huc12"].astype(str).str.strip()

sulfur_by_huc = (
    mine_huc.groupby("huc12", as_index=False)["sulfur_colocated"]
    .mean()
    .rename(columns={"sulfur_colocated": "mean_sulfur"})
)
print(f"Mine HUC12s with sulfur data: {len(sulfur_by_huc):,}")
print(sulfur_by_huc["mean_sulfur"].describe())

# ── 2. Load HUC12 geometries (Appalachian coal-region bbox) ─────────────────
COAL_BBOX = (-130, 24, -65, 50)
print("Loading HUC12 geometries (Appalachian bbox)...")
huc_geom = gpd.read_file(str(HUC_SHP), bbox=COAL_BBOX)
huc_geom["huc12"] = huc_geom["huc12"].astype(str).str.strip()

mine_geom = huc_geom.merge(sulfur_by_huc, on="huc12", how="inner")
print(f"Mine HUC12 geometries with sulfur: {len(mine_geom):,}")

# ── 3. Reproject to Albers Equal Area, clip extent to mapped HUC12s ─────────
CRS = "EPSG:5070"
print(f"Pre-reprojection CRS: {mine_geom.crs}")
mine_geom = mine_geom.to_crs(CRS)
states    = gpd.read_file(str(STATES_SHP)).to_crs(CRS)
print(f"Post-reprojection CRS: {mine_geom.crs}, states CRS: {states.crs}")
assert mine_geom.crs == states.crs, "CRS mismatch — reproject before joining"

bounds = mine_geom.total_bounds  # minx, miny, maxx, maxy
extent = box(bounds[0], bounds[1], bounds[2], bounds[3])
states_clip = states.clip(extent)

# ── 4. Plot ───────────────────────────────────────────────────────────────────
# Sulfur is heavily right-skewed (p75 ~= 2.3, max = 6.8 from a single outlier
# HUC12), so a linear 0-max color scale crushes almost all watersheds into the
# pale end of the ramp. Cap the scale at the 95th percentile and route the
# remaining tail into the colorbar's "extend" arrow so the bulk of the
# variation is visible.
VMIN = 0.0
VMAX = round(mine_geom["mean_sulfur"].quantile(0.95), 1)
n_clipped = (mine_geom["mean_sulfur"] > VMAX).sum()
print(f"Color scale: {VMIN:.1f}-{VMAX:.1f}% sulfur ({n_clipped} HUC12s above cap, shown via colorbar arrow)")

fig, ax = plt.subplots(figsize=(10, 7))

states_clip.plot(ax=ax, color="#f5f5f5", edgecolor="#bbbbbb", linewidth=0.4, zorder=1)

mine_geom.plot(
    ax=ax, column="mean_sulfur", cmap="YlOrRd", edgecolor="#4d4d4d",
    linewidth=0.2, vmin=VMIN, vmax=VMAX, zorder=2,
    legend=True,
    legend_kwds={
        "label": "Mean Sulfur (% of Coal Weight)",
        "shrink": 0.6,
        "format": FormatStrFormatter("%.1f"),
        "extend": "max",
    },
)

states_clip.boundary.plot(ax=ax, color="#666666", linewidth=0.5, zorder=3)

ax.set_xlim(bounds[0], bounds[2])
ax.set_ylim(bounds[1], bounds[3])
ax.axis("off")
ax.set_title("HUC12 watersheds containing coal mines, by mean coal sulfur content", fontsize=16)

plt.tight_layout()
plt.savefig(str(OUT_PATH), dpi=200, bbox_inches="tight")
print(f"Saved: {OUT_PATH}")
