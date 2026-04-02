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

def year_share(df: pd.DataFrame) -> pd.DataFrame:
    findf = pd.DataFrame()
    # Ensure datetime dtype once
    df = df.copy()
    df = df.reset_index(drop=True)
    df['NON_COMPL_PER_BEGIN_DATE'] = pd.to_datetime(df['NON_COMPL_PER_BEGIN_DATE'], format='mixed')
    df['NON_COMPL_PER_END_DATE']   = pd.to_datetime(df['NON_COMPL_PER_END_DATE'], format='mixed')

    for row in df.index:
        print(f"{row} of {df.index.max()}")
        rowdf = pd.DataFrame()
        # a single row object for convenience
        r = df.loc[row]
        yeardiff = r.NON_COMPL_PER_END_DATE.year - r.NON_COMPL_PER_BEGIN_DATE.year

        for i in range(yeardiff + 1):
            rowtemp = df.loc[[row]].copy()  # one-row DataFrame

            if i == 0 and yeardiff == 0:
                # first (partial) year
                start = r.NON_COMPL_PER_BEGIN_DATE
                end = r.NON_COMPL_PER_END_DATE
                share = ((end - start).days) / 365
                year_val = start.year

            elif i == 0 and yeardiff > 0:
                # first (partial) year
                start = r.NON_COMPL_PER_BEGIN_DATE
                year_end = pd.to_datetime(str(start.year) + '-12-31')
                share = ((year_end - start).days) / 365
                year_val = start.year

            elif i == yeardiff:
                # last (partial) year
                end = r.NON_COMPL_PER_END_DATE
                year_start = pd.to_datetime(str(end.year) + '-01-01')
                share = ((end - year_start).days + 1) / 365
                year_val = end.year

            else:
                # full middle years
                y = r.NON_COMPL_PER_BEGIN_DATE.year + i
                share = 1
                year_val = y

            # Safe assignments using .loc
            rowtemp.loc[:, 'share_yr_violation'] = share
            rowtemp.loc[:, 'year'] = year_val

            rowdf = pd.concat([rowdf, rowtemp], ignore_index=True)

        findf = pd.concat([findf, rowdf], ignore_index=True)
    return findf

# load the national huc file
huc = gpd.read_file(r"Z:\ek559\sdwa_violations\WBD_HUC12_CONUS_pulled10262020\WBD_HUC12_CONUS_pulled10262020.shp")
# load the complete huc production file
huccoal = pd.read_parquet("Z:/ek559/mining_wq/clean_data/huc_coal_charac_geom_match.parquet")
huclist = huccoal[['huc12','minehuc']].drop_duplicates()

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
# match facilities to intake hucs
facility = facility.merge(intake, on = ['PWSID', 'FACILITY_ID'], how='inner')
facility_huc = facility
#match facilities to mining related hucs
facility = facility.merge(huclist, on = 'huc12', how = 'inner')

# remove pwsid's that get their water from both an upstream and a mine huc
# Step 1: Identify PWSIDs that have both 'mine' and 'upstream_of_mine'
minehuc_types = facility.groupby('PWSID')['minehuc'].unique()
pwsids_to_drop = minehuc_types[minehuc_types.apply(lambda x: 'mine' in x and 'upstream_of_mine' in x)].index
# Step 2: Filter out those PWSIDs from the original DataFrame
facility = facility[~facility['PWSID'].isin(pwsids_to_drop)]

# remove pwsid's that get their water from both an upstream and a downstream huc
# Step 1: Identify PWSIDs that have both 'downstream_of_mine' and 'upstream_of_mine'
minehuc_types = facility.groupby('PWSID')['minehuc'].unique()
pwsids_to_drop = minehuc_types[minehuc_types.apply(lambda x: 'downstream_of_mine' in x and 'upstream_of_mine' in x)].index
# Step 2: Filter out those PWSIDs from the original DataFrame
facility = facility[~facility['PWSID'].isin(pwsids_to_drop)]

# HUCs with facilities in them
pwsminehucs = facility[facility['minehuc']=='mine']['huc12'].unique()
pwsupstreamminehucs = facility[facility['minehuc']=='upstream_of_mine']['huc12'].unique()
pwsdownstreamminehucs = facility[facility['minehuc']=='downstream_of_mine']['huc12'].unique()

