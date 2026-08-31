# ============================================================
# Script: enforcement_visit_type_panels.r
# Purpose: Two-panel summary table of enforcement actions and site visits over
#          the main 2SLS downstream utility-year sample (minehuc_downstream_of_mine==1
#          & minehuc_mine==0, year 1985-2005, PWSID != "WV3303401", minus the
#          fixed-effect singleton rows dropped by the reference 2SLS spec —
#          6,225 obs). Panel A ("Enforcement type") reports the share and count
#          of utility-year cells with a Formal, Informal, or Any enforcement
#          action. Panel B ("Visit type") reports the same for Sanitary,
#          Technical assistance, Enforcement, Sample collection, and
#          Inspection site visits. Both panels split into three sub-samples:
#          the whole panel, cells with an MR violation (nitrates, arsenic, or
#          inorganic chemicals), and cells with an MCL violation (same three).
# Inputs:  clean_data/cws_data/prod_vio_sulfur.parquet
#          clean_data/cws_data/sdwa_enf_agg_d12.parquet
#          clean_data/cws_data/sdwa_visit_agg_d12.parquet
# Outputs: output/sum/enforcement_visit_type_panels.tex
# Author: EK  Date: 2026-08-30
# ============================================================

.libPaths(c("C:/Users/ek559/AppData/Local/R/win-library/4.6", "Z:/ek559/RPackages"))
library(arrow)
library(fixest)

# ── 1. Load downstream 2SLS utility-year sample ──────────────────────────────
share_vars <- c("nitrates_MR_share_days",            "nitrates_MCL_share_days",
                "arsenic_MR_share_days",             "arsenic_MCL_share_days",
                "inorganic_chemicals_MR_share_days", "inorganic_chemicals_MCL_share_days")

full <- as.data.frame(
  arrow::read_parquet(
    "Z:/ek559/mining_wq/clean_data/cws_data/prod_vio_sulfur.parquet",
    col_select = c("PWSID", "year", "minehuc_downstream_of_mine", "minehuc_mine",
                   "num_facilities", "sulfur_unified_sum", "post95",
                   "num_coal_mines_upstream_sum", share_vars)))

full <- full[full$year > 1984 & full$year < 2006 & full$PWSID != "WV3303401", ]
dset <- full[full$minehuc_downstream_of_mine == 1 & full$minehuc_mine == 0, ]
cat("Raw downstream 2SLS sample obs (1985-2005):", nrow(dset), "\n")

# ── 2. Drop fixed-effect singleton rows to match the reference 2SLS sample ──
# Reproduces the exact estimation sample of 2sls_dwnstrm_minevio_mr_ivsum_binvio
# (N=6,225) rather than hardcoding row indices, so this stays correct if the
# upstream panel changes.
dset$inorganic_chemicals_MR_bin <- as.integer(dset$inorganic_chemicals_MR_share_days > 0) * 100L
fs_check <- fixest::feols(
  inorganic_chemicals_MR_bin ~ num_facilities | PWSID + year,
  data = dset, cluster = ~PWSID)
removed <- fs_check$obs_selection$obsRemoved
if (!is.null(removed)) {
  cat("Dropping", length(removed), "fixed-effect singleton rows to match reference 2SLS sample\n")
  dset <- dset[-abs(removed), ]
}
dset$inorganic_chemicals_MR_bin <- NULL
N_obs <- nrow(dset)
cat("Main 2SLS sample obs:", N_obs, "\n")
stopifnot(N_obs == 6225)

# ── 3. MR / MCL year subset flags (union of nitrates, arsenic, IOC) ─────────
dset$mr_year  <- with(dset, nitrates_MR_share_days  > 0 | arsenic_MR_share_days  > 0 |
                             inorganic_chemicals_MR_share_days  > 0)
dset$mcl_year <- with(dset, nitrates_MCL_share_days > 0 | arsenic_MCL_share_days > 0 |
                             inorganic_chemicals_MCL_share_days > 0)
cat("MR-year subset N:",  sum(dset$mr_year),  "\n")
cat("MCL-year subset N:", sum(dset$mcl_year), "\n")

