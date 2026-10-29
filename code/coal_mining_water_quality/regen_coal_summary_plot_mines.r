# ============================================================
# Script: regen_coal_summary_plot_mines.r
# Purpose: Mine-level coal summary figure (mean/total mine coal production
#          and number of active mines by sulfur level), 1983-2005.
# Inputs: clean_data/coal_mine_prod_charac.parquet,
#         clean_data/huc_coal_charac_geom_match.parquet
# Outputs: output/fig/coal_summary_plot_mines.png
# Author: EK  Date: 2026-10-28
# ============================================================

.libPaths(c("C:/Users/ek559/AppData/Local/R/win-library/4.6", "Z:/ek559/RPackages"))
library(dplyr)
library(arrow)
library(ggplot2)
library(patchwork)
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
  summarise(avg_mine_coal = mean(production_short_tons),
            tot_sulf_coal = sum(production_short_tons),
            n_active_mines = n_distinct(mine_id),
            .groups = "drop")
coal_prod_over_time$high_sulfur <- as.factor(coal_prod_over_time$high_sulfur)

# Rescale: thousand short tons (mean), million short tons (total)
coal_prod_over_time$avg_mine_coal_k <- coal_prod_over_time$avg_mine_coal / 1e3
coal_prod_over_time$tot_sulf_coal_m <- coal_prod_over_time$tot_sulf_coal / 1e6

sulfur_labels <- c("0" = "Low sulfur (\u22641.5% weight)", "1" = "High sulfur (>1.5% weight)")

panel_plot <- function(yvar, title, ylab, accuracy) {
  ggplot(coal_prod_over_time, aes(x = year, y = .data[[yvar]], color = high_sulfur)) +
    geom_line() +
    labs(title = title, x = "Year", y = ylab) +
    scale_color_manual(name = "Sulfur level", values = c("0" = "blue", "1" = "red"),
                       labels = sulfur_labels) +
    scale_y_continuous(labels = scales::label_number(accuracy = accuracy, big.mark = "")) +
    theme_minimal()
}

plot1 <- panel_plot("avg_mine_coal_k", "Mean mine coal production", "Thousand short tons", 1)
plot2 <- panel_plot("tot_sulf_coal_m", "Total mine coal production", "Million short tons", 1)
plot3 <- panel_plot("n_active_mines", "Active coal mines", "Number of mines", 1)

combined_plot <- wrap_plots(list(plot1, plot2, plot3), ncol = 1) +
  plot_layout(guides = "collect") &
  theme(legend.position = "bottom")

out_path <- file.path(ROOT, "output/fig/coal_summary_plot_mines.png")
if (file.exists(out_path)) cat("WARNING:", out_path, "already exists -- overwriting\n")
ggsave(out_path, combined_plot, height = 5, width = 6.5)
cat("Saved:", out_path, "\n")
