# ============================================================
# Script: sdwa_regulator_data_inventory.r
# Purpose: Profile SDWA datasets for regulator behavior analysis, restricted to
#          strictly downstream CWSs (minehuc_downstream_of_mine==1, minehuc_mine==0).
#          Produces inventory and profile tables for site visits and enforcement.
# Inputs:  clean_data/cws_data/prod_vio_sulfur.parquet (downstream PWSID filter)
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_SITE_VISITS.csv
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.csv
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_PUB_WATER_SYSTEMS.csv
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_EVENTS_MILESTONES.csv
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_PN_VIOLATION_ASSOC.csv
# Outputs: output/sum/sdwa_regulator_data_inventory.tex
# Author: EK  Date: 2026-04-15
# NOTE:    PWSID must be loaded as character in all datasets to preserve leading
#          zeros and alpha-state prefixes (e.g. "AL0000097").
# ============================================================

.libPaths("Z:/ek559/RPackages")
library(arrow)
library(data.table)

SDWA_DIR <- "Z:/ek559/sdwa_violations/SDWA_latest_downloads"

# ── 0. Strictly downstream PWSID list ────────────────────────────────────────
pws_sample <- as.data.frame(
  arrow::read_parquet("Z:/ek559/mining_wq/clean_data/cws_data/prod_vio_sulfur.parquet",
                      col_select = c("PWSID", "minehuc_downstream_of_mine", "minehuc_mine")))
pws_ids <- unique(pws_sample$PWSID[
  pws_sample$minehuc_downstream_of_mine == 1 & pws_sample$minehuc_mine == 0])
n_pws_total <- length(pws_ids)
cat("Strictly downstream PWSIDs:", n_pws_total, "\n")

fn <- function(x) format(as.integer(x), big.mark = ",")
fp <- function(x) sprintf("%.1f", x)

# ── 1. SITE VISITS ────────────────────────────────────────────────────────────
cat("\n=== Loading SDWA_SITE_VISITS.csv ===\n")
sv_full <- fread(file.path(SDWA_DIR, "SDWA_SITE_VISITS.csv"),
                 select = c("PWSID","VISIT_ID","VISIT_DATE","AGENCY_TYPE_CODE",
                            "VISIT_REASON_CODE","COMPLIANCE_EVAL_CODE"),
                 colClasses = list(character = "PWSID"),
                 na.strings = c("","NA"), showProgress = FALSE)
cat("Total rows in file:", nrow(sv_full), "\n")

# Date in MM/DD/YYYY format — year at positions 7-10
sv_full[, yr := as.integer(substr(VISIT_DATE, 7, 10))]
sv <- sv_full[PWSID %in% pws_ids & yr >= 1985 & yr <= 2005]
cat("Matched sample, 1985-2005:", nrow(sv), "rows,",
    uniqueN(sv$PWSID), "unique PWSIDs\n")

# Summaries
reason_tab <- sv[, .N, by = VISIT_REASON_CODE][order(-N)]
reason_tab[, share := 100 * N / nrow(sv)]

agency_tab <- sv[, .N, by = AGENCY_TYPE_CODE][order(-N)]
agency_tab[, share := 100 * N / nrow(sv)]

eval_tab <- sv[, .N, by = COMPLIANCE_EVAL_CODE][order(-N)]
eval_tab[, share := 100 * N / nrow(sv)]

sv_py    <- sv[, .N, by = .(PWSID, yr)]
sv_min   <- min(sv_py$N)
sv_q25   <- quantile(sv_py$N, 0.25)
sv_med   <- median(sv_py$N)
sv_mean  <- mean(sv_py$N)
sv_q75   <- quantile(sv_py$N, 0.75)
sv_max   <- max(sv_py$N)
n_sv_pws <- uniqueN(sv$PWSID)
cat("Visits/PWSID-year — median:", sv_med, " mean:", round(sv_mean, 1), "\n")

