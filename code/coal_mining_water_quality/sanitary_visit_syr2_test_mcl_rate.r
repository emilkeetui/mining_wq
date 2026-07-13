# ============================================================
# Script: sanitary_visit_syr2_test_mcl_rate.r
# Purpose: CWS x SYR2-sample-date rate table (strictly-downstream 2SLS
#          sample) testing whether the arsenic/nitrate/inorganic-chemicals
#          MR violation rate differs for SYR2 test observations whose
#          measured value is already close to (> 50% of) the MCL. Row 1:
#          MR violation rate (same calendar year as the sample date) over
#          all SYR2 sample-date observations. Row 2: rate restricted to
#          sample-date observations with ratio (VALUE / mcl_mgL) > 0.5.
# Inputs:  clean_data/cws_data/prod_vio_sulfur.parquet
#          clean_data/cws_6year_review_measurement_level_syr2.parquet
# Outputs: output/sum/sanitary_visit_syr2_test_mcl_rate.tex
# Author: EK  Date: 2026-07-13
# ============================================================

.libPaths("Z:/ek559/RPackages")
library(arrow)
library(data.table)

ROOT <- "Z:/ek559/mining_wq"

TARGET_CHEMS <- c("arsenic", "nitrate", "selenium", "barium", "chromium")

# ── 0. Sample: strictly-downstream CWSs ───────────────────────────────────────
panel <- as.data.table(
  arrow::read_parquet(file.path(ROOT, "clean_data/cws_data/prod_vio_sulfur.parquet"),
    col_select = c("PWSID", "year", "minehuc_downstream_of_mine", "minehuc_mine",
                   "arsenic_MR_share", "nitrates_MR_share", "inorganic_chemicals_MR_share")))
downstream_mask <- panel$minehuc_downstream_of_mine == 1 & panel$minehuc_mine == 0
sample_pwsids   <- unique(panel$PWSID[downstream_mask])
cat("Downstream CWSs in sample:", length(sample_pwsids), "\n")

# ── 1. MR violation by CWS-year (any of arsenic/nitrates/inorganic_chemicals) ─
mr_py <- panel[downstream_mask]
mr_py[, mr_violation := as.integer(
  (arsenic_MR_share > 0 & !is.na(arsenic_MR_share)) |
  (nitrates_MR_share > 0 & !is.na(nitrates_MR_share)) |
  (inorganic_chemicals_MR_share > 0 & !is.na(inorganic_chemicals_MR_share))
)]
mr_py <- unique(mr_py[, .(PWSID, year, mr_violation)])
cat("CWS-years with an arsenic/nitrate/IOC MR violation:", sum(mr_py$mr_violation),
    "of", nrow(mr_py), "\n")

rm(panel); gc()

# ── 2. SYR2 sample dates (arsenic/nitrate/selenium/barium/chromium) ──────────
syr2 <- as.data.table(arrow::read_parquet(
  file.path(ROOT, "clean_data/cws_6year_review_measurement_level_syr2.parquet"),
  col_select = c("PWSID", "sample_date", "CHEMID_name", "VALUE", "mcl_mgL", "ratio")))
syr2 <- syr2[PWSID %in% sample_pwsids & CHEMID_name %in% TARGET_CHEMS &
             !is.na(sample_date) & !is.na(ratio)]
syr2[, sample_yr := as.integer(format(as.Date(sample_date), "%Y"))]
cat("SYR2 sample-date observations (downstream CWSs, 5-chem restriction):", nrow(syr2), "\n")

# ── 3. Attach MR violation by calendar year of the sample date ───────────────
syr2 <- merge(syr2, mr_py, by.x = c("PWSID", "sample_yr"), by.y = c("PWSID", "year"), all.x = TRUE)
syr2[is.na(mr_violation), mr_violation := 0L]

# ── 4. Two rows: rate of MR violation across nested samples ─────────────────
row1_dt <- syr2
row2_dt <- syr2[ratio > 0.5]

rate <- function(dt) 100 * mean(dt$mr_violation)

rows <- data.table(
  sample = c("All SYR2 sample dates (downstream 2SLS panel)",
             "SYR2 sample dates with ratio to MCL > 50\\%"),
  n    = c(nrow(row1_dt), nrow(row2_dt)),
  rate = c(rate(row1_dt), rate(row2_dt))
)
cat("\n--- Arsenic/nitrate/IOC MR violation rate table ---\n")
print(rows)

# ── 5. LaTeX table (hand-assembled; no wrap_for_beamer -- has \begin{table}) ─
dir.create(file.path(ROOT, "output/sum"), showWarnings = FALSE, recursive = TRUE)

fmt_n   <- function(x) gsub(",", "{,}", formatC(x, format = "d", big.mark = ","))
fmt_pct <- function(x) sprintf("%.2f", x)

rows_tex <- sprintf("%s & %s & %s\\%% \\\\", rows$sample, fmt_n(rows$n), fmt_pct(rows$rate))

notes_main <- paste0(
  "Sample: strictly downstream CWSs (", length(sample_pwsids), "), SYR2 sample-date ",
  "observations of arsenic, nitrate, selenium, barium, or chromium (", nrow(row1_dt),
  " observations). MR violation = 1 if a monitoring/reporting violation ",
  "(VIOLATION\\_CATEGORY\\_CODE = MR) is recorded for arsenic, nitrates, or inorganic ",
  "chemicals (arsenic\\_MR\\_share, nitrates\\_MR\\_share, or inorganic\\_chemicals\\_MR\\_share ",
  "$>$ 0) at that CWS in the calendar year of the SYR2 sample date. Ratio to MCL = ",
  "VALUE / mcl\\_mgL for that measurement, as recorded in the EPA Six-Year Review (SYR2) ",
  "data. Row 2 restricts to sample-date observations with ratio to MCL $>$ 0.5 (N\\,=\\,",
  fmt_n(nrow(row2_dt)), ")."
)

out_tex <- file.path(ROOT, "output/sum/sanitary_visit_syr2_test_mcl_rate.tex")
lines_tex <- c(
  "\\begin{table}[htbp]",
  paste0("\\caption{\\label{tab:sanitary_visit_syr2_test_mcl_rate} Arsenic/Nitrate/IOC MR ",
         "Violation Rate, by SYR2 Test Proximity to MCL (Downstream CWSs)}"),
  "\\bigskip",
  "\\centering",
  "\\begin{adjustbox}{width = \\textwidth, center}",
  "\\begin{tabular}{lcc}",
  "\\toprule",
  "Sample & N (SYR2 sample dates) & MR violation rate \\\\",
  "\\midrule",
  rows_tex,
  "\\bottomrule",
  "\\end{tabular}",
  "\\end{adjustbox}",
  "{\\tiny\\linespread{1}\\selectfont \\par \\raggedright ",
  notes_main,
  "}",
  "\\end{table}"
)
writeLines(lines_tex, out_tex)
cat("\nTable saved to:", out_tex, "\n")

# ── 6. Verification ──────────────────────────────────────────────────────────
stopifnot(file.exists(out_tex), file.info(out_tex)$size > 0)
stopifnot(nrow(row1_dt) >= nrow(row2_dt), nrow(row2_dt) > 0)
cat("Output verified: file exists and is non-zero; row counts consistent.\n")
cat("=== DONE ===\n")
