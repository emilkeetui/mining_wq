# ============================================================
# Script: check_enforcement_descriptives.r
# Purpose: Descriptive check on SDWA_SITE_VISITS and
#          SDWA_VIOLATIONS_ENFORCEMENT for sample PWSIDs 1985–2005
# Inputs:
#   clean_data/cws_data/prod_vio_sulfur.parquet
#   Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_SITE_VISITS.csv
#   Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.csv
# Outputs: console only
# Author: EK  Date: 2026-04-28
# ============================================================

.libPaths("Z:/ek559/RPackages")
library(arrow)
library(dplyr)

ROOT    <- "Z:/ek559/mining_wq"
SDWA    <- "Z:/ek559/sdwa_violations/SDWA_latest_downloads"

# ── Sample PWSID list ─────────────────────────────────────────────────────────
main <- read_parquet(file.path(ROOT, "clean_data/cws_data/prod_vio_sulfur.parquet"))
main <- main[main$year >= 1985 & main$year <= 2005, ]
sample_ids  <- unique(main$PWSID)
panel_size  <- length(sample_ids) * 21
cat(sprintf("Sample: %d PWSIDs × 21 years = %d PWSID-years\n\n", length(sample_ids), panel_size))

# ── SITE VISITS ───────────────────────────────────────────────────────────────
cat("=== SDWA_SITE_VISITS ===\n")
sv <- read.csv(file.path(SDWA, "SDWA_SITE_VISITS.csv"), stringsAsFactors = FALSE)
sv <- sv[sv$PWSID %in% sample_ids, ]

# Parse year from VISIT_DATE (format: MM/DD/YYYY or YYYY-MM-DD)
sv$year <- as.integer(substr(trimws(sv$VISIT_DATE), nchar(trimws(sv$VISIT_DATE)) - 3, nchar(trimws(sv$VISIT_DATE))))
sv <- sv[!is.na(sv$year) & sv$year >= 1985 & sv$year <= 2005, ]

cat(sprintf("Total visits (1985-2005):      %d\n", nrow(sv)))
cat(sprintf("Unique PWSIDs with >=1 visit:  %d / %d (%.1f%%)\n",
    length(unique(sv$PWSID)), length(sample_ids),
    100 * length(unique(sv$PWSID)) / length(sample_ids)))

cat("\nVisit reason code breakdown:\n")
print(sort(table(sv$VISIT_REASON_CODE), decreasing = TRUE))

sv_agg <- sv %>%
  group_by(PWSID, year) %>%
  summarise(n_visits = n(), .groups = "drop")

cat(sprintf("\nPWSID-years with >=1 visit:    %d / %d (%.1f%%)\n",
    nrow(sv_agg), panel_size, 100 * nrow(sv_agg) / panel_size))
cat(sprintf("Mean visits per active PWSID-year: %.2f\n", mean(sv_agg$n_visits)))

cat("\nVisits per year:\n")
yr_tab <- sv %>% count(year) %>% arrange(year)
print(as.data.frame(yr_tab), row.names = FALSE)

# Sanitary surveys (SNSV) only
snsv <- sv[sv$VISIT_REASON_CODE == "SNSV", ]
snsv_agg <- snsv %>% group_by(PWSID, year) %>% summarise(n_snsv = n(), .groups = "drop")
cat(sprintf("\nSanitary survey (SNSV) PWSID-years: %d (%.1f%% of panel)\n",
    nrow(snsv_agg), 100 * nrow(snsv_agg) / panel_size))

rm(sv, snsv); gc()

# ── VIOLATIONS ENFORCEMENT ────────────────────────────────────────────────────
cat("\n=== SDWA_VIOLATIONS_ENFORCEMENT ===\n")
enf <- read.csv(file.path(SDWA, "SDWA_VIOLATIONS_ENFORCEMENT.csv"), stringsAsFactors = FALSE)
enf <- enf[enf$PWSID %in% sample_ids, ]

# Parse year from CALCULATED_RTC_DATE or COMPL_PER_BEGIN_DATE
# Use COMPL_PER_BEGIN_DATE which indicates the violation period start
enf$year <- as.integer(substr(trimws(enf$COMPL_PER_BEGIN_DATE), nchar(trimws(enf$COMPL_PER_BEGIN_DATE)) - 3, nchar(trimws(enf$COMPL_PER_BEGIN_DATE))))
enf_yr <- enf[!is.na(enf$year) & enf$year >= 1985 & enf$year <= 2005, ]

cat(sprintf("Total enforcement records (1985-2005): %d\n", nrow(enf_yr)))
cat(sprintf("Unique PWSIDs with enforcement:        %d / %d (%.1f%%)\n",
    length(unique(enf_yr$PWSID)), length(sample_ids),
    100 * length(unique(enf_yr$PWSID)) / length(sample_ids)))

cat("\nENF_ACTION_CATEGORY breakdown:\n")
print(sort(table(enf_yr$ENF_ACTION_CATEGORY), decreasing = TRUE))

cat("\nVIOLATION_CATEGORY_CODE breakdown:\n")
print(sort(table(enf_yr$VIOLATION_CATEGORY_CODE), decreasing = TRUE))

# Formal enforcement specifically
formal <- enf_yr[enf_yr$ENF_ACTION_CATEGORY == "Formal", ]
cat(sprintf("\nFormal enforcement records:  %d\n", nrow(formal)))
cat(sprintf("Unique PWSIDs, formal:       %d (%.1f%% of sample)\n",
    length(unique(formal$PWSID)), 100 * length(unique(formal$PWSID)) / length(sample_ids)))

# PWSID-year aggregation
enf_agg <- enf_yr %>%
  group_by(PWSID, year) %>%
  summarise(
    n_enf        = n(),
    n_formal     = sum(ENF_ACTION_CATEGORY == "Formal",   na.rm = TRUE),
    n_informal   = sum(ENF_ACTION_CATEGORY == "Informal", na.rm = TRUE),
    n_mr         = sum(VIOLATION_CATEGORY_CODE == "MR",   na.rm = TRUE),
    n_federal    = sum(ENF_ORIGINATOR_CODE == "F",        na.rm = TRUE),
    .groups = "drop"
  )

cat(sprintf("\nPWSID-years with >=1 enf action:  %d / %d (%.1f%%)\n",
    nrow(enf_agg), panel_size, 100 * nrow(enf_agg) / panel_size))
cat(sprintf("PWSID-years with formal action:   %d (%.1f%%)\n",
    sum(enf_agg$n_formal > 0), 100 * sum(enf_agg$n_formal > 0) / panel_size))
cat(sprintf("Mean enf actions per active PWSID-year: %.2f\n", mean(enf_agg$n_enf)))

cat("\nEnforcement records per year:\n")
yr_enf <- enf_yr %>% count(year) %>% arrange(year)
print(as.data.frame(yr_enf), row.names = FALSE)

cat("\nDone.\n")
