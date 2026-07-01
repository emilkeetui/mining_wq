# ============================================================
# Script: sanitary_visit_event_study.r
# Purpose: Event study testing whether regulators deploy sanitary
#          visits preemptively (before suspected violations) or
#          reactively (after violation onset). Outcome = sanitary
#          visit occurrence in CWS-month; regressor = relative-month
#          dummies around each violation onset (strictly-downstream
#          2SLS sample, 1985-2005).
# Inputs:  clean_data/cws_data/prod_vio_sulfur.parquet
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.parquet
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_SITE_VISITS.csv
# Outputs: output/reg/sanitary_visit_event_study.tex
#          output/fig/es_sanitary_visit_onset.png
#          output/sum/sanitary_visit_onset_summary.tex
#          output/sum/visit_type_onset_summary.tex
# Author: EK  Date: 2026-06-30
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

# ── 1. Violation onsets (any category): dedupe on VIOLATION_ID ───────────────
ve <- as.data.table(arrow::read_parquet(
  file.path(SDWA_DIR, "SDWA_VIOLATIONS_ENFORCEMENT.parquet"),
  col_select = c("PWSID", "VIOLATION_ID", "NON_COMPL_PER_BEGIN_DATE")))
ve <- ve[PWSID %in% sample_pwsids]

onsets <- unique(ve[, .(PWSID, VIOLATION_ID, NON_COMPL_PER_BEGIN_DATE)])
onsets[, onset_dt := as.Date(NON_COMPL_PER_BEGIN_DATE, "%m/%d/%Y")]
onsets <- onsets[!is.na(onset_dt)]
onsets[, onset_yr := as.integer(format(onset_dt, "%Y"))]
onsets <- onsets[onset_yr >= 1985 & onset_yr <= 2005]
onsets[, onset_month_idx := month_idx_of(onset_dt)]
cat("Violation onsets in sample:", nrow(onsets), "\n")

rm(ve); gc()

# ── 2. Sanitary visit lookup (CWS-month indicator) ───────────────────────────
sv <- fread(file.path(SDWA_DIR, "SDWA_SITE_VISITS.csv"),
  select = c("PWSID", "VISIT_DATE", "VISIT_REASON_CODE"),
  colClasses = list(character = "PWSID"), na.strings = c("", "NA"), showProgress = FALSE)
sv <- sv[PWSID %in% sample_pwsids]
sv[, visit_dt := as.Date(VISIT_DATE, "%m/%d/%Y")]
sv <- sv[!is.na(visit_dt)]
sv[, yr := as.integer(format(visit_dt, "%Y"))]
sv <- sv[yr >= 1985 & yr <= 2005]

san_reasons <- c("SNSV", "SNSP", "SSVF")
sv_san <- sv[VISIT_REASON_CODE %in% san_reasons]
sv_san[, month_idx := month_idx_of(visit_dt)]
visit_lookup <- unique(sv_san[, .(PWSID, month_idx, has_visit = 1L)])
setkey(visit_lookup, PWSID, month_idx)
cat("CWS-months with >=1 sanitary visit:", nrow(visit_lookup), "\n")

rm(sv, sv_san); gc()

# ── 3. Stacked event panel scaffold ──────────────────────────────────────────
REL_WINDOW <- -6:6
scaffold <- onsets[, .(rel_month = REL_WINDOW), by = .(PWSID, VIOLATION_ID, onset_month_idx)]
scaffold[, month_idx := onset_month_idx + rel_month]
scaffold <- scaffold[month_idx >= 1 & month_idx <= n_months]
setkey(scaffold, PWSID, month_idx)

cat("\nStacked event scaffold:", nrow(scaffold), "rows (",
    length(unique(scaffold$VIOLATION_ID)), "onsets x", length(REL_WINDOW), "rel-months)\n")

# Sanitary panel kept for section 5 figure
event_panel <- visit_lookup[scaffold]
event_panel[is.na(has_visit), has_visit := 0L]
cat("Overall sanitary visit rate in window:", round(mean(event_panel$has_visit), 4), "\n")

