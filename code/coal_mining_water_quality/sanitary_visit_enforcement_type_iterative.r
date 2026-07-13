# ============================================================
# Script: sanitary_visit_enforcement_type_iterative.r
# Purpose: CWS-month panel (strictly-downstream 2SLS sample, 1985-2005)
#          testing whether sanitary visit timing predicts the *type* of
#          enforcement action taken that month. Binary before6/after6
#          window indicators built for sanitary visits (SNSV/SNSP/SSVF),
#          mirroring sanitary_visit_mr_violation_iterative.r. Three LPM
#          outcomes, one per column block: formal enforcement action,
#          informal enforcement action, no enforcement action.
#          Col 1: formal enforcement,   sanitary visit windows only, no FE (full panel)
#          Col 2: formal enforcement,   + n_prior_violations + pct_mcl_last_max,
#                 CWS + calendar-month FE (SYR2-restricted)
#          Col 3: informal enforcement, sanitary visit windows only, no FE (full panel)
#          Col 4: informal enforcement, + n_prior_violations + pct_mcl_last_max,
#                 CWS + calendar-month FE (SYR2-restricted)
#          Col 5: no enforcement,       sanitary visit windows only, no FE (full panel)
#          Col 6: no enforcement,       + n_prior_violations + pct_mcl_last_max,
#                 CWS + calendar-month FE (SYR2-restricted)
#          Enforcement action type: ENF_ACTION_CATEGORY == "Formal" / "Informal"
#          on ENFORCEMENT_DATE; no_enforcement = 1 if neither occurred that month.
# Inputs:  clean_data/cws_data/prod_vio_sulfur.parquet
#          clean_data/cws_6year_review_measurement_level_syr2.parquet
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_SITE_VISITS.csv
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.parquet
# Outputs: output/reg/sanitary_visit_enforcement_type_iterative.tex
# Author: EK  Date: 2026-07-13
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
    col_select = c("PWSID", "minehuc_downstream_of_mine", "minehuc_mine")))
downstream_mask <- panel$minehuc_downstream_of_mine == 1 & panel$minehuc_mine == 0
sample_pwsids   <- unique(panel$PWSID[downstream_mask])
cat("Downstream CWSs in sample:", length(sample_pwsids), "\n")

month_idx_of <- function(d) {
  yr <- as.integer(format(d, "%Y"))
  mo <- as.integer(format(d, "%m"))
  (yr - 1985L) * 12L + (mo - 1L) + 1L
}
n_months <- month_idx_of(as.Date("2005-12-01"))

# ── 1. Violation onsets (for n_prior_violations control) ──────────────────────
ve <- as.data.table(arrow::read_parquet(
  file.path(SDWA_DIR, "SDWA_VIOLATIONS_ENFORCEMENT.parquet"),
  col_select = c("PWSID", "VIOLATION_ID", "NON_COMPL_PER_BEGIN_DATE")))
ve <- ve[PWSID %in% sample_pwsids]

onsets <- unique(ve[, .(PWSID, VIOLATION_ID, NON_COMPL_PER_BEGIN_DATE)])
onsets[, onset_dt := as.Date(NON_COMPL_PER_BEGIN_DATE, "%m/%d/%Y")]
onsets <- onsets[!is.na(onset_dt)]
onsets[, onset_yr := as.integer(format(onset_dt, "%Y"))]
onsets <- onsets[onset_yr >= 1985 & onset_yr <= 2005]
onsets[, month_idx := month_idx_of(onset_dt)]
setorder(onsets, PWSID, onset_dt)

# n_prior_violations: cumulative count of onsets strictly before this month
onset_counts <- onsets[, .(n_onsets_this_month = .N), by = .(PWSID, month_idx)]
setorder(onset_counts, PWSID, month_idx)
onset_counts[, cum_after := cumsum(n_onsets_this_month), by = PWSID]
onset_counts[, n_prior_violations := cum_after - n_onsets_this_month]

rm(ve); gc()

# ── 2. Enforcement action type by CWS-month (Formal / Informal / none) ───────
enf <- as.data.table(arrow::read_parquet(
  file.path(SDWA_DIR, "SDWA_VIOLATIONS_ENFORCEMENT.parquet"),
  col_select = c("PWSID", "ENFORCEMENT_DATE", "ENF_ACTION_CATEGORY")))
