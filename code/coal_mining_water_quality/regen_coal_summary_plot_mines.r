# ============================================================
# Script: regen_coal_summary_plot_mines.r
# Purpose: Mine-level coal summary figure (total mine coal production
#          by sulfur level), 1983-2005.
# Inputs: clean_data/coal_mine_prod_charac.parquet,
#         clean_data/huc_coal_charac_geom_match.parquet,
#         clean_data/cws_data/step_instruments.parquet,
#         clean_data/cws_data/step_huc_links_k2.parquet
# Outputs: output/fig/coal_summary_plot_mines.png
# Author: EK  Date: 2026-10-28
# ============================================================

.libPaths(c("C:/Users/ek559/AppData/Local/R/win-library/4.6", "Z:/ek559/RPackages"))
library(dplyr)
library(arrow)
library(ggplot2)
library(scales)

ROOT <- "Z:/ek559/mining_wq"

mines <- arrow::read_parquet(file.path(ROOT, "clean_data/coal_mine_prod_charac.parquet"),
                             col_select = c("mine_id", "huc12", "year", "production_short_tons"))
mines$year <- as.integer(mines$year)
mines <- mines[mines$year >= 1983 & mines$year <= 2005, ]

# Collapse mine_type rows (surface/underground/refuse) to one mine-year
mines <- mines %>% group_by(mine_id, huc12, year) %>%
  summarise(production_short_tons = sum(production_short_tons, na.rm = TRUE), .groups = "drop")

# Sulfur from the HUC12 panel so mines are classified as in the HUC12-level figure
huc_sulfur <- arrow::read_parquet(file.path(ROOT, "clean_data/huc_coal_charac_geom_match.parquet"),
                                  col_select = c("huc12", "sulfur_colocated")) %>%
  distinct(huc12, sulfur_colocated)
stopifnot(!any(duplicated(huc_sulfur$huc12)))

# Restrict to mines in HUC12s linked (within 2 steps upstream) to the k=2 main-arm CWS sample.
# Intake HUC12s themselves contain no mines by construction (utilities with a mine-HUC
# intake are dropped), so the linked HUC12s are the sample's mine-bearing watersheds.
k2_pwsids <- arrow::read_parquet(file.path(ROOT, "clean_data/cws_data/step_instruments.parquet"),
                                 col_select = c("PWSID", "arm", "k", "n_mine_hucs_linked")) %>%
  filter(arm == "main", k == 2, n_mine_hucs_linked >= 1) %>% distinct(PWSID)
k2_links <- arrow::read_parquet(file.path(ROOT, "clean_data/cws_data/step_huc_links_k2.parquet"))
k2_linked_hucs <- unique(k2_links$linked_huc12[k2_links$PWSID %in% k2_pwsids$PWSID])
cat("k=2 main-arm CWS:", nrow(k2_pwsids), " linked HUC12s:", length(k2_linked_hucs), "\n")
n_all_mines <- n_distinct(mines$mine_id)
mines <- mines[mines$huc12 %in% k2_linked_hucs, ]
cat("Mines kept in k=2 linked HUC12s:", n_distinct(mines$mine_id), "of", n_all_mines, "\n")

n_before <- nrow(mines)
mines_before <- n_distinct(mines$mine_id)
mines <- inner_join(mines, huc_sulfur, by = "huc12")
mines <- mines[!is.na(mines$sulfur_colocated), ]
cat("Mine-year rows before/after sulfur join:", n_before, "/", nrow(mines), "\n")
cat("Mines dropped for missing sulfur:", mines_before - n_distinct(mines$mine_id),
    "of", mines_before, "\n")

mines$high_sulfur <- as.integer(mines$sulfur_colocated > 1.5)
active <- mines[mines$production_short_tons > 0, ]
cat("Active mine-years by sulfur group:\n")
print(table(active$high_sulfur))

coal_prod_over_time <- active %>% group_by(high_sulfur, year) %>%
  summarise(tot_sulf_coal = sum(production_short_tons), .groups = "drop")
coal_prod_over_time$high_sulfur <- as.factor(coal_prod_over_time$high_sulfur)

# Rescale: million short tons
coal_prod_over_time$tot_sulf_coal_m <- coal_prod_over_time$tot_sulf_coal / 1e6

sulfur_labels <- c("0" = "Low sulfur (\u22641.5% weight)", "1" = "High sulfur (>1.5% weight)")

combined_plot <- ggplot(coal_prod_over_time,
                        aes(x = year, y = tot_sulf_coal_m, color = high_sulfur)) +
  geom_line() +
  labs(x = "Year", y = "Million short tons") +
  scale_color_manual(name = "Sulfur level", values = c("0" = "blue", "1" = "red"),
                     labels = sulfur_labels) +
  scale_y_continuous(labels = scales::label_number(accuracy = 1, big.mark = "")) +
  theme_minimal() +
  theme(legend.position = "bottom")

out_path <- file.path(ROOT, "output/fig/coal_summary_plot_mines.png")
if (file.exists(out_path)) cat("WARNING:", out_path, "already exists -- overwriting\n")
ggsave(out_path, combined_plot, height = 3, width = 6.5)
cat("Saved:", out_path, "\n")