# ── 3b. Load all visit types (shared by sections 4, 7, 8) ────────────────────
sv_all <- fread(file.path(SDWA_DIR, "SDWA_SITE_VISITS.csv"),
  select = c("PWSID", "VISIT_DATE", "VISIT_REASON_CODE"),
  colClasses = list(character = "PWSID"), na.strings = c("", "NA"), showProgress = FALSE)
sv_all <- sv_all[PWSID %in% sample_pwsids]
sv_all[, visit_dt := as.Date(VISIT_DATE, "%m/%d/%Y")]
sv_all <- sv_all[!is.na(visit_dt)]
sv_all[, yr := as.integer(format(visit_dt, "%Y"))]
sv_all <- sv_all[yr >= 1985 & yr <= 2005]
sv_all[, month_idx := month_idx_of(visit_dt)]
type_pm <- unique(sv_all[, .(PWSID, month_idx, VISIT_REASON_CODE)])
rm(sv_all); gc()

visit_group_codes <- list(
  "Sanitary visits"      = c("SNSV", "SSVF"),
  "Technical assistance" = c("TECH", "ENGR", "OM"),
  "Enforcement visits"   = c("FENF", "INVG", "EMRG"),
  "Sample collection"    = c("SMPL"),
  "Inspection"           = c("SITE", "RSCH", "INFI")
)

# ── 4. Event-study regressions (one per visit group) ─────────────────────────
# Reference period = month -1 (last full month before onset).
build_group_panel <- function(codes) {
  lookup <- unique(type_pm[VISIT_REASON_CODE %in% codes, .(PWSID, month_idx, has_visit = 1L)])
  setkey(lookup, PWSID, month_idx)
  pnl <- lookup[scaffold, on = .(PWSID, month_idx)]
  pnl[is.na(has_visit), has_visit := 0L]
  pnl
}

models <- lapply(visit_group_codes, function(codes) {
  pnl <- build_group_panel(codes)
  feols(has_visit ~ i(rel_month, ref = -1) | PWSID + month_idx, data = pnl, cluster = ~PWSID)
})

for (grp in names(models)) {
  cat(sprintf("\n--- %s (ref = month -1) ---\n", grp))
  print(summary(models[[grp]]))
}

# Alias for section 5 figure (sanitary group only)
m_event <- models[["Sanitary visits"]]

# ── 5. Coefficient plot ───────────────────────────────────────────────────────
dir.create(file.path(ROOT, "output/fig"), showWarnings = FALSE, recursive = TRUE)
out_fig <- file.path(ROOT, "output/fig/es_sanitary_visit_onset.png")

png(out_fig, width = 2000, height = 1400, res = 300)
iplot(m_event,
      xlab = "Months relative to violation onset",
      ylab = "P(sanitary visit)",
      main = "Sanitary Visit Timing Around Violation Onset")
abline(v = 0, lty = 2, col = "gray50")
dev.off()

cat(sprintf("Figure saved to: %s\n", out_fig))

# ── 6. LaTeX table ─────────────────────────────────────────────────────────────
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
out_tex <- file.path(ROOT, "output/reg/sanitary_visit_event_study.tex")

note_main <- paste0(
  "Sample: strictly downstream CWSs (", length(sample_pwsids), "), stacked event panel of ",
  length(unique(scaffold$VIOLATION_ID)), " violation onsets (any category) x 13 relative ",
  "months (-6 to +6), N=", nrow(scaffold), ". Outcome = 1 if any visit of that group occurred ",
  "at that CWS in that calendar month. Visit groups: sanitary visits (SNSV, SSVF), technical ",
  "assistance (TECH, ENGR, OM), enforcement visits (FENF, INVG, EMRG), sample collection ",
  "(SMPL), inspection (SITE, RSCH, INFI). Rel\\_month = calendar months relative to ",
  "NON\\_COMPL\\_PER\\_BEGIN\\_DATE of the onset (0 = onset month); reference period = month -1. ",
  "LPM with CWS and calendar-month fixed effects; SEs clustered at the CWS (PWSID) level. ",
  "Same CWS-month can appear in multiple onsets' windows (stacked design)."
)

star_sig <- function(p) {
  if (p < 0.01) return("$^{***}$")
  if (p < 0.05) return("$^{**}$")
  if (p < 0.10) return("$^{*}$")
  ""
}
rel_levels <- c(-6, -5, -4, -3, -2, 0, 1, 2, 3, 4, 5, 6)
coef_names <- paste0("rel_month::", rel_levels)
col_head   <- paste(rel_levels, collapse = " & ")

