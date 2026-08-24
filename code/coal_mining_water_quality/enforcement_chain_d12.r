# ============================================================
# Script: enforcement_chain_d12.r
# Purpose: Merge SDWA site visits and enforcement into D1-D2
#          downstream panel; check density; run H2 and H3 regressions
#          H2: instrument -> site visits (n_visits, any_snsv)
#          H3: instrument -> formal enforcement (any_enf, any_formal, mean_rtc_days)
#          Also diagnoses the 2005 enforcement spike.
# Inputs:
#   clean_data/cws_data/prod_vio_sulfur_4step.parquet
#   clean_data/cws_data/prod_vio_sulfur.parquet
#   Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_SITE_VISITS.csv
#   Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.csv
# Outputs:
#   output/reg/h2_visits_d12.tex
#   output/reg/h2_snsv_d12.tex
#   output/reg/h3_enf_d12.tex
#   output/reg/h3_inf_formal_d12.tex
# Author: EK  Date: 2026-04-28
# ============================================================

.libPaths(c("C:/Users/ek559/AppData/Local/R/win-library/4.6", "Z:/ek559/RPackages"))
library(arrow)
library(data.table)
library(fixest)
library(dplyr)

ROOT <- "Z:/ek559/mining_wq"
SDWA <- "Z:/ek559/sdwa_violations/SDWA_latest_downloads"
setwd(ROOT)

# ── Step 1: Load D1-D2 panel ─────────────────────────────────────────────────
cat("Loading D1-D2 panel...\n")
step4 <- read_parquet("clean_data/cws_data/prod_vio_sulfur_4step.parquet")
d12   <- step4[step4$downstream_step <= 2 &
               step4$year >= 1985 & step4$year <= 2005, ]

ids_d12    <- unique(d12$PWSID)
panel_size <- nrow(d12)
cat(sprintf("D1-D2 panel: %d PWSIDs x %d PWSID-years\n\n",
            length(ids_d12), panel_size))

# ── Step 1b: Load D1 main panel (prod_vio_sulfur.parquet, same sample as didhet.r) ──
cat("Loading D1 main panel (prod_vio_sulfur.parquet)...\n")
main_pvs  <- read_parquet("clean_data/cws_data/prod_vio_sulfur.parquet")
d1_main   <- main_pvs[main_pvs$minehuc_downstream_of_mine == 1 &
                       main_pvs$minehuc_mine == 0 &
                       main_pvs$year >= 1985 & main_pvs$year <= 2005 &
                       main_pvs$PWSID != "WV3303401", ]
ids_d1_main <- unique(d1_main$PWSID)
cat(sprintf("D1 main panel: %d PWSIDs x %d PWSID-years\n\n",
            length(ids_d1_main), nrow(d1_main)))
rm(main_pvs); gc()

# ── Step 2: Site visits ───────────────────────────────────────────────────────
cat("Reading SDWA_SITE_VISITS.csv (355 MB)...\n")
sv <- fread(file.path(SDWA, "SDWA_SITE_VISITS.csv"),
            select = c("PWSID", "VISIT_DATE", "VISIT_REASON_CODE", "AGENCY_TYPE_CODE"))
sv <- sv[PWSID %in% union(ids_d12, ids_d1_main)]

# Parse year from last 4 chars of VISIT_DATE (handles MM/DD/YYYY)
sv[, year := as.integer(substr(trimws(VISIT_DATE),
                               nchar(trimws(VISIT_DATE)) - 3,
                               nchar(trimws(VISIT_DATE))))]
sv <- sv[!is.na(year) & year >= 1985 & year <= 2005]

cat(sprintf("Site visits in D1-D2 (1985-2005): %d\n", nrow(sv)))
cat(sprintf("PWSIDs with >=1 visit: %d / %d (%.1f%%)\n",
    length(unique(sv$PWSID)), length(ids_d12),
    100 * length(unique(sv$PWSID)) / length(ids_d12)))

sv_agg <- sv[, .(n_visits = .N,
                  any_snsv     = any(VISIT_REASON_CODE %in% c("SNSV", "SSVF")),
                  any_tech     = any(VISIT_REASON_CODE %in% c("TECH", "ENGR", "OM")),
                  any_enfvisit = any(VISIT_REASON_CODE %in% c("FENF", "INVG", "EMRG")),
                  any_smpl     = any(VISIT_REASON_CODE == "SMPL"),
                  any_insp     = any(VISIT_REASON_CODE %in% c("SITE", "RSCH", "INFI"))),
              by = .(PWSID, year)]
cat(sprintf("PWSID-years with >=1 visit: %d / %d (%.1f%%)\n",
    nrow(sv_agg), panel_size, 100 * nrow(sv_agg) / panel_size))
cat(sprintf("Mean visits per active PWSID-year: %.2f\n",
    mean(sv_agg$n_visits)))

cat("\nVisit reason code breakdown (D1-D2):\n")
print(sort(table(sv$VISIT_REASON_CODE), decreasing = TRUE))

cat("\nVisits per year (D1-D2) — check for 1993-1994 anomaly:\n")
yr_sv <- sv[, .N, by = year][order(year)]
print(as.data.frame(yr_sv))

# ── Cache visit aggregates so future subsample work can skip the 355 MB read ──
cache_dir <- file.path(ROOT, "clean_data", "cws_data")
dir.create(cache_dir, showWarnings = FALSE, recursive = TRUE)

sv_cache <- file.path(cache_dir, "sdwa_visit_agg_d12.parquet")
if (file.exists(sv_cache)) cat("NOTE: overwriting existing cache:", sv_cache, "\n")
sv_out <- as.data.frame(sv_agg)
sv_out$PWSID <- as.character(sv_out$PWSID)
sv_out$year  <- as.integer(sv_out$year)
arrow::write_parquet(sv_out, sv_cache)
cat("Cached visit aggregates:", nrow(sv_out), "rows ->", sv_cache, "\n")

rm(sv); gc()

# ── Step 3: Violations/enforcement (3.7 GB — column select) ──────────────────
cat("\nReading SDWA_VIOLATIONS_ENFORCEMENT.csv (3.7 GB, 7 cols selected)...\n")
enf <- fread(file.path(SDWA, "SDWA_VIOLATIONS_ENFORCEMENT.csv"),
             select = c("PWSID", "COMPL_PER_BEGIN_DATE", "NON_COMPL_PER_BEGIN_DATE",
                        "CALCULATED_RTC_DATE", "ENF_ACTION_CATEGORY",
                        "VIOLATION_CATEGORY_CODE", "ENF_ORIGINATOR_CODE"))
ids_all <- union(ids_d12, ids_d1_main)
enf <- enf[PWSID %in% ids_all]

enf[, year := as.integer(substr(trimws(COMPL_PER_BEGIN_DATE),
                                nchar(trimws(COMPL_PER_BEGIN_DATE)) - 3,
                                nchar(trimws(COMPL_PER_BEGIN_DATE))))]
enf <- enf[!is.na(year) & year >= 1985 & year <= 2005]

cat(sprintf("Enforcement records in D1-D2 (1985-2005): %d\n", nrow(enf)))
cat(sprintf("PWSIDs with >=1 record: %d / %d (%.1f%%)\n",
    length(unique(enf$PWSID)), length(ids_d12),
    100 * length(unique(enf$PWSID)) / length(ids_d12)))

