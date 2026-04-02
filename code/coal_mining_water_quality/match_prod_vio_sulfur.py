import pandas as pd
import numpy as np

hucsulfur = pd.read_csv("Z:/ek559/mining_wq/clean_data/huc_coal_charac_geom_match.csv")
hucsulfur.drop('Unnamed: 0', axis=1, inplace=True)
df_years = pd.DataFrame({'year': list(range(1983, 2025))})
hucsulfur = hucsulfur.merge(df_years, how='cross')
huc_prod = pd.read_csv("Z:/ek559/mining_wq/clean_data/coal_huc_prod.csv")
sysvio = pd.read_csv("Z:/ek559/mining_wq/clean_data/cws_data/matched_vio_pws.csv", low_memory=False)
sysvio.drop(['Unnamed: 0', 'SUBMISSIONYEARQUARTER_x', 'SUBMISSIONYEARQUARTER_y'], axis=1, inplace=True)

fin = pd.merge(hucsulfur, huc_prod, on=['huc12', 'year'], how='left')
fin[['production_short_tons_coal', 'num_coal_mines']] = fin[['production_short_tons_coal', 'num_coal_mines']].fillna(0)

coaldata = fin[fin['huc12'].isin(sysvio['huc12'].unique())]
coaldata['post95'] = np.where(coaldata['year']>=1995,
                              1,
                              0)
coaldata.to_csv("Z:/ek559/mining_wq/clean_data/prod_sulfur.csv", index=False)

fin = pd.merge(fin, sysvio, on = ['huc12','minehuc','year'], how = 'right')
fin['post95'] = np.where(fin['year']>=1995,
                         1,
                         0)
fin = pd.get_dummies(fin,
                     columns=['minehuc', 'RULE_CODE', 'RULE_FAMILY_CODE'],
                     dummy_na=True,
                     dtype=int)
# Assuming your dataframe is called df
fin.columns = fin.columns.str.replace(r'\.0$', '', regex=True)
fin.to_csv("Z:/ek559/mining_wq/clean_data/prod_vio_sulfur.csv", index=False)