# ============================================================
# Script: mr_violation_breakdown.r
# Purpose: Describe MR and MCL violations in SDWA for IOC rules —
#          by violation code and regulatory rule code.
#          Restricted to the downstream 2SLS CWS-year sample
#          (minehuc_downstream_of_mine == 1 & minehuc_mine == 0,
#          year 1985-2005, PWSID != "WV3303401") — same filter as
#          the "dwnstrm" sample_specs entry in didhet.r (full_unbal).
#          IOC rules: nitrate (331), arsenic (332), inorganic chemicals (333).
# Inputs:  clean_data/cws_data/prod_vio_sulfur.parquet (downstream PWSID filter)
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.parquet
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_REF_CODE_VALUES.csv
# Outputs: output/sum/mr_violation_breakdown.tex
#          output/sum/ioc_days_dwnstrm.tex
# Author: EK  Date: 2026-04-15
# ============================================================

.libPaths("Z:/ek559/RPackages")
library(arrow)
library(data.table)

# ── 0. Downstream 2SLS CWS-year sample PWSID list ────────────────────────────
# Matches full_unbal's "dwnstrm" sample_specs filter in didhet.r:
# year 1985-2005, PWSID != "WV3303401", minehuc_downstream_of_mine == 1 & minehuc_mine == 0.
pws_sample <- as.data.frame(
  arrow::read_parquet("Z:/ek559/mining_wq/clean_data/cws_data/prod_vio_sulfur.parquet",
                      col_select = c("PWSID", "year", "minehuc_downstream_of_mine", "minehuc_mine")))
pws_sample <- pws_sample[pws_sample$year > 1984 & pws_sample$year < 2006, ]
pws_sample <- pws_sample[pws_sample$PWSID != "WV3303401", ]
pws_ids <- unique(pws_sample$PWSID[
  pws_sample$minehuc_downstream_of_mine == 1 & pws_sample$minehuc_mine == 0])
cat("Downstream 2SLS sample PWSIDs:", length(pws_ids), "\n")

# ── 1. Load violations from parquet ──────────────────────────────────────────
cat("Loading violations parquet...\n")
ve <- as.data.table(arrow::read_parquet(
  "Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.parquet",
  col_select = c("PWSID", "VIOLATION_ID", "NON_COMPL_PER_BEGIN_DATE",
                 "VIOLATION_CATEGORY_CODE", "VIOLATION_CODE", "RULE_CODE")
))
cat("Total rows in parquet:", nrow(ve), "\n")

ve[, yr       := as.integer(substr(NON_COMPL_PER_BEGIN_DATE, 7, 10))]
ve[, rule_tmp := suppressWarnings(as.integer(RULE_CODE))]

# ── 1a. MR violations, IOC rules ──────────────────────────────────────────────
mr_raw <- ve[PWSID %in% pws_ids & VIOLATION_CATEGORY_CODE == "MR" &
             yr >= 1985 & yr <= 2005]
mr <- unique(mr_raw, by = c("PWSID", "VIOLATION_ID"))
mr <- mr[rule_tmp %in% c(331L, 332L, 333L)]
cat("IOC MR violations (rules 331/332/333):", nrow(mr), "\n")

# ── 1b. MCL violations, IOC rules ─────────────────────────────────────────────
mcl_raw <- ve[PWSID %in% pws_ids & VIOLATION_CATEGORY_CODE == "MCL" &
              yr >= 1985 & yr <= 2005]
mcl <- unique(mcl_raw, by = c("PWSID", "VIOLATION_ID"))
mcl <- mcl[rule_tmp %in% c(331L, 332L, 333L)]
cat("IOC MCL violations (rules 331/332/333):", nrow(mcl), "\n")

N_mr  <- nrow(mr)
N_mcl <- nrow(mcl)

