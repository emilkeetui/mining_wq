# ============================================================
# Script: enforcement_chain_d12_coaltons.r
# Purpose: Reproduce the H2b (visit-type LPM) and H3 (D1 informal/formal
#          enforcement) tables with upstream coal PRODUCTION (short tons,
#          summed across upstream HUC12s, scaled to millions) as the
#          endogenous variable, in place of the upstream coal mine count.
#          Instrument is unchanged (post95 x sulfur_unified_mean). Reads the
#          cached SDWA aggregates built by enforcement_chain_d12.r instead of
#          the 355 MB / 3.7 GB raw SDWA CSVs.
# Inputs:
#   clean_data/cws_data/prod_vio_sulfur.parquet
#   clean_data/cws_data/sdwa_visit_agg_d12.parquet
#   clean_data/cws_data/sdwa_enf_agg_d12.parquet
# Outputs:
#   output/reg/h2_snsv_d12_ivsumcoaltons.tex
#   output/reg/h3_inf_formal_d12_ivsumcoaltons.tex
# Author: EK  Date: 2026-08-27
# ============================================================

.libPaths(c("C:/Users/ek559/AppData/Local/R/win-library/4.6", "Z:/ek559/RPackages"))
library(arrow)
library(fixest)
library(dplyr)

ROOT <- "Z:/ek559/mining_wq"
setwd(ROOT)

cache_dir <- file.path(ROOT, "clean_data", "cws_data")
sv_cache  <- file.path(cache_dir, "sdwa_visit_agg_d12.parquet")
enf_cache <- file.path(cache_dir, "sdwa_enf_agg_d12.parquet")
if (!file.exists(sv_cache))  stop("Missing cache: ", sv_cache, " - do not fall back to raw CSV read.")
if (!file.exists(enf_cache)) stop("Missing cache: ", enf_cache, " - do not fall back to raw CSV read.")

# ── D1 main panel (prod_vio_sulfur.parquet, one step downstream) ────────────
cat("Loading D1 main panel (prod_vio_sulfur.parquet)...\n")
main_pvs <- read_parquet("clean_data/cws_data/prod_vio_sulfur.parquet")
d1_main  <- main_pvs[main_pvs$minehuc_downstream_of_mine == 1 &
                      main_pvs$minehuc_mine == 0 &
                      main_pvs$year >= 1985 & main_pvs$year <= 2005 &
                      main_pvs$PWSID != "WV3303401", ]
cat(sprintf("D1 main panel: %d PWSIDs x %d PWSID-years\n\n",
    length(unique(d1_main$PWSID)), nrow(d1_main)))
rm(main_pvs); gc()

# ── Cached SDWA aggregates ───────────────────────────────────────────────────
sv_agg  <- read_parquet(sv_cache)
enf_agg <- read_parquet(enf_cache)
str(sv_agg)
str(enf_agg)
stopifnot(is.character(sv_agg$PWSID),  is.integer(sv_agg$year))
stopifnot(is.character(enf_agg$PWSID), is.integer(enf_agg$year))

# ── Build D1 regression panel (mirrors enforcement_chain_d12.r lines 251-278) ──
cat("\nBuilding D1 main regression panel...\n")
panel_d1 <- d1_main %>%
  left_join(as.data.frame(sv_agg),  by = c("PWSID", "year")) %>%
  left_join(as.data.frame(enf_agg), by = c("PWSID", "year"))
panel_d1$n_visits[is.na(panel_d1$n_visits)]         <- 0L
panel_d1$any_snsv[is.na(panel_d1$any_snsv)]         <- FALSE
panel_d1$any_tech[is.na(panel_d1$any_tech)]         <- FALSE
panel_d1$any_enfvisit[is.na(panel_d1$any_enfvisit)] <- FALSE
panel_d1$any_smpl[is.na(panel_d1$any_smpl)]         <- FALSE
panel_d1$any_insp[is.na(panel_d1$any_insp)]         <- FALSE
panel_d1$any_snsv     <- as.integer(panel_d1$any_snsv)
panel_d1$any_tech     <- as.integer(panel_d1$any_tech)
panel_d1$any_enfvisit <- as.integer(panel_d1$any_enfvisit)
panel_d1$any_smpl     <- as.integer(panel_d1$any_smpl)
panel_d1$any_insp     <- as.integer(panel_d1$any_insp)
panel_d1$any_enf[is.na(panel_d1$any_enf)]           <- FALSE
panel_d1$any_informal[is.na(panel_d1$any_informal)] <- FALSE
panel_d1$any_formal[is.na(panel_d1$any_formal)]     <- FALSE
panel_d1$any_enf      <- as.integer(panel_d1$any_enf)
panel_d1$any_informal <- as.integer(panel_d1$any_informal)
panel_d1$any_formal   <- as.integer(panel_d1$any_formal)
panel_d1$no_enf       <- 1L - panel_d1$any_enf

