# ============================================================
# Script: test_h3_inf_formal_chem.r
# Purpose: TEST version of h3_inf_formal_d12.tex — replaces the generic
#          any_informal/any_formal/no_enf outcomes with a combined
#          chemical-restricted version: informal (formal) enforcement
#          equals 1 if applied to arsenic, nitrates, OR IOC MR
#          violations (D1 downstream sample). 9-column layout,
#          identical style to h3_inf_formal_d12.tex.
#          RULE_CODE mapping (same as enf_action_by_viol_type_dwnstrm.r):
#            331 = nitrate, 332 = arsenic, 333 = inorganic chemicals (IOC)
#          IOC MR restricts rule 333 to VIOLATION_CATEGORY_CODE == "MR".
# Inputs:
#   clean_data/cws_data/prod_vio_sulfur.parquet
#   Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.csv
# Outputs:
#   output/reg/test_h3_inf_formal_chem.tex
# Author: EK  Date: 2026-07-15
# ============================================================

.libPaths("Z:/ek559/RPackages")
library(arrow)
library(data.table)
library(fixest)
library(dplyr)

ROOT <- "Z:/ek559/mining_wq"
SDWA <- "Z:/ek559/sdwa_violations/SDWA_latest_downloads"
setwd(ROOT)

# ── Step 1: D1 main panel (same sample as h3_inf_formal_d12.tex) ────────────
cat("Loading D1 main panel (prod_vio_sulfur.parquet)...\n")
main_pvs <- read_parquet("clean_data/cws_data/prod_vio_sulfur.parquet")
d1_main  <- main_pvs[main_pvs$minehuc_downstream_of_mine == 1 &
                      main_pvs$minehuc_mine == 0 &
                      main_pvs$year >= 1985 & main_pvs$year <= 2005 &
                      main_pvs$PWSID != "WV3303401", ]
ids_d1_main <- unique(d1_main$PWSID)
cat(sprintf("D1 main panel: %d PWSIDs x %d PWSID-years\n\n",
            length(ids_d1_main), nrow(d1_main)))
rm(main_pvs); gc()

# ── Step 2: Enforcement actions, restricted to arsenic/nitrate/IOC MR ───────
cat("Reading SDWA_VIOLATIONS_ENFORCEMENT.csv (3.7 GB, 7 cols selected)...\n")
enf <- fread(file.path(SDWA, "SDWA_VIOLATIONS_ENFORCEMENT.csv"),
             select = c("PWSID", "COMPL_PER_BEGIN_DATE", "VIOLATION_CATEGORY_CODE",
                        "RULE_CODE", "ENF_ACTION_CATEGORY", "ENFORCEMENT_ID"))
enf <- enf[PWSID %in% ids_d1_main & !is.na(ENFORCEMENT_ID)]

enf[, year := as.integer(substr(trimws(COMPL_PER_BEGIN_DATE),
                                nchar(trimws(COMPL_PER_BEGIN_DATE)) - 3,
                                nchar(trimws(COMPL_PER_BEGIN_DATE))))]
enf <- enf[!is.na(year) & year >= 1985 & year <= 2005]
enf[, rule_num := suppressWarnings(as.numeric(RULE_CODE))]

cat(sprintf("Enforcement records in D1 sample (1985-2005): %d\n", nrow(enf)))

# Combined chemical restriction: arsenic (332) OR nitrate (331) OR IOC-MR (333 & MR)
enf_chem <- enf[rule_num == 332 |
                 rule_num == 331 |
                 (rule_num == 333 & VIOLATION_CATEGORY_CODE == "MR")]
cat(sprintf("Combined (arsenic/nitrate/IOC-MR) enforcement records: %d\n", nrow(enf_chem)))

enf_agg_chem <- enf_chem[, .(any_enf      = TRUE,
                              any_informal = any(ENF_ACTION_CATEGORY == "Informal", na.rm = TRUE),
                              any_formal   = any(ENF_ACTION_CATEGORY == "Formal",   na.rm = TRUE)),
                          by = .(PWSID, year)]
