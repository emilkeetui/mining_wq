# ============================================================
# Script: run_k2_6yr_tables.r
# Purpose: SYR2 6-Year Review concentration exhibits for the k=2 A-full
#          main arm: OLS effect of cumulative upstream coal production on
#          mean measured concentration (arsenic/nitrate/barium/selenium),
#          reported as one-step-upstream vs. two-step-upstream dose columns
#          on the same k2 sample to show dose-distance decay; summary
#          statistics, a balance test of utility characteristics against
#          dose, and an SYR2-reporting-status violation-rate comparison.
#          The grid instrument is degenerate on this sample (post95 is
#          identically 1 on every non-missing VALUE obs <= 2005), so these
#          report OLS (matching run_step_top3_outcomes.r's
#          build_dose_sample(2)/fml_state, which reproduces the published
#          k=1 anchor). FE: PWSID + huc02^year, matching the published k=1
#          table. Sources k2_common.r.
# Inputs:
#   clean_data/cws_data/step_instruments.parquet (via k2_common.r)
#   clean_data/cws_6year_review_ravalli.parquet
#   clean_data/cws_data/pwsid_huc02.parquet
#   clean_data/cws_data/cws_geopop_annual.parquet
#   clean_data/cws_data/prod_vio_sulfur.parquet (main 2SLS sample, read-only,
#     for syr2_mr_comparison_k2's SYR2-reporting-status comparison)
#   clean_data/cws_6year_review.parquet (SYR2 reporting-status universe)
# Outputs:
#   output/reg/6yr_huc02fe_inorg_ravalli_2005_k2.tex (+ _present.tex)
#   output/sum/6yr_huc02fe_inorg_val_sumstats_ravalli_2005_k2.tex (+ _present.tex)
#   output/reg/pt_balance_6yr_k2.tex
#   output/sum/syr2_mr_comparison_k2.tex (+ _present.tex)
# Author: EK  Date: 2026-09-16
# ============================================================

source("Z:/ek559/mining_wq/code/coal_mining_water_quality/k2_common.r")
library(tidyr)

main_dat <- build_k2_panel("main")

si <- read_parquet(file.path(ROOT, "clean_data/cws_data/step_instruments.parquet"))
stopifnot(is.character(si$PWSID))

d6r <- read_parquet(file.path(ROOT, "clean_data/cws_6year_review_ravalli.parquet"))
stopifnot(is.character(d6r$PWSID), "STATE_CODE" %in% names(d6r))
d6r <- d6r %>% dplyr::filter(year >= 1985, PWSID != "WV3303401")

# huc02 lookup, joined in so the k2 table can use the same PWSID + huc02^year
# FE as the published k=1 table (cws_6year_review_huc02fe.r:91-105), rather
# than the coarser STATE_CODE^year stand-in used elsewhere in this script for
# the RF/2SLS grid specs (where the instrument is degenerate on this sample).
huc02_lookup <- read_parquet(file.path(ROOT, "clean_data/cws_data/pwsid_huc02.parquet"))
stopifnot(is.character(huc02_lookup$PWSID), is.character(huc02_lookup$huc02))
d6r <- d6r %>% dplyr::left_join(huc02_lookup %>% dplyr::select(PWSID, huc02), by = "PWSID")
cat("Rows with missing huc02 after merge:", sum(is.na(d6r$huc02)), "\n")

CHEMS <- c("arsenic", "nitrate", "barium", "selenium")
nice_chem <- c(arsenic = "Arsenic", nitrate = "Nitrate", barium = "Barium", selenium = "Selenium")

# ── build_dose_sample(): k-step upstream cumulative dose, verbatim logic
# from run_step_top3_outcomes.r:112-140 (already-validated OLS construction
# that reproduces the published k=1 anchor), generalized to let the dose
# regressor be built from a different flow-step depth than the one that
# defines the estimation sample (dose-distance decay comparison, plan
# k2-dose-distance-columns.md Step 1). `sample_k` selects the utility-year
# rows (via the A2 intake-purity screen, unchanged); `dose_k` selects which
# k's cumulative production feeds the regressor. When `dose_k == sample_k`
# this is exactly the original single-k behavior. ────────────────────────
build_dose_sample <- function(sample_k, dose_k = sample_k) {
  arm_k <- si %>% dplyr::filter(arm == "main", k == sample_k, n_mine_hucs_linked >= 1) %>%
    apply_a2() %>%
    dplyr::select(PWSID, year, production_linked_sum)

  linked_pwsids <- unique(arm_k$PWSID)
  d <- d6r %>% dplyr::filter(PWSID %in% linked_pwsids, CHEMID_name %in% CHEMS)

  if (dose_k == sample_k) {
    dose_src <- arm_k
  } else {
    dose_src <- arm_k %>% dplyr::select(PWSID, year) %>%
      dplyr::left_join(
        si %>% dplyr::filter(arm == "main", k == dose_k) %>%
          dplyr::select(PWSID, year, production_linked_sum),
        by = c("PWSID", "year")
      )
  }

  cum_panel <- dose_src %>%
    dplyr::distinct(PWSID, year, production_linked_sum) %>%
    dplyr::arrange(PWSID, year) %>%
    dplyr::group_by(PWSID) %>%
    dplyr::mutate(coal_prod_upstream_cumsum =
             cumsum(replace(production_linked_sum, is.na(production_linked_sum), 0))) %>%
    dplyr::ungroup() %>%
    dplyr::select(PWSID, year, coal_prod_upstream_cumsum)

  d <- d %>% dplyr::inner_join(cum_panel, by = c("PWSID", "year"))

  chk <- d %>% dplyr::distinct(PWSID, year, coal_prod_upstream_cumsum) %>%
    dplyr::arrange(PWSID, year) %>% dplyr::group_by(PWSID) %>%
    dplyr::mutate(diff = coal_prod_upstream_cumsum - dplyr::lag(coal_prod_upstream_cumsum))
  stopifnot(all(chk$diff >= 0 | is.na(chk$diff)))

  d$coal_prod_upstream_cumsum_10mst <- d$coal_prod_upstream_cumsum / 1e7
  d <- d[!is.na(d$VALUE), ]
  d <- d[d$year <= 2005, ]
  d
}

