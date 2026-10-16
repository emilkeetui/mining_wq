# ============================================================
# Script: regen_sulfur_histogram_k2.r
# Purpose: Three-panel histogram (active coal mines, coal production, % sulfur)
#          for mine HUC12s within two flow steps upstream of utility intakes
#          (k=2 sample). Port of regen_sulfur_histogram_downstream2sls.r.
# Inputs: clean_data/cws_data/step_huc_links_k2.parquet,
#         clean_data/huc_coal_charac_geom_match.csv,
#         clean_data/huc_coal_charac_geom_match.parquet,
#         clean_data/coal_huc_prod.csv
# Outputs: output/fig/sulfur_histogram_k2.png
# Author: EK  Date: 2026-10-14
# ============================================================

.libPaths(c("C:/Users/ek559/AppData/Local/R/win-library/4.6", "Z:/ek559/RPackages"))
library(dplyr)
library(arrow)

options(scipen = 999)
ROOT <- "Z:/ek559/mining_wq"

# Mine HUC12s linked to a utility within two flow steps, active 1985-2005
# (same selection as run_k2_figures.r)
huc_links <- arrow::read_parquet(file.path(ROOT, "clean_data/cws_data/step_huc_links_k2.parquet"))
linked_hucs <- unique(huc_links$linked_huc12)

huc_csv <- read.csv(file.path(ROOT, "clean_data/huc_coal_charac_geom_match.csv"),
                    colClasses = c(huc12 = "character"))
mine_hucs <- unique(huc_csv$huc12[huc_csv$minehuc == "mine"])
target_hucs <- intersect(linked_hucs, mine_hucs)

coal_prod <- read.csv(file.path(ROOT, "clean_data/coal_huc_prod.csv"), colClasses = c(huc12 = "character"))
coal_prod <- coal_prod[coal_prod$year >= 1985 & coal_prod$year <= 2005, ]
active_hucs <- unique(coal_prod$huc12[coal_prod$num_coal_mines > 0])
target_hucs <- intersect(target_hucs, active_hucs)
cat("Linked mine HUC12s active 1985-2005:", length(target_hucs), "\n")

coal_data_k2 <- arrow::read_parquet(file.path(ROOT, "clean_data/huc_coal_charac_geom_match.parquet"))
coal_data_k2 <- coal_data_k2[coal_data_k2$huc12 %in% target_hucs &
                             coal_data_k2$year >= 1985 & coal_data_k2$year <= 2005, ]
stopifnot(nrow(coal_data_k2) > 100)

coal_sulfur_hist_k2 <- coal_data_k2 %>% group_by(huc12) %>%
  summarise(sulfur = suppressWarnings(max(sulfur_colocated, na.rm = TRUE))) %>%
  filter(is.finite(sulfur))
cat("HUC12s in sulfur histogram:", nrow(coal_sulfur_hist_k2), "\n")

out_path <- file.path(ROOT, "output/fig/sulfur_histogram_k2.png")
if (file.exists(out_path)) cat("WARNING:", out_path, "already exists -- overwriting\n")
png(out_path, width = 11, height = 13.5, units = "in", res = 300)
par(mfrow = c(3, 1), mar = c(6, 8, 5, 2) + 0.1, mgp = c(5, 1, 0),
    cex.main = 2.2, cex.lab = 1.7, cex.axis = 1.55)

hist(coal_data_k2$num_coal_mines_colocated,
     main = "Active coal mines",
     xlab = "Number of active coal mines", ylab = "Frequency", las = 1,
     col = "lightblue", border = "black")

# Production in million short tons so tick labels stay short (no raw 2000000)
hist(coal_data_k2$production_short_tons_coal_colocated / 1e6,
     main = "Coal production",
     xlab = "Coal production (million short tons)", ylab = "Frequency", las = 1,
     col = "lightblue", border = "black")

hist(coal_sulfur_hist_k2$sulfur,
     main = "Coal sulfur content",
     xlab = "Coal sulfur content (% of weight)", ylab = "Frequency", las = 1,
     col = "lightblue", border = "black")

dev.off()
cat("Saved:", out_path, "\n")
