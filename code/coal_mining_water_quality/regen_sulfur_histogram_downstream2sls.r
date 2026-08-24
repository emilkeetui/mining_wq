# ============================================================
# Script: regen_sulfur_histogram_downstream2sls.R
# Purpose: Regenerate sulfur_histogram_downstream2sls.png at higher
#          resolution for the JMP end-of-paper figure (F6). Extracted
#          from mining_reg.r's "ARP on coal production" section as a
#          standalone script because mining_reg.r fails earlier
#          (line 222, ENF_ACTION_CATEGORY) on the current schema of
#          clean_data/cws_data/sdwa_facilities.csv / prod_vio_sulfur.parquet,
#          well before reaching this figure's code.
# Inputs: clean_data/prod_sulfur.csv, clean_data/huc_coal_charac_geom_match.parquet,
#         clean_data/cws_data/prod_vio_sulfur.parquet, clean_data/cws_data/sdwa_facilities.csv
# Outputs: output/fig/sulfur_histogram_downstream2sls.png
# Author: EK  Date: 2026-08-24
# ============================================================

.libPaths(c("C:/Users/ek559/AppData/Local/R/win-library/4.6", "Z:/ek559/RPackages"))
library(dplyr)
library(arrow)

prod_s <- read.csv("Z:/ek559/mining_wq/clean_data/prod_sulfur.csv", stringsAsFactors = FALSE)

pvs_ds <- arrow::read_parquet("Z:/ek559/mining_wq/clean_data/cws_data/prod_vio_sulfur.parquet",
                              col_select = c("PWSID", "minehuc_downstream_of_mine", "minehuc_mine"))
ds_pwsids <- unique(pvs_ds$PWSID[pvs_ds$minehuc_downstream_of_mine == 1 & pvs_ds$minehuc_mine == 0])

facilities <- read.csv("Z:/ek559/mining_wq/clean_data/cws_data/sdwa_facilities.csv", stringsAsFactors = FALSE) %>%
  select(PWSID, huc12, minehuc_downstream_of_mine) %>%
  distinct()
ds_facility_hucs <- unique(facilities$huc12[facilities$PWSID %in% ds_pwsids &
                                            facilities$minehuc_downstream_of_mine == 1])
ds_facility_hucs <- sprintf("%012.0f", as.numeric(ds_facility_hucs))

ds_rows_2sls <- prod_s[sprintf("%012.0f", prod_s$huc12) %in% ds_facility_hucs & !is.na(prod_s$fromhuc), ]
upstream_mine_hucs_2sls <- unique(sprintf("%012.0f", ds_rows_2sls$fromhuc))
cat("Downstream-only 2SLS CWSs:", length(ds_pwsids),
    "| downstream-of-mine intake HUC12s:", length(ds_facility_hucs),
    "| one-hop-upstream HUC12s:", length(upstream_mine_hucs_2sls), "\n")

coal_data_2sls <- arrow::read_parquet("Z:/ek559/mining_wq/clean_data/huc_coal_charac_geom_match.parquet")
coal_data_2sls <- coal_data_2sls[coal_data_2sls$huc12 %in% upstream_mine_hucs_2sls &
                                 coal_data_2sls$year >= 1985 & coal_data_2sls$year <= 2005, ]
active_mine_hucs_2sls <- coal_data_2sls %>%
  group_by(huc12) %>%
  summarise(max_mines = max(num_coal_mines_colocated, na.rm = TRUE)) %>%
  filter(max_mines > 0) %>%
  pull(huc12)
coal_data_2sls <- coal_data_2sls[coal_data_2sls$huc12 %in% active_mine_hucs_2sls, ]

coal_sulfur_hist_2sls <- coal_data_2sls %>% group_by(huc12) %>%
  summarise(sulfur = max(sulfur_colocated, na.rm = TRUE))
cat("HUC12s in sulfur histogram:", nrow(coal_sulfur_hist_2sls), "\n")

out_path <- "Z:/ek559/mining_wq/output/fig/sulfur_histogram_downstream2sls.png"
png(out_path, width = 6.5, height = 4.5, units = "in", res = 300)
par(mar = c(7, 4, 4, 2) + 0.1)
hist(coal_sulfur_hist_2sls$sulfur, main = "HUC12 Coal Sulfur % Histogram", xlab = "Coal bed % sulfur", col = "lightblue", border = "black")
mtext("Sample: HUC12's with at least one active mine between 1985 and 2005 and", side = 1, line = 4, cex = 0.75, col = "grey40")
mtext("directly upstream of a utility water intake.", side = 1, line = 4.8, cex = 0.75, col = "grey40")
dev.off()
cat("Saved:", out_path, "\n")
