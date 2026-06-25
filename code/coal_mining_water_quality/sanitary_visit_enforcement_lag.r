# ============================================================
# Script: sanitary_visit_enforcement_lag.r
# Purpose: Test whether sanitary visits inform enforcement (Q1: visit -> enforcement
#          in next 6/12 months) and whether MR violations trigger sanitary visits
#          (Q2: any MR violation -> visit in next 6/12 months), at the downstream
#          CWS-month level. Empirical companion to the K&S inspection-as-
#          information-channel question.
# Inputs:  clean_data/cws_data/prod_vio_sulfur.parquet
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_SITE_VISITS.csv
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.parquet
# Outputs: output/sum/sanitary_visit_to_enforcement.tex
#          output/reg/sanitary_visit_to_enforcement_timing.tex
#          output/reg/mr_to_sanitary_visit.tex
#          output/sum/visit_type_summary.tex
# Author: EK  Date: 2026-06-24
# ============================================================

.libPaths("Z:/ek559/RPackages")
library(arrow)
library(data.table)
library(fixest)

ROOT     <- "Z:/ek559/mining_wq"
SDWA_DIR <- "Z:/ek559/sdwa_violations/SDWA_latest_downloads"

# ── 0. Sample: strictly-downstream CWSs ───────────────────────────────────────
panel <- as.data.table(
  arrow::read_parquet(file.path(ROOT, "clean_data/cws_data/prod_vio_sulfur.parquet"),
    col_select = c("PWSID", "STATE_CODE", "minehuc_downstream_of_mine", "minehuc_mine")))
downstream_mask <- panel$minehuc_downstream_of_mine == 1 & panel$minehuc_mine == 0
sample_pwsids   <- unique(panel$PWSID[downstream_mask])
cat("Downstream CWSs in sample:", length(sample_pwsids), "\n")

month_idx_of <- function(d) {
  yr <- as.integer(format(d, "%Y"))
  mo <- as.integer(format(d, "%m"))
  (yr - 1985L) * 12L + (mo - 1L) + 1L
}

# ── 1. Site visits ─────────────────────────────────────────────────────────────
sv <- fread(file.path(SDWA_DIR, "SDWA_SITE_VISITS.csv"),
  select = c("PWSID", "VISIT_DATE", "VISIT_REASON_CODE"),
  colClasses = list(character = "PWSID"), na.strings = c("", "NA"), showProgress = FALSE)
sv <- sv[PWSID %in% sample_pwsids]
sv[, visit_dt := as.Date(VISIT_DATE, "%m/%d/%Y")]
sv <- sv[!is.na(visit_dt)]
sv[, yr := as.integer(format(visit_dt, "%Y"))]
sv <- sv[yr >= 1985 & yr <= 2005]
sv[, month_idx := month_idx_of(visit_dt)]

san_reasons <- c("SNSV", "SNSP", "SSVF")
enf_reasons <- c("FENF", "IENF")
sv[, is_san := VISIT_REASON_CODE %in% san_reasons]
sv[, is_any := !(VISIT_REASON_CODE %in% enf_reasons)]

visit_pm <- sv[, .(visit_san = as.integer(any(is_san)),
                    visit_any = as.integer(any(is_any))),
               by = .(PWSID, month_idx)]
cat("Site-visit PWSID-months:", nrow(visit_pm),
    "| visit_san=1:", sum(visit_pm$visit_san),
    "| visit_any=1:", sum(visit_pm$visit_any), "\n")

# ── 2. Violations/enforcement parquet ─────────────────────────────────────────
ve <- as.data.table(arrow::read_parquet(
  file.path(SDWA_DIR, "SDWA_VIOLATIONS_ENFORCEMENT.parquet"),
  col_select = c("PWSID", "VIOLATION_ID", "ENFORCEMENT_ID",
                 "NON_COMPL_PER_BEGIN_DATE", "VIOLATION_CATEGORY_CODE", "RULE_CODE",
                 "ENFORCEMENT_DATE", "ENF_ACTION_CATEGORY")))
ve <- ve[PWSID %in% sample_pwsids]

