# ============================================================
# Script: run_k2_6yr_swap_tables.r
# Purpose: Regressor-swap versions of run_k2_6yr_tables.r's SYR2
#          concentration table (6yr_huc02fe_inorg_ravalli_2005_k2): OLS of
#          mean measured concentration (arsenic/nitrate/barium/selenium) on
#          (a) the contemporaneous number of upstream coal mines and (b)
#          annual upstream coal production (1M short tons), each in place of
#          cumulative upstream production. Panel A = within one flow step
#          upstream, Panel B = within two, on the same k=2 sample rows.
#          FE: PWSID + huc02^year. Sources k2_common.r.
# Inputs:
#   clean_data/cws_data/step_instruments.parquet
#   clean_data/cws_data/step_purity_flags.parquet (via k2_common.r)
#   clean_data/cws_6year_review_ravalli.parquet
#   clean_data/cws_data/pwsid_huc02.parquet
# Outputs:
#   output/reg/6yr_huc02fe_inorg_ravalli_2005_k2nmines.tex (+ _present.tex)
#   output/reg/6yr_huc02fe_inorg_ravalli_2005_k2annprod.tex (+ _present.tex)
# Author: EK  Date: 2026-09-23
# ============================================================

source("Z:/ek559/mining_wq/code/coal_mining_water_quality/k2_common.r")

si <- read_parquet(file.path(ROOT, "clean_data/cws_data/step_instruments.parquet"))
stopifnot(is.character(si$PWSID))

d6r <- read_parquet(file.path(ROOT, "clean_data/cws_6year_review_ravalli.parquet"))
stopifnot(is.character(d6r$PWSID), "STATE_CODE" %in% names(d6r))
d6r <- d6r %>% dplyr::filter(year >= 1985, PWSID != "WV3303401")

huc02_lookup <- read_parquet(file.path(ROOT, "clean_data/cws_data/pwsid_huc02.parquet"))
stopifnot(is.character(huc02_lookup$PWSID), is.character(huc02_lookup$huc02))
d6r <- d6r %>% dplyr::left_join(huc02_lookup %>% dplyr::select(PWSID, huc02), by = "PWSID")
cat("Rows with missing huc02 after merge:", sum(is.na(d6r$huc02)), "\n")

CHEMS <- c("arsenic", "nitrate", "barium", "selenium")
nice_chem <- c(arsenic = "Arsenic", nitrate = "Nitrate", barium = "Barium", selenium = "Selenium")

# ── build_dose_sample(): run_k2_6yr_tables.r's builder, generalized so the
# dose can be any step_instruments column (`dose_var`), either cumulated
# since 1985 (`cumulate = TRUE`, the parent table's cumulative production) or
# used contemporaneously (`cumulate = FALSE`, the upstream mine count here).
# The output column carries the name of `dose_var` when not cumulated, and
# `coal_prod_upstream_cumsum_10mst` (dose / 1e7) when cumulated, as in the
# parent. `sample_k` picks the utility-year rows; `dose_k` the flow depth. ──
build_dose_sample <- function(sample_k, dose_k = sample_k,
                              dose_var = "production_linked_sum", cumulate = TRUE) {
  arm_k <- si %>% dplyr::filter(arm == "main", k == sample_k, n_mine_hucs_linked >= 1) %>%
    apply_a2() %>%
    dplyr::select(PWSID, year, dose = dplyr::all_of(dose_var))

  linked_pwsids <- unique(arm_k$PWSID)
  d <- d6r %>% dplyr::filter(PWSID %in% linked_pwsids, CHEMID_name %in% CHEMS)

  if (dose_k == sample_k) {
    dose_src <- arm_k
  } else {
    dose_src <- arm_k %>% dplyr::select(PWSID, year) %>%
      dplyr::left_join(
        si %>% dplyr::filter(arm == "main", k == dose_k) %>%
          dplyr::select(PWSID, year, dose = dplyr::all_of(dose_var)),
        by = c("PWSID", "year")
      )
  }

  out_var <- if (cumulate) "coal_prod_upstream_cumsum_10mst" else dose_var
  dose_panel <- dose_src %>%
    dplyr::distinct(PWSID, year, dose) %>%
    dplyr::arrange(PWSID, year) %>%
    dplyr::group_by(PWSID) %>%
    dplyr::mutate(dose = replace(dose, is.na(dose), 0),
                  dose = if (cumulate) cumsum(dose) / 1e7 else dose) %>%
    dplyr::ungroup()

  if (cumulate) {
    chk <- dose_panel %>% dplyr::group_by(PWSID) %>%
      dplyr::mutate(diff = dose - dplyr::lag(dose))
    stopifnot(all(chk$diff >= 0 | is.na(chk$diff)))
  }
  names(dose_panel)[names(dose_panel) == "dose"] <- out_var

  d <- d %>% dplyr::inner_join(dose_panel, by = c("PWSID", "year"))
  d <- d[!is.na(d$VALUE), ]
  d <- d[d$year <= 2005, ]
  d
}