# ── 2. Load violation-code and rule-code descriptions ────────────────────────
ref <- fread(
  "Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_REF_CODE_VALUES.csv",
  header = FALSE,
  col.names = c("VALUE_TYPE", "VALUE_CODE", "VALUE_DESCRIPTION")
)
viol_code_ref <- ref[VALUE_TYPE == "VIOLATION_CODE", .(VALUE_CODE, VALUE_DESCRIPTION)]
rule_code_ref <- ref[VALUE_TYPE == "RULE_CODE",      .(VALUE_CODE, VALUE_DESCRIPTION)]

# ── 3. Violation-code frequency tables ───────────────────────────────────────
tab_vc_mr <- mr[, .N, by = VIOLATION_CODE]
tab_vc_mr[, share := 100 * N / N_mr]
tab_vc_mr <- merge(tab_vc_mr, viol_code_ref,
                   by.x = "VIOLATION_CODE", by.y = "VALUE_CODE", all.x = TRUE)
tab_vc_mr[is.na(VALUE_DESCRIPTION), VALUE_DESCRIPTION := VIOLATION_CODE]
setorder(tab_vc_mr, -N)
cat("\nMR — by violation code:\n"); print(tab_vc_mr)

tab_vc_mcl <- mcl[, .N, by = VIOLATION_CODE]
tab_vc_mcl[, share := 100 * N / N_mcl]
tab_vc_mcl <- merge(tab_vc_mcl, viol_code_ref,
                    by.x = "VIOLATION_CODE", by.y = "VALUE_CODE", all.x = TRUE)
tab_vc_mcl[is.na(VALUE_DESCRIPTION), VALUE_DESCRIPTION := VIOLATION_CODE]
setorder(tab_vc_mcl, -N)
cat("\nMCL — by violation code:\n"); print(tab_vc_mcl)

# ── 4. Rule-code frequency tables (MR and MCL) ───────────────────────────────
make_rule_tab <- function(dt) {
  dt[, rc := as.character(suppressWarnings(as.integer(RULE_CODE)))]
  t <- dt[!is.na(rc), .N, by = rc]
  t[, share := 100 * N / nrow(dt)]
  t <- merge(t, rule_code_ref, by.x = "rc", by.y = "VALUE_CODE", all.x = TRUE)
  t[is.na(VALUE_DESCRIPTION), VALUE_DESCRIPTION := rc]
  setorder(t, -N)
  t
}
tab_rule_mr  <- make_rule_tab(copy(mr))
tab_rule_mcl <- make_rule_tab(copy(mcl))
cat("\nMR — by rule code:\n"); print(tab_rule_mr)
cat("\nMCL — by rule code:\n"); print(tab_rule_mcl)

# Combined rule-code table (MR and MCL side-by-side)
tab_rule <- merge(
  tab_rule_mr [, .(rc, VALUE_DESCRIPTION, N_mr  = N, share_mr  = share)],
  tab_rule_mcl[, .(rc, N_mcl = N, share_mcl = share)],
  by = "rc", all = TRUE
)
tab_rule[is.na(N_mr),      c("N_mr",  "share_mr")  := list(0L, 0)]
tab_rule[is.na(N_mcl),     c("N_mcl", "share_mcl") := list(0L, 0)]
setorder(tab_rule, -N_mr)
cat("\nCombined rule table:\n"); print(tab_rule)

# ── 5. LaTeX helpers ──────────────────────────────────────────────────────────
fn  <- function(x) format(as.integer(x), big.mark = ",")
fp  <- function(x) sprintf("%.1f", x)
esc <- function(x) gsub("_", "\\\\_", x)
trunc_desc <- function(x, w = 48) {
  ifelse(nchar(x) > w, paste0(substr(x, 1, w - 2), ".."), x)
}

sample_note <- paste0(
  "Sample restricted to the downstream 2SLS CWS-year sample ",
  "(minehuc\\_downstream\\_of\\_mine\\,=\\,1 and minehuc\\_mine\\,=\\,0, 1985--2005, ",
  "excluding PWSID WV3303401). ",
  "Source: SDWA\\_VIOLATIONS\\_ENFORCEMENT.parquet, SDWA\\_REF\\_CODE\\_VALUES.csv."
)