# Enforcement events (Q1 outcome) — dedupe on ENFORCEMENT_ID, date = ENFORCEMENT_DATE
enf <- ve[!is.na(ENFORCEMENT_ID) & !is.na(ENFORCEMENT_DATE)]
enf[, enf_dt := as.Date(ENFORCEMENT_DATE, "%m/%d/%Y")]
enf <- enf[!is.na(enf_dt)]
enf[, enf_yr := as.integer(format(enf_dt, "%Y"))]
enf <- enf[enf_yr >= 1985 & enf_yr <= 2005]
enf <- unique(enf[, .(PWSID, ENFORCEMENT_ID, enf_dt, ENF_ACTION_CATEGORY)])
enf[, month_idx := month_idx_of(enf_dt)]

enf_pm <- enf[, .(
  enf_informal = as.integer(any(ENF_ACTION_CATEGORY == "Informal",  na.rm = TRUE)),
  enf_resolving= as.integer(any(ENF_ACTION_CATEGORY == "Resolving", na.rm = TRUE)),
  enf_formal   = as.integer(any(ENF_ACTION_CATEGORY == "Formal",    na.rm = TRUE))
), by = .(PWSID, month_idx)]
enf_pm[, enf_any := as.integer(enf_informal == 1 | enf_resolving == 1 | enf_formal == 1)]
cat("Enforcement PWSID-months:", nrow(enf_pm),
    "| informal:", sum(enf_pm$enf_informal),
    "| resolving:", sum(enf_pm$enf_resolving),
    "| formal:", sum(enf_pm$enf_formal),
    "| any:", sum(enf_pm$enf_any), "\n")

# MR begin event (Q2 regressor) — any MR violation, dedupe on VIOLATION_ID,
# date = NON_COMPL_PER_BEGIN_DATE
mr <- ve[VIOLATION_CATEGORY_CODE == "MR"]
mr[, begin_dt := as.Date(NON_COMPL_PER_BEGIN_DATE, "%m/%d/%Y")]
mr <- mr[!is.na(begin_dt)]
mr[, mr_yr := as.integer(format(begin_dt, "%Y"))]
mr <- mr[mr_yr >= 1985 & mr_yr <= 2005]
mr <- unique(mr[, .(PWSID, VIOLATION_ID, begin_dt)])
mr[, month_idx := month_idx_of(begin_dt)]

mr_pm <- mr[, .(mr_any = 1L), by = .(PWSID, month_idx)]
cat("MR-begin PWSID-months:", nrow(mr_pm),
    "(", uniqueN(mr$PWSID), "CWSs )\n")

# ── 3. Monthly skeleton: full cross of sample PWSID x months 1985-01..2005-12 ─
n_months <- month_idx_of(as.Date("2005-12-01"))
skel <- CJ(PWSID = sample_pwsids, month_idx = seq_len(n_months))

skel <- merge(skel, visit_pm, by = c("PWSID", "month_idx"), all.x = TRUE)
skel <- merge(skel, enf_pm,   by = c("PWSID", "month_idx"), all.x = TRUE)
skel <- merge(skel, mr_pm, by = c("PWSID", "month_idx"), all.x = TRUE)

fill_cols <- c("visit_san", "visit_any", "enf_informal", "enf_resolving",
               "enf_formal", "enf_any", "mr_any")
for (cl in fill_cols) skel[is.na(get(cl)), (cl) := 0L]

setorder(skel, PWSID, month_idx)
cat("\nFull monthly panel: ", nrow(skel), " PWSID-months (",
    length(sample_pwsids), " CWSs x ", n_months, " months)\n", sep = "")

# ── 4. Forward-window outcomes via frollsum on the lead of each event vector ──
build_forward <- function(dt, col, h) {
  out_name <- paste0(col, "_next", h)
  dt[, (out_name) := {
    lead_event <- shift(get(col), n = -1, fill = 0L)
    roll <- frollsum(lead_event, n = h, align = "left", fill = NA)
    as.integer(roll > 0)
  }, by = PWSID]
  invisible(dt)
}

event_cols <- c("enf_informal", "enf_resolving", "enf_formal", "enf_any",
                "visit_san", "visit_any", "mr_any")
for (cl in event_cols) {
  build_forward(skel, cl, 6)
  build_forward(skel, cl, 12)
}

# ── 5. Right-censoring trim (per horizon, applied at regression time) ────────
max_origin_6  <- month_idx_of(as.Date("2005-06-01"))
max_origin_12 <- month_idx_of(as.Date("2004-12-01"))