# add facilities from pwsid's matched to mine, upstream, and downstream, 
# which are not themselves in a huc associated with mining
facility_pws = facility['PWSID'].unique()
facility_pws = facility_huc[facility_huc['PWSID'].isin(facility_pws)]
# remove rows from facility_pws that are in facility
facility_pws = (
    facility_pws
      .merge(
          facility[['PWSID', 'FACILITY_ID']].drop_duplicates(),
          on=['PWSID', 'FACILITY_ID'], how='left', indicator=True
      )
      .query("_merge == 'left_only'")
      .drop(columns="_merge")
)
# now facility contains all facilities that are from pws's
# with any association to a mining huc. The PWS's that
# are associated with mining huc are only those that
# are associated with either mine and downstream or upstream
# there are no mine and upstream or downstream and upstream pws's
facility = pd.concat([facility, facility_pws], axis=0)

# remove pwsid's that receive water HUCs that are unidentified
# and/or a downstream or colocated HUC with mines
# Keep thosere downstream get their water from a source that isnt upstream both an upstream and a downstream huc
# Step 1: unique values per PWSID
minehuc_types = facility.groupby('PWSID')['minehuc'].unique()

def should_drop(x):
    # x is the array/list of unique values for one PWSID
    has_nan = any(pd.isna(v) for v in x)
    non_nan_vals = [v for v in x if not pd.isna(v)]
    # "anything other than upstream_of_mine"
    has_non_upstream = any(v != 'upstream_of_mine' for v in non_nan_vals)
    return has_nan and has_non_upstream

# Step 2: compute PWSIDs to drop and filter
pwsids_to_drop = minehuc_types[minehuc_types.apply(should_drop)].index
facility = facility[~facility['PWSID'].isin(pwsids_to_drop)]

# Recompute and inspect what's left
minehuc_types = facility.groupby('PWSID')['minehuc'].unique()
minehuc_types

# For display consistency: normalize NaNs to string 'nan'
def normalize_nan(seq):
    return [('nan' if pd.isna(v) else v) for v in seq]

# checks if removing was successful
unordered_sets = minehuc_types.apply(lambda x: frozenset(normalize_nan(x)))
unique_unordered_lists = [sorted(list(s)) for s in set(unordered_sets)]
unique_unordered_lists

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

# Merge the hucs that are have a pws intake
# Merge the coal characteristics which are at the huc level
fin = huccoal
fin = fin[fin['huc12'].isin(facility['huc12'].unique())]
fin['post95'] = np.where(fin['year']>=1995,
                         1,
                         0)

# Make a pws coal production dataframe that takes the average of all 
# huc level coal production associated with the pws intakes        
# extract the pws's from facility: drop to pws-huc-year level
onelvldwn = facility.drop_duplicates(subset=['PWSID','huc12','year'])
onelvldwn = onelvldwn.merge(fin, how='left')
# take it down to the pws-year level
onelvldwn = (
    onelvldwn
    .groupby(['PWSID', 'year'], as_index=False)
    .agg(
        btu_colocated=('btu_colocated', 'mean'),
        sulfur_colocated=('sulfur_colocated', 'mean'),
        btu_upstream=('btu_upstream', 'mean'),
        sulfur_upstream=('sulfur_upstream', 'mean'),
        production_short_tons_coal_colocated=('production_short_tons_coal_colocated', 'mean'),
        num_coal_mines_colocated=('num_coal_mines_colocated', 'mean'),
        production_short_tons_coal_upstream=('production_short_tons_coal_upstream', 'mean'),
        num_coal_mines_upstream=('num_coal_mines_upstream', 'mean'),
        num_coal_mines_unified=('num_coal_mines_unified', 'mean'),
        production_short_tons_coal_unified=('production_short_tons_coal_unified', 'mean'),
        btu_unified=('btu_unified', 'mean'),
        sulfur_unified=('sulfur_unified', 'mean')
    )
)

