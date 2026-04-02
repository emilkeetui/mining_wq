import pandas as pd
import geopandas as gpd
import matplotlib.pyplot as plt
from matplotlib.patches import Patch
import pygris
import numpy as np

# Sample with coal hucs and adjacent to coal hucs
# mining -> huc12 <- pws
# match made on the huc between mines and pws's
# the pws's to keep will be those who draw from a huc either 
# in a mining huc (treated)
# or those upstream and adjacent to a mining huc

# Process: load mining huc's and get a list of hucs upstream and adjacent to those
mines = pd.read_csv("Z:/ek559/mining_wq/clean_data/coal_mine_prod.csv", dtype={'mine_id': str, 'huc12': str}, low_memory=False)
# remove mines that are missing both production and huc data
mines = mines[~mines['latitude'].isna()]
mines = mines[~mines['production_short_tons'].isna()]
mines['minehuc'] = 'mine'
minehuc = mines[['minehuc','huc12','tohuc']]
# keep a dataframe with all the unique hucs associated with mining and where they flow
# 1116 hucs
minehuc = minehuc.drop_duplicates()

# load the national huc file
huc = gpd.read_file(r"Z:\ek559\sdwa_violations\WBD_HUC12_CONUS_pulled10262020\WBD_HUC12_CONUS_pulled10262020.shp")
# upstream hucs flow into mine hucs and do not have a mine upstream
# 557 such hucs
upminehuc = huc[huc['tohuc'].isin(minehuc.huc12)]
upminehuc = upminehuc[~upminehuc['huc12'].isin(minehuc.huc12)]
upminehuc['minehuc'] = 'upstream_of_mine'
upminehuc = upminehuc[['minehuc', 'huc12', 'tohuc']]
# concat the huc list of upstream and mining hucs
huclist = pd.concat([upminehuc, minehuc], ignore_index=True)


### We cant match pwsid-facility to violation we can only match violation to pwsid
### Facility has useful information which we need to condense down to pwsid
### Facility and intake data are contemporary - so matching pwsid to facility or intake to
### determine which to keep are equivalent

# violation data have pwsid and identifies a facility id 5.6 million out of 14.6 million observations
# need to use pwsid because not enough matches made with violation and pws characteristic data also using facility_id
violation = pd.read_csv("Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.csv", low_memory=False)
violation['NON_COMPL_PER_BEGIN_DATE'] = pd.to_datetime(violation['NON_COMPL_PER_BEGIN_DATE'])
violation['VIOL_FIRST_REPORTED_DATE'] = pd.to_datetime(violation['VIOL_FIRST_REPORTED_DATE'])
violation['ENF_FIRST_REPORTED_DATE'] = pd.to_datetime(violation['ENF_FIRST_REPORTED_DATE'])
violation = violation[~((violation['NON_COMPL_PER_BEGIN_DATE'].isna()) & (violation['VIOL_FIRST_REPORTED_DATE'].isna()))]
violation['year'] = violation['NON_COMPL_PER_BEGIN_DATE'].dt.year

# pub water system is only identified by pwsid and no facility id variable
# can link aggregate pub water system to all facilities through the pwsid
water_sys = pd.read_csv("Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_PUB_WATER_SYSTEMS.csv", low_memory=False)
water_sys = water_sys.drop(columns=['PRIMACY_AGENCY_CODE', 'EPA_REGION', 'SEASON_BEGIN_DATE', 
                                    'SEASON_END_DATE','POP_CAT_2_CODE', 'POP_CAT_3_CODE', 
                                    'POP_CAT_4_CODE', 'POP_CAT_5_CODE',
                                    'POP_CAT_11_CODE','SERVICE_CONNECTIONS_COUNT',
                                    'SUBMISSION_STATUS_CODE', 'ORG_NAME', 'ADMIN_NAME', 'EMAIL_ADDR',
                                    'PHONE_NUMBER', 'PHONE_EXT_NUMBER', 'FAX_NUMBER', 'ALT_PHONE_NUMBER',
                                    'ADDRESS_LINE1', 'ADDRESS_LINE2','SEASONAL_STARTUP_SYSTEM'])
