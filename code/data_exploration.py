import pandas as pd
import geopandas as gpd
from matplotlib import pyplot as plt

pws = pd.read_excel(r"Z:\ek559\water_instrument\cws_intake_hucs\PWS_Loctations_HUC12_A_I_2022Q2.xlsx")
ut = gpd.read_file(r"Z:\ek559\downloads\mrds-trim\mrds-trim.shp")
bingham = ut[ut["SITE_NAME"].str.startswith("Bingham")]
bingham = bingham[bingham["CODE_LIST"].str.contains("CU")]
huc = gpd.read_file(r"Z:\ek559\downloads\Nationalwatersh\WBD_HUC12_CONUS_pulled10262020\WBD_HUC12_CONUS_pulled10262020\WBD_HUC12_CONUS_pulled10262020.shp")
bingham = bingham.to_crs(huc.crs)
minehuc = gpd.overlay(huc, bingham, how="intersection", keep_geom_type=False)
minehuc.huc12 = minehuc.huc12.astype(str)
pws.HUC_12 = pws.HUC_12.astype(str)
cwsintakemining = minehuc.merge(pws, left_on = 'huc12', right_on = 'HUC_12', how = 'inner')
cwsintakemining.PWSID.unique()
violation = pd.read_csv(r"Z:\ek559\sdwa_violations\SDWA_latest_downloads\SDWA_VIOLATIONS_ENFORCEMENT.csv")
pwsminehucviolation = cwsintakemining.merge(violation, left_on = 'PWSID', right_on = 'PWSID', how = 'inner')
pwsminehucviolation[['PWSID', 'WATER_TYPE_CODE', 'VIOLATION_CATEGORY_CODE', 'CONTAMINANT_CODE']]
pwsminehucviolation.VIOLATION_CATEGORY_CODE.unique()
pwsminehucviolation.CONTAMINANT_CODE.unique()
mcl = pwsminehucviolation[pwsminehucviolation['VIOLATION_CATEGORY_CODE']=='MCL']
mcl.CONTAMINANT_CODE.unique()