# collapsing facility to pwsid-year level 
# not going to collapse to the pwsid-huc12-year level because we
# cant match violations to huc12's
columns_to_max = [
    'num_facilities', 'num_hucs',
    'FACILITY_ACTIVITY_CODE_A', 'FACILITY_ACTIVITY_CODE_I',
    'FACILITY_ACTIVITY_CODE_nan', 'FACILITY_TYPE_CODE_IN',
    'FACILITY_TYPE_CODE_RS', 'FACILITY_TYPE_CODE_SP',
    'FACILITY_TYPE_CODE_WL', 'FACILITY_TYPE_CODE_nan', 'IS_SOURCE_IND_Y',
    'IS_SOURCE_IND_nan', 'WATER_TYPE_CODE_GU', 'WATER_TYPE_CODE_GW',
    'WATER_TYPE_CODE_SW', 'WATER_TYPE_CODE_nan',
    'SELLER_TREATMENT_CODE_nan', 'FILTRATION_STATUS_CODE_FIL',
    'FILTRATION_STATUS_CODE_MIF', 'FILTRATION_STATUS_CODE_SAF',
    'FILTRATION_STATUS_CODE_nan', 'IS_SOURCE_TREATED_IND_N',
    'IS_SOURCE_TREATED_IND_U', 'IS_SOURCE_TREATED_IND_Y',
    'IS_SOURCE_TREATED_IND_nan', 'AVAILABILITY_CODE_E',
    'AVAILABILITY_CODE_I', 'AVAILABILITY_CODE_O', 'AVAILABILITY_CODE_P',
    'AVAILABILITY_CODE_S', 'AVAILABILITY_CODE_nan',
    'minehuc_downstream_of_mine', 'minehuc_mine',
    'minehuc_upstream_of_mine', 'minehuc_nan'
]
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

# Make violation at the pwsid level using the rule family to determine the level
# interact violation category (mcl/mr) with rule_family_code (chemical/disinfect) with the
# type of enforcement
# then hot encode the individual and the interactions. This allows you to 
# collapse at the pwsid level and have a dependent variable for:
# did you have mcl violation in that year. Did you have an mcl-chemical violation in that year
# did you mcl-chemical violation lead to EFG (federal public notification issued)

violation_keep["rule_family"] = "no_violation"

violation_keep.loc[
    (violation_keep["RULE_FAMILY_CODE"] == 110) |
    (violation_keep["RULE_FAMILY_CODE"] == 120) |
    (violation_keep["RULE_FAMILY_CODE"] == 140),
    "rule_family"
] = "microbials"

violation_keep.loc[
    (violation_keep["RULE_FAMILY_CODE"] == 210) |
    (violation_keep["RULE_FAMILY_CODE"] == 220) |
    (violation_keep["RULE_FAMILY_CODE"] == 230),
    "rule_family"
] = "disinfectants_byproducts"

violation_keep.loc[
    (violation_keep["RULE_FAMILY_CODE"] == 310) |
    (violation_keep["RULE_FAMILY_CODE"] == 320) |
    (violation_keep["RULE_FAMILY_CODE"] == 330) |
    (violation_keep["RULE_FAMILY_CODE"] == 340) |
    (violation_keep["RULE_FAMILY_CODE"] == 350),
    "rule_family"
] = "chemicals"

violation_keep.loc[
    (violation_keep["RULE_FAMILY_CODE"] == 410) |
    (violation_keep["RULE_FAMILY_CODE"] == 420) |
    (violation_keep["RULE_FAMILY_CODE"] == 430),
    "rule_family"
] = "other"

# violation cat X rule family
violation_keep["violation_cat_rule_fam"] = (
    violation_keep["VIOLATION_CATEGORY_CODE"].astype(str) + 
    "_" + 
    violation_keep["rule_family"].astype(str)
)

# there are multiple observations at the pwsid, violation_id, non_compl_per_begin_date, and non_compl_per_end_date
# because a violation can receive multiple enforcement actions
violation_keep = violation_keep.drop_duplicates(subset=['PWSID',
                                                        'VIOLATION_ID',
                                                        'NON_COMPL_PER_BEGIN_DATE',
                                                        'NON_COMPL_PER_END_DATE'])

# one hot encode enforcement variables
# create dataframe at the pwsid-yearofenforcement level then merge to the 
# final dataframe and match enforcement year to final dataframe year

violation_keep = pd.get_dummies(violation_keep,
                          columns=["RULE_CODE",
                                   "VIOLATION_CATEGORY_CODE"],
                          dummy_na=True,
                          dtype=int)

# were violations ongoing over multiple years?
# if over multiple years then duplicate the violation over all years it was ongoing

# One-to-one rule codes
violation_keep["nitrates"] = 0
violation_keep.loc[violation_keep["RULE_CODE_331.0"] == 1, "nitrates"] = 1

violation_keep["arsenic"] = 0
violation_keep.loc[violation_keep["RULE_CODE_332.0"] == 1, "arsenic"] = 1

violation_keep["inorganic_chemicals"] = 0
violation_keep.loc[violation_keep["RULE_CODE_333.0"] == 1, "inorganic_chemicals"] = 1

