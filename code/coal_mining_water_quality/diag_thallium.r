# ============================================================
# Script: diag_thallium.r
# Purpose: Diagnose small SE on thallium coefficient in 6yr HUC02-FE regression
# Inputs:  clean_data/cws_6year_review.parquet
#          clean_data/cws_data/pwsid_huc02.parquet
# Outputs: console diagnostics
# Author: EK  Date: 2026-06-05
# ============================================================

.libPaths("Z:/ek559/RPackages")
library(fixest)
library(arrow)
library(dplyr)

PROJECT_ROOT <- "Z:/ek559/mining_wq"

df6 <- read_parquet(file.path(PROJECT_ROOT, "clean_data", "cws_6year_review.parquet"))
huc02 <- read_parquet(file.path(PROJECT_ROOT, "clean_data", "cws_data", "pwsid_huc02.parquet"))

df6 <- df6 |> left_join(huc02 |> select(PWSID, huc02), by = "PWSID")
df6 <- df6[df6$year >= 1985, ]
df6 <- df6[df6$PWSID != "WV3303401", ]
df6 <- df6[df6$minehuc_downstream_of_mine == 1 & df6$minehuc_mine == 0, ]

# Cumulative production
cum_panel <- df6 |>
  distinct(PWSID, year, production_short_tons_coal_upstream_sum) |>
  arrange(PWSID, year) |>
  group_by(PWSID) |>
  mutate(coal_prod_upstream_cumsum =
           cumsum(replace(production_short_tons_coal_upstream_sum,
                          is.na(production_short_tons_coal_upstream_sum), 0))) |>
  ungroup() |>
  select(PWSID, year, coal_prod_upstream_cumsum)

df6 <- df6 |> left_join(cum_panel, by = c("PWSID", "year"))
df6$coal_prod_upstream_cumsum_10mst <- df6$coal_prod_upstream_cumsum / 1e7
df6 <- df6[!is.na(df6$VALUE), ]

# Thallium subset
th <- df6[grepl("thallium", tolower(df6$CHEMID_name)), ]
cat("=== THALLIUM SAMPLE ===\n")
cat("N rows:", nrow(th), "\n")
cat("Unique PWSIDs:", length(unique(th$PWSID)), "\n")
cat("Year range:", min(th$year), "-", max(th$year), "\n\n")

# 1. Outcome distribution
cat("=== OUTCOME (VALUE) DISTRIBUTION ===\n")
print(summary(th$VALUE))
cat("SD:", sd(th$VALUE, na.rm = TRUE), "\n")
cat("Share == 0:", mean(th$VALUE == 0, na.rm = TRUE), "\n")
cat("Share at detection limit or below 0.0001:", mean(th$VALUE <= 0.0001, na.rm = TRUE), "\n")
cat("Share above MCL (0.0005):", mean(th$VALUE > 0.0005, na.rm = TRUE), "\n\n")

# 2. Value frequency table (top values)
cat("=== TOP 20 MOST COMMON VALUES ===\n")
val_tab <- sort(table(th$VALUE), decreasing = TRUE)
print(head(val_tab, 20))
cat("\n")

# 3. Regressor distribution
cat("=== REGRESSOR (coal_prod_upstream_cumsum_10mst) DISTRIBUTION ===\n")
print(summary(th$coal_prod_upstream_cumsum_10mst))
cat("SD:", sd(th$coal_prod_upstream_cumsum_10mst, na.rm = TRUE), "\n\n")

# 4. Fixed effects structure
cat("=== FIXED EFFECTS STRUCTURE ===\n")
cat("Unique PWSID:", length(unique(th$PWSID)), "\n")
cat("Unique huc02:", length(unique(th$huc02)), "\n")
cat("Unique huc02 x year cells:", nrow(distinct(th, huc02, year)), "\n")
cat("Obs per PWSID (median, mean):",
    median(table(th$PWSID)), mean(table(th$PWSID)), "\n\n")

# 5. Run the regression and inspect residuals
fml <- VALUE ~ coal_prod_upstream_cumsum_10mst + num_facilities | PWSID + huc02^year
m <- feols(fml, data = th, cluster = ~PWSID)
cat("=== REGRESSION RESULTS ===\n")
print(summary(m))
cat("\nCoef:", coef(m)["coal_prod_upstream_cumsum_10mst"],
    "| SE:", se(m)["coal_prod_upstream_cumsum_10mst"],
    "| t:", coef(m)["coal_prod_upstream_cumsum_10mst"] / se(m)["coal_prod_upstream_cumsum_10mst"], "\n\n")

# 6. Residual diagnostics
resid_vals <- residuals(m)
cat("=== RESIDUAL DISTRIBUTION ===\n")
print(summary(resid_vals))
cat("Residual SD:", sd(resid_vals), "\n")
cat("Residual SD vs outcome SD ratio:", sd(resid_vals) / sd(th$VALUE, na.rm = TRUE), "\n\n")

# 7. Within-PWSID variation in regressor (key: after FE absorption)
th_fe <- th |>
  group_by(PWSID) |>
  mutate(coal_demeaned = coal_prod_upstream_cumsum_10mst - mean(coal_prod_upstream_cumsum_10mst, na.rm = TRUE)) |>
  ungroup()
cat("=== WITHIN-PWSID VARIATION IN REGRESSOR (after PWSID FE) ===\n")
cat("SD of within-PWSID demeaned coal:", sd(th_fe$coal_demeaned, na.rm = TRUE), "\n")
cat("(Compare to overall SD:", sd(th$coal_prod_upstream_cumsum_10mst, na.rm = TRUE), ")\n\n")

# 8. Influential observations — top 10 by abs(VALUE)
cat("=== TOP 10 ROWS BY VALUE (potential outliers) ===\n")
top_vals <- th |> arrange(desc(VALUE)) |> select(PWSID, year, VALUE, coal_prod_upstream_cumsum_10mst, huc02) |> head(10)
print(top_vals)
cat("\n")

# 9. Cluster size distribution
cat("=== CLUSTER (PWSID) SIZE DISTRIBUTION ===\n")
clust_sizes <- table(th$PWSID)
print(summary(as.integer(clust_sizes)))
cat("N clusters (PWSIDs):", length(clust_sizes), "\n")
cat("Share of clusters with only 1 obs:", mean(clust_sizes == 1), "\n\n")

# 10. Leave-one-PWSID-out sensitivity
cat("=== LEAVE-ONE-PWSID-OUT SENSITIVITY (top 5 by abs leverage) ===\n")
pwsids <- names(clust_sizes)
loo_coefs <- sapply(pwsids, function(p) {
  d <- th[th$PWSID != p, ]
  tryCatch({
    m_loo <- feols(fml, data = d, cluster = ~PWSID, warn = FALSE)
    coef(m_loo)["coal_prod_upstream_cumsum_10mst"]
  }, error = function(e) NA_real_)
})
loo_df <- data.frame(
  PWSID     = names(loo_coefs),
  coef_excl = as.numeric(loo_coefs),
  stringsAsFactors = FALSE
)
loo_df$influence <- abs(loo_df$coef_excl - coef(m)["coal_prod_upstream_cumsum_10mst"])
loo_df <- loo_df[order(-loo_df$influence), ]
cat("Baseline coef:", round(coef(m)["coal_prod_upstream_cumsum_10mst"], 6), "\n")
print(head(loo_df, 10))
