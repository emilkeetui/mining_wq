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
n_months <- month_idx_of(as.Date("2005-12-01"))

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
                 "NON_COMPL_PER_BEGIN_DATE", "NON_COMPL_PER_END_DATE",
                 "VIOLATION_CATEGORY_CODE", "RULE_CODE",
                 "ENFORCEMENT_DATE", "ENF_ACTION_CATEGORY", "CALCULATED_RTC_DATE")))
ve <- ve[PWSID %in% sample_pwsids]

# Enforcement events (ongoing) — each action spans ENFORCEMENT_DATE through
# CALCULATED_RTC_DATE (fallback NON_COMPL_PER_END_DATE, then single month)
enf <- ve[!is.na(ENFORCEMENT_ID) & !is.na(ENFORCEMENT_DATE)]
enf[, enf_dt  := as.Date(ENFORCEMENT_DATE,       "%m/%d/%Y")]
enf[, rtc_dt  := as.Date(CALCULATED_RTC_DATE,    "%m/%d/%Y")]
enf[, ncpe_dt := as.Date(NON_COMPL_PER_END_DATE, "%m/%d/%Y")]
enf <- enf[!is.na(enf_dt)]
enf[, enf_yr := as.integer(format(enf_dt, "%Y"))]
enf <- enf[enf_yr >= 1985 & enf_yr <= 2005]
enf[, end_dt      := fifelse(!is.na(rtc_dt), rtc_dt, fifelse(!is.na(ncpe_dt), ncpe_dt, enf_dt))]
enf[, start_month := month_idx_of(enf_dt)]
enf[, end_month   := pmax(month_idx_of(end_dt), start_month)]
enf <- unique(enf[, .(PWSID, ENFORCEMENT_ID, start_month, end_month, ENF_ACTION_CATEGORY)])

month_lists <- Map(seq, enf$start_month, enf$end_month)
n_per_row   <- lengths(month_lists)
enf_long <- data.table(
  PWSID               = rep(enf$PWSID, n_per_row),
  ENF_ACTION_CATEGORY = rep(enf$ENF_ACTION_CATEGORY, n_per_row),
  month_idx           = unlist(month_lists)
)
enf_long <- enf_long[month_idx >= 1 & month_idx <= n_months]

