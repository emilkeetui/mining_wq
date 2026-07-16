# ============================================================
# Script: upstream_coal_summary.R
# Purpose: Summary table (mean, max, SD, N) of upstream coal mining
#          intensity in the main 2SLS downstream sample: (1) number of
#          upstream mines, (2) short tons of coal mined upstream, and
#          (3) coal produced per active upstream mine (restricted to
#          CWS-years with num_coal_mines_upstream_sum > 0).
# Inputs: clean_data/cws_data/prod_vio_sulfur.parquet
# Outputs: output/sum/upstream_coal_summary.tex
# Author: EK  Date: 2026-07-15
# ============================================================

.libPaths("Z:/ek559/RPackages")
library(arrow)
library(dplyr)
library(tinytable)

full <- read_parquet("Z:/ek559/mining_wq/clean_data/cws_data/prod_vio_sulfur.parquet")

### PRIOR TO 2006 and AFTER 1985 — same filters as main 2SLS downstream sample
full <- full[full$year < 2006 & full$year > 1984, ]
full <- full[full$PWSID != "WV3303401", ]

# Main 2SLS downstream sample: downstream-of-mine HUCs, excluding colocated
dwnstrm <- full[(full$minehuc_downstream_of_mine == 1) & (full$minehuc_mine == 0), ]

str(dwnstrm[, c("num_coal_mines_upstream_sum", "production_short_tons_coal_upstream_sum")])

# CWS-years with at least one active upstream mine
dwnstrm_active <- dwnstrm[dwnstrm$num_coal_mines_upstream_sum > 0, ]
dwnstrm_active$coal_tons_per_active_mine <-
  dwnstrm_active$production_short_tons_coal_upstream_sum / dwnstrm_active$num_coal_mines_upstream_sum

summary_row <- function(x) {
  x <- x[!is.na(x)]
  data.frame(
    Mean = mean(x),
    Max  = max(x),
    SD   = sd(x),
    N    = length(x)
  )
}

upstream_coal_summary <- bind_rows(
  summary_row(dwnstrm$num_coal_mines_upstream_sum),
  summary_row(dwnstrm$production_short_tons_coal_upstream_sum),
  summary_row(dwnstrm_active$coal_tons_per_active_mine)
)

upstream_coal_summary <- cbind(
  Variable = c(
    "N upstream mines",
    "Short tons coal mined upstream",
    "Coal produced per active upstream mine (tons)"
  ),
  upstream_coal_summary
)

print(upstream_coal_summary)

tt(upstream_coal_summary, digits = 2) |>
  format_tt(j = c("Mean", "Max", "SD"), num_fmt = "decimal", digits = 2) |>
  format_tt(j = "N", num_fmt = "decimal", digits = 0) |>
  theme_latex(outer = "label={tblr:upstream_coal_summary}", resize_width = 1, resize_direction = "down") |>
  save_tt("Z:/ek559/mining_wq/output/sum/upstream_coal_summary.tex", overwrite = TRUE)

cat("Wrote Z:/ek559/mining_wq/output/sum/upstream_coal_summary.tex\n")
