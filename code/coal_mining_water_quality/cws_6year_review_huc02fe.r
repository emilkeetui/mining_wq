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
  num_facilities                  = "Num. intake facilities"
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
    chems       = c("arsenic", "nitrate", "thallium",
                    "barium", "cadmium", "chromium", "mercury", "selenium")
    # Silver excluded: secondary MCL only (40 CFR 143.3); no SYR2/SYR3 data.
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
  coal_prod_upstream_cumsum_10mst = "Cumul. upstream coal prod. (10M ST)",
  num_facilities                  = "Num. intake facilities"
)

# ---------------------------------------------------------------------------
# run_count_tables(): same chemical groups as run_group_tables() but with
#   num_measurements as the sole outcome (one column per chemical).
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
                               "number of measurements — ", grp$group_label,
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

cat("\nDone.\n")