reg6  <- skel[month_idx <= max_origin_6]
reg12 <- skel[month_idx <= max_origin_12]
cat("Q1/Q2 regression N (h=6): ", nrow(reg6),  "\n", sep = "")
cat("Q1/Q2 regression N (h=12):", nrow(reg12), "\n", sep = "")

base_rate <- function(dt, col) round(100 * mean(dt[[col]], na.rm = TRUE), 2)

# ── 6. Backward window for visit_san (used in Q1 summary table, col 2) ───────
build_backward <- function(dt, col, h) {
  out_name <- paste0(col, "_prev", h)
  dt[, (out_name) := {
    lag_event <- shift(get(col), n = 1, fill = 0L)
    roll <- frollsum(lag_event, n = h, align = "right", fill = NA)
    as.integer(roll > 0)
  }, by = PWSID]
  invisible(dt)
}
build_backward(reg12, "visit_san", 12)

# ── 7. Q2 regressions: mr_any_t -> visit_{t+1..t+h} ───────────────────────────
q2_models <- list()
for (vdef in c("visit_san", "visit_any")) {
  for (h in c(6, 12)) {
    dt   <- if (h == 6) reg6 else reg12
    yvar <- paste0(vdef, "_next", h)
    fml  <- as.formula(paste0(yvar, " ~ mr_any | PWSID + month_idx"))
    key  <- paste0(vdef, "__h", h)
    q2_models[[key]] <- feols(fml, data = dt, cluster = ~PWSID)
  }
}

# ── 7b. Q2 reverse regressions: visit_t -> mr_any_{t+1..t+h} ─────────────────
q3_models <- list()
for (vdef in c("visit_san", "visit_any")) {
  for (h in c(6, 12)) {
    dt   <- if (h == 6) reg6 else reg12
    yvar <- paste0("mr_any_next", h)
    fml  <- as.formula(paste0(yvar, " ~ ", vdef, " | PWSID + month_idx"))
    key  <- paste0(vdef, "__h", h)
    q3_models[[key]] <- feols(fml, data = dt, cluster = ~PWSID)
  }
}

# ── 8. Output: Q1 summary table — does the visit precede or follow the MR
#      violation in the chain that ends in (reduced) enforcement? ────────────
# Col 1: P(enforcement in the 12 months following an MR violation).
# Col 2: among MR violations preceded by a sanitary visit in the prior 12
#        months, P(enforcement in the 12 months following the MR violation).
# Col 3: among MR violations followed by a sanitary visit within the next 12
#        months, P(enforcement in the 12 months following THAT VISIT) —
#        i.e. the visit, not the MR violation, anchors the outcome window.
dict <- c(visit_san = "Sanitary visit (t)", visit_any = "Any non-enforcement visit (t)",
          mr_any = "MR violation begins (t)")

enf_cols_q1 <- c(enf_formal = "Formal", enf_informal = "Informal", enf_any = "Any")

# Column 2: MR violation in month t, sanitary visit in [t-12, t-1]
col2_dt <- reg12[mr_any == 1 & visit_san_prev12 == 1]

# Column 3: MR violation in month t, first sanitary visit in (t, t+12]; outcome
# is enf_X_next12 evaluated at that visit's month (already on skel for every
# CWS-month from section 4's forward-window construction).
mr_events <- unique(mr[, .(PWSID, mr_month = month_idx)])
san_visit_months <- unique(sv[is_san == TRUE, .(PWSID, visit_month = month_idx)])
link <- san_visit_months[mr_events, on = "PWSID", allow.cartesian = TRUE]
link <- link[visit_month > mr_month & visit_month <= mr_month + 12]
link <- link[, .(visit_month = min(visit_month)), by = .(PWSID, mr_month)]
link <- merge(link, skel[, c("PWSID", "month_idx",
                              paste0(names(enf_cols_q1), "_next12")), with = FALSE],
              by.x = c("PWSID", "visit_month"), by.y = c("PWSID", "month_idx"), all.x = TRUE)

mr_dt <- reg12[mr_any == 1]

