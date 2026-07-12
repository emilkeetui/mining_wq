# ============================================================
# Script: mr_reading_event_study.r
# Purpose: Event study testing whether CWSs submit SYR2 contaminant
#          readings preemptively/contemporaneously (trigger/exposure) or
#          reactively (diligence/return-to-compliance) around MR
#          (monitoring/reporting) violation onset. Outcome = any SYR2
#          reading in CWS-month; regressor = relative-month dummies
#          around each same-group MR violation onset (strictly-downstream
#          2SLS sample, 1998-2005). Mirrors sanitary_visit_event_study.r's
#          stacked event-study design.
# Inputs:  clean_data/cws_data/prod_vio_sulfur.parquet
#          clean_data/mr_concentration_lag_measurement.parquet
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.parquet
# Outputs: output/reg/mr_reading_event_study.tex
#          output/fig/es_reading_onset.png
#          output/sum/mr_reading_onset_summary.tex
# Author: EK  Date: 2026-07-03
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
year_of_month_idx <- function(mi) 1985L + (mi - 1L) %/% 12L

# SYR2 coverage window: readings only exist Jan 1998 - Dec 2005. Restrict onset
# dates so the full [-6,+6] relative-month window falls inside covered months;
# otherwise "no reading" near the sample edges would reflect left/right
# censoring of the source data rather than CWS behavior.
ONSET_MIN <- as.Date("1998-07-01")
ONSET_MAX <- as.Date("2005-06-30")

# ── 1. MR violation onsets, downstream PWSIDs, dedupe on VIOLATION_ID ────────
ve <- as.data.table(arrow::read_parquet(
  file.path(SDWA_DIR, "SDWA_VIOLATIONS_ENFORCEMENT.parquet"),
  col_select = c("PWSID", "VIOLATION_ID", "NON_COMPL_PER_BEGIN_DATE",
                 "VIOLATION_CATEGORY_CODE", "CONTAMINANT_CODE", "RULE_CODE")))
ve <- ve[PWSID %in% sample_pwsids & VIOLATION_CATEGORY_CODE == "MR"]

onsets_all <- unique(ve[, .(PWSID, VIOLATION_ID, NON_COMPL_PER_BEGIN_DATE, CONTAMINANT_CODE, RULE_CODE)])
onsets_all[, onset_dt := as.Date(NON_COMPL_PER_BEGIN_DATE, "%m/%d/%Y")]
onsets_all <- onsets_all[!is.na(onset_dt) & onset_dt >= ONSET_MIN & onset_dt <= ONSET_MAX]
onsets_all[, onset_month_idx := month_idx_of(onset_dt)]
cat("MR violation onset-rows (downstream, window-restricted to",
    format(ONSET_MIN, "%Y-%m"), "-", format(ONSET_MAX, "%Y-%m"), "):", nrow(onsets_all), "\n")

rm(ve); gc()

# ── 2. Chemical groupings: onset filter + reading chemical codes ─────────────
target_chem_codes <- c("1005", "1040", "1045", "1010", "1020")  # arsenic, nitrate, selenium, barium, chromium

chem_groups <- list(
  "Arsenic" = list(
    onsets = unique(onsets_all[CONTAMINANT_CODE == "1005", .(PWSID, VIOLATION_ID, onset_month_idx)]),
    codes  = "1005"),
  "Nitrate" = list(
    onsets = unique(onsets_all[CONTAMINANT_CODE == "1040", .(PWSID, VIOLATION_ID, onset_month_idx)]),
    codes  = "1040"),
  "Pooled IOC" = list(
    onsets = unique(onsets_all[RULE_CODE == 333, .(PWSID, VIOLATION_ID, onset_month_idx)]),
    codes  = c("1045", "1010", "1020")),
  "Any target chemical" = list(
    onsets = unique(onsets_all[CONTAMINANT_CODE %in% target_chem_codes | RULE_CODE == 333,
                                .(PWSID, VIOLATION_ID, onset_month_idx)]),
    codes  = target_chem_codes)
)