# ── 2. VIOLATIONS / ENFORCEMENT ───────────────────────────────────────────────
cat("\n=== Loading SDWA_VIOLATIONS_ENFORCEMENT.csv ===\n")
cols_ve <- c("PWSID","VIOLATION_ID","NON_COMPL_PER_BEGIN_DATE","CALCULATED_RTC_DATE",
             "VIOLATION_CATEGORY_CODE","IS_MAJOR_VIOL_IND","VIOLATION_STATUS",
             "RULE_CODE","ENFORCEMENT_ID","ENF_ACTION_CATEGORY","ENF_ORIGINATOR_CODE",
             "VIOL_ORIGINATOR_CODE")
ve_full <- fread(file.path(SDWA_DIR, "SDWA_VIOLATIONS_ENFORCEMENT.csv"),
                 select = cols_ve,
                 colClasses = list(character = "PWSID"),
                 na.strings = c("","NA","--->'"), showProgress = TRUE)
cat("Total rows:", nrow(ve_full), "\n")

ve_full[, yr := as.integer(substr(NON_COMPL_PER_BEGIN_DATE, 7, 10))]
ve <- ve_full[PWSID %in% pws_ids & yr >= 1985 & yr <= 2005]
cat("Matched sample, 1985-2005:", nrow(ve), "rows,", uniqueN(ve$PWSID), "PWSIDs\n")

n_with_enf     <- sum(!is.na(ve$ENFORCEMENT_ID))
n_unique_viols <- uniqueN(ve$VIOLATION_ID)
cat("Rows with enforcement action:", n_with_enf, "\n")
cat("Unique violations:", n_unique_viols, "\n")

vc_tab <- ve[, .N, by = VIOLATION_CATEGORY_CODE][order(-N)]
vc_tab[, share := 100 * N / nrow(ve)]

ec_tab <- ve[!is.na(ENF_ACTION_CATEGORY), .N, by = ENF_ACTION_CATEGORY][order(-N)]
ec_tab[, share := 100 * N / n_with_enf]

eo_tab <- ve[!is.na(ENF_ORIGINATOR_CODE), .N, by = ENF_ORIGINATOR_CODE][order(-N)]
eo_tab[, share := 100 * N / n_with_enf]

vs_tab <- ve[, .N, by = VIOLATION_STATUS][order(-N)]
vs_tab[, share := 100 * N / nrow(ve)]

ve[, begin_dt := as.Date(NON_COMPL_PER_BEGIN_DATE, format = "%m/%d/%Y")]
ve[, rtc_dt   := as.Date(CALCULATED_RTC_DATE,       format = "%m/%d/%Y")]
ve[, days_rtc := as.numeric(rtc_dt - begin_dt)]
n_days    <- sum(!is.na(ve$days_rtc))
days_min  <- min(ve$days_rtc,  na.rm = TRUE)
days_q25  <- quantile(ve$days_rtc, 0.25, na.rm = TRUE)
days_med  <- median(ve$days_rtc, na.rm = TRUE)
days_mean <- mean(ve$days_rtc,   na.rm = TRUE)
days_q75  <- quantile(ve$days_rtc, 0.75, na.rm = TRUE)
days_max  <- max(ve$days_rtc,  na.rm = TRUE)
cat("Days to RTC — median:", days_med, " mean:", round(days_mean, 0), "\n")

# ── 3. PUB WATER SYSTEMS (cross-sectional) ────────────────────────────────────
cat("\n=== Loading SDWA_PUB_WATER_SYSTEMS.csv ===\n")
pws_file <- fread(file.path(SDWA_DIR, "SDWA_PUB_WATER_SYSTEMS.csv"),
                  select = c("PWSID","REDUCED_RTCR_MONITORING",
                             "OUTSTANDING_PERFORMER","SOURCE_WATER_PROTECTION_CODE"),
                  colClasses = list(character = "PWSID"),
                  na.strings = c("","NA"), showProgress = FALSE)
