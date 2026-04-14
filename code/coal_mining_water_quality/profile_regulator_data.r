# ============================================================
# Script: profile_regulator_data.r
# Purpose: Quick profile of SDWA datasets for regulator behavior variables
# Inputs: prod_vio_sulfur.parquet, SDWA_SITE_VISITS.csv,
#         SDWA_VIOLATIONS_ENFORCEMENT.csv, SDWA_PUB_WATER_SYSTEMS.csv,
#         SDWA_EVENTS_MILESTONES.csv, SDWA_PN_VIOLATION_ASSOC.csv
# Outputs: console output only
# Author: EK  Date: 2026-04-13
# ============================================================

library(arrow)
library(dplyr)
if (!requireNamespace("lubridate", quietly = TRUE)) {
  cat("lubridate not available, using base R date functions\n")
  year_fn <- function(x) as.integer(format(x, "%Y"))
} else {
  library(lubridate)
  year_fn <- lubridate::year
}

cat("=== Loading CWS sample ===\n")
pws <- arrow::read_parquet("Z:/ek559/mining_wq/clean_data/cws_data/prod_vio_sulfur.parquet") |>
  select(PWSID, year) |> distinct()
cat("Sample: ", n_distinct(pws$PWSID), "unique PWSIDs,",
    "years", min(pws$year), "-", max(pws$year), "\n\n")

# ---------------------------------------------------------------
# 1. SITE VISITS
# ---------------------------------------------------------------
cat("=== 1. SITE VISITS ===\n")
sv <- read.csv("Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_SITE_VISITS.csv",
               stringsAsFactors = FALSE)
cat("Total rows in file:", nrow(sv), "\n")
sv$VISIT_DATE <- as.Date(sv$VISIT_DATE, format = "%m/%d/%Y")
sv$year <- year_fn(sv$VISIT_DATE)

sv_sample <- sv |> filter(PWSID %in% pws$PWSID)
cat("Rows matching sample PWSIDs (all years):", nrow(sv_sample), "\n")

sv_sample_period <- sv_sample |> filter(year >= 1985 & year <= 2005)
cat("Rows in sample period 1985-2005:", nrow(sv_sample_period), "\n")
cat("Unique PWSIDs with visits 1985-2005:", n_distinct(sv_sample_period$PWSID), "\n")
cat("Year range of matched visits:", min(sv_sample_period$year, na.rm=TRUE), "-",
    max(sv_sample_period$year, na.rm=TRUE), "\n\n")

cat("VISIT_REASON_CODE distribution (1985-2005):\n")
print(sort(table(sv_sample_period$VISIT_REASON_CODE), decreasing = TRUE))

cat("\nAGENCY_TYPE_CODE distribution (1985-2005):\n")
print(sort(table(sv_sample_period$AGENCY_TYPE_CODE), decreasing = TRUE))

cat("\nCOMPLIANCE_EVAL_CODE distribution (1985-2005):\n")
print(sort(table(sv_sample_period$COMPLIANCE_EVAL_CODE, useNA = "ifany"), decreasing = TRUE))

cat("\nSOURCE_WATER_EVAL_CODE distribution (1985-2005):\n")
print(sort(table(sv_sample_period$SOURCE_WATER_EVAL_CODE, useNA = "ifany"), decreasing = TRUE))

cat("\nMANAGEMENT_OPS_EVAL_CODE distribution (1985-2005):\n")
print(sort(table(sv_sample_period$MANAGEMENT_OPS_EVAL_CODE, useNA = "ifany"), decreasing = TRUE))

cat("\nVisits per PWSID-year (1985-2005) summary:\n")
visits_per_py <- sv_sample_period |>
  group_by(PWSID, year) |>
  summarise(n_visits = n(), .groups = "drop")
print(summary(visits_per_py$n_visits))
cat("\n")

# ---------------------------------------------------------------
# 2. ENFORCEMENT ACTIONS (from violations file)
# ---------------------------------------------------------------
cat("=== 2. ENFORCEMENT ACTIONS ===\n")
ve <- read.csv("Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.csv",
               stringsAsFactors = FALSE)
cat("Total rows in file:", nrow(ve), "\n")

ve$NON_COMPL_PER_BEGIN_DATE <- as.Date(ve$NON_COMPL_PER_BEGIN_DATE, format = "%m/%d/%Y")
ve$viol_year <- year_fn(ve$NON_COMPL_PER_BEGIN_DATE)

ve_sample <- ve |> filter(PWSID %in% pws$PWSID, viol_year >= 1985, viol_year <= 2005)
cat("Violation rows matching sample PWSIDs (1985-2005):", nrow(ve_sample), "\n")

# Rows that have enforcement actions
ve_enf <- ve_sample |> filter(!is.na(ENFORCEMENT_ID) & ENFORCEMENT_ID != "")
cat("Rows with an enforcement action:", nrow(ve_enf), "\n")
cat("Unique violations with enforcement:", n_distinct(ve_enf$VIOLATION_ID), "\n")
cat("Unique PWSIDs with enforcement:", n_distinct(ve_enf$PWSID), "\n\n")

cat("ENF_ACTION_CATEGORY distribution:\n")
print(sort(table(ve_enf$ENF_ACTION_CATEGORY, useNA = "ifany"), decreasing = TRUE))

cat("\nENF_ORIGINATOR_CODE distribution:\n")
print(sort(table(ve_enf$ENF_ORIGINATOR_CODE, useNA = "ifany"), decreasing = TRUE))

cat("\nVIOLATION_STATUS distribution (all sample violations 1985-2005):\n")
print(sort(table(ve_sample$VIOLATION_STATUS, useNA = "ifany"), decreasing = TRUE))

