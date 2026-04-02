import pandas as pd

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

mines = mines[mines['huc12'].isin(facility_huc)]
mines = mines.drop_duplicates(subset=['mine_id'])
mines = mines[['mine_id', 'huc12', 'latitude', 'longitude']]
mines.to_csv('Z:/ek559/mining_wq/clean_data/mines_in_pws_huc12s.csv')