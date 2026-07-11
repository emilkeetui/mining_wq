# ============================================================
# Script: sanitary_visit_mr_violation_iterative.r
# Purpose: CWS-month panel (strictly-downstream 2SLS sample, 1985-2005)
#          testing whether visit timing across five visit groups predicts
#          an MR violation onset. Binary before6/after6 window
#          indicators built for each visit group. Three cumulative LPM specs
#          on a single binary MR-violation outcome.
#          Spec 1: visit indicators only + FE (1985-2005)
#          Spec 2: + n_prior_violations + FE (1985-2005)
#          Spec 3: + n_prior_violations + pct_mcl_last_max + FE (SYR2-restricted sample)
#          Visit groups: sanitary (SNSV/SNSP/SSVF), technical assistance
#          (TECH/ENGR/OM), enforcement visits (FENF/INVG/EMRG), sample
#          collection (SMPL), inspection (SITE/RSCH/INFI).
# Inputs:  clean_data/cws_data/prod_vio_sulfur.parquet
#          clean_data/cws_6year_review_measurement_level_syr2.parquet
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_SITE_VISITS.csv
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.parquet
# Outputs: output/reg/sanitary_visit_mr_violation_iterative.tex
# Author: EK  Date: 2026-07-10
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

# ── 1. Violation onsets (any category + MR) ───────────────────────────────────
ve <- as.data.table(arrow::read_parquet(
  file.path(SDWA_DIR, "SDWA_VIOLATIONS_ENFORCEMENT.parquet"),
  col_select = c("PWSID", "VIOLATION_ID", "NON_COMPL_PER_BEGIN_DATE",
                 "VIOLATION_CATEGORY_CODE")))
ve <- ve[PWSID %in% sample_pwsids]

onsets <- unique(ve[, .(PWSID, VIOLATION_ID, NON_COMPL_PER_BEGIN_DATE, VIOLATION_CATEGORY_CODE)])
onsets[, onset_dt := as.Date(NON_COMPL_PER_BEGIN_DATE, "%m/%d/%Y")]
onsets <- onsets[!is.na(onset_dt)]
onsets[, onset_yr := as.integer(format(onset_dt, "%Y"))]
onsets <- onsets[onset_yr >= 1985 & onset_yr <= 2005]
onsets[, month_idx := month_idx_of(onset_dt)]
setorder(onsets, PWSID, onset_dt)

violation_pm <- onsets[, .(any_violation = 1L,
                            mr_violation  = as.integer(any(VIOLATION_CATEGORY_CODE == "MR"))),
                        by = .(PWSID, month_idx)]
cat("CWS-months with a violation onset:", nrow(violation_pm),
    "| MR onsets:", sum(violation_pm$mr_violation), "\n")

# n_prior_violations: cumulative count of onsets strictly before this month
onset_counts <- onsets[, .(n_onsets_this_month = .N), by = .(PWSID, month_idx)]
setorder(onset_counts, PWSID, month_idx)
onset_counts[, cum_after := cumsum(n_onsets_this_month), by = PWSID]
onset_counts[, n_prior_violations := cum_after - n_onsets_this_month]

rm(ve); gc()

