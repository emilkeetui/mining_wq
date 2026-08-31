# ============================================================
# Script: exclusion_test_num_facilities.r
# Purpose: Exclusion-restriction falsification test - regress the number of
#          active intake facilities on the ARP x sulfur instrument, on the
#          main 2SLS estimation sample (CWSs at most one watershed downstream
#          of a coal mine)
# Inputs:  clean_data/cws_data/prod_vio_sulfur.parquet
# Outputs: output/reg/exclusion_test_num_facilities.tex
# Author: EK  Date: 2026-08-31
# ============================================================

.libPaths(c(.libPaths(), "Z:/ek559/RPackages"))
library(fixest)
library(arrow)
library(dplyr)

# -- Step 2: load and cut the sample (mirrors run_main_tables.r lines 6-8) --
full <- read_parquet("Z:/ek559/mining_wq/clean_data/cws_data/prod_vio_sulfur.parquet")
full <- full[full$year < 2006 & full$year > 1984, ]
full <- full[full$PWSID != "WV3303401", ]
full$num_facilities <- as.numeric(full$num_facilities)

cat("-- Cross-language schema check --\n")
cat("class(PWSID):", class(full$PWSID), "\n")
cat("class(year):",  class(full$year),  "\n")
str(full[, c("PWSID", "year", "num_facilities", "sulfur_unified_sum", "post95",
             "minehuc_downstream_of_mine", "minehuc_mine")])
if (!is.character(full$PWSID)) stop("PWSID is not character - fix the Python writer before proceeding.")
if (!is.integer(full$year))    cat("NOTE: year is not integer class (", class(full$year), ") - proceeding, matches run_main_tables.r behavior.\n")

cat("\nRows in full:", nrow(full), "\n")

# -- Sample: main 2SLS estimation sample only (CWSs at most one watershed
# downstream of a coal mine). Colocated and all-watersheds cuts are not
# reported - the test is restricted to the sample the
# paper's 2SLS design actually uses. -----------------------------------------
dset <- full[(full$minehuc_downstream_of_mine == 1) & (full$minehuc_mine == 0), ]
dset <- dset[!is.na(dset$num_facilities), ]

n_obs   <- nrow(dset)
mean_f  <- mean(dset$num_facilities, na.rm = TRUE)
sd_f    <- sd(dset$num_facilities, na.rm = TRUE)

change_tbl <- dset %>%
  group_by(PWSID) %>%
  summarise(n_distinct_f = n_distinct(num_facilities), .groups = "drop")
n_change <- sum(change_tbl$n_distinct_f > 1)
share_change <- n_change / nrow(change_tbl)

# Balanced-panel subsample: utilities observed in every year present in this
# sample. Column (2) uses this subsample. Coal sulfur content is fixed within
# a utility over the sample period and the panel of utilities observed each
# year is unbalanced (utilities enter/leave the sample), so a post-1995
# interaction estimated with only year fixed effects on the full unbalanced
# panel can reflect a change in which utilities are observed each period
# rather than a genuine change at any given utility. Restricting to the
# balanced subsample isolates a genuine divergence from that artifact.
n_years_expected <- length(unique(dset$year))
year_counts <- dset %>%
  group_by(PWSID) %>%
  summarise(n_years = n_distinct(year), .groups = "drop")
balanced_ids <- year_counts$PWSID[year_counts$n_years == n_years_expected]
dset_bal     <- dset[dset$PWSID %in% balanced_ids, ]
n_bal_cws    <- length(balanced_ids)
# Reported per column, since the two columns estimate on different samples.
n_change_bal <- sum(change_tbl$n_distinct_f[change_tbl$PWSID %in% balanced_ids] > 1)