dose2    <- build_dose_sample(2)              # unchanged; still used by sumstats + balance sections
dose2_k1 <- build_dose_sample(2, dose_k = 1)  # same rows, one-step dose

stopifnot(nrow(dose2) == nrow(dose2_k1))
key_cols <- c("PWSID", "year", "CHEMID_name", "VALUE")
dose2_sorted    <- dose2[order(dose2$PWSID, dose2$year, dose2$CHEMID_name), key_cols]
dose2_k1_sorted <- dose2_k1[order(dose2_k1$PWSID, dose2_k1$year, dose2_k1$CHEMID_name), key_cols]
rownames(dose2_sorted) <- NULL; rownames(dose2_k1_sorted) <- NULL
stopifnot(identical(dose2_sorted, dose2_k1_sorted))

dose2_10        <- dose2[order(dose2$PWSID, dose2$year, dose2$CHEMID_name), ]$coal_prod_upstream_cumsum_10mst
dose2_k1_10     <- dose2_k1[order(dose2_k1$PWSID, dose2_k1$year, dose2_k1$CHEMID_name), ]$coal_prod_upstream_cumsum_10mst
stopifnot(all(dose2_k1_10 <= dose2_10 + 1e-9))
cat(sprintf("One-step dose is zero for %.1f%% of rows (%d of %d)\n",
            100 * mean(dose2_k1_10 == 0), sum(dose2_k1_10 == 0), length(dose2_k1_10)))
n_a2_main_k2 <- dplyr::n_distinct(main_dat$PWSID)
cat(sprintf("k2 dose sample: %d rows, %d utilities, %d distinct chemicals\n",
            nrow(dose2), dplyr::n_distinct(dose2$PWSID), dplyr::n_distinct(dose2$CHEMID_name)))
cat(sprintf("Coverage: %d of %d k2 main-arm utilities have SYR2 concentration coverage (%.1f%%)\n",
            dplyr::n_distinct(dose2$PWSID), n_a2_main_k2,
            100 * dplyr::n_distinct(dose2$PWSID) / n_a2_main_k2))

fml_huc02 <- VALUE ~ coal_prod_upstream_cumsum_10mst + num_facilities | PWSID + huc02^year

# ── 6yr_huc02fe_inorg_ravalli_2005_k2.tex ────────────────────────────────
# 8 columns: within-one-flow-step dose (1-4) then within-two-flow-step dose
# (5-8), each x {arsenic, nitrate, barium, selenium}, same k2 sample rows
# throughout -- only the dose regressor's source k differs (plan
# k2-dose-distance-columns.md Step 2, dose-distance decay comparison).
dose_list  <- list(one = dose2_k1, two = dose2)
models_val <- list()
hdr_val    <- character(0)
for (dose_name in names(dose_list)) {
  dose_df <- dose_list[[dose_name]]
  for (chem in CHEMS) {
    d_chem <- dose_df[dose_df$CHEMID_name == chem, ]
    cat("  Dose:", dose_name, "| Chemical:", chem, "| n rows:", nrow(d_chem), "\n")
    if (nrow(d_chem) < 30) { cat("  Skipping -- too few obs.\n"); next }
    m <- tryCatch(fixest::feols(fml_huc02, data = d_chem, cluster = ~PWSID, warn = FALSE, notes = FALSE),
                  error = function(e) { cat("  ERROR:", conditionMessage(e), "\n"); NULL })
    if (!is.null(m)) {
      models_val <- c(models_val, list(m))
      hdr_val    <- c(hdr_val, nice_chem[[chem]])
      cat("  n =", m$nobs, "| coef =", round(coef(m)["coal_prod_upstream_cumsum_10mst"], 4), "\n")
    }
  }
}
stopifnot(length(models_val) == 8)  # 2 dose defs x {arsenic, nitrate, barium, selenium}, all survive

# Panel layout (rather than side-by-side column groups): Panel A = within-
# one-flow-step dose, Panel B = within-two-flow-step dose, each x {arsenic,
# nitrate, barium, selenium}. Each panel is rendered by its own etable()
# call (so column numbering and the adjustbox scale independently per
# panel), then the two adjustbox+tabular blocks are stacked inside a single
# table float -- adjustbox inside the float around each panel's tabular
# individually, per CLAUDE.md's multi-panel-table nesting convention.
extract_adjustbox <- function(tex_lines) {
  x <- paste(tex_lines, collapse = "\n")
  start_pos <- regexpr("\\\\begin\\{adjustbox\\}", x)
  end_pos   <- regexpr("\\\\end\\{adjustbox\\}", x)
  end_full  <- end_pos + attr(end_pos, "match.length") - 1
  substr(x, start_pos, end_full)
}