pws_file <- pws_file[PWSID %in% pws_ids]
n_pws_file <- uniqueN(pws_file$PWSID)
cat("PWSIDs in PUB_WATER_SYSTEMS file:", n_pws_file, "\n")

# ── 4. EVENTS / MILESTONES ────────────────────────────────────────────────────
cat("\n=== Loading SDWA_EVENTS_MILESTONES.csv ===\n")
em_full <- fread(file.path(SDWA_DIR, "SDWA_EVENTS_MILESTONES.csv"),
                 colClasses = list(character = "PWSID"),
                 na.strings = c("","NA"), showProgress = FALSE)
cat("Total rows in file:", nrow(em_full), "\n")
# EVENT_ACTUAL_DATE is MM/DD/YYYY
em_full[, yr := as.integer(substr(EVENT_ACTUAL_DATE, 7, 10))]
em <- em_full[PWSID %in% pws_ids & yr >= 1985 & yr <= 2005]
cat("Events/milestones matched:", nrow(em), "rows,", uniqueN(em$PWSID), "PWSIDs\n")

# ── 5. PUBLIC NOTICES ─────────────────────────────────────────────────────────
cat("\n=== Loading SDWA_PN_VIOLATION_ASSOC.csv ===\n")
pn_full <- fread(file.path(SDWA_DIR, "SDWA_PN_VIOLATION_ASSOC.csv"),
                 colClasses = list(character = "PWSID"),
                 na.strings = c("","NA"), showProgress = FALSE)
cat("Total rows in file:", nrow(pn_full), "\n")
pn_full[, yr := as.integer(substr(NON_COMPL_PER_BEGIN_DATE, 7, 10))]
pn <- pn_full[PWSID %in% pws_ids & yr >= 1985 & yr <= 2005]
cat("PN rows matched:", nrow(pn), "PWSIDs:", uniqueN(pn$PWSID), "\n")

# ── 6. LaTeX helpers ──────────────────────────────────────────────────────────
make_rows <- function(labels_vec, count_tab, count_col, total) {
  rows <- character(0)
  for (cd in names(labels_vec)) {
    r <- count_tab[get(count_col) == cd]
    if (nrow(r) == 0) next
    rows <- c(rows,
      paste0(labels_vec[[cd]], " & ", fn(r$N), " & ", fp(r$share), " \\\\"))
  }
  rows
}