# ── 6. Panel A — MR violations by violation code ─────────────────────────────
routine_codes <- c("03","23","24","25","26","04")
other_codes   <- setdiff(tab_vc_mr$VIOLATION_CODE, routine_codes)

make_vc_rows <- function(codes, dt) {
  rows <- character(0)
  for (cd in codes) {
    r <- dt[VIOLATION_CODE == cd]
    if (nrow(r) == 0) next
    rows <- c(rows,
      paste0(r$VIOLATION_CODE, " & ", esc(trunc_desc(r$VALUE_DESCRIPTION)), " & ",
             fn(r$N), " & ", fp(r$share), " \\\\"))
  }
  rows
}

panel_a_lines <- c(
  "\\noindent\\textbf{Panel A: MR violations by violation code} \\\\[4pt]",
  "\\begin{tabular}{clrr}",
  "\\hline\\hline",
  "\\textbf{Code} & \\textbf{Description} & \\textbf{Count} & \\textbf{Share (\\%)} \\\\",
  "\\hline",
  "\\addlinespace[2pt]",
  "\\multicolumn{4}{l}{\\textit{Routine and repeat monitoring failures}} \\\\",
  "\\addlinespace[2pt]",
  make_vc_rows(routine_codes, tab_vc_mr),
  if (length(other_codes) > 0) c(
    "\\addlinespace[4pt]",
    "\\multicolumn{4}{l}{\\textit{Contaminant- or rule-specific monitoring failures}} \\\\",
    "\\addlinespace[2pt]",
    make_vc_rows(other_codes, tab_vc_mr)
  ),
  "\\addlinespace[2pt]",
  "\\hline",
  paste0(" & \\textit{Total} & ", fn(N_mr), " & 100.0 \\\\"),
  "\\hline\\hline",
  "\\end{tabular}"
)

# ── 7. Panel B — MCL violations by violation code ────────────────────────────
panel_b_lines <- c(
  "\\vspace{8pt}",
  "",
  "\\noindent\\textbf{Panel B: MCL violations by violation code} \\\\[4pt]",
  "\\begin{tabular}{clrr}",
  "\\hline\\hline",
  "\\textbf{Code} & \\textbf{Description} & \\textbf{Count} & \\textbf{Share (\\%)} \\\\",
  "\\hline",
  "\\addlinespace[2pt]",
  {
    rows <- character(0)
    for (i in seq_len(nrow(tab_vc_mcl))) {
      r <- tab_vc_mcl[i]
      rows <- c(rows,
        paste0(r$VIOLATION_CODE, " & ", esc(trunc_desc(r$VALUE_DESCRIPTION)), " & ",
               fn(r$N), " & ", fp(r$share), " \\\\"))
    }
    rows
  },
  "\\addlinespace[2pt]",
  "\\hline",
  paste0(" & \\textit{Total} & ", fn(N_mcl), " & 100.0 \\\\"),
  "\\hline\\hline",
  "\\end{tabular}"
)

# ── 8. Panel C — MR and MCL by rule code, side-by-side ───────────────────────
make_rule_rows <- function(dt) {
  rows <- character(0)
  for (i in seq_len(nrow(dt))) {
    r <- dt[i]
    rows <- c(rows,
      paste0(r$rc, " & ", esc(trunc_desc(r$VALUE_DESCRIPTION)), " & ",
             fn(r$N_mr), " & ", fp(r$share_mr), " & ",
             fn(r$N_mcl), " & ", fp(r$share_mcl), " \\\\"))
  }
  rows
}