insert_panel_title <- function(tex_str, n_col, panel_label) {
  lines   <- strsplit(tex_str, "\n")[[1]]
  mid_idx <- which(trimws(lines) == "\\midrule")[1]
  title_line <- paste0("      \\multicolumn{", n_col + 1, "}{l}{\\textbf{", panel_label, "}} \\\\")
  c(lines[seq_len(mid_idx)], title_line, lines[(mid_idx + 1):length(lines)])
}

panel_tabular <- function(models_grp) {
  raw <- etable(
    models_grp,
    headers      = list(":_:" = unname(nice_chem[CHEMS])),
    depvar       = FALSE,
    fitstat      = ~n,
    style.tex    = style.tex("aer", adjustbox = TRUE),
    tex          = TRUE,
    digits       = "r4",
    drop         = "Number of intake facilities",
    drop.section = "fixef",
    dict         = k2_dict
  )
  extract_adjustbox(raw)
}

panel_a_lines <- insert_panel_title(panel_tabular(models_val[1:4]), 4, "Panel A: Within one HUC12 upstream")
panel_b_lines <- insert_panel_title(panel_tabular(models_val[5:8]), 4, "Panel B: Within two HUC12 upstream")

reg_title <- "Effect of cumulative upstream coal production on inorganic chemicals by upstream distance, SYR2 1998--2005"
reg_label <- "tab:6yr_huc02fe_inorg_ravalli_2005_k2"

build_two_panel_table <- function(panel_a, panel_b, title, label, notes, out_path) {
  lines <- c(
    "\\begin{table}[htbp]",
    "   ",
    paste0("   \\caption{\\label{", label, "} ", title, "}"),
    "   \\bigskip",
    "   ",
    "   \\centering",
    "   ",
    panel_a,
    "   ",
    "   \\bigskip",
    "   ",
    panel_b,
    "   ",
    "   {\\tiny\\linespread{1}\\selectfont \\par \\raggedright ",
    paste0("   ", notes, "}"),
    "   ",
    "\\end{table}",
    "",
    ""
  )
  writeLines(lines, out_path)
}

note_reg <- paste0(
  "\\textit{Notes:} Within each chemical, the column shows mean measured concentration ",
  "from the EPA 6-Year Review. Non-detect values replaced by MDL$/\\sqrt{2}$ following ",
  "Ravalli et al.~(2022). Explanatory variable is cumulative coal production since 1985 ",
  "(in 10 million short tons) in watersheds within one flow step upstream of the ",
  "utility's intake (Panel A) or within two flow steps upstream (Panel B). ",
  "Sample: utilities with a coal mine within two flow steps upstream of their intake ",
  "and no coal mine colocated with their intake. Standard errors clustered at the ",
  "utility level. All specifications include utility and HUC02 $\\times$ year fixed ",
  "effects. *** p$<$0.01, ** p$<$0.05, * p$<$0.1."
)
out_reg <- "Z:/ek559/mining_wq/output/reg/6yr_huc02fe_inorg_ravalli_2005_k2.tex"
build_two_panel_table(panel_a_lines, panel_b_lines, reg_title, reg_label, note_reg, out_reg)
cat("Written:", out_reg, "\n")

# Presentation companion: same table body, notes = FE sentence + clustering +
# stars only (table has no FE checkmark rows -- drop.section = "fixef") --
# .claude/logs/2026-08-31-presentation-notes-tables.md.
note_reg_present <- paste0(
  "\\textit{Notes:} All specifications include utility and HUC02 $\\times$ year ",
  "fixed effects. Standard errors clustered at the utility level. ",
  "*** p$<$0.01, ** p$<$0.05, * p$<$0.1."
)
out_reg_present <- sub("\\.tex$", "_present.tex", out_reg)
build_two_panel_table(panel_a_lines, panel_b_lines, reg_title, reg_label, note_reg_present, out_reg_present)
cat("Written:", out_reg_present, "\n")

# ── 6yr_huc02fe_inorg_val_sumstats_ravalli_2005_k2.tex ───────────────────
mcl_labels <- c(
  "arsenic"  = "Pre-2006: 0.050 mg/L, 2006+: 0.010 mg/L",
  "nitrate"  = "10.0 mg/L",
  "barium"   = "2.000 mg/L",
  "selenium" = "0.050 mg/L"
)
mcl_values <- c("nitrate" = 10.000, "barium" = 2.000, "selenium" = 0.050)
mcl_value_for <- function(chem, year) {
  if (chem == "arsenic") return(ifelse(year <= 2005, 0.050, 0.010))
  rep(unname(mcl_values[[chem]]), length(year))
}

build_sumstats_k2 <- function(df_subset) {
  sum_rows <- list(); coal_list <- list()
  for (chem in CHEMS) {
    d_s <- df_subset[df_subset$CHEMID_name == chem, ]
    if (nrow(d_s) == 0) next
    keep_s <- stats::complete.cases(d_s[, c("VALUE", "VALUE_max", "coal_prod_upstream_cumsum_10mst",
                                             "num_facilities", "STATE_CODE", "year", "PWSID")])
    d_reg_s <- d_s[keep_s, ]
    if (nrow(d_reg_s) == 0) next
    near_mcl_share <- {
      half_mcl <- 0.5 * mcl_value_for(chem, d_reg_s$year)
      mean(d_reg_s$VALUE > half_mcl, na.rm = TRUE)
    }
    sum_rows[[chem]] <- data.frame(
      variable = paste0(nice_chem[[chem]], " (mg/L)"), mcl_label = mcl_labels[[chem]],
      mean_val = mean(d_reg_s$VALUE, na.rm = TRUE), max_val = max(d_reg_s$VALUE_max, na.rm = TRUE),
      sd_val = sd(d_reg_s$VALUE, na.rm = TRUE), n_obs = nrow(d_reg_s), near_mcl = near_mcl_share,
      stringsAsFactors = FALSE
    )
    coal_list[[chem]] <- d_reg_s[, c("PWSID", "year", "coal_prod_upstream_cumsum_10mst")]
  }
  if (length(coal_list) == 0) return(list(sum_df = NULL, coal_df = NULL))
  coal_df <- unique(do.call(rbind, coal_list))
  coal_df <- coal_df[!duplicated(coal_df[, c("PWSID", "year")]), ]
  list(sum_df = do.call(rbind, sum_rows), coal_df = coal_df)
}