q1_summary <- data.table(
  enf_type = unname(enf_cols_q1),
  after_mr_pct = sapply(names(enf_cols_q1), function(cl)
    round(100 * mean(mr_dt[[paste0(cl, "_next12")]], na.rm = TRUE), 2)),
  visit_before_mr_pct = sapply(names(enf_cols_q1), function(cl)
    round(100 * mean(col2_dt[[paste0(cl, "_next12")]], na.rm = TRUE), 2)),
  visit_after_mr_pct = sapply(names(enf_cols_q1), function(cl)
    round(100 * mean(link[[paste0(cl, "_next12")]], na.rm = TRUE), 2))
)

rows_q1 <- sprintf("%s & %.2f & %.2f & %.2f \\\\",
                    q1_summary$enf_type, q1_summary$after_mr_pct,
                    q1_summary$visit_before_mr_pct, q1_summary$visit_after_mr_pct)

notes_q1 <- paste0("Sample: strictly downstream CWSs (", length(sample_pwsids),
                    "), CWS-months 1985-01 to 2004-12 (right-censored to allow a full ",
                    "12-month forward window). Column 1: among all MR-violation onsets (",
                    uniqueN(mr$PWSID), " CWSs, N=", nrow(mr_dt), "), the probability that ",
                    "enforcement of that type occurs in the 12 months following the MR ",
                    "violation. Column 2: among MR-violation onsets preceded by a sanitary ",
                    "visit (visit\\_san: SNSV/SNSP/SSVF) in the prior 12 months (N=", nrow(col2_dt),
                    "), the probability of enforcement in the 12 months following the MR ",
                    "violation. Column 3: among MR-violation onsets followed by a sanitary ",
                    "visit within the next 12 months (N=", nrow(link), "), the probability of ",
                    "enforcement in the 12 months following that visit (the first qualifying ",
                    "visit after the violation). Comparing columns 2 and 3 distinguishes whether ",
                    "visits forestall enforcement by preceding the MR violation (visit $\\to$ ",
                    "lower MR risk $\\to$ lower enforcement, column 2) or by following it (MR ",
                    "violation $\\to$ visit $\\to$ lower enforcement after the visit, column 3).")

out_q1 <- file.path(ROOT, "output/sum/sanitary_visit_to_enforcement.tex")
lines_q1 <- c(
  "\\begin{table}[htbp]",
  "\\caption{\\label{tab:visit_to_enf} Sanitary Visits Before vs. After MR Violations: Probability of Subsequent Enforcement (Downstream CWSs, 1985--2005)}",
  "\\bigskip",
  "\\centering",
  "\\begin{adjustbox}{width = \\textwidth, center}",
  "\\begin{tabular}{lccc}",
  "\\toprule",
  "Enforcement type & Within 12mo of MR (\\%) & Visit occured in year preceding MR (\\%) & Visit occured in year following MR (\\%) \\\\",
  "\\midrule",
  rows_q1,
  "\\bottomrule",
  "\\end{tabular}",
  "\\end{adjustbox}",
  "{\\tiny\\linespread{1}\\selectfont \\par \\raggedright ",
  notes_q1,
  "}",
  "\\end{table}"
)
writeLines(lines_q1, out_q1)
cat("\nWrote:", out_q1, "\n")

# ── 8b. Regression version of the Q1 summary table — single regression per
#       outcome with both timing indicators, so the before/after coefficients
#       are estimated jointly and directly comparable (and testable for
#       equality), rather than read off as two separate conditional means.
#       enf_X_next{6,12} ~ visit_san_prev12 + visit_after_mr | PWSID + month_idx,
#       estimated on the MR-violation sample only (mr_any == 1).
build_backward(reg6, "visit_san", 12)
reg6[,  visit_after_mr := visit_san_next12]
reg12[, visit_after_mr := visit_san_next12]

mr6_dt  <- reg6[mr_any == 1]
mr12_dt <- reg12[mr_any == 1]

timing_models <- list()
for (ecat in names(enf_cols_q1)) {
  for (h in c(6, 12)) {
    dt   <- if (h == 6) mr6_dt else mr12_dt
    yvar <- paste0(ecat, "_next", h)
    fml  <- as.formula(paste0(yvar, " ~ visit_san_prev12 + visit_after_mr | PWSID + month_idx"))
    key  <- paste0(ecat, "__h", h)
    timing_models[[key]] <- feols(fml, data = dt, cluster = ~PWSID)
  }
}