# CWS type PWS ie not transient
water_sys = water_sys[water_sys['PWS_TYPE_CODE']=='CWS']
# remove deactivated or inactive facilities
water_sys['PWS_DEACTIVATION_DATE'] = pd.to_datetime(water_sys['PWS_DEACTIVATION_DATE'])
water_sys = water_sys[
    (water_sys['PWS_DEACTIVATION_DATE'] >= "1983-01-01") |
    (water_sys['PWS_DEACTIVATION_DATE'].isna())
]
water_sys = water_sys.drop_duplicates()
df_years = pd.DataFrame({'year': list(range(1983, 2025))})
water_sys['year_pws_deactivated'] = water_sys['PWS_DEACTIVATION_DATE'].dt.year 
water_sys = water_sys.merge(df_years, how='cross')
water_sys = water_sys[~(water_sys['year_pws_deactivated'] < water_sys['year'])]

#one hot encode variables
water_sys['SOURCE_PROTECTION_year'] = pd.to_datetime(water_sys['SOURCE_PROTECTION_BEGIN_DATE']).dt.year
water_sys['SOURCE_WATER_PROTECTION_CODE'] = np.where(water_sys['SOURCE_PROTECTION_year']>water_sys['year'],
                                                     'N',
                                                     water_sys['SOURCE_WATER_PROTECTION_CODE'])
original_cols = water_sys[['SOURCE_WATER_PROTECTION_CODE', 'PRIMARY_SOURCE_CODE', 
                           'IS_WHOLESALER_IND', 'IS_SCHOOL_OR_DAYCARE_IND', 'IS_GRANT_ELIGIBLE_IND']].copy()
water_sys = pd.get_dummies(water_sys,
                           columns=['SOURCE_WATER_PROTECTION_CODE', 'PRIMARY_SOURCE_CODE', 
                                    'IS_WHOLESALER_IND', 'IS_SCHOOL_OR_DAYCARE_IND', 'IS_GRANT_ELIGIBLE_IND'],
                           dummy_na=True,
                           dtype=int)
water_sys = pd.concat([water_sys, original_cols], axis=1)

# sdwa facilities list
facility = pd.read_csv("Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_FACILITIES.csv", low_memory=False)
# intake always have a facility id and have pwsid
intake = pd.read_excel("Z:/ek559/water_instrument/cws_intake_hucs/PWS_Loctations_HUC12_A_I_2022Q2.xlsx",
                       dtype={'HUC_12': str, 'FACILITY_ID': str})
intake = intake[['HUC_12', 'PWSID', 'FACILITY_ID']]
intake = intake.rename(columns = {'HUC_12':'huc12'})
intake = intake.drop_duplicates()
facility = facility.merge(intake, on = ['PWSID', 'FACILITY_ID'], how='inner')
facility_huc = facility
facility = facility.merge(huclist, on = 'huc12', how='inner')
# remove pwsid's that get their water from both an upstream and a downstream huc
# Step 1: Identify PWSIDs that have both 'mine' and 'upstream_of_mine'
minehuc_types = facility.groupby('PWSID')['minehuc'].unique()
pwsids_to_drop = minehuc_types[minehuc_types.apply(lambda x: 'mine' in x and 'upstream_of_mine' in x)].index
# Step 2: Filter out those PWSIDs from the original DataFrame
facility = facility[~facility['PWSID'].isin(pwsids_to_drop)]

# uphuc
pwsminehucs = facility[facility['minehuc']=='mine']['huc12'].unique()
pwsupstreamminehucs = facility[facility['minehuc']=='upstream_of_mine']['huc12'].unique()

# add facilities from pwsid's matched to upstream and downstream
facility_pws = facility['PWSID'].unique()
facility_pws = facility_huc[facility_huc['PWSID'].isin(facility_pws)]
facility_pws = facility_pws[~facility_pws.set_index(['PWSID', 'FACILITY_ID']).index.isin(
    facility.set_index(['PWSID', 'FACILITY_ID']).index)]
facility = pd.concat([facility, facility_pws], axis=0)

# remove deactivated or inactive facilities
facility['FACILITY_DEACTIVATION_DATE'] = pd.to_datetime(facility['FACILITY_DEACTIVATION_DATE'])
facility = facility[
    (facility['FACILITY_DEACTIVATION_DATE'] >= "1983-01-01") |
    (facility['FACILITY_DEACTIVATION_DATE'].isna())
]
facility = facility.drop_duplicates()
facility['year_deactivated'] = facility['FACILITY_DEACTIVATION_DATE'].dt.year