cat(sprintf("PWSID-years with combined enf:      %d\n", nrow(enf_agg_chem)))
cat(sprintf("PWSID-years with informal action:   %d\n", sum(enf_agg_chem$any_informal)))
cat(sprintf("PWSID-years with formal action:     %d\n", sum(enf_agg_chem$any_formal)))

rm(enf, enf_chem); gc()

# ── Step 3: Build regression panel ───────────────────────────────────────────
cat("\nBuilding D1 regression panel with combined chemical-restricted enforcement...\n")
panel_d1 <- d1_main %>%
  left_join(as.data.frame(enf_agg_chem), by = c("PWSID", "year"))

panel_d1$any_enf[is.na(panel_d1$any_enf)]           <- FALSE
panel_d1$any_informal[is.na(panel_d1$any_informal)] <- FALSE
panel_d1$any_formal[is.na(panel_d1$any_formal)]     <- FALSE
panel_d1$any_enf      <- as.integer(panel_d1$any_enf)
panel_d1$any_informal <- as.integer(panel_d1$any_informal)
panel_d1$any_formal   <- as.integer(panel_d1$any_formal)
panel_d1$no_enf       <- 1L - panel_d1$any_enf

cat(sprintf("D1 panel: %d PWSID-years\n", nrow(panel_d1)))
cat(sprintf("any_informal = 1 in %d (%.2f%%)\n",
    sum(panel_d1$any_informal), 100 * mean(panel_d1$any_informal)))
cat(sprintf("any_formal   = 1 in %d (%.2f%%)\n",
    sum(panel_d1$any_formal),   100 * mean(panel_d1$any_formal)))
cat(sprintf("no_enf       = 1 in %d (%.2f%%)\n",
    sum(panel_d1$no_enf),       100 * mean(panel_d1$no_enf)))

stopifnot("post95"                      %in% names(panel_d1))
stopifnot("sulfur_unified_mean"         %in% names(panel_d1) ||
          "sulfur_unified"              %in% names(panel_d1))
stopifnot("num_coal_mines_upstream_sum" %in% names(panel_d1) ||
          "num_coal_mines_upstream"     %in% names(panel_d1))

# Match the exact instrument/treatment names used in enforcement_chain_d12.r
sulfur_var <- if ("sulfur_unified_mean" %in% names(panel_d1)) "sulfur_unified_mean" else "sulfur_unified"
treat_var  <- if ("num_coal_mines_upstream_sum" %in% names(panel_d1)) "num_coal_mines_upstream_sum" else "num_coal_mines_upstream"
cat(sprintf("\nUsing sulfur var: %s, treatment var: %s\n", sulfur_var, treat_var))

# ── Step 4: Regressions — informal / formal / no_enf, D1 main sample ────────
fml_ols_id1 <- as.formula(paste0("any_informal ~ ", treat_var, " + num_facilities | PWSID + year"))
fml_rf_id1  <- as.formula(paste0("any_informal ~ post95:", sulfur_var, " + num_facilities | PWSID + year"))
fml_iv_id1  <- as.formula(paste0("any_informal ~ num_facilities | PWSID + year | ",
                                  treat_var, " ~ post95:", sulfur_var))

ols_id1 <- feols(fml_ols_id1, data = panel_d1, cluster = ~PWSID)
rf_id1  <- feols(fml_rf_id1,  data = panel_d1, cluster = ~PWSID)
iv_id1  <- feols(fml_iv_id1,  data = panel_d1, cluster = ~PWSID)

fml_ols_fd1 <- as.formula(paste0("any_formal ~ ", treat_var, " + num_facilities | PWSID + year"))
fml_rf_fd1  <- as.formula(paste0("any_formal ~ post95:", sulfur_var, " + num_facilities | PWSID + year"))
fml_iv_fd1  <- as.formula(paste0("any_formal ~ num_facilities | PWSID + year | ",
                                  treat_var, " ~ post95:", sulfur_var))

