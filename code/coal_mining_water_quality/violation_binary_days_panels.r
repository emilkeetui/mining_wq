# ============================================================
# Script: violation_binary_days_panels.r
# Purpose: Two-panel summary table of MR and MCL violations for the
#          downstream 2SLS utility-year sample (minehuc_downstream_of_mine == 1
#          & minehuc_mine == 0, year 1985-2005, PWSID != "WV3303401") —
#          same filter as the "dwnstrm" sample_specs entry in didhet.r
#          (full_unbal). Panel A ("Any violation in year") reports the
#          share of utility-year obs with a nonzero violation share and the
#          count of such obs, for nitrates, arsenic, and IOCs. Panel B
#          ("Days in year") reports mean, SD, P90, and P99 of days in
#          violation for the same three contaminants. Both panels split
#          MR and MCL into separate multicolumns.
# Inputs:  clean_data/cws_data/prod_vio_sulfur.parquet
# Outputs: output/sum/violation_binary_days_panels.tex
# Author: EK  Date: 2026-08-29
# ============================================================

.libPaths(c("C:/Users/ek559/AppData/Local/R/win-library/4.6", "Z:/ek559/RPackages"))
library(arrow)

# ── 1. Load downstream 2SLS utility-year sample ──────────────────────────────────
share_vars <- c("nitrates_MR_share",            "nitrates_MCL_share",
                "arsenic_MR_share",             "arsenic_MCL_share",
                "inorganic_chemicals_MR_share", "inorganic_chemicals_MCL_share")

days_vars <- c("nitrates_MR_share_days",            "nitrates_MCL_share_days",
               "arsenic_MR_share_days",             "arsenic_MCL_share_days",
               "inorganic_chemicals_MR_share_days", "inorganic_chemicals_MCL_share_days")

dat <- as.data.frame(
  arrow::read_parquet(
    "Z:/ek559/mining_wq/clean_data/cws_data/prod_vio_sulfur.parquet",
    col_select = c("PWSID", "year", "minehuc_downstream_of_mine", "minehuc_mine",
                   share_vars, days_vars)))

dat <- dat[
  dat$year > 1984 & dat$year < 2006 &
  dat$PWSID != "WV3303401" &
  dat$minehuc_downstream_of_mine == 1 & dat$minehuc_mine == 0, ]

N_obs   <- nrow(dat)
N_pws   <- length(unique(dat$PWSID))
N_years <- length(unique(dat$year))
cat("Downstream 2SLS sample obs (1985-2005):", N_obs, "\n")
cat("Unique CWS:", N_pws, "\n")
cat("Unique years:", N_years, "\n")
cat("N / unique CWS:", N_obs / N_pws, "\n")

# ── 2. Incidence indicator = 1{share > 0} ─────────────────────────────────────
for (v in share_vars) {
  dat[[paste0(v, "_ind")]] <- as.integer(!is.na(dat[[v]]) & dat[[v]] > 0)
}

# ── 3. Per-contaminant binary and days-in-year statistics ───────────────────
p_at <- function(x, prob) quantile(x, probs = prob, na.rm = TRUE, names = FALSE)

contaminant_stats <- function(mr_share_ind, mcl_share_ind, mr_days, mcl_days) {
  list(
    mr_rate  = mean(dat[[mr_share_ind]],  na.rm = TRUE),
    mr_cnt   = sum(dat[[mr_share_ind]] == 1, na.rm = TRUE),
    mcl_rate = mean(dat[[mcl_share_ind]], na.rm = TRUE),
    mcl_cnt  = sum(dat[[mcl_share_ind]] == 1, na.rm = TRUE),
    mr_mean  = mean(dat[[mr_days]], na.rm = TRUE),
    mr_sd    = sd(dat[[mr_days]],   na.rm = TRUE),
    mr_p90   = p_at(dat[[mr_days]], 0.90),
    mr_p99   = p_at(dat[[mr_days]], 0.99),
    mcl_mean = mean(dat[[mcl_days]], na.rm = TRUE),
    mcl_sd   = sd(dat[[mcl_days]],   na.rm = TRUE),
    mcl_p90  = p_at(dat[[mcl_days]], 0.90),
    mcl_p99  = p_at(dat[[mcl_days]], 0.99)
  )
}

