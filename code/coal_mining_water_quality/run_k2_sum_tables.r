# ============================================================
# Script: run_k2_sum_tables.r
# Purpose: Summary-statistics tables for the k=2 A-full main-arm sample:
#          (1) two-panel MR/MCL violation incidence and days-in-year summary
#              for nitrates, arsenic, and inorganic chemicals (ports
#              violation_binary_days_panels.r);
#          (2) two-panel enforcement-type and visit-type summary across the
#              whole panel and MR-/MCL-violation-year subsets (ports
#              enforcement_visit_type_panels.r), restricted to the k2
#              reference 2SLS estimation sample by dropping FE-singleton
#              rows re-derived from the reference model's own
#              obs_selection (not a hardcoded row count).
#          Sources k2_common.r. Writes to output/sum/.
# Inputs:
#   clean_data/cws_data/step_instruments.parquet (via k2_common.r)
#   clean_data/cws_data/cws_covariates_steps.parquet (via k2_common.r)
#   clean_data/cws_data/sdwa_vio_agg_steps.parquet (via k2_common.r)
#   clean_data/cws_data/sdwa_visit_agg_k2.parquet (via k2_common.r)
#   clean_data/cws_data/sdwa_enf_agg_k2.parquet (via k2_common.r)
# Outputs:
#   output/sum/violation_binary_days_panels_k2.tex (+ _present.tex)
#   output/sum/enforcement_visit_type_panels_k2.tex (+ _present.tex)
# Author: EK  Date: 2026-09-14
# ============================================================

source("Z:/ek559/mining_wq/code/coal_mining_water_quality/k2_common.r")

main_dat <- build_k2_panel("main")

main_dat <- main_dat[order(main_dat$PWSID, main_dat$year), ]
prod_filled_k2 <- ifelse(is.na(main_dat$production_linked_sum), 0, main_dat$production_linked_sum)
main_dat$coal_prod_upstream_cumsum_10mst <- ave(prod_filled_k2, main_dat$PWSID, FUN = cumsum) / 1e7

N_obs   <- nrow(main_dat)
N_pws   <- length(unique(main_dat$PWSID))
N_years <- length(unique(main_dat$year))
cat(sprintf("k2 main-arm sample: %d obs, %d utilities, %d years\n", N_obs, N_pws, N_years))

# ── 1. violation_binary_days_panels_k2.tex ──────────────────────────────
p_at <- function(x, prob) quantile(x, probs = prob, na.rm = TRUE, names = FALSE)

contaminant_stats_k2 <- function(mr_bin, mcl_bin, mr_days, mcl_days) {
  list(
    mr_rate  = mean(main_dat[[mr_bin]],  na.rm = TRUE),
    mr_cnt   = sum(main_dat[[mr_bin]] == 100,  na.rm = TRUE),
    mcl_rate = mean(main_dat[[mcl_bin]], na.rm = TRUE),
    mcl_cnt  = sum(main_dat[[mcl_bin]] == 100, na.rm = TRUE),
    mr_mean  = mean(main_dat[[mr_days]], na.rm = TRUE),
    mr_sd    = sd(main_dat[[mr_days]],   na.rm = TRUE),
    mr_p90   = p_at(main_dat[[mr_days]], 0.90),
    mr_p99   = p_at(main_dat[[mr_days]], 0.99),
    mcl_mean = mean(main_dat[[mcl_days]], na.rm = TRUE),
    mcl_sd   = sd(main_dat[[mcl_days]],   na.rm = TRUE),
    mcl_p90  = p_at(main_dat[[mcl_days]], 0.90),
    mcl_p99  = p_at(main_dat[[mcl_days]], 0.99)
  )
}

stats_nitrate <- contaminant_stats_k2("nitrates_MR_bin",              "nitrates_MCL_bin",
                                       "nitrates_MR_share_days",       "nitrates_MCL_share_days")
stats_arsenic <- contaminant_stats_k2("arsenic_MR_bin",                "arsenic_MCL_bin",
                                       "arsenic_MR_share_days",        "arsenic_MCL_share_days")
stats_ioc     <- contaminant_stats_k2("inorganic_chemicals_MR_bin",    "inorganic_chemicals_MCL_bin",
                                       "inorganic_chemicals_MR_share_days", "inorganic_chemicals_MCL_share_days")

row_specs <- list(
  list(label = "Nitrates",            s = stats_nitrate),
  list(label = "Arsenic",             s = stats_arsenic),
  list(label = "Inorganic chemicals", s = stats_ioc)
)

# ── 1b. Panel C — Mining exposure covariates ────────────────────────────
panelc_stats <- function(var) {
  list(
    mean = mean(main_dat[[var]], na.rm = TRUE),
    sd   = sd(main_dat[[var]],   na.rm = TRUE),
    p90  = p_at(main_dat[[var]], 0.90),
    p99  = p_at(main_dat[[var]], 0.99)
  )
}