enf <- enf[PWSID %in% sample_pwsids & ENF_ACTION_CATEGORY %in% c("Formal", "Informal")]
enf[, enf_dt := as.Date(ENFORCEMENT_DATE, "%m/%d/%Y")]
enf <- enf[!is.na(enf_dt)]
enf[, yr := as.integer(format(enf_dt, "%Y"))]
enf <- enf[yr >= 1985 & yr <= 2005]
enf[, month_idx := month_idx_of(enf_dt)]

cat("Formal enforcement actions:  ", nrow(enf[ENF_ACTION_CATEGORY == "Formal"]),
    "in", uniqueN(enf[ENF_ACTION_CATEGORY == "Formal"]$PWSID), "CWSs\n")
cat("Informal enforcement actions:", nrow(enf[ENF_ACTION_CATEGORY == "Informal"]),
    "in", uniqueN(enf[ENF_ACTION_CATEGORY == "Informal"]$PWSID), "CWSs\n")

enf_pm <- enf[, .(formal_enforcement   = as.integer(any(ENF_ACTION_CATEGORY == "Formal")),
                   informal_enforcement = as.integer(any(ENF_ACTION_CATEGORY == "Informal"))),
              by = .(PWSID, month_idx)]

rm(enf); gc()

# ── 3. Sanitary visit windows (SNSV/SNSP/SSVF) ────────────────────────────────
sv <- fread(file.path(SDWA_DIR, "SDWA_SITE_VISITS.csv"),
  select = c("PWSID", "VISIT_DATE", "VISIT_REASON_CODE"),
  colClasses = list(character = "PWSID"), na.strings = c("", "NA"), showProgress = FALSE)
sv <- sv[PWSID %in% sample_pwsids]
sv[, visit_dt := as.Date(VISIT_DATE, "%m/%d/%Y")]
sv <- sv[!is.na(visit_dt)]
sv[, yr := as.integer(format(visit_dt, "%Y"))]
sv <- sv[yr >= 1985 & yr <= 2005]
sv[, month_idx := month_idx_of(visit_dt)]

san <- sv[VISIT_REASON_CODE %in% c("SNSV", "SNSP", "SSVF")]
cat("Sanitary visits (SNSV/SNSP/SSVF):", nrow(san), "in", uniqueN(san$PWSID), "CWSs\n")
visits_dd <- unique(san[, .(PWSID, month_idx)])

before_long <- visits_dd[, .(month_idx = seq(month_idx - 6L, month_idx - 1L)),
                            by = .(PWSID, visit_month = month_idx)]
after_long  <- visits_dd[, .(month_idx = seq(month_idx + 1L, month_idx + 6L)),
                            by = .(PWSID, visit_month = month_idx)]

b_pm <- unique(before_long[month_idx >= 1L & month_idx <= n_months, .(PWSID, month_idx)])
a_pm <- unique(after_long[month_idx  >= 1L & month_idx <= n_months, .(PWSID, month_idx)])
b_pm[, san_before6 := 1L]
a_pm[, san_after6  := 1L]

san_pm <- merge(b_pm, a_pm, by = c("PWSID", "month_idx"), all = TRUE)
cat(sprintf("san_before6=1: %d  san_after6=1: %d\n",
            sum(san_pm$san_before6, na.rm = TRUE), sum(san_pm$san_after6, na.rm = TRUE)))

rm(sv, san); gc()

# ── 4. SYR2 contaminant concentration (% of MCL), running max ────────────────
syr2 <- as.data.table(arrow::read_parquet(
  file.path(ROOT, "clean_data/cws_6year_review_measurement_level_syr2.parquet"),
  col_select = c("PWSID", "sample_date", "ratio")))
syr2 <- syr2[PWSID %in% sample_pwsids & !is.na(ratio)]
syr2[, sample_dt := as.Date(sample_date)]
setorder(syr2, PWSID, sample_dt)
syr2[, cummax_ratio := cummax(ratio), by = PWSID]
syr2[, month_idx := month_idx_of(sample_dt)]
syr2_pm <- syr2[, .(cummax_ratio = cummax_ratio[.N]), by = .(PWSID, month_idx)]
setorder(syr2_pm, PWSID, month_idx)