cat("\nENF_ACTION_CATEGORY breakdown (D1-D2):\n")
print(sort(table(enf$ENF_ACTION_CATEGORY), decreasing = TRUE))

cat("\nVIOLATION_CATEGORY_CODE breakdown (D1-D2):\n")
print(sort(table(enf$VIOLATION_CATEGORY_CODE), decreasing = TRUE))

# Days to return-to-compliance (NON_COMPL_PER_BEGIN_DATE → CALCULATED_RTC_DATE)
enf[, begin_date := as.Date(NON_COMPL_PER_BEGIN_DATE, format = "%m/%d/%Y")]
enf[, rtc_date   := as.Date(CALCULATED_RTC_DATE,      format = "%m/%d/%Y")]
enf[, days_to_rtc := as.numeric(rtc_date - begin_date)]
# Drop implausible values (negative or > 10 years)
enf[days_to_rtc < 0 | days_to_rtc > 3650, days_to_rtc := NA_real_]

n_rtc <- sum(!is.na(enf$days_to_rtc))
cat(sprintf("\ndays_to_rtc: valid in %d / %d records (%.1f%%)\n",
    n_rtc, nrow(enf), 100 * n_rtc / nrow(enf)))
cat(sprintf("  Median: %.0f days  Mean: %.0f days\n",
    median(enf$days_to_rtc, na.rm = TRUE),
    mean(enf$days_to_rtc,   na.rm = TRUE)))

formal_d12 <- enf[ENF_ACTION_CATEGORY == "Formal"]
enf_agg <- enf[, .(n_enf         = .N,
                    any_enf       = TRUE,
                    any_informal  = any(ENF_ACTION_CATEGORY == "Informal", na.rm = TRUE),
                    any_formal    = any(ENF_ACTION_CATEGORY == "Formal", na.rm = TRUE),
                    mean_rtc_days = mean(days_to_rtc, na.rm = TRUE)),
                by = .(PWSID, year)]
cat(sprintf("\nPWSID-years with >=1 enf action:   %d / %d (%.1f%%)\n",
    nrow(enf_agg), panel_size, 100 * nrow(enf_agg) / panel_size))
cat(sprintf("PWSID-years with informal action:  %d (%.1f%%)\n",
    sum(enf_agg$any_informal), 100 * sum(enf_agg$any_informal) / panel_size))
cat(sprintf("PWSID-years with formal action:    %d (%.1f%%)\n",
    sum(enf_agg$any_formal), 100 * sum(enf_agg$any_formal) / panel_size))
cat(sprintf("Unique PWSIDs with formal action: %d (%.1f%%)\n",
    length(unique(formal_d12$PWSID)),
    100 * length(unique(formal_d12$PWSID)) / length(ids_d12)))

# ── Cache enforcement aggregates so future subsample work can skip the 3.9 GB read ──
enf_cache <- file.path(cache_dir, "sdwa_enf_agg_d12.parquet")
if (file.exists(enf_cache)) cat("NOTE: overwriting existing cache:", enf_cache, "\n")
enf_out <- as.data.frame(enf_agg)
enf_out$PWSID <- as.character(enf_out$PWSID)
enf_out$year  <- as.integer(enf_out$year)
arrow::write_parquet(enf_out, enf_cache)
cat("Cached enforcement aggregates:", nrow(enf_out), "rows ->", enf_cache, "\n")

cat("\nEnforcement records per year (D1-D2) — check 1993-1994 spike:\n")
yr_enf <- enf[, .N, by = year][order(year)]
print(as.data.frame(yr_enf))

# ── 2005 spike investigation ──────────────────────────────────────────────────
cat("\n=== 2005 SPIKE INVESTIGATION ===\n")
enf[, noncmpl_year := as.integer(substr(trimws(NON_COMPL_PER_BEGIN_DATE),
                                        nchar(trimws(NON_COMPL_PER_BEGIN_DATE)) - 3,
                                        nchar(trimws(NON_COMPL_PER_BEGIN_DATE))))]

spike <- enf[year == 2005]
cat(sprintf("Records where COMPL_PER_BEGIN_DATE year = 2005: %d\n", nrow(spike)))

cat("\nNON_COMPL_PER_BEGIN_DATE year for these records:\n")
print(sort(table(spike$noncmpl_year), decreasing = TRUE))

cat("\nENF_ACTION_CATEGORY for 2005 records:\n")
print(sort(table(spike$ENF_ACTION_CATEGORY), decreasing = TRUE))

cat("\nVIOLATION_CATEGORY_CODE for 2005 records:\n")
print(sort(table(spike$VIOLATION_CATEGORY_CODE), decreasing = TRUE))

cat("\nTop 10 PWSIDs by record count in 2005:\n")
print(head(spike[, .N, by = PWSID][order(-N)], 10))

# Check: if we use NON_COMPL_PER_BEGIN_DATE year instead, what does the per-year
# count look like for 2005 records?
cat("\nIf we reassign 2005 COMPL records by NON_COMPL year:\n")
yr_noncmpl_2005 <- spike[!is.na(noncmpl_year), .N, by = noncmpl_year][order(noncmpl_year)]
print(as.data.frame(yr_noncmpl_2005))

rm(spike); gc()

# Summary: should we use NON_COMPL_PER_BEGIN_DATE for year assignment?
# If most 2005 COMPL records have non-compliance years spread across earlier years,
# the spike is a COMPL_PER date artifact and NON_COMPL is the right date to use.
cat("\nYear distribution using NON_COMPL_PER_BEGIN_DATE (all D1-D2 records 1985-2005):\n")
yr_noncmpl <- enf[!is.na(noncmpl_year) & noncmpl_year >= 1985 & noncmpl_year <= 2005,
                   .N, by = noncmpl_year][order(noncmpl_year)]
print(as.data.frame(yr_noncmpl))

rm(enf, formal_d12); gc()

# ── Step 4: Build regression panel ───────────────────────────────────────────
cat("\nBuilding regression panel...\n")
panel <- d12 %>%
  left_join(as.data.frame(sv_agg),  by = c("PWSID", "year")) %>%
  left_join(as.data.frame(enf_agg), by = c("PWSID", "year"))

panel$n_visits[is.na(panel$n_visits)]         <- 0L
panel$any_snsv[is.na(panel$any_snsv)]         <- FALSE
panel$any_tech[is.na(panel$any_tech)]         <- FALSE
panel$any_enfvisit[is.na(panel$any_enfvisit)] <- FALSE
panel$any_smpl[is.na(panel$any_smpl)]         <- FALSE
panel$any_insp[is.na(panel$any_insp)]         <- FALSE
panel$any_enf[is.na(panel$any_enf)]           <- FALSE
panel$any_informal[is.na(panel$any_informal)] <- FALSE
panel$any_formal[is.na(panel$any_formal)]     <- FALSE
# mean_rtc_days: leave NA for PWSID-years with no enforcement (outcome is conditional)