stats_nitrate <- contaminant_stats("nitrates_MR_share_ind",            "nitrates_MCL_share_ind",
                                    "nitrates_MR_share_days",           "nitrates_MCL_share_days")
stats_arsenic <- contaminant_stats("arsenic_MR_share_ind",              "arsenic_MCL_share_ind",
                                    "arsenic_MR_share_days",             "arsenic_MCL_share_days")
stats_ioc     <- contaminant_stats("inorganic_chemicals_MR_share_ind",  "inorganic_chemicals_MCL_share_ind",
                                    "inorganic_chemicals_MR_share_days", "inorganic_chemicals_MCL_share_days")

print(stats_nitrate)
print(stats_arsenic)
print(stats_ioc)

row_specs <- list(
  list(label = "Nitrates", s = stats_nitrate),
  list(label = "Arsenic",  s = stats_arsenic),
  list(label = "IOCs",     s = stats_ioc)
)

# ── 4. LaTeX helpers ──────────────────────────────────────────────────────────
fn  <- function(x) format(as.integer(x), big.mark = ",")
fr  <- function(x) sprintf("%.2f", 100 * x)
fp2 <- function(x) sprintf("%.2f", x)

# ── 5. Panel A — Any violation in year (Binary) ──────────────────────────────
make_binary_row <- function(rs) {
  paste0(rs$label,
         " & ", fr(rs$s$mr_rate),  " & ", fn(rs$s$mr_cnt),
         " & ", fr(rs$s$mcl_rate), " & ", fn(rs$s$mcl_cnt),
         " \\\\")
}

# Fixed, centered column widths so the MR and MCL blocks span the same
# horizontal extent in both panels. A block's rendered width is its
# columns' widths plus (n_cols - 1) inter-column gaps (each 2*\tabcolsep,
# 12pt by default) — Panel B's 4-column blocks have 2 more internal gaps
# than Panel A's 2-column blocks, so Panel A's column width is inflated
# by that gap difference (not simply doubled) to make both blocks land at
# the same total width.
tabcolsep_cm <- 6 / 72.27 * 2.54
gap_cm       <- 2 * tabcolsep_cm
w_b_num <- 1.3
block_w <- 4 * w_b_num + 3 * gap_cm
w_a_num <- (block_w - gap_cm) / 2
w_b <- paste0(w_b_num, "cm")
w_a <- paste0(round(w_a_num, 2), "cm")
col_a <- paste0("l *{4}{>{\\centering\\arraybackslash}p{", w_a, "}}")
col_b <- paste0("l *{8}{>{\\centering\\arraybackslash}p{", w_b, "}}")

panel_a_lines <- c(
  paste0("\\begin{tabular}{", col_a, "}"),
  "\\toprule",
  "\\multicolumn{5}{l}{\\textbf{Panel A: Any violation in year}} \\\\",
  " & \\multicolumn{2}{c}{\\textbf{MR}} & \\multicolumn{2}{c}{\\textbf{MCL}} \\\\",
  "\\cmidrule(lr){2-3}\\cmidrule(lr){4-5}",
  paste0("\\textbf{Contaminant} & \\textbf{\\%} & \\textbf{N} & ",
         "\\textbf{\\%} & \\textbf{N} \\\\"),
  "\\hline",
  sapply(row_specs, make_binary_row),
  "\\end{tabular}"
)

# ── 6. Panel B — Days in year ─────────────────────────────────────────────────
make_days_row <- function(rs) {
  paste0(rs$label,
         " & ", fp2(rs$s$mr_mean),  " & ", fp2(rs$s$mr_sd),  " & ", fp2(rs$s$mr_p90),  " & ", fp2(rs$s$mr_p99),
         " & ", fp2(rs$s$mcl_mean), " & ", fp2(rs$s$mcl_sd), " & ", fp2(rs$s$mcl_p90), " & ", fp2(rs$s$mcl_p99),
         " \\\\")
}