cat("\nOnsets per chemical group:\n")
for (grp in names(chem_groups)) {
  cat(sprintf("  %-22s onsets: %5d\n", grp, nrow(chem_groups[[grp]]$onsets)))
}

# ── 3. SYR2 reading dates (measurement-level, already downstream-only) ───────
meas <- as.data.table(arrow::read_parquet(
  file.path(ROOT, "clean_data/mr_concentration_lag_measurement.parquet"),
  col_select = c("PWSID", "contaminant_code", "sample_date")))
meas[, month_idx := month_idx_of(sample_date)]
cat("\nSYR2 measurement rows:", nrow(meas), "\n")

# ── 4. Stacked event panel + regression per chemical group ───────────────────
REL_WINDOW <- -6:6

build_scaffold <- function(onsets_grp) {
  scaffold <- onsets_grp[, .(rel_month = REL_WINDOW), by = .(PWSID, VIOLATION_ID, onset_month_idx)]
  scaffold[, month_idx := onset_month_idx + rel_month]
  scaffold
}

build_reading_panel <- function(onsets_grp, codes) {
  scaffold <- build_scaffold(onsets_grp)
  lookup <- unique(meas[contaminant_code %in% codes, .(PWSID, month_idx, has_reading = 1L)])
  setkey(lookup, PWSID, month_idx)
  pnl <- lookup[scaffold, on = .(PWSID, month_idx)]
  pnl[is.na(has_reading), has_reading := 0L]
  pnl[, cal_year := year_of_month_idx(month_idx)]
  pnl
}

panels <- lapply(chem_groups, function(g) build_reading_panel(g$onsets, g$codes))

# Calendar-YEAR fixed effects (not month_idx): with a stacked design and heavy
# onset repetition per CWS (multiple MR onsets per PWSID within the narrow
# SYR2-covered window), a full calendar-month FE makes many (PWSID, month_idx)
# cells appear identically across overlapping onset windows with different
# rel_month, leaving rel_month collinear with the FE (feols reported SEs in the
# thousands). Calendar-year FE is coarser and matches this project's usual
# convention (PWSID + YEAR, e.g. mr_concentration_lag.r) while still absorbing
# secular trends; rel_month dummies retain month-level resolution.
# Sparse onset groups (e.g. Arsenic) can still leave dummies collinear with the
# FE -- same underpowered-arsenic issue seen in mr_concentration_lag.r. Skip
# rather than halt.
fit_result <- lapply(panels, function(pnl) {
  tryCatch(
    feols(has_reading ~ i(rel_month, ref = -1) | PWSID + cal_year, data = pnl, cluster = ~PWSID),
    error = function(e) {
      cat("[SKIPPED] Model failed to fit:", conditionMessage(e), "\n")
      NULL
    }
  )
})
models <- Filter(Negate(is.null), fit_result)
skipped_groups <- setdiff(names(chem_groups), names(models))
if (length(skipped_groups) > 0) {
  cat("\n[NOTE] Groups excluded from table/figure (insufficient N for FE-saturated model):",
      paste(skipped_groups, collapse = ", "), "\n")
}

for (grp in names(models)) {
  cat(sprintf("\n--- %s (ref = month -1) ---\n", grp))
  print(summary(models[[grp]]))
}

m_event <- models[["Any target chemical"]]

# ── 5. Coefficient plot (primary group: Any target chemical) ─────────────────
dir.create(file.path(ROOT, "output/fig"), showWarnings = FALSE, recursive = TRUE)
out_fig <- file.path(ROOT, "output/fig/es_reading_onset.png")

png(out_fig, width = 2000, height = 1400, res = 300)
iplot(m_event,
      xlab = "Months relative to MR violation onset",
      ylab = "P(any SYR2 reading)",
      main = "SYR2 Reading Probability Around MR Violation Onset")
abline(v = 0, lty = 2, col = "gray50")
dev.off()