# Convert binary outcomes to integer for LPM
panel$any_snsv     <- as.integer(panel$any_snsv)
panel$any_tech     <- as.integer(panel$any_tech)
panel$any_enfvisit <- as.integer(panel$any_enfvisit)
panel$any_smpl     <- as.integer(panel$any_smpl)
panel$any_insp     <- as.integer(panel$any_insp)
panel$any_enf      <- as.integer(panel$any_enf)
panel$any_informal <- as.integer(panel$any_informal)
panel$any_formal   <- as.integer(panel$any_formal)

cat(sprintf("Regression panel: %d PWSID-years\n", nrow(panel)))
cat(sprintf("Mean n_visits: %.3f  (SD: %.3f)\n",
    mean(panel$n_visits), sd(panel$n_visits)))
cat(sprintf("n_visits > 0: %d (%.1f%% of panel)\n",
    sum(panel$n_visits > 0), 100 * mean(panel$n_visits > 0)))

# Confirm instrument and treatment are present
stopifnot("post95"            %in% names(panel))
stopifnot("sulfur_upstream"   %in% names(panel))
stopifnot("num_coal_mines_upstream" %in% names(panel))
stopifnot("STATE_CODE"        %in% names(panel))

# D1 main panel (prod_vio_sulfur.parquet, one step downstream, same as didhet.r "dwnstrm")
cat("\nBuilding D1 main regression panel...\n")
panel_d1 <- d1_main %>%
  left_join(as.data.frame(sv_agg),  by = c("PWSID", "year")) %>%
  left_join(as.data.frame(enf_agg), by = c("PWSID", "year"))
panel_d1$n_visits[is.na(panel_d1$n_visits)]         <- 0L
panel_d1$any_snsv[is.na(panel_d1$any_snsv)]         <- FALSE
panel_d1$any_tech[is.na(panel_d1$any_tech)]         <- FALSE
panel_d1$any_enfvisit[is.na(panel_d1$any_enfvisit)] <- FALSE
panel_d1$any_smpl[is.na(panel_d1$any_smpl)]         <- FALSE
panel_d1$any_insp[is.na(panel_d1$any_insp)]         <- FALSE
panel_d1$any_snsv     <- as.integer(panel_d1$any_snsv)
panel_d1$any_tech     <- as.integer(panel_d1$any_tech)
panel_d1$any_enfvisit <- as.integer(panel_d1$any_enfvisit)
panel_d1$any_smpl     <- as.integer(panel_d1$any_smpl)
panel_d1$any_insp     <- as.integer(panel_d1$any_insp)
panel_d1$any_enf[is.na(panel_d1$any_enf)]           <- FALSE
panel_d1$any_informal[is.na(panel_d1$any_informal)] <- FALSE
panel_d1$any_formal[is.na(panel_d1$any_formal)]     <- FALSE
panel_d1$any_enf      <- as.integer(panel_d1$any_enf)
panel_d1$any_informal <- as.integer(panel_d1$any_informal)
panel_d1$any_formal   <- as.integer(panel_d1$any_formal)
panel_d1$no_enf       <- 1L - panel_d1$any_enf
cat(sprintf("D1 main panel: %d PWSID-years\n", nrow(panel_d1)))
cat(sprintf("any_informal = 1 in %d (%.1f%%)\n",
    sum(panel_d1$any_informal), 100 * mean(panel_d1$any_informal)))
cat(sprintf("any_formal   = 1 in %d (%.1f%%)\n",
    sum(panel_d1$any_formal),   100 * mean(panel_d1$any_formal)))

# ── Surface-water subsample: D1 panel restricted to CWSs whose primary water
# source is surface water, to test whether the enforcement-chain results are
# driven by surface-water or groundwater systems. ────────────────────────────
sw_codes    <- c("SW", "SWP")
stopifnot("PRIMARY_SOURCE_CODE" %in% names(panel_d1))
panel_d1_sw <- panel_d1[panel_d1$PRIMARY_SOURCE_CODE %in% sw_codes, ]
cat(sprintf("\nD1 surface-water panel: %d CWS-years, %d CWSs\n",
            nrow(panel_d1_sw), length(unique(panel_d1_sw$PWSID))))
for (oc in c("any_snsv","any_tech","any_enfvisit","any_smpl","any_insp",
             "any_informal","any_formal","no_enf")) {
  cat(sprintf("  %-14s = 1 in %d (%.1f%%)\n", oc,
              sum(panel_d1_sw[[oc]]), 100 * mean(panel_d1_sw[[oc]])))
}

has_variation <- function(dset, y) {
  v <- dset[[y]]
  v <- v[!is.na(v)]
  length(v) > 0L && length(unique(v)) > 1L
}

# ── Step 5: H2 regression ────────────────────────────────────────────────────
cat("\n=== H2: Regulator site visits ~ mining (D1-D2) ===\n")

fml_ols <- n_visits ~ num_coal_mines_upstream + num_facilities |
           PWSID + year + STATE_CODE
fml_rf  <- n_visits ~ post95:sulfur_upstream  + num_facilities |
           PWSID + year + STATE_CODE
fml_iv  <- n_visits ~ num_facilities | PWSID + year + STATE_CODE |
           num_coal_mines_upstream ~ post95:sulfur_upstream

ols <- feols(fml_ols, data = panel, cluster = ~PWSID)
rf  <- feols(fml_rf,  data = panel, cluster = ~PWSID)
iv  <- feols(fml_iv,  data = panel, cluster = ~PWSID)

cat("\n--- OLS ---\n");         print(summary(ols))
cat("\n--- Reduced form ---\n"); print(summary(rf))
cat("\n--- 2SLS (H2) ---\n");   print(summary(iv))
cat(sprintf("\nFirst-stage F-stat: %.1f\n", fitstat(iv, "ivf")[[1]]$stat))

# ── Step 5b: H2b — visit-type binaries (LPM), all 5 categories ──────────────
# Categories match output/sum/visit_type_summary.tex:
#   Sanitary visits (SNSV, SSVF), Technical assistance (TECH, ENGR, OM),
#   Enforcement visits (FENF, INVG, EMRG), Sample collection (SMPL),
#   Inspection (SITE, RSCH, INFI).
visit_outcomes <- c(any_snsv     = "Sanitary visits",
                     any_tech     = "Technical assistance",
                     any_enfvisit = "Enforcement visits",
                     any_smpl     = "Sample collection",
                     any_insp     = "Inspection")

cat("\n=== H2b: Any visit by type (binary, LPM) ~ mining (D1 main panel) ===\n")

models_b <- list()
for (oc in names(visit_outcomes)) {
  cat(sprintf("\n%s (%s) = 1 in %d / %d CWS-years (%.1f%%)\n",
      oc, visit_outcomes[oc], sum(panel_d1[[oc]]), nrow(panel_d1),
      100 * mean(panel_d1[[oc]])))

  fml_ols_oc <- as.formula(paste0(oc, " ~ num_coal_mines_upstream_sum + num_facilities | PWSID + year"))
  fml_rf_oc  <- as.formula(paste0(oc, " ~ post95:sulfur_unified_mean + num_facilities | PWSID + year"))
  fml_iv_oc  <- as.formula(paste0(oc, " ~ num_facilities | PWSID + year | num_coal_mines_upstream_sum ~ post95:sulfur_unified_mean"))

  models_b[[paste0(oc, "_ols")]] <- feols(fml_ols_oc, data = panel_d1, cluster = ~PWSID)
  models_b[[paste0(oc, "_rf")]]  <- feols(fml_rf_oc,  data = panel_d1, cluster = ~PWSID)
  models_b[[paste0(oc, "_iv")]]  <- feols(fml_iv_oc,  data = panel_d1, cluster = ~PWSID)

  cat(sprintf("\n--- OLS (%s, D1) ---\n", oc));         print(summary(models_b[[paste0(oc, "_ols")]]))
  cat(sprintf("\n--- Reduced form (%s, D1) ---\n", oc)); print(summary(models_b[[paste0(oc, "_rf")]]))
  cat(sprintf("\n--- 2SLS (%s, D1) ---\n", oc));        print(summary(models_b[[paste0(oc, "_iv")]]))
}

