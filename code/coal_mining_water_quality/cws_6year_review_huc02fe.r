# ============================================================
# Script: cws_6year_review_huc02fe.r
# Purpose: Estimate effect of cumulative upstream coal production on
#          mean analyte concentration AND share of samples above MCL
#          (EPA 6-Year Review), grouped by SDWA chemical category.
#          PWSID + HUC02 x year fixed effects.
#          Main sample: 1998-2011. Robustness: 1998-2005.
# Inputs:  clean_data/cws_6year_review.parquet
#          clean_data/cws_data/pwsid_huc02.parquet
# Outputs: output/reg/6yr_huc02fe_<group>.tex        (main, 1998-2011)
#          output/reg/6yr_huc02fe_<group>_2005.tex   (robustness, 1998-2005)
# Author: EK  Date: 2026-05-27
# ============================================================

.libPaths("Z:/ek559/RPackages")
library(fixest)
library(arrow)
library(dplyr)

PROJECT_ROOT <- "Z:/ek559/mining_wq"
SIX_YR_PATH  <- file.path(PROJECT_ROOT, "clean_data", "cws_6year_review.parquet")
HUC02_PATH   <- file.path(PROJECT_ROOT, "clean_data", "cws_data", "pwsid_huc02.parquet")
OUTPUT_DIR   <- file.path(PROJECT_ROOT, "output", "reg")

# ---------------------------------------------------------------------------
# LaTeX helpers
# ---------------------------------------------------------------------------
move_notes_below_adjustbox <- function(x) {
  x <- paste(x, collapse = "\n")
  end_adj <- "\\end{adjustbox}"
  par_rag <- "\\par \\raggedright"
  par_pos     <- regexpr(par_rag, x, fixed = TRUE)
  end_adj_pos <- regexpr(end_adj, x, fixed = TRUE)
  if (par_pos[1] == -1 || end_adj_pos[1] == -1) return(x)
  note_block <- substr(x, par_pos[1], end_adj_pos[1] - 1)
  x <- sub(note_block, "", x, fixed = TRUE)
  x <- sub(end_adj, paste0(end_adj, "\n   {\\tiny\\linespread{1}\\selectfont ",
                            trimws(note_block), "}"), x, fixed = TRUE)
  x
}

# ---------------------------------------------------------------------------
# Load data
# ---------------------------------------------------------------------------
cat("Reading:", SIX_YR_PATH, "\n")
df6 <- read_parquet(SIX_YR_PATH)
cat("Loaded:", nrow(df6), "rows x", ncol(df6), "columns\n")

cat("Reading:", HUC02_PATH, "\n")
huc02 <- read_parquet(HUC02_PATH)
cat("HUC02 lookup:", nrow(huc02), "rows\n")

stopifnot(is.character(df6$PWSID))
stopifnot(is.character(huc02$PWSID))
stopifnot(is.character(huc02$huc02))
cat("HUC02 length check (all 2 chars):", all(nchar(huc02$huc02) == 2), "\n")

# ---------------------------------------------------------------------------
# Data prep
# ---------------------------------------------------------------------------
df6 <- df6 |> left_join(huc02 |> select(PWSID, huc02), by = "PWSID")
cat("Rows with missing HUC02 after merge:", sum(is.na(df6$huc02)), "\n")

# Keep 1985+ for cumulative production construction; no upper year cut here
df6 <- df6[df6$year >= 1985, ]
df6 <- df6[df6$PWSID != "WV3303401", ]
df6 <- df6[df6$minehuc_downstream_of_mine == 1 & df6$minehuc_mine == 0, ]
cat("Downstream rows (1985+):", nrow(df6), "\n")
cat("Unique downstream PWSIDs:", length(unique(df6$PWSID)), "\n")

# Cumulative upstream production since 1985 (computed over full time series)
cum_panel <- df6 |>
  distinct(PWSID, year, production_short_tons_coal_upstream_sum) |>
  arrange(PWSID, year) |>
  group_by(PWSID) |>
  mutate(coal_prod_upstream_cumsum =
           cumsum(replace(production_short_tons_coal_upstream_sum,
                          is.na(production_short_tons_coal_upstream_sum), 0))) |>
  ungroup() |>
  select(PWSID, year, coal_prod_upstream_cumsum)

