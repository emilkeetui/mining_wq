import pandas as pd
import geopandas as gpd
import numpy as np
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
import pygris
from matplotlib.patches import Patch

# mapping the changes in coal production at the huc-intake level 
# between 1983 and 1995, 1983 and 2000, 1995 and 2000
huclevel = pd.read_csv("Z:/ek559/mining_wq/clean_data/coal_huc_prod.csv",
                       dtype={'huc12': str})
# match to only cws intake hucs
intake = pd.read_excel("Z:/ek559/water_instrument/cws_intake_hucs/PWS_Loctations_HUC12_A_I_2022Q2.xlsx",
                       dtype={'HUC_12': str})
intake = intake.rename(columns = {'HUC_12':'huc12'})
intake = pd.DataFrame(intake['huc12'])
intake = intake.drop_duplicates(subset='huc12')
huclevel = huclevel.merge(intake, how ='inner', on = 'huc12')

huclevel['prod1983'] = np.where(huclevel['year'] == 1983,
                                huclevel['production_short_tons_coal'],
                                np.nan)
huclevel['minecount1983'] = np.where(huclevel['year'] == 1983,
                                huclevel['num_coal_mines'],
                                np.nan)
huclevel['prod1995'] = np.where(huclevel['year'] == 1995,
                                huclevel['production_short_tons_coal'],
                                np.nan)
huclevel['minecount1995'] = np.where(huclevel['year'] == 1995,
                                huclevel['num_coal_mines'],
                                np.nan)
huclevel['prod2000'] = np.where(huclevel['year'] == 2000,
                                huclevel['production_short_tons_coal'],
                                np.nan)
huclevel['minecount2000'] = np.where(huclevel['year'] == 2000,
                                huclevel['num_coal_mines'],
                                np.nan)

huclevel = huclevel.groupby(['huc12']).agg(
    prod1983=('prod1983', 'max'),
    minecount1983 =('minecount1983', 'max'),
    prod1995=('prod1995', 'max'),
    minecount1995 =('minecount1995', 'max'),
    prod2000=('prod2000', 'max'),
    minecount2000 =('minecount2000', 'max')
).reset_index()

huclevel['prodtondiff1983_1995'] = huclevel['prod1995'] - huclevel['prod1983']
huclevel['prodtondiff1983_2000'] = huclevel['prod2000'] - huclevel['prod1983']
huclevel['prodtondiff1995_2000'] = huclevel['prod2000'] - huclevel['prod1995']

huclevel = huclevel.fillna(0)

# huc shapefile
huc = gpd.read_file(r"Z:\ek559\sdwa_violations\WBD_HUC12_CONUS_pulled10262020\WBD_HUC12_CONUS_pulled10262020.shp")
huc = huc.rename(columns={'name': 'name_huc'})
huc = huc.drop(['objectid', 'tnmid', 'loaddate',
                'areaacres', 'areasqkm', 'states',
                'hutype', 'humod', 'tohuc', 'noncontrib',
                'noncontr_1'], axis = 1)
huclevel = huc.merge(huclevel, how='right', on='huc12')

# Reproject HUC-level data to Web Mercator
huclevel = huclevel.to_crs(epsg=3857)

# Load and reproject contiguous US states
all_states = pygris.states()
contiguous_states = all_states[~all_states['STUSPS'].isin(['AK', 'HI', 'PR', 'VI', 'GU', 'MP', 'AS'])]
contiguous_states = contiguous_states.to_crs(epsg=3857)

# 1983 and 1995
# Create the plot
fig, ax = plt.subplots(1, 1, figsize=(12, 8))
contiguous_states.plot(ax=ax, color='grey', edgecolor='black', linewidth=0.5)
huclevel[huclevel['prodtondiff1983_1995'] < 0].plot(
    ax=ax,
    column='prodtondiff1983_1995',
    cmap='Reds',
    edgecolor='Red',
    linewidth=0.1,
)
huclevel[huclevel['prodtondiff1983_1995'] >= 0].plot(
    ax=ax,
    column='prodtondiff1983_1995',
    cmap='Blues',
    edgecolor='blue',
    linewidth=0.1,
)
legend_elements = [
    Patch(facecolor='blue', edgecolor='blue', label='Increase in production'),
    Patch(facecolor='red', edgecolor='red', label='Decrease in production')
]
ax.legend(handles=legend_elements)
ax.set_title("Net Changes in HUC12 level Coal Production (1983–1995)", fontsize=14)
ax.axis('off')
plt.tight_layout()
plt.savefig("Z:/ek559/mining_wq/plots/data_cleaning/huc12_prod_change_1983_1995.png", dpi=900)
plt.close()

# 1995 and 2000
# Create the plot
fig, ax = plt.subplots(1, 1, figsize=(12, 8))
contiguous_states.plot(ax=ax, color='grey', edgecolor='black', linewidth=0.5)
huclevel[huclevel['prodtondiff1995_2000'] < 0].plot(
    ax=ax,
    column='prodtondiff1995_2000',
    cmap='Reds',
    edgecolor='Red',
    linewidth=0.1,
)
huclevel[huclevel['prodtondiff1995_2000'] >= 0].plot(
    ax=ax,
    column='prodtondiff1995_2000',
    cmap='Blues',
    edgecolor='blue',
    linewidth=0.1,
)
legend_elements = [
    Patch(facecolor='blue', edgecolor='blue', label='Increase in production'),
    Patch(facecolor='red', edgecolor='red', label='Decrease in production')
]
ax.legend(handles=legend_elements)
ax.set_title("Net Changes in HUC12 level Coal Production (1995-2000)", fontsize=14)
ax.axis('off')
plt.tight_layout()
plt.savefig("Z:/ek559/mining_wq/plots/data_cleaning/huc12_prod_change_1995_2000.png", dpi=900)
plt.close()