# -- Term-resolution helper: search for the row whose name contains all of the
# given substrings, excluding rows that also contain an excluded substring.
# Does not hardcode fixest's interaction-term ordering (post95:sulfur_unified_sum
# vs sulfur_unified_sum:post95). ---------------------------------------------
get_single_term <- function(model, include, exclude = NULL) {
  ct <- fixest::coeftable(model)
  rn <- rownames(ct)
  ok <- sapply(rn, function(r) {
    all(sapply(include, function(p) grepl(p, r, fixed = TRUE))) &&
      (is.null(exclude) || !any(sapply(exclude, function(p) grepl(p, r, fixed = TRUE))))
  })
  row <- rn[ok]
  if (length(row) != 1) {
    stop("Could not uniquely resolve term for include=[", paste(include, collapse = ","),
         "] exclude=[", paste(exclude, collapse = ","), "] - candidate rows: ",
         paste(row, collapse = " | "), " - all rows: ", paste(rn, collapse = " | "))
  }
  list(est = ct[row, "Estimate"], se = ct[row, "Std. Error"], pval = ct[row, "Pr(>|t|)"], row = row)
}

ci95 <- function(term) c(lo = term$est - 1.96 * term$se, hi = term$est + 1.96 * term$se)

# -- Step 3/4: estimate the two specifications, print diagnostics ------------
# Column (1): utility + year fixed effects
# Column (2): year fixed effects only (levels), balanced-panel subsample
#
# A levels specification on the full unbalanced panel is deliberately NOT
# reported: coal sulfur content is fixed within a utility and the number of
# intake facilities changes for one utility in this sample, so a post-1995
# interaction estimated off the unbalanced panel picks up which utilities are
# observed in each period rather than any change at a utility. The balanced
# subsample in column (2) is the levels specification that is interpretable.
cat("\n================ Estimation ================\n")

m1 <- tryCatch(
  fixest::feols(num_facilities ~ post95:sulfur_unified_sum | PWSID + year,
                 data = dset, cluster = ~PWSID),
  error = function(e) stop("Column (1) feols failed: ", conditionMessage(e))
)
m2 <- tryCatch(
  fixest::feols(num_facilities ~ sulfur_unified_sum + post95:sulfur_unified_sum | year,
                 data = dset_bal, cluster = ~PWSID),
  error = function(e) stop("Column (2) feols failed: ", conditionMessage(e))
)

col1_interact <- get_single_term(m1, include = c("post95", "sulfur_unified_sum"))
col2_main     <- get_single_term(m2, include = c("sulfur_unified_sum"), exclude = c("post95"))
col2_interact <- get_single_term(m2, include = c("post95", "sulfur_unified_sum"))

col1_ci <- ci95(col1_interact)
col2_ci <- ci95(col2_interact)

# Utilities retained per column: column (1) drops fixed-effect singletons
# (utilities/years with only one observation in the joint PWSID x year FE
# structure); column (2) does not (year FE only).
n_cws_col1 <- length(fixest::fixef(m1)$PWSID)
n_cws_col2 <- n_bal_cws

n_obs_col1 <- nobs(m1)
n_obs_col2 <- nobs(m2)

cat("\n--- Sample: CWSs at most one watershed downstream of a coal mine ---\n")
cat(sprintf("  N obs: col1=%d  col2=%d\n", n_obs_col1, n_obs_col2))
cat(sprintf("  N CWSs: col1=%d  col2=%d\n", n_cws_col1, n_cws_col2))
cat(sprintf("  Mean num_facilities: %.4f | SD: %.4f\n", mean_f, sd_f))
cat(sprintf("  CWSs with within-CWS change in num_facilities: %d of %d (%.4f)\n",
            n_change, nrow(change_tbl), share_change))
cat(sprintf("  Col (1) [post95 x sulfur_unified_sum]: est=%.4f  se=%.4f  p=%.4f  CI=[%.4f, %.4f]\n",
            col1_interact$est, col1_interact$se, col1_interact$pval, col1_ci["lo"], col1_ci["hi"]))
cat(sprintf("  Col (2) [sulfur_unified_sum]:          est=%.4f  se=%.4f  p=%.4f\n",
            col2_main$est, col2_main$se, col2_main$pval))
cat(sprintf("  Col (2) [post95 x sulfur_unified_sum]: est=%.4f  se=%.4f  p=%.4f  CI=[%.4f, %.4f]\n",
            col2_interact$est, col2_interact$se, col2_interact$pval, col2_ci["lo"], col2_ci["hi"]))