enf_pm <- enf_long[, .(
  enf_informal  = as.integer(any(ENF_ACTION_CATEGORY == "Informal",  na.rm = TRUE)),
  enf_resolving = as.integer(any(ENF_ACTION_CATEGORY == "Resolving", na.rm = TRUE)),
  enf_formal    = as.integer(any(ENF_ACTION_CATEGORY == "Formal",    na.rm = TRUE))
), by = .(PWSID, month_idx)]
enf_pm[, enf_any := as.integer(enf_informal == 1 | enf_resolving == 1 | enf_formal == 1)]
cat("Enforcement PWSID-months (ongoing):", nrow(enf_pm),
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

# ── 6. Backward window for visit_san (used in section 8b timing regressions) ─
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
build_backward(skel,  "mr_any",    12)

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

# ── 8. Summary table: visit frequency around enforcement events, by visit group
#      Two panels: Panel A = formal enforcement, Panel B = informal enforcement
#      Unconditional probability = share of all CWS-months with that enforcement
#      type (the baseline for interpreting regression coefficients).
#      Pre/post columns = P(visit group occurs in ±H months | enforcement event)

dict <- c(visit_san = "Sanitary visit (t)", visit_any = "Any non-enforcement visit (t)",
          mr_any = "MR violation begins (t)")

enf_cols_q1 <- c(enf_formal = "Formal", enf_informal = "Informal", enf_any = "Any")

H <- 6L

group_order_q1 <- c("Sanitary visits", "Technical assistance", "Enforcement visits",
                     "Sample collection", "Inspection")
group_codes_q1 <- list(
  "Sanitary visits"      = c("SNSV", "SSVF"),
  "Technical assistance" = c("TECH", "ENGR", "OM"),
  "Enforcement visits"   = c("FENF", "INVG", "EMRG"),
  "Sample collection"    = c("SMPL"),
  "Inspection"           = c("SITE", "RSCH", "INFI")
)

fmt_n   <- function(x) gsub(",", "{,}", formatC(x, format = "d", big.mark = ","))
fmt_pct <- function(x) ifelse(is.nan(x) | is.na(x), "--", sprintf("%.2f", x))

# Compute visit-anchored enforcement probability for one enforcement type (enf_col).
# Unconditional prob = share of ALL CWS-months (skel) with that enforcement.
# Col 3 = P(enf | CWS-month falls in the 6-month window AFTER a visit of this type):
#   for each visit at month t, expand to months [t, t+6]; among all such cells,
#   compute the share with that enforcement type.
# Col 4 = P(enf | CWS-month falls in the 6-month window BEFORE a visit of this type):
#   for each visit at month t, expand to months [t-6, t]; share with enforcement.
enf_visit_rows <- function(enf_col) {
  unc_enf_pct <- round(100 * mean(skel[[enf_col]]), 2)
  enf_skel    <- skel[, .(PWSID, month_idx, enf = get(enf_col))]

  rbindlist(lapply(group_order_q1, function(grp) {
    codes  <- group_codes_q1[[grp]]
    grp_pm <- unique(sv[VISIT_REASON_CODE %in% codes, .(PWSID, month_idx)])

    if (nrow(grp_pm) == 0) {
      return(data.table(group = grp, unconditional_pct = unc_enf_pct,
                        after_pct = NaN, before_pct = NaN))
    }

    # All CWS-months in the 6-month window AFTER each visit
    after_cells <- grp_pm[, .(month_idx = seq(month_idx, month_idx + 6L)),
                            by = .(PWSID, v = month_idx)]
    after_cells <- unique(after_cells[month_idx >= 1 & month_idx <= n_months,
                                       .(PWSID, month_idx)])

    # All CWS-months in the 6-month window BEFORE each visit
    before_cells <- grp_pm[, .(month_idx = seq(month_idx - 6L, month_idx)),
                             by = .(PWSID, v = month_idx)]
    before_cells <- unique(before_cells[month_idx >= 1 & month_idx <= n_months,
                                         .(PWSID, month_idx)])

    enf_after  <- merge(after_cells,  enf_skel, by = c("PWSID", "month_idx"), all.x = TRUE)
    enf_before <- merge(before_cells, enf_skel, by = c("PWSID", "month_idx"), all.x = TRUE)

    data.table(
      group             = grp,
      unconditional_pct = unc_enf_pct,
      after_pct         = round(100 * mean(enf_after$enf,  na.rm = TRUE), 2),
      before_pct        = round(100 * mean(enf_before$enf, na.rm = TRUE), 2)
    )
  }))
}

formal_rows   <- enf_visit_rows("enf_formal")
informal_rows <- enf_visit_rows("enf_informal")

n_formal   <- nrow(reg6[enf_formal   == 1])
n_informal <- nrow(reg6[enf_informal == 1])

emit_panel_rows <- function(rows) {
  sprintf("%s & %.2f & %s & %s \\\\",
          rows$group,
          rows$unconditional_pct,
          fmt_pct(rows$after_pct),
          fmt_pct(rows$before_pct))
}

notes_q1 <- paste0(
  "Sample: strictly downstream CWSs (", length(sample_pwsids), "), CWS-months ",
  "1985-01 to 2005-12. Total CWS-months: ", nrow(skel), " (", length(sample_pwsids), " CWSs). ",
  "Column 2 (Unconditional probability): share of all CWS-months in which that panel's ",
  "enforcement type occurs; this is the mean of the dependent variable for interpreting ",
  "regression coefficients from sanitary\\_visit\\_enforcement\\_iterative.tex in percentage-point ",
  "vs.\\ relative terms. ",
  "Column 3: among all CWS-months falling within the 6-month window following any visit of ",
  "that type (months $[t, t+6]$ for each visit at month $t$), the share with that enforcement ",
  "type beginning in that month, i.e.\\ P(enf.\\ $|$ within 6 mo.\\ after visit). ",
  "Column 4: among all CWS-months falling within the 6-month window preceding any visit of ",
  "that type (months $[t-6, t]$ for each visit at month $t$), the share with that enforcement ",
  "type beginning in that month, i.e.\\ P(enf.\\ $|$ within 6 mo.\\ before visit). ",
  "CWS-months may appear in multiple windows if visits are closely spaced. ",
  "Enforcement event counts for context: Panel A formal N\\,=\\,",
  fmt_n(n_formal), "; Panel B informal N\\,=\\,", fmt_n(n_informal), ". ",
  "Visit groups: sanitary visits (SNSV, SSVF); technical assistance (TECH, ENGR, OM); ",
  "enforcement visits (FENF, INVG, EMRG); sample collection (SMPL); inspection (SITE, RSCH, INFI)."
)

out_q1 <- file.path(ROOT, "output/sum/sanitary_visit_to_enforcement.tex")
lines_q1 <- c(
  "\\begin{table}[htbp]",
  paste0("\\caption{\\label{tab:visit_to_enf} Visit Frequency Around Enforcement Actions, ",
         "by Visit Group (Downstream CWSs, 1985--2005)}"),
  "\\bigskip",
  "\\centering",
  "\\begin{adjustbox}{width = \\textwidth, center}",
  "\\begin{tabular}{lccc}",
  "\\toprule",
  paste0("Visit group & Unconditional probability (\\%) & ",
         "P(enf.\\ 6 mo.\\ after visit) (\\%) & ",
         "P(enf.\\ 6 mo.\\ before visit) (\\%) \\\\"),
  "\\midrule",
  paste0("\\multicolumn{4}{l}{\\textbf{Panel A: Formal enforcement} ",
         "(N\\,=\\,", fmt_n(n_formal), " enforcement events)} \\\\"),
  "\\midrule",
  emit_panel_rows(formal_rows),
  "\\midrule",
  paste0("\\multicolumn{4}{l}{\\textbf{Panel B: Informal enforcement} ",
         "(N\\,=\\,", fmt_n(n_informal), " enforcement events)} \\\\"),
  "\\midrule",
  emit_panel_rows(informal_rows),
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

skel_types <- merge(skel[, .(PWSID, month_idx, mr_any, mr_any_next12, mr_any_prev12)],
                     type_wide, by = c("PWSID", "month_idx"), all.x = TRUE)
for (cl in present_types) skel_types[is.na(get(cl)), (cl) := 0L]
setorder(skel_types, PWSID, month_idx)
skel_types[, year := 1985L + (month_idx - 1L) %/% 12L]

# Right-censored version (consistent with section 5): a month only carries a
# valid mr_any_next12 window if it isn't within 12 months of the sample end.
# mr_any_prev12 is NA only for the first 11 months of the sample (no backward
# window), handled by build_backward's fill = NA.
reg12_types <- skel_types[month_idx <= max_origin_12]

# CWS-year level summary. Col 1/2: does a visit of this type occur at all in
# the CWS-year (sum / share over all CWS-years). Col 4: among CWS-years in
# which the visit occurs, the share where that visit (in a non-censored
# month) precedes an MR violation within the next 12 months. Col 5: among
# CWS-years in which the visit occurs, the share where that visit follows an
# MR violation that began within the prior 12 months.
visit_summary <- data.table(code = present_types)
visit_summary[, label := visit_type_labels[code]]

year_stats <- rbindlist(lapply(present_types, function(cd) {
  visited_dt <- skel_types[, .(visited = as.integer(any(get(cd) > 0))), by = .(PWSID, year)]
  pre12_dt   <- reg12_types[, .(pre12  = as.integer(any(get(cd) > 0 & mr_any_next12 == 1, na.rm = TRUE))),
                            by = .(PWSID, year)]
  post12_dt  <- skel_types[,  .(post12 = as.integer(any(get(cd) > 0 & mr_any_prev12 == 1, na.rm = TRUE))),
                            by = .(PWSID, year)]
  m <- merge(visited_dt, pre12_dt,  by = c("PWSID", "year"), all.x = TRUE)
  m <- merge(m,          post12_dt, by = c("PWSID", "year"), all.x = TRUE)
  data.table(
    n_obs             = sum(m$visited),
    unconditional_pct = 100 * mean(m$visited),
    precede_pct       = 100 * mean(m$pre12[m$visited == 1],  na.rm = TRUE),
    follow_pct        = 100 * mean(m$post12[m$visited == 1], na.rm = TRUE)
  )
}))
visit_summary <- cbind(visit_summary, year_stats)

# Group visit types into the five categories used as dependent variables in
# h2_snsv_d12.tex and sanitary_visit_enforcement_iterative.tex. Codes not
# listed here (OTHR, TRNG, LABC, PRMT, VAEX, CPEV, RCDR, ...) are dropped from
# this table since they don't fall cleanly into any of the five groups.
visit_group_map <- c(
  SNSV = "Sanitary visits", SSVF = "Sanitary visits",
  TECH = "Technical assistance", ENGR = "Technical assistance", OM = "Technical assistance",
  FENF = "Enforcement visits", INVG = "Enforcement visits", EMRG = "Enforcement visits",
  SMPL = "Sample collection",
  SITE = "Inspection", RSCH = "Inspection", INFI = "Inspection"
)
group_order <- c("Sanitary visits", "Technical assistance", "Enforcement visits",
                  "Sample collection", "Inspection")

visit_summary[, group := visit_group_map[code]]
visit_summary <- visit_summary[!is.na(group)]
visit_summary[, group := factor(group, levels = group_order)]
setorder(visit_summary, group, -unconditional_pct)

cat("\nVisit-type summary: ", nrow(visit_summary), " types observed in sample (",
    length(present_types) - nrow(visit_summary), " dropped, not in any group)\n", sep = "")

# NaN occurs when every CWS-year with that visit type is fully right-censored
# at the given horizon (e.g. a type observed only in 2005 for the 12-month
# window); display as "--" rather than "NaN".
fmt_pct <- function(x) ifelse(is.nan(x), "--", sprintf("%.2f", x))

rows_summary <- sprintf("%d & %s & %s & %.2f & %s & %s \\\\",
                         visit_summary$n_obs,
                         as.character(visit_summary$group), visit_summary$label,
                         visit_summary$unconditional_pct,
                         fmt_pct(visit_summary$precede_pct), fmt_pct(visit_summary$follow_pct))

n_mr_pwsids <- uniqueN(mr$PWSID)
notes_summary <- paste0(
  "Sample: strictly downstream CWSs (", length(sample_pwsids), "), CWS-years 1985 to ",
  "2005 (", length(sample_pwsids), " CWSs x 21 years). Visit types are grouped into ",
  "sanitary visits (SNSV, SSVF), technical assistance (TECH, ENGR, OM), enforcement ",
  "visits (FENF, INVG, EMRG), sample collection (SMPL), and inspection (SITE, RSCH, ",
  "INFI); types not falling into one of these five groups are omitted. Column 1: ",
  "number of CWS-years with at least one visit of that type, 1985--2005. Column 3: ",
  "share of all CWS-years with at least one visit of that type. Column 4: among ",
  "CWS-years with at least one visit of that type, the share in which that visit (in ",
  "a month with a fully observed forward window) precedes an MR violation onset ",
  "within the next 12 months, right-censored at 2004-12 as in the regressions above. ",
  "Column 5: among CWS-years with at least one visit of that type, the share in which ",
  "that visit follows an MR violation onset that began within the prior 12 months."
)

out_summary <- file.path(ROOT, "output/sum/visit_type_summary.tex")
lines_summary <- c(
  "\\begin{table}[htbp]",
  "\\caption{\\label{tab:visit_type_summary} Site Visit Types: Frequency and Timing Relative to MR Violations (Downstream CWSs, 1985--2005)}",
  "\\bigskip",
  "\\centering",
  "\\begin{adjustbox}{width = \\textwidth, center}",
  "\\begin{tabular}{lllccc}",
  "\\toprule",
  "N & Group & Visit type & Unconditional probability (\\%) & Visit precedes MR within year (\\%) & Visit follows MR within year (\\%) \\\\",
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