# 1983 and 2000
# Create the plot
fig, ax = plt.subplots(1, 1, figsize=(12, 8))
contiguous_states.plot(ax=ax, color='grey', edgecolor='black', linewidth=0.5)
huclevel[huclevel['prodtondiff1983_2000'] < 0].plot(
    ax=ax,
    column='prodtondiff1983_2000',
    cmap='Reds',
    edgecolor='Red',
    linewidth=0.1,
)
huclevel[huclevel['prodtondiff1983_2000'] >= 0].plot(
    ax=ax,
    column='prodtondiff1983_2000',
    cmap='Blues',
    edgecolor='blue',
    linewidth=0.1,
)
legend_elements = [
    Patch(facecolor='blue', edgecolor='blue', label='Increase in production'),
    Patch(facecolor='red', edgecolor='red', label='Decrease in production')
]
ax.legend(handles=legend_elements)
ax.set_title("Net Changes in HUC12 level Coal Production (1983-2000)", fontsize=14)
ax.axis('off')
plt.tight_layout()
plt.savefig("Z:/ek559/mining_wq/plots/data_cleaning/huc12_prod_change_1983_2000.png", dpi=900)
plt.close()

# Mean huclevel total production
huclevel = pd.read_csv("Z:/ek559/mining_wq/clean_data/coal_huc_prod.csv",
                       dtype={'huc12': str})
annual_stats = huclevel.groupby('year')['production_short_tons_coal'].agg(['mean', 'std']).reset_index()
plt.figure(figsize=(10, 6))
plt.errorbar(annual_stats['year'], annual_stats['mean'], yerr=annual_stats['std'], fmt='-o', capsize=5)
plt.xlabel('Year')
plt.ylabel('Average Production in Tons')
plt.title('Annual HUC12 Average Production Over Time with Standard Deviation')
plt.grid(True)
plt.tight_layout()
plt.savefig("Z:/ek559/mining_wq/plots/data_cleaning/huc12_prod_over_time.png", dpi=900)
plt.close()

############
# HUC12's with intakes and mine production
############

mines = pd.read_csv("Z:/ek559/mining_wq/clean_data/coal_mine_prod.csv", dtype={'mine_id': str, 'huc12': str}, low_memory=False)
# remove mines that are missing both production and huc data
mines = mines[~mines['latitude'].isna()]
mines = mines[~mines['production_short_tons'].isna()]

facility = pd.read_csv("Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_FACILITIES.csv", low_memory=False)
# intake always have a facility id and have pwsid
intake = pd.read_excel("Z:/ek559/water_instrument/cws_intake_hucs/PWS_Loctations_HUC12_A_I_2022Q2.xlsx",
                       dtype={'HUC_12': str, 'FACILITY_ID': str})
intake = intake[['HUC_12', 'PWSID', 'FACILITY_ID']]
intake = intake.rename(columns = {'HUC_12':'huc12'})
intake = intake.drop_duplicates()
facility = facility.merge(intake, on = ['PWSID', 'FACILITY_ID'], how='inner')
facility_huc = facility['huc12'].unique()

huclevel = pd.read_csv("Z:/ek559/mining_wq/clean_data/coal_huc_prod.csv",
                       dtype={'huc12': str})

huclevel = huclevel[huclevel['huc12'].isin(facility_huc)]

huclevel['prod1990'] = np.where(huclevel['year'] == 1990,
                                huclevel['production_short_tons_coal'],
                                np.nan)
huclevel['prod2005'] = np.where(huclevel['year'] == 2005,
                                huclevel['production_short_tons_coal'],
                                np.nan)

huclevel = huclevel.groupby(['huc12']).agg(
    prod1990=('prod1990', 'max'),
    prod2005=('prod2005', 'max'),
).reset_index()

huclevel['prodtondiff1990_2005'] = huclevel['prod2005'] - huclevel['prod1990']
huclevel = huclevel[['prodtondiff1990_2005','huc12']]

# huc shapefile
huc = gpd.read_file(r"Z:\ek559\sdwa_violations\WBD_HUC12_CONUS_pulled10262020\WBD_HUC12_CONUS_pulled10262020.shp")
huc = huc.rename(columns={'name': 'name_huc'})
huc = huc.drop(['objectid', 'tnmid', 'loaddate',
                'areaacres', 'areasqkm', 'states',
                'hutype', 'humod', 'tohuc', 'noncontrib',
                'noncontr_1'], axis = 1)
huclevel = huc.merge(huclevel, how='inner', on='huc12')

# Reproject HUC-level data to Web Mercator
huclevel = huclevel.to_crs(epsg=3857)
huclevel['increase'] = np.where(huclevel['prodtondiff1990_2005']>0,
                                1,
                                0)
huclevel['decrease'] = np.where(huclevel['prodtondiff1990_2005']<0,
                                1,
                                0)

# Load and reproject contiguous US states
all_states = pygris.states()
contiguous_states = all_states[~all_states['STUSPS'].isin(['AK', 'HI', 'PR', 'VI', 'GU', 'MP', 'AS'])]
contiguous_states = contiguous_states.to_crs(epsg=3857)

# 1990 and 2005
# Create the plot
fig, ax = plt.subplots(1, 1, figsize=(12, 8))
contiguous_states.plot(ax=ax, color='white', edgecolor='black', linewidth=0.5)
huclevel[huclevel['decrease'] == 1].plot(
    ax=ax,
    column='decrease',
    color='red',
    edgecolor='Red',
    linewidth=0.1,
)
huclevel[huclevel['increase'] == 1].plot(
    ax=ax,
    column='increase',
    color='blue',
    edgecolor='blue',
    linewidth=0.1,
)
legend_elements = [
    Patch(facecolor='blue', edgecolor='blue', label='Increase in production'),
    Patch(facecolor='red', edgecolor='red', label='Decrease in production')
]
ax.legend(handles=legend_elements)
ax.set_title("Net Changes in HUC12 level Coal Production (1990–2005)", fontsize=14)
ax.axis('off')
ax.figure.text(0.5, 0.02, "Note: Only HUC12's containing both coal mines and PWS's.",
         ha='center', va='bottom', fontsize=10, color='black')