# Scaled endogenous variable: millions of short tons.
panel_d1$production_short_tons_coal_upstream_sum_mil <-
  panel_d1$production_short_tons_coal_upstream_sum / 1e6

cat(sprintf("D1 main panel: %d PWSID-years\n", nrow(panel_d1)))
cat(sprintf("any_informal = 1 in %d (%.1f%%)\n",
    sum(panel_d1$any_informal), 100 * mean(panel_d1$any_informal)))
cat(sprintf("any_formal   = 1 in %d (%.1f%%)\n",
    sum(panel_d1$any_formal),   100 * mean(panel_d1$any_formal)))

# ── Gate: panel size and production-column completeness ─────────────────────
if (nrow(panel_d1) != 6232) {
  stop(sprintf("Gate failed: nrow(panel_d1) = %d, expected 6232.", nrow(panel_d1)))
}
n_na_prod <- sum(is.na(panel_d1$production_short_tons_coal_upstream_sum_mil))
if (n_na_prod != 0) {
  stop(sprintf("Gate failed: %d NAs in production_short_tons_coal_upstream_sum_mil.", n_na_prod))
}
cat("Gate passed: nrow(panel_d1) == 6232, 0 NAs in production column.\n")

has_variation <- function(dset, y) {
  v <- dset[[y]]
  v <- v[!is.na(v)]
  length(v) > 0L && length(unique(v)) > 1L
}

# ── H2b: visit-type binaries (LPM), all 5 categories ─────────────────────────
visit_outcomes <- c(any_snsv     = "Sanitary visits",
                     any_tech     = "Technical assistance",
                     any_enfvisit = "Enforcement visits",
                     any_smpl     = "Sample collection",
                     any_insp     = "Inspection")

cat("\n=== H2b: Any visit by type (binary, LPM) ~ coal production (D1 main panel) ===\n")

models_b <- list()
for (oc in names(visit_outcomes)) {
  cat(sprintf("\n%s (%s) = 1 in %d / %d CWS-years (%.1f%%)\n",
      oc, visit_outcomes[oc], sum(panel_d1[[oc]]), nrow(panel_d1),
      100 * mean(panel_d1[[oc]])))

  fml_ols_oc <- as.formula(paste0(oc, " ~ production_short_tons_coal_upstream_sum_mil + num_facilities | PWSID + year"))
  fml_rf_oc  <- as.formula(paste0(oc, " ~ post95:sulfur_unified_mean + num_facilities | PWSID + year"))
  fml_iv_oc  <- as.formula(paste0(oc, " ~ num_facilities | PWSID + year | production_short_tons_coal_upstream_sum_mil ~ post95:sulfur_unified_mean"))

  models_b[[paste0(oc, "_ols")]] <- feols(fml_ols_oc, data = panel_d1, cluster = ~PWSID)
  models_b[[paste0(oc, "_rf")]]  <- feols(fml_rf_oc,  data = panel_d1, cluster = ~PWSID)
  models_b[[paste0(oc, "_iv")]]  <- feols(fml_iv_oc,  data = panel_d1, cluster = ~PWSID)
}

# Clustered first-stage F-stat (no state FE, matches table spec). The first
# stage is identical across outcomes (same treatment/instrument/sample), so
# it is computed once and reused for every 2SLS column.
f_fs_b <- feols(production_short_tons_coal_upstream_sum_mil ~ post95:sulfur_unified_mean + num_facilities |
                PWSID + year, data = panel_d1, cluster = ~PWSID)
t_cl_b <- coef(f_fs_b)["post95:sulfur_unified_mean"] / se(f_fs_b)["post95:sulfur_unified_mean"]
f_cl_b <- round(t_cl_b^2, 2)
cat(sprintf("\nClustered first-stage F-stat (H2b, D1): %.2f\n", f_cl_b))

# ── H3 on D1 main panel ───────────────────────────────────────────────────────
cat("\n=== H3 (D1 main): Informal/formal enforcement ~ coal production ===\n")