# create this as a time series dataset
facility = facility.merge(df_years, how='cross')

# remove facilities where the year of deactivation is 
# less than the year variable, 
# leave if year of deactivation is na
facility = facility[~(facility['year_deactivated'] < facility['year'])]

# number of facilities 
facility['num_facilities'] = facility.groupby(['PWSID', 'year'])['FACILITY_ID'].transform('count')
#number of hucs
facility['num_hucs'] = facility.groupby(['PWSID', 'year'])['huc12'].transform('count')

# now remove all non-upstream and non-downstream hucs
# using the availability code to determine if the water 
# drawn from that huc was permanent or emergency
facility = facility[~facility['minehuc'].isna()]

# Generate one-hot encoded columns
facility = pd.get_dummies(facility,
                          columns=['FACILITY_ACTIVITY_CODE', 
                                    'FACILITY_TYPE_CODE', 
                                    'IS_SOURCE_IND', 
                                    'WATER_TYPE_CODE',
                                    'SELLER_TREATMENT_CODE',
                                    'FILTRATION_STATUS_CODE', 
                                    'IS_SOURCE_TREATED_IND', 
                                    'AVAILABILITY_CODE',
                                    'minehuc'],
                          dummy_na=True,
                          dtype=int)
# save just the facility data
facility.to_csv("Z:/ek559/mining_wq/clean_data/cws_data/sdwa_facilities.csv", index=False)

# Merge the coal characteristics which are at the huc level
hucsulfur = pd.read_csv("Z:/ek559/mining_wq/clean_data/huc_coal_charac_geom_match.csv", dtype={'huc12': str})
hucsulfur.drop('Unnamed: 0', axis=1, inplace=True)
df_years = pd.DataFrame({'year': list(range(1983, 2025))})
hucsulfur = hucsulfur.merge(df_years, how='cross')
huc_prod = pd.read_csv("Z:/ek559/mining_wq/clean_data/coal_huc_prod.csv", dtype={'huc12': str})
fin = pd.merge(hucsulfur, huc_prod, on=['huc12', 'year'], how='left')
fin[['production_short_tons_coal', 'num_coal_mines']] = fin[['production_short_tons_coal', 'num_coal_mines']].fillna(0)
fin = fin[fin['huc12'].isin(facility['huc12'].unique())]
coaldata = fin[fin['minehuc']=='mine']
coaldata['post95'] = np.where(coaldata['year']>=1995,
                              1,
                              0)
coaldata.to_csv("Z:/ek559/mining_wq/clean_data/prod_sulfur.csv", index=False)
fin = fin[['huc12','minehuc','year','btu', 'sulfur', 'production_short_tons_coal', 'num_coal_mines']]

# take facility down to pws-huc-year level
onelvldwn = facility.drop_duplicates(subset=['PWSID','huc12','year'])
onelvldwn = onelvldwn.merge(fin, how='left')
onelvldwn = onelvldwn.groupby(['PWSID', 'year'])[['btu', 'sulfur', 'production_short_tons_coal', 'num_coal_mines']].mean().reset_index()

#reduce to pws level
columns_to_max = [
    'FACILITY_ACTIVITY_CODE_A', 'FACILITY_ACTIVITY_CODE_nan', 'FACILITY_TYPE_CODE_IG',
    'FACILITY_TYPE_CODE_IN', 'FACILITY_TYPE_CODE_RS', 'FACILITY_TYPE_CODE_SP',
    'FACILITY_TYPE_CODE_WL', 'FACILITY_TYPE_CODE_nan', 'IS_SOURCE_IND_Y',
    'IS_SOURCE_IND_nan', 'WATER_TYPE_CODE_GU', 'WATER_TYPE_CODE_GW',
    'WATER_TYPE_CODE_SW', 'WATER_TYPE_CODE_nan', 'AVAILABILITY_CODE_E',
    'AVAILABILITY_CODE_I', 'AVAILABILITY_CODE_O', 'AVAILABILITY_CODE_P',
    'AVAILABILITY_CODE_S', 'AVAILABILITY_CODE_nan', 'SELLER_TREATMENT_CODE_nan',
    'FILTRATION_STATUS_CODE_FIL', 'FILTRATION_STATUS_CODE_MIF',
    'FILTRATION_STATUS_CODE_SAF', 'FILTRATION_STATUS_CODE_nan',
    'IS_SOURCE_TREATED_IND_N', 'IS_SOURCE_TREATED_IND_Y',
    'IS_SOURCE_TREATED_IND_nan', 'num_hucs', 'num_facilities',
    'minehuc_mine', 'minehuc_upstream_of_mine', 'minehuc_nan'
]
columns_to_mean = ['btu', 'sulfur','production_short_tons_coal', 'num_coal_mines']

