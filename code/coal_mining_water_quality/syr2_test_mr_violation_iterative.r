# ============================================================
# Script: syr2_test_mr_violation_iterative.r
# Purpose: CWS-month panel (strictly-downstream 2SLS sample, 1997-2005)
#          testing whether the timing of SYR2 tests (arsenic, nitrate,
#          barium, selenium) predicts an IOC MR violation onset (nitrate/
#          arsenic/inorganic chemicals rules 331/332/333). Binary
#          before6/after6 window indicators built for SYR2 test months,
#          mirroring sanitary_visit_syr2_test_iterative.r but with the
#          roles of "visit" and "outcome" reversed: here the SYR2 test is
#          the leading/lagging event and the MR violation onset is the
#          outcome.
#          Col 1: SYR2 test windows only, no FE
#          Col 2: SYR2 test windows, CWS + calendar-month-of-year FE
# Inputs:  clean_data/cws_data/prod_vio_sulfur.parquet
#          clean_data/cws_6year_review_measurement_level_syr2.parquet
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.parquet
# Outputs: output/reg/syr2_test_mr_violation_iterative.tex
# Author: EK  Date: 2026-07-16
# ============================================================

.libPaths("Z:/ek559/RPackages")
library(arrow)
library(data.table)
library(fixest)

ROOT     <- "Z:/ek559/mining_wq"
SDWA_DIR <- "Z:/ek559/sdwa_violations/SDWA_latest_downloads"

# SYR2 chemicals used for the leading/lagging test-timing indicator.
TARGET_CHEMS <- c("arsenic", "barium", "nitrate", "selenium")

# IOC rule codes: nitrate (331), arsenic (332), inorganic chemicals (333).
IOC_RULES <- c(331L, 332L, 333L)

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

# ── 1. IOC MR violation onsets (nitrate/arsenic/inorganic chemicals) ─────────
ve <- as.data.table(arrow::read_parquet(
  file.path(SDWA_DIR, "SDWA_VIOLATIONS_ENFORCEMENT.parquet"),
  col_select = c("PWSID", "VIOLATION_ID", "NON_COMPL_PER_BEGIN_DATE",
                 "VIOLATION_CATEGORY_CODE", "RULE_CODE")))
ve <- ve[PWSID %in% sample_pwsids]
ve[, rule_tmp := suppressWarnings(as.integer(RULE_CODE))]

onsets <- unique(ve[VIOLATION_CATEGORY_CODE == "MR" & rule_tmp %in% IOC_RULES,
  .(PWSID, VIOLATION_ID, NON_COMPL_PER_BEGIN_DATE)])
onsets[, onset_dt := as.Date(NON_COMPL_PER_BEGIN_DATE, "%m/%d/%Y")]
onsets <- onsets[!is.na(onset_dt)]
onsets[, onset_yr := as.integer(format(onset_dt, "%Y"))]
onsets <- onsets[onset_yr >= 1997 & onset_yr <= 2005]
onsets[, month_idx := month_idx_of(onset_dt)]

mr_pm <- unique(onsets[, .(PWSID, month_idx)])
mr_pm[, mr_violation := 1L]
cat("CWS-months with an IOC MR violation onset (rules 331/332/333):", nrow(mr_pm), "\n")

rm(ve); gc()

# ── 2. SYR2 test-timing indicator (arsenic/nitrate/barium/selenium) ──────────
syr2 <- as.data.table(arrow::read_parquet(
  file.path(ROOT, "clean_data/cws_6year_review_measurement_level_syr2.parquet"),
  col_select = c("PWSID", "sample_date", "CHEMID_name")))
syr2 <- syr2[PWSID %in% sample_pwsids & !is.na(sample_date) & CHEMID_name %in% TARGET_CHEMS]
syr2[, sample_dt := as.Date(sample_date)]
syr2 <- syr2[!is.na(sample_dt)]
syr2[, yr := as.integer(format(sample_dt, "%Y"))]
syr2 <- syr2[yr >= 1985 & yr <= 2005]
syr2[, month_idx := month_idx_of(sample_dt)]

has_syr2_pwsids <- unique(syr2$PWSID)
cat("Downstream CWSs with >=1 SYR2 measurement (4-chem restriction):", length(has_syr2_pwsids), "\n")

n_months <- month_idx_of(as.Date("2005-12-01"))

tests_dd <- unique(syr2[, .(PWSID, month_idx)])
cat("SYR2 test months (4-chem restriction):", nrow(tests_dd), "\n")

before_long <- tests_dd[, .(month_idx = seq(month_idx - 6L, month_idx - 1L)),
                            by = .(PWSID, test_month = month_idx)]