# ── 7. LaTeX Table 1: Dataset inventory ───────────────────────────────────────
t1_lines <- c(
  "\\begin{table}[h!]",
  "\\centering",
  "\\caption{SDWA Datasets Available for Regulator Behavior Analysis (Downstream CWSs)}",
  "\\label{tab:sdwa_inventory}",
  "\\small",
  "\\begin{tabular}{llrrll}",
  "\\hline\\hline",
  "Dataset & Key Variables & \\multicolumn{2}{c}{Rows (1985--2005)} & Usability \\\\",
  "\\cmidrule(lr){3-4}",
  " & & Total file & Matched sample & \\\\",
  "\\hline",
  paste0("\\texttt{SDWA\\_SITE\\_VISITS} & Visit frequency, reason code, & ",
         fn(nrow(sv_full)), " & ", fn(nrow(sv)),
         " & \\textbf{Strong} \\\\"),
  paste0(" & agency type, eval codes & & (", fn(n_sv_pws), " PWSIDs) & \\\\[4pt]"),
  paste0("\\texttt{SDWA\\_VIOLATIONS\\_} & Enforcement category, & ",
         fn(nrow(ve_full)), " & ", fn(nrow(ve)),
         " & \\textbf{Strong} \\\\"),
  paste0("\\texttt{ENFORCEMENT} & originator, days to RTC, & & (",
         fn(uniqueN(ve$PWSID)), " PWSIDs) & \\\\"),
  " & violation status & & & \\\\[4pt]",
  paste0("\\texttt{SDWA\\_EVENTS\\_} & Milestone codes (DEEM, DONE, & ",
         fn(nrow(em_full)), " & ", fn(nrow(em)),
         " & Narrow \\\\"),
  paste0("\\texttt{MILESTONES} & SDFF, FICF), reason codes & & (",
         fn(uniqueN(em$PWSID)), " PWSIDs) & (LCR only) \\\\[4pt]"),
  paste0("\\texttt{SDWA\\_PN\\_VIOLATION\\_} & Public notice tier, & ",
         fn(nrow(pn_full)), " & ", fn(nrow(pn)),
         " & Too sparse \\\\"),
  paste0("\\texttt{ASSOC} & related violation & & (",
         fn(uniqueN(pn$PWSID)), " PWSIDs) & \\\\[4pt]"),
  paste0("\\texttt{SDWA\\_PUB\\_WATER\\_} & Reduced monitoring status, & --- & ",
         fn(n_pws_file), " PWSIDs & Too sparse \\\\"),
  "\\texttt{SYSTEMS} & outstanding performer & & (cross-sectional) & \\\\",
  "\\hline\\hline",
  paste0("\\multicolumn{5}{l}{\\footnotesize Note: ``Matched sample'' = PWSIDs in the ",
         "strictly downstream coal mining CWS sample.} \\\\"),
  "\\multicolumn{5}{l}{\\footnotesize LCR = Lead and Copper Rule. RTC = return to compliance.} \\\\",
  "\\end{tabular}",
  "\\end{table}"
)

# ── 8. LaTeX Table 2: Site visits profile ─────────────────────────────────────
reason_labels <- c(
  SNSV="Sanitary survey (SNSV)", TECH="Technical assistance (TECH)",
  SITE="Site visit (SITE)", RSCH="Research (RSCH)", SMPL="Sampling (SMPL)",
  INVG="Investigation (INVG)", OTHR="Other (OTHR)", INFI="Infrastructure inspection (INFI)"
)
top_reasons <- names(reason_labels)
other_reason_n <- sum(reason_tab[!VISIT_REASON_CODE %in% top_reasons & !is.na(VISIT_REASON_CODE)]$N, na.rm=TRUE)

agency_labels <- c(
  ST="State (ST)", SA="State administrative district (SA)",
  SR="State administrative region (SR)", DS="District (DS)"
)
top_agencies  <- names(agency_labels)
other_agency_n <- sum(agency_tab[!AGENCY_TYPE_CODE %in% top_agencies & !is.na(AGENCY_TYPE_CODE)]$N, na.rm=TRUE)

eval_labels <- c(
  N="No deficiencies (N)", R="Recommendations made (R)",
  M="Minor deficiencies (M)", D="Sanitary defect (D)"
)

# "Not evaluated" = X, Z, or NA
n_noteval <- nrow(sv[is.na(COMPLIANCE_EVAL_CODE) | COMPLIANCE_EVAL_CODE %in% c("X","Z","") ])

reason_rows  <- make_rows(reason_labels,  reason_tab,  "VISIT_REASON_CODE", nrow(sv))
agency_rows  <- make_rows(agency_labels,  agency_tab,  "AGENCY_TYPE_CODE",  nrow(sv))
eval_rows    <- make_rows(eval_labels,    eval_tab,    "COMPLIANCE_EVAL_CODE", nrow(sv))

