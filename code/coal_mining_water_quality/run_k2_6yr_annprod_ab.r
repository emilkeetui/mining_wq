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

panel_a_tex <- strip_cmidrule(panel_tabular(models_a))
panel_a_lines <- insert_panel_title(panel_a_tex, 4, "Panel A: Utilities with a coal mine one watershed upstream")
panel_b_tex <- strip_cmidrule(panel_tabular(models_b))
panel_b_tex <- drop_line(panel_b_tex, "Arsenic & Nitrate & Barium & Selenium")
panel_b_tex <- drop_colnum_row(panel_b_tex)
panel_b_lines <- insert_panel_title(panel_b_tex, 4, "Panel B: Utilities with a coal mine within two watersheds upstream")

# Both panels keep their Observations row (different N). Panel A is cut just
# before its bottomrule; Panel B contributes everything after its top midrule.
a_end <- which(trimws(panel_a_lines) == "\\bottomrule")[1] - 1
mid_b <- which(trimws(panel_b_lines) == "\\midrule")[1]
merged_panel_lines <- c(panel_a_lines[seq_len(a_end)], "      \\midrule",
                        panel_b_lines[(mid_b + 1):length(panel_b_lines)])

title <- "Effect of annual upstream coal production on inorganic chemicals, SYR2 1998--2005"
label <- "tab:6yr_huc02fe_inorg_ravalli_2005_annprod_ab"
build_panel_table(merged_panel_lines, title, label, note_reg, out_reg)
cat("Written:", out_reg, "\n")
out_reg_present <- sub("\\.tex$", "_present.tex", out_reg)
build_panel_table(merged_panel_lines, title, label, note_reg_present, out_reg_present)
cat("Written:", out_reg_present, "\n")
cat("\n=== run_k2_6yr_annprod_ab.r DONE ===\n")