df6 <- df6 |> left_join(cum_panel, by = c("PWSID", "year"))

chk <- df6 |>
  distinct(PWSID, year, coal_prod_upstream_cumsum) |>
  arrange(PWSID, year) |>
  group_by(PWSID) |>
  mutate(diff = coal_prod_upstream_cumsum - lag(coal_prod_upstream_cumsum))
stopifnot(all(chk$diff >= 0 | is.na(chk$diff)))
cat("Cumsum monotonicity check: PASSED\n")

df6$coal_prod_upstream_cumsum_10mst <- df6$coal_prod_upstream_cumsum / 1e7

# Keep rows with a 6-Year Review observation (yields 1998-2011)
df6 <- df6[!is.na(df6$VALUE), ]
cat("Rows with non-missing VALUE:", nrow(df6),
    "| year range:", min(df6$year), "-", max(df6$year), "\n\n")

# ---------------------------------------------------------------------------
# Regression formulas
# ---------------------------------------------------------------------------
fml_val <- VALUE            ~ coal_prod_upstream_cumsum_10mst + num_facilities | PWSID + huc02^year
fml_shr <- share_above_mcl  ~ coal_prod_upstream_cumsum_10mst + num_facilities | PWSID + huc02^year
fml_cnt <- num_measurements ~ coal_prod_upstream_cumsum_10mst + num_facilities | PWSID + huc02^year
fml_max <- VALUE_max         ~ coal_prod_upstream_cumsum_10mst + num_facilities | PWSID + huc02^year

# ---------------------------------------------------------------------------
# Table notes
# ---------------------------------------------------------------------------
note_base <- paste0(
  "Within each chemical, columns show (1) mean measured concentration and ",
  "(2) share of annual samples exceeding the MCL, both from the EPA 6-Year Review. ",
  "Explanatory variable is cumulative coal production since 1985 ",
  "(in 10 million short tons) in the HUC12 one step upstream of the CWS intake. ",
  "Fixed effects: PWSID and HUC02$\\times$year (first two digits of intake HUC12 ",
  "interacted with year). ",
  "Sample: CWSs at most one HUC12 downstream of a coal mine ",
  "(minehuc\\_downstream\\_of\\_mine = 1, minehuc\\_mine = 0). ",
  "Standard errors clustered at PWSID level."
)

note_main  <- paste0("Sample period 1998--2011. ", note_base)
note_2005  <- paste0("Sample period 1998--2005 (robustness). ", note_base)
# Total coliform (TCR) data are available in the 6-Year Review only for 2006--2008 (SYR3).
note_tc_main <- paste0(
  "Sample period 2006--2008 (EPA Six-Year Review 3; TCR data not included in SYR2). ",
  note_base,
  " Outcome is the fraction of annual samples testing positive for total coliform ",
  "under the Total Coliform Rule (40 CFR 141.63; 54 FR 27544, Jun 29 1989)."
)
note_tc_2005 <- paste0(
  "Total coliform data available only for 2006--2008 (SYR3); ",
  "no observations in the 1998--2005 robustness window. Table omitted."
)

dict_global <- c(
  VALUE                           = "Mean conc.",
  share_above_mcl                 = "Share $>$ MCL",
  coal_prod_upstream_cumsum_10mst = "Cumul. upstream coal prod. (10M ST)",
  num_facilities                  = "Num. intake facilities",
  "PWSID"                         = "CWS"
)