cat(sprintf("  Col (1) 95pct CI as pct of mean num_facilities: [%.2f%%, %.2f%%]\n",
            100 * col1_ci["lo"] / mean_f, 100 * col1_ci["hi"] / mean_f))

# -- Step 5: supplementary control-sensitivity check (console/log only) -----
# Already restricted to the downstream (D1) sample - unaffected by dropping
# the colocated / all-watersheds columns above.
cat("\n================ Step 5: control-sensitivity check ================\n")
cat("Sample: downstream (D1). Outcomes: nitrates_MR_bin, arsenic_MR_bin, inorganic_chemicals_MR_bin\n")
cat("coalvar = num_coal_mines_upstream_sum | instrument = post95:sulfur_unified_sum | FE = PWSID + year | cluster = PWSID\n\n")

# _bin variables are not persisted in the parquet - construct them here the
# same way run_main_tables.r does (0/100 indicator for any violation days > 0,
# NA preserved where the underlying share-days variable is NA).
mr_bin_src <- c("nitrates_MR_share_days", "arsenic_MR_share_days", "inorganic_chemicals_MR_share_days")
for (v in mr_bin_src) {
  bv <- sub("_share_days$", "_bin", v)
  full[[bv]] <- ifelse(is.na(full[[v]]), NA_integer_, as.integer(full[[v]] > 0) * 100L)
}

dset_d1 <- full[(full$minehuc_downstream_of_mine == 1) & (full$minehuc_mine == 0), ]
mr_outcomes <- c("nitrates_MR_bin", "arsenic_MR_bin", "inorganic_chemicals_MR_bin")

sensitivity_results <- list()
for (y in mr_outcomes) {
  dset_y <- dset_d1[!is.na(dset_d1[[y]]), ]

  f_with <- as.formula(paste0(y, " ~ num_facilities | PWSID + year | num_coal_mines_upstream_sum ~ post95:sulfur_unified_sum"))
  f_without <- as.formula(paste0(y, " ~ 1 | PWSID + year | num_coal_mines_upstream_sum ~ post95:sulfur_unified_sum"))

  m_with <- tryCatch(fixest::feols(f_with, data = dset_y, cluster = ~PWSID),
                      error = function(e) stop("with-control IV failed for ", y, ": ", conditionMessage(e)))
  m_without <- tryCatch(fixest::feols(f_without, data = dset_y, cluster = ~PWSID),
                         error = function(e) stop("without-control IV failed for ", y, ": ", conditionMessage(e)))

  t_with <- get_single_term(m_with, include = c("num_coal_mines_upstream_sum"))
  t_without <- get_single_term(m_without, include = c("num_coal_mines_upstream_sum"))

  pct_change <- 100 * (t_without$est - t_with$est) / t_with$est

  sensitivity_results[[y]] <- list(with = t_with, without = t_without, pct_change = pct_change)

  cat(sprintf("  %-28s  with-control est=%.4f (se=%.4f)  |  without-control est=%.4f (se=%.4f)  |  pct change in point estimate = %.2f%%\n",
              y, t_with$est, t_with$se, t_without$est, t_without$se, pct_change))
}