# Clustered first-stage F-stat (no state FE, matches table spec). The first
# stage is identical across outcomes (same treatment/instrument/sample), so
# it is computed once and reused for every 2SLS column.
f_fs_b <- feols(num_coal_mines_upstream_sum ~ post95:sulfur_unified_mean + num_facilities |
                PWSID + year, data = panel_d1, cluster = ~PWSID)
t_cl_b <- coef(f_fs_b)["post95:sulfur_unified_mean"] / se(f_fs_b)["post95:sulfur_unified_mean"]
f_cl_b <- round(t_cl_b^2, 2)
cat(sprintf("\nClustered first-stage F-stat (H2b, D1): %.2f\n", f_cl_b))

# ── Step 5c: H3 — formal enforcement actions ──────────────────────────────────
cat("\n=== H3: Enforcement actions ~ mining (D1-D2) ===\n")
cat(sprintf("any_enf      = 1 in %d PWSID-years (%.1f%%)\n",
    sum(panel$any_enf),      100 * mean(panel$any_enf)))
cat(sprintf("any_informal = 1 in %d PWSID-years (%.1f%%)\n",
    sum(panel$any_informal), 100 * mean(panel$any_informal)))
cat(sprintf("any_formal   = 1 in %d PWSID-years (%.1f%%)\n",
    sum(panel$any_formal),   100 * mean(panel$any_formal)))
cat(sprintf("mean_rtc_days available in %d PWSID-years\n",
    sum(!is.na(panel$mean_rtc_days))))

# H3a: any enforcement action (binary, 16.7% density — well powered)
fml_ols_e <- any_enf ~ num_coal_mines_upstream + num_facilities |
             PWSID + year + STATE_CODE
fml_rf_e  <- any_enf ~ post95:sulfur_upstream  + num_facilities |
             PWSID + year + STATE_CODE
fml_iv_e  <- any_enf ~ num_facilities | PWSID + year + STATE_CODE |
             num_coal_mines_upstream ~ post95:sulfur_upstream

ols_e <- feols(fml_ols_e, data = panel, cluster = ~PWSID)
rf_e  <- feols(fml_rf_e,  data = panel, cluster = ~PWSID)
iv_e  <- feols(fml_iv_e,  data = panel, cluster = ~PWSID)

cat("\n--- OLS (any_enf) ---\n");         print(summary(ols_e))
cat("\n--- Reduced form (any_enf) ---\n"); print(summary(rf_e))
cat("\n--- 2SLS (any_enf) ---\n");        print(summary(iv_e))
cat(sprintf("\nFirst-stage F-stat (H3a): %.1f\n", fitstat(iv_e, "ivf")[[1]]$stat))

# H3b: formal enforcement only (binary, 2.4% — sparse)
fml_ols_f <- any_formal ~ num_coal_mines_upstream + num_facilities |
             PWSID + year + STATE_CODE
fml_rf_f  <- any_formal ~ post95:sulfur_upstream  + num_facilities |
             PWSID + year + STATE_CODE
fml_iv_f  <- any_formal ~ num_facilities | PWSID + year + STATE_CODE |
             num_coal_mines_upstream ~ post95:sulfur_upstream

ols_f <- feols(fml_ols_f, data = panel, cluster = ~PWSID)
rf_f  <- feols(fml_rf_f,  data = panel, cluster = ~PWSID)
iv_f  <- feols(fml_iv_f,  data = panel, cluster = ~PWSID)

cat("\n--- OLS (any_formal) ---\n");         print(summary(ols_f))
cat("\n--- Reduced form (any_formal) ---\n"); print(summary(rf_f))
cat("\n--- 2SLS (any_formal) ---\n");        print(summary(iv_f))
cat(sprintf("\nFirst-stage F-stat (H3b): %.1f\n", fitstat(iv_f, "ivf")[[1]]$stat))

# H3a2: informal enforcement only (binary)
fml_ols_i <- any_informal ~ num_coal_mines_upstream + num_facilities |
             PWSID + year + STATE_CODE
fml_rf_i  <- any_informal ~ post95:sulfur_upstream  + num_facilities |
             PWSID + year + STATE_CODE
fml_iv_i  <- any_informal ~ num_facilities | PWSID + year + STATE_CODE |
             num_coal_mines_upstream ~ post95:sulfur_upstream

ols_i <- feols(fml_ols_i, data = panel, cluster = ~PWSID)
rf_i  <- feols(fml_rf_i,  data = panel, cluster = ~PWSID)
iv_i  <- feols(fml_iv_i,  data = panel, cluster = ~PWSID)

cat("\n--- OLS (any_informal) ---\n");         print(summary(ols_i))
cat("\n--- Reduced form (any_informal) ---\n"); print(summary(rf_i))
cat("\n--- 2SLS (any_informal) ---\n");        print(summary(iv_i))
cat(sprintf("\nFirst-stage F-stat (H3a2): %.1f\n", fitstat(iv_i, "ivf")[[1]]$stat))

# ── H3 on D1 main panel (prod_vio_sulfur.parquet, num_coal_mines_upstream_sum) ──
cat("\n=== H3 (D1 main): Informal/formal enforcement ~ mining ===\n")

fml_ols_id1 <- any_informal ~ num_coal_mines_upstream_sum + num_facilities |
               PWSID + year
fml_rf_id1  <- any_informal ~ post95:sulfur_unified_mean  + num_facilities |
               PWSID + year
fml_iv_id1  <- any_informal ~ num_facilities | PWSID + year |
               num_coal_mines_upstream_sum ~ post95:sulfur_unified_mean

ols_id1 <- feols(fml_ols_id1, data = panel_d1, cluster = ~PWSID)
rf_id1  <- feols(fml_rf_id1,  data = panel_d1, cluster = ~PWSID)
iv_id1  <- feols(fml_iv_id1,  data = panel_d1, cluster = ~PWSID)

fml_ols_fd1 <- any_formal ~ num_coal_mines_upstream_sum + num_facilities |
               PWSID + year
fml_rf_fd1  <- any_formal ~ post95:sulfur_unified_mean  + num_facilities |
               PWSID + year
fml_iv_fd1  <- any_formal ~ num_facilities | PWSID + year |
               num_coal_mines_upstream_sum ~ post95:sulfur_unified_mean

ols_fd1 <- feols(fml_ols_fd1, data = panel_d1, cluster = ~PWSID)
rf_fd1  <- feols(fml_rf_fd1,  data = panel_d1, cluster = ~PWSID)
iv_fd1  <- feols(fml_iv_fd1,  data = panel_d1, cluster = ~PWSID)