plt.tight_layout()
plt.savefig("Z:/ek559/mining_wq/plots/data_cleaning/huc12_prod_change_1990_2005.png", dpi=900)
plt.close()

#######
# PWS intake locations
######

pws_intake = huc[huc['huc12'].isin(facility_huc)]
pws_intake = pws_intake.to_crs(epsg=3857)
fig, ax = plt.subplots(1, 1, figsize=(12, 8))
contiguous_states.plot(ax=ax, color='white', edgecolor='black', linewidth=0.5)
pws_intake.plot(
    ax=ax,
    color='red',
    edgecolor='Red',
    linewidth=0.2,
)
legend_elements = [
    Patch(facecolor='red', edgecolor='red', label='HUC12'),
]
ax.legend(handles=legend_elements)
ax.set_title("PWS intake HUC12", fontsize=14)
ax.axis('off')
ax.figure.text(0.5, 0.02, "Note: All PWS HUC12 intakes; data from EPA",
         ha='center', va='bottom', fontsize=10, color='black')
plt.tight_layout()
plt.savefig("Z:/ek559/mining_wq/plots/data_cleaning/pws_huc12_intake_map.png", dpi=900)
plt.close()

##############
# All mining hucs
##############

huclevel = pd.read_csv("Z:/ek559/mining_wq/clean_data/coal_huc_prod.csv",
                       dtype={'huc12': str})

huclevel['prod1985'] = np.where(huclevel['year'] == 1985,
                                huclevel['production_short_tons_coal'],
                                np.nan)
huclevel['prod2005'] = np.where(huclevel['year'] == 2005,
                                huclevel['production_short_tons_coal'],
                                np.nan)

huclevel = huclevel.groupby(['huc12']).agg(
    prod1985=('prod1985', 'max'),
    prod2005=('prod2005', 'max'),
).reset_index()

huclevel['prodtondiff1985_2005'] = huclevel['prod2005'] - huclevel['prod1985']
huclevel = huclevel[['prodtondiff1985_2005','huc12']]

# huc shapefile
huc = gpd.read_file(r"Z:\ek559\sdwa_violations\WBD_HUC12_CONUS_pulled10262020\WBD_HUC12_CONUS_pulled10262020.shp")
huc = huc.rename(columns={'name': 'name_huc'})
huc = huc.drop(['objectid', 'tnmid', 'loaddate',
                'areaacres', 'areasqkm', 'states',
                'hutype', 'humod', 'tohuc', 'noncontrib',
                'noncontr_1'], axis = 1)
huclevel = huc.merge(huclevel, how='inner', on='huc12')

# Reproject HUC-level data to Web Mercator
huclevel = huclevel.to_crs(epsg=3857)
huclevel['increase'] = np.where(huclevel['prodtondiff1985_2005']>0,
                                1,
                                0)
huclevel['decrease'] = np.where(huclevel['prodtondiff1985_2005']<0,
                                1,
                                0)

# Load and reproject contiguous US states
all_states = pygris.states()
contiguous_states = all_states[~all_states['STUSPS'].isin(['AK', 'HI', 'PR', 'VI', 'GU', 'MP', 'AS'])]
contiguous_states = contiguous_states.to_crs(epsg=3857)

# 1990 and 2005
# Create the plot
fig, ax = plt.subplots(1, 1, figsize=(12, 8))
contiguous_states.plot(ax=ax, color='white', edgecolor='black', linewidth=0.5)
huclevel[huclevel['decrease'] == 1].plot(
    ax=ax,
    column='decrease',
    color='red',
    edgecolor='Red',
    linewidth=0.1,
)
huclevel[huclevel['increase'] == 1].plot(
    ax=ax,
    column='increase',
    color='blue',
    edgecolor='blue',
    linewidth=0.1,
)
legend_elements = [
    Patch(facecolor='blue', edgecolor='blue', label='Increase in production'),
    Patch(facecolor='red', edgecolor='red', label='Decrease in production')
]
ax.legend(handles=legend_elements)
ax.set_title("Net Changes in HUC12 level Coal Production (1985–2005)", fontsize=14)
ax.axis('off')
ax.figure.text(0.5, 0.02, "Note: All HUC12's containing active coal mines.",
         ha='center', va='bottom', fontsize=10, color='black')
plt.tight_layout()
plt.savefig("Z:/ek559/mining_wq/plots/data_cleaning/all_huc12_prod_change_1985_2005.png", dpi=900)
plt.close()

########################
# proportionate circles
########################

huclevel = pd.read_csv("Z:/ek559/mining_wq/clean_data/coal_huc_prod.csv",
                       dtype={'huc12': str})

# ----------------------------
# 1) Build 1990/2005 totals per HUC12
# ----------------------------
# mark year-specific production
huclevel['prod1985'] = np.where(huclevel['year'] == 1985,
                                huclevel['production_short_tons_coal'],
                                np.nan)
huclevel['prod2005'] = np.where(huclevel['year'] == 2005,
                                huclevel['production_short_tons_coal'],
                                np.nan)

# aggregate TOTAL production by HUC12
huclevel = (huclevel
            .groupby('huc12', as_index=False)
            .agg(prod1985=('prod1985', 'sum'),
                 prod2005=('prod2005', 'sum')))

