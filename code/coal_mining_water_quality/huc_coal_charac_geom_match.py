import pandas as pd
import geopandas as gpd
from shapely.geometry import Point
import numpy as np

# All hucs associated with this project are those that contain mines, those that are upstream of
# mines and who do not contain mines and whose upstream hucs do not contain mines, and those that are 
# downstream of mines.
# Each row of the final dataset consists of the hucs where mining takes place,
# hucs that are directly downstream and upstream of those mining hucs, and the columns
# are the colocated coal production and sulfur and the mean coal and sulfur from upstream

# Load sample details CSV
sample = pd.read_csv("Z:/ek559/mining_wq/raw_data/coal_qual/CQ2025101314323_sampledetails.CSV", nrows=7450)
sample.columns = sample.columns.str.replace(" ", "").str.lower()

# Load ultimate analysis CSV
ult = pd.read_csv("Z:/ek559/mining_wq/raw_data/coal_qual/CQ20251013152532_proximateultimate.CSV", nrows=7430)
ult.columns = ult.columns.str.replace(" ", "").str.lower()

# Merge datasets on 'sampleid'
samplelocation = pd.merge(ult, sample, on='sampleid')

# Filter out rows with missing sulfur values
samplelocation = samplelocation[samplelocation['sulfur'].notna()]

# Convert to GeoDataFrame
geometry = [Point(xy) for xy in zip(samplelocation['longitude'], samplelocation['latitude'])]
samplelocation_gdf = gpd.GeoDataFrame(samplelocation, geometry=geometry, crs="EPSG:4326")
samplelocation_gdf = samplelocation_gdf.to_crs("EPSG:5070")
samplelocation_gdf = samplelocation_gdf[['geometry', 'sulfur', 'btu']]
samplelocation_gdf = samplelocation_gdf[~samplelocation_gdf['sulfur'].isna()]

# load the national huc file
huc = gpd.read_file(r"Z:\ek559\sdwa_violations\WBD_HUC12_CONUS_pulled10262020\WBD_HUC12_CONUS_pulled10262020.shp")
huc = huc.to_crs("EPSG:5070")

# load the minehucs and upstream hucs
mines = pd.read_csv("Z:/ek559/mining_wq/clean_data/coal_huc_prod.csv", dtype={'huc12': str}, low_memory=False)
# remove mines that are missing both production and huc data
# keep a dataframe with all the unique hucs associated with mining and where they flow
mines = mines[~mines['huc12'].isna()]
mines = mines[~mines['production_short_tons_coal'].isna()]
mines['minehuc'] = 'mine'
minehuc = mines[['minehuc','huc12']]
minehuc = minehuc.drop_duplicates()

mines = mines.merge(huc, on='huc12', how='inner')

minehuc = mines[['minehuc','huc12','tohuc']]
minehuc = minehuc.drop_duplicates()
# 1116 hucs

#######################
# Upstream of mine hucs
#######################
# upstream hucs flow into mine hucs and do not have a mine upstream
# tohuc in the parent huc file is the huc downstream
# A huc is upstream of a minehuc if its tohuc is a minehuc code
# 557 such hucs
upminehuc = huc[huc['tohuc'].isin(minehuc.huc12)]
upminehuc = upminehuc[~upminehuc['huc12'].isin(minehuc.huc12)]
upminehuc = upminehuc[~upminehuc['huc12'].isin(minehuc.tohuc)]
upminehuc['minehuc'] = 'upstream_of_mine'
upminehuc = upminehuc[['minehuc', 'huc12', 'tohuc']]

# hucs upstream of the mine upstream hucs
# from the universe of hucs find the hucs 
# which are upstream of the hucs in upminehuc
huc_up = huc
huc_up = huc_up.rename(columns={'huc12': 'fromhuc'})
huc_up = huc_up[['fromhuc','tohuc']]
huc_up = huc_up.rename(columns={'tohuc': 'huc12'})
upminehuc = upminehuc.merge(huc_up, how='left')

# remove upstream hucs that have mining in them or are downtream of a mine
both_updown = list((set(upminehuc['fromhuc']) & set(minehuc['huc12'])) | 
                   (set(upminehuc['huc12']) & set(minehuc['huc12'])))
upminehuc = upminehuc[~upminehuc['huc12'].isin(both_updown)]

#################
# Downstream HUCS
#################
# downstream hucs are downstream of a coal huc
# and have no coal produced inside them
downstreamcoal = minehuc
downstreamcoal = downstreamcoal.drop(['huc12', 'minehuc'], axis=1)
downstreamcoal = downstreamcoal.rename(columns={'tohuc': 'huc12'})
downstreamcoal['minehuc'] = 'downstream_of_mine'
downstreamcoal = downstreamcoal[~downstreamcoal['huc12'].isin(minehuc['huc12'])]
downstreamcoal = downstreamcoal[~downstreamcoal['huc12'].isin(upminehuc['huc12'])]
huc_up = huc
huc_up = huc_up.rename(columns={'huc12': 'fromhuc'})
huc_up = huc_up[['fromhuc','tohuc']]
huc_up = huc_up.rename(columns={'tohuc': 'huc12'})
downstreamcoal = downstreamcoal.merge(huc_up, how='left')