fml_ols_ned1 <- no_enf ~ num_coal_mines_upstream_sum + num_facilities |
                PWSID + year
fml_rf_ned1  <- no_enf ~ post95:sulfur_unified_mean  + num_facilities |
                PWSID + year
fml_iv_ned1  <- no_enf ~ num_facilities | PWSID + year |
                num_coal_mines_upstream_sum ~ post95:sulfur_unified_mean

ols_ned1 <- feols(fml_ols_ned1, data = panel_d1, cluster = ~PWSID)
rf_ned1  <- feols(fml_rf_ned1,  data = panel_d1, cluster = ~PWSID)
iv_ned1  <- feols(fml_iv_ned1,  data = panel_d1, cluster = ~PWSID)

# Clustered first-stage F-stat: t^2 from separate clustered first-stage regression.
# fixest ivf uses HC1 SEs; this is the cluster-robust version (same approach as didhet.r).
f_fs_d1 <- feols(num_coal_mines_upstream_sum ~ post95:sulfur_unified_mean + num_facilities |
                 PWSID + year, data = panel_d1, cluster = ~PWSID)
t_cl_d1 <- coef(f_fs_d1)["post95:sulfur_unified_mean"] /
            se(f_fs_d1)["post95:sulfur_unified_mean"]
f_cl_d1 <- round(t_cl_d1^2, 2)
cat(sprintf("Clustered first-stage F-stat (D1 main): %.2f\n", f_cl_d1))

cat("\n--- OLS (any_informal, D1 main) ---\n");         print(summary(ols_id1))
cat("\n--- Reduced form (any_informal, D1 main) ---\n"); print(summary(rf_id1))
cat("\n--- 2SLS (any_informal, D1 main) ---\n");        print(summary(iv_id1))
cat("\n--- OLS (any_formal, D1 main) ---\n");           print(summary(ols_fd1))
cat("\n--- Reduced form (any_formal, D1 main) ---\n");  print(summary(rf_fd1))
cat("\n--- 2SLS (any_formal, D1 main) ---\n");         print(summary(iv_fd1))

# ── H3b robustness: sample restrictions ──────────────────────────────────────
cat("\n=== H3b ROBUSTNESS: sample restrictions (any_formal) ===\n")

# Drop 2005 (WA5340950 data spike)
panel_no2005 <- panel[panel$year <= 2004, ]
cat(sprintf("Drop 2005: %d PWSID-years\n", nrow(panel_no2005)))
iv_f_no2005 <- feols(fml_iv_f, data = panel_no2005, cluster = ~PWSID)

# Drop pre-1993 (thin early data)
panel_post93 <- panel[panel$year >= 1993, ]
cat(sprintf("Drop pre-1993: %d PWSID-years\n", nrow(panel_post93)))
iv_f_post93 <- feols(fml_iv_f, data = panel_post93, cluster = ~PWSID)

# Drop both: 1993-2004 only
panel_93_04 <- panel[panel$year >= 1993 & panel$year <= 2004, ]
cat(sprintf("1993-2004 only: %d PWSID-years\n", nrow(panel_93_04)))
iv_f_93_04 <- feols(fml_iv_f, data = panel_93_04, cluster = ~PWSID)

cat("\n--- H3b robustness summary (2SLS, any_formal) ---\n")
cat(sprintf("Baseline (1985-2005):  coef = %.4f  SE = %.4f  p = %.4f  F = %.1f\n",
    coef(iv_f)["fit_num_coal_mines_upstream"],
    se(iv_f)["fit_num_coal_mines_upstream"],
    pvalue(iv_f)["fit_num_coal_mines_upstream"],
    fitstat(iv_f, "ivf")[[1]]$stat))
cat(sprintf("Drop 2005 (1985-2004): coef = %.4f  SE = %.4f  p = %.4f  F = %.1f\n",
    coef(iv_f_no2005)["fit_num_coal_mines_upstream"],
    se(iv_f_no2005)["fit_num_coal_mines_upstream"],
    pvalue(iv_f_no2005)["fit_num_coal_mines_upstream"],
    fitstat(iv_f_no2005, "ivf")[[1]]$stat))
cat(sprintf("Drop pre-1993 (1993-2005): coef = %.4f  SE = %.4f  p = %.4f  F = %.1f\n",
    coef(iv_f_post93)["fit_num_coal_mines_upstream"],
    se(iv_f_post93)["fit_num_coal_mines_upstream"],
    pvalue(iv_f_post93)["fit_num_coal_mines_upstream"],
    fitstat(iv_f_post93, "ivf")[[1]]$stat))
cat(sprintf("1993-2004 only:        coef = %.4f  SE = %.4f  p = %.4f  F = %.1f\n",
    coef(iv_f_93_04)["fit_num_coal_mines_upstream"],
    se(iv_f_93_04)["fit_num_coal_mines_upstream"],
    pvalue(iv_f_93_04)["fit_num_coal_mines_upstream"],
    fitstat(iv_f_93_04, "ivf")[[1]]$stat))

# H3c: mean days to RTC (conditional on enforcement record existing)
panel_enf <- panel[!is.na(panel$mean_rtc_days), ]
cat(sprintf("\nH3c sample (PWSID-years with enforcement): %d\n", nrow(panel_enf)))

fml_ols_r <- mean_rtc_days ~ num_coal_mines_upstream + num_facilities |
             PWSID + year + STATE_CODE
fml_rf_r  <- mean_rtc_days ~ post95:sulfur_upstream  + num_facilities |
             PWSID + year + STATE_CODE
fml_iv_r  <- mean_rtc_days ~ num_facilities | PWSID + year + STATE_CODE |
             num_coal_mines_upstream ~ post95:sulfur_upstream

ols_r <- feols(fml_ols_r, data = panel_enf, cluster = ~PWSID)
rf_r  <- feols(fml_rf_r,  data = panel_enf, cluster = ~PWSID)
iv_r  <- feols(fml_iv_r,  data = panel_enf, cluster = ~PWSID)

cat("\n--- OLS (mean_rtc_days) ---\n");         print(summary(ols_r))
cat("\n--- Reduced form (mean_rtc_days) ---\n"); print(summary(rf_r))
cat("\n--- 2SLS (mean_rtc_days) ---\n");        print(summary(iv_r))
cat(sprintf("\nFirst-stage F-stat (H3c): %.1f\n", fitstat(iv_r, "ivf")[[1]]$stat))

# ── Step 6: LaTeX tables ──────────────────────────────────────────────────────

# Wraps a fixest etable .tex file so it scales automatically in both beamer
# (constrained by slide height) and regular LaTeX documents.
wrap_for_beamer <- function(path, beamer_height = "0.78\\textheight") {
  header <- c(
    "\\makeatletter",
    paste0("\\@ifclassloaded{beamer}{%\n",
           "  \\begin{adjustbox}{max width=\\linewidth,",
           " max totalheight=", beamer_height, ", center}%\n",
           "}{%\n",
           "  \\begin{adjustbox}{max width=\\linewidth, center}%\n",
           "}%"),
    "\\makeatother"
  )
  lines <- readLines(path)
  note_start  <- grep("^\\\\par \\\\raggedright\\s*$", lines)
  endgroup_ln <- grep("^\\\\par\\\\endgroup\\s*$",     lines)
  if (length(note_start) == 1 && length(endgroup_ln) == 1 && note_start < endgroup_ln) {
    note_text <- lines[(note_start + 1):(endgroup_ln - 1)]
    body      <- c(lines[seq_len(note_start - 1)], "\\par\\endgroup")
    writeLines(c(header, body, "\\end{adjustbox}", "",
                 "\\par \\raggedright", note_text, "\\par"), path)
  } else {
    writeLines(c(header, lines, "\\end{adjustbox}"), path)
  }
}