# Wald test of equality between the two timing coefficients in each model
equality_pval <- function(mod) {
  b  <- coef(mod)
  vc <- vcov(mod)
  if (!all(c("visit_san_prev12", "visit_after_mr") %in% names(b))) return(NA_real_)
  diff   <- b["visit_san_prev12"] - b["visit_after_mr"]
  se_dif <- sqrt(vc["visit_san_prev12", "visit_san_prev12"] +
                 vc["visit_after_mr", "visit_after_mr"] -
                 2 * vc["visit_san_prev12", "visit_after_mr"])
  2 * pnorm(-abs(diff / se_dif))
}

timing_col_order <- as.vector(outer(names(enf_cols_q1), c(6, 12),
                                     function(e, h) paste0(e, "__h", h)))
timing_ordered   <- timing_models[timing_col_order]
ecat_order_t <- rep(names(enf_cols_q1), 2)
h_order_t    <- rep(c(6, 12), each = length(enf_cols_q1))
headers_timing <- paste0(rep(unname(enf_cols_q1), 2), " (", h_order_t, "mo)")
pvals_timing   <- sapply(timing_ordered, equality_pval)

dict_timing <- c(visit_san_prev12 = "Visit in 12mo before MR",
                  visit_after_mr  = "Visit in 12mo after MR")

ta_timing <- etable(timing_ordered,
                     headers = list("Outcome: enforcement in next h months" = headers_timing),
                     dict = dict_timing, tex = TRUE)

notes_timing <- paste0("Sample: MR-violation onsets at strictly downstream CWSs (",
                        uniqueN(mr$PWSID), " CWSs; N=", nrow(mr6_dt), " for 6mo outcomes, N=",
                        nrow(mr12_dt), " for 12mo outcomes). Visit\\_san\\_prev12 = sanitary ",
                        "visit (SNSV/SNSP/SSVF) in the 12 months before the MR violation; ",
                        "visit\\_after\\_mr = sanitary visit in the 12 months after the MR ",
                        "violation. LPM with PWSID and calendar-month fixed effects; SEs ",
                        "clustered by PWSID. P-values from a Wald test of equality between the ",
                        "two timing coefficients, by outcome: ",
                        paste(sprintf("%s = %.3f", headers_timing, pvals_timing), collapse = "; "),
                        ".")

out_timing <- file.path(ROOT, "output/reg/sanitary_visit_to_enforcement_timing.tex")
lines_timing <- c(
  "\\begin{table}[htbp]",
  "\\caption{\\label{tab:visit_to_enf_timing} Sanitary Visit Timing and Enforcement: Before vs. After MR Violation}",
  "\\bigskip",
  "\\centering",
  "\\begin{adjustbox}{width = \\textwidth, center}",
  as.character(ta_timing),
  "\\end{adjustbox}",
  "{\\tiny\\linespread{1}\\selectfont \\par \\raggedright ",
  notes_timing,
  "}",
  "\\end{table}"
)
writeLines(lines_timing, out_timing)
cat("Wrote:", out_timing, "\n")

# ── 9. Output: Q2 table (Panel A: MR -> visit; Panel B: visit -> MR) ────────
q2_col_order <- c("visit_san__h6", "visit_san__h12", "visit_any__h6", "visit_any__h12")
q2_ordered   <- q2_models[q2_col_order]
headers_q2   <- c("Sanitary visit (6mo)", "Sanitary visit (12mo)",
                   "Any visit (6mo)", "Any visit (12mo)")
base_rates_q2 <- c(base_rate(reg6, "visit_san_next6"), base_rate(reg12, "visit_san_next12"),
                    base_rate(reg6, "visit_any_next6"), base_rate(reg12, "visit_any_next12"))

q3_ordered  <- q3_models[q2_col_order]
headers_q3  <- c("MR violation (6mo)", "MR violation (12mo)",
                  "MR violation (6mo)", "MR violation (12mo)")
base_rates_q3 <- c(base_rate(reg6, "mr_any_next6"), base_rate(reg12, "mr_any_next12"),
                    base_rate(reg6, "mr_any_next6"), base_rate(reg12, "mr_any_next12"))

dict_q2 <- c(dict, PWSID = "CWS", month_idx = "month", visit_any = "Any visit (t)")