# collapsing facility to pwsid-year level 
# not going to collapse to the pwsid-huc12-year level because we
# cant match violations to huc12's
facility = facility.groupby(['PWSID', 'year'])[columns_to_max].max().reset_index()
facility = facility.merge(onelvldwn, how='left')

# merge to water system characteristics
# only keep pwsid-years where there is an active facility we can link to 
# an intake source. Intake is a modern dataset but if we can match intake to
# facility id that was active in early part of the data then we reduce that concern
water_sys = water_sys.merge(facility, on = ['PWSID','year'], how = 'inner')

#num rows when matching pws and facility id to violation
# only 63 violations
#viol_pws_facid = violation.merge(water_sys, on = ['PWSID', 'FACILITY_ID'], how='inner'
# num rows when matching pws to violation
# 282703 violations - need to match violations by pwsid only not facility
# 296475 violations if water_sys is at the pwsid-huc12 level and there are a 
# few pwsid's with more than one huc12 intake
#viol_pws = violation.merge(water_sys, on = ['PWSID'], how='right')
#viol_pws.to_csv("Z:/ek559/mining_wq/clean_data/cws_data/violation_match.csv", index=False)
violation_keep = violation[violation['PWSID'].isin(water_sys.PWSID)]
violation_keep.to_csv("Z:/ek559/mining_wq/clean_data/cws_data/violation_predrop.csv", index=False)

# one hot encode enforcement variables
# create dataframe at the pwsid-violation-enforcement-yearofenforcement level then merge to the 
# final dataframe and match enforcement year to final dataframe year
enf_keep = pd.get_dummies(violation_keep,
                          columns=['ENFORCEMENT_ACTION_TYPE_CODE', 
                                   'ENF_ACTION_CATEGORY', 
                                   'ENF_ORIGINATOR_CODE'],
                          dummy_na=True,
                          dtype=int)
