# ============================================================
# Script: figures_nonmining_numbervio.r
# Purpose: Regenerate non-mining violation trend figure and
#          number-of-violations figure (downstream/colocated
#          split by sulfur) after pre-rule NaN correction.
# Inputs:  clean_data/cws_data/prod_vio_sulfur.parquet
# Outputs: output/fig/non_mining_viol_mean_line1985to2005_dwnstreamcolocatedsulfur.png
#          output/fig/number_vio_mean_line1985to2005_dwnstreamcolocatedsulfur.png
# Author: EK  Date: 2026-04-14
# ============================================================

.libPaths("Z:/ek559/RPackages")
library(arrow)
library(dplyr)
library(ggplot2)
library(patchwork)

full <- read_parquet("Z:/ek559/mining_wq/clean_data/cws_data/prod_vio_sulfur.parquet")
full <- full[full$year < 2006 & full$year > 1984, ]
full <- full[full$PWSID != "WV3303401", ]

# Balance panel: keep only PWSIDs observed all 21 years
full <- full %>%
  group_by(PWSID) %>%
  mutate(total_pwsid_obs = n()) %>%
  ungroup()
full <- full[full$total_pwsid_obs == 21, ]
cat("Rows after balance panel:", nrow(full), "\n")

# sulfur_location: downstream vs colocated, high vs low sulfur
full$HighSulfur <- ifelse(full$sulfur_colocated > 1.5, "High sulfur", "Low sulfur")
full$sulfur_location <- "High sulfur downstream"
full$sulfur_location[full$minehuc_downstream_of_mine == 1 &
                     full$minehuc_mine == 0 &
                     full$HighSulfur == "Low sulfur"] <- "Low sulfur downstream"
full$sulfur_location[full$minehuc_downstream_of_mine == 0 &
                     full$minehuc_mine == 1 &
                     full$HighSulfur == "High sulfur"] <- "High sulfur colocated"
full$sulfur_location[full$minehuc_downstream_of_mine == 0 &
                     full$minehuc_mine == 1 &
                     full$HighSulfur == "Low sulfur"] <- "Low sulfur colocated"

stackmineviobytreat <- function(varlist, dset, plot_title, vartitle, numcol,
                                groupvar, outname,
                                legndnrow = 2, legndncol = 2,
                                morethantwolegndobj = FALSE) {
  plotlist <- list()
  for (i in seq_along(varlist)) {
    varname <- varlist[i]
    df <- dset %>%
      group_by(.data[[groupvar]], year) %>%
      summarise(val = mean(.data[[varname]], na.rm = TRUE), .groups = "drop")
    p <- ggplot(df, aes(x = year, y = val, color = .data[[groupvar]])) +
      geom_line() +
      labs(title = vartitle[i], y = "Mean days", x = "Year") +
      theme_minimal() +
      theme(legend.position = "none") +
      scale_x_continuous(breaks = c(1985, 1990, 1995, 2000, 2005))
    plotlist[[varname]] <- p
  }
  if (isTRUE(morethantwolegndobj)) {
    combined <- wrap_plots(plotlist, ncol = numcol) +
      plot_annotation(title = plot_title) +
      plot_layout(guides = "collect") &
      theme(legend.position = "bottom") &
      guides(color = guide_legend(nrow = legndnrow, ncol = legndncol))
  } else {
    combined <- wrap_plots(plotlist, ncol = numcol) +
      plot_annotation(title = plot_title) +
      plot_layout(guides = "collect") &
      theme(legend.position = "bottom")
  }
  ggsave(outname, combined, height = 5, width = 5)
  cat("Saved:", outname, "\n")
}

dset_ds <- full[full$minehuc_upstream_of_mine == 0, ]

# Figure 1: non-mining violations (VOC, SOC, SWTR, total coliform)
stackmineviobytreat(
  c("voc_share_days", "soc_share_days",
    "surface_ground_water_rule_share_days", "total_coliform_share_days"),
  dset_ds,
  "Days of the year PWSs spent in violation",
  c("Volatile Organic Chemicals", "Synthetic Organic Chemicals",
    "Surface/Ground Water Rule", "Total Coliforms"),
  2, "sulfur_location",
  "Z:/ek559/mining_wq/output/fig/non_mining_viol_mean_line1985to2005_dwnstreamcolocatedsulfur.png",
  morethantwolegndobj = TRUE
)

# Figure 2: number of violations (total, mining, non-mining)
stackmineviobytreat(
  c("num_violations", "num_mining_violations", "num_non_mining_violations"),
  dset_ds,
  "Number of violations in a year PWSs",
  c("Total", "Mining related", "Non-mining related"),
  2, "sulfur_location",
  "Z:/ek559/mining_wq/output/fig/number_vio_mean_line1985to2005_dwnstreamcolocatedsulfur.png",
  morethantwolegndobj = TRUE
)

cat("Done.\n")