dose_parent <- build_dose_sample(2)  # parent's cumulative-production rows (row-count gate only)
nm2    <- build_dose_sample(2,             dose_var = "num_coal_mines_linked_sum", cumulate = FALSE)
nm2_k1 <- build_dose_sample(2, dose_k = 1, dose_var = "num_coal_mines_linked_sum", cumulate = FALSE)
an2    <- build_dose_sample(2,             cumulate = FALSE)
an2_k1 <- build_dose_sample(2, dose_k = 1, cumulate = FALSE)
an2$coal_prod_upstream_1mst    <- an2$production_linked_sum / 1e6
an2_k1$coal_prod_upstream_1mst <- an2_k1$production_linked_sum / 1e6

# Row gate: every swap sample has exactly the parent table's rows.
key_cols <- c("PWSID", "year", "CHEMID_name", "VALUE")
sort_keys <- function(df) { x <- df[order(df$PWSID, df$year, df$CHEMID_name), key_cols]; rownames(x) <- NULL; x }
for (df in list(nm2, nm2_k1, an2, an2_k1)) stopifnot(identical(sort_keys(df), sort_keys(dose_parent)))
cat(sprintf("k2 dose sample: %d rows, %d utilities (identical rows to parent table)\n",
            nrow(nm2), dplyr::n_distinct(nm2$PWSID)))
cat(sprintf("Mines within one step: mean %.2f, zero for %.1f%% of rows; within two: mean %.2f, zero for %.1f%%\n",
            mean(nm2_k1$num_coal_mines_linked_sum), 100 * mean(nm2_k1$num_coal_mines_linked_sum == 0),
            mean(nm2$num_coal_mines_linked_sum),    100 * mean(nm2$num_coal_mines_linked_sum == 0)))
cat(sprintf("Annual prod. (1M ST) within one step: mean %.3f, zero for %.1f%% of rows; within two: mean %.3f, zero for %.1f%%\n",
            mean(an2_k1$coal_prod_upstream_1mst), 100 * mean(an2_k1$coal_prod_upstream_1mst == 0),
            mean(an2$coal_prod_upstream_1mst),    100 * mean(an2$coal_prod_upstream_1mst == 0)))

# Fit the 8 models (one-step dose then two-step dose, x 4 chemicals).
fit_swap_models <- function(dose_list, regvar) {
  fml <- as.formula(paste0("VALUE ~ ", regvar, " + num_facilities | PWSID + huc02^year"))
  models_val <- list()
  for (dose_name in names(dose_list)) {
    dose_df <- dose_list[[dose_name]]
    for (chem in CHEMS) {
      d_chem <- dose_df[dose_df$CHEMID_name == chem, ]
      cat("  Dose:", dose_name, "| Chemical:", chem, "| n rows:", nrow(d_chem), "\n")
      if (nrow(d_chem) < 30) { cat("  Skipping -- too few obs.\n"); next }
      m <- tryCatch(fixest::feols(fml, data = d_chem, cluster = ~PWSID, warn = FALSE, notes = FALSE),
                    error = function(e) { cat("  ERROR:", conditionMessage(e), "\n"); NULL })
      if (!is.null(m)) {
        models_val <- c(models_val, list(m))
        ct <- fixest::coeftable(m)[regvar, ]
        cat(sprintf("  n = %d | coef = %.4f (%.4f)\n", m$nobs, ct["Estimate"], ct["Std. Error"]))
      }
    }
  }
  stopifnot(length(models_val) == 8)
  models_val
}

# ── Two-panel table assembly (helpers verbatim from run_k2_6yr_tables.r) ──
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