row_specs_c <- list(
  list(label = "Number of mines upstream",
       s = panelc_stats("num_coal_mines_linked_sum")),
  list(label = "Cumul. upstream coal prod. (10M ST) since 1985",
       s = panelc_stats("coal_prod_upstream_cumsum_10mst")),
  list(label = "Percentage of coal weight as sulfur",
       s = panelc_stats("sulfur_mean0"))
)

fn  <- function(x) format(as.integer(x), big.mark = ",")
fr  <- function(x) sprintf("%.2f", x)   # already 0-100 (percentage points)
fp2 <- function(x) sprintf("%.2f", x)

make_binary_row <- function(rs) {
  paste0(rs$label,
         " & ", fr(rs$s$mr_rate),  " & ", fn(rs$s$mr_cnt),
         " & ", fr(rs$s$mcl_rate), " & ", fn(rs$s$mcl_cnt),
         " \\\\")
}

# Fixed-width (not auto "l") row-label column: "Inorganic chemicals" (the
# capitalized display label, table-figure-formatting.md Rule 5) is wider
# than the original table's "IOCs" abbreviation, which was already within
# ~6pt of the text width -- an auto "l" column here overflows the page.
w_label_cm   <- 3.0
tabcolsep_cm <- 6 / 72.27 * 2.54
gap_cm       <- 2 * tabcolsep_cm
w_b_num <- 1.15
block_w <- 4 * w_b_num + 3 * gap_cm
w_a_num <- (block_w - gap_cm) / 2
w_b <- paste0(w_b_num, "cm")
w_a <- paste0(round(w_a_num, 2), "cm")
w_label <- paste0(w_label_cm, "cm")
col_a <- paste0(">{\\raggedright\\arraybackslash}p{", w_label, "} *{4}{>{\\centering\\arraybackslash}p{", w_a, "}}")
col_b <- paste0(">{\\raggedright\\arraybackslash}p{", w_label, "} *{8}{>{\\centering\\arraybackslash}p{", w_b, "}}")

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
  "\\hline",
  "\\end{tabular}"
)

# ── 1c. Panel C — Mining exposure covariates ────────────────────────────
make_panelc_row <- function(rs) {
  paste0(rs$label,
         " & ", fp2(rs$s$mean), " & ", fp2(rs$s$sd), " & ", fp2(rs$s$p90), " & ", fp2(rs$s$p99),
         " \\\\")
}

# Label column matches col_a/col_b's w_label (not a wider 6.5cm) so the
# Mean/SD/P90/P99 columns start at the same x-position as, and are the same
# width as, Panel B's MR supercolumn -- i.e. Panel C's Mean sits under
# Panel B's MR Mean, SD under SD, etc.
col_c <- paste0(">{\\raggedright\\arraybackslash}p{", w_label, "} *{4}{>{\\centering\\arraybackslash}p{", w_b, "}}")

panel_c_lines <- c(
  paste0("\\begin{tabular}{", col_c, "}"),
  "\\hline",
  "\\multicolumn{5}{l}{\\textbf{Panel C: Mining exposure covariates}} \\\\",
  "\\hline",
  paste0("\\textbf{Variable} & \\textbf{Mean} & \\textbf{SD} & \\textbf{P90} & \\textbf{P99} \\\\"),
  "\\hline",
  sapply(row_specs_c, make_panelc_row),
  "\\bottomrule",
  "\\end{tabular}"
)

combined_note <- paste0(
  "\\textit{Notes:} Sample of drinking water utilities with a coal mine within two ",
  "flow steps upstream of their intake and no coal mine colocated with their intake, ",
  "1985--2005. MR = monitoring and reporting violation; MCL = maximum contaminant ",
  "level violation. Panel A: \\% Non-zero is the share of utility-year observations ",
  "with a nonzero violation share for that category, in percent; Num. Violations is ",
  "the corresponding count of utility-year observations. Panel B: Mean, SD, P90, and ",
  "P99 describe the number of days in a year in violation. Panel C reports Mean, SD, ",
  "P90, and P99 for the number of coal mines upstream, cumulative coal production ",
  "upstream since 1985 (10 million short tons), and the percentage of coal weight ",
  "that is sulfur, for the same sample. Number of observations = ",
  "Number of utilities $\\times$ Number of years. ",
  "N\\,=\\,", fn(N_obs), " = ", fn(N_pws), " utilities $\\times$ up to ", fn(N_years),
  " years (1985--2005)."
)