data_rows <- unlist(lapply(names(models), function(grp) {
  m     <- models[[grp]]
  coefs <- coef(m)[coef_names]
  ses   <- se(m)[coef_names]
  pvals <- pvalue(m)[coef_names]
  coef_row <- paste(sprintf("%.4f%s", coefs, vapply(pvals, star_sig, character(1))), collapse = " & ")
  se_row   <- paste(sprintf("(%.4f)", ses), collapse = " & ")
  c(paste0("         ", grp, " & ", coef_row, " \\\\"),
    paste0("          & ", se_row, " \\\\"))
}))

tab_body <- paste0(
  "\\begin{table}[htbp]\n",
  "   \\caption{\\label{tab:sanitary_visit_event_study} Visit Probability Around Violation Onset by Group (Event Study)}\n",
  "   \\bigskip\n",
  "   \\centering\n",
  "   \\begin{adjustbox}{width = \\textwidth, center}\n",
  "      \\begin{tabular}{l", paste(rep("c", length(rel_levels)), collapse = ""), "}\n",
  "         \\toprule\n",
  "         Visit group (ref. month $=-1$) & ", col_head, " \\\\\n",
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
  stop("Table file missing or empty -- check etable() call.")
}
if (file.exists(out_fig) && file.info(out_fig)$size > 0) {
  cat("Figure verified: file exists and is non-zero.\n")
} else {
  stop("Figure file missing or empty -- check png()/iplot() call.")
}

# ── 7. Group-level summary table ─────────────────────────────────────────────
# type_pm, scaffold, and visit_group_codes are all defined in sections 3b and 4.

# Descriptive labels and five-group taxonomy, identical to the mapping used in
# sanitary_visit_enforcement_lag.r (output/sum/visit_type_summary.tex), so the
# two visit-type tables stay consistent. Source: SDWA_REF_CODE_VALUES.csv
# (VALUE_TYPE == "VISIT_REASON_CODE").
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
visit_group_map <- c(
  SNSV = "Sanitary visits", SSVF = "Sanitary visits",
  TECH = "Technical assistance", ENGR = "Technical assistance", OM = "Technical assistance",
  FENF = "Enforcement visits", INVG = "Enforcement visits", EMRG = "Enforcement visits",
  SMPL = "Sample collection",
  SITE = "Inspection", RSCH = "Inspection", INFI = "Inspection"
)
group_order <- c("Sanitary visits", "Technical assistance", "Enforcement visits",
                  "Sample collection", "Inspection")

# ── 7. Group-level summary: one row per visit group ───────────────────────────
dir.create(file.path(ROOT, "output/sum"), showWarnings = FALSE, recursive = TRUE)
out_sum <- file.path(ROOT, "output/sum/sanitary_visit_onset_summary.tex")

group_stats <- rbindlist(lapply(names(visit_group_codes), function(grp) {
  codes      <- visit_group_codes[[grp]]
  lookup_grp <- unique(type_pm[VISIT_REASON_CODE %in% codes, .(PWSID, month_idx, has_visit = 1L)])
  setkey(lookup_grp, PWSID, month_idx)
  merged <- lookup_grp[scaffold, on = .(PWSID, month_idx)]
  merged[is.na(has_visit), has_visit := 0L]
  data.table(
    group             = grp,
    n_obs             = sum(merged$has_visit),
    unconditional_pct = 100 * mean(merged$has_visit),
    pre_window_pct    = 100 * mean(merged[rel_month %in% -6:-1, has_visit]),
    post_window_pct   = 100 * mean(merged[rel_month %in%  0:6,  has_visit])
  )
}))

rows_sum <- sprintf("%d & %s & %.2f & %.2f & %.2f \\\\",
                     group_stats$n_obs, group_stats$group,
                     group_stats$unconditional_pct, group_stats$pre_window_pct,
                     group_stats$post_window_pct)