# -- Step 6/7/8: render table -------------------------------------------------
# fmt_num_wide() copied verbatim from run_main_tables.r (lines 317-341) so
# decimal alignment matches the rest of the paper. get_term() itself is not
# used here (we use get_single_term() above, which resolves the
# interaction-term row name without hardcoding ordering). fmt_col() from
# run_main_tables.r assumed a fixed three-term (OLS/RF/IV) column shape that
# no longer applies now that the table is a single tabular with three
# specification columns holding different numbers of terms each (one term in
# column 1, two in columns 2 and 3) - fmt_col_terms() below generalizes the
# same width-sharing logic, built on the unmodified fmt_num_wide(), to a
# variable-length list of terms per column.
fmt_num_wide <- function(est, se, pval, w, digits = 2) {
  sign_coef <- if (est < 0) "-" else "\\phantom{-}"
  num       <- sprintf(paste0("%.", digits, "f"), abs(est))
  se_num    <- sprintf(paste0("%.", digits, "f"), se)
  int_w  <- function(s) nchar(sub("\\..*$", "", s))
  pad_to <- function(s) {
    cur <- int_w(s)
    if (cur < w) paste0(strrep("\\phantom{0}", w - cur), s) else s
  }
  num    <- pad_to(num)
  se_num <- pad_to(se_num)
  stars_n <- if (is.na(pval)) 0L else if (pval < 0.01) 3L else if (pval < 0.05) 2L else if (pval < 0.1) 1L else 0L
  stars_render <- paste0(vapply(1:3, function(i) if (i <= stars_n) "*" else "\\phantom{*}", character(1)), collapse = "")
  list(
    coef = paste0("\\phantom{(}", sign_coef, num, "$^{", stars_render, "}$"),
    se   = paste0("(", "\\phantom{-}", se_num, ")\\phantom{$^{***}$}")
  )
}

fmt_col_terms <- function(terms_list, digits = 2) {
  int_w <- function(x) {
    if (is.na(x)) return(0L)
    nchar(sub("\\..*$", "", sprintf(paste0("%.", digits, "f"), abs(x))))
  }
  w <- max(sapply(terms_list, function(t) max(int_w(t$est), int_w(t$se))))
  lapply(terms_list, function(t) fmt_num_wide(t$est, t$se, t$pval, w, digits))
}

fmt_ci <- function(ci, digits = 4) {
  paste0("[", sprintf(paste0("%.", digits, "f"), ci["lo"]), ", ",
         sprintf(paste0("%.", digits, "f"), ci["hi"]), "]")
}

DIGITS <- 4

# Shared integer-digit width computed per column, across all numbers rendered
# in that column (Step 7 rule 3): column 1 has only the interaction term;
# column 2 has a sulfur-level term and an interaction term.
col1_fmt <- fmt_col_terms(list(col1_interact), digits = DIGITS)
col2_fmt <- fmt_col_terms(list(col2_main, col2_interact), digits = DIGITS)

sulfur_row_coef <- paste0("Upstream sulfur & & ", col2_fmt[[1]]$coef, " \\\\")
sulfur_row_se   <- paste0(" & & ", col2_fmt[[1]]$se, " \\\\")
interact_row_coef <- paste0("Post-1995 $\\times$ Upstream sulfur & ", col1_fmt[[1]]$coef, " & ", col2_fmt[[2]]$coef, " \\\\")
interact_row_se   <- paste0(" & ", col1_fmt[[1]]$se, " & ", col2_fmt[[2]]$se, " \\\\")
ci_row <- paste0("95\\% confidence interval & ", fmt_ci(col1_ci), " & ", fmt_ci(col2_ci), " \\\\")

# Column widths - label column plus two narrower data columns (one per
# specification), now that the table has a single tabular with only two
# short "(1)/(2)" column headers rather than sample-name headers.
n_y        <- 2
label_w_cm <- 5.5
data_w_cm  <- 2.5
label_w    <- paste0(label_w_cm, "cm")
data_w     <- paste0(data_w_cm, "cm")
col_spec   <- paste0("p{", label_w, "}",
                      paste(rep(paste0(">{\\raggedleft\\arraybackslash}p{", data_w, "}"), n_y), collapse = ""))
header_row <- " & (1) & (2) \\\\"

# Physical width check (matches run_main_tables.r's multi-panel convention):
# scale via adjustbox only if the natural width exceeds the text width.
tabcolsep_pt    <- 4
cm_per_pt       <- 2.54 / 72.27
textwidth_cm    <- 16.51
intercol_pad_cm <- 2 * (n_y + 1) * tabcolsep_pt * cm_per_pt
natural_w_cm    <- label_w_cm + n_y * data_w_cm + intercol_pad_cm
needs_scale     <- natural_w_cm > textwidth_cm
total_w         <- if (needs_scale) "\\linewidth" else paste0(round(natural_w_cm, 4), "cm")

