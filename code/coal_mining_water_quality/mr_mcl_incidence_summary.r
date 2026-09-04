# ============================================================
# Script: mr_mcl_incidence_summary.r
# Purpose: Summary table of incidence rate, count, and N for arsenic,
#          inorganic chemicals, and nitrates MR and MCL violations,
#          restricted to the downstream 2SLS CWS-year sample
#          (minehuc_downstream_of_mine == 1 & minehuc_mine == 0,
#          year 1985-2005, PWSID != "WV3303401") — same filter as
#          the "dwnstrm" sample_specs entry in didhet.r (full_unbal).
#          Incidence indicator = 1 if the *_MR_share / *_MCL_share
#          variable is > 0 (any violation days that year), else 0.
# Inputs:  clean_data/cws_data/prod_vio_sulfur.parquet
# Outputs: output/sum/mr_mcl_incidence_summary.tex
# Author: EK  Date: 2026-07-15
# ============================================================

.libPaths(c("C:/Users/ek559/AppData/Local/R/win-library/4.6", "Z:/ek559/RPackages"))
library(arrow)

# ── 1. Load downstream 2SLS CWS-year sample ──────────────────────────────────
share_vars <- c("arsenic_MR_share",             "arsenic_MCL_share",
                "inorganic_chemicals_MR_share", "inorganic_chemicals_MCL_share",
                "nitrates_MR_share",            "nitrates_MCL_share")

dat <- as.data.frame(
  arrow::read_parquet(
    "Z:/ek559/mining_wq/clean_data/cws_data/prod_vio_sulfur.parquet",
    col_select = c("PWSID", "year", "minehuc_downstream_of_mine", "minehuc_mine",
                   share_vars)))

dat <- dat[
  dat$year > 1984 & dat$year < 2006 &
  dat$PWSID != "WV3303401" &
  dat$minehuc_downstream_of_mine == 1 & dat$minehuc_mine == 0, ]

cat("Downstream 2SLS sample obs (1985-2005):", nrow(dat), "\n")

# ── 2. Incidence indicator = 1{share > 0} ─────────────────────────────────────
for (v in share_vars) {
  dat[[paste0(v, "_ind")]] <- as.integer(!is.na(dat[[v]]) & dat[[v]] > 0)
}

# ── 3. Rate, count, N per row ─────────────────────────────────────────────────
row_specs <- list(
  list(label = "Arsenic MR violation",             var = "arsenic_MR_share_ind"),
  list(label = "Arsenic MCL violation",             var = "arsenic_MCL_share_ind"),
  list(label = "Inorganic chemicals MR violation",  var = "inorganic_chemicals_MR_share_ind"),
  list(label = "Inorganic chemicals MCL violation", var = "inorganic_chemicals_MCL_share_ind"),
  list(label = "Nitrate MR violation",               var = "nitrates_MR_share_ind"),
  list(label = "Nitrate MCL violation",               var = "nitrates_MCL_share_ind")
)

stats <- do.call(rbind, lapply(row_specs, function(rs) {
  x     <- dat[[rs$var]]
  n_obs <- sum(!is.na(x))
  cnt   <- sum(x == 1, na.rm = TRUE)
  data.frame(label = rs$label, rate = cnt / n_obs, count = cnt, N = n_obs)
}))
print(stats)

# ── 4. LaTeX helpers ──────────────────────────────────────────────────────────
fn <- function(x) format(as.integer(x), big.mark = ",")
fr <- function(x) sprintf("%.2f", 100 * x)

make_row <- function(i) {
  paste0(stats$label[i], " & ", fr(stats$rate[i]), " & ",
         fn(stats$count[i]), " & ", fn(stats$N[i]), " \\\\")
}

table_lines <- c(
  "\\begin{table}[htbp]",
  "\\centering",
  "\\caption{Incidence of MR and MCL Violations, Downstream 2SLS Utility-Year Sample, 1985--2005}",
  "\\label{tab:mr_mcl_incidence_summary}",
  "\\small",
  "\\begin{tabular}{lrrr}",
  "\\hline\\hline",
  "\\textbf{Violation} & \\textbf{Rate (\\%)} & \\textbf{Count} & \\textbf{N} \\\\",
  "\\hline",
  sapply(seq_len(nrow(stats)), make_row),
  "\\hline\\hline",
  "\\end{tabular}",
  "\\begin{minipage}{\\linewidth}",
  "\\vspace{4pt}",
  "\\footnotesize",
  "\\raggedright",
  paste0(
    "\\textit{Notes:} Sample restricted to utilities strictly downstream of a coal mine, ",
    "years 1985--2005. ",
    "Rate is the share of utility-year observations with a nonzero violation share for that ",
    "category, in percent. ",
    "MR = monitoring and reporting violation; MCL = maximum contaminant level violation. ",
    "Inorganic chemicals encompasses nitrates and arsenic as sub-contaminants."
  ),
  "\\end{minipage}",
  "\\end{table}"
)

header <- c(
  "% ============================================================",
  "% Table: MR/MCL Violation Incidence Summary, Downstream 2SLS Sample, 1985--2005",
  "% Purpose: Rate (share of obs with any violation days), count, and N for",
  "%          arsenic, inorganic chemicals, and nitrates MR/MCL violations.",
  "% Sample:  Downstream 2SLS utility-year sample (minehuc_downstream_of_mine=1, minehuc_mine=0,",
  "%          1985-2005, excluding PWSID WV3303401)",
  paste0("% N:       ", fn(nrow(dat)), " utility-year observations"),
  "% ============================================================"
)

out_path <- "Z:/ek559/mining_wq/output/sum/mr_mcl_incidence_summary.tex"
writeLines(c(header, "", table_lines), out_path)
cat("\nOutput written to:", out_path, "\n")
cat("=== DONE ===\n")