# ----------------------------
# 2) Read HUC12 shapefile and merge attributes
# ----------------------------
huc = gpd.read_file(r"Z:\ek559\sdwa_violations\WBD_HUC12_CONUS_pulled10262020\WBD_HUC12_CONUS_pulled10262020.shp")
# keep only necessary columns (adjust to match your file’s column names)
# If your shapefile stores the HUC12 code as 'huc12' or 'HUC12', adapt accordingly:
if 'HUC12' in huc.columns and 'huc12' not in huc.columns:
    huc = huc.rename(columns={'HUC12': 'huc12'})

huc = huc.merge(huclevel, how='inner', on='huc12')

# ----------------------------
# 3) Reproject to Web Mercator for plotting
# ----------------------------
huc = huc.to_crs(epsg=3857)

# centroids for circle plotting
huc_pts = huc.copy()
huc_pts['geometry'] = huc_pts.geometry.centroid

# ----------------------------
# 4) Background: contiguous US states (Web Mercator)
# ----------------------------
all_states = pygris.states()
contiguous_states = all_states[~all_states['STUSPS'].isin(['AK', 'HI', 'PR', 'VI', 'GU', 'MP', 'AS'])]
contiguous_states = contiguous_states.to_crs(epsg=3857)

# ----------------------------
# 5) Helper to draw proportional circles
# ----------------------------
def plot_circles(ax, states_gdf, pts_gdf, values, color, title, s_max=800):
    """Plot states outline and proportional circles from pts_gdf."""
    # base map
    states_gdf.plot(ax=ax, color='white', edgecolor='black', linewidth=0.5)

    # values prep
    v = values.fillna(0)
    vmax = float(v.max()) if np.isfinite(v.max()) else 1.0  # avoid zero division
    sizes = (v / vmax) * s_max  # area in points^2

    # circles
    ax.scatter(pts_gdf.geometry.x, pts_gdf.geometry.y,
               s=sizes, color=color, alpha=0.6,
               edgecolors='k', linewidth=0.3)

    # title, formatting
    ax.set_title(title, fontsize=14)
    ax.axis('off')

    # a small size legend (three reference values)
    ref_vals = [vmax/4, vmax/2, vmax] if vmax > 0 else [1, 2, 3]
    legend_handles = []
    for rv in ref_vals:
        legend_handles.append(
            ax.scatter([], [], s=(rv/vmax)*s_max if vmax > 0 else rv,
                       color=color, alpha=0.6, edgecolors='k')
        )
    labels = [f"{rv:,.0f} short tons" for rv in ref_vals]
    ax.legend(legend_handles, labels, title="Production", loc="lower left",
              frameon=False, fontsize=9)

# ----------------------------
# 6) Two stacked maps
# ----------------------------
fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(12, 16))

plot_circles(
    ax=ax1,
    states_gdf=contiguous_states,
    pts_gdf=huc_pts,
    values=huc_pts['prod1985'],
    color='steelblue',
    title="Coal production (short tons) by HUC12: 1985",
    s_max=800  # adjust to taste
)

plot_circles(
    ax=ax2,
    states_gdf=contiguous_states,
    pts_gdf=huc_pts,
    values=huc_pts['prod2005'],
    color='tomato',
    title="Coal production (short tons) by HUC12: 2005",
    s_max=800
)

# shared note
fig.text(0.5, 0.02,
         "Notes: Circle areas are proportional to total production in the year shown.",
         ha='center', va='bottom', fontsize=10, color='black')

plt.tight_layout()
plt.savefig("Z:/ek559/mining_wq/plots/data_cleaning/proportionatecircleprod_huc12_1985_2005.png", dpi=1200)
plt.close()



##########
# One map for proportional changes
##########



# ------------------------------------------------------------
# Helper: make a bubble-size legend whose areas match scatter s
# ------------------------------------------------------------
def bubble_size_legend(ax, values, s_min=20, s_max=800, n=3,
                       title='|Change| (short tons)', loc='lower left',
                       bbox_to_anchor=(0.02, 0.05), color='gray', alpha=0.5):
    """
    Draw a size (area) legend for bubble plots.
    values: 1D array of positive magnitudes used to compute sizes.
    """
    vals = np.linspace(values.min(), values.max(), n) if np.ptp(values) > 0 else np.array([values.min()])
    # linear scaling to match how we scale s
    vmin, vmax = values.min(), values.max()
    s_vals = s_min + (vals - vmin) * (s_max - s_min) / (vmax - vmin + 1e-12)

    handles = []
    labels = []
    for v, s in zip(vals, s_vals):
        h = plt.scatter([], [], s=s, facecolors='none', edgecolors=color, alpha=alpha)
        handles.append(h)
        labels.append(f'{v:,.0f}')
    leg = ax.legend(handles, labels, title=title, scatterpoints=1,
                    loc=loc, bbox_to_anchor=bbox_to_anchor, frameon=True)
    return leg