table_lines_1 <- c(
  "\\begin{table}[htbp]",
  "\\raggedright",
  "\\caption{Coal Mining Exposed Utilities' Inorganic Chemical Water Violations, Two-Step Upstream Watershed Linkage, 1985--2005}",
  "\\label{tab:violation_binary_days_panels_k2}",
  "\\small",
  panel_a_lines,
  panel_b_lines,
  panel_c_lines,
  "\\begin{minipage}{\\linewidth}",
  "\\vspace{4pt}",
  "\\footnotesize",
  "\\raggedright",
  combined_note,
  "\\end{minipage}",
  "\\end{table}"
)

out_path_1 <- "Z:/ek559/mining_wq/output/sum/violation_binary_days_panels_k2.tex"
writeLines(table_lines_1, out_path_1)
cat("\nWritten:", out_path_1, "\n")

# Presentation companion: same table body, trailing notes minipage dropped
# entirely (summary statistics carry no clustering/FE/stars) --
# .claude/logs/2026-08-31-presentation-notes-tables.md.
table_lines_1_present <- c(
  "\\begin{table}[htbp]",
  "\\raggedright",
  "\\caption{Coal Mining Exposed Utilities' Inorganic Chemical Water Violations, Two-Step Upstream Watershed Linkage, 1985--2005}",
  "\\label{tab:violation_binary_days_panels_k2}",
  "\\small",
  panel_a_lines,
  panel_b_lines,
  panel_c_lines,
  "\\end{table}"
)
out_path_1_present <- sub("\\.tex$", "_present.tex", out_path_1)
writeLines(table_lines_1_present, out_path_1_present)
cat("Written:", out_path_1_present, "\n")

# ── 2. enforcement_visit_type_panels_k2.tex ─────────────────────────────
# Reference 2SLS sample: drop FE-singleton rows relative to
# inorganic_chemicals_MR_bin ~ num_facilities | PWSID + year, re-derived
# from the model's own obs_selection (not a hardcoded row count, since the
# k2 N differs from the original D1 anchor of 6,225).
dset2 <- main_dat
fs_check <- fixest::feols(
  inorganic_chemicals_MR_bin ~ num_facilities | PWSID + year,
  data = dset2, cluster = ~PWSID, warn = FALSE, notes = FALSE)
removed <- fs_check$obs_selection$obsRemoved
if (!is.null(removed)) {
  cat("Dropping", length(removed), "fixed-effect singleton rows to match reference 2SLS sample\n")
  dset2 <- dset2[-abs(removed), ]
}
N_obs2 <- nrow(dset2)
cat("k2 reference 2SLS sample obs:", N_obs2, "\n")

dset2$mr_year  <- with(dset2, nitrates_MR_bin  > 0 | arsenic_MR_bin  > 0 | inorganic_chemicals_MR_bin  > 0)
dset2$mcl_year <- with(dset2, nitrates_MCL_bin > 0 | arsenic_MCL_bin > 0 | inorganic_chemicals_MCL_bin > 0)
cat("MR-year subset N:",  sum(dset2$mr_year),  "\n")
cat("MCL-year subset N:", sum(dset2$mcl_year), "\n")

rate_cnt <- function(mask, v) {
  x <- dset2[[v]][mask]
  list(rate = mean(x) / 100, cnt = sum(x == 100))
}
row_stats <- function(v) {
  list(
    whole = rate_cnt(rep(TRUE, N_obs2), v),
    mr    = rate_cnt(dset2$mr_year,  v),
    mcl   = rate_cnt(dset2$mcl_year, v)
  )
}

panel_a_rows2 <- list(
  list(label = "Formal",   s = row_stats("any_formal")),
  list(label = "Informal", s = row_stats("any_informal")),
  list(label = "Any",      s = row_stats("any_enf"))
)
panel_b_rows2 <- list(
  list(label = "Sanitary",             s = row_stats("any_snsv")),
  list(label = "Technical assistance", s = row_stats("any_tech")),
  list(label = "Enforcement",          s = row_stats("any_enfvisit")),
  list(label = "Sample collection",    s = row_stats("any_smpl")),
  list(label = "Inspection",           s = row_stats("any_insp"))
)

fr2 <- function(x) {
  s          <- sprintf("%.2f", 100 * x)
  int_digits <- nchar(sub("\\..*", "", s))
  pad        <- paste(rep("\\phantom{0}", 3 - int_digits), collapse = "")
  paste0(pad, s)
}
make_row2 <- function(rs) {
  paste0(rs$label,
         " & ", fr2(rs$s$whole$rate), " & ", fn(rs$s$whole$cnt),
         " & ", fr2(rs$s$mr$rate),    " & ", fn(rs$s$mr$cnt),
         " & ", fr2(rs$s$mcl$rate),  " & ", fn(rs$s$mcl$cnt),
         " \\\\")
}