cat(sprintf("Figure saved to: %s\n", out_fig))

# ── 6. LaTeX coefficient table ────────────────────────────────────────────────
dir.create(file.path(ROOT, "output/reg"), showWarnings = FALSE, recursive = TRUE)
out_tex <- file.path(ROOT, "output/reg/mr_reading_event_study.tex")

note_main <- paste0(
  "Sample: strictly downstream CWSs (", length(sample_pwsids), "), stacked event panel of ",
  "same-group MR violation onsets x 13 relative months (-6 to +6). Outcome = 1 if any SYR2 ",
  "reading for that group's chemical(s) occurred at that CWS in that calendar month. Chemical ",
  "groups: Arsenic (contaminant 1005), Nitrate (1040), Pooled IOC (selenium 1045, barium 1010, ",
  "chromium 1020), Any target chemical (union of all five). Onsets restricted to ",
  format(ONSET_MIN, "%Y-%m"), "--", format(ONSET_MAX, "%Y-%m"),
  " so the full [-6,+6] window falls inside SYR2 coverage (1998-2005); this avoids left/right ",
  "censoring of reading data near the sample edges. Rel\\_month = calendar months relative to ",
  "NON\\_COMPL\\_PER\\_BEGIN\\_DATE of the MR violation onset (0 = onset month); reference period ",
  "= month -1. LPM with CWS and calendar-year fixed effects (year, not month, to avoid ",
  "collinearity from heavy onset-window overlap per CWS in the stacked design); SEs clustered ",
  "at the CWS (PWSID) level. Same CWS-month can appear in multiple onsets' windows (stacked design). ",
  "'--' indicates a rel\\_month dummy dropped by feols due to collinearity with the fixed ",
  "effects (occurs for the Arsenic column, N onsets = 23)."
)

star_sig <- function(p) {
  if (is.na(p)) return("")
  if (p < 0.01) return("$^{***}$")
  if (p < 0.05) return("$^{**}$")
  if (p < 0.10) return("$^{*}$")
  ""
}
rel_levels <- c(-6, -5, -4, -3, -2, 0, 1, 2, 3, 4, 5, 6)
coef_names <- paste0("rel_month::", rel_levels)
col_head   <- paste(rel_levels, collapse = " & ")

fmt_coef <- function(x, p) if (is.na(x)) "--" else sprintf("%.4f%s", x, star_sig(p))
fmt_se   <- function(x)    if (is.na(x)) ""   else sprintf("(%.4f)", x)

data_rows <- unlist(lapply(names(models), function(grp) {
  m     <- models[[grp]]
  coefs <- coef(m)[coef_names]
  ses   <- se(m)[coef_names]
  pvals <- pvalue(m)[coef_names]
  coef_row <- paste(mapply(fmt_coef, coefs, pvals), collapse = " & ")
  se_row   <- paste(vapply(ses, fmt_se, character(1)), collapse = " & ")
  n_onsets <- length(unique(panels[[grp]]$VIOLATION_ID))
  c(paste0("         ", grp, " (N onsets = ", n_onsets, ") & ", coef_row, " \\\\"),
    paste0("          & ", se_row, " \\\\"))
}))

tab_body <- paste0(
  "\\begin{table}[htbp]\n",
  "   \\caption{\\label{tab:mr_reading_event_study} SYR2 Reading Probability Around MR Violation Onset (Event Study)}\n",
  "   \\bigskip\n",
  "   \\centering\n",
  "   \\begin{adjustbox}{width = \\textwidth, center}\n",
  "      \\begin{tabular}{l", paste(rep("c", length(rel_levels)), collapse = ""), "}\n",
  "         \\toprule\n",
  "         Chemical group (ref. month $=-1$) & ", col_head, " \\\\\n",
  "         \\midrule\n",
  paste(data_rows, collapse = "\n"), "\n",
  "         \\bottomrule\n",
  "      \\end{tabular}\n",
  "   \\end{adjustbox}\n",
  "      {\\tiny\\linespread{1}\\selectfont \\par \\raggedright ", note_main, "}\n",
  "\\end{table}\n"
)
writeLines(tab_body, out_tex)