has_syr2_pwsids <- unique(syr2_pm$PWSID)
cat("Downstream CWSs with >=1 SYR2 measurement:", length(has_syr2_pwsids), "\n")

syr2_skel <- CJ(PWSID = has_syr2_pwsids, month_idx = seq_len(n_months))
setkey(syr2_skel, PWSID, month_idx)
setkey(syr2_pm, PWSID, month_idx)
pct_mcl_dt <- syr2_pm[syr2_skel, roll = TRUE, on = .(PWSID, month_idx)]
setnames(pct_mcl_dt, "cummax_ratio", "pct_mcl_last_max")

rm(syr2); gc()

# ── 5. Build full CWS-month skeleton and merge ────────────────────────────────
skel <- CJ(PWSID = sample_pwsids, month_idx = seq_len(n_months))
skel <- merge(skel, enf_pm,                                by = c("PWSID", "month_idx"), all.x = TRUE)
skel <- merge(skel, onset_counts[, .(PWSID, month_idx, n_prior_violations)],
              by = c("PWSID", "month_idx"), all.x = TRUE)
skel <- merge(skel, san_pm,                                by = c("PWSID", "month_idx"), all.x = TRUE)
skel <- merge(skel, pct_mcl_dt[, .(PWSID, month_idx, pct_mcl_last_max)],
              by = c("PWSID", "month_idx"), all.x = TRUE)

setorder(skel, PWSID, month_idx)
skel[, n_prior_violations := nafill(n_prior_violations, type = "locf"), by = PWSID]

fill0_cols <- c("formal_enforcement", "informal_enforcement", "n_prior_violations",
                "san_before6", "san_after6")
for (cl in fill0_cols) skel[is.na(get(cl)), (cl) := 0L]
skel[, no_enforcement := as.integer(formal_enforcement == 0L & informal_enforcement == 0L)]
skel[, has_syr2 := PWSID %in% has_syr2_pwsids]

cat("\nFull CWS-month panel:", nrow(skel), "rows (", length(sample_pwsids),
    "CWSs x", n_months, "months)\n")
cat("formal_enforcement mean:  ", round(mean(skel$formal_enforcement), 4), "\n")
cat("informal_enforcement mean:", round(mean(skel$informal_enforcement), 4), "\n")
cat("no_enforcement mean:      ", round(mean(skel$no_enforcement), 4), "\n")

# ── 6. SYR2-restricted sample for the +controls/FE columns ───────────────────
syr2_lo <- month_idx_of(as.Date("1998-01-01"))
syr2_hi <- month_idx_of(as.Date("2005-12-01"))
spec_dt <- skel[has_syr2 == TRUE & month_idx >= syr2_lo & month_idx <= syr2_hi &
                !is.na(pct_mcl_last_max)]
cat("\nSYR2-restricted sample:", nrow(spec_dt), "CWS-months,",
    length(unique(spec_dt$PWSID)), "CWSs\n")

# ── 7. Regressions ─────────────────────────────────────────────────────────────
rhs_san      <- "san_before6 + san_after6"
rhs_controls <- "n_prior_violations + pct_mcl_last_max"
fe           <- "PWSID + month_idx"

run_spec_no_fe <- function(yvar, rhs, dt) {
  fml <- as.formula(paste0(yvar, " ~ ", rhs))
  feols(fml, data = dt, cluster = ~PWSID)
}
run_spec <- function(yvar, rhs, dt) {
  fml <- as.formula(paste0(yvar, " ~ ", rhs, " | ", fe))
  feols(fml, data = dt, cluster = ~PWSID)
}

m_formal_1   <- run_spec_no_fe("formal_enforcement",   rhs_san, skel)
m_formal_2   <- run_spec(      "formal_enforcement",   paste(rhs_san, rhs_controls, sep = " + "), spec_dt)
m_informal_1 <- run_spec_no_fe("informal_enforcement", rhs_san, skel)
m_informal_2 <- run_spec(      "informal_enforcement", paste(rhs_san, rhs_controls, sep = " + "), spec_dt)
m_none_1     <- run_spec_no_fe("no_enforcement",        rhs_san, skel)
m_none_2     <- run_spec(      "no_enforcement",        paste(rhs_san, rhs_controls, sep = " + "), spec_dt)