# ── 4. Merge cached enforcement / visit aggregates ───────────────────────────
enf_agg <- as.data.frame(arrow::read_parquet(
  "Z:/ek559/mining_wq/clean_data/cws_data/sdwa_enf_agg_d12.parquet",
  col_select = c("PWSID", "year", "any_enf", "any_informal", "any_formal")))
vis_agg <- as.data.frame(arrow::read_parquet(
  "Z:/ek559/mining_wq/clean_data/cws_data/sdwa_visit_agg_d12.parquet",
  col_select = c("PWSID", "year", "any_snsv", "any_tech", "any_enfvisit", "any_smpl", "any_insp")))

dset <- merge(dset, enf_agg, by = c("PWSID", "year"), all.x = TRUE)
dset <- merge(dset, vis_agg, by = c("PWSID", "year"), all.x = TRUE)

enf_cols <- c("any_enf", "any_informal", "any_formal")
vis_cols <- c("any_snsv", "any_tech", "any_enfvisit", "any_smpl", "any_insp")
for (v in c(enf_cols, vis_cols)) {
  dset[[v]][is.na(dset[[v]])] <- FALSE
  dset[[v]] <- as.integer(dset[[v]])
}
stopifnot(nrow(dset) == N_obs)

# ── 5. Rate/count helper across the three sub-samples ────────────────────────
rate_cnt <- function(mask, v) {
  x <- dset[[v]][mask]
  list(rate = mean(x), cnt = sum(x == 1))
}

row_stats <- function(v) {
  list(
    whole = rate_cnt(rep(TRUE, N_obs), v),
    mr    = rate_cnt(dset$mr_year,  v),
    mcl   = rate_cnt(dset$mcl_year, v)
  )
}

panel_a_rows <- list(
  list(label = "Formal",   s = row_stats("any_formal")),
  list(label = "Informal", s = row_stats("any_informal")),
  list(label = "Any",      s = row_stats("any_enf"))
)

panel_b_rows <- list(
  list(label = "Sanitary",               s = row_stats("any_snsv")),
  list(label = "Technical assistance",   s = row_stats("any_tech")),
  list(label = "Enforcement",            s = row_stats("any_enfvisit")),
  list(label = "Sample collection",      s = row_stats("any_smpl")),
  list(label = "Inspection",             s = row_stats("any_insp"))
)

# ── 6. LaTeX helpers ──────────────────────────────────────────────────────────
fn <- function(x) format(as.integer(x), big.mark = ",")
# Right-justified within a fixed-width column is not enough on its own to
# align the decimal point across rows when the integer part has a varying
# number of digits (e.g. "3.50" vs "67.63") — pad the shorter integer parts
# with a digit-width \phantom{0} so every value's decimal point falls at the
# same horizontal position, the same trick used for the regression tables'
# >{\raggedleft\arraybackslash} columns.
fr <- function(x) {
  s        <- sprintf("%.2f", 100 * x)
  int_digits <- nchar(sub("\\..*", "", s))
  pad      <- paste(rep("\\phantom{0}", 3 - int_digits), collapse = "")
  paste0(pad, s)
}

make_row <- function(rs) {
  paste0(rs$label,
         " & ", fr(rs$s$whole$rate), " & ", fn(rs$s$whole$cnt),
         " & ", fr(rs$s$mr$rate),    " & ", fn(rs$s$mr$cnt),
         " & ", fr(rs$s$mcl$rate),  " & ", fn(rs$s$mcl$cnt),
         " \\\\")
}

# Fixed-width label column (rather than auto-fit "l") so Panel A and Panel B's
# six numeric columns line up vertically despite the two tabulars sizing
# their first column independently — "Technical assistance" (Panel B) is
# much wider than "Formal"/"Informal"/"Any" (Panel A), so a shared p{} width
# is required for both blocks to render at the same total table width.
# Numeric columns are right-justified (matching the regression tables'
# >{\raggedleft\arraybackslash} convention) so the phantom-padded decimals
# in fr() actually line up.
w_label <- 4.3
w_num   <- 1.55
col_spec <- paste0(">{\\raggedright\\arraybackslash}p{", w_label, "cm} ",
                    "*{6}{>{\\raggedleft\\arraybackslash}p{", w_num, "cm}}")

