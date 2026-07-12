# ============================================================
# Script: sanitary_visit_syr2_test_iterative.r
# Purpose: CWS-month panel (strictly-downstream 2SLS sample, restricted to
#          CWSs with >=1 SYR2 measurement among arsenic/barium/chromium/
#          nitrate/selenium, 1998-2005) testing whether the timing of
#          sanitary visits and enforcement visits predicts whether a SYR2
#          test of one of those 5 chemicals occurred that month. Binary
#          before6/after6 window indicators built for each visit group.
#          Col 1: sanitary visit windows only, no FE
#          Col 2: sanitary visit windows, CWS + calendar-month-of-year FE
#          Col 3: enforcement visit windows only, no FE
#          Col 4: enforcement visit windows, CWS + calendar-month-of-year FE
#          Visit groups: sanitary (SNSV/SNSP/SSVF), enforcement (FENF/INVG/EMRG).
# Inputs:  clean_data/cws_data/prod_vio_sulfur.parquet
#          clean_data/cws_6year_review_measurement_level_syr2.parquet
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_SITE_VISITS.csv
# Outputs: output/reg/sanitary_visit_syr2_test_iterative.tex
# Author: EK  Date: 2026-07-11
# ============================================================

.libPaths("Z:/ek559/RPackages")
library(arrow)
library(data.table)
library(fixest)

ROOT     <- "Z:/ek559/mining_wq"
SDWA_DIR <- "Z:/ek559/sdwa_violations/SDWA_latest_downloads"

# SYR2 chemicals used for the test-occurrence outcome.
TARGET_CHEMS <- c("arsenic", "barium", "chromium", "nitrate", "selenium")

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

# ── 1. SYR2 test-occurrence outcome (arsenic/barium/chromium/nitrate/selenium) ─
syr2 <- as.data.table(arrow::read_parquet(
  file.path(ROOT, "clean_data/cws_6year_review_measurement_level_syr2.parquet"),
  col_select = c("PWSID", "sample_date", "CHEMID_name")))
syr2 <- syr2[PWSID %in% sample_pwsids & !is.na(sample_date) & CHEMID_name %in% TARGET_CHEMS]
syr2[, sample_dt := as.Date(sample_date)]
syr2 <- syr2[!is.na(sample_dt)]
syr2[, month_idx := month_idx_of(sample_dt)]

has_syr2_pwsids <- unique(syr2$PWSID)
cat("Downstream CWSs with >=1 SYR2 measurement (5-chem restriction):", length(has_syr2_pwsids), "\n")

test_pm <- unique(syr2[, .(PWSID, month_idx)])
test_pm[, test_occurred := 1L]
cat("CWS-months with >=1 SYR2 test (5-chem restriction):", nrow(test_pm), "\n")

rm(syr2); gc()

# ── 2. Visit groups: sanitary and enforcement ─────────────────────────────────
visit_groups <- list(
  san  = c("SNSV", "SNSP", "SSVF"),
  enfv = c("FENF", "INVG", "EMRG")
)

sv <- fread(file.path(SDWA_DIR, "SDWA_SITE_VISITS.csv"),
  select = c("PWSID", "VISIT_DATE", "VISIT_REASON_CODE"),
  colClasses = list(character = "PWSID"), na.strings = c("", "NA"), showProgress = FALSE)
sv <- sv[PWSID %in% sample_pwsids]
sv[, visit_dt := as.Date(VISIT_DATE, "%m/%d/%Y")]
sv <- sv[!is.na(visit_dt)]
sv[, yr := as.integer(format(visit_dt, "%Y"))]
sv <- sv[yr >= 1985 & yr <= 2005]
sv[, month_idx := month_idx_of(visit_dt)]

# For each group: deduplicate visit months, expand into ±6 month windows.
build_visit_windows <- function(codes, prefix) {
  grp <- sv[VISIT_REASON_CODE %in% codes]
  cat(sprintf("  Group %-4s: %d visits, %d CWSs\n",
              prefix, nrow(grp), uniqueN(grp$PWSID)))
  visits_dd <- unique(grp[, .(PWSID, month_idx)])

  before_long <- visits_dd[, .(month_idx = seq(month_idx - 6L, month_idx - 1L)),
                              by = .(PWSID, visit_month = month_idx)]
  after_long  <- visits_dd[, .(month_idx = seq(month_idx + 1L, month_idx + 6L)),
                              by = .(PWSID, visit_month = month_idx)]

  b_pm <- unique(before_long[month_idx >= 1L & month_idx <= n_months, .(PWSID, month_idx)])
  a_pm <- unique(after_long[month_idx  >= 1L & month_idx <= n_months, .(PWSID, month_idx)])

  b_pm[[paste0(prefix, "_before6")]] <- 1L
  a_pm[[paste0(prefix, "_after6")]]  <- 1L

  m <- merge(b_pm, a_pm, by = c("PWSID", "month_idx"), all = TRUE)
  cat(sprintf("    before6=1: %d  after6=1: %d\n",
              sum(m[[paste0(prefix, "_before6")]], na.rm = TRUE),
              sum(m[[paste0(prefix, "_after6")]],  na.rm = TRUE)))
  m
}