cat("\n--- Formal enforcement, no FE ---\n");                     print(summary(m_formal_1))
cat("\n--- Formal enforcement, +controls, SYR2-restricted ---\n"); print(summary(m_formal_2))
cat("\n--- Informal enforcement, no FE ---\n");                     print(summary(m_informal_1))
cat("\n--- Informal enforcement, +controls, SYR2-restricted ---\n"); print(summary(m_informal_2))
cat("\n--- No enforcement, no FE ---\n");                          print(summary(m_none_1))
cat("\n--- No enforcement, +controls, SYR2-restricted ---\n");     print(summary(m_none_2))

# ── 8. LaTeX table ─────────────────────────────────────────────────────────────
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

dir.create(file.path(ROOT, "output/reg"), showWarnings = FALSE, recursive = TRUE)

dict <- c(
  formal_enforcement   = "Formal enforcement action in month t",
  informal_enforcement = "Informal enforcement action in month t",
  no_enforcement        = "No enforcement action in month t",
  san_before6           = "Sanitary visit lead (1, 6) months",
  san_after6            = "Sanitary visit lag (-6, -1) months",
  n_prior_violations    = "N prior violations",
  pct_mcl_last_max      = "Last max conc. (\\% of MCL)",
  PWSID                 = "CWS",
  month_idx             = "Year-month"
)

out_tex <- file.path(ROOT, "output/reg/sanitary_visit_enforcement_type_iterative.tex")
note_main <- paste0(
  "Sample: strictly downstream CWSs (", length(sample_pwsids), "), CWS-months 1985-01 ",
  "to 2005-12 in columns (1), (3), (5). Outcomes: formal_enforcement = 1 if a formal ",
  "enforcement action (ENF\\_ACTION\\_CATEGORY = Formal) was taken against that CWS in ",
  "that calendar month; informal\\_enforcement = 1 if an informal action (ENF\\_ACTION\\_",
  "CATEGORY = Informal) was taken; no\\_enforcement = 1 if neither occurred. ",
  "san\\_before6 = 1 if the CWS-month falls in the 6 calendar months preceding a sanitary ",
  "visit (SNSV/SNSP/SSVF); san\\_after6 = 1 if it falls in the 6 months following one; ",
  "both are 0 outside any such window. N\\_prior\\_violations = cumulative count of prior ",
  "violation onsets (any category) at that CWS. Last max conc. (\\% of MCL) = running-max ",
  "SYR2 contaminant concentration as a share of the MCL. Columns (1), (3), (5) use the ",
  "full panel with no fixed effects, N=", nrow(skel), ". Columns (2), (4), (6) add the ",
  "prior-violation and concentration controls, include CWS and year-month fixed effects, ",
  "and are restricted to CWSs with >=1 SYR2 measurement and CWS-months within the SYR2 ",
  "window (1998-2005), N=", nrow(spec_dt), ". SEs clustered at the CWS (PWSID) level in ",
  "all columns."
)

do.call(etable, c(
  list(m_formal_1, m_formal_2, m_informal_1, m_informal_2, m_none_1, m_none_2),
  list(title     = "Sanitary Visit Timing and Enforcement Action Type",
       label     = "tab:sanitary_visit_enforcement_type_iterative",
       dict      = dict,
       headers   = list("Outcome" = c("Formal", "Formal", "Informal", "Informal",
                                       "None", "None")),
       notes     = note_main,
       fitstat   = ~n,
       style.tex = style.tex("aer", adjustbox = TRUE),
       tex       = TRUE,
       postprocess.tex = move_notes_below_adjustbox,
       file      = out_tex,
       replace   = TRUE)))

cat(sprintf("\nTable saved to: %s\n", out_tex))
if (file.exists(out_tex) && file.info(out_tex)$size > 0) {
  cat("Output verified: file exists and is non-zero.\n")
} else {
  stop("Output file missing or empty -- check etable() call.")
}
cat("=== DONE ===\n")
