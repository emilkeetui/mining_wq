import pandas as pd
import geopandas as gpd
import os
import glob
import matplotlib.pyplot as plt
from matplotlib.patches import Patch
import pygris
import numpy as np

# Matching mines to huc12's
minegpd = pd.read_csv("Z:/ek559/mining_wq/msha_data/mines.csv",
                   encoding='windows-1252',
                   dtype={'mine_id': str,'FIPS_CNTY_CD': str, 'BOM_STATE_CD': str})
print(minegpd.shape)
minegpd = gpd.GeoDataFrame(minegpd, geometry=gpd.points_from_xy(minegpd.longitude, minegpd.latitude), crs="EPSG:4326")
huc = gpd.read_file(r"Z:\ek559\sdwa_violations\WBD_HUC12_CONUS_pulled10262020\WBD_HUC12_CONUS_pulled10262020.shp")
huc = huc.rename(columns={'name': 'name_huc'})
huc = huc.drop(['objectid', 'tnmid', 'loaddate',
                'areaacres', 'areasqkm', 'states',
                'hutype', 'humod', 'noncontrib',
                'noncontr_1'], axis = 1)
minegpd = minegpd.to_crs(huc.crs)
minegpd = minegpd.sjoin(huc, predicate = 'intersects')
minegpd = minegpd.drop(['index_right', 'geometry'], axis = 1)

# Abandoned mines before 1983
minegpd['current_status_dt'] = pd.to_datetime(minegpd['current_status_dt'])
minegpd['activeafter83'] = np.where((minegpd['current_status_dt']>'1983-01-01') & (minegpd['current_mine_status'].isin(['Active','New Mine'])),
                                    1,
                                    0)

minepd = pd.DataFrame(minegpd)

#number of mines (18870) and hucs (5685)
print("mines",len(minegpd.mine_id.unique()))
print("hucs",len(minegpd.huc12.unique()))

# match mine production
fullprod = pd.DataFrame()
folder_path = "Z:/ek559/mining_wq/eia_data/coal/coal_prod"
file_list = glob.glob(os.path.join(folder_path, "coalpublic*.xls"))
for file in file_list:
    print(file)
    tempprod = pd.read_excel(file, header=None, engine='xlrd', dtype={'msha_id': str})
    tempprod.columns = tempprod.iloc[3]
    tempprod = tempprod.iloc[4:].reset_index(drop=True)
    tempprod.columns = tempprod.columns.str.replace(" ", "_").str.replace("(", "").str.replace(")", "").str.lower()
    tempprod = tempprod.rename(columns={'msha_id': 'mine_id'})
    fullprod = pd.concat([fullprod, tempprod], ignore_index=True)

file_list = glob.glob(os.path.join(folder_path, "coalpublic*.xlsx"))
for file in file_list:
    print(file)
    tempprod = pd.read_excel(file, header=None, dtype={'msha_id': str})
    tempprod.columns = tempprod.iloc[3]
    tempprod = tempprod.iloc[4:].reset_index(drop=True)
    tempprod.columns = tempprod.columns.str.replace(" ", "_").str.replace("(", "").str.replace(")", "").str.lower()
    tempprod = tempprod.rename(columns={'msha_id': 'mine_id'})
    fullprod = pd.concat([fullprod, tempprod], ignore_index=True)

print('Merging')
print(fullprod)
print(minepd)

fullprod.to_csv("Z:/ek559/mining_wq/clean_data/eia_prod.csv", index=False)
fullprod = pd.read_csv("Z:/ek559/mining_wq/clean_data/eia_prod.csv", dtype={'mine_id': str}, low_memory=False)

# for now just match on mind_id - if you want to match on county and state you need
# to change the county in eia from the full name to the two letter abreviation
minepd = minepd.merge(fullprod, how='outer', on = ['mine_id'])
print('minepd')
print(minepd)

# latitude is present in every observation from msha 
# missing latitude after match is only for observations
# from eia which could not be matched to an observation in msha
print('missing in msha not eia', minepd.latitude.isna().sum())

#save the matched file
print('Saving mine level')
print(minepd.columns)
print(minepd.shape)
minepd.to_csv("Z:/ek559/mining_wq/clean_data/coal_mine_prod.csv", index=False)
minepd = pd.read_csv("Z:/ek559/mining_wq/clean_data/coal_mine_prod.csv", dtype={'mine_id': str, 'huc12': str}, low_memory=False)

# plot where mines are being dropped
# no regard for abandoned
minegpd = minegpd.merge(huc, on = 'huc12', how='left')
minegpd = gpd.GeoDataFrame(minegpd, geometry='geometry')
# prod data
# all eia data has production
# all msha data has lat
# removing missing production and lat will retain only matched obs
minepd = minepd[~minepd['production_short_tons'].isna()]
minepd = minepd[~minepd['latitude'].isna()]
minepd = minepd.merge(huc, on = 'huc12', how='left')
minepd = gpd.GeoDataFrame(minepd, geometry='geometry')

# Identify shared geometries
matched = minegpd[minegpd.geometry.isin(minepd.geometry)]

# Unique to full set of mines from msha but not in production
# contains mines not matched to eia including abandoned before 1983 here abandoned later removed
mshanoteia = minegpd[~minegpd.geometry.isin(matched.geometry)]

# Load and reproject contiguous US states
all_states = pygris.states()
contiguous_states = all_states[~all_states['STUSPS'].isin(['AK', 'HI', 'PR', 'VI', 'GU', 'MP', 'AS'])]
contiguous_states = contiguous_states.to_crs(minepd.crs)

# active mines
# msha data abandoned before 1983
abandonedmsha = minegpd[minegpd['activeafter83']==0]
abandonedmsha = gpd.GeoDataFrame(abandonedmsha, geometry='geometry')
mshanoteia = mshanoteia[~mshanoteia.geometry.isin(abandonedmsha.geometry)]

# Plotting
fig, ax = plt.subplots()
contiguous_states.plot(ax=ax, color='white', edgecolor='black', linewidth=0.5)
abandonedmsha.plot(ax=ax, color='green')
mshanoteia.plot(ax=ax, color='blue')
matched.plot(ax=ax, color='red')

# Manually create legend handles
legend_elements = [
    Patch(facecolor='green', edgecolor='green', label='Abandoned'),
    Patch(facecolor='blue', edgecolor='blue', label='MSHA only'),
    Patch(facecolor='red', edgecolor='red', label='MSHA and EIA')
]

# Add legend and axis labels
ax.legend(handles=legend_elements)
ax.set_title("HUC12s with MSHA and EIA Mine Data")
ax.axis('off')
plt.savefig("Z:/ek559/mining_wq/plots/data_cleaning/eia_msha_mine_huc12s.png", dpi=900)
plt.show()
plt.close()

#huc level file
print('Saving huc level')
hucgroup = minepd.groupby(['huc12', 'year']).agg(
    production_short_tons_coal=('production_short_tons', 'sum'),
    num_coal_mines=('mine_id', 'count')
).reset_index()

huc_unique = pd.DataFrame(hucgroup['huc12'].drop_duplicates())
df_years = pd.DataFrame({'year': list(range(1983, 2025))})
huc_year = huc_unique.merge(df_years, how='cross')
hucgroup = hucgroup.merge(huc_year, on=['huc12','year'], how='outer')
hucgroup[['production_short_tons_coal', 'num_coal_mines']] = hucgroup[['production_short_tons_coal', 'num_coal_mines']].fillna(0)

hucgroup.to_csv("Z:/ek559/mining_wq/clean_data/coal_huc_prod.csv", index=False)