fml_ols_id1 <- any_informal ~ production_short_tons_coal_upstream_sum_mil + num_facilities |
               PWSID + year
fml_rf_id1  <- any_informal ~ post95:sulfur_unified_mean  + num_facilities |
               PWSID + year
fml_iv_id1  <- any_informal ~ num_facilities | PWSID + year |
               production_short_tons_coal_upstream_sum_mil ~ post95:sulfur_unified_mean

ols_id1 <- feols(fml_ols_id1, data = panel_d1, cluster = ~PWSID)
rf_id1  <- feols(fml_rf_id1,  data = panel_d1, cluster = ~PWSID)
iv_id1  <- feols(fml_iv_id1,  data = panel_d1, cluster = ~PWSID)

fml_ols_fd1 <- any_formal ~ production_short_tons_coal_upstream_sum_mil + num_facilities |
               PWSID + year
fml_rf_fd1  <- any_formal ~ post95:sulfur_unified_mean  + num_facilities |
               PWSID + year
fml_iv_fd1  <- any_formal ~ num_facilities | PWSID + year |
               production_short_tons_coal_upstream_sum_mil ~ post95:sulfur_unified_mean

ols_fd1 <- feols(fml_ols_fd1, data = panel_d1, cluster = ~PWSID)
rf_fd1  <- feols(fml_rf_fd1,  data = panel_d1, cluster = ~PWSID)
iv_fd1  <- feols(fml_iv_fd1,  data = panel_d1, cluster = ~PWSID)

fml_ols_ned1 <- no_enf ~ production_short_tons_coal_upstream_sum_mil + num_facilities |
                PWSID + year
fml_rf_ned1  <- no_enf ~ post95:sulfur_unified_mean  + num_facilities |
                PWSID + year
fml_iv_ned1  <- no_enf ~ num_facilities | PWSID + year |
                production_short_tons_coal_upstream_sum_mil ~ post95:sulfur_unified_mean

ols_ned1 <- feols(fml_ols_ned1, data = panel_d1, cluster = ~PWSID)
rf_ned1  <- feols(fml_rf_ned1,  data = panel_d1, cluster = ~PWSID)
iv_ned1  <- feols(fml_iv_ned1,  data = panel_d1, cluster = ~PWSID)

# Clustered first-stage F-stat: t^2 from separate clustered first-stage regression.
f_fs_d1 <- feols(production_short_tons_coal_upstream_sum_mil ~ post95:sulfur_unified_mean + num_facilities |
                 PWSID + year, data = panel_d1, cluster = ~PWSID)
t_cl_d1 <- coef(f_fs_d1)["post95:sulfur_unified_mean"] /
            se(f_fs_d1)["post95:sulfur_unified_mean"]
f_cl_d1 <- round(t_cl_d1^2, 2)
cat(sprintf("Clustered first-stage F-stat (D1 main): %.2f\n", f_cl_d1))

# ── LaTeX tables ──────────────────────────────────────────────────────────────
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

dir.create(file.path(ROOT, "output/reg"), showWarnings = FALSE, recursive = TRUE)

# H2b table
out_tex_b   <- file.path(ROOT, "output/reg/h2_snsv_d12_ivsumcoaltons.tex")
f_label_b   <- "F-test (1st stage, clustered), Upstream coal production (mil. short tons)"
f_vec_b     <- rep(c("", "", format(f_cl_b, nsmall = 2)), length(visit_outcomes))
el_b        <- list(f_vec_b)
names(el_b) <- f_label_b

dict_b <- c(
  "any_snsv"                                          = "Sanitary visits",
  "any_tech"                                           = "Technical assistance",
  "any_enfvisit"                                       = "Enforcement visits",
  "any_smpl"                                           = "Sample collection",
  "any_insp"                                           = "Inspection",
  "production_short_tons_coal_upstream_sum_mil"        = "Upstream coal production (mil. short tons)",
  "fit_production_short_tons_coal_upstream_sum_mil"    = "Upstream coal production (mil. short tons)",
  "post95:sulfur_unified_mean"                         = "post95 $\\times$ Upstream sulfur \\%",
  "PWSID"                                              = "CWS"
)