t2_lines <- c(
  "\\begin{table}[h!]",
  "\\centering",
  "\\caption{Site Visits in Analysis Sample, 1985--2005 (Downstream CWSs)}",
  "\\label{tab:site_visits_profile}",
  "\\small",
  "\\begin{tabular}{lrr}",
  "\\hline\\hline",
  " & \\multicolumn{1}{c}{Count} & \\multicolumn{1}{c}{Share (\\%)} \\\\",
  "\\hline",
  "\\multicolumn{3}{l}{\\textit{Panel A: Visit reason}} \\\\",
  reason_rows,
  if (other_reason_n > 0)
    paste0("Other (ENGR, PRMT, OM, EMRG, etc.) & ", fn(other_reason_n), " & ",
           fp(100*other_reason_n/nrow(sv)), " \\\\"),
  "\\hline",
  paste0("\\textit{Total} & ", fn(nrow(sv)), " & 100.0 \\\\[6pt]"),
  "\\multicolumn{3}{l}{\\textit{Panel B: Agency conducting visit}} \\\\",
  agency_rows,
  if (other_agency_n > 0)
    paste0("Other & ", fn(other_agency_n), " & ",
           fp(100*other_agency_n/nrow(sv)), " \\\\"),
  "\\hline",
  paste0("\\textit{Total} & ", fn(nrow(sv)), " & 100.0 \\\\[6pt]"),
  "\\multicolumn{3}{l}{\\textit{Panel C: Compliance evaluation outcome}} \\\\",
  paste0("Not evaluated / not applicable (X, Z) & ", fn(n_noteval), " & ",
         fp(100*n_noteval/nrow(sv)), " \\\\"),
  eval_rows,
  "\\hline",
  paste0("\\textit{Total} & ", fn(nrow(sv)), " & 100.0 \\\\[6pt]"),
  "\\multicolumn{3}{l}{\\textit{Panel D: Visits per PWSID-year}} \\\\",
  paste0("Minimum & ", sv_min, " & \\\\"),
  paste0("25th percentile & ", sv_q25, " & \\\\"),
  paste0("Median & ", sv_med, " & \\\\"),
  paste0("Mean & ", round(sv_mean, 1), " & \\\\"),
  paste0("75th percentile & ", sv_q75, " & \\\\"),
  paste0("Maximum & ", sv_max, " & \\\\"),
  "\\hline\\hline",
  paste0("\\multicolumn{3}{l}{\\footnotesize Note: Sample is ", fn(n_sv_pws),
         " unique strictly downstream PWSIDs matched to coal mining analysis sample.} \\\\"),
  "\\end{tabular}",
  "\\end{table}"
)

# ── 9. LaTeX Table 3: Enforcement profile ─────────────────────────────────────
labels_vc <- c(MR="Monitoring \\& Reporting (MR)",
               MCL="Maximum Contaminant Level (MCL)",
               TT="Treatment Technique (TT)",
               MRDL="Max. Residual Disinfectant Level (MRDL)")
labels_ec <- c(Informal="Informal", Resolving="Resolving", Formal="Formal")
labels_vs <- c(Resolved="Resolved", Archived="Archived",
               Addressed="Addressed (formal enforcement, not resolved)",
               Unaddressed="Unaddressed")

other_vc_n <- sum(vc_tab[!VIOLATION_CATEGORY_CODE %in% names(labels_vc)]$N, na.rm=TRUE)
vc_rows  <- make_rows(labels_vc, vc_tab, "VIOLATION_CATEGORY_CODE", nrow(ve))
ec_rows  <- make_rows(labels_ec, ec_tab, "ENF_ACTION_CATEGORY",     n_with_enf)
vs_rows  <- make_rows(labels_vs, vs_tab, "VIOLATION_STATUS",         nrow(ve))

# Enforcement originator
eo_s <- eo_tab[ENF_ORIGINATOR_CODE == "S"]$N
eo_f <- eo_tab[ENF_ORIGINATOR_CODE == "F"]$N
if (length(eo_s) == 0) eo_s <- 0L
if (length(eo_f) == 0) eo_f <- 0L