violation_keep["radionuclides"] = 0
violation_keep.loc[violation_keep["RULE_CODE_340.0"] == 1, "radionuclides"] = 1

violation_keep["lead_copper_rule"] = 0
violation_keep.loc[violation_keep["RULE_CODE_350.0"] == 1, "lead_copper_rule"] = 1

# Non-mining violations (OR across multiple rule codes)
violation_keep["total_coliform"] = 0
violation_keep.loc[
    (violation_keep["RULE_CODE_110.0"] == 1) | (violation_keep["RULE_CODE_111.0"] == 1),
    "total_coliform"
] = 1

violation_keep["surface_ground_water_rule"] = 0
violation_keep.loc[
    (violation_keep["RULE_CODE_121.0"] == 1) |
    (violation_keep["RULE_CODE_140.0"] == 1) |
    (violation_keep["RULE_CODE_122.0"] == 1) |
    (violation_keep["RULE_CODE_123.0"] == 1),
    "surface_ground_water_rule"
] = 1

violation_keep["dbpr"] = 0
violation_keep.loc[
    (violation_keep["RULE_CODE_210.0"] == 1) |
    (violation_keep["RULE_CODE_220.0"] == 1) |
    (violation_keep["RULE_CODE_230.0"] == 1),
    "dbpr"
] = 1

violation_keep["voc"] = 0
violation_keep.loc[violation_keep["RULE_CODE_310.0"] == 1, "voc"] = 1

violation_keep["soc"] = 0
violation_keep.loc[violation_keep["RULE_CODE_320.0"] == 1, "soc"] = 1

violation_keep['mining_vio'] = np.where((violation_keep["nitrates"]==1)|(violation_keep["arsenic"]==1)|
                                        (violation_keep["inorganic_chemicals"]==1)|(violation_keep["radionuclides"]==1)|
                                        (violation_keep["lead_copper_rule"]),
                                        1,
                                        0)
violation_keep['non_mining_vio'] = np.where((violation_keep["soc"]==1)|(violation_keep["voc"]==1)|
                                            (violation_keep["surface_ground_water_rule"]==1)|(violation_keep["total_coliform"]==1)|
                                            (violation_keep["dbpr"]),
                                            1,
                                            0)

# make the share of the year in violation

# in documentation NON_COMPL_PER_END_DATE is null when the violation is ongoing
# There are no null values but there are 2000 values of this kind '--->'
# I treat '--->' as null and replace them with 12/31/2024 since 2024 is the most 
# recent year of data.

violation_keep['NON_COMPL_PER_END_DATE'] = np.where(violation_keep['NON_COMPL_PER_END_DATE'] == '--->',
                                                    '12-31-2024',
                                                    violation_keep['NON_COMPL_PER_END_DATE'])

violation_keep = year_share(violation_keep)

for vio_var in ['voc','soc','dbpr','surface_ground_water_rule','total_coliform',
                'lead_copper_rule','radionuclides','inorganic_chemicals',
                'arsenic','nitrates']:
    violation_keep[f"{vio_var}_share"] = violation_keep[vio_var] * violation_keep['share_yr_violation']
    violation_keep[f"{vio_var}_MCL_share"] = violation_keep[f"{vio_var}_share"]*violation_keep['VIOLATION_CATEGORY_CODE_MCL']
    violation_keep[f"{vio_var}_MR_share"] = violation_keep[f"{vio_var}_share"]*violation_keep['VIOLATION_CATEGORY_CODE_MR']
    violation_keep[f"{vio_var}_TT_share"] = violation_keep[f"{vio_var}_share"]*violation_keep['VIOLATION_CATEGORY_CODE_TT']
violation_keep = violation_keep[violation_keep['share_yr_violation']>=0]

violation_keep.to_csv("Z:/ek559/mining_wq/clean_data/cws_data/violation.csv", index=False)


# Collapse to the PWSID year level
# at the PWSID and year level there are 
# multiple RULE_CODE violations which means 
# aggregating them at that level means 
# that they arent mutually exclusive
# so making one variable will doesnt work
# at the pwsid-year-violation id level
# the violations are unique.

columns_groupby = [col for col in violation_keep.columns if col.startswith(('VIOLATION_CATEGORY_CODE',
                                                                            'nitrates','arsenic', 
                                                                            'inorganic_chemicals', 'radionuclides', 
                                                                            'lead_copper_rule','total_coliform', 
                                                                            'surface_ground_water_rule', 'dbpr', 
                                                                            'voc', 'soc',
                                                                            'RULE_CODE'))]