panel_a_ss  <- build_sumstats_k2(dose2)
sum_df_a_ss <- panel_a_ss$sum_df
median_cum_prod <- median(panel_a_ss$coal_df$coal_prod_upstream_cumsum_10mst, na.rm = TRUE)
dose2_above <- dose2[dose2$coal_prod_upstream_cumsum_10mst > median_cum_prod, ]
panel_b_ss  <- build_sumstats_k2(dose2_above)
sum_df_b_ss <- panel_b_ss$sum_df

fmt_num_ss <- function(x) if (is.na(x)) "---" else sprintf("%.4f", x)
fmt_n_ss   <- function(x) formatC(x, format = "d", big.mark = ",")
fmt_pct_ss <- function(x) if (is.na(x)) "---" else sprintf("%.1f\\%%", 100 * x)

note_ss <- paste(c(
  "\\textit{Notes:} SYR2 sample from 1998--2005.",
  "``Near MCL'' is the share of utility-year mean concentrations exceeding 50\\% of the applicable MCL.",
  paste0("Panel B restricts Panel A's sample to utility-year observations with cumulative upstream coal production above the sample median of ", fmt_num_ss(median_cum_prod), " (10M ST).")
), collapse = " ")

col_spec_ss <- paste0(
  ">{\\raggedright\\arraybackslash}p{4.4cm}", ">{\\raggedright\\arraybackslash}p{3.6cm}",
  ">{\\raggedleft\\arraybackslash}p{1.3cm}", ">{\\raggedleft\\arraybackslash}p{1.3cm}",
  ">{\\raggedleft\\arraybackslash}p{1.3cm}", ">{\\raggedleft\\arraybackslash}p{1.15cm}",
  ">{\\raggedleft\\arraybackslash}p{1.3cm}"
)
header_row_ss <- "Variable & MCL & Mean & Max & Std.\\ Dev. & $N$ & Near MCL \\\\"
make_ss_row <- function(r) {
  paste0("         ", r$variable, " & ", r$mcl_label, " & ", fmt_num_ss(r$mean_val), " & ",
         fmt_num_ss(r$max_val), " & ", fmt_num_ss(r$sd_val), " & ", fmt_n_ss(r$n_obs), " & ",
         fmt_pct_ss(r$near_mcl), " \\\\")
}

panel_a_lines_ss <- c(
  "   \\begin{adjustbox}{width = 0.9\\textwidth, center}",
  paste0("      \\begin{tabular}{", col_spec_ss, "}"),
  "         \\toprule",
  paste0("         ", header_row_ss),
  "         \\midrule",
  "         \\multicolumn{7}{l}{\\textbf{Panel A: Full sample}} \\\\",
  vapply(seq_len(nrow(sum_df_a_ss)), function(i) make_ss_row(sum_df_a_ss[i, ]), character(1)),
  "         \\bottomrule",
  "      \\end{tabular}",
  "   \\end{adjustbox}"
)
panel_b_lines_ss <- c(
  "   \\bigskip",
  "   \\begin{adjustbox}{width = 0.9\\textwidth, center}",
  paste0("      \\begin{tabular}{", col_spec_ss, "}"),
  "         \\multicolumn{7}{l}{\\textbf{Panel B: Utility exposed to above median cumulative tons of coal extraction}} \\\\",
  vapply(seq_len(nrow(sum_df_b_ss)), function(i) make_ss_row(sum_df_b_ss[i, ]), character(1)),
  "         \\bottomrule",
  "      \\end{tabular}",
  "   \\end{adjustbox}"
)

tex_ss <- c(
  "", "\\begin{table}[htbp]",
  paste0("   \\caption{\\label{tab:6yr_huc02fe_inorg_val_sumstats_ravalli_2005_k2} Utility contaminant concentrations (1998-2005) and cumulative upstream coal production exposure (since 1985), two-step upstream watershed linkage}"),
  "   \\bigskip", "   \\centering",
  panel_a_lines_ss, panel_b_lines_ss,
  "   \\begin{minipage}{\\linewidth}", "   \\vspace{4pt}",
  paste0("   {\\tiny\\linespread{1}\\selectfont\\raggedright ", note_ss, "}"),
  "   \\end{minipage}", "\\end{table}", ""
)
out_ss <- "Z:/ek559/mining_wq/output/sum/6yr_huc02fe_inorg_val_sumstats_ravalli_2005_k2.tex"
writeLines(tex_ss, out_ss)
cat("Written:", out_ss, "\n")