# ------------------------------------------------------------
# Main: one-map change plot
# ------------------------------------------------------------
def plot_change_map(states_gdf, pts_gdf, col_1985='prod1985', col_2005='prod2005',
                    s_min=20, s_max=800, alpha=0.7):
    """
    Make a single map where increases are blue, decreases are red,
    and circle *area* is proportional to |2005 - 1985|.
    """
    gdf = pts_gdf.copy()
    gdf['change'] = gdf[col_2005] - gdf[col_1985]
    gdf['mag'] = np.abs(gdf['change'])

    # guard against all-zero or missing
    mag_nonzero = gdf.loc[gdf['mag'] > 0, 'mag'].to_numpy()
    if mag_nonzero.size == 0:
        raise ValueError("All changes are zero or missing—nothing to plot.")

    vmin, vmax = np.nanmin(mag_nonzero), np.nanmax(mag_nonzero)
    # s is area in points^2; keep a small visible minimum for nonzero bubbles
    gdf['s'] = np.where(
        gdf['mag'] <= 0,
        0.0,
        s_min + (gdf['mag'] - vmin) * (s_max - s_min) / (vmax - vmin + 1e-12)
    )

    inc = gdf[gdf['change'] > 0]
    dec = gdf[gdf['change'] < 0]

    fig, ax = plt.subplots(1, 1, figsize=(12, 8))

    # base map
    states_gdf.plot(ax=ax, facecolor='white', edgecolor='0.7', linewidth=0.6)

    # bubbles (area ∝ |change|)
    if not dec.empty:
        dec.plot(ax=ax, markersize=dec['s'], color='tomato', alpha=alpha, marker='o', linewidth=0)
    if not inc.empty:
        inc.plot(ax=ax, markersize=inc['s'], color='steelblue', alpha=alpha, marker='o', linewidth=0)

    ax.set_axis_off()
    ax.set_title("Change in tonnes of coal extracted by HUC12, from 1985 to 2005\n"
                 "Blue = increase, Red = decrease; circle area proportionate to change",
                 fontsize=14)

    # legends
    size_leg = bubble_size_legend(ax, values=mag_nonzero, s_min=s_min, s_max=s_max,
                                  title='Change (short tons)', loc='lower left',
                                  bbox_to_anchor=(0.02, 0.05))
    ax.add_artist(size_leg)  # keep size legend when adding another legend

    color_handles = [
        Line2D([0], [0], marker='o', color='w', label='Increase',
               markerfacecolor='steelblue', markersize=10, alpha=alpha),
        Line2D([0], [0], marker='o', color='w', label='Decrease',
               markerfacecolor='tomato', markersize=10, alpha=alpha)
    ]
    ax.legend(handles=color_handles, title='Direction', loc='lower right')

    # note
    fig.text(0.5, 0.02,
             "Notes: Circle areas are proportional to absolute change in production (short tons), 1985-2005.",
             ha='center', va='bottom', fontsize=9, color='black')

    plt.tight_layout()
    plt.savefig("Z:/ek559/mining_wq/plots/data_cleaning/proportionatecircleprod_huc12_1985_2005.png", dpi=1200)
    plt.close()
    
# ---- usage (given your existing GeoDataFrames) ----
plot_change_map(
    states_gdf=contiguous_states,
    pts_gdf=huc_pts,
    col_1985='prod1985',
    col_2005='prod2005',
    s_min=20,
    s_max=800
)

##########################################################################
# Proportionate circle map: change in coal PRODUCTION, 1985-2005
# Mine HUC12s upstream of downstream-only 2SLS CWSs, >= 1 active mine year 1985-2005
##########################################################################

import pyogrio

# Mine HUC12s that a downstream-only 2SLS CWS draws water from: fromhuc in
# "downstream_of_mine" rows of prod_sulfur. Restricted to HUC12s with >= 1
# active mine year in 1985-2005 (same sample as scatter and regression outputs).
import pyarrow.parquet as pq

prod_s = pd.read_csv("Z:/ek559/mining_wq/clean_data/prod_sulfur.csv",
                     dtype={"huc12": str}, low_memory=False)
ds_rows = prod_s[prod_s["minehuc"] == "downstream_of_mine"]
raw_fromhucs = ds_rows["fromhuc"].dropna().unique()
upstream_mine_hucs_all = set(str(int(f)).zfill(12) for f in raw_fromhucs)

# Identify active HUC12s: present in parquet with >= 1 mine year in 1985-2005
huccoal_pq = pq.read_table(
    "Z:/ek559/mining_wq/clean_data/huc_coal_charac_geom_match.parquet",
    columns=["huc12", "year", "num_coal_mines_colocated"]
).to_pandas()
huccoal_pq["huc12"] = huccoal_pq["huc12"].astype(str).str.zfill(12)
huccoal_sub = huccoal_pq[
    huccoal_pq["huc12"].isin(upstream_mine_hucs_all) &
    huccoal_pq["year"].between(1985, 2005)
]
active_mine_hucs = set(
    huccoal_sub.groupby("huc12")["num_coal_mines_colocated"]
    .max()
    .pipe(lambda s: s[s > 0].index)
)
upstream_mine_hucs = upstream_mine_hucs_all & active_mine_hucs
print(f"Mine HUC12s upstream of downstream-only 2SLS CWSs: {len(upstream_mine_hucs)}")

coal_all = pd.read_csv("Z:/ek559/mining_wq/clean_data/coal_huc_prod.csv", dtype={"huc12": str})

# Production data
coal = coal_all[coal_all["huc12"].isin(upstream_mine_hucs)].copy()

prod_1985 = (coal[coal["year"] == 1985]
             .groupby("huc12")["production_short_tons_coal"].max()
             .rename("prod1985"))
prod_2005 = (coal[coal["year"] == 2005]
             .groupby("huc12")["production_short_tons_coal"].max()
             .rename("prod2005"))

mine_chg = (pd.concat([prod_1985, prod_2005], axis=1)
            .reset_index()
            .fillna(0))
mine_chg["change"] = mine_chg["prod2005"] - mine_chg["prod1985"]
mine_chg["mag"]    = mine_chg["change"].abs()
print(f"Upstream-only mine HUC12s with data: {len(mine_chg)}  "
      f"(increase: {(mine_chg['change']>0).sum()}, decrease: {(mine_chg['change']<0).sum()})")

# Load HUC12 centroids
huc_attrs = pyogrio.read_dataframe(
    r"Z:\ek559\sdwa_violations\WBD_HUC12_CONUS_pulled10262020\WBD_HUC12_CONUS_pulled10262020.shp",
    columns=["huc12"]
)
huc_attrs["huc12"] = huc_attrs["huc12"].astype(str).str.strip()
huc_attrs = huc_attrs[huc_attrs["huc12"].isin(mine_chg["huc12"])].copy()
huc_attrs = huc_attrs.to_crs("EPSG:5070")
huc_attrs["geometry"] = huc_attrs["geometry"].centroid