# ---------------------------------------------------------------------------
# Chemical groups (SDWA categories)
# Each group may optionally specify:
#   outcomes — "both" (default), "value_only", or "shr_only"
#   dict     — named character vector passed to etable() dict=; defaults to dict_global
# ---------------------------------------------------------------------------
chem_groups <- list(
  list(
    group_label = "Inorganic Chemicals",
    file_label  = "inorg",
    # Cadmium (1.8%) and mercury (1.6%) dropped by Ravalli et al. detection-rate filter
    # (DETECT_RATE_MIN = 0.10 in cws_6year_review.py). Silver excluded: secondary MCL only.
    chems       = c("arsenic", "nitrate", "thallium",
                    "barium", "chromium", "selenium")
  ),
  list(
    group_label = "Radionuclides",
    file_label  = "radio",
    chems       = c("alpha particles", "beta particles", "radium", "uranium")
  ),
  list(
    group_label = "Volatile Organic Chemicals (VOCs)",
    file_label  = "voc",
    chems       = c("benzene", "carbon tetrachloride",
                    "1,2-dichloroethane", "1,1-dichloroethylene",
                    "1,1,1-trichloroethane", "vinyl chloride",
                    "p-dichlorobenzene", "trichloroethylene")
  ),
  list(
    group_label = "Synthetic Organic Chemicals (SOCs)",
    file_label  = "soc",
    chems       = c("2,4-D", "2,4,5-TP (Silvex)", "endrin",
                    "lindane", "methoxychlor", "toxaphene")
  ),
  list(
    group_label = "Total Coliforms",
    file_label  = "tc",
    chems       = c("total coliform"),
    outcomes    = "value_only",   # VALUE = fraction of samples positive; share_above_mcl
                                   # is identical after collapsing presence/absence data
    note        = note_tc_main,   # TC-specific note (data 2006-2008 only)
    dict        = c(
      VALUE                           = "Frac. positive",
      coal_prod_upstream_cumsum_10mst = "Cumul. upstream coal prod. (10M ST)",
      num_facilities                  = "Num. intake facilities"
    )
  )
)

# Pretty column-header labels for each chemical
nice_chem <- function(x) {
  switch(x,
    # IOCs
    "arsenic"                = "Arsenic",
    "nitrate"                = "Nitrate",
    "thallium"               = "Thallium",
    "barium"                 = "Barium",
    "cadmium"                = "Cadmium",
    "chromium"               = "Chromium",
    "mercury"                = "Mercury",
    "selenium"               = "Selenium",
    # SOCs
    "2,4-D"                  = "2,4-D",
    "2,4,5-TP (Silvex)"      = "Silvex",
    "endrin"                 = "Endrin",
    "lindane"                = "Lindane",
    "methoxychlor"           = "Methoxychlor",
    "toxaphene"              = "Toxaphene",
    # VOCs
    "benzene"                = "Benzene",
    "carbon tetrachloride"   = "Carbon tet.",
    "1,2-dichloroethane"     = "1,2-DCE",
    "p-dichlorobenzene"      = "p-DCB",
    "1,1-dichloroethylene"   = "1,1-DCE",
    "1,1,1-trichloroethane"  = "1,1,1-TCA",
    "trichloroethylene"      = "TCE",
    "vinyl chloride"         = "Vinyl Cl.",
    # Radionuclides
    "alpha particles"        = "Alpha part.",
    "beta particles"         = "Beta part.",
    "radium"                 = "Radium",
    "uranium"                = "Uranium",
    # Total Coliforms
    "total coliform"         = "Total coliform",
    tools::toTitleCase(x)
  )
}