enf_keep['ENFORCEMENT_DATE']=pd.to_datetime(enf_keep['ENFORCEMENT_DATE'])
enf_keep['year'] = enf_keep['ENFORCEMENT_DATE'].dt.year
enf_keep = enf_keep.groupby(['PWSID','VIOLATION_ID','year'])[
       ['ENFORCEMENT_ACTION_TYPE_CODE_EF!',
       'ENFORCEMENT_ACTION_TYPE_CODE_EF-', 'ENFORCEMENT_ACTION_TYPE_CODE_EF/',
       'ENFORCEMENT_ACTION_TYPE_CODE_EF<', 'ENFORCEMENT_ACTION_TYPE_CODE_EFJ',
       'ENFORCEMENT_ACTION_TYPE_CODE_EFL', 'ENFORCEMENT_ACTION_TYPE_CODE_EFN',
       'ENFORCEMENT_ACTION_TYPE_CODE_EIA', 'ENFORCEMENT_ACTION_TYPE_CODE_EID',
       'ENFORCEMENT_ACTION_TYPE_CODE_EIE', 'ENFORCEMENT_ACTION_TYPE_CODE_EIF',
       'ENFORCEMENT_ACTION_TYPE_CODE_EO+', 'ENFORCEMENT_ACTION_TYPE_CODE_EO0',
       'ENFORCEMENT_ACTION_TYPE_CODE_EO6', 'ENFORCEMENT_ACTION_TYPE_CODE_EO7',
       'ENFORCEMENT_ACTION_TYPE_CODE_EOX', 'ENFORCEMENT_ACTION_TYPE_CODE_SF%',
       'ENFORCEMENT_ACTION_TYPE_CODE_SF3', 'ENFORCEMENT_ACTION_TYPE_CODE_SF4',
       'ENFORCEMENT_ACTION_TYPE_CODE_SF5', 'ENFORCEMENT_ACTION_TYPE_CODE_SFG',
       'ENFORCEMENT_ACTION_TYPE_CODE_SFH', 'ENFORCEMENT_ACTION_TYPE_CODE_SFJ',
       'ENFORCEMENT_ACTION_TYPE_CODE_SFK', 'ENFORCEMENT_ACTION_TYPE_CODE_SFL',
       'ENFORCEMENT_ACTION_TYPE_CODE_SFM', 'ENFORCEMENT_ACTION_TYPE_CODE_SFN',
       'ENFORCEMENT_ACTION_TYPE_CODE_SFO', 'ENFORCEMENT_ACTION_TYPE_CODE_SFQ',
       'ENFORCEMENT_ACTION_TYPE_CODE_SFR', 'ENFORCEMENT_ACTION_TYPE_CODE_SFT',
       'ENFORCEMENT_ACTION_TYPE_CODE_SFV', 'ENFORCEMENT_ACTION_TYPE_CODE_SIA',
       'ENFORCEMENT_ACTION_TYPE_CODE_SIB', 'ENFORCEMENT_ACTION_TYPE_CODE_SIC',
       'ENFORCEMENT_ACTION_TYPE_CODE_SID', 'ENFORCEMENT_ACTION_TYPE_CODE_SIE',
       'ENFORCEMENT_ACTION_TYPE_CODE_SIF', 'ENFORCEMENT_ACTION_TYPE_CODE_SII',
       'ENFORCEMENT_ACTION_TYPE_CODE_SO+', 'ENFORCEMENT_ACTION_TYPE_CODE_SO0',
       'ENFORCEMENT_ACTION_TYPE_CODE_SO6', 'ENFORCEMENT_ACTION_TYPE_CODE_SO7',
       'ENFORCEMENT_ACTION_TYPE_CODE_SO8', 'ENFORCEMENT_ACTION_TYPE_CODE_SOX',
       'ENFORCEMENT_ACTION_TYPE_CODE_SOY', 'ENFORCEMENT_ACTION_TYPE_CODE_nan',
       'ENF_ACTION_CATEGORY_Formal', 'ENF_ACTION_CATEGORY_Informal',
       'ENF_ACTION_CATEGORY_Resolving', 'ENF_ACTION_CATEGORY_nan',
       'ENF_ORIGINATOR_CODE_F', 'ENF_ORIGINATOR_CODE_S',
       'ENF_ORIGINATOR_CODE_nan']].max().reset_index()

violation_keep = violation_keep.drop_duplicates(subset=['PWSID',
                                                        'VIOLATION_ID',
                                                        'NON_COMPL_PER_BEGIN_DATE',
                                                        'NON_COMPL_PER_END_DATE'])

# were violations ongoing over multiple years?
# if over multiple years then duplicate the violation over all years it was ongoing
violation_keep['viol_year_start'] = violation_keep['NON_COMPL_PER_BEGIN_DATE'].dt.year
violation_keep['NON_COMPL_PER_END_DATE'] = pd.to_datetime(
    violation_keep['NON_COMPL_PER_END_DATE'],
    errors='coerce'
)
violation_keep['viol_year_end'] = violation_keep['NON_COMPL_PER_END_DATE'].dt.year
violation_keep['CALCULATED_RTC_DATE'] = pd.to_datetime(violation_keep['CALCULATED_RTC_DATE'])
violation_keep['viol_year_end'] = np.where((~violation_keep.CALCULATED_RTC_DATE.isna()) & (violation_keep['viol_year_end']!=violation_keep['NON_COMPL_PER_END_DATE'].dt.year),
                                           violation_keep['NON_COMPL_PER_END_DATE'].dt.year,
                                           violation_keep['viol_year_end'])
violation_keep['multi_year_viol'] = np.where(violation_keep['viol_year_end']>violation_keep['viol_year_start'],
                                             1,
                                             0)

# List to store new rows
expanded_rows = []