mine_pts = huc_attrs.merge(mine_chg, on="huc12")
mine_pts = gpd.GeoDataFrame(mine_pts, geometry="geometry", crs="EPSG:5070")
print(f"Mine HUC12 centroids matched: {len(mine_pts)}")

# Size bubbles proportionally to |change|
mag_nonzero = mine_pts.loc[mine_pts["mag"] > 0, "mag"].to_numpy()
vmin_m, vmax_m = float(mag_nonzero.min()), float(mag_nonzero.max())
S_MIN, S_MAX = 15, 500
mine_pts["s"] = np.where(
    mine_pts["mag"] <= 0, 0.0,
    S_MIN + (mine_pts["mag"] - vmin_m) * (S_MAX - S_MIN) / (vmax_m - vmin_m + 1e-12)
)

states_albers = contiguous_states.to_crs("EPSG:5070")
bounds = mine_pts.total_bounds
buf = 150_000
xlim = (bounds[0] - buf, bounds[2] + buf)
ylim = (bounds[1] - buf, bounds[3] + buf)

fig, ax = plt.subplots(figsize=(11, 7))
states_albers.plot(ax=ax, facecolor="white", edgecolor="0.65", linewidth=0.5)

inc = mine_pts[mine_pts["change"] > 0]
dec = mine_pts[mine_pts["change"] < 0]
if not dec.empty:
    dec.plot(ax=ax, markersize=dec["s"], color="tomato",   alpha=0.75, marker="o", linewidth=0)
if not inc.empty:
    inc.plot(ax=ax, markersize=inc["s"], color="steelblue", alpha=0.75, marker="o", linewidth=0)

ax.set_xlim(*xlim)
ax.set_ylim(*ylim)
ax.set_axis_off()
ax.set_title(
    "Change in coal production (short tons) by HUC12, 1985 to 2005\n"
    "Mine HUC12s upstream of downstream-only 2SLS CWSs  |  Blue = increase, Red = decrease",
    fontsize=11
)

# Size legend
ref_mags = np.array([vmax_m * 0.25, vmax_m * 0.5, vmax_m])
ref_s    = S_MIN + (ref_mags - vmin_m) * (S_MAX - S_MIN) / (vmax_m - vmin_m + 1e-12)
size_handles = [ax.scatter([], [], s=s, color="grey", alpha=0.6, edgecolors="k")
                for s in ref_s]
size_labels  = [f"{int(v):,.0f} short tons" for v in ref_mags]
leg1 = ax.legend(size_handles, size_labels, title="|Change|", loc="lower left",
                 bbox_to_anchor=(0.01, 0.05), frameon=True, fontsize=8)
ax.add_artist(leg1)

color_handles = [
    Line2D([0],[0], marker="o", color="w", markerfacecolor="steelblue", markersize=9, label="Increase"),
    Line2D([0],[0], marker="o", color="w", markerfacecolor="tomato",    markersize=9, label="Decrease"),
]
ax.legend(handles=color_handles, title="Direction", loc="lower right", fontsize=8)

fig.text(0.5, 0.01,
         "Circle area proportional to absolute change in coal production (short tons), 1985–2005.\n"
         "Mine HUC12s upstream of CWS intakes in the downstream-only 2SLS regression sample.",
         ha="center", fontsize=8, color="0.4")

plt.tight_layout()
out_path = "Z:/ek559/mining_wq/output/fig/proportionatecircleprod_huc12_1985_2005.png"
plt.savefig(out_path, dpi=200, bbox_inches="tight")
plt.close()
print(f"Saved: {out_path}")

##########################################################################
# Proportionate circle map: change in coal PRODUCTION, 1985-2005
# All mining HUC12s (any HUC12 with > 0 production in at least one year)
##########################################################################

coal_all_full = pd.read_csv("Z:/ek559/mining_wq/clean_data/coal_huc_prod.csv", dtype={"huc12": str})

# Restrict to HUC12s with positive production in at least one year 1985-2005
active_all = (
    coal_all_full[coal_all_full["year"].between(1985, 2005)]
    .groupby("huc12")["production_short_tons_coal"]
    .max()
    .pipe(lambda s: s[s > 0].index)
)

coal_active = coal_all_full[coal_all_full["huc12"].isin(active_all)].copy()

prod_1985_all = (coal_active[coal_active["year"] == 1985]
                 .groupby("huc12")["production_short_tons_coal"].max()
                 .rename("prod1985"))
prod_2005_all = (coal_active[coal_active["year"] == 2005]
                 .groupby("huc12")["production_short_tons_coal"].max()
                 .rename("prod2005"))

mine_chg_all = (pd.concat([prod_1985_all, prod_2005_all], axis=1)
                .reset_index()
                .fillna(0))
mine_chg_all["change"] = mine_chg_all["prod2005"] - mine_chg_all["prod1985"]
mine_chg_all["mag"] = mine_chg_all["change"].abs()
print(f"All active mine HUC12s: {len(mine_chg_all)}  "
      f"(increase: {(mine_chg_all['change'] > 0).sum()}, "
      f"decrease: {(mine_chg_all['change'] < 0).sum()})")

huc_attrs_all = pyogrio.read_dataframe(
    r"Z:\ek559\sdwa_violations\WBD_HUC12_CONUS_pulled10262020\WBD_HUC12_CONUS_pulled10262020.shp",
    columns=["huc12"]
)
huc_attrs_all["huc12"] = huc_attrs_all["huc12"].astype(str).str.strip()
huc_attrs_all = huc_attrs_all[huc_attrs_all["huc12"].isin(mine_chg_all["huc12"])].copy()
huc_attrs_all = huc_attrs_all.to_crs("EPSG:5070")
huc_attrs_all["geometry"] = huc_attrs_all["geometry"].centroid