mean_str     <- sprintf("%.3f", mean_f)
mean_bal_str <- sprintf("%.3f", mean(dset_bal$num_facilities, na.rm = TRUE))
n_change_str     <- format(n_change, big.mark = ",")
n_change_bal_str <- format(n_change_bal, big.mark = ",")

tabular_lines <- c(
  paste0("\\begin{tabular}{", col_spec, "}"),
  "\\hline\\hline",
  header_row,
  "\\hline",
  sulfur_row_coef,
  sulfur_row_se,
  interact_row_coef,
  interact_row_se,
  ci_row,
  "\\hline",
  paste0("Utility fixed effects & $\\checkmark$ & \\\\"),
  paste0("Year fixed effects & $\\checkmark$ & $\\checkmark$ \\\\"),
  paste0("Balanced panel & & $\\checkmark$ \\\\"),
  paste0("Mean number of intake facilities & ", mean_str, " & ", mean_bal_str, " \\\\"),
  paste0("Utilities with a change in intake facilities & ", n_change_str, " & ", n_change_bal_str, " \\\\"),
  paste0("Utilities & ", format(n_cws_col1, big.mark = ","), " & ", format(n_cws_col2, big.mark = ","), " \\\\"),
  paste0("Observations & ", format(n_obs_col1, big.mark = ","), " & ", format(n_obs_col2, big.mark = ","), " \\\\"),
  "\\hline\\hline",
  "\\end{tabular}"
)

if (needs_scale) {
  tab_start <- grep("^\\\\begin\\{tabular\\}", tabular_lines)[1]
  tab_end   <- max(grep("^\\\\end\\{tabular\\}", tabular_lines))
  tabular_lines <- c(
    tabular_lines[seq_len(tab_start - 1)],
    "\\begin{adjustbox}{max width=\\linewidth}",
    tabular_lines[tab_start:tab_end],
    "\\end{adjustbox}",
    if (tab_end < length(tabular_lines)) tabular_lines[(tab_end + 1):length(tabular_lines)] else NULL
  )
}

caption_title <- "Instrument balance: coal sulfur exposure after 1995 and the number of intake facilities at utilities"

note_text <- paste0(
  "\\textit{Notes:} The dependent variable is the number of active intake facilities operated by ",
  "the utility. The instrument is an indicator for the post-1995 period interacted with the sum of ",
  "coal sulfur content across upstream watersheds. The sample is community water systems at most one ",
  "watershed downstream of a coal mine. Coal sulfur content is fixed for a given utility over the ",
  "sample period, and the number of intake facilities changes for very few utilities. The panel of ",
  "utilities observed each year is unbalanced, since utilities enter and leave the sample over time; ",
  "a post-1995 interaction identified from differences across utilities can therefore reflect a ",
  "change in which utilities are observed in each period rather than a genuine change at any given ",
  "utility. The final column addresses this by restricting to utilities observed in every year of ",
  "the sample period. Standard errors, clustered at the utility level, are shown in ",
  "parentheses below each coefficient. Sample period 1985--2005. *** p$<$0.01, ** p$<$0.05, * p$<$0.1."
)

table_lines <- c(
  "\\begin{table}[htbp]",
  "\\raggedright",
  paste0("\\begin{minipage}{", total_w, "}"),
  paste0("\\caption{\\label{exclusion_test_num_facilities} ", caption_title, "}"),
  "\\end{minipage}",
  "\\small",
  "{\\setlength{\\tabcolsep}{4pt}%",
  tabular_lines,
  "}",
  paste0("\\begin{minipage}{", total_w, "}"),
  "\\vspace{4pt}",
  "\\footnotesize",
  "\\raggedright",
  note_text,
  "\\end{minipage}",
  "\\end{table}"
)

out_path <- "Z:/ek559/mining_wq/output/reg/exclusion_test_num_facilities.tex"
writeLines(table_lines, out_path)
cat("\nTable written to:", out_path, "\n")

cat("\n================ Done ================\n")