# Presentation companion: same table body, trailing notes minipage dropped
# entirely (summary statistics carry no clustering/FE/stars) --
# .claude/logs/2026-08-31-presentation-notes-tables.md.
tex_ss_present <- c(
  "", "\\begin{table}[htbp]",
  paste0("   \\caption{\\label{tab:6yr_huc02fe_inorg_val_sumstats_ravalli_2005_k2} Utility contaminant concentrations (1998-2005) and cumulative upstream coal production exposure (since 1985), two-step upstream watershed linkage}"),
  "   \\bigskip", "   \\centering",
  panel_a_lines_ss, panel_b_lines_ss,
  "\\end{table}", ""
)
out_ss_present <- sub("\\.tex$", "_present.tex", out_ss)
writeLines(tex_ss_present, out_ss_present)
cat("Written:", out_ss_present, "\n")

# ── pt_balance_6yr_k2.tex ─────────────────────────────────────────────────
# Cross-sectional balance test: dose (cumulative upstream production by
# 2005) regressed on pre-determined utility characteristics, on the k2 dose
# sample. Ports pt_diagnostics_6yr.r Part A, with huc02 FE swapped for
# STATE_CODE FE and the fixed one-step downstream sample swapped for the k2
# arm-k cumulative-dose panel.
arm_k2_cum <- si %>% dplyr::filter(arm == "main", k == 2, n_mine_hucs_linked >= 1) %>%
  dplyr::select(PWSID, year, production_linked_sum) %>%
  dplyr::distinct(PWSID, year, production_linked_sum) %>%
  dplyr::arrange(PWSID, year) %>%
  dplyr::group_by(PWSID) %>%
  dplyr::mutate(coal_prod_upstream_cumsum =
           cumsum(replace(production_linked_sum, is.na(production_linked_sum), 0))) %>%
  dplyr::ungroup()

dose_cs <- arm_k2_cum %>%
  dplyr::filter(PWSID %in% unique(dose2$PWSID)) %>%
  dplyr::mutate(prod_ann = replace(production_linked_sum, is.na(production_linked_sum), 0)) %>%
  dplyr::group_by(PWSID) %>%
  dplyr::summarise(
    dose_10mst      = sum(prod_ann[year >= 1985 & year <= 2005]) / 1e7,
    dose_post_10mst = sum(prod_ann[year >= 1998 & year <= 2005]) / 1e7,
    dose_pre_10mst  = sum(prod_ann[year >= 1985 & year <= 1997]) / 1e7,
    .groups = "drop"
  ) %>%
  dplyr::mutate(any_dose = as.integer(dose_10mst > 0), any_dose_post = as.integer(dose_post_10mst > 0))

geopop <- read_parquet(file.path(ROOT, "clean_data/cws_data/cws_geopop_annual.parquet"))
pop97 <- geopop %>% dplyr::filter(year == 1997) %>% dplyr::select(PWSID, geopop_hat) %>%
  dplyr::mutate(log_pop_1997 = log(pmax(geopop_hat, 1))) %>% dplyr::select(PWSID, log_pop_1997)

syr2_chars <- dose2 %>%
  dplyr::arrange(PWSID, year) %>%
  dplyr::group_by(PWSID) %>%
  dplyr::summarise(
    STATE_CODE        = dplyr::first(STATE_CODE),
    num_facilities     = dplyr::first(num_facilities),
    num_hucs           = dplyr::first(num_hucs),
    pop_served_syr2    = dplyr::first(POPULATION_SERVED_COUNT),
    surface_water      = as.integer(dplyr::first(PRIMARY_SOURCE_CODE) %in% c("SW", "SWP")),
    owner_public       = as.integer(dplyr::first(OWNER_TYPE_CODE) %in% c("L", "M", "F", "S")),
    is_wholesaler      = as.integer(dplyr::first(IS_WHOLESALER_IND) == "Y"),
    source_protected   = as.integer(dplyr::first(SOURCE_WATER_PROTECTION_CODE) == "Y"),
    .groups = "drop"
  ) %>%
  dplyr::mutate(log_pop_syr2 = log(pmax(pop_served_syr2, 1)))

bal <- dose_cs %>% dplyr::left_join(pop97, by = "PWSID") %>% dplyr::left_join(syr2_chars, by = "PWSID")
cat(sprintf("\nBalance sample utilities: %d (with 1997 backcast pop: %d)\n",
            nrow(bal), sum(!is.na(bal$log_pop_1997))))

RHS_BAL <- "log_pop_1997 + log_pop_syr2 + num_facilities + num_hucs + surface_water + owner_public + is_wholesaler + source_protected"
fml_bal_1 <- as.formula(paste0("dose_post_10mst ~ ", RHS_BAL))
fml_bal_2 <- as.formula(paste0("any_dose_post   ~ ", RHS_BAL))
fml_bal_3 <- as.formula(paste0("dose_post_10mst ~ ", RHS_BAL, " | STATE_CODE"))
fml_bal_4 <- as.formula(paste0("any_dose_post   ~ ", RHS_BAL, " | STATE_CODE"))

m_bal <- list(
  fixest::feols(fml_bal_1, data = bal, vcov = "hetero", warn = FALSE, notes = FALSE),
  fixest::feols(fml_bal_2, data = bal, vcov = "hetero", warn = FALSE, notes = FALSE),
  fixest::feols(fml_bal_3, data = bal, vcov = "hetero", warn = FALSE, notes = FALSE),
  fixest::feols(fml_bal_4, data = bal, vcov = "hetero", warn = FALSE, notes = FALSE)
)