#####################
# Colocated mine hucs
#####################
# hucs upstream of the mine hucs
huc_up = huc
huc_up = huc_up.rename(columns={'huc12': 'fromhuc'})
huc_up = huc_up[['fromhuc', 'tohuc']]
huc_up = huc_up.rename(columns={'tohuc': 'huc12'})
minehuc = minehuc.merge(huc_up, how='left')

#######################################################
# Match master list of hucs to huc coal characteristics
#######################################################

allhucs = huc[huc['huc12'].isin(minehuc['huc12'])|
              huc['huc12'].isin(minehuc['fromhuc'])|
              huc['huc12'].isin(downstreamcoal['huc12'])|
              huc['huc12'].isin(downstreamcoal['fromhuc'])|
              huc['huc12'].isin(upminehuc['huc12'])|
              huc['huc12'].isin(upminehuc['fromhuc'])]

# Match coal samples to hucs
# Make buffer 
# with 50 km buffers you get 391 hucs
samplelocation_gdf["geometry"] = samplelocation_gdf.buffer(20000)
allhucs = allhucs.sjoin(samplelocation_gdf, how= "left", predicate="intersects")
allhucs = pd.DataFrame(allhucs)
allhucs = allhucs[['huc12','sulfur','btu']]
allhucs.sulfur = allhucs.sulfur.astype(float)
allhucs.btu = allhucs.btu.astype(float)
huc_sulfur = allhucs.groupby(['huc12'])['sulfur'].mean().reset_index()
huc_btu = allhucs.groupby(['huc12'])['btu'].mean().reset_index()
allhucs = pd.merge(huc_btu, huc_sulfur,
                   on = ['huc12'])
allhucs[['btu', 'sulfur']] = allhucs[['btu', 'sulfur']].fillna(0)

####################
# match to upminehuc
####################

def matchsulfurbtu(dset):
    temp_colocated_charac = allhucs[allhucs['huc12'].isin(dset['huc12'])]
    temp_upstream_charac = allhucs[allhucs['huc12'].isin(dset['fromhuc'])]
    temp_colocated_charac = temp_colocated_charac.rename(columns={'btu':'btu_colocated',
                                                                  'sulfur': 'sulfur_colocated'})
    temp_colocated_charac = temp_colocated_charac[['huc12','btu_colocated','sulfur_colocated']]
    temp_upstream_charac = temp_upstream_charac.rename(columns={'btu':'btu_upstream',
                                                                'sulfur': 'sulfur_upstream',
                                                                'huc12':'fromhuc'})
    temp_upstream_charac = temp_upstream_charac[['btu_upstream','fromhuc','sulfur_upstream']]
    dset = dset.merge(temp_colocated_charac, how = 'left')
    dset = dset.merge(temp_upstream_charac, how = 'left')
    return dset

upminehuc = matchsulfurbtu(upminehuc)
minehuc = matchsulfurbtu(minehuc)
downstreamcoal = matchsulfurbtu(downstreamcoal)

fin = pd.concat([upminehuc, minehuc, downstreamcoal])

fin.to_csv("Z:/ek559/mining_wq/clean_data/huc_coal_charac_geom_match.csv")

###############################################
# Merge coal production to coal characteristics
###############################################

# Merge the coal characteristics which are at the huc level
df_years = pd.DataFrame({'year': list(range(1983, 2025))})
hucsulfur = fin.merge(df_years, how='cross')
huc_prod = pd.read_csv("Z:/ek559/mining_wq/clean_data/coal_huc_prod.csv", dtype={'huc12': str})

##############################################
# downstream colocated and upstream production
##############################################
fin_dstream = hucsulfur[hucsulfur['minehuc']=='downstream_of_mine']
# colocated coal production
dstream_colocate = huc_prod[huc_prod['huc12'].isin(fin_dstream['huc12'])]
dstream_colocate.rename(columns={'production_short_tons_coal': 'production_short_tons_coal_colocated',
                                                    'num_coal_mines': 'num_coal_mines_colocated'},
                                                    inplace=True)
fin_dstream = fin_dstream.merge(dstream_colocate, how='left')
# upstream of downstream coal production
# we rename dstream huc12 col fromhuc since fin_dstream relates to upstream hucs with fromhuc col
dstream_upstream = huc_prod[huc_prod['huc12'].isin(fin_dstream['fromhuc'])]
dstream_upstream.rename(columns={'production_short_tons_coal': 'production_short_tons_coal_upstream',
                                                    'num_coal_mines': 'num_coal_mines_upstream',
                                                    'huc12': 'fromhuc'},
                                                    inplace=True)