panel_c_lines <- c(
  "\\vspace{8pt}",
  "",
  "\\noindent\\textbf{Panel C: MR vs.~MCL violations by regulatory rule} \\\\[4pt]",
  "\\begin{tabular}{clrrrr}",
  "\\hline\\hline",
  paste0("\\textbf{Rule} & \\textbf{Rule name} & ",
         "\\multicolumn{2}{c}{\\textbf{MR}} & ",
         "\\multicolumn{2}{c}{\\textbf{MCL}} \\\\"),
  "\\cmidrule(lr){3-4}\\cmidrule(lr){5-6}",
  paste0("\\textbf{code} & & \\textbf{Count} & \\textbf{Share (\\%)} & ",
         "\\textbf{Count} & \\textbf{Share (\\%)} \\\\"),
  "\\hline",
  "\\addlinespace[2pt]",
  make_rule_rows(tab_rule),
  "\\addlinespace[2pt]",
  "\\hline",
  paste0("  & \\textit{Total} & ", fn(N_mr), " & 100.0 & ", fn(N_mcl), " & 100.0 \\\\"),
  "\\hline\\hline",
  "\\end{tabular}"
)

# ── 9. Write combined three-panel table ──────────────────────────────────────
header <- c(
  "% ============================================================",
  "% Table: IOC MR and MCL Violation Breakdown, 1985--2005 (Downstream CWSs)",
  "% Purpose: Three-panel table describing violation codes and rule codes for",
  "%          MR and MCL violations under IOC rules (nitrate 331, arsenic 332,",
  "%          inorganic chemicals 333).",
  "% Sample:  Downstream 2SLS CWS-year sample (minehuc_downstream_of_mine=1, minehuc_mine=0,",
  "%          1985-2005, excluding PWSID WV3303401)",
  "% Source:  SDWA_VIOLATIONS_ENFORCEMENT.parquet + SDWA_REF_CODE_VALUES.csv",
  paste0("% N MR:    ", fn(N_mr),  " unique IOC MR violations, 1985--2005"),
  paste0("% N MCL:   ", fn(N_mcl), " unique IOC MCL violations, 1985--2005"),
  "% ============================================================"
)

combined_note <- paste0(
  "\\textit{Notes:} ",
  "Panel A: violation codes classify the type of monitoring-and-reporting failure; ",
  "code 03 = Monitoring, Regular; 04 = Monitoring, Check/Repeat/Confirmation. ",
  "Panel B: violation codes classify the type of MCL exceedance. ",
  "Panel C: rule 331 = Nitrate; 332 = Arsenic; 333 = Inorganic Chemicals; ",
  "MR = monitoring and reporting violation; MCL = maximum contaminant level violation; ",
  "inorganic chemicals (333) encompasses nitrates and arsenic as sub-contaminants. ",
  "All panels restricted to IOC rules (nitrate 331, arsenic 332, inorganic chemicals 333). ",
  sample_note
)

combined_table_lines <- c(
  "\\begin{table}[htbp]",
  "\\centering",
  "\\caption{IOC Violations by Violation Code and Regulatory Rule, 1985--2005 (Downstream CWSs)}",
  "\\label{tab:mr_mcl_violation_breakdown}",
  "\\small",
  panel_a_lines,
  panel_b_lines,
  panel_c_lines,
  "\\begin{minipage}{\\linewidth}",
  "\\vspace{4pt}",
  "\\footnotesize",
  combined_note,
  "\\end{minipage}",
  "\\end{table}"
)

out_path <- "Z:/ek559/mining_wq/output/sum/mr_violation_breakdown.tex"
writeLines(c(header, "", combined_table_lines), out_path)
cat("\nOutput written to:", out_path, "\n")

# ── 10. Summary table: Days in a Year with IOC Violation (D1 downstream) ─────

ioc_vars <- c("inorganic_chemicals_MR_share_days", "inorganic_chemicals_MCL_share_days",
              "nitrates_MR_share_days",            "nitrates_MCL_share_days",
              "arsenic_MR_share_days",             "arsenic_MCL_share_days")

d1_panel <- as.data.frame(
  arrow::read_parquet(
    "Z:/ek559/mining_wq/clean_data/cws_data/prod_vio_sulfur.parquet",
    col_select = c("PWSID", "year", "minehuc_downstream_of_mine", "minehuc_mine",
                   ioc_vars)))

d1_panel <- d1_panel[
  d1_panel$minehuc_downstream_of_mine == 1 &
  d1_panel$minehuc_mine == 0 &
  d1_panel$year > 1984 & d1_panel$year < 2006 &
  d1_panel$PWSID != "WV3303401", ]