ols_fd1 <- feols(fml_ols_fd1, data = panel_d1, cluster = ~PWSID)
rf_fd1  <- feols(fml_rf_fd1,  data = panel_d1, cluster = ~PWSID)
iv_fd1  <- feols(fml_iv_fd1,  data = panel_d1, cluster = ~PWSID)

fml_ols_ned1 <- as.formula(paste0("no_enf ~ ", treat_var, " + num_facilities | PWSID + year"))
fml_rf_ned1  <- as.formula(paste0("no_enf ~ post95:", sulfur_var, " + num_facilities | PWSID + year"))
fml_iv_ned1  <- as.formula(paste0("no_enf ~ num_facilities | PWSID + year | ",
                                   treat_var, " ~ post95:", sulfur_var))

ols_ned1 <- feols(fml_ols_ned1, data = panel_d1, cluster = ~PWSID)
rf_ned1  <- feols(fml_rf_ned1,  data = panel_d1, cluster = ~PWSID)
iv_ned1  <- feols(fml_iv_ned1,  data = panel_d1, cluster = ~PWSID)

# Clustered first-stage F-stat (same treatment/instrument for all outcomes)
fml_fs <- as.formula(paste0(treat_var, " ~ post95:", sulfur_var, " + num_facilities | PWSID + year"))
fs     <- feols(fml_fs, data = panel_d1, cluster = ~PWSID)
t_cl   <- coef(fs)[paste0("post95:", sulfur_var)] / se(fs)[paste0("post95:", sulfur_var)]
f_cl_d1 <- round(t_cl^2, 2)
cat(sprintf("\nClustered first-stage F-stat: %.2f\n", f_cl_d1))

# ── Step 5: Helpers copied from enforcement_chain_d12.r ─────────────────────
wrap_for_beamer <- function(path, beamer_height = "0.7\\paperheight") {
  header <- c(
    "\\makeatletter",
    paste0("\\@ifclassloaded{beamer}{%\n",
           "  \\begin{adjustbox}{max width=\\linewidth,",
           " max totalheight=", beamer_height, ", center}%\n",
           "}{%\n",
           "  \\begin{adjustbox}{max width=\\linewidth, center}%\n",
           "}%"),
    "\\makeatother"
  )
  lines <- readLines(path)
  note_start  <- grep("^\\\\par \\\\raggedright\\s*$", lines)
  endgroup_ln <- grep("^\\\\par\\\\endgroup\\s*$",     lines)
  if (length(note_start) == 1 && length(endgroup_ln) == 1 && note_start < endgroup_ln) {
    note_text <- lines[(note_start + 1):(endgroup_ln - 1)]
    body      <- c(lines[seq_len(note_start - 1)], "\\par\\endgroup")
    writeLines(c(header, body, "\\end{adjustbox}", "",
                 "\\par \\raggedright", note_text, "\\par"), path)
  } else {
    writeLines(c(header, lines, "\\end{adjustbox}"), path)
  }
}

move_notes_below_adjustbox <- function(x) {
  x           <- paste(x, collapse = "\n")
  end_adj     <- "\\end{adjustbox}"
  par_rag     <- "\\par \\raggedright"
  par_pos     <- regexpr(par_rag, x, fixed = TRUE)
  end_adj_pos <- regexpr(end_adj, x, fixed = TRUE)
  if (par_pos[1] == -1 || end_adj_pos[1] == -1) return(x)
  note_block <- substr(x, par_pos[1], end_adj_pos[1] - 1)
  x <- sub(note_block, "", x, fixed = TRUE)
  x <- sub(end_adj,
            paste0(end_adj, "\n   {\\tiny\\linespread{1}\\selectfont ",
                   trimws(note_block), "}"),
            x, fixed = TRUE)
  x
}