cat("Building visit-window indicators:\n")
visit_pm_list <- lapply(names(visit_groups),
                         function(g) build_visit_windows(visit_groups[[g]], g))

# Merge sanitary and enforcement groups into a single CWS-month visit table
visit_pm <- Reduce(function(a, b) merge(a, b, by = c("PWSID", "month_idx"), all = TRUE),
                    visit_pm_list)

rm(sv); gc()

# ── 3. Build SYR2-window CWS-month skeleton and merge ─────────────────────────
syr2_lo <- month_idx_of(as.Date("1998-01-01"))
syr2_hi <- month_idx_of(as.Date("2005-12-01"))

skel <- CJ(PWSID = has_syr2_pwsids, month_idx = seq(syr2_lo, syr2_hi))
skel <- merge(skel, test_pm,  by = c("PWSID", "month_idx"), all.x = TRUE)
skel <- merge(skel, visit_pm, by = c("PWSID", "month_idx"), all.x = TRUE)

setorder(skel, PWSID, month_idx)

visit_win_cols <- c("san_before6", "san_after6", "enfv_before6", "enfv_after6")
fill0_cols <- c("test_occurred", visit_win_cols)
for (cl in fill0_cols) skel[is.na(get(cl)), (cl) := 0L]

# Calendar-month-of-year FE (Jan-Dec), not the running month_idx -- controls
# for testing seasonality rather than absolute calendar time.
skel[, calendar_month := ((month_idx - 1L) %% 12L) + 1L]

cat("\nSYR2-window CWS-month panel:", nrow(skel), "rows (", length(has_syr2_pwsids),
    "CWSs x", syr2_hi - syr2_lo + 1L, "months)\n")
cat("test_occurred mean:", round(mean(skel$test_occurred), 4), "\n")

# ── 4. Regressions ─────────────────────────────────────────────────────────────
run_spec_no_fe <- function(yvar, rhs, dt) {
  fml <- as.formula(paste0(yvar, " ~ ", rhs))
  feols(fml, data = dt, cluster = ~PWSID)
}
run_spec <- function(yvar, rhs, dt) {
  fml <- as.formula(paste0(yvar, " ~ ", rhs, " | PWSID + calendar_month"))
  feols(fml, data = dt, cluster = ~PWSID)
}

m_san_1  <- run_spec_no_fe("test_occurred", "san_before6 + san_after6",   skel)
m_san_2  <- run_spec(      "test_occurred", "san_before6 + san_after6",   skel)
m_enfv_1 <- run_spec_no_fe("test_occurred", "enfv_before6 + enfv_after6", skel)
m_enfv_2 <- run_spec(      "test_occurred", "enfv_before6 + enfv_after6", skel)

cat("\n--- SYR2 test occurred, sanitary, no FE ---\n");        print(summary(m_san_1))
cat("\n--- SYR2 test occurred, sanitary, CWS+month FE ---\n"); print(summary(m_san_2))
cat("\n--- SYR2 test occurred, enforcement, no FE ---\n");        print(summary(m_enfv_1))
cat("\n--- SYR2 test occurred, enforcement, CWS+month FE ---\n"); print(summary(m_enfv_2))

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
  test_occurred  = "SYR2 test occurred in month t",
  san_before6    = "Sanitary visit lead (1, 6) months",
  san_after6     = "Sanitary visit lag (-6, -1) months",
  enfv_before6   = "Enforcement visit lead (1, 6) months",
  enfv_after6    = "Enforcement visit lag (-6, -1) months",
  PWSID          = "CWS",
  calendar_month = "Calendar month (Jan-Dec)"
)

out_tex <- file.path(ROOT, "output/reg/sanitary_visit_syr2_test_iterative.tex")
note_main <- paste0(
  "Sample: downstream CWSs with >=1 SYR2 measurement of arsenic, barium, chromium, ",
  "nitrate, or selenium (", length(has_syr2_pwsids),
  "), CWS-months 1998-01 to 2005-12. Outcome = 1 if >=1 SYR2 (Six-Year Review 2) ",
  "measurement of one of those 5 chemicals was recorded for that CWS in that ",
  "calendar month. ",
  "before6 = 1 if the CWS-month falls in the 6 calendar months preceding any ",
  "visit of that type; after6 = 1 if it falls in the 6 months following one; ",
  "both are 0 outside any such window. Sanitary visits = SNSV/SNSP/SSVF; ",
  "enforcement visits = FENF/INVG/EMRG. Columns (2) and (4) include CWS fixed ",
  "effects and calendar-month-of-year fixed effects (Jan-Dec, not absolute ",
  "calendar time), which absorb seasonality in SYR2 testing rather than the ",
  "specific year-month. Columns (1) and (3) have no fixed effects. N=", nrow(skel),
  " in all columns. SEs clustered at the CWS (PWSID) level in all columns."
)

do.call(etable, c(
  list(m_san_1, m_san_2, m_enfv_1, m_enfv_2),
  list(title     = "Sanitary and Enforcement Visit Timing and SYR2 Test Occurrence",
       label     = "tab:sanitary_visit_syr2_test_iterative",
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