# ---------------------------------------------------------------------------
# run_group_tables(): estimate and write one table per chemical group
#   df        — analysis dataset (already filtered to desired sample period)
#   note      — table footnote string
#   file_sfx  — suffix appended to output file name (e.g. "" or "_2005")
#   title_sfx — appended to table title (e.g. "" or ", robustness 1998--2005")
#
# Per-group options (set in chem_groups list):
#   outcomes  — "both" (default): VALUE + share_above_mcl per chemical
#               "value_only":    VALUE model only
#               "shr_only":      share_above_mcl model only
#   dict      — named character vector for etable(); defaults to dict_global
# ---------------------------------------------------------------------------
run_group_tables <- function(df, note, file_sfx, title_sfx) {
  for (grp in chem_groups) {
    cat("\n--- Group:", grp$group_label, file_sfx, "---\n")

    if (length(grp$chems) == 0) {
      cat("  No chemicals defined — skipping.\n")
      next
    }

    outcomes_mode <- if (!is.null(grp$outcomes)) grp$outcomes else "both"
    grp_dict      <- if (!is.null(grp$dict))     grp$dict     else dict_global
    grp_note      <- if (!is.null(grp$note))     grp$note     else note

    models_list <- list()
    hdr_vec     <- character(0)

    for (chem in grp$chems) {
      d <- df[df$CHEMID_name == chem, ]
      cat("  Chemical:", chem, "| n rows:", nrow(d), "\n")

      if (nrow(d) < 30) {
        cat("  Skipping — too few obs.\n")
        next
      }

      nm <- nice_chem(chem)

      if (outcomes_mode %in% c("both", "value_only")) {
        m_val <- tryCatch(
          feols(fml_val, data = d, cluster = ~PWSID),
          error = function(e) { cat("  ERROR (VALUE):", conditionMessage(e), "\n"); NULL }
        )
        if (!is.null(m_val)) {
          models_list <- c(models_list, list(m_val))
          hdr_vec     <- c(hdr_vec, nm)
          cat("  n_val =", m_val$nobs,
              "| coef_val =", round(coef(m_val)["coal_prod_upstream_cumsum_10mst"], 4), "\n")
        }
      }

      if (outcomes_mode %in% c("both", "shr_only")) {
        # share_above_mcl requires variation; skip if constant (e.g. all zeros)
        shr_var <- var(d$share_above_mcl, na.rm = TRUE)
        if (is.na(shr_var) || shr_var == 0) {
          cat("  share_above_mcl is constant — skipping share model.\n")
        } else {
          m_shr <- tryCatch(
            feols(fml_shr, data = d, cluster = ~PWSID),
            error = function(e) { cat("  ERROR (share_above_mcl):", conditionMessage(e), "\n"); NULL }
          )
          if (!is.null(m_shr)) {
            models_list <- c(models_list, list(m_shr))
            hdr_vec     <- c(hdr_vec, nm)  # repeated name → multicolumn with m_val
            cat("  n_shr =", m_shr$nobs,
                "| coef_shr =", round(coef(m_shr)["coal_prod_upstream_cumsum_10mst"], 4), "\n")
          }
        }
      }
    }

    if (length(models_list) == 0) {
      cat("  No models estimated — skipping table output.\n")
      next
    }

    out <- file.path(OUTPUT_DIR,
                     paste0("6yr_huc02fe_", grp$file_label, file_sfx, ".tex"))

    etable(
      models_list,
      headers         = hdr_vec,
      fitstat         = ~ . + n + r2,
      style.tex       = style.tex("aer", adjustbox = TRUE),
      tex             = TRUE,
      drop            = "^num_facilities$",
      title           = paste0("Effect of cumulative upstream coal production on ",
                               grp$group_label, " (6-Year Review, downstream CWSs",
                               title_sfx, ")"),
      label           = paste0("tab:6yr_huc02fe_", grp$file_label, file_sfx),
      dict            = grp_dict,
      notes           = grp_note,
      postprocess.tex = move_notes_below_adjustbox,
      file            = out
    )
    cat("  Written:", out, "\n")
  }
}

# ---------------------------------------------------------------------------
# Notes and dict for count (num_measurements) tables
# ---------------------------------------------------------------------------
note_cnt_base <- paste0(
  "Outcome is the number of annual measurements of the analyte recorded ",
  "for each CWS in the EPA 6-Year Review. ",
  "Explanatory variable is cumulative coal production since 1985 ",
  "(in 10 million short tons) in the HUC12 one step upstream of the CWS intake. ",
  "Fixed effects: PWSID and HUC02$\\times$year (first two digits of intake HUC12 ",
  "interacted with year). ",
  "Sample: CWSs at most one HUC12 downstream of a coal mine ",
  "(minehuc\\_downstream\\_of\\_mine = 1, minehuc\\_mine = 0). ",
  "Standard errors clustered at PWSID level."
)

note_cnt_main <- paste0("Sample period 1998--2011. ", note_cnt_base)
note_cnt_2005 <- paste0("Sample period 1998--2005 (robustness). ", note_cnt_base)
note_tc_cnt_main <- paste0(
  "Sample period 2006--2008 (EPA Six-Year Review 3; TCR data not included in SYR2). ",
  note_cnt_base,
  " Number of presence/absence coliform tests conducted under the Total Coliform Rule ",
  "(40 CFR 141.63; 54 FR 27544, Jun 29 1989)."
)