cat("\nVIOL_ORIGINATOR_CODE distribution (all sample violations 1985-2005):\n")
print(sort(table(ve_sample$VIOL_ORIGINATOR_CODE, useNA = "ifany"), decreasing = TRUE))

cat("\nIS_MAJOR_VIOL_IND distribution (all sample violations 1985-2005):\n")
print(sort(table(ve_sample$IS_MAJOR_VIOL_IND, useNA = "ifany"), decreasing = TRUE))

cat("\nVIOLATION_CATEGORY_CODE distribution (all sample violations 1985-2005):\n")
print(sort(table(ve_sample$VIOLATION_CATEGORY_CODE, useNA = "ifany"), decreasing = TRUE))

# Time to return to compliance
ve_sample$CALCULATED_RTC_DATE <- as.Date(ve_sample$CALCULATED_RTC_DATE, format = "%m/%d/%Y")
ve_rtc <- ve_sample |>
  filter(!is.na(CALCULATED_RTC_DATE) & !is.na(NON_COMPL_PER_BEGIN_DATE)) |>
  mutate(days_to_rtc = as.numeric(CALCULATED_RTC_DATE - NON_COMPL_PER_BEGIN_DATE))
cat("\nDays to return to compliance (where non-missing):\n")
cat("N obs:", nrow(ve_rtc), "\n")
print(summary(ve_rtc$days_to_rtc))

# ---------------------------------------------------------------
# 3. PUB WATER SYSTEMS — reduced monitoring & outstanding performer
# ---------------------------------------------------------------
cat("\n=== 3. PUB WATER SYSTEMS — regulatory discretion fields ===\n")
pws_chars <- read.csv("Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_PUB_WATER_SYSTEMS.csv",
                       stringsAsFactors = FALSE)
pws_match <- pws_chars |> filter(PWSID %in% pws$PWSID)
cat("PWSIDs matched:", n_distinct(pws_match$PWSID), "\n")

cat("\nREDUCED_RTCR_MONITORING distribution:\n")
print(sort(table(pws_match$REDUCED_RTCR_MONITORING, useNA = "ifany"), decreasing = TRUE))

cat("\nOUTSTANDING_PERFORMER distribution:\n")
print(sort(table(pws_match$OUTSTANDING_PERFORMER, useNA = "ifany"), decreasing = TRUE))

cat("\nSOURCE_WATER_PROTECTION_CODE distribution:\n")
print(sort(table(pws_match$SOURCE_WATER_PROTECTION_CODE, useNA = "ifany"), decreasing = TRUE))

cat("\nREDUCED_MONITORING_BEGIN_DATE non-missing:",
    sum(!is.na(pws_match$REDUCED_MONITORING_BEGIN_DATE) &
        pws_match$REDUCED_MONITORING_BEGIN_DATE != ""), "\n")
cat("OUTSTANDING_PERFORM_BEGIN_DATE non-missing:",
    sum(!is.na(pws_match$OUTSTANDING_PERFORM_BEGIN_DATE) &
        pws_match$OUTSTANDING_PERFORM_BEGIN_DATE != ""), "\n")

# ---------------------------------------------------------------
# 4. EVENTS AND MILESTONES
# ---------------------------------------------------------------
cat("\n=== 4. EVENTS AND MILESTONES ===\n")
em <- read.csv("Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_EVENTS_MILESTONES.csv",
               stringsAsFactors = FALSE)
cat("Total rows in file:", nrow(em), "\n")
em$EVENT_ACTUAL_DATE <- as.Date(em$EVENT_ACTUAL_DATE, format = "%m/%d/%Y")
em$year <- year_fn(em$EVENT_ACTUAL_DATE)

em_sample <- em |> filter(PWSID %in% pws$PWSID)
cat("Rows matching sample PWSIDs (all years):", nrow(em_sample), "\n")

em_period <- em_sample |> filter(year >= 1985 & year <= 2005)
cat("Rows in sample period 1985-2005:", nrow(em_period), "\n")
cat("Unique PWSIDs with events 1985-2005:", n_distinct(em_period$PWSID), "\n\n")

cat("EVENT_MILESTONE_CODE distribution (1985-2005):\n")
print(sort(table(em_period$EVENT_MILESTONE_CODE, useNA = "ifany"), decreasing = TRUE))

cat("\nEVENT_REASON_CODE distribution (1985-2005):\n")
print(sort(table(em_period$EVENT_REASON_CODE, useNA = "ifany"), decreasing = TRUE))

# ---------------------------------------------------------------
# 5. PUBLIC NOTICE VIOLATIONS
# ---------------------------------------------------------------
cat("\n=== 5. PUBLIC NOTICE VIOLATIONS ===\n")
pn <- read.csv("Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_PN_VIOLATION_ASSOC.csv",
               stringsAsFactors = FALSE)
cat("Total rows in file:", nrow(pn), "\n")
pn$NON_COMPL_PER_BEGIN_DATE <- as.Date(pn$NON_COMPL_PER_BEGIN_DATE, format = "%m/%d/%Y")
pn$year <- year_fn(pn$NON_COMPL_PER_BEGIN_DATE)

pn_sample <- pn |> filter(PWSID %in% pws$PWSID, year >= 1985, year <= 2005)
cat("Rows matching sample PWSIDs (1985-2005):", nrow(pn_sample), "\n")
cat("Unique PWSIDs with public notices:", n_distinct(pn_sample$PWSID), "\n")
cat("Unique violations with public notices:", n_distinct(pn_sample$PN_VIOLATION_ID), "\n\n")

cat("=== PROFILE COMPLETE ===\n")
