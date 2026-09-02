# ============================================================
# Script: regen_scatterhuccoalsulfur_pooled.R
# Purpose: Regenerate scatterhuccoalsulfur_pooled.png as a binscatter — mean
#          and SD of sulfur (%) within each coal-mine-count bin, linear fit
#          drawn behind the binned points with increased line transparency.
#          Extracted from didhet.r's "pooled version" scatter-plot section as
#          a standalone script because didhet.r unconditionally reinstalls
#          ~15 packages on every run and is 2900+ lines long, both
#          disproportionate for this figure alone. Mirrored in didhet.r
#          lines 115-148.
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

# Pooled version, binscatter: bin by number of coal mines, plot the mean and
# SD of sulfur (%) across all HUC12s in each bin, with the linear fit (on the
# underlying HUC12-year observations) drawn behind the binned points and
# rendered with increased transparency.
make_binscatter_panel <- function(df, panel_title) {
  binned <- df %>%
    group_by(num_coal_mines_colocated) %>%
    summarise(
      mean_sulfur = mean(sulfur_colocated, na.rm = TRUE),
      sd_sulfur   = sd(sulfur_colocated, na.rm = TRUE),
      .groups = "drop"
    )

  fit <- lm(sulfur_colocated ~ num_coal_mines_colocated, data = df)
  fit_line <- data.frame(
    num_coal_mines_colocated = seq(
      min(df$num_coal_mines_colocated, na.rm = TRUE),
      max(df$num_coal_mines_colocated, na.rm = TRUE),
      length.out = 100
    )
  )
  fit_line$sulfur_colocated <- predict(fit, newdata = fit_line)

  ggplot(mapping = aes(x = num_coal_mines_colocated, y = sulfur_colocated)) +
    geom_line(data = fit_line, color = "black", linewidth = 0.9, alpha = 0.25) +
    geom_pointrange(
      data = binned,
      aes(y = mean_sulfur, ymin = mean_sulfur - sd_sulfur, ymax = mean_sulfur + sd_sulfur),
      color = "steelblue", size = 0.4
    ) +
    labs(
      title = panel_title,
      x     = "Number of coal mines",
      y     = "Sulfur (%)"
    ) +
    theme_bw() +
    theme(panel.grid = element_blank())
}

p_before_pooled <- make_binscatter_panel(huccoal %>% filter(year <= 1995), "Up to and Including 1995")
p_after_pooled  <- make_binscatter_panel(huccoal %>% filter(year > 1995), "After 1995")

(p_before_pooled + p_after_pooled) +
  plot_annotation(
    title   = "Descriptive evidence of first-stage relevance",
    caption = "Sample: HUC12 watersheds directly upstream of drinking water utility water intakes 1985-2005.\nPoints show the mean sulfur as a percent of coal weight within each coal-mine-count bin; ranges show +/- 1 standard deviation within bin.",
    theme   = theme(plot.caption = element_text(hjust = 0))
  )

out_path <- "Z:/ek559/mining_wq/output/fig/scatterhuccoalsulfur_pooled.png"
ggsave(out_path, width = 8, height = 5, dpi = 500)
cat("Saved:", out_path, "\n")