ta_q2 <- etable(q2_ordered, headers = list("Outcome: site visit in next h months" = headers_q2),
                 dict = dict_q2, depvar = FALSE, fitstat = ~ n, tex = TRUE)
tb_q2 <- etable(q3_ordered,
                 headers = list("Outcome: MR violation begins in next h months" = headers_q3),
                 dict = dict_q2, depvar = FALSE, fitstat = ~ n, tex = TRUE)

notes_q2 <- paste0("Sample: strictly downstream CWSs (", length(sample_pwsids),
                    "), PWSID-months 1985-01 to 2005-12. Panel A regressor is any MR ",
                    "violation (VIOLATION\\_CATEGORY\\_CODE=MR, any rule code) beginning in ",
                    "month t; Panel B regressors are visit\\_san (sanitary survey: ",
                    "SNSV/SNSP/SSVF) and visit\\_any (any visit reason except FENF/IENF) in ",
                    "month t. Base rates (\\%) of the next-h-month outcome: Panel A: ",
                    paste(sprintf("%s = %s", headers_q2, base_rates_q2), collapse = "; "),
                    "; Panel B: ",
                    paste(sprintf("%s = %s", headers_q3, base_rates_q3), collapse = "; "),
                    ". LPM with PWSID and calendar-month fixed effects; SEs clustered by PWSID.")

out_q2 <- file.path(ROOT, "output/reg/mr_to_sanitary_visit.tex")
lines_q2 <- c(
  "\\begin{table}[htbp]",
  "\\caption{\\label{tab:mr_to_visit} MR Violations and Subsequent Sanitary Visits}",
  "\\bigskip",
  "\\centering",
  "\\textbf{Panel A: MR Violation (\\texttt{mr\\_any}) $\\to$ Site Visit}\\\\[4pt]",
  "\\begin{adjustbox}{width = \\textwidth, center}",
  as.character(ta_q2),
  "\\end{adjustbox}",
  "\\vspace{8pt}",
  "\\textbf{Panel B: Site Visit $\\to$ MR Violation (\\texttt{mr\\_any})}\\\\[4pt]",
  "\\begin{adjustbox}{width = \\textwidth, center}",
  as.character(tb_q2),
  "\\end{adjustbox}",
  "{\\tiny\\linespread{1}\\selectfont \\par \\raggedright ",
  notes_q2,
  "}",
  "\\end{table}"
)
writeLines(lines_q2, out_q2)
cat("Wrote:", out_q2, "\n")

# ── 10. Visit-type summary table ─────────────────────────────────────────────
# Descriptive labels for SDWA_SITE_VISITS.VISIT_REASON_CODE, taken from
# SDWA_REF_CODE_VALUES.csv (VALUE_TYPE == "VISIT_REASON_CODE").
visit_type_labels <- c(
  XCON = "Cross connection inspection", L1PS = "Level 1 assessment, partial survey",
  L1SS = "Level 1 assessment and sanitary survey", L2PS = "Level 2 assessment, partial survey",
  L2SS = "Level 2 assessment and sanitary survey", LV1A = "Level 1 assessment (RTCR)",
  LV2A = "Level 2 assessment (RTCR)", CAPD = "Capacity development assessment",
  CMPA = "Compliance assistance", CNST = "Construction inspection",
  CPEV = "Comprehensive performance evaluation", EMRG = "Emergency assistance",
  ENGR = "Engineering determination/advice/plan review", FENF = "Formal enforcement",
  FUFE = "Follow-up to formal enforcement", IENF = "Informal enforcement",
  INFI = "Informal system inspection", INVG = "Investigation",
  LABC = "Laboratory certification", LABI = "Laboratory inspection",
  LOCD = "Locational data collection", NEED = "Needs survey",
  OM = "Operation and maintenance", OTHR = "Other",
  PRMT = "Permit (qualification/review/compliance)", PUBH = "Public hearing",
  RCDR = "Record review", RSCH = "Regularly scheduled",
  SHAZ = "Sanitary hazards investigation", SITE = "Site inspection",
  SMPL = "Sample collection", SNSP = "Sanitary survey, partial",
  SNSV = "Sanitary survey, complete", SRCE = "Source water inspection",
  SRF = "State revolving fund", SSVF = "Sanitary survey follow-up",
  TECH = "Technical assistance", TRNG = "Training",
  TRTP = "Water treatment plant site visit", VAEX = "Variance/exemption related",
  WHPP = "Wellhead protection program", WSHD = "Watershed evaluation"
)