cat("Downstream 2SLS sample obs (1985-2005):", nrow(d1_panel), "\n")
N_d1     <- nrow(d1_panel)
N_pws_d1 <- length(unique(d1_panel$PWSID))

stats_d1 <- data.frame(
  contaminant = c("Inorganic chemicals", "Nitrates", "Arsenic"),
  mr_mean  = c(mean(d1_panel$inorganic_chemicals_MR_share_days, na.rm = TRUE),
               mean(d1_panel$nitrates_MR_share_days,            na.rm = TRUE),
               mean(d1_panel$arsenic_MR_share_days,             na.rm = TRUE)),
  mr_sd    = c(sd(d1_panel$inorganic_chemicals_MR_share_days,   na.rm = TRUE),
               sd(d1_panel$nitrates_MR_share_days,              na.rm = TRUE),
               sd(d1_panel$arsenic_MR_share_days,               na.rm = TRUE)),
  mcl_mean = c(mean(d1_panel$inorganic_chemicals_MCL_share_days, na.rm = TRUE),
               mean(d1_panel$nitrates_MCL_share_days,            na.rm = TRUE),
               mean(d1_panel$arsenic_MCL_share_days,             na.rm = TRUE)),
  mcl_sd   = c(sd(d1_panel$inorganic_chemicals_MCL_share_days,  na.rm = TRUE),
               sd(d1_panel$nitrates_MCL_share_days,             na.rm = TRUE),
               sd(d1_panel$arsenic_MCL_share_days,              na.rm = TRUE))
)
print(stats_d1)

fp2 <- function(x) sprintf("%.2f", x)

make_row <- function(i) {
  paste0(stats_d1$contaminant[i],
         " & ", fp2(stats_d1$mr_mean[i]),  " & ", fp2(stats_d1$mr_sd[i]),
         " & ", fp2(stats_d1$mcl_mean[i]), " & ", fp2(stats_d1$mcl_sd[i]),
         " \\\\")
}

t_days_lines <- c(
  "\\begin{table}[htbp]",
  "\\centering",
  "\\caption{Days in a Year with IOC Violation}",
  "\\label{tab:ioc_days_dwnstrm}",
  "\\small",
  "\\begin{tabular}{lrrrr}",
  "\\hline\\hline",
  " & \\multicolumn{2}{c}{\\textbf{MR Violations}} & \\multicolumn{2}{c}{\\textbf{MCL Violations}} \\\\",
  "\\cmidrule(lr){2-3}\\cmidrule(lr){4-5}",
  "\\textbf{Contaminant} & \\textbf{Mean} & \\textbf{SD} & \\textbf{Mean} & \\textbf{SD} \\\\",
  "\\hline",
  make_row(1),
  make_row(2),
  make_row(3),
  "\\hline\\hline",
  "\\end{tabular}",
  "\\begin{minipage}{\\linewidth}",
  "\\vspace{4pt}",
  "\\footnotesize",
  paste0("\\textit{Notes:} Sample restricted to the downstream 2SLS CWS-year sample ",
         "(minehuc\\_downstream\\_of\\_mine\\,=\\,1 and minehuc\\_mine\\,=\\,0, years 1985--2005, ",
         "excluding PWSID WV3303401). ",
         "MR = monitoring and reporting violation; MCL = maximum contaminant level violation. ",
         "Inorganic chemicals encompasses nitrates and arsenic as sub-contaminants. ",
         "Outcomes measured as days out of the year in violation. ",
         "N\\,=\\,", format(N_d1, big.mark = ","),
         " CWS$\\times$year observations across ",
         format(N_pws_d1, big.mark = ","), " unique community water systems."),
  "\\end{minipage}",
  "\\end{table}"
)

out_path_days <- "Z:/ek559/mining_wq/output/sum/ioc_days_dwnstrm.tex"
writeLines(t_days_lines, out_path_days)
cat("\nIOC days summary table written to:", out_path_days, "\n")

cat("=== DONE ===\n")