header_block <- function() {
  c(" & \\multicolumn{2}{c}{\\textbf{Whole panel}} & \\multicolumn{2}{c}{\\textbf{During MR year}} & \\multicolumn{2}{c}{\\textbf{During MCL year}} \\\\",
    "\\cmidrule(lr){2-3}\\cmidrule(lr){4-5}\\cmidrule(lr){6-7}",
    " & \\textbf{\\%} & \\textbf{N} & \\textbf{\\%} & \\textbf{N} & \\textbf{\\%} & \\textbf{N} \\\\")
}

# ── 7. Panel A — Enforcement type ─────────────────────────────────────────────
panel_a_lines <- c(
  paste0("\\begin{tabular}{", col_spec, "}"),
  "\\hline\\hline",
  header_block(),
  "\\multicolumn{7}{l}{\\textbf{Panel A: Enforcement type}} \\\\",
  sapply(panel_a_rows, make_row),
  "\\end{tabular}"
)

# ── 8. Panel B — Visit type ───────────────────────────────────────────────────
# Column headings are not repeated here (Panel A's header applies to both
# panels, since both share the same six columns).
panel_b_lines <- c(
  paste0("\\begin{tabular}{", col_spec, "}"),
  "\\hline",
  "\\multicolumn{7}{l}{\\textbf{Panel B: Visit type}} \\\\",
  sapply(panel_b_rows, make_row),
  "\\hline\\hline",
  "\\end{tabular}"
)

# ── 9. Assemble table ─────────────────────────────────────────────────────────
n_mr_fmt  <- fn(sum(dset$mr_year))
n_mcl_fmt <- fn(sum(dset$mcl_year))

combined_note <- paste0(
  "\\textit{Notes:} Sample of drinking water utilities downstream of a coal mine between ",
  "1985--2005. MR = monitoring and reporting violation; MCL = maximum contaminant level ",
  "violation. Whole panel columns report the share and count of utility-year cells with a ",
  "given enforcement action or site visit type, among all ", fn(N_obs), " cells. During MR ",
  "year and During MCL year columns restrict to the ", n_mr_fmt, " and ", n_mcl_fmt, " cells, ",
  "respectively, with a nitrate, arsenic, or inorganic chemical violation of that category, ",
  "before computing the same share and count. Panel A: Formal and Informal enforcement follow ",
  "the EPA SDWIS enforcement-action classification; Any is a cell with an enforcement action of ",
  "either category. Panel B: Sanitary visits are sanitary surveys and follow-up sanitary ",
  "surveys; Technical assistance covers technical assistance, engineering, and operations and ",
  "maintenance visits; Enforcement visits are formal-enforcement, investigation, and emergency ",
  "site visits; Sample collection is a sample-collection visit; Inspection covers site, ",
  "regularly scheduled, and informal system inspections. An enforcement action or visit type ",
  "may co-occur with others in the same cell, so rows need not sum to the Any/whole-panel total. ",
  "Number of observations = ", fn(N_obs), "."
)

table_lines <- c(
  "\\begin{table}[htbp]",
  "\\raggedright",
  "\\caption{Enforcement Actions and Site Visits, Coal Mining Exposed Utilities 1985--2005}",
  "\\label{tab:enforcement_visit_type_panels}",
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
  "% Table: Enforcement Actions and Site Visits, Coal Mining Exposed Utilities, 1985--2005",
  "% Purpose: Two-panel summary of enforcement action types (Formal/Informal/Any) and",
  "%          site visit types (Sanitary/Technical assistance/Enforcement/Sample",
  "%          collection/Inspection) over the whole panel and MR-/MCL-year subsets.",
  "% Sample:  Main 2SLS downstream utility-year sample (minehuc_downstream_of_mine=1,",
  "%          minehuc_mine=0, 1985-2005, excluding PWSID WV3303401, minus 7 fixed-effect",
  "%          singleton rows dropped by the reference 2SLS specification)",
  paste0("% N:       ", fn(N_obs), " utility-year observations (MR-year subset N=", n_mr_fmt,
         "; MCL-year subset N=", n_mcl_fmt, ")"),
  "% ============================================================"
)

out_path <- "Z:/ek559/mining_wq/output/sum/enforcement_visit_type_panels.tex"
writeLines(c(header, "", table_lines), out_path)
cat("\nOutput written to:", out_path, "\n")
cat("=== DONE ===\n")
