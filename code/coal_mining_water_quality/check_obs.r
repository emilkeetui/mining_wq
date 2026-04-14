.libPaths("Z:/ek559/RPackages")
library(arrow)
library(dplyr)

full <- read_parquet("Z:/ek559/mining_wq/clean_data/cws_data/prod_vio_sulfur.parquet")
full <- full[full$year < 2006 & full$year > 1984, ]
full <- full[full$PWSID != "WV3303401", ]

cat("Downstream obs BEFORE balanced panel filter:",
    nrow(full[(full$minehuc_downstream_of_mine == 1) & (full$minehuc_mine == 0), ]), "\n")

full <- full %>% group_by(PWSID) %>% mutate(total_pwsid_obs = n())
full <- full[full$total_pwsid_obs == 21, ]

cat("Downstream obs AFTER balanced panel filter:",
    nrow(full[(full$minehuc_downstream_of_mine == 1) & (full$minehuc_mine == 0), ]), "\n")