# Per-type PWSID-month indicators for every VISIT_REASON_CODE observed in the
# sample (already restricted to sample_pwsids and 1985-2005 above).
present_types <- sort(unique(sv$VISIT_REASON_CODE))
type_pm <- unique(sv[, .(PWSID, month_idx, VISIT_REASON_CODE)])
type_wide <- dcast(type_pm, PWSID + month_idx ~ VISIT_REASON_CODE,
                    fun.aggregate = length, value.var = "VISIT_REASON_CODE", fill = 0L)

skel_types <- merge(skel[, .(PWSID, month_idx, mr_any)], type_wide,
                     by = c("PWSID", "month_idx"), all.x = TRUE)
for (cl in present_types) skel_types[is.na(get(cl)), (cl) := 0L]
setorder(skel_types, PWSID, month_idx)
for (cl in present_types) {
  build_forward(skel_types, cl, 6)
  build_forward(skel_types, cl, 12)
}

reg6_types  <- skel_types[month_idx <= max_origin_6]
reg12_types <- skel_types[month_idx <= max_origin_12]

visit_summary <- data.table(code = present_types)
visit_summary[, label := visit_type_labels[code]]
visit_summary[, unconditional_pct := sapply(code, function(cd)
  100 * uniqueN(sv[VISIT_REASON_CODE == cd, PWSID]) / length(sample_pwsids))]
visit_summary[, cond6_pct := sapply(code, function(cd)
  100 * mean(reg6_types[mr_any == 1][[paste0(cd, "_next6")]], na.rm = TRUE))]
visit_summary[, cond12_pct := sapply(code, function(cd)
  100 * mean(reg12_types[mr_any == 1][[paste0(cd, "_next12")]], na.rm = TRUE))]
setorder(visit_summary, -unconditional_pct)

cat("\nVisit-type summary: ", nrow(visit_summary), " types observed in sample\n", sep = "")

rows_summary <- sprintf("%s & %.2f & %.2f & %.2f \\\\",
                         visit_summary$label, visit_summary$unconditional_pct,
                         visit_summary$cond6_pct, visit_summary$cond12_pct)

n_mr_pwsids <- uniqueN(mr$PWSID)
notes_summary <- paste0(
  "Sample: strictly downstream CWSs (", length(sample_pwsids), "), CWS-months 1985-01 to ",
  "2005-12. Column 1: share of sample CWSs with at least one visit of that type, ",
  "1985--2005. Columns 2-3: among CWS-months in which an MR violation begins (",
  n_mr_pwsids, " CWSs ever have an MR-violation onset), the share followed by a visit ",
  "of that type within the next 6 (12) months, right-censored at 2005-06 (2004-12) as ",
  "in the regressions above."
)

out_summary <- file.path(ROOT, "output/sum/visit_type_summary.tex")
lines_summary <- c(
  "\\begin{table}[htbp]",
  "\\caption{\\label{tab:visit_type_summary} Site Visit Types: Frequency and Timing Relative to MR Violations (Downstream CWSs, 1985--2005)}",
  "\\bigskip",
  "\\centering",
  "\\begin{adjustbox}{width = \\textwidth, center}",
  "\\begin{tabular}{lccc}",
  "\\toprule",
  "Visit type & Unconditional probability (\\%) & Visit within 6 months of MR & Visit within year of MR \\\\",
  "\\midrule",
  rows_summary,
  "\\bottomrule",
  "\\end{tabular}",
  "\\end{adjustbox}",
  "{\\tiny\\linespread{1}\\selectfont \\par \\raggedright ",
  notes_summary,
  "}",
  "\\end{table}"
)
writeLines(lines_summary, out_summary)
cat("Wrote:", out_summary, "\n")

# ── 11. Verification ──────────────────────────────────────────────────────────
stopifnot(file.exists(out_q1), file.exists(out_timing), file.exists(out_q2), file.exists(out_summary))
stopifnot(file.info(out_q1)$size > 0, file.info(out_timing)$size > 0,
          file.info(out_q2)$size > 0, file.info(out_summary)$size > 0)
cat("\nOutput verified: all four .tex files exist and are non-zero.\n")
cat("=== DONE ===\n")
