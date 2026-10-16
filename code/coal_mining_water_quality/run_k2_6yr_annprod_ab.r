# ============================================================
# Script: run_k2_6yr_annprod_ab.r
# Purpose: Two-panel SYR2 concentration table on ANNUAL upstream coal
#          production (1M short tons). Panel A = utilities with a coal mine
#          one watershed upstream (strictly downstream sample, one-step
#          annual production); Panel B = utilities with a coal mine within
#          two watersheds upstream (k=2 sample, two-step annual production).
#          Outcome: mean measured concentration of arsenic/nitrate/barium/
#          selenium. FE: PWSID + huc02^year. Sources k2_common.r.
# Inputs:
#   clean_data/cws_data/step_instruments.parquet
#   clean_data/cws_6year_review_ravalli.parquet
#   clean_data/cws_data/pwsid_huc02.parquet
# Outputs:
#   output/reg/6yr_huc02fe_inorg_ravalli_2005_annprod_ab.tex (+ _present.tex)
# Author: EK  Date: 2026-10-14
# ============================================================

source("Z:/ek559/mining_wq/code/coal_mining_water_quality/k2_common.r")

out_reg <- file.path(ROOT, "output/reg/6yr_huc02fe_inorg_ravalli_2005_annprod_ab.tex")
if (file.exists(out_reg)) cat("WARNING:", out_reg, "already exists -- overwriting
")

si <- read_parquet(file.path(ROOT, "clean_data/cws_data/step_instruments.parquet"))
stopifnot(is.character(si$PWSID))

d6r <- read_parquet(file.path(ROOT, "clean_data/cws_6year_review_ravalli.parquet"))
stopifnot(is.character(d6r$PWSID), "STATE_CODE" %in% names(d6r))
d6r <- d6r %>% dplyr::filter(year >= 1985, PWSID != "WV3303401")

huc02_lookup <- read_parquet(file.path(ROOT, "clean_data/cws_data/pwsid_huc02.parquet"))
stopifnot(is.character(huc02_lookup$PWSID), is.character(huc02_lookup$huc02))
d6r <- d6r %>% dplyr::left_join(huc02_lookup %>% dplyr::select(PWSID, huc02), by = "PWSID")

CHEMS <- c("arsenic", "nitrate", "barium", "selenium")
nice_chem <- c(arsenic = "Arsenic", nitrate = "Nitrate", barium = "Barium", selenium = "Selenium")
regvar <- "coal_prod_upstream_1mst"

# ── Panel A sample: strictly downstream utilities, one-step annual production ──
a_df <- d6r %>%
  dplyr::filter(minehuc_downstream_of_mine == 1, minehuc_mine == 0, CHEMID_name %in% CHEMS)
a_df[[regvar]] <- replace(a_df$production_short_tons_coal_upstream_sum,
                          is.na(a_df$production_short_tons_coal_upstream_sum), 0) / 1e6
a_df <- a_df[!is.na(a_df$VALUE) & a_df$year <= 2005, ]
cat(sprintf("Panel A: %d rows, %d utilities
", nrow(a_df), dplyr::n_distinct(a_df$PWSID)))

# ── Panel B sample: k=2 sample, two-step annual production (as in k2annprod) ──
arm_k <- si %>% dplyr::filter(arm == "main", k == 2, n_mine_hucs_linked >= 1) %>%
  apply_a2() %>%
  dplyr::select(PWSID, year, production_linked_sum)
dose_panel <- arm_k %>%
  dplyr::distinct(PWSID, year, production_linked_sum) %>%
  dplyr::mutate(!!regvar := replace(production_linked_sum, is.na(production_linked_sum), 0) / 1e6) %>%
  dplyr::select(PWSID, year, dplyr::all_of(regvar))
b_df <- d6r %>%
  dplyr::filter(PWSID %in% unique(arm_k$PWSID), CHEMID_name %in% CHEMS) %>%
  dplyr::inner_join(dose_panel, by = c("PWSID", "year"))
b_df <- b_df[!is.na(b_df$VALUE) & b_df$year <= 2005, ]
cat(sprintf("Panel B: %d rows, %d utilities
", nrow(b_df), dplyr::n_distinct(b_df$PWSID)))
stopifnot(nrow(a_df) >= 100, nrow(b_df) >= 100)

fml <- as.formula(paste0("VALUE ~ ", regvar, " + num_facilities | PWSID + huc02^year"))
fit_panel <- function(df) {
  out <- lapply(CHEMS, function(chem) {
    d_chem <- df[df$CHEMID_name == chem, ]
    m <- fixest::feols(fml, data = d_chem, cluster = ~PWSID, warn = FALSE, notes = FALSE)
    ct <- fixest::coeftable(m)[regvar, ]
    cat(sprintf("  %s: n = %d | coef = %.4f (%.4f)
", chem, m$nobs, ct["Estimate"], ct["Std. Error"]))
    m
  })
  out
}
cat("Panel A models
"); models_a <- fit_panel(a_df)
cat("Panel B models
"); models_b <- fit_panel(b_df)

# ── Two-panel table assembly ──────────────────────────────────────────────
# Concentration outcome: coefficients and SEs carry 2 significant figures and
# are decimal-aligned within each column with fixed-width integer/fraction boxes.
note_reg_present <- paste0(
  "\\textit{Notes:} All specifications include utility and HUC02 $\\times$ year ",
  "fixed effects. Standard errors clustered at the utility level. ",
  "*** p$<$0.01, ** p$<$0.05, * p$<$0.1."
)
note_reg <- paste0(
  "\\textit{Notes:} Within each chemical, the column shows mean measured concentration ",
  "from the EPA 6-Year Review. Non-detect values replaced by MDL$/\\sqrt{2}$ following ",
  "Ravalli et al.~(2022). Explanatory variable is coal production during the year ",
  "(in millions of short tons) in watersheds upstream of the utility's intake. ",
  "Panel A: community water systems with a coal mine one watershed upstream and no coal mine ",
  "colocated with their intake, with production in that upstream watershed. ",
  "Panel B: community water systems with a coal mine within two watersheds ",
  "upstream and no coal mine colocated with their intake, with production summed across those watersheds. ",
  "Standard errors clustered at the utility level. All specifications include utility and ",
  "HUC02 $\\times$ year fixed effects. *** p$<$0.01, ** p$<$0.05, * p$<$0.1."
)

ab_pad <- "\\phantom{$^{***}$}"
ab_cells <- function(models_a, models_b) {
  terms <- lapply(c(models_a, models_b), get_term, term = regvar)
  n_m   <- length(models_a)
  out   <- vector("list", n_m)
  for (j in seq_len(n_m)) {
    t_a <- terms[[j]]; t_b <- terms[[n_m + j]]
    strs  <- c(fmt_sig(t_a$est), fmt_sig(t_a$se), fmt_sig(t_b$est), fmt_sig(t_b$se))
    stars <- c(stars_from_p(t_a$pval), 0L, stars_from_p(t_b$pval), 0L)
    cells <- split_align_cells(strs, stars = stars, paren = c(FALSE, TRUE, FALSE, TRUE))
    out[[j]] <- cells
  }
  out
}
ab_col <- ab_cells(models_a, models_b)
ab_row <- function(label, k) paste0(label, " & ", paste(vapply(ab_col, `[`, character(1), k), collapse = " & "), " \\\\")
ab_n   <- function(models) paste0("Observations & ",
  paste0(fmt_int(vapply(models, nobs, numeric(1))), ab_pad, collapse = " & "), " \\\\")
ab_cen <- ">{\\centering\\arraybackslash}p{2cm}"
ab_lab <- k2_dict[["coal_prod_upstream_1mst"]]
ab_w_cm <- c(6.2, rep(2, 4))
body_ab <- c(
  paste0("\\begin{tabular}{p{6.2cm}", paste0(rep(">{\\raggedleft\\arraybackslash}p{2cm}", 4), collapse = ""), "}"),
  "\\toprule",
  paste0(" & ", paste0("\\multicolumn{1}{", ab_cen, "}{", unname(nice_chem[CHEMS]), "}", collapse = " & "), " \\\\"),
  paste0(" & ", paste0("\\multicolumn{1}{", ab_cen, "}{(", 1:4, ")}", collapse = " & "), " \\\\"),
  "\\midrule",
  "\\multicolumn{5}{l}{\\textbf{Panel A: Utilities with a coal mine one watershed upstream}} \\\\",
  ab_row(ab_lab, 1), ab_row("", 2), ab_n(models_a),
  "\\midrule",
  "\\multicolumn{5}{l}{\\textbf{Panel B: Utilities with a coal mine within two watersheds upstream}} \\\\",
  ab_row(ab_lab, 3), ab_row("", 4), ab_n(models_b),
  "\\bottomrule",
  "\\end{tabular}"
)
tw_ab <- table_width(ab_w_cm)
if (tw_ab$needs_scale) body_ab <- c("\\begin{adjustbox}{max width=\\linewidth}", body_ab, "\\end{adjustbox}")

title <- "Effect of annual upstream coal production on inorganic chemicals, SYR2 1998--2005"
label <- "tab:6yr_huc02fe_inorg_ravalli_2005_annprod_ab"
writeLines(table_shell(label, title, tw_ab$total_w, body_ab, note_reg), out_reg)
cat("Written:", out_reg, "\n")
out_reg_present <- sub("\\.tex$", "_present.tex", out_reg)
writeLines(table_shell(label, title, tw_ab$total_w, body_ab, note_reg_present), out_reg_present)
cat("Written:", out_reg_present, "\n")
cat("\n=== run_k2_6yr_annprod_ab.r DONE ===\n")