etable(models_b,
       title          = "Effect of Coal Production on Regulator Visit Probability by Visit Type (D1 Downstream Sample, LPM)",
       label          = "tab:h2_snsv_d12_ivsumcoaltons",
       dict           = dict_b,
       drop           = "num_facilities",
       extralines     = el_b,
       fitstat        = ~n,
       notes          = paste0("\\textit{Notes:} Sample restricted to community water systems strictly downstream ",
                               "of a coal mine. ",
                               "N = ", nrow(panel_d1), " CWS-years. Each panel of 3 columns (OLS, RF, 2SLS) ",
                               "reports a separate binary outcome: any visit of that type in a CWS-year. ",
                               "Sanitary visits are sanitary surveys and follow-up sanitary surveys. ",
                               "Technical assistance includes technical assistance, engineering ",
                               "determination/advice/plan review, and operation and maintenance visits. ",
                               "Enforcement visits include formal enforcement, investigation, and emergency ",
                               "assistance visits. Sample collection is sample collection visits. Inspection ",
                               "includes site inspections, regularly scheduled visits, and informal system ",
                               "inspections. ",
                               "The endogenous regressor is coal production, in millions of short tons, ",
                               "summed across the watersheds directly upstream of the CWS intake. ",
                               "The instrument interacts an indicator for the post-1995 period with mean ",
                               "upstream coal sulfur content. SEs clustered at the CWS level. ",
                               "*** p$<$0.01, ** p$<$0.05, * p$<$0.1."),
       style.tex      = style.tex("aer", adjustbox = TRUE),
       tex            = TRUE,
       postprocess.tex = postprocess_table,
       file           = out_tex_b,
       replace        = TRUE)
cat(sprintf("\nTable saved to: %s\n", out_tex_b))
if (file.exists(out_tex_b) && file.info(out_tex_b)$size > 0) {
  cat("Output verified: file exists and is non-zero.\n")
} else {
  stop("Output file missing or empty — check etable() call.")
}

# H3 table: informal vs formal, D1 main sample
out_tex_h3_inf <- file.path(ROOT, "output/reg/h3_inf_formal_d12_ivsumcoaltons.tex")
inf_d1_pct <- 100 * mean(panel_d1$any_informal)
frm_d1_pct <- 100 * mean(panel_d1$any_formal)
ned1_pct   <- 100 * mean(panel_d1$no_enf)
f_label_d1 <- "F-test (1st stage, clustered), Upstream coal production (mil. short tons)"
f_vec_d1   <- c("", "", format(round(f_cl_d1, 2), nsmall = 2),
                "", "", format(round(f_cl_d1, 2), nsmall = 2),
                "", "", format(round(f_cl_d1, 2), nsmall = 2))
el_d1 <- list(f_vec_d1)
names(el_d1) <- f_label_d1

dict_enf <- c(
  "any_informal"                                       = "Any informal enf",
  "any_formal"                                         = "Any formal enf",
  "no_enf"                                              = "No enforcement",
  "production_short_tons_coal_upstream_sum_mil"        = "Upstream coal production (mil. short tons)",
  "fit_production_short_tons_coal_upstream_sum_mil"    = "Upstream coal production (mil. short tons)",
  "post95:sulfur_unified_mean"                         = "post95 $\\times$ Upstream sulfur \\%",
  "PWSID"                                              = "CWS"
)

etable(ols_id1, rf_id1, iv_id1, ols_fd1, rf_fd1, iv_fd1, ols_ned1, rf_ned1, iv_ned1,
       title          = "Effect of Coal Production on Enforcement Actions by Type (D1 Downstream Sample)",
       label          = "tab:h3_inf_formal_d12_ivsumcoaltons",
       dict           = dict_enf,
       drop           = "num_facilities",
       extralines     = el_d1,
       fitstat        = ~n,
       notes          = paste0("\\textit{Notes:} Sample restricted to community water systems strictly ",
                               "downstream of a coal mine. ",
                               "Cols 1-3: informal enforcement action (",
                               sprintf("%.1f", inf_d1_pct), "% of panel). ",
                               "Cols 4-6: formal enforcement action (",
                               sprintf("%.1f", frm_d1_pct), "% of panel). ",
                               "Cols 7-9: no enforcement (",
                               sprintf("%.1f", ned1_pct), "% of panel). ",
                               "The endogenous regressor is coal production, in millions of short tons, ",
                               "summed across the watersheds directly upstream of the CWS intake. ",
                               "The instrument interacts an indicator for the post-1995 period with mean ",
                               "upstream coal sulfur content. SEs clustered at the CWS level. ",
                               "*** p$<$0.01, ** p$<$0.05, * p$<$0.1."),
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

cat("\nDone.\n")