notes_sum <- paste0(
  "Sample: strictly downstream CWSs (", length(sample_pwsids), "), stacked event panel of ",
  length(unique(event_panel$VIOLATION_ID)), " violation onsets (any category) x 13 relative ",
  "months (-6 to +6), N=", nrow(scaffold), " CWS-month observations. Visit groups: sanitary ",
  "visits (SNSV, SSVF), technical assistance (TECH, ENGR, OM), enforcement visits (FENF, ",
  "INVG, EMRG), sample collection (SMPL), inspection (SITE, RSCH, INFI). Column 1: count of ",
  "stacked CWS-month observations with a visit of that group. Column 3: share of all CWS-months ",
  "in the stacked panel with a visit of that group. Column 4: share of CWS-months in the ",
  "pre-onset window (rel\\_month -6 to -1) with a visit. Column 5: share of CWS-months in ",
  "the post-onset window (rel\\_month 0 to +6) with a visit; the +6 window includes the ",
  "contemporaneous onset month (rel\\_month = 0)."
)

lines_sum <- c(
  "\\begin{table}[htbp]",
  "\\caption{\\label{tab:sanitary_visit_onset_summary} Visit Probability Relative to Violation Onset, by Visit Group (Downstream CWSs, 1985--2005)}",
  "\\bigskip",
  "\\centering",
  "\\begin{adjustbox}{width = \\textwidth, center}",
  "\\begin{tabular}{llccc}",
  "\\toprule",
  "N & Visit group & Unconditional probability (\\%) & Pre-onset window, $-6$ (\\%) & Post-onset window, $+6$ (\\%) \\\\",
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
  cat("Group summary table verified: file exists and is non-zero.\n")
} else {
  stop("Group summary table file missing or empty -- check writeLines() call.")
}

# ── 8. Group-level breakdown → visit_type_onset_summary.tex ──────────────────
# Reuses group_stats computed in section 7 (same data, different output file).
rows_type <- sprintf("%d & %s & %.2f & %.2f & %.2f \\\\",
                      group_stats$n_obs, group_stats$group,
                      group_stats$unconditional_pct, group_stats$pre_window_pct,
                      group_stats$post_window_pct)

out_type <- file.path(ROOT, "output/sum/visit_type_onset_summary.tex")
notes_type <- paste0(
  "Sample: strictly downstream CWSs (", length(sample_pwsids), "), stacked event panel of ",
  length(unique(scaffold$VIOLATION_ID)), " violation onsets (any category) x 13 relative ",
  "months (-6 to +6), N=", nrow(scaffold), " CWS-month observations. Visit groups: sanitary ",
  "visits (SNSV, SSVF), technical assistance (TECH, ENGR, OM), enforcement visits (FENF, ",
  "INVG, EMRG), sample collection (SMPL), inspection (SITE, RSCH, INFI). Column 1: count of ",
  "stacked CWS-month observations with a visit of that group. Column 3: share of all ",
  "CWS-months in the stacked panel with a visit of that group. Column 4: share of CWS-months ",
  "in the pre-onset window (rel\\_month -6 to -1) with a visit. Column 5: share of CWS-months ",
  "in the post-onset window (rel\\_month 0 to +6) with a visit; the +6 window includes the ",
  "contemporaneous onset month (rel\\_month = 0)."
)

lines_type <- c(
  "\\begin{table}[htbp]",
  "\\caption{\\label{tab:visit_type_onset_summary} Site Visit Group Probability Relative to Violation Onset (Downstream CWSs, 1985--2005)}",
  "\\bigskip",
  "\\centering",
  "\\begin{adjustbox}{width = \\textwidth, center}",
  "\\begin{tabular}{llccc}",
  "\\toprule",
  "N & Visit group & Unconditional probability (\\%) & Pre-onset window, $-6$ (\\%) & Post-onset window, $+6$ (\\%) \\\\",
  "\\midrule",
  rows_type,
  "\\bottomrule",
  "\\end{tabular}",
  "\\end{adjustbox}",
  "{\\tiny\\linespread{1}\\selectfont \\par \\raggedright ",
  notes_type,
  "}",
  "\\end{table}"
)
writeLines(lines_type, out_type)
cat("Wrote:", out_type, "\n")

if (file.exists(out_type) && file.info(out_type)$size > 0) {
  cat("Visit-type summary table verified: file exists and is non-zero.\n")
} else {
  stop("Visit-type summary table file missing or empty -- check writeLines() call.")
}

cat("=== DONE ===\n")