wald_f <- character(0); wald_p <- character(0)
for (i in seq_along(m_bal)) {
  w <- tryCatch(
    fixest::wald(m_bal[[i]], keep = "log_pop|num_|surface_water|owner_public|is_wholesaler|source_protected", print = FALSE),
    error = function(e) NULL
  )
  if (!is.null(w)) {
    wald_f <- c(wald_f, format(round(w$stat, 2), nsmall = 2))
    wald_p <- c(wald_p, format(round(w$p, 3), nsmall = 3))
  } else {
    wald_f <- c(wald_f, "---"); wald_p <- c(wald_p, "---")
  }
}

dict_bal <- c(k2_dict,
  dose_10mst       = "Dose 1985--2005 (10M ST)",
  dose_post_10mst  = "Dose 1998--2005 (10M ST)",
  dose_pre_10mst   = "Dose 1985--1997 (10M ST)",
  any_dose         = "Any upstream mining",
  any_dose_post    = "Any mining 1998--2005",
  log_pop_1997     = "Log backcast pop. 1997",
  log_pop_syr2     = "Log pop. served (SYR2)",
  num_hucs         = "Num. source HUC12s",
  surface_water    = "Surface water source",
  owner_public     = "Public ownership",
  is_wholesaler    = "Wholesaler",
  source_protected = "Source water protection",
  STATE_CODE       = "State"
)

note_bal <- paste0(
  "\\textit{Notes:} Covariates differ in timing, and only population pre-dates the dose ",
  "window. Backcast population served in 1997 is constructed from decennial census ",
  "geography and interpolated between the 1990 and 2000 census anchors; it is ",
  "therefore dated before 1998 by construction but is not an observed 1997 ",
  "measurement. The remaining covariates (population served, number of intake ",
  "facilities, number of source HUC12s, primary source type, ownership, wholesaler ",
  "status, and source water protection) are drawn from the SDWIS/SYR2 inventory and ",
  "are recorded contemporaneously with the dose window. Heteroskedasticity-robust ",
  "standard errors. Sample: utilities with a coal mine within two flow steps upstream ",
  "of their intake and no coal mine colocated with their intake, 1998--2005. ",
  "*** p$<$0.01, ** p$<$0.05, * p$<$0.1."
)

col_order  <- c(1, 3, 2, 4)
m_bal_ord  <- m_bal[col_order]
wald_f_ord <- wald_f[col_order]
wald_p_ord <- wald_p[col_order]

postprocess_bal_k2 <- function(x) {
  x <- move_notes_below_adjustbox(x)
  x <- right_align_tabular(x)
  lines <- strsplit(paste(x, collapse = "\n"), "\n")[[1]]
  is_numrow <- function(line) {
    cells <- strsplit(line, "&", fixed = TRUE)[[1]]
    cells <- trimws(gsub("\\\\\\\\.*$", "", cells))
    cells <- cells[cells != ""]
    length(cells) > 0 && all(grepl("^\\(\\d+\\)$", cells))
  }
  idx <- which(vapply(lines, is_numrow, logical(1)))
  for (i in idx) lines[i] <- gsub("(\\(\\d+\\))", "\\\\multicolumn{1}{c}{\\1}", lines[i])
  paste(lines, collapse = "\n")
}

out_bal <- "Z:/ek559/mining_wq/output/reg/pt_balance_6yr_k2.tex"
etable(
  m_bal_ord,
  headers = list(" " = list("Cumul. upstream coal prod. (10M ST)" = 2, "Any upstream coal mining" = 2)),
  depvar = FALSE,
  fitstat = ~ n,
  extralines = list(
    "Joint $F$-test (all covariates)" = wald_f_ord,
    "\\hspace{1em} $p$-value"         = wald_p_ord
  ),
  style.tex = style.tex("aer", adjustbox = TRUE),
  tex = TRUE,
  digits = "r4",
  title = "Balance test of utility characteristics and upstream coal production 1998--2005, two-step upstream watershed linkage",
  label = "tab:pt_balance_6yr_k2",
  dict = dict_bal,
  notes = note_bal,
  postprocess.tex = postprocess_bal_k2,
  file = out_bal, replace = TRUE
)
cat("Written:", out_bal, "\n")

# ── syr2_mr_comparison_k2.tex ────────────────────────────────────────────
# Compare MR/MCL violation rates between utilities with and without SYR2
# readings for target inorganic chemicals, on the k2 main-arm panel. Ports
# syr2_mr_comparison.r, with the fixed downstream 2SLS panel swapped for
# the k2 main-arm panel and the raw `_share` incidence vars swapped for the
# already-built `_bin` (0/100) indicators (equivalent: both test
# share/share_days > 0).
syr2_raw <- read_parquet(file.path(ROOT, "clean_data/cws_6year_review.parquet"))
target_chems <- c("arsenic", "nitrate", "selenium", "barium")

pws_with_readings <- syr2_raw %>%
  dplyr::filter(CHEMID_name %in% target_chems, !is.na(num_measurements) & num_measurements > 0) %>%
  dplyr::distinct(PWSID) %>% dplyr::pull(PWSID)
states_with_readings <- syr2_raw %>% dplyr::filter(PWSID %in% pws_with_readings) %>%
  dplyr::distinct(STATE_CODE) %>% dplyr::pull(STATE_CODE)
cat(sprintf("\nGroup 1 utilities (has target-chemical SYR2 reading): %d\n", length(pws_with_readings)))

pwsid_state <- main_dat %>% dplyr::distinct(PWSID, STATE_CODE)