cat(sprintf("\nTable saved to: %s\n", out_tex))
if (file.exists(out_tex) && file.info(out_tex)$size > 0) {
  cat("Table verified: file exists and is non-zero.\n")
} else {
  stop("Table file missing or empty -- check writeLines() call.")
}
if (file.exists(out_fig) && file.info(out_fig)$size > 0) {
  cat("Figure verified: file exists and is non-zero.\n")
} else {
  stop("Figure file missing or empty -- check png()/iplot() call.")
}

# ── 7. Pre/post-onset window summary table ────────────────────────────────────
dir.create(file.path(ROOT, "output/sum"), showWarnings = FALSE, recursive = TRUE)
out_sum <- file.path(ROOT, "output/sum/mr_reading_onset_summary.tex")

group_stats <- rbindlist(lapply(names(chem_groups), function(grp) {
  pnl <- panels[[grp]]
  data.table(
    group             = grp,
    n_onsets          = length(unique(pnl$VIOLATION_ID)),
    n_obs             = sum(pnl$has_reading),
    unconditional_pct = 100 * mean(pnl$has_reading),
    pre_window_pct    = 100 * mean(pnl[rel_month %in% -6:-1, has_reading]),
    post_window_pct   = 100 * mean(pnl[rel_month %in%  0:6,  has_reading])
  )
}))

rows_sum <- sprintf("%d & %s & %.2f & %.2f & %.2f \\\\",
                     group_stats$n_onsets, group_stats$group,
                     group_stats$unconditional_pct, group_stats$pre_window_pct,
                     group_stats$post_window_pct)

notes_sum <- paste0(
  "Sample: strictly downstream CWSs (", length(sample_pwsids), "), stacked event panel of ",
  "same-group MR violation onsets, window-restricted to ", format(ONSET_MIN, "%Y-%m"), "--",
  format(ONSET_MAX, "%Y-%m"), " x 13 relative months (-6 to +6). Chemical groups: Arsenic ",
  "(contaminant 1005), Nitrate (1040), Pooled IOC (selenium 1045, barium 1010, chromium 1020), ",
  "Any target chemical (union of all five). Column 1: number of unique MR violation onsets in ",
  "that group. Column 4: share of CWS-months in the pre-onset window (rel\\_month -6 to -1) with ",
  "a same-group SYR2 reading. Column 5: share of CWS-months in the post-onset window (rel\\_month ",
  "0 to +6) with a reading; the +6 window includes the contemporaneous onset month (rel\\_month = 0)."
)

lines_sum <- c(
  "\\begin{table}[htbp]",
  "\\caption{\\label{tab:mr_reading_onset_summary} SYR2 Reading Probability Relative to MR Violation Onset, by Chemical Group (Downstream CWSs, 1998--2005)}",
  "\\bigskip",
  "\\centering",
  "\\begin{adjustbox}{width = \\textwidth, center}",
  "\\begin{tabular}{llccc}",
  "\\toprule",
  "N onsets & Chemical group & Unconditional probability (\\%) & Pre-onset window, $-6$ (\\%) & Post-onset window, $+6$ (\\%) \\\\",
  "\\midrule",
  rows_sum,
  "\\bottomrule",
  "\\end{tabular}",
  "\\end{adjustbox}",
  "{\\tiny\\linespread{1}\\selectfont \\par \\raggedright ",
  notes_sum,
  "}",
  "\\end{table}"
)
writeLines(lines_sum, out_sum)
cat("Wrote:", out_sum, "\n")

if (file.exists(out_sum) && file.info(out_sum)$size > 0) {
  cat("Summary table verified: file exists and is non-zero.\n")
} else {
  stop("Summary table file missing or empty -- check writeLines() call.")
}

cat("=== DONE ===\n")