# remove NaNs, normalize them first
violation_keep['mining_vio'] = violation_keep['mining_vio'].fillna(0).astype(int)
violation_keep['non_mining_vio'] = violation_keep['non_mining_vio'].fillna(0).astype(int)

# collapse the rows down to the PWSID-year level, taking the maximum value for each
# violation variable in each year. num_mining_violations and num_non_mining_violations
# do not always equal num_violations because there are some violations
# that are neither. But mining_vio and non_mining_vio are the count of violations
# that correspond to the 8 violation family types in the primary analysis

violation_keep =    (violation_keep.groupby(['PWSID', 'year'])
                    .agg(**{col: ('{}'.format(col), 'max') for col in columns_groupby},
                        
                    # total rows in the group
                    num_violations=('PWSID', 'size'),

                    # counts of violations (sum works because flags are 0/1)
                    num_mining_violations=('mining_vio', 'sum'),
                    num_non_mining_violations=('non_mining_vio', 'sum'))
                    .reset_index())

# Match violation to pws
# THIS is at system-year level
print(water_sys.columns)
water_sys = water_sys.merge(violation_keep, how='left', on = ['PWSID', 'year'])
print(water_sys.columns)

water_sys['post95'] = np.where(water_sys['year']>=1995,
                         1,
                         0)

water_sys.OWNER_TYPE_CODE = water_sys.OWNER_TYPE_CODE.fillna('NA')
water_sys.year_pws_deactivated = water_sys.year_pws_deactivated.fillna(3000)

water_sys = water_sys.fillna(0)

water_sys["no_violation"] = np.where((water_sys["VIOLATION_CATEGORY_CODE_MCL"]==0) & 
                                     (water_sys["VIOLATION_CATEGORY_CODE_MON"]==0) &
                                     (water_sys["VIOLATION_CATEGORY_CODE_MR"]==0) &
                                     (water_sys["VIOLATION_CATEGORY_CODE_MRDL"]==0) &
                                     (water_sys["VIOLATION_CATEGORY_CODE_Other"]==0) &
                                     (water_sys["VIOLATION_CATEGORY_CODE_RPT"]==0) &
                                     (water_sys["VIOLATION_CATEGORY_CODE_TT"]==0),
                                     1,
                                     0)

# days in violation
columns_groupby = [col for col in water_sys.columns if col.endswith(('share'))]

for vio_var in columns_groupby:
    print(vio_var)
    print(water_sys[f"{vio_var}"].min())
    water_sys[f"{vio_var}_days"] = water_sys[vio_var] * 365
    print(water_sys[f"{vio_var}_days"].min())

water_sys.PWS_NAME = water_sys.PWS_NAME.astype('string')
water_sys.PWS_DEACTIVATION_DATE = water_sys.PWS_DEACTIVATION_DATE.astype('string')
water_sys.CDS_ID = water_sys.CDS_ID.astype('string')
water_sys.CITY_NAME = water_sys.CITY_NAME.astype('string')
water_sys.ZIP_CODE = water_sys.ZIP_CODE.astype('string')
water_sys.STATE_CODE = water_sys.STATE_CODE.astype('string')
water_sys.SOURCE_PROTECTION_BEGIN_DATE = water_sys.SOURCE_PROTECTION_BEGIN_DATE.astype('string')
water_sys.OUTSTANDING_PERFORMER = water_sys.OUTSTANDING_PERFORMER.astype('string')
water_sys.OUTSTANDING_PERFORM_BEGIN_DATE = water_sys.OUTSTANDING_PERFORM_BEGIN_DATE.astype('string')
water_sys.REDUCED_RTCR_MONITORING = water_sys.REDUCED_RTCR_MONITORING.astype('string')
water_sys.REDUCED_MONITORING_BEGIN_DATE = water_sys.REDUCED_MONITORING_BEGIN_DATE.astype('string')
water_sys.REDUCED_MONITORING_END_DATE = water_sys.REDUCED_MONITORING_END_DATE.astype('string')
water_sys.SOURCE_WATER_PROTECTION_CODE = water_sys.SOURCE_WATER_PROTECTION_CODE.astype('string')

water_sys.to_parquet("Z:/ek559/mining_wq/clean_data/cws_data/prod_vio_sulfur.parquet")

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