dict_cnt <- c(
  num_measurements                = "Num. measurements",
  VALUE                           = "Mean concentration",
  VALUE_max                       = "Max concentration",
  coal_prod_upstream_cumsum_10mst = "Cumul. upstream coal prod. (10M ST)",
  num_facilities                  = "Num. intake facilities",
  "PWSID"                         = "CWS"
)

# ---------------------------------------------------------------------------
# run_count_tables(): same chemical groups as run_group_tables() but with
#   num_measurements, mean VALUE, and max VALUE as outcomes (three columns
#   per chemical, grouped under a multicolumn header).
# ---------------------------------------------------------------------------
run_count_tables <- function(df, note, file_sfx, title_sfx) {
  for (grp in chem_groups) {
    cat("\n--- Count | Group:", grp$group_label, file_sfx, "---\n")

    if (length(grp$chems) == 0) {
      cat("  No chemicals defined — skipping.\n")
      next
    }

    grp_note <- if (!is.null(grp$note)) {
      # Replace TC-specific note with count equivalent
      note_tc_cnt_main
    } else {
      note
    }

    models_list <- list()
    hdr_vec     <- character(0)

    for (chem in grp$chems) {
      d <- df[df$CHEMID_name == chem, ]
      cat("  Chemical:", chem, "| n rows:", nrow(d), "\n")

      if (nrow(d) < 30) {
        cat("  Skipping — too few obs.\n")
        next
      }

      nm <- nice_chem(chem)

      m_cnt <- tryCatch(
        feols(fml_cnt, data = d, cluster = ~PWSID),
        error = function(e) { cat("  ERROR (num_measurements):", conditionMessage(e), "\n"); NULL }
      )
      if (!is.null(m_cnt)) {
        models_list <- c(models_list, list(m_cnt))
        hdr_vec     <- c(hdr_vec, nm)
        cat("  n_cnt =", m_cnt$nobs,
            "| coef_cnt =", round(coef(m_cnt)["coal_prod_upstream_cumsum_10mst"], 4), "\n")
      }

      m_val <- tryCatch(
        feols(fml_val, data = d, cluster = ~PWSID),
        error = function(e) { cat("  ERROR (VALUE mean):", conditionMessage(e), "\n"); NULL }
      )
      if (!is.null(m_val)) {
        models_list <- c(models_list, list(m_val))
        hdr_vec     <- c(hdr_vec, nm)
        cat("  n_val =", m_val$nobs,
            "| coef_val =", round(coef(m_val)["coal_prod_upstream_cumsum_10mst"], 4), "\n")
      }

      m_max <- tryCatch(
        feols(fml_max, data = d, cluster = ~PWSID),
        error = function(e) { cat("  ERROR (VALUE max):", conditionMessage(e), "\n"); NULL }
      )
      if (!is.null(m_max)) {
        models_list <- c(models_list, list(m_max))
        hdr_vec     <- c(hdr_vec, nm)
        cat("  n_max =", m_max$nobs,
            "| coef_max =", round(coef(m_max)["coal_prod_upstream_cumsum_10mst"], 4), "\n")
      }
    }

    if (length(models_list) == 0) {
      cat("  No models estimated — skipping table output.\n")
      next
    }

    out <- file.path(OUTPUT_DIR,
                     paste0("6yr_huc02fe_cnt_", grp$file_label, file_sfx, ".tex"))

    etable(
      models_list,
      headers         = hdr_vec,
      fitstat         = ~ . + n + r2,
      style.tex       = style.tex("aer", adjustbox = TRUE),
      tex             = TRUE,
      drop            = "^num_facilities$",
      title           = paste0("Effect of cumulative upstream coal production on ",
                               "measurements and concentration — ", grp$group_label,
                               " (6-Year Review, downstream CWSs", title_sfx, ")"),
      label           = paste0("tab:6yr_huc02fe_cnt_", grp$file_label, file_sfx),
      dict            = dict_cnt,
      notes           = grp_note,
      postprocess.tex = move_notes_below_adjustbox,
      file            = out
    )
    cat("  Written:", out, "\n")
  }
}

# ---------------------------------------------------------------------------
# Main run: 1998-2011 (all rows with non-missing VALUE)
# ---------------------------------------------------------------------------
cat("=== MAIN SAMPLE: 1998-2011 ===\n")
run_group_tables(df6, note_main, file_sfx = "", title_sfx = "")