fin_dstream = fin_dstream.merge(dstream_upstream, how='left')

#############################
# mining colocated production
#############################

fin_mine = hucsulfur[hucsulfur['minehuc']=='mine']
# colocated coal production
mine_colocate = huc_prod[huc_prod['huc12'].isin(fin_mine['huc12'])]
mine_colocate.rename(columns={'production_short_tons_coal': 'production_short_tons_coal_colocated',
                              'num_coal_mines': 'num_coal_mines_colocated'},
                              inplace=True)
fin_mine = fin_mine.merge(mine_colocate, on = ['huc12', 'year'], how='left')
# upstream of mine huc coal production
mine_upstream = huc_prod[huc_prod['huc12'].isin(fin_mine['fromhuc'])]
mine_upstream.rename(columns={'production_short_tons_coal': 'production_short_tons_coal_upstream',
                              'num_coal_mines': 'num_coal_mines_upstream',
                              'huc12': 'fromhuc'},
                              inplace=True)
fin_mine = fin_mine.merge(mine_upstream, how='left')

##########################################
# upstream production
##########################################

fin_upstreammine = hucsulfur[hucsulfur['minehuc']=='upstream_of_mine']
#fin_upstreammine['production_short_tons_coal_colocated']
# upstream coal production
upstreammine = huc_prod[huc_prod['huc12'].isin(fin_upstreammine['huc12'])]
upstreammine.rename(columns={'production_short_tons_coal': 'production_short_tons_coal_colocated',
                                 'num_coal_mines': 'num_coal_mines_colocated'}, inplace=True)
fin_upstreammine = fin_upstreammine.merge(upstreammine, how='left')
# upstream of mine huc coal production
mine_upstream = huc_prod[huc_prod['huc12'].isin(fin_upstreammine['fromhuc'])]
mine_upstream.rename(columns={'production_short_tons_coal': 'production_short_tons_coal_upstream',
                              'num_coal_mines': 'num_coal_mines_upstream',
                              'huc12': 'fromhuc'}, inplace=True)
fin_upstreammine = fin_upstreammine.merge(mine_upstream, how='left')

############################################################
# concat production from upstream, colocated, and downstream
############################################################

fin = pd.concat([fin_dstream, fin_mine, fin_upstreammine])

prod_cols = ['production_short_tons_coal_upstream', 'num_coal_mines_upstream',
                  'production_short_tons_coal_colocated', 'num_coal_mines_colocated']

fin[prod_cols] = fin[prod_cols].fillna(0)

############################################################
# collapse down to the huc-year level
# ##########################################################
# upstream coal production is the average of the
# coal produced in the huc12's directly upstream

fin = fin.groupby(['huc12', 'minehuc', 'year'], as_index=False).agg(btu_colocated=('btu_colocated', 'mean'),
                                                         sulfur_colocated=('sulfur_colocated', 'mean'),
                                                         btu_upstream=('btu_upstream', 'mean'),
                                                         sulfur_upstream=('sulfur_upstream', 'mean'),
                                                         production_short_tons_coal_colocated=('production_short_tons_coal_colocated', 'mean'),
                                                         num_coal_mines_colocated=('num_coal_mines_colocated', 'mean'),
                                                         production_short_tons_coal_upstream=('production_short_tons_coal_upstream', 'mean'),
                                                         num_coal_mines_upstream=('num_coal_mines_upstream', 'mean'))

fin['sulfur_unified'] = np.where((fin['sulfur_upstream']!=0) & (fin['sulfur_colocated']!=0),
                                 fin[['sulfur_upstream', 'sulfur_colocated']].mean(axis=1),
                                 fin[['sulfur_upstream', 'sulfur_colocated']].max(axis=1))

fin['btu_unified'] = np.where((fin['btu_upstream']!=0) & (fin['btu_colocated']!=0),
                                 fin[['btu_upstream', 'btu_colocated']].mean(axis=1),
                                 fin[['btu_upstream', 'btu_colocated']].max(axis=1))

fin['num_coal_mines_unified'] = np.where((fin['num_coal_mines_upstream']!=0) & (fin['num_coal_mines_colocated']!=0),
                                 fin[['num_coal_mines_upstream', 'num_coal_mines_colocated']].mean(axis=1),
                                 fin[['num_coal_mines_upstream', 'num_coal_mines_colocated']].max(axis=1))

fin['production_short_tons_coal_unified'] = np.where((fin['production_short_tons_coal_upstream']!=0) & (fin['production_short_tons_coal_colocated']!=0),
                                 fin[['production_short_tons_coal_upstream', 'production_short_tons_coal_colocated']].mean(axis=1),
                                 fin[['production_short_tons_coal_upstream', 'production_short_tons_coal_colocated']].max(axis=1))

fin.to_parquet("Z:/ek559/mining_wq/clean_data/huc_coal_charac_geom_match.parquet")