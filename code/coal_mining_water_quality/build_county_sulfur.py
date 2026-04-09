# ============================================================
# Script: build_county_sulfur.py
# Purpose: Assign county-level average sulfur percent from USGS
#          coal quality boreholes using a 50 km buffer spatial join.
# Inputs:  raw_data/coal_qual/CQ2025101314323_sampledetails.CSV
#          raw_data/coal_qual/CQ20251013152532_proximateultimate.CSV
#          clean_data/county_mining_downstream.parquet
# Outputs: clean_data/county_sulfur.parquet
# Author: EK  Date: 2026-04-08
# ============================================================

import pandas as pd
import geopandas as gpd
import numpy as np
from pathlib import Path

RAW_DIR   = Path("Z:/ek559/mining_wq/raw_data/coal_qual")
CLEAN_DIR = Path("Z:/ek559/mining_wq/clean_data")
PROJ      = "EPSG:5070"   # Albers Equal Area CONUS — metres, suitable for buffering

# ── Step 1: Load and join borehole files ──────────────────────────────────────
print("Step 1: Loading borehole data...", flush=True)

details = pd.read_csv(RAW_DIR / "CQ2025101314323_sampledetails.CSV",
                      usecols=["Sample ID", "Latitude", "Longitude"])

proximate = pd.read_csv(RAW_DIR / "CQ20251013152532_proximateultimate.CSV",
                        usecols=["Sample ID", " Sulfur"])
proximate = proximate.rename(columns={" Sulfur": "sulfur_pct"})

boreholes = details.merge(proximate, on="Sample ID", how="inner")
boreholes["sulfur_pct"] = pd.to_numeric(boreholes["sulfur_pct"], errors="coerce")
boreholes = boreholes.dropna(subset=["Latitude", "Longitude", "sulfur_pct"])
boreholes = boreholes.rename(columns={"Sample ID": "sample_id"})

print(f"  Boreholes with lat/lon/sulfur: {len(boreholes):,}")
print(f"  Sulfur range: {boreholes['sulfur_pct'].min():.2f}% – {boreholes['sulfur_pct'].max():.2f}%")

# ── Step 2: Build buffered borehole GeoDataFrame ──────────────────────────────
print("\nStep 2: Building 50 km borehole buffers...", flush=True)

boreholes_gdf = gpd.GeoDataFrame(
    boreholes[["sample_id", "sulfur_pct"]],
    geometry=gpd.points_from_xy(boreholes["Longitude"], boreholes["Latitude"]),
    crs="EPSG:4326"
).to_crs(PROJ)

boreholes_gdf["geometry"] = boreholes_gdf.geometry.buffer(50_000)   # 50 km in metres
print(f"  Buffers created: {len(boreholes_gdf):,}")

# ── Step 3: Load county boundaries ───────────────────────────────────────────
print("\nStep 3: Loading county boundaries...", flush=True)

counties = pd.read_parquet(CLEAN_DIR / "county_mining_downstream.parquet")
counties_gdf = gpd.GeoDataFrame(
    counties[["fips5", "state", "county_name"]],
    geometry=gpd.GeoSeries.from_wkb(
        counties["geometry"].apply(lambda g: g.wkb if hasattr(g, "wkb") else g),
        crs="EPSG:4326"
    ) if counties["geometry"].dtype == object else counties["geometry"],
    crs="EPSG:4326"
).to_crs(PROJ)

print(f"  Counties loaded: {len(counties_gdf)}")

# ── Step 4: Spatial join — borehole buffers → counties ───────────────────────
print("\nStep 4: Spatial join (50 km buffers to county polygons)...", flush=True)

joined = gpd.sjoin(
    boreholes_gdf[["sample_id", "sulfur_pct", "geometry"]],
    counties_gdf[["fips5", "geometry"]],
    how="inner",
    predicate="intersects"
)[["sample_id", "sulfur_pct", "fips5"]]

print(f"  Borehole-county pairs: {len(joined):,}")
print(f"  Unique counties matched: {joined['fips5'].nunique()}")
print(f"  Unique boreholes matched: {joined['sample_id'].nunique()}")

# ── Step 5: Average sulfur by county ─────────────────────────────────────────
print("\nStep 5: Computing county-average sulfur...", flush=True)

county_sulfur = (
    joined.groupby("fips5")
    .agg(sulfur_county_pct=("sulfur_pct", "mean"),
         n_boreholes=("sample_id", "count"))
    .reset_index()
)

# ── Step 6: Left-join to full county list ────────────────────────────────────
result = counties[["fips5", "state", "county_name"]].merge(
    county_sulfur, on="fips5", how="left"
)

n_matched   = result["sulfur_county_pct"].notna().sum()
n_unmatched = result["sulfur_county_pct"].isna().sum()
print(f"  Counties with sulfur data: {n_matched} of {len(result)}")
print(f"  Counties with no borehole within 50 km: {n_unmatched}")
print(f"  Sulfur range (matched): "
      f"{result['sulfur_county_pct'].min():.3f}% – {result['sulfur_county_pct'].max():.3f}%")

# ── Step 7: Save ──────────────────────────────────────────────────────────────
out = CLEAN_DIR / "county_sulfur.parquet"
result.to_parquet(out, index=False)
print(f"\nSaved: {out}")
print(result[["fips5", "state", "county_name", "sulfur_county_pct", "n_boreholes"]].head(15).to_string())