rename_col_numbers_to_labels <- function(x) {
  x     <- paste(x, collapse = "\n")
  lines <- strsplit(x, "\n")[[1]]
  for (i in seq_along(lines)) {
    nums <- regmatches(lines[i], gregexpr("\\(\\d+\\)", lines[i]))[[1]]
    if (length(nums) >= 2) {
      num_vals <- as.integer(gsub("[()]", "", nums))
      if (identical(num_vals, seq_along(num_vals))) {
        labels <- rep(c("OLS", "RF", "2SLS"), length.out = length(nums))
        line   <- lines[i]
        for (j in seq_along(nums)) line <- sub(nums[j], labels[j], line, fixed = TRUE)
        lines[i] <- line
      }
    }
  }
  paste(lines, collapse = "\n")
}

postprocess_table <- function(x) rename_col_numbers_to_labels(move_notes_below_adjustbox(x))

# ── Step 6: Assemble table (9-column layout, same style as h3_inf_formal_d12.tex) ──
dir.create(file.path(ROOT, "output/reg"), showWarnings = FALSE, recursive = TRUE)
out_tex_h3_inf <- file.path(ROOT, "output/reg/test_h3_inf_formal_chem.tex")

inf_d1_pct <- 100 * mean(panel_d1$any_informal)
frm_d1_pct <- 100 * mean(panel_d1$any_formal)
ned1_pct   <- 100 * mean(panel_d1$no_enf)
f_label_d1 <- "F-test (1st stage, clustered), Upstream coal mines (sum)"
f_vec_d1   <- c("", "", format(round(f_cl_d1, 2), nsmall = 2),
                "", "", format(round(f_cl_d1, 2), nsmall = 2),
                "", "", format(round(f_cl_d1, 2), nsmall = 2))
el_d1 <- list(f_vec_d1)
names(el_d1) <- f_label_d1

dict_enf <- c(
  "any_informal"                    = "Any informal enf",
  "any_formal"                      = "Any formal enf",
  "no_enf"                          = "No enforcement",
  "num_coal_mines_upstream_sum"     = "Upstream coal mines (sum)",
  "fit_num_coal_mines_upstream_sum" = "Upstream coal mines (sum)",
  "post95:sulfur_unified_mean"      = "post95 $\\times$ Upstream sulfur \\%",
  "PWSID"                           = "CWS"
)

etable(ols_id1, rf_id1, iv_id1, ols_fd1, rf_fd1, iv_fd1, ols_ned1, rf_ned1, iv_ned1,
       title          = "TEST: Effect of Coal Mining on Enforcement Actions Restricted to Arsenic, Nitrate, and IOC MR Violations (D1 Downstream Sample)",
       label          = "tab:test_h3_inf_formal_chem",
       dict           = dict_enf,
       drop           = "num_facilities",
       extralines     = el_d1,
       fitstat        = ~n,
       notes          = paste0("TEST TABLE. D1 downstream sample (minehuc_downstream_of_mine = 1, minehuc_mine = 0). ",
                               "Enforcement actions restricted to those linked (via RULE_CODE) to arsenic (332), ",
                               "nitrate (331), or inorganic chemicals MR violations (333, VIOLATION_CATEGORY_CODE == 'MR'). ",
                               "Cols 1-3: informal enforcement action (",
                               sprintf("%.2f", inf_d1_pct), "% of panel). ",
                               "Cols 4-6: formal enforcement action (",
                               sprintf("%.2f", frm_d1_pct), "% of panel). ",
                               "Cols 7-9: no enforcement (",
                               sprintf("%.2f", ned1_pct), "% of panel). ",
                               "Treatment: num_coal_mines_upstream_sum. ",
                               "Instrument: post95 x sulfur_unified_mean. SEs clustered at CWS level."),
       style.tex      = style.tex("aer", adjustbox = TRUE),
       tex            = TRUE,
       postprocess.tex = postprocess_table,
       file           = out_tex_h3_inf,
       replace        = TRUE)
cat(sprintf("\nTable saved to: %s\n", out_tex_h3_inf))
if (file.exists(out_tex_h3_inf) && file.info(out_tex_h3_inf)$size > 0) {
  cat("Output verified: file exists and is non-zero.\n")
} else {
  stop("Output file missing or empty — check etable() call.")
}