# ---------------------------------------------------------------------------
# Robustness run: 1998-2005
# ---------------------------------------------------------------------------
cat("\n=== ROBUSTNESS: 1998-2005 ===\n")
df6_2005 <- df6[df6$year <= 2005, ]
cat("Rows (1998-2005):", nrow(df6_2005),
    "| year range:", min(df6_2005$year), "-", max(df6_2005$year), "\n")
run_group_tables(df6_2005, note_2005, file_sfx = "_2005", title_sfx = ", robustness 1998--2005")
# Total coliform has no obs in 1998-2005 (SYR3 only covers 2006-2008); no table produced.

# ---------------------------------------------------------------------------
# Count tables: num_measurements as outcome
# ---------------------------------------------------------------------------
cat("\n=== COUNT TABLES (num_measurements): MAIN SAMPLE 1998-2011 ===\n")
run_count_tables(df6, note_cnt_main, file_sfx = "", title_sfx = "")

cat("\n=== COUNT TABLES (num_measurements): ROBUSTNESS 1998-2005 ===\n")
run_count_tables(df6_2005, note_cnt_2005, file_sfx = "_2005", title_sfx = ", robustness 1998--2005")
# Total coliform has no obs in 1998-2005; no cnt_tc_2005 table produced.

# ---------------------------------------------------------------------------
# Share-above-MCL inorganic table: share of samples exceeding applicable MCL,
# no R^2 rows, no num_facilities row in display (variable kept in regression).
# Output: 6yr_huc02fe_inorg_val.tex
# ---------------------------------------------------------------------------
cat("\n=== INORGANIC CHEMICALS — SHARE ABOVE MCL ===\n")
{
  grp_inorg <- chem_groups[[1]]  # inorganic chemicals
  # Thallium excluded: 86% of values cluster at two detection-limit values,
  # making share_above_mcl unreliable (near-zero variance in binary exceedance).
  inorg_val_chems <- setdiff(grp_inorg$chems, "thallium")

  note_val <- paste0(
    "Sample period 1998--2011. ",
    "Outcome is the mean measured concentration of the analyte in a given CWS-year ",
    "from the EPA 6-Year Review (Ravalli et al.~2022 cleaning). ",
    "For arsenic, the MCL is 0.050 mg/L through 2005 and 0.010 mg/L from 2006 onward. ",
    "Explanatory variable is cumulative coal production since 1985 ",
    "(in 10 million short tons) in the HUC12 one step upstream of the CWS intake. ",
    "Fixed effects: PWSID and HUC02$\\times$year (first two digits of intake HUC12 ",
    "interacted with year). ",
    "Sample: CWSs at most one HUC12 downstream of a coal mine ",
    "(minehuc\\_downstream\\_of\\_mine = 1, minehuc\\_mine = 0). ",
    "Standard errors clustered at PWSID level."
  )

  models_val <- list()
  hdr_val    <- character(0)

  for (chem in inorg_val_chems) {
    d <- df6[df6$CHEMID_name == chem, ]
    cat("  Chemical:", chem, "| n rows:", nrow(d), "\n")
    if (nrow(d) < 30) { cat("  Skipping — too few obs.\n"); next }

    m <- tryCatch(
      feols(fml_val, data = d, cluster = ~PWSID),
      error = function(e) { cat("  ERROR:", conditionMessage(e), "\n"); NULL }
    )
    if (!is.null(m)) {
      models_val <- c(models_val, list(m))
      hdr_val    <- c(hdr_val, nice_chem(chem))
      cat("  n =", m$nobs,
          "| coef =", round(coef(m)["coal_prod_upstream_cumsum_10mst"], 6), "\n")
    }
  }

  out_val <- file.path(OUTPUT_DIR, "6yr_huc02fe_inorg_val.tex")
  etable(
    models_val,
    headers         = hdr_val,
    fitstat         = ~ n,            # observations only; no R^2 or Within R^2
    style.tex       = style.tex("aer", adjustbox = TRUE),
    tex             = TRUE,
    drop            = "Num\\.",       # matches "Num. intake facilities" label (dict active)
    title           = paste0("Effect of cumulative upstream coal production on ",
                             "mean measured concentration ",
                             "(6-Year Review, downstream CWSs)"),
    label           = "tab:6yr_huc02fe_inorg_val",
    dict            = dict_global,
    notes           = note_val,
    postprocess.tex = move_notes_below_adjustbox,
    file            = out_val
  )
  cat("  Written:", out_val, "\n")

  # -------------------------------------------------------------------------
  # Summary statistics for 6yr_huc02fe_inorg_val.tex
  # Rows: one per inorganic chemical (share_above_mcl) + one for cumulative coal prod
  # Sample: complete cases used in each chemical's feols regression
  # -------------------------------------------------------------------------
  cat("\n--- Summary statistics for inorg_val ---\n")

  sum_rows  <- list()
  coal_list <- list()

  # MCL labels sourced from _MCL_RECORDS in cws_6year_review.py
  mcl_labels <- c(
    "arsenic"  = "Pre-2006: 0.050 mg/L, 2006+: 0.010 mg/L",
    "nitrate"  = "10.0 mg/L",
    "barium"   = "2.000 mg/L",
    "cadmium"  = "0.005 mg/L",
    "chromium" = "0.100 mg/L",
    "mercury"  = "0.002 mg/L",
    "selenium" = "0.050 mg/L"
  )

  for (chem in inorg_val_chems) {
    d_s <- df6[df6$CHEMID_name == chem, ]
    if (nrow(d_s) < 30) next

    m_s <- tryCatch(
      feols(fml_val, data = d_s, cluster = ~PWSID),
      error = function(e) NULL
    )
    if (is.null(m_s)) next

    keep_s <- complete.cases(d_s[, c("VALUE", "VALUE_max", "coal_prod_upstream_cumsum_10mst",
                                      "num_facilities", "huc02", "year", "PWSID")])
    d_reg_s <- d_s[keep_s, ]
    cat("  ", chem, ": n_complete =", nrow(d_reg_s), "| feols nobs =", m_s$nobs, "\n")

    sum_rows[[chem]] <- data.frame(
      variable  = paste0(nice_chem(chem), " (mg/L)"),
      mcl_label = ifelse(chem %in% names(mcl_labels), mcl_labels[[chem]], "---"),
      mean_val  = mean(d_reg_s$VALUE,     na.rm = TRUE),
      max_val   = max(d_reg_s$VALUE_max,  na.rm = TRUE),
      sd_val    = sd(d_reg_s$VALUE,       na.rm = TRUE),
      n_obs     = nrow(d_reg_s),
      stringsAsFactors = FALSE
    )
    coal_list[[chem]] <- d_reg_s[, c("PWSID", "year", "coal_prod_upstream_cumsum_10mst")]
  }

  # Coal production: unique PWSID x year pairs across all regression samples
  coal_df <- unique(do.call(rbind, coal_list))
  coal_df <- coal_df[!duplicated(coal_df[, c("PWSID", "year")]), ]
  sum_rows[["coal"]] <- data.frame(
    variable  = "Cumul. upstream coal prod. (10M ST)",
    mcl_label = "---",
    mean_val  = mean(coal_df$coal_prod_upstream_cumsum_10mst, na.rm = TRUE),
    max_val   = max(coal_df$coal_prod_upstream_cumsum_10mst,  na.rm = TRUE),
    sd_val    = sd(coal_df$coal_prod_upstream_cumsum_10mst,   na.rm = TRUE),
    n_obs     = sum(!is.na(coal_df$coal_prod_upstream_cumsum_10mst)),
    stringsAsFactors = FALSE
  )

  sum_df <- do.call(rbind, sum_rows)

  fmt_num <- function(x) {
    if (is.na(x)) return("---")
    a <- abs(x)
    if (a == 0)   return("0.0000")
    if (a < 1e-4) return(sprintf("%.2e", x))
    if (a < 1)    return(sprintf("%.4f", x))
    if (a < 100)  return(sprintf("%.3f", x))
    return(sprintf("%.2f", x))
  }
  fmt_n <- function(x) formatC(x, format = "d", big.mark = ",")

  note_ss <- paste0(
    "Sample period 1998--2011. ",
    "Statistics computed on the sample used in each chemical's regression in ",
    "Table~\\ref{tab:6yr_huc02fe_inorg_val}. ",
    "For cumulative upstream coal production, statistics are computed over unique ",
    "PWSID$\\times$year pairs that appear in at least one regression sample. ",
    "Sample: CWSs at most one HUC12 downstream of a coal mine ",
    "(minehuc\\_downstream\\_of\\_mine = 1, minehuc\\_mine = 0)."
  )

  tex_ss <- c(
    "",
    "\\begin{table}[htbp]",
    paste0("   \\caption{\\label{tab:6yr_huc02fe_inorg_val_sumstats} ",
           "Summary statistics: mean concentration for inorganic chemicals and cumulative upstream coal production}"),
    "   \\bigskip",
    "   \\centering",
    "   \\begin{adjustbox}{width = 0.9\\textwidth, center}",
    "      \\begin{tabular}{lp{3.8cm}cccc}",
    "         \\toprule",
    "         Variable & MCL & Mean & Max & Std.\\ Dev. & $N$ \\\\",
    "         \\midrule"
  )

  for (i in seq_len(nrow(sum_df))) {
    r <- sum_df[i, ]
    tex_ss <- c(tex_ss, paste0(
      "         ", r$variable, " & ",
      r$mcl_label, " & ",
      fmt_num(r$mean_val), " & ",
      fmt_num(r$max_val), " & ",
      fmt_num(r$sd_val), " & ",
      fmt_n(r$n_obs), " \\\\"
    ))
  }

  tex_ss <- c(tex_ss,
    "         \\bottomrule",
    "      \\end{tabular}",
    "   \\end{adjustbox}",
    paste0("   {\\tiny\\linespread{1}\\selectfont \\par \\raggedright ", note_ss, "}"),
    "\\end{table}",
    ""
  )

  out_ss <- file.path(PROJECT_ROOT, "output", "sum", "6yr_huc02fe_inorg_val_sumstats.tex")
  writeLines(tex_ss, out_ss)
  cat("  Written:", out_ss, "\n")
}