# Iterate through the DataFrame
for _, row in violation_keep.iterrows():
    if row['multi_year_viol'] == 1:
        start_year = row['year']
        end_year = row['NON_COMPL_PER_END_DATE'].year
        for y in range(start_year, end_year + 1):
            new_row = row.copy()
            new_row['year'] = y
            expanded_rows.append(new_row)
    else:
        expanded_rows.append(row)
violation_keep_expanded = pd.DataFrame(expanded_rows)
violation_keep_expanded.to_csv("Z:/ek559/mining_wq/clean_data/cws_data/violation.csv", index=False)

violation_keep = violation_keep_expanded

# Match violation to pws
# the violations that arent matched occur in years where there were no pwsid-year observations
# this could occur because all pwsid facilities are shown to be deactivated before the violation occured
# THIS is at system-violation-year level
water_sys = water_sys.merge(violation_keep, how='left', on = ['PWSID', 'year'])

# make sys-year without a violation have a no_violation = 1 variable
water_sys['no_violation'] = np.where(water_sys['VIOLATION_ID'].isna(),
                                     1,
                                     0)

# get violation dummies
original_cols = water_sys[['VIOLATION_CATEGORY_CODE', 'IS_HEALTH_BASED_IND', 
                           'IS_MAJOR_VIOL_IND', 'VIOL_ORIGINATOR_CODE']].copy()
water_sys = pd.get_dummies(water_sys,
                           columns=['VIOLATION_CATEGORY_CODE', 'IS_HEALTH_BASED_IND', 
                                   'IS_MAJOR_VIOL_IND', 'VIOL_ORIGINATOR_CODE'],
                           dummy_na=True,
                           dtype=int)
water_sys = pd.concat([water_sys, original_cols], axis=1)
water_sys['multi_year_viol'] = water_sys['multi_year_viol'].fillna(0)

# merge the enforcement back to the final dataframe
water_sys = water_sys.merge(enf_keep, how='left', on = ['PWSID','VIOLATION_ID', 'year'])

water_sys['post95'] = np.where(water_sys['year']>=1995,
                         1,
                         0)
water_sys = pd.get_dummies(water_sys,
                           columns=['RULE_CODE', 'RULE_FAMILY_CODE'],
                           dummy_na=True,
                           dtype=int)
# Assuming your dataframe is called df
fin.columns = fin.columns.str.replace(r'\.0$', '', regex=True)

water_sys.to_csv("Z:/ek559/mining_wq/clean_data/cws_data/prod_vio_sulfur.csv")

# pws's that draw water from mine hucs
# plotting the upstream and downstream hucs with pws's
minehucpwsgpd = huc[huc['huc12'].isin(pwsminehucs)]
minehucpwsgpd = gpd.GeoDataFrame(minehucpwsgpd, geometry='geometry')
uphucpwsgpd = huc[huc['huc12'].isin(pwsupstreamminehucs)]
uphucpwsgpd = gpd.GeoDataFrame(uphucpwsgpd, geometry='geometry')

# Load and reproject contiguous US states
all_states = pygris.states(year=2010)
contiguous_states = all_states[~all_states['NAME'].isin(['Alaska', 'Hawaii', 'Puerto Rico'])]
contiguous_states.to_file("Z:/ek559/nys_algal_bloom/NYS algal bloom/census_data/contiguous_states.shp")
contiguous_states = contiguous_states.to_crs(minehucpwsgpd.crs)

fig, ax = plt.subplots()
contiguous_states.plot(ax=ax, color='white', edgecolor='black', linewidth=0.5)
minehucpwsgpd.plot(ax=ax, color='blue')
uphucpwsgpd.plot(ax=ax, color='red')

# Manually create legend handles
legend_elements = [
    Patch(facecolor='blue', edgecolor='blue', label='Containing Coal Mining'),
    Patch(facecolor='red', edgecolor='red', label='Upstream of Coal Mining')
]

# Add legend and axis labels
ax.legend(handles=legend_elements)
ax.set_title("CWS intake HUC12s which are upstream or contain a coal mines")
ax.axis('off')
plt.savefig("Z:/ek559/mining_wq/plots/data_cleaning/cws_updownstream_huc12s.png", dpi=900)
plt.close()