group_assign <- pwsid_state %>%
  dplyr::mutate(group = dplyr::case_when(
    PWSID %in% pws_with_readings ~ 1L,
    STATE_CODE %in% states_with_readings & !(PWSID %in% pws_with_readings) ~ 2L,
    TRUE ~ NA_integer_
  )) %>% dplyr::filter(!is.na(group))
cat(sprintf("Group 1: %d utilities | Group 2: %d utilities\n",
            sum(group_assign$group == 1), sum(group_assign$group == 2)))

panel_grp <- main_dat %>% dplyr::inner_join(group_assign %>% dplyr::select(PWSID, group), by = "PWSID")
panel_grp <- panel_grp %>% dplyr::mutate(
  any_mr  = (nitrates_MR_bin > 0 | arsenic_MR_bin > 0 | inorganic_chemicals_MR_bin > 0),
  any_mcl = (nitrates_MCL_bin > 0 | arsenic_MCL_bin > 0 | inorganic_chemicals_MCL_bin > 0),
  vio_count = as.integer(arsenic_MR_bin > 0) + as.integer(nitrates_MR_bin > 0) + as.integer(inorganic_chemicals_MR_bin > 0) +
              as.integer(arsenic_MCL_bin > 0) + as.integer(nitrates_MCL_bin > 0) + as.integer(inorganic_chemicals_MCL_bin > 0)
)

pws_outcomes <- panel_grp %>% dplyr::group_by(PWSID, group) %>%
  dplyr::summarise(
    ever_mr_9705  = as.integer(any(any_mr  & year >= 1997 & year <= 2005, na.rm = TRUE)),
    ever_mr_8505  = as.integer(any(any_mr  & year >= 1985 & year <= 2005, na.rm = TRUE)),
    ever_mcl_9705 = as.integer(any(any_mcl & year >= 1997 & year <= 2005, na.rm = TRUE)),
    ever_mcl_8505 = as.integer(any(any_mcl & year >= 1985 & year <= 2005, na.rm = TRUE)),
    mean_num_vio_9705 = mean(vio_count[year >= 1997 & year <= 2005], na.rm = TRUE),
    mean_num_vio_8505 = mean(vio_count[year >= 1985 & year <= 2005], na.rm = TRUE),
    .groups = "drop"
  )

group_means <- pws_outcomes %>% dplyr::group_by(group) %>%
  dplyr::summarise(
    n_cws = dplyr::n(),
    ever_mr_9705 = mean(ever_mr_9705, na.rm = TRUE), ever_mr_8505 = mean(ever_mr_8505, na.rm = TRUE),
    ever_mcl_9705 = mean(ever_mcl_9705, na.rm = TRUE), ever_mcl_8505 = mean(ever_mcl_8505, na.rm = TRUE),
    mean_num_vio_9705 = mean(mean_num_vio_9705, na.rm = TRUE), mean_num_vio_8505 = mean(mean_num_vio_8505, na.rm = TRUE),
    .groups = "drop"
  )

g1 <- dplyr::filter(pws_outcomes, group == 1); g2 <- dplyr::filter(pws_outcomes, group == 2)
pvals <- list(
  ever_mr_9705      = stats::t.test(g1$ever_mr_9705,      g2$ever_mr_9705)$p.value,
  ever_mr_8505      = stats::t.test(g1$ever_mr_8505,      g2$ever_mr_8505)$p.value,
  ever_mcl_9705     = stats::t.test(g1$ever_mcl_9705,     g2$ever_mcl_9705)$p.value,
  ever_mcl_8505     = stats::t.test(g1$ever_mcl_8505,     g2$ever_mcl_8505)$p.value,
  mean_num_vio_9705 = stats::t.test(g1$mean_num_vio_9705, g2$mean_num_vio_9705)$p.value,
  mean_num_vio_8505 = stats::t.test(g1$mean_num_vio_8505, g2$mean_num_vio_8505)$p.value
)

fmt_pct_c  <- function(x) sprintf("%.1f\\%%", x * 100)
fmt_mean_c <- function(x) sprintf("%.2f", x)
star_str_c <- function(p) if (p < 0.01) "^{***}" else if (p < 0.05) "^{**}" else if (p < 0.1) "^{*}" else ""

g1_row <- dplyr::filter(group_means, group == 1); g2_row <- dplyr::filter(group_means, group == 2)
diffs <- c(
  ever_mr_9705      = g1_row$ever_mr_9705      - g2_row$ever_mr_9705,
  ever_mr_8505      = g1_row$ever_mr_8505      - g2_row$ever_mr_8505,
  ever_mcl_9705     = g1_row$ever_mcl_9705     - g2_row$ever_mcl_9705,
  ever_mcl_8505     = g1_row$ever_mcl_8505     - g2_row$ever_mcl_8505,
  mean_num_vio_9705 = g1_row$mean_num_vio_9705 - g2_row$mean_num_vio_9705,
  mean_num_vio_8505 = g1_row$mean_num_vio_8505 - g2_row$mean_num_vio_8505
)