# ---------------------------------------------------------------------------
# Scatter plot: beta particle mean concentration vs cumulative upstream coal
# production. Each point = one PWSID-year observation.
# ---------------------------------------------------------------------------
cat("\n=== SCATTER: beta particles vs cumulative upstream coal production ===\n")
suppressPackageStartupMessages(library(ggplot2))

beta_df <- df6[df6$CHEMID_name == "beta particles", ]
cat("Beta particles observations:", nrow(beta_df), "\n")
cat("Unique PWSIDs:", length(unique(beta_df$PWSID)), "\n")

# Aggregate to PWSID mean for annotation counts
beta_pwsid <- aggregate(
  cbind(VALUE, coal_prod_upstream_cumsum_10mst) ~ PWSID,
  data  = beta_df,
  FUN   = mean
)

p_beta <- ggplot(beta_df,
                 aes(x = coal_prod_upstream_cumsum_10mst, y = VALUE)) +
  geom_point(alpha = 0.55, size = 2, colour = "#2c6fad") +
  geom_smooth(method = "lm", se = TRUE, colour = "#d62728",
              linewidth = 0.85, fill = "#d62728", alpha = 0.15) +
  scale_x_continuous(name = "Cumulative upstream coal production since 1985\n(10 million short tons)") +
  scale_y_continuous(name = "Mean beta particle concentration\n(pCi/L, EPA 6-Year Review)") +
  annotate("text", x = Inf, y = Inf,
           label = paste0("N = ", nrow(beta_df), " PWSID-years\n",
                          length(unique(beta_df$PWSID)), " unique CWSs"),
           hjust = 1.05, vjust = 1.4, size = 3, colour = "grey30") +
  theme_classic(base_size = 11) +
  theme(
    axis.line   = element_line(colour = "black"),
    panel.grid  = element_blank()
  )

out_scatter <- file.path(PROJECT_ROOT, "output", "fig",
                         "beta_particles_vs_cumcoal_scatter.png")
ggsave(out_scatter, p_beta, width = 6, height = 4.5, dpi = 300)
cat("Written:", out_scatter, "\n")

cat("\nDone.\n")