after_long  <- tests_dd[, .(month_idx = seq(month_idx + 1L, month_idx + 6L)),
                            by = .(PWSID, test_month = month_idx)]

b_pm <- unique(before_long[month_idx >= 1L & month_idx <= n_months, .(PWSID, month_idx)])
a_pm <- unique(after_long[month_idx  >= 1L & month_idx <= n_months, .(PWSID, month_idx)])

b_pm[, syr2_before6 := 1L]
a_pm[, syr2_after6  := 1L]

test_pm <- merge(b_pm, a_pm, by = c("PWSID", "month_idx"), all = TRUE)
cat(sprintf("  before6=1: %d  after6=1: %d\n",
            sum(test_pm$syr2_before6, na.rm = TRUE),
            sum(test_pm$syr2_after6,  na.rm = TRUE)))

rm(syr2); gc()

# ── 3. Build CWS-month skeleton (1997-2005, SYR2-restricted sample) ──────────
skel_lo <- month_idx_of(as.Date("1997-01-01"))
skel_hi <- month_idx_of(as.Date("2005-12-01"))

skel <- CJ(PWSID = has_syr2_pwsids, month_idx = seq(skel_lo, skel_hi))
skel <- merge(skel, mr_pm,   by = c("PWSID", "month_idx"), all.x = TRUE)
skel <- merge(skel, test_pm, by = c("PWSID", "month_idx"), all.x = TRUE)

setorder(skel, PWSID, month_idx)

fill0_cols <- c("mr_violation", "syr2_before6", "syr2_after6")
for (cl in fill0_cols) skel[is.na(get(cl)), (cl) := 0L]

# Calendar-month-of-year FE (Jan-Dec), not the running month_idx -- controls
# for violation-reporting seasonality rather than absolute calendar time.
skel[, calendar_month := ((month_idx - 1L) %% 12L) + 1L]

cat("\nCWS-month panel:", nrow(skel), "rows (", length(has_syr2_pwsids),
    "CWSs x", skel_hi - skel_lo + 1L, "months)\n")
cat("mr_violation mean:", round(mean(skel$mr_violation), 4), "\n")

# ── 4. Regressions ─────────────────────────────────────────────────────────────
run_spec_no_fe <- function(yvar, rhs, dt) {
  fml <- as.formula(paste0(yvar, " ~ ", rhs))
  feols(fml, data = dt, cluster = ~PWSID)
}
run_spec <- function(yvar, rhs, dt) {
  fml <- as.formula(paste0(yvar, " ~ ", rhs, " | PWSID + calendar_month"))
  feols(fml, data = dt, cluster = ~PWSID)
}

m_1 <- run_spec_no_fe("mr_violation", "syr2_before6 + syr2_after6", skel)
m_2 <- run_spec(      "mr_violation", "syr2_before6 + syr2_after6", skel)

cat("\n--- MR violation, SYR2 test timing, no FE ---\n");        print(summary(m_1))
cat("\n--- MR violation, SYR2 test timing, CWS+month FE ---\n"); print(summary(m_2))

# ── 5. LaTeX table ─────────────────────────────────────────────────────────────
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
  mr_violation   = "IOC MR violation onset in month t",
  syr2_before6   = "SYR2 test lead (1, 6) months",
  syr2_after6    = "SYR2 test lag (-6, -1) months",
  PWSID          = "CWS",
  calendar_month = "Calendar month (Jan-Dec)"
)

out_tex <- file.path(ROOT, "output/reg/syr2_test_mr_violation_iterative.tex")
note_main <- paste0(
  "Sample: downstream CWSs with >=1 SYR2 measurement of arsenic, nitrate, barium, ",
  "or selenium (", length(has_syr2_pwsids),
  "), CWS-months 1997-01 to 2005-12. Outcome = 1 if an IOC MR violation (nitrate rule ",
  "331, arsenic rule 332, or inorganic chemicals rule 333) onset occurs in that CWS-",
  "month. before6 = 1 if the CWS-month falls in the 6 calendar months preceding any ",
  "SYR2 (Six-Year Review 2) test of arsenic, nitrate, barium, or selenium; after6 = 1 ",
  "if it falls in the 6 months following one; both are 0 outside any such window. ",
  "Column (2) includes CWS fixed effects and calendar-month-of-year fixed effects ",
  "(Jan-Dec, not absolute calendar time), which absorb seasonality in violation ",
  "reporting rather than the specific year-month. Column (1) has no fixed effects. ",
  "N=", nrow(skel), " in both columns. SEs clustered at the CWS (PWSID) level in ",
  "both columns."
)

do.call(etable, c(
  list(m_1, m_2),
  list(title     = "SYR2 Test Timing and IOC MR Violation Onset",
       label     = "tab:syr2_test_mr_violation_iterative",
       dict      = dict,
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