# ── 2. Visit groups ───────────────────────────────────────────────────────────
# Five groups, each producing a before6/after6 window indicator.
visit_groups <- list(
  san  = c("SNSV", "SNSP", "SSVF"),
  tech = c("TECH", "ENGR", "OM"),
  enfv = c("FENF", "INVG", "EMRG"),
  smpl = c("SMPL"),
  insp = c("SITE", "RSCH", "INFI")
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

# Merge all groups into a single CWS-month visit table
visit_pm <- Reduce(function(a, b) merge(a, b, by = c("PWSID", "month_idx"), all = TRUE),
                    visit_pm_list)

rm(sv); gc()

# ── 3. SYR2 contaminant concentration (% of MCL), running max ────────────────
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

# ── 4. Build full CWS-month skeleton and merge ────────────────────────────────
skel <- CJ(PWSID = sample_pwsids, month_idx = seq_len(n_months))
skel <- merge(skel, violation_pm,                          by = c("PWSID", "month_idx"), all.x = TRUE)
skel <- merge(skel, onset_counts[, .(PWSID, month_idx, n_prior_violations)],
              by = c("PWSID", "month_idx"), all.x = TRUE)
skel <- merge(skel, visit_pm,                              by = c("PWSID", "month_idx"), all.x = TRUE)
skel <- merge(skel, pct_mcl_dt[, .(PWSID, month_idx, pct_mcl_last_max)],
              by = c("PWSID", "month_idx"), all.x = TRUE)

setorder(skel, PWSID, month_idx)
skel[, n_prior_violations := nafill(n_prior_violations, type = "locf"), by = PWSID]

visit_win_cols <- c("san_before6", "san_after6",
                     "tech_before6", "tech_after6",
                     "enfv_before6", "enfv_after6",
                     "smpl_before6", "smpl_after6",
                     "insp_before6", "insp_after6")
fill0_cols <- c("any_violation", "mr_violation", "n_prior_violations", visit_win_cols)
for (cl in fill0_cols) skel[is.na(get(cl)), (cl) := 0L]
skel[, has_syr2 := PWSID %in% has_syr2_pwsids]

cat("\nFull CWS-month panel:", nrow(skel), "rows (", length(sample_pwsids),
    "CWSs x", n_months, "months)\n")
cat("mr_violation mean:", round(mean(skel$mr_violation), 4), "\n")

# ── 5. SYR2-restricted sample for spec 3 ──────────────────────────────────────
syr2_lo <- month_idx_of(as.Date("1998-01-01"))
syr2_hi <- month_idx_of(as.Date("2005-12-01"))
spec3_dt <- skel[has_syr2 == TRUE & month_idx >= syr2_lo & month_idx <= syr2_hi &
                  !is.na(pct_mcl_last_max)]
cat("\nSpec-3 (SYR2-restricted) sample:", nrow(spec3_dt), "CWS-months,",
    length(unique(spec3_dt$PWSID)), "CWSs\n")

# ── 6. Regressions ─────────────────────────────────────────────────────────────
rhs_visits   <- paste(visit_win_cols, collapse = " + ")
rhs_controls <- "n_prior_violations"
fe           <- "PWSID + month_idx"

# Spec 1: visit indicators only, no FE (1985-2005)
rhs1 <- rhs_visits
# Spec 2: + controls + FE (1985-2005)
rhs2 <- paste(rhs_visits, rhs_controls, sep = " + ")
# Spec 3: + controls + pct_mcl_last_max + FE (SYR2 window)
rhs3 <- paste(rhs_visits, rhs_controls, "pct_mcl_last_max", sep = " + ")

run_spec_no_fe <- function(yvar, rhs, dt) {
  fml <- as.formula(paste0(yvar, " ~ ", rhs))
  feols(fml, data = dt, cluster = ~PWSID)
}
run_spec <- function(yvar, rhs, dt) {
  fml <- as.formula(paste0(yvar, " ~ ", rhs, " | ", fe))
  feols(fml, data = dt, cluster = ~PWSID)
}

m_mr_1 <- run_spec_no_fe("mr_violation", rhs1, skel)
m_mr_2 <- run_spec("mr_violation", rhs2, skel)
m_mr_3 <- run_spec("mr_violation", rhs3, spec3_dt)

cat("\n--- MR violation, spec 1 ---\n"); print(summary(m_mr_1))
cat("\n--- MR violation, spec 2 ---\n"); print(summary(m_mr_2))
cat("\n--- MR violation, spec 3 ---\n"); print(summary(m_mr_3))

# ── 7. LaTeX table ─────────────────────────────────────────────────────────────
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
  san_before6        = "Sanitary visit lead (1, 6) months",
  san_after6         = "Sanitary visit lag (-6, -1) months",
  tech_before6       = "Tech. assistance visit lead (1, 6) months",
  tech_after6        = "Tech. assistance visit lag (-6, -1) months",
  enfv_before6       = "Enforcement visit lead (1, 6) months",
  enfv_after6        = "Enforcement visit lag (-6, -1) months",
  smpl_before6       = "Sample collection visit lead (1, 6) months",
  smpl_after6        = "Sample collection visit lag (-6, -1) months",
  insp_before6       = "Inspection visit lead (1, 6) months",
  insp_after6        = "Inspection visit lag (-6, -1) months",
  n_prior_violations = "N prior violations",
  pct_mcl_last_max   = "Last max conc. (\\% of MCL)",
  PWSID              = "CWS"
)

out_tex <- file.path(ROOT, "output/reg/sanitary_visit_mr_violation_iterative.tex")
note_main <- paste0(
  "Sample: strictly downstream CWSs (", length(sample_pwsids), "), CWS-months 1985-01 ",
  "to 2005-12. Outcome = 1 if an MR violation onset occurs in that CWS-month. ",
  "For each visit group, before6 = 1 if the CWS-month falls in the 6 ",
  "calendar months preceding any visit of that type; after6 = 1 if it falls in the 6 months ",
  "following one; both are 0 outside any such window. Visit groups: sanitary visits ",
  "(SNSV/SNSP/SSVF); technical assistance (TECH/ENGR/OM); enforcement visits ",
  "(FENF/INVG/EMRG); sample collection (SMPL); inspection (SITE/RSCH/INFI). ",
  "N\\_prior\\_violations = cumulative count of prior violation onsets (any category) at that CWS. ",
  "Column (1): visit indicators only, no fixed effects, full panel N=", nrow(skel), ". ",
  "Column (2): + prior violation control, CWS and calendar-month fixed ",
  "effects, full panel N=", nrow(skel), ". ",
  "Column (3): + control and running-max contaminant concentration (\\% of MCL), ",
  "CWS and calendar-month fixed effects, restricted to CWSs with >=1 SYR2 measurement and ",
  "CWS-months within the SYR2 window (1998-2005), N=", nrow(spec3_dt), ". ",
  "SEs clustered at the CWS (PWSID) level in all columns."
)

do.call(etable, c(
  list(m_mr_1, m_mr_2, m_mr_3),
  list(title     = "Visit Group Timing and MR Violation Onset",
       label     = "tab:sanitary_visit_mr_violation_iterative",
       dict      = dict,
       headers   = list("Outcome" = c("MR violation", "MR violation", "MR violation")),
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