t3_lines <- c(
  "\\begin{table}[h!]",
  "\\centering",
  "\\caption{Enforcement Actions in Analysis Sample, 1985--2005 (Downstream CWSs)}",
  "\\label{tab:enforcement_profile}",
  "\\small",
  "\\begin{tabular}{lrr}",
  "\\hline\\hline",
  " & \\multicolumn{1}{c}{Count} & \\multicolumn{1}{c}{Share (\\%)} \\\\",
  "\\hline",
  "\\multicolumn{3}{l}{\\textit{Panel A: Violation category}} \\\\",
  vc_rows,
  if (other_vc_n > 0)
    paste0("Other & ", fn(other_vc_n), " & ",
           fp(100*other_vc_n/nrow(ve)), " \\\\"),
  "\\hline",
  paste0("\\textit{Total violations} & ", fn(nrow(ve)), " & 100.0 \\\\[6pt]"),
  "\\multicolumn{3}{l}{\\textit{Panel B: Enforcement action category}} \\\\",
  ec_rows,
  "\\hline",
  paste0("\\textit{Total enforcement actions} & ", fn(n_with_enf), " & 100.0 \\\\[6pt]"),
  "\\multicolumn{3}{l}{\\textit{Panel C: Enforcement originator}} \\\\",
  paste0("State & ", fn(eo_s), " & ", fp(100*eo_s/n_with_enf), " \\\\"),
  paste0("Federal & ", fn(eo_f), " & ", fp(100*eo_f/n_with_enf), " \\\\"),
  "\\hline",
  paste0("\\textit{Total enforcement actions} & ", fn(n_with_enf), " & 100.0 \\\\[6pt]"),
  "\\multicolumn{3}{l}{\\textit{Panel D: Violation status}} \\\\",
  vs_rows,
  "\\hline",
  paste0("\\textit{Total violations} & ", fn(nrow(ve)), " & 100.0 \\\\[6pt]"),
  paste0("\\multicolumn{3}{l}{\\textit{Panel E: Days to return to compliance (N\\,=\\,",
         fn(n_days), ")}} \\\\"),
  paste0("Minimum & $", fn(days_min), "$ & \\\\"),
  paste0("25th percentile & ", fn(days_q25), " & \\\\"),
  paste0("Median & ", fn(days_med), " & \\\\"),
  paste0("Mean & ", fn(round(days_mean)), " & \\\\"),
  paste0("75th percentile & ", fn(days_q75), " & \\\\"),
  paste0("Maximum & ", fn(days_max), " & \\\\"),
  "\\hline\\hline",
  paste0("\\multicolumn{3}{l}{\\footnotesize Note: Sample is ", fn(uniqueN(ve$PWSID)),
         " unique strictly downstream PWSIDs with enforcement actions.} \\\\"),
  "\\multicolumn{3}{l}{\\footnotesize Negative values of days to return to compliance reflect data entry inconsistencies in SDWIS.} \\\\",
  "\\end{tabular}",
  "\\end{table}"
)

# ── 10. Write output ──────────────────────────────────────────────────────────
header <- c(
  "% ============================================================",
  "% Tables: SDWA datasets for regulator behavior analysis (Downstream CWSs)",
  paste0("% Generated: ", Sys.Date()),
  paste0("% Sample: ", n_pws_total, " strictly downstream CWSs",
         " (minehuc_downstream_of_mine=1, minehuc_mine=0)"),
  "% Sections:",
  "%   Tables 1--3: inventory, site visits, enforcement",
  "% ============================================================"
)

out_path <- "Z:/ek559/mining_wq/output/sum/sdwa_regulator_data_inventory.tex"
writeLines(
  c(header, "",
    "% ------------------------------------------------------------------",
    "% Table 1: Dataset inventory",
    "% ------------------------------------------------------------------",
    t1_lines, "",
    "% ------------------------------------------------------------------",
    "% Table 2: Site visits profile",
    "% ------------------------------------------------------------------",
    t2_lines, "",
    "% ------------------------------------------------------------------",
    "% Table 3: Enforcement actions profile",
    "% ------------------------------------------------------------------",
    t3_lines),
  out_path
)
cat("\nOutput written to:", out_path, "\n")
cat("=== DONE ===\n")
