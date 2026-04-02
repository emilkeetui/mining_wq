# creating raster based on usgs coal qual sample data
# Based on Douglas, Stratford, and Seth Wiggins. 
# Effects of Acid Rain Regulations on Production of Eastern Coals of Varying Sulfur Content. No. 15-38. 
# 2015. They do: "Sulfur (percent by weight) and heat content (mmBtu/ton) data come from 
# the USGS Coal Quality database, which contains over 13,000 samples of coal and associated rocks 
# (Bragg et al, 1998). Using ArcGIS Kriging, we interpolated a 
# raster from these borehole points. ArcGIS’s ‘Extract Values to Points’ tool produces county-level 
# estimates of sulfur content, from which we calculated figures for sulfur content in units of pounds per 
# million Btu.

import rasterio
from rasterio.transform import from_origin
import geopandas as gpd
import pandas as pd
import matplotlib.pyplot as plt
from skgstat import Variogram
import gstools as gs
from scipy.spatial import distance_matrix
import numpy as np

sample = pd.read_csv("Z:/ek559/mining_wq/coal_qual/CQ2025101314323_sampledetails.CSV",
                     low_memory=False,
                     on_bad_lines="skip")
sample.columns = sample.columns.str.replace(' ', '', regex=False).str.lower()

ult = pd.read_csv("Z:/ek559/mining_wq/coal_qual/CQ20251013152532_proximateultimate.CSV",
                  low_memory=False,
                  on_bad_lines="skip")
ult.columns = ult.columns.str.replace(' ', '', regex=False).str.lower()
ult = ult[~ult['sulfur'].astype(str).str.contains('Maine', na=False)]
ult = ult[~ult['btu'].astype(str).str.contains('Michigan', na=False)]

samplelocation = pd.merge(ult, sample, on='sampleid')
samplelocation = samplelocation[~samplelocation['sulfur'].isna()]

# Step 2: Prepare coordinates and values
coords = samplelocation[['longitude', 'latitude']].values
values = samplelocation['sulfur'].values
values = values.astype(float)

# Step 3: Fit variogram model using Scikit-GStat
V = Variogram(coords, values, model='spherical', normalize=False)

# Step 4: Convert to GSTools model with shorter range
short_range = 0.02  # degrees, adjust as needed
model = gs.Spherical(dim=2, var=V.parameters[0], len_scale=short_range)

# Step 5: Create expanded grid for interpolation
margin_x = 0.1 * (coords[:, 0].max() - coords[:, 0].min())
margin_y = 0.1 * (coords[:, 1].max() - coords[:, 1].min())
grid_lon = np.linspace(coords[:, 0].min() - margin_x, coords[:, 0].max() + margin_x, 500)
grid_lat = np.linspace(coords[:, 1].min() - margin_y, coords[:, 1].max() + margin_y, 500)
grid_lon, grid_lat = np.meshgrid(grid_lon, grid_lat)

# Step 6: Perform Ordinary Kriging
OK = gs.krige.Ordinary(model, cond_pos=coords.T, cond_val=values)
field, variance = OK((grid_lon.ravel(), grid_lat.ravel()))
field = field.reshape(grid_lon.shape)
variance = variance.reshape(grid_lon.shape)

# Step 7: Mask field beyond a distance threshold
grid_points = np.column_stack((grid_lon.ravel(), grid_lat.ravel()))
dists = distance_matrix(grid_points, coords)
min_dist = dists.min(axis=1).reshape(grid_lon.shape)
distance_threshold = 0.05  # degrees
field_masked = np.where(min_dist > distance_threshold, 0, field)

# Load contiguous US shapefile
contiguous_states = gpd.read_file("Z:/ek559/nys_algal_bloom/NYS algal bloom/census_data/contiguous_states.shp")

contiguous_states = contiguous_states.to_crs(epsg=4326)

# Ensure CRS matches (optional but recommended)
# If your grid and borehole data are in a known CRS, reproject the shapefile to match
# Example: contiguous_states = contiguous_states.to_crs(epsg=4326)

# Step 8: Plot the masked field and borehole points
fig, ax = plt.subplots(figsize=(10, 8))

# Plot the base map of contiguous US
contiguous_states.plot(ax=ax, color='lightgray', edgecolor='black')

# Plot the raster field
contour = ax.contourf(grid_lon, grid_lat, field_masked, cmap='viridis', levels=100)
cbar = plt.colorbar(contour, ax=ax, label='Sulfur concentration')

# Plot borehole points
scatter = ax.scatter(coords[:, 0], coords[:, 1], c=values, cmap='viridis',
                     edgecolor='black', s=100, label='Borehole samples')

# Optional: Add sample IDs
for i, row in samplelocation.iterrows():
    ax.text(row['lon'], row['lat'], str(row['sample_id']), fontsize=9,
            ha='center', va='center', color='white', weight='bold')

# Final plot adjustments
ax.set_title('Ordinary Kriging Interpolation of Sulfur (Masked Beyond Threshold)')
ax.set_xlabel('Longitude')
ax.set_ylabel('Latitude')
ax.legend()
ax.grid(True)
plt.tight_layout()
plt.show()

# Define raster metadata
nrows, ncols = field_masked.shape
xres = (grid_lon.max() - grid_lon.min()) / (ncols - 1)
yres = (grid_lat.max() - grid_lat.min()) / (nrows - 1)
x_min = grid_lon.min()
y_max = grid_lat.max()

# Create affine transform
transform = from_origin(x_min, y_max, xres, yres)

# Save raster to specified path
with rasterio.open(
    r"Z:/ek559/mining_wq/coal_qual/sulfur_intrerpolation.tif",
    "w",
    driver="GTiff",
    height=nrows,
    width=ncols,
    count=1,
    dtype=field_masked.dtype,
    crs="EPSG:4326",
    transform=transform,
) as dst:
    dst.write(field_masked, 1)

# read the raster 

# Open the GeoTIFF file
with rasterio.open(r"C:/desktop/sulfur_intrerpolation.tif") as src:
    raster_data = src.read(1)  # Read the first band
    transform = src.transform
    crs = src.crs

# Display basic info
print("CRS:", crs)
print("Transform:", transform)
# each pixel is 0.63 degrees
# The raster starts at Longitude 127.92°W.
# The raster starts at Latitude 50.93°N.
print("Shape:", raster_data.shape)

# Plot the raster
plt.figure(figsize=(10, 8))
plt.imshow(raster_data, cmap='viridis', extent=(
    transform[2],
    transform[2] + transform[0] * raster_data.shape[1],
    transform[5] + transform[4] * raster_data.shape[0],
    transform[5]
))
plt.colorbar(label='Sulfur concentration')
plt.title("Sulfur Interpolation Raster")
plt.xlabel("Longitude")
plt.ylabel("Latitude")
plt.grid(True)
plt.tight_layout()
plt.show()