w_label <- 4.3
w_num   <- 1.55
col_spec2 <- paste0(">{\\raggedright\\arraybackslash}p{", w_label, "cm} ",
                     "*{6}{>{\\raggedleft\\arraybackslash}p{", w_num, "cm}}")
header_block2 <- c(
  " & \\multicolumn{2}{c}{\\textbf{Whole panel}} & \\multicolumn{2}{c}{\\textbf{During MR year}} & \\multicolumn{2}{c}{\\textbf{During MCL year}} \\\\",
  "\\cmidrule(lr){2-3}\\cmidrule(lr){4-5}\\cmidrule(lr){6-7}",
  " & \\textbf{\\%} & \\textbf{N} & \\textbf{\\%} & \\textbf{N} & \\textbf{\\%} & \\textbf{N} \\\\"
)

panel_a_lines2 <- c(
  paste0("\\begin{tabular}{", col_spec2, "}"),
  "\\toprule",
  header_block2,
  "\\multicolumn{7}{l}{\\textbf{Panel A: Enforcement type}} \\\\",
  sapply(panel_a_rows2, make_row2),
  "\\end{tabular}"
)
panel_b_lines2 <- c(
  paste0("\\begin{tabular}{", col_spec2, "}"),
  "\\hline",
  "\\multicolumn{7}{l}{\\textbf{Panel B: Visit type}} \\\\",
  sapply(panel_b_rows2, make_row2),
  "\\bottomrule",
  "\\end{tabular}"
)

n_mr_fmt2  <- fn(sum(dset2$mr_year))
n_mcl_fmt2 <- fn(sum(dset2$mcl_year))

combined_note2 <- paste0(
  "\\textit{Notes:} Sample of drinking water utilities with a coal mine within two ",
  "flow steps upstream of their intake and no coal mine colocated with their intake, ",
  "1985--2005. MR = monitoring and reporting violation; MCL = maximum contaminant ",
  "level violation. Whole panel columns report the share and count of utility-year ",
  "cells with a given enforcement action or site visit type, among all ", fn(N_obs2), " ",
  "cells. During MR year and During MCL year columns restrict to the ", n_mr_fmt2, " and ",
  n_mcl_fmt2, " cells, respectively, with a nitrate, arsenic, or inorganic chemical ",
  "violation of that category, before computing the same share and count. Panel A: ",
  "Formal and Informal enforcement follow the EPA SDWIS enforcement-action ",
  "classification; Any is a cell with an enforcement action of either category. ",
  "Panel B: Sanitary visits are sanitary surveys and follow-up sanitary surveys; ",
  "Technical assistance covers technical assistance, engineering, and operations and ",
  "maintenance visits; Enforcement visits are formal-enforcement, investigation, and ",
  "emergency site visits; Sample collection is a sample-collection visit; Inspection ",
  "covers site, regularly scheduled, and informal system inspections. An enforcement ",
  "action or visit type may co-occur with others in the same cell, so rows need not ",
  "sum to the Any/whole-panel total. Number of observations = ", fn(N_obs2), "."
)

table_lines_2 <- c(
  "\\begin{table}[htbp]",
  "\\raggedright",
  "\\caption{Enforcement Actions and Site Visits, Coal Mining Exposed Utilities, Two-Step Upstream Watershed Linkage, 1985--2005}",
  "\\label{tab:enforcement_visit_type_panels_k2}",
  "\\small",
  panel_a_lines2,
  panel_b_lines2,
  "\\begin{minipage}{\\linewidth}",
  "\\vspace{4pt}",
  "\\footnotesize",
  "\\raggedright",
  combined_note2,
  "\\end{minipage}",
  "\\end{table}"
)

out_path_2 <- "Z:/ek559/mining_wq/output/sum/enforcement_visit_type_panels_k2.tex"
writeLines(table_lines_2, out_path_2)
cat("Written:", out_path_2, "\n")

# Presentation companion: same table body, trailing notes minipage dropped
# entirely (summary statistics carry no clustering/FE/stars) --
# .claude/logs/2026-08-31-presentation-notes-tables.md.
table_lines_2_present <- c(
  "\\begin{table}[htbp]",
  "\\raggedright",
  "\\caption{Enforcement Actions and Site Visits, Coal Mining Exposed Utilities, Two-Step Upstream Watershed Linkage, 1985--2005}",
  "\\label{tab:enforcement_visit_type_panels_k2}",
  "\\small",
  panel_a_lines2,
  panel_b_lines2,
  "\\end{table}"
)
out_path_2_present <- sub("\\.tex$", "_present.tex", out_path_2)
writeLines(table_lines_2_present, out_path_2_present)
cat("Written:", out_path_2_present, "\n")

cat("\n=== run_k2_sum_tables.r DONE ===\n")