# Post-processing helpers for style.tex("aer") tables
move_notes_below_adjustbox <- function(x) {
  x           <- paste(x, collapse = "\n")
  end_adj     <- "\\end{adjustbox}"
  par_rag     <- "\\par \\raggedright"
  par_pos     <- regexpr(par_rag, x, fixed = TRUE)
  end_adj_pos <- regexpr(end_adj, x, fixed = TRUE)
  if (par_pos[1] == -1 || end_adj_pos[1] == -1) return(x)
  note_block <- substr(x, par_pos[1], end_adj_pos[1] - 1)
  x <- sub(note_block, "", x, fixed = TRUE)
  x <- sub(end_adj,
            paste0(end_adj, "\n   {\\tiny\\linespread{1}\\selectfont ",
                   trimws(note_block), "}"),
            x, fixed = TRUE)
  x
}

rename_col_numbers_to_labels <- function(x) {
  x     <- paste(x, collapse = "\n")
  lines <- strsplit(x, "\n")[[1]]
  for (i in seq_along(lines)) {
    nums <- regmatches(lines[i], gregexpr("\\(\\d+\\)", lines[i]))[[1]]
    if (length(nums) >= 2) {
      num_vals <- as.integer(gsub("[()]", "", nums))
      if (identical(num_vals, seq_along(num_vals))) {
        labels <- rep(c("OLS", "RF", "2SLS"), length.out = length(nums))
        line   <- lines[i]
        for (j in seq_along(nums)) line <- sub(nums[j], labels[j], line, fixed = TRUE)
        lines[i] <- line
      }
    }
  }
  paste(lines, collapse = "\n")
}

postprocess_table <- function(x) rename_col_numbers_to_labels(move_notes_below_adjustbox(x))

dir.create(file.path(ROOT, "output/reg"), showWarnings = FALSE, recursive = TRUE)
out_tex <- file.path(ROOT, "output/reg/h2_visits_d12.tex")

etable(ols, rf, iv,
       title   = "H2: Effect of Coal Mining on Regulator Site Visits (D1-D2 Downstream Sample)",
       headers = c("OLS", "Reduced form", "2SLS"),
       notes   = paste0("D1-D2 downstream sample (downstream_step <= 2). ",
                        "N = ", nrow(panel), " PWSID-years. ",
                        "Instrument: post95 x sulfur_upstream. ",
                        "SEs clustered at PWSID level."),
       fitstat = ~r2 + n + ivf,
       file    = out_tex,
       replace = TRUE)

wrap_for_beamer(out_tex)
cat(sprintf("\nTable saved to: %s\n", out_tex))
if (file.exists(out_tex) && file.info(out_tex)$size > 0) {
  cat("Output verified: file exists and is non-zero.\n")
} else {
  stop("Output file missing or empty — check etable() call.")
}

out_tex_b   <- file.path(ROOT, "output/reg/h2_snsv_d12.tex")
f_label_b   <- "F-test (1st stage, clustered), Upstream coal mines (sum)"
f_vec_b     <- rep(c("", "", format(f_cl_b, nsmall = 2)), length(visit_outcomes))
el_b        <- list(f_vec_b)
names(el_b) <- f_label_b

dict_b <- c(
  "any_snsv"                        = "Sanitary visits",
  "any_tech"                        = "Technical assistance",
  "any_enfvisit"                    = "Enforcement visits",
  "any_smpl"                        = "Sample collection",
  "any_insp"                        = "Inspection",
  "num_coal_mines_upstream_sum"     = "Upstream coal mines (sum)",
  "fit_num_coal_mines_upstream_sum" = "Upstream coal mines (sum)",
  "post95:sulfur_unified_mean"      = "post95 $\\times$ Upstream sulfur \\%",
  "PWSID"                           = "CWS"
)

etable(models_b,
       title          = "Effect of Coal Mining on Regulator Visit Probability by Visit Type (D1 Downstream Sample, LPM)",
       label          = "tab:h2_snsv_d12",
       dict           = dict_b,
       drop           = "num_facilities",
       extralines     = el_b,
       fitstat        = ~n,
       notes          = paste0("\\textit{Notes:} Sample restricted to community water systems strictly downstream ",
                               "of a coal mine. ",
                               "N = ", nrow(panel_d1), " CWS-years. Each panel of 3 columns (OLS, RF, 2SLS) ",
                               "reports a separate binary outcome: any visit of that type in a CWS-year. ",
                               "Sanitary visits are sanitary surveys and follow-up sanitary surveys. ",
                               "Technical assistance includes technical assistance, engineering ",
                               "determination/advice/plan review, and operation and maintenance visits. ",
                               "Enforcement visits include formal enforcement, investigation, and emergency ",
                               "assistance visits. Sample collection is sample collection visits. Inspection ",
                               "includes site inspections, regularly scheduled visits, and informal system ",
                               "inspections. ",
                               "The instrument interacts an indicator for the post-1995 period with mean ",
                               "upstream coal sulfur content. SEs clustered at the CWS level. ",
                               "*** p$<$0.01, ** p$<$0.05, * p$<$0.1."),
       style.tex      = style.tex("aer", adjustbox = TRUE),
       tex            = TRUE,
       postprocess.tex = postprocess_table,
       file           = out_tex_b,
       replace        = TRUE)
cat(sprintf("\nTable saved to: %s\n", out_tex_b))
if (file.exists(out_tex_b) && file.info(out_tex_b)$size > 0) {
  cat("Output verified: file exists and is non-zero.\n")
} else {
  stop("Output file missing or empty — check etable() call.")
}

# ── Surface-water subsample: H2b table (visit-type LPM), panel_d1_sw ─────────
cat("\n=== H2b (surface water): Any visit by type (binary, LPM) ~ mining (D1 SW panel) ===\n")

models_b_sw   <- list()
outcomes_kept <- character(0)
for (oc in names(visit_outcomes)) {
  if (!has_variation(panel_d1_sw, oc)) {
    cat("  Dropping", oc, "- no variation in surface-water subsample\n"); next
  }
  fml_ols_oc <- as.formula(paste0(oc, " ~ num_coal_mines_upstream_sum + num_facilities | PWSID + year"))
  fml_rf_oc  <- as.formula(paste0(oc, " ~ post95:sulfur_unified_mean + num_facilities | PWSID + year"))
  fml_iv_oc  <- as.formula(paste0(oc, " ~ num_facilities | PWSID + year | num_coal_mines_upstream_sum ~ post95:sulfur_unified_mean"))
  models_b_sw[[paste0(oc, "_ols")]] <- feols(fml_ols_oc, data = panel_d1_sw, cluster = ~PWSID)
  models_b_sw[[paste0(oc, "_rf")]]  <- feols(fml_rf_oc,  data = panel_d1_sw, cluster = ~PWSID)
  models_b_sw[[paste0(oc, "_iv")]]  <- feols(fml_iv_oc,  data = panel_d1_sw, cluster = ~PWSID)
  outcomes_kept <- c(outcomes_kept, oc)
}

