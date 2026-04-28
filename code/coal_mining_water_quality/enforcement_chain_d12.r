# ============================================================
# Script: enforcement_chain_d12.r
# Purpose: Merge SDWA site visits and enforcement into D1-D2
#          downstream panel; check density; run H2 and H3 regressions
#          H2: instrument -> site visits (n_visits, any_snsv)
#          H3: instrument -> formal enforcement (any_enf, any_formal, mean_rtc_days)
#          Also diagnoses the 2005 enforcement spike.
# Inputs:
#   clean_data/cws_data/prod_vio_sulfur_4step.parquet
#   Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_SITE_VISITS.csv
#   Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.csv
# Outputs:
#   output/reg/h2_visits_d12.tex
#   output/reg/h2_snsv_d12.tex
#   output/reg/h3_enf_d12.tex
# Author: EK  Date: 2026-04-28
# ============================================================

.libPaths("Z:/ek559/RPackages")
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

# ── Step 2: Site visits ───────────────────────────────────────────────────────
cat("Reading SDWA_SITE_VISITS.csv (355 MB)...\n")
sv <- fread(file.path(SDWA, "SDWA_SITE_VISITS.csv"),
            select = c("PWSID", "VISIT_DATE", "VISIT_REASON_CODE", "AGENCY_TYPE_CODE"))
sv <- sv[PWSID %in% ids_d12]

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
                  any_snsv = any(VISIT_REASON_CODE == "SNSV")),
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

rm(sv); gc()

# ── Step 3: Violations/enforcement (3.7 GB — column select) ──────────────────
cat("\nReading SDWA_VIOLATIONS_ENFORCEMENT.csv (3.7 GB, 7 cols selected)...\n")
enf <- fread(file.path(SDWA, "SDWA_VIOLATIONS_ENFORCEMENT.csv"),
             select = c("PWSID", "COMPL_PER_BEGIN_DATE", "NON_COMPL_PER_BEGIN_DATE",
                        "CALCULATED_RTC_DATE", "ENF_ACTION_CATEGORY",
                        "VIOLATION_CATEGORY_CODE", "ENF_ORIGINATOR_CODE"))
enf <- enf[PWSID %in% ids_d12]

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
                    any_formal    = any(ENF_ACTION_CATEGORY == "Formal", na.rm = TRUE),
                    mean_rtc_days = mean(days_to_rtc, na.rm = TRUE)),
                by = .(PWSID, year)]
cat(sprintf("\nPWSID-years with >=1 enf action: %d / %d (%.1f%%)\n",
    nrow(enf_agg), panel_size, 100 * nrow(enf_agg) / panel_size))
cat(sprintf("PWSID-years with formal action:  %d (%.1f%%)\n",
    sum(enf_agg$any_formal), 100 * sum(enf_agg$any_formal) / panel_size))
cat(sprintf("Unique PWSIDs with formal action: %d (%.1f%%)\n",
    length(unique(formal_d12$PWSID)),
    100 * length(unique(formal_d12$PWSID)) / length(ids_d12)))

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

panel$n_visits[is.na(panel$n_visits)]     <- 0L
panel$any_snsv[is.na(panel$any_snsv)]     <- FALSE
panel$any_enf[is.na(panel$any_enf)]       <- FALSE
panel$any_formal[is.na(panel$any_formal)] <- FALSE
# mean_rtc_days: leave NA for PWSID-years with no enforcement (outcome is conditional)

# Convert binary outcomes to integer for LPM
panel$any_snsv   <- as.integer(panel$any_snsv)
panel$any_formal <- as.integer(panel$any_formal)
panel$any_enf    <- as.integer(panel$any_enf)

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

# ── Step 5b: H2b — sanitary survey binary (LPM) ──────────────────────────────
cat("\n=== H2b: Any sanitary survey (SNSV binary, LPM) ~ mining (D1-D2) ===\n")
cat(sprintf("any_snsv = 1 in %d / %d PWSID-years (%.1f%%)\n",
    sum(panel$any_snsv), nrow(panel), 100 * mean(panel$any_snsv)))

fml_ols_b <- any_snsv ~ num_coal_mines_upstream + num_facilities |
             PWSID + year + STATE_CODE
fml_rf_b  <- any_snsv ~ post95:sulfur_upstream  + num_facilities |
             PWSID + year + STATE_CODE
fml_iv_b  <- any_snsv ~ num_facilities | PWSID + year + STATE_CODE |
             num_coal_mines_upstream ~ post95:sulfur_upstream

ols_b <- feols(fml_ols_b, data = panel, cluster = ~PWSID)
rf_b  <- feols(fml_rf_b,  data = panel, cluster = ~PWSID)
iv_b  <- feols(fml_iv_b,  data = panel, cluster = ~PWSID)

cat("\n--- OLS (any_snsv) ---\n");         print(summary(ols_b))
cat("\n--- Reduced form (any_snsv) ---\n"); print(summary(rf_b))
cat("\n--- 2SLS (any_snsv) ---\n");        print(summary(iv_b))
cat(sprintf("\nFirst-stage F-stat (H2b): %.1f\n", fitstat(iv_b, "ivf")[[1]]$stat))

# ── Step 5c: H3 — formal enforcement actions ──────────────────────────────────
cat("\n=== H3: Enforcement actions ~ mining (D1-D2) ===\n")
cat(sprintf("any_enf    = 1 in %d PWSID-years (%.1f%%)\n",
    sum(panel$any_enf),    100 * mean(panel$any_enf)))
cat(sprintf("any_formal = 1 in %d PWSID-years (%.1f%%)\n",
    sum(panel$any_formal), 100 * mean(panel$any_formal)))
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

cat(sprintf("\nTable saved to: %s\n", out_tex))
if (file.exists(out_tex) && file.info(out_tex)$size > 0) {
  cat("Output verified: file exists and is non-zero.\n")
} else {
  stop("Output file missing or empty — check etable() call.")
}

out_tex_b <- file.path(ROOT, "output/reg/h2_snsv_d12.tex")
etable(ols_b, rf_b, iv_b,
       title   = "H2b: Effect of Coal Mining on Sanitary Survey Probability (D1-D2, LPM)",
       headers = c("OLS", "Reduced form", "2SLS"),
       notes   = paste0("D1-D2 downstream sample. Outcome: any sanitary survey (SNSV) in PWSID-year. ",
                        "N = ", nrow(panel), " PWSID-years. ",
                        "Instrument: post95 x sulfur_upstream. ",
                        "SEs clustered at PWSID level."),
       fitstat = ~r2 + n + ivf,
       file    = out_tex_b,
       replace = TRUE)

cat(sprintf("\nTable saved to: %s\n", out_tex_b))
if (file.exists(out_tex_b) && file.info(out_tex_b)$size > 0) {
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

cat(sprintf("\nTable saved to: %s\n", out_tex_h3))
if (file.exists(out_tex_h3) && file.info(out_tex_h3)$size > 0) {
  cat("Output verified: file exists and is non-zero.\n")
} else {
  stop("Output file missing or empty — check etable() call.")
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

cat(sprintf("\nTable saved to: %s\n", out_tex_rtc))
if (file.exists(out_tex_rtc) && file.info(out_tex_rtc)$size > 0) {
  cat("Output verified: file exists and is non-zero.\n")
} else {
  stop("Output file missing or empty — check etable() call.")
}

cat("\nDone.\n")