mine_pts_all = huc_attrs_all.merge(mine_chg_all, on="huc12")
mine_pts_all = gpd.GeoDataFrame(mine_pts_all, geometry="geometry", crs="EPSG:5070")
print(f"All mine HUC12 centroids matched: {len(mine_pts_all)}")

mag_nonzero_all = mine_pts_all.loc[mine_pts_all["mag"] > 0, "mag"].to_numpy()
vmin_a, vmax_a = float(mag_nonzero_all.min()), float(mag_nonzero_all.max())
S_MIN_A, S_MAX_A = 15, 500
mine_pts_all["s"] = np.where(
    mine_pts_all["mag"] <= 0, 0.0,
    S_MIN_A + (mine_pts_all["mag"] - vmin_a) * (S_MAX_A - S_MIN_A) / (vmax_a - vmin_a + 1e-12)
)

fig, ax = plt.subplots(figsize=(11, 7))
states_albers.plot(ax=ax, facecolor="white", edgecolor="0.65", linewidth=0.5)

inc_all = mine_pts_all[mine_pts_all["change"] > 0]
dec_all = mine_pts_all[mine_pts_all["change"] < 0]
if not dec_all.empty:
    dec_all.plot(ax=ax, markersize=dec_all["s"], color="tomato",    alpha=0.75, marker="o", linewidth=0)
if not inc_all.empty:
    inc_all.plot(ax=ax, markersize=inc_all["s"], color="steelblue", alpha=0.75, marker="o", linewidth=0)

ax.set_axis_off()
ax.set_title(
    "Change in coal production (short tons) by HUC12, 1985 to 2005\n"
    "All active mine HUC12s  |  Blue = increase, Red = decrease",
    fontsize=11
)

ref_mags_a = np.array([vmax_a * 0.25, vmax_a * 0.5, vmax_a])
ref_s_a    = S_MIN_A + (ref_mags_a - vmin_a) * (S_MAX_A - S_MIN_A) / (vmax_a - vmin_a + 1e-12)
size_handles_a = [ax.scatter([], [], s=s, color="grey", alpha=0.6, edgecolors="k") for s in ref_s_a]
size_labels_a  = [f"{int(v):,.0f} short tons" for v in ref_mags_a]
leg1_a = ax.legend(size_handles_a, size_labels_a, title="|Change|", loc="lower left",
                   bbox_to_anchor=(0.01, 0.05), frameon=True, fontsize=8)
ax.add_artist(leg1_a)

color_handles_a = [
    Line2D([0], [0], marker="o", color="w", markerfacecolor="steelblue", markersize=9, label="Increase"),
    Line2D([0], [0], marker="o", color="w", markerfacecolor="tomato",    markersize=9, label="Decrease"),
]
ax.legend(handles=color_handles_a, title="Direction", loc="lower right", fontsize=8)

fig.text(0.5, 0.01,
         "Circle area proportional to absolute change in coal production (short tons), 1985–2005.\n"
         "All HUC12s with positive coal production in at least one year, 1985–2005.",
         ha="center", fontsize=8, color="0.4")

plt.tight_layout()
out_path_all = "Z:/ek559/mining_wq/output/fig/proportionatecircleprod_diff_allminehuc12_1985_2005.png"
plt.savefig(out_path_all, dpi=200, bbox_inches="tight")
plt.close()
print(f"Saved: {out_path_all}")

##########################################################################
# Proportionate circle maps (2-panel): upstream mine HUC12s, 1985-2005
# Panel 1: change in coal production | Panel 2: change in active mine count
# Upstream HUC12s = mine HUC12s upstream of downstream-only 2SLS CWSs
# (reuses upstream_mine_hucs and coal from the section above)
##########################################################################

coal_up = coal_all[coal_all["huc12"].isin(upstream_mine_hucs)].copy()

prod_1985_up = (coal_up[coal_up["year"] == 1985]
                .groupby("huc12")["production_short_tons_coal"].max()
                .rename("prod1985"))
prod_2005_up = (coal_up[coal_up["year"] == 2005]
                .groupby("huc12")["production_short_tons_coal"].max()
                .rename("prod2005"))

mine_1985_up = (coal_up[coal_up["year"] == 1985]
                .groupby("huc12")["num_coal_mines"].max()
                .rename("mines1985"))
mine_2005_up = (coal_up[coal_up["year"] == 2005]
                .groupby("huc12")["num_coal_mines"].max()
                .rename("mines2005"))

upstream_chg = (pd.concat([prod_1985_up, prod_2005_up, mine_1985_up, mine_2005_up], axis=1)
                .reset_index()
                .fillna(0))
upstream_chg["prod_change"]  = upstream_chg["prod2005"]  - upstream_chg["prod1985"]
upstream_chg["mines_change"] = upstream_chg["mines2005"] - upstream_chg["mines1985"]
upstream_chg["prod_mag"]     = upstream_chg["prod_change"].abs()
upstream_chg["mines_mag"]    = upstream_chg["mines_change"].abs()
print(f"Upstream HUC12s: {len(upstream_chg)}  "
      f"prod increase: {(upstream_chg['prod_change'] > 0).sum()}, "
      f"decrease: {(upstream_chg['prod_change'] < 0).sum()}  |  "
      f"mine increase: {(upstream_chg['mines_change'] > 0).sum()}, "
      f"decrease: {(upstream_chg['mines_change'] < 0).sum()}")

huc_up = pyogrio.read_dataframe(
    r"Z:\ek559\sdwa_violations\WBD_HUC12_CONUS_pulled10262020\WBD_HUC12_CONUS_pulled10262020.shp",
    columns=["huc12"]
)
huc_up["huc12"] = huc_up["huc12"].astype(str).str.strip()
huc_up = huc_up[huc_up["huc12"].isin(upstream_chg["huc12"])].copy()
huc_up = huc_up.to_crs("EPSG:5070")
huc_up["geometry"] = huc_up["geometry"].centroid