f_fs_b_sw <- feols(num_coal_mines_upstream_sum ~ post95:sulfur_unified_mean + num_facilities |
                   PWSID + year, data = panel_d1_sw, cluster = ~PWSID)
f_cl_b_sw <- round((coef(f_fs_b_sw)["post95:sulfur_unified_mean"] /
                    se(f_fs_b_sw)["post95:sulfur_unified_mean"])^2, 2)
cat(sprintf("Clustered first-stage F-stat (H2b, D1 surface water): %.2f\n", f_cl_b_sw))

out_tex_b_sw <- file.path(ROOT, "output/reg/h2_snsv_d12_surfacewater.tex")
el_b_sw        <- list(rep(c("", "", format(f_cl_b_sw, nsmall = 2)), length(outcomes_kept)))
names(el_b_sw) <- f_label_b

visit_note_sentences <- c(
  any_snsv     = "Sanitary visits are sanitary surveys and follow-up sanitary surveys. ",
  any_tech     = paste0("Technical assistance includes technical assistance, engineering ",
                        "determination/advice/plan review, and operation and maintenance visits. "),
  any_enfvisit = paste0("Enforcement visits include formal enforcement, investigation, and emergency ",
                        "assistance visits. "),
  any_smpl     = "Sample collection is sample collection visits. ",
  any_insp     = paste0("Inspection includes site inspections, regularly scheduled visits, and informal ",
                        "system inspections. ")
)
visit_note_block_sw <- paste(visit_note_sentences[outcomes_kept], collapse = "")

etable(models_b_sw,
       title          = "Effect of Coal Mining on Regulator Visit Probability by Visit Type (D1 Downstream Sample, LPM, Surface Water Systems)",
       label          = "tab:h2_snsv_d12_surfacewater",
       dict           = dict_b,
       drop           = "num_facilities",
       extralines     = el_b_sw,
       fitstat        = ~n,
       notes          = paste0("\\textit{Notes:} Sample restricted to community water systems strictly downstream ",
                               "of a coal mine. ",
                               "Sample further restricted to community water systems whose primary water source is surface water. ",
                               "N = ", nrow(panel_d1_sw), " CWS-years. Each panel of 3 columns (OLS, RF, 2SLS) ",
                               "reports a separate binary outcome: any visit of that type in a CWS-year. ",
                               visit_note_block_sw,
                               "The instrument interacts an indicator for the post-1995 period with mean ",
                               "upstream coal sulfur content. SEs clustered at the CWS level. ",
                               "*** p$<$0.01, ** p$<$0.05, * p$<$0.1."),
       style.tex      = style.tex("aer", adjustbox = TRUE),
       tex            = TRUE,
       postprocess.tex = postprocess_table,
       file           = out_tex_b_sw,
       replace        = TRUE)
cat(sprintf("\nTable saved to: %s\n", out_tex_b_sw))
if (file.exists(out_tex_b_sw) && file.info(out_tex_b_sw)$size > 0) {
  cat("Output verified: file exists and is non-zero.\n")
} else {
  stop("Output file missing or empty — check etable() call.")
}

# H3 table: any_enf and any_formal side by side (OLS / RF / 2SLS for each)
out_tex_h3 <- file.path(ROOT, "output/reg/h3_enf_d12.tex")
etable(ols_e, rf_e, iv_e, ols_f, rf_f, iv_f,
       iv_f_no2005, iv_f_post93, iv_f_93_04,
       title   = "H3: Effect of Coal Mining on Enforcement Actions (D1-D2 Downstream Sample)",
       headers = c("Any enf. (OLS)", "Any enf. (RF)", "Any enf. (2SLS)",
                   "Formal (OLS)",   "Formal (RF)",   "Formal (2SLS)",
                   "Formal: drop 2005", "Formal: 1993+", "Formal: 1993-2004"),
       notes   = paste0("D1-D2 downstream sample. Cols 1-3: any enforcement action (16.7% of panel). ",
                        "Cols 4-9: formal enforcement action (2.4% baseline). ",
                        "Cols 7-9: sample robustness checks dropping 2005 spike / pre-1993 thin data. ",
                        "Instrument: post95 x sulfur_upstream. SEs clustered at PWSID level."),
       fitstat = ~r2 + n + ivf,
       file    = out_tex_h3,
       replace = TRUE)

wrap_for_beamer(out_tex_h3)
cat(sprintf("\nTable saved to: %s\n", out_tex_h3))
if (file.exists(out_tex_h3) && file.info(out_tex_h3)$size > 0) {
  cat("Output verified: file exists and is non-zero.\n")
} else {
  stop("Output file missing or empty — check etable() call.")
}

# H3 table: informal vs formal, D1 main sample (one step downstream, same as didhet.r)
out_tex_h3_inf <- file.path(ROOT, "output/reg/h3_inf_formal_d12.tex")
inf_d1_pct <- 100 * mean(panel_d1$any_informal)
frm_d1_pct <- 100 * mean(panel_d1$any_formal)
ned1_pct   <- 100 * mean(panel_d1$no_enf)
f_label_d1 <- "F-test (1st stage, clustered), Upstream coal mines (sum)"
f_vec_d1   <- c("", "", format(round(f_cl_d1, 2), nsmall = 2),
                "", "", format(round(f_cl_d1, 2), nsmall = 2),
                "", "", format(round(f_cl_d1, 2), nsmall = 2))
el_d1 <- list(f_vec_d1)
names(el_d1) <- f_label_d1

dict_enf <- c(
  "any_informal"                    = "Any informal enf",
  "any_formal"                      = "Any formal enf",
  "no_enf"                          = "No enforcement",
  "num_coal_mines_upstream_sum"     = "Upstream coal mines (sum)",
  "fit_num_coal_mines_upstream_sum" = "Upstream coal mines (sum)",
  "post95:sulfur_unified_mean"      = "post95 $\\times$ Upstream sulfur \\%",
  "PWSID"                           = "CWS"
)

etable(ols_id1, rf_id1, iv_id1, ols_fd1, rf_fd1, iv_fd1, ols_ned1, rf_ned1, iv_ned1,
       title          = "Effect of Coal Mining on Enforcement Actions by Type (D1 Downstream Sample)",
       label          = "tab:h3_inf_formal_d12",
       dict           = dict_enf,
       drop           = "num_facilities",
       extralines     = el_d1,
       fitstat        = ~n,
       notes          = paste0("\\textit{Notes:} Sample restricted to community water systems strictly ",
                               "downstream of a coal mine. ",
                               "Cols 1-3: informal enforcement action (",
                               sprintf("%.1f", inf_d1_pct), "% of panel). ",
                               "Cols 4-6: formal enforcement action (",
                               sprintf("%.1f", frm_d1_pct), "% of panel). ",
                               "Cols 7-9: no enforcement (",
                               sprintf("%.1f", ned1_pct), "% of panel). ",
                               "The instrument interacts an indicator for the post-1995 period with mean ",
                               "upstream coal sulfur content. SEs clustered at the CWS level. ",
                               "*** p$<$0.01, ** p$<$0.05, * p$<$0.1."),
       style.tex      = style.tex("aer", adjustbox = TRUE),
       tex            = TRUE,
       postprocess.tex = postprocess_table,
       file           = out_tex_h3_inf,
       replace        = TRUE)