strip_cmidrule <- function(tex_str) {
  gsub(" *\\\\cmidrule\\(lr\\)\\{[0-9]+-[0-9]+\\}", "", tex_str)
}
drop_line <- function(tex_str, pattern) {
  lines <- strsplit(tex_str, "\n", fixed = TRUE)[[1]]
  paste(lines[!grepl(pattern, lines, fixed = TRUE)], collapse = "\n")
}
drop_colnum_row <- function(tex_str) {
  lines <- strsplit(tex_str, "\n", fixed = TRUE)[[1]]
  is_colnum <- grepl("\\(1\\)", lines) & grepl("\\(4\\)", lines)
  paste(lines[!is_colnum], collapse = "\n")
}
build_panel_table <- function(body, title, label, notes, out_path) {
  lines <- c(
    "\\begin{table}[htbp]",
    "   ",
    paste0("   \\caption{\\label{", label, "} ", title, "}"),
    "   \\bigskip",
    "   ",
    "   \\centering",
    "   ",
    body,
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

note_reg_present <- paste0(
  "\\textit{Notes:} All specifications include utility and HUC02 $\\times$ year ",
  "fixed effects. Standard errors clustered at the utility level. ",
  "*** p$<$0.01, ** p$<$0.05, * p$<$0.1."
)

# Merge the two etable panels into one tabular and write the table + its
# presentation companion. `regressor_sentence` describes the explanatory
# variable in plain language (no variable names).
write_swap_table <- function(models_val, stem, title, regressor_sentence) {
  panel_a_tex <- strip_cmidrule(panel_tabular(models_val[1:4]))
  panel_a_tex <- drop_line(panel_a_tex, "Observations")
  panel_a_lines <- insert_panel_title(panel_a_tex, 4, "Panel A: Within one HUC12 upstream")

  panel_b_tex <- strip_cmidrule(panel_tabular(models_val[5:8]))
  panel_b_tex <- drop_line(panel_b_tex, "Arsenic & Nitrate & Barium & Selenium")
  panel_b_tex <- drop_colnum_row(panel_b_tex)
  panel_b_lines <- insert_panel_title(panel_b_tex, 4, "Panel B: Within two HUC12 upstream")

  top_a_idx <- which(trimws(panel_a_lines) == "\\bottomrule")[1] - 1
  top_a     <- panel_a_lines[seq_len(top_a_idx)]
  mid_b_idx <- which(trimws(panel_b_lines) == "\\midrule")[1]
  bottom_b  <- panel_b_lines[mid_b_idx:length(panel_b_lines)]
  merged_panel_lines <- c(top_a, bottom_b)

  note_reg <- paste0(
    "\\textit{Notes:} Within each chemical, the column shows mean measured concentration ",
    "from the EPA 6-Year Review. Non-detect values replaced by MDL$/\\sqrt{2}$ following ",
    "Ravalli et al.~(2022). ", regressor_sentence, " ",
    "Sample: utilities with a coal mine within two flow steps upstream of their intake ",
    "and no coal mine colocated with their intake. Standard errors clustered at the ",
    "utility level. All specifications include utility and HUC02 $\\times$ year fixed ",
    "effects. *** p$<$0.01, ** p$<$0.05, * p$<$0.1."
  )
  label   <- paste0("tab:", stem)
  out_reg <- file.path(ROOT, "output/reg", paste0(stem, ".tex"))
  build_panel_table(merged_panel_lines, title, label, note_reg, out_reg)
  cat("Written:", out_reg, "\n")
  out_reg_present <- sub("\\.tex$", "_present.tex", out_reg)
  build_panel_table(merged_panel_lines, title, label, note_reg_present, out_reg_present)
  cat("Written:", out_reg_present, "\n")
}

# ── 6yr_huc02fe_inorg_ravalli_2005_k2nmines ──────────────────────────────
write_swap_table(
  fit_swap_models(list(one = nm2_k1, two = nm2), "num_coal_mines_linked_sum"),
  stem  = "6yr_huc02fe_inorg_ravalli_2005_k2nmines",
  title = "Effect of the number of upstream coal mines on inorganic chemicals by upstream distance, SYR2 1998--2005",
  regressor_sentence = paste0(
    "Explanatory variable is the number of coal mines in the year in watersheds within ",
    "one flow step upstream of the utility's intake (Panel A) or within two flow steps ",
    "upstream (Panel B), summed across those watersheds.")
)

# ── 6yr_huc02fe_inorg_ravalli_2005_k2annprod ─────────────────────────────
write_swap_table(
  fit_swap_models(list(one = an2_k1, two = an2), "coal_prod_upstream_1mst"),
  stem  = "6yr_huc02fe_inorg_ravalli_2005_k2annprod",
  title = "Effect of upstream coal production on inorganic chemicals by upstream distance, SYR2 1998--2005",
  regressor_sentence = paste0(
    "Explanatory variable is coal production during the year (in millions of short tons) ",
    "in watersheds within one flow step upstream of the utility's intake (Panel A) or ",
    "within two flow steps upstream (Panel B).")
)

cat("\n=== run_k2_6yr_swap_tables.r DONE ===\n")
