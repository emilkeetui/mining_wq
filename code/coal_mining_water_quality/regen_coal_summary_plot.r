# ============================================================
# Script: regen_coal_summary_plot.r
# Purpose: Regenerate the coal summary figure (mean/total HUC12 coal production
#          and mean active mines by sulfur level) with rescaled, fixed-decimal
#          axes. Data prep and plot code copied from mining_reg.r.
# Inputs: clean_data/huc_coal_charac_geom_match.parquet
# Outputs: output/fig/coal_summary_plot.png
# Author: EK  Date: 2026-10-28
# ============================================================

.libPaths(c("C:/Users/ek559/AppData/Local/R/win-library/4.6", "Z:/ek559/RPackages"))
library(dplyr)
library(arrow)
library(ggplot2)
library(patchwork)
library(scales)

ROOT <- "Z:/ek559/mining_wq"

# All mine-colocated or upstream-of-mine HUC12s
coal_data_summary <- arrow::read_parquet(file.path(ROOT, "clean_data/huc_coal_charac_geom_match.parquet"))
coal_data_summary <- coal_data_summary[coal_data_summary$minehuc %in% c("mine", "upstream_of_mine") &
                                       coal_data_summary$year >= 1983 & coal_data_summary$year <= 2005, ]
coal_data_summary$high_sulfur <- as.integer(coal_data_summary$sulfur_colocated > 1.5)

coal_prod_over_time <- coal_data_summary %>% group_by(high_sulfur, year) %>%
  summarise(avg_huc_coal = mean(production_short_tons_coal_colocated, na.rm = TRUE),
            tot_sulf_coal = sum(production_short_tons_coal_colocated, na.rm = TRUE),
            mean_coal_mine = mean(num_coal_mines_colocated, na.rm = TRUE),
            .groups = "drop")
coal_prod_over_time$high_sulfur <- as.factor(coal_prod_over_time$high_sulfur)

# Rescale: thousand short tons (mean), million short tons (total)
coal_prod_over_time$avg_huc_coal_k <- coal_prod_over_time$avg_huc_coal / 1e3
coal_prod_over_time$tot_sulf_coal_m <- coal_prod_over_time$tot_sulf_coal / 1e6

sulfur_labels <- c("0" = "Low sulfur (≤1.5% weight)", "1" = "High sulfur (>1.5% weight)")

panel_plot <- function(yvar, title, ylab, accuracy) {
  ggplot(coal_prod_over_time, aes(x = year, y = .data[[yvar]], color = high_sulfur)) +
    geom_line() +
    labs(title = title, x = "Year", y = ylab) +
    scale_color_manual(name = "Sulfur level", values = c("0" = "blue", "1" = "red"),
                       labels = sulfur_labels) +
    scale_y_continuous(labels = scales::label_number(accuracy = accuracy, big.mark = "")) +
    theme_minimal()
}

plot1 <- panel_plot("avg_huc_coal_k", "Mean HUC12 coal production", "Thousand short tons", 1)
plot2 <- panel_plot("tot_sulf_coal_m", "Total HUC12 coal production", "Million short tons", 1)
plot3 <- panel_plot("mean_coal_mine", "Mean active HUC12 coal mines", "Number of mines", 0.01)

combined_plot <- wrap_plots(list(plot1, plot2, plot3), ncol = 1) +
  plot_layout(guides = "collect") &
  theme(legend.position = "bottom")

out_path <- file.path(ROOT, "output/fig/coal_summary_plot.png")
if (file.exists(out_path)) cat("WARNING:", out_path, "already exists -- overwriting\n")
ggsave(out_path, combined_plot, height = 5, width = 6.5)
cat("Saved:", out_path, "\n")