rows_9705 <- list(
  list(label = "Ever MR violation",  g1 = fmt_pct_c(g1_row$ever_mr_9705),  g2 = fmt_pct_c(g2_row$ever_mr_9705),
       diff = fmt_pct_c(diffs["ever_mr_9705"]), p = pvals$ever_mr_9705),
  list(label = "Ever MCL violation", g1 = fmt_pct_c(g1_row$ever_mcl_9705), g2 = fmt_pct_c(g2_row$ever_mcl_9705),
       diff = fmt_pct_c(diffs["ever_mcl_9705"]), p = pvals$ever_mcl_9705),
  list(label = "Mean annual violations (count, 0--6)", g1 = fmt_mean_c(g1_row$mean_num_vio_9705), g2 = fmt_mean_c(g2_row$mean_num_vio_9705),
       diff = fmt_mean_c(diffs["mean_num_vio_9705"]), p = pvals$mean_num_vio_9705)
)
rows_8505 <- list(
  list(label = "Ever MR violation",  g1 = fmt_pct_c(g1_row$ever_mr_8505),  g2 = fmt_pct_c(g2_row$ever_mr_8505),
       diff = fmt_pct_c(diffs["ever_mr_8505"]), p = pvals$ever_mr_8505),
  list(label = "Ever MCL violation", g1 = fmt_pct_c(g1_row$ever_mcl_8505), g2 = fmt_pct_c(g2_row$ever_mcl_8505),
       diff = fmt_pct_c(diffs["ever_mcl_8505"]), p = pvals$ever_mcl_8505),
  list(label = "Mean annual violations (count, 0--6)", g1 = fmt_mean_c(g1_row$mean_num_vio_8505), g2 = fmt_mean_c(g2_row$mean_num_vio_8505),
       diff = fmt_mean_c(diffs["mean_num_vio_8505"]), p = pvals$mean_num_vio_8505)
)

build_panel_c <- function(panel_title, rows) {
  header <- paste0(
    "\\textbf{", panel_title, "}\\\\[2pt]\n",
    "\\begin{adjustbox}{max width=\\textwidth}\n",
    "\\begin{tabular}{lrrrr}\n\\toprule\n",
    " & \\multicolumn{2}{c}{Utility appears in SYR2} & & \\\\\n",
    "\\cmidrule(lr){2-3}\n",
    " & Yes & No & Diff. & $p$-value \\\\\n",
    " & \\multicolumn{1}{c}{(1)} & \\multicolumn{1}{c}{(2)} & \\multicolumn{1}{c}{(3)} & \\multicolumn{1}{c}{(4)} \\\\\n",
    "\\hline\n"
  )
  body <- ""
  for (i in seq_along(rows)) {
    r <- rows[[i]]
    stars <- star_str_c(r$p)
    diff_cell <- if (nzchar(stars)) paste0(r$diff, "$", stars, "$") else r$diff
    if (i == length(rows)) body <- paste0(body, "\\hline\n")
    body <- paste0(body, r$label, " & ", r$g1, " & ", r$g2, " & ", diff_cell, " & ", sprintf("%.3f", r$p), " \\\\\n")
  }
  footer <- "\\bottomrule\n\\end{tabular}\n\\end{adjustbox}\n"
  paste0(header, body, footer)
}

tex_c <- paste0(
  "\\begin{table}[htbp]\n\\centering\n",
  "\\caption{MR and MCL violation rates and counts by SYR2 contaminant reporting status, two-step upstream watershed linkage}\n",
  "\\label{tab:syr2_mr_comparison_k2}\n",
  build_panel_c("Panel A: 1997--2005", rows_9705),
  "\\vspace{8pt}\n",
  build_panel_c("Panel B: 1985--2005", rows_8505),
  "\\begin{minipage}{\\linewidth}\n\\vspace{4pt}\n\\footnotesize\n\\raggedright\n",
  "\\textit{Notes:} Sample restricted to utilities with a coal mine within two flow steps ",
  "upstream of their intake and no coal mine colocated with their intake. ",
  "\\textit{Has SYR2 reading}: at least one Six-Year Review contaminant reading for ",
  "arsenic, nitrate, selenium, or barium. \\textit{No SYR2 reading}: utility is in a ",
  "state where at least one utility has a SYR2 reading but the utility itself does ",
  "not. MR violation: inorganic chemical monitoring and reporting violation. MCL ",
  "violation: inorganic chemical maximum contaminant violation. Mean annual ",
  "violations: sum of MR and MCL violation indicators across arsenic, nitrate, and ",
  "inorganic chemicals categories (maximum of 6 per utility-year). $N$ utilities: ",
  "group 1 = ", g1_row$n_cws, ", group 2 = ", g2_row$n_cws, ". Diff.~stars from ",
  "two-sample $t$-test: *** $p<0.01$, ** $p<0.05$, * $p<0.1$.\n",
  "\\end{minipage}\n\\end{table}\n"
)

out_c <- "Z:/ek559/mining_wq/output/sum/syr2_mr_comparison_k2.tex"
writeLines(tex_c, out_c)
cat("Written:", out_c, "\n")

# Presentation companion: same table body, trailing notes minipage dropped
# entirely -- .claude/logs/2026-08-31-presentation-notes-tables.md.
tex_c_present <- paste0(
  "\\begin{table}[htbp]\n\\centering\n",
  "\\caption{MR and MCL violation rates and counts by SYR2 contaminant reporting status, two-step upstream watershed linkage}\n",
  "\\label{tab:syr2_mr_comparison_k2}\n",
  build_panel_c("Panel A: 1997--2005", rows_9705),
  "\\vspace{8pt}\n",
  build_panel_c("Panel B: 1985--2005", rows_8505),
  "\\end{table}\n"
)
out_c_present <- sub("\\.tex$", "_present.tex", out_c)
writeLines(tex_c_present, out_c_present)
cat("Written:", out_c_present, "\n")

cat("\n=== run_k2_6yr_tables.r DONE ===\n")
