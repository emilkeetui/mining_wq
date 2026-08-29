# ============================================================
# Script: regen_scatterhuccoalsulfur_pooled.R
# Purpose: Regenerate scatterhuccoalsulfur_pooled.png with a left-justified
#          plot caption (table-figure-formatting.md Rule 1). Extracted from
#          didhet.r's "pooled version" scatter-plot section as a standalone
#          script because didhet.r unconditionally reinstalls ~15 packages
#          on every run and is 2900+ lines long, both disproportionate for
#          this figure alone. Code for this figure is otherwise unchanged
#          from didhet.r lines 116-146.
# Inputs:  clean_data/prod_sulfur.csv, clean_data/huc_coal_charac_geom_match.parquet
# Outputs: output/fig/scatterhuccoalsulfur_pooled.png
# Author: EK  Date: 2026-08-28
# ============================================================

.libPaths(c("C:/Users/ek559/AppData/Local/R/win-library/4.6", "Z:/ek559/RPackages"))
library(dplyr)
library(arrow)
library(ggplot2)
library(patchwork)

# Sample: mine HUC12s that (1) a downstream-only 2SLS CWS draws water from — identified
# as fromhuc in "downstream_of_mine" rows of prod_sulfur.csv — and (2) had at least one
# active mine in 1985-2005. No exclusion based on whether the HUC12 also has a CWS intake.
prod_s_scatter <- read.csv("Z:/ek559/mining_wq/clean_data/prod_sulfur.csv", stringsAsFactors = FALSE)
ds_rows_scatter <- prod_s_scatter[prod_s_scatter$minehuc == "downstream_of_mine" & !is.na(prod_s_scatter$fromhuc), ]
upstream_mine_hucs_scatter <- unique(sprintf("%012.0f", ds_rows_scatter$fromhuc))

huccoal <- arrow::read_parquet("Z:/ek559/mining_wq/clean_data/huc_coal_charac_geom_match.parquet")
huccoal <- huccoal[huccoal$huc12 %in% upstream_mine_hucs_scatter &
                   huccoal$year >= 1985 & huccoal$year <= 2005, ]

# Keep only HUC12s with at least one active mine year in 1985-2005
active_scatter_hucs <- huccoal %>%
  group_by(huc12) %>%
  summarise(max_mines = max(num_coal_mines_colocated, na.rm = TRUE)) %>%
  filter(max_mines > 0) %>%
  pull(huc12)
huccoal <- huccoal[huccoal$huc12 %in% active_scatter_hucs, ]
cat("Scatter sample — upstream mine HUC12s with >= 1 mine year:", length(active_scatter_hucs), "\n")
cat("Scatter sample rows:", nrow(huccoal), "\n")

# Pooled version: single color, single best-fit line per panel
p_before_pooled <- huccoal %>%
  filter(year <= 1995) %>%
  ggplot(aes(x = num_coal_mines_colocated, y = sulfur_colocated)) +
  geom_point(alpha = 0.4, size = 1.5, color = "steelblue") +
  geom_smooth(method = "lm", se = FALSE, color = "black", linewidth = 0.9) +
  labs(
    title = "Up to and Including 1995",
    x     = "Number of coal mines",
    y     = "Sulfur (%)"
  ) +
  theme_bw()

p_after_pooled <- huccoal %>%
  filter(year > 1995) %>%
  ggplot(aes(x = num_coal_mines_colocated, y = sulfur_colocated)) +
  geom_point(alpha = 0.4, size = 1.5, color = "steelblue") +
  geom_smooth(method = "lm", se = FALSE, color = "black", linewidth = 0.9) +
  labs(
    title = "After 1995",
    x     = "Number of coal mines",
    y     = "Sulfur (%)"
  ) +
  theme_bw()

(p_before_pooled + p_after_pooled) +
  plot_annotation(
    title   = "HUC12 sulfur (%) vs. number of coal mines",
    caption = "Sample: mine HUC12s (D1) upstream of downstream-only 2SLS CWS intakes, >= 1 active mine year 1985-2005.",
    theme   = theme(plot.caption = element_text(hjust = 0))
  )

out_path <- "Z:/ek559/mining_wq/output/fig/scatterhuccoalsulfur_pooled.png"
ggsave(out_path, width = 8, height = 5, dpi = 500)
cat("Saved:", out_path, "\n")