cat(sprintf("\nTable saved to: %s\n", out_tex_h3_inf))
if (file.exists(out_tex_h3_inf) && file.info(out_tex_h3_inf)$size > 0) {
  cat("Output verified: file exists and is non-zero.\n")
} else {
  stop("Output file missing or empty — check etable() call.")
}

# ── Surface-water subsample: H3 informal/formal/no-enforcement table, panel_d1_sw ──
cat("\n=== H3 (D1 surface water): Informal/formal enforcement ~ mining ===\n")

h3_dep_sw <- c(any_informal = "any_informal", any_formal = "any_formal", no_enf = "no_enf")

models_h3_sw <- list()
h3_kept_sw   <- character(0)
for (oc in h3_dep_sw) {
  if (!has_variation(panel_d1_sw, oc)) {
    cat("  Dropping", oc, "- no variation in surface-water subsample\n"); next
  }
  fml_ols_oc <- as.formula(paste0(oc, " ~ num_coal_mines_upstream_sum + num_facilities | PWSID + year"))
  fml_rf_oc  <- as.formula(paste0(oc, " ~ post95:sulfur_unified_mean + num_facilities | PWSID + year"))
  fml_iv_oc  <- as.formula(paste0(oc, " ~ num_facilities | PWSID + year | num_coal_mines_upstream_sum ~ post95:sulfur_unified_mean"))
  models_h3_sw[[paste0(oc, "_ols")]] <- feols(fml_ols_oc, data = panel_d1_sw, cluster = ~PWSID)
  models_h3_sw[[paste0(oc, "_rf")]]  <- feols(fml_rf_oc,  data = panel_d1_sw, cluster = ~PWSID)
  models_h3_sw[[paste0(oc, "_iv")]]  <- feols(fml_iv_oc,  data = panel_d1_sw, cluster = ~PWSID)
  h3_kept_sw <- c(h3_kept_sw, oc)
}

if (length(h3_kept_sw) == 0) {
  cat("  No estimable H3 outcomes in surface-water subsample - skipping table\n")
} else {
  f_fs_d1_sw <- feols(num_coal_mines_upstream_sum ~ post95:sulfur_unified_mean + num_facilities |
                      PWSID + year, data = panel_d1_sw, cluster = ~PWSID)
  t_cl_d1_sw <- coef(f_fs_d1_sw)["post95:sulfur_unified_mean"] /
                se(f_fs_d1_sw)["post95:sulfur_unified_mean"]
  f_cl_d1_sw <- round(t_cl_d1_sw^2, 2)
  cat(sprintf("Clustered first-stage F-stat (D1 surface water): %.2f\n", f_cl_d1_sw))

  inf_d1_pct_sw <- 100 * mean(panel_d1_sw$any_informal)
  frm_d1_pct_sw <- 100 * mean(panel_d1_sw$any_formal)
  ned1_pct_sw   <- 100 * mean(panel_d1_sw$no_enf)

  out_tex_h3_inf_sw <- file.path(ROOT, "output/reg/h3_inf_formal_d12_surfacewater.tex")
  f_vec_d1_sw     <- rep(c("", "", format(round(f_cl_d1_sw, 2), nsmall = 2)), length(h3_kept_sw))
  el_d1_sw        <- list(f_vec_d1_sw)
  names(el_d1_sw) <- f_label_d1

  h3_note_sentences_sw <- c(
    any_informal = paste0("informal enforcement action (", sprintf("%.1f", inf_d1_pct_sw), "% of panel). "),
    any_formal   = paste0("formal enforcement action (", sprintf("%.1f", frm_d1_pct_sw), "% of panel). "),
    no_enf       = paste0("no enforcement (", sprintf("%.1f", ned1_pct_sw), "% of panel). ")
  )
  col_desc_sw <- character(0)
  for (i in seq_along(h3_kept_sw)) {
    oc        <- h3_kept_sw[i]
    start_col <- (i - 1) * 3 + 1
    end_col   <- i * 3
    col_desc_sw <- c(col_desc_sw,
      paste0("Cols ", start_col, "-", end_col, ": ", h3_note_sentences_sw[[oc]]))
  }
  col_desc_sw <- paste(col_desc_sw, collapse = "")

  do.call(etable, c(models_h3_sw, list(
    title          = "Effect of Coal Mining on Enforcement Actions by Type (D1 Downstream Sample, Surface Water Systems)",
    label          = "tab:h3_inf_formal_d12_surfacewater",
    dict           = dict_enf,
    drop           = "num_facilities",
    extralines     = el_d1_sw,
    fitstat        = ~n,
    notes          = paste0("\\textit{Notes:} Sample restricted to community water systems strictly ",
                            "downstream of a coal mine. ",
                            "Sample further restricted to community water systems whose primary water source is surface water. ",
                            col_desc_sw,
                            "The instrument interacts an indicator for the post-1995 period with mean ",
                            "upstream coal sulfur content. SEs clustered at the CWS level. ",
                            "*** p$<$0.01, ** p$<$0.05, * p$<$0.1."),
    style.tex      = style.tex("aer", adjustbox = TRUE),
    tex            = TRUE,
    postprocess.tex = postprocess_table,
    file           = out_tex_h3_inf_sw,
    replace        = TRUE
  )))
  cat(sprintf("\nTable saved to: %s\n", out_tex_h3_inf_sw))
  if (file.exists(out_tex_h3_inf_sw) && file.info(out_tex_h3_inf_sw)$size > 0) {
    cat("Output verified: file exists and is non-zero.\n")
  } else {
    stop("Output file missing or empty — check etable() call.")
  }
}

# H3c RTC table
out_tex_rtc <- file.path(ROOT, "output/reg/h3_rtc_d12.tex")
etable(ols_r, rf_r, iv_r,
       title   = "H3c: Effect of Coal Mining on Days to Return-to-Compliance (D1-D2, Conditional on Enforcement)",
       headers = c("OLS", "Reduced form", "2SLS"),
       notes   = paste0("Sample: PWSID-years with at least one enforcement record. ",
                        "N = ", nrow(panel_enf), " PWSID-years. ",
                        "Outcome: mean days from violation start to return-to-compliance. ",
                        "Instrument: post95 x sulfur_upstream. ",
                        "SEs clustered at PWSID level."),
       fitstat = ~r2 + n + ivf,
       file    = out_tex_rtc,
       replace = TRUE)

wrap_for_beamer(out_tex_rtc)
cat(sprintf("\nTable saved to: %s\n", out_tex_rtc))
if (file.exists(out_tex_rtc) && file.info(out_tex_rtc)$size > 0) {
  cat("Output verified: file exists and is non-zero.\n")
} else {
  stop("Output file missing or empty — check etable() call.")
}

cat("\nDone.\n")