panel_b_lines <- c(
  paste0("\\begin{tabular}{", col_b, "}"),
  "\\hline",
  "\\multicolumn{9}{l}{\\textbf{Panel B: Days in year}} \\\\",
  " & \\multicolumn{4}{c}{\\textbf{MR}} & \\multicolumn{4}{c}{\\textbf{MCL}} \\\\",
  "\\cmidrule(lr){2-5}\\cmidrule(lr){6-9}",
  paste0("\\textbf{Contaminant} & \\textbf{Mean} & \\textbf{SD} & \\textbf{P90} & \\textbf{P99} & ",
         "\\textbf{Mean} & \\textbf{SD} & \\textbf{P90} & \\textbf{P99} \\\\"),
  "\\hline",
  sapply(row_specs, make_days_row),
  "\\bottomrule",
  "\\end{tabular}"
)

# ── 7. Assemble table ─────────────────────────────────────────────────────────
combined_note <- paste0(
  "\\textit{Notes:} Sample of drinking water utilities downstream of a coal mine between 1985--2005. ",
  "MR = monitoring and reporting violation; MCL = maximum contaminant level violation. ",
  "Panel A: \\% Non-zero is the share of utility-year observations with a nonzero violation share for ",
  "that category, in percent; Num. Violations is the corresponding count of utility-year observations. ",
  "Panel B: Mean, SD, P90, and P99 describe the number of days in a year in violation. ",
  "Number of observations = Number of utilities $\\times$ Number of years. ",
  "N\\,=\\,", fn(N_obs), " = ", fn(N_pws), " utilities $\\times$ up to ", fn(N_years),
  " years (1985--2005)."
)

table_lines <- c(
  "\\begin{table}[htbp]",
  "\\raggedright",
  "\\caption{Coal Mining Exposed Utilities' Inorganic Chemical Water Violations 1985--2005}",
  "\\label{tab:violation_binary_days_panels}",
  "\\small",
  panel_a_lines,
  panel_b_lines,
  "\\begin{minipage}{\\linewidth}",
  "\\vspace{4pt}",
  "\\footnotesize",
  "\\raggedright",
  combined_note,
  "\\end{minipage}",
  "\\end{table}"
)

header <- c(
  "% ============================================================",
  "% Table: Coal Mining Exposed Utilities' Inorganic Chemical Water Violations, 1985--2005",
  "% Purpose: Two-panel summary of MR and MCL violations for nitrates, arsenic, and IOCs —",
  "%          Panel A: Any Violation in Year (% non-zero, num. violations).",
  "%          Panel B: Days in Year (mean, SD, P90, P99).",
  "% Sample:  Downstream 2SLS utility-year sample (minehuc_downstream_of_mine=1, minehuc_mine=0,",
  "%          1985-2005, excluding PWSID WV3303401)",
  paste0("% N:       ", fn(N_obs), " utility-year observations across ", fn(N_pws), " unique utilities"),
  "% ============================================================"
)

out_path <- "Z:/ek559/mining_wq/output/sum/violation_binary_days_panels.tex"
writeLines(c(header, "", table_lines), out_path)
cat("\nOutput written to:", out_path, "\n")

# -- Presentation companion: same table body, notes block omitted entirely
# (summary statistics carry no clustering/FE/stars) -- see
# .claude/logs/2026-08-31-presentation-notes-tables.md.
table_lines_present <- c(
  "\\begin{table}[htbp]",
  "\\raggedright",
  "\\caption{Coal Mining Exposed Utilities' Inorganic Chemical Water Violations 1985--2005}",
  "\\label{tab:violation_binary_days_panels}",
  "\\small",
  panel_a_lines,
  panel_b_lines,
  "\\end{table}"
)
out_path_present <- sub("\\.tex$", "_present.tex", out_path)
writeLines(c(header, "", table_lines_present), out_path_present)
cat("Presentation output written to:", out_path_present, "\n")
cat("=== DONE ===\n")