up_pts = huc_up.merge(upstream_chg, on="huc12")
up_pts = gpd.GeoDataFrame(up_pts, geometry="geometry", crs="EPSG:5070")
print(f"Upstream mine HUC12 centroids matched: {len(up_pts)}")

def scale_bubble_sizes(change_series, s_min=15, s_max=500):
    """Scale |change| to scatter marker sizes; return sizes array and (vmin, vmax) of nonzero mags."""
    mag = change_series.abs()
    nonzero = mag[mag > 0].to_numpy()
    vmin_s, vmax_s = nonzero.min(), nonzero.max()
    sizes = np.where(
        mag <= 0, 0.0,
        s_min + (mag - vmin_s) * (s_max - s_min) / (vmax_s - vmin_s + 1e-12)
    )
    return sizes, vmin_s, vmax_s

S_MIN2, S_MAX2 = 15, 500
prod_sizes_up, prod_vmin_up, prod_vmax_up = scale_bubble_sizes(up_pts["prod_change"],  S_MIN2, S_MAX2)
mine_sizes_up, mine_vmin_up, mine_vmax_up = scale_bubble_sizes(up_pts["mines_change"], S_MIN2, S_MAX2)
up_pts["s_prod"]  = prod_sizes_up
up_pts["s_mines"] = mine_sizes_up

bounds_up = up_pts.total_bounds
buf_up = 150_000
xlim_up = (bounds_up[0] - buf_up, bounds_up[2] + buf_up)
ylim_up = (bounds_up[1] - buf_up, bounds_up[3] + buf_up)

def draw_upstream_panel(ax, pts, s_col, change_col, vmin_v, vmax_v,
                        s_min, s_max, title, unit_label):
    states_albers.plot(ax=ax, facecolor="white", edgecolor="0.65", linewidth=0.5)
    inc = pts[pts[change_col] > 0]
    dec = pts[pts[change_col] < 0]
    if not dec.empty:
        dec.plot(ax=ax, markersize=dec[s_col], color="tomato",    alpha=0.75, marker="o", linewidth=0)
    if not inc.empty:
        inc.plot(ax=ax, markersize=inc[s_col], color="steelblue", alpha=0.75, marker="o", linewidth=0)
    ax.set_xlim(*xlim_up)
    ax.set_ylim(*ylim_up)
    ax.set_axis_off()
    ax.set_title(title, fontsize=11)

    ref_v = np.array([vmax_v * 0.25, vmax_v * 0.5, vmax_v])
    ref_s = s_min + (ref_v - vmin_v) * (s_max - s_min) / (vmax_v - vmin_v + 1e-12)
    sz_handles = [ax.scatter([], [], s=s, color="grey", alpha=0.6, edgecolors="k") for s in ref_s]
    sz_labels  = [f"{int(v):,.0f} {unit_label}" for v in ref_v]
    leg1 = ax.legend(sz_handles, sz_labels, title="|Change|", loc="lower left",
                     bbox_to_anchor=(0.01, 0.05), frameon=True, fontsize=8)
    ax.add_artist(leg1)

    color_handles = [
        Line2D([0], [0], marker="o", color="w", markerfacecolor="steelblue", markersize=9, label="Increase"),
        Line2D([0], [0], marker="o", color="w", markerfacecolor="tomato",    markersize=9, label="Decrease"),
    ]
    ax.legend(handles=color_handles, title="Direction", loc="lower right", fontsize=8)

# Panel 1: change in coal production (short tons)
fig, ax1 = plt.subplots(1, 1, figsize=(11, 7))
draw_upstream_panel(
    ax=ax1, pts=up_pts, s_col="s_prod", change_col="prod_change",
    vmin_v=prod_vmin_up, vmax_v=prod_vmax_up, s_min=S_MIN2, s_max=S_MAX2,
    title="Change in coal production (short tons), 1985–2005\nMine HUC12s upstream of CWS intakes  |  Blue = increase, Red = decrease",
    unit_label="short tons"
)
fig.text(0.5, 0.01,
         "Circle area proportional to absolute change in coal production (short tons), 1985–2005.\n"
         "Mine HUC12s upstream of CWS intakes in the downstream-only 2SLS regression sample.",
         ha="center", fontsize=8, color="0.4")
plt.tight_layout()
out_prod = "Z:/ek559/mining_wq/output/fig/proportionatecircle_upstream_prod_huc12_1985_2005.png"
plt.savefig(out_prod, dpi=200, bbox_inches="tight")
plt.close()
print(f"Saved: {out_prod}")

# Panel 2: change in number of active coal mines
fig, ax2 = plt.subplots(1, 1, figsize=(11, 7))
draw_upstream_panel(
    ax=ax2, pts=up_pts, s_col="s_mines", change_col="mines_change",
    vmin_v=mine_vmin_up, vmax_v=mine_vmax_up, s_min=S_MIN2, s_max=S_MAX2,
    title="Change in number of active coal mines, 1985–2005\nMine HUC12s upstream of CWS intakes  |  Blue = increase, Red = decrease",
    unit_label="mines"
)
fig.text(0.5, 0.01,
         "Circle area proportional to absolute change in number of active coal mines, 1985–2005.\n"
         "Mine HUC12s upstream of CWS intakes in the downstream-only 2SLS regression sample.",
         ha="center", fontsize=8, color="0.4")
plt.tight_layout()
out_mines = "Z:/ek559/mining_wq/output/fig/proportionatecircle_upstream_mines_huc12_1985_2005.png"
plt.savefig(out_mines, dpi=200, bbox_inches="tight")
plt.close()
print(f"Saved: {out_mines}")
