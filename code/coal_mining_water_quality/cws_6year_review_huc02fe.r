# ============================================================
# Script: cws_6year_review_huc02fe.r
# Purpose: Estimate effect of cumulative upstream coal production on
#          mean analyte concentration AND share of samples above MCL
#          (EPA 6-Year Review), grouped by SDWA chemical category.
#          PWSID + HUC02 x year fixed effects.
#          Main sample: 1998-2011. Robustness: 1998-2005.
#          Tables produced for both the standard dataset and the
#          Ravalli et al. (2022) MDL/sqrt(2)-imputed dataset.
# Inputs:  clean_data/cws_6year_review.parquet
#          clean_data/cws_6year_review_ravalli.parquet
#          clean_data/cws_data/pwsid_huc02.parquet
# Outputs: output/reg/6yr_huc02fe_<group>[_ravalli][_2005].tex
#          output/reg/6yr_huc02fe_inorg_val[_ravalli][_ravalli_2005].tex
#          output/sum/6yr_huc02fe_inorg_val[_ravalli][_ravalli_2005]_sumstats.tex
# Author: EK  Date: 2026-05-27
# ============================================================

.libPaths(c("C:/Users/ek559/AppData/Local/R/win-library/4.6", "Z:/ek559/RPackages"))
library(fixest)
library(arrow)
library(dplyr)

PROJECT_ROOT         <- "Z:/ek559/mining_wq"
SIX_YR_PATH          <- file.path(PROJECT_ROOT, "clean_data", "cws_6year_review.parquet")
SIX_YR_PATH_RAVALLI  <- file.path(PROJECT_ROOT, "clean_data", "cws_6year_review_ravalli.parquet")
HUC02_PATH           <- file.path(PROJECT_ROOT, "clean_data", "cws_data", "pwsid_huc02.parquet")
OUTPUT_DIR           <- file.path(PROJECT_ROOT, "output", "reg")

# ---------------------------------------------------------------------------
# LaTeX helper
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

# add_cmidrule_under_superheader(): inserts a \cmidrule rule line directly
# below the first multicolumn-spanning header row (e.g. the "Mean conc."
# depvar span), underlining just the spanned columns, booktabs-style.
add_cmidrule_under_superheader <- function(x) {
  x <- paste(x, collapse = "\n")
  lines <- strsplit(x, "\n")[[1]]
  toprule_idx <- which(grepl("\\toprule", lines, fixed = TRUE))[1]
  if (is.na(toprule_idx)) return(x)
  hdr_idx <- NA
  for (i in seq(toprule_idx + 1, length(lines))) {
    if (grepl("\\multicolumn", lines[i], fixed = TRUE)) { hdr_idx <- i; break }
    if (grepl("\\midrule", lines[i], fixed = TRUE)) break
  }
  if (is.na(hdr_idx)) return(x)

  cells <- strsplit(lines[hdr_idx], "&", fixed = TRUE)[[1]]
  col <- 0
  rule_parts <- character(0)
  for (cell in cells) {
    m <- regmatches(cell, regexpr("\\\\multicolumn\\{([0-9]+)\\}", cell))
    if (length(m) > 0 && nzchar(m)) {
      n <- as.integer(sub("\\\\multicolumn\\{([0-9]+)\\}.*", "\\1", m))
      rule_parts <- c(rule_parts, sprintf("\\cmidrule(lr){%d-%d}", col + 1, col + n))
      col <- col + n
    } else {
      col <- col + 1
    }
  }
  if (length(rule_parts) == 0) return(x)
  lines <- append(lines, paste(rule_parts, collapse = " "), after = hdr_idx)
  paste(lines, collapse = "\n")
}

# ---------------------------------------------------------------------------
# Load datasets
# ---------------------------------------------------------------------------
cat("Reading:", SIX_YR_PATH, "\n")
df6_raw  <- read_parquet(SIX_YR_PATH)
cat("Loaded:", nrow(df6_raw), "rows x", ncol(df6_raw), "columns\n")

cat("Reading:", SIX_YR_PATH_RAVALLI, "\n")
df6r_raw <- read_parquet(SIX_YR_PATH_RAVALLI)
cat("Loaded (Ravalli):", nrow(df6r_raw), "rows x", ncol(df6r_raw), "columns\n")

cat("Reading:", HUC02_PATH, "\n")
huc02 <- read_parquet(HUC02_PATH)
cat("HUC02 lookup:", nrow(huc02), "rows\n")

stopifnot(is.character(df6_raw$PWSID))
stopifnot(is.character(df6r_raw$PWSID))
stopifnot(is.character(huc02$PWSID))
stopifnot(is.character(huc02$huc02))
cat("HUC02 length check (all 2 chars):", all(nchar(huc02$huc02) == 2), "\n")

# ---------------------------------------------------------------------------
# Data prep function — applied identically to both datasets
# ---------------------------------------------------------------------------
prep_data <- function(df_raw, label = "") {
  df <- df_raw |> left_join(huc02 |> select(PWSID, huc02), by = "PWSID")
  cat(label, "Rows with missing HUC02 after merge:", sum(is.na(df$huc02)), "\n")

  # Keep 1985+ for cumulative production construction; no upper year cut here
  df <- df[df$year >= 1985, ]
  df <- df[df$PWSID != "WV3303401", ]
  df <- df[df$minehuc_downstream_of_mine == 1 & df$minehuc_mine == 0, ]
  cat(label, "Downstream rows (1985+):", nrow(df), "\n")
  cat(label, "Unique downstream PWSIDs:", length(unique(df$PWSID)), "\n")

  cum_panel <- df |>
    distinct(PWSID, year, production_short_tons_coal_upstream_sum) |>
    arrange(PWSID, year) |>
    group_by(PWSID) |>
    mutate(coal_prod_upstream_cumsum =
             cumsum(replace(production_short_tons_coal_upstream_sum,
                            is.na(production_short_tons_coal_upstream_sum), 0))) |>
    ungroup() |>
    select(PWSID, year, coal_prod_upstream_cumsum)

  df <- df |> left_join(cum_panel, by = c("PWSID", "year"))

  chk <- df |>
    distinct(PWSID, year, coal_prod_upstream_cumsum) |>
    arrange(PWSID, year) |>
    group_by(PWSID) |>
    mutate(diff = coal_prod_upstream_cumsum - lag(coal_prod_upstream_cumsum))
  stopifnot(all(chk$diff >= 0 | is.na(chk$diff)))
  cat(label, "Cumsum monotonicity check: PASSED\n")

  df$coal_prod_upstream_cumsum_10mst <- df$coal_prod_upstream_cumsum / 1e7

  # Keep rows with a 6-Year Review observation (yields 1998-2011)
  df <- df[!is.na(df$VALUE), ]
  cat(label, "Rows with non-missing VALUE:", nrow(df),
      "| year range:", min(df$year), "-", max(df$year), "\n\n")
  df
}

cat("=== Preparing standard dataset ===\n")
df6  <- prep_data(df6_raw,  label = "[std] ")

cat("=== Preparing Ravalli dataset ===\n")
df6r <- prep_data(df6r_raw, label = "[rav] ")

# ---------------------------------------------------------------------------
# Regression formulas (shared across both datasets)
# ---------------------------------------------------------------------------
fml_val <- VALUE            ~ coal_prod_upstream_cumsum_10mst + num_facilities | PWSID + huc02^year
fml_shr <- share_above_mcl  ~ coal_prod_upstream_cumsum_10mst + num_facilities | PWSID + huc02^year
fml_cnt <- num_measurements ~ coal_prod_upstream_cumsum_10mst + num_facilities | PWSID + huc02^year
fml_max <- VALUE_max         ~ coal_prod_upstream_cumsum_10mst + num_facilities | PWSID + huc02^year
# Detection-share outcome: detect_share = share of a CWS-year's samples that were
# detections (above the reporting/detection limit).
fml_dsh <- detect_share     ~ coal_prod_upstream_cumsum_10mst + num_facilities | PWSID + huc02^year

# ---------------------------------------------------------------------------
# Table notes
# Standard: SYR2 non-detects = MRL, SYR3 non-detects = missing (no imputation).
# Ravalli:  all non-detects replaced by MDL/sqrt(2) following Ravalli et al. 2022.
# ---------------------------------------------------------------------------
note_base_std <- paste0(
  "Within each chemical, columns show (1) mean measured concentration and ",
  "(2) share of annual samples exceeding the MCL, both from the EPA 6-Year Review. ",
  "Non-detect values are not imputed. ",
  "Explanatory variable is cumulative coal production since 1985 ",
  "(in 10 million short tons) one watershed upstream of the CWS intake. ",
  "Sample: community water systems strictly downstream of a coal mine. ",
  "Standard errors clustered at the CWS level. ",
  "*** p$<$0.01, ** p$<$0.05, * p$<$0.1."
)

note_base_rav <- paste0(
  "Within each chemical, columns show (1) mean measured concentration and ",
  "(2) share of annual samples exceeding the MCL, both from the EPA 6-Year Review. ",
  "Non-detect values replaced by MDL$/\\sqrt{2}$ following Ravalli et al.~(2022). ",
  "Explanatory variable is cumulative coal production since 1985 ",
  "(in 10 million short tons) one watershed upstream of the CWS intake. ",
  "Sample: community water systems strictly downstream of a coal mine. ",
  "Standard errors clustered at the CWS level. ",
  "*** p$<$0.01, ** p$<$0.05, * p$<$0.1."
)

# The 1998--2011 tables report both a mean-concentration and a share-above-MCL
# column for arsenic; the 1998--2005 tables report mean concentration only, so
# they take a one-part description of the columns.
note_base_std_2005 <- paste0(
  "Within each chemical, columns show mean measured concentration ",
  "from the EPA 6-Year Review. ",
  "Non-detect values are not imputed. ",
  "Explanatory variable is cumulative coal production since 1985 ",
  "(in 10 million short tons) one watershed upstream of the CWS intake. ",
  "Sample: community water systems strictly downstream of a coal mine. ",
  "Standard errors clustered at the CWS level. ",
  "*** p$<$0.01, ** p$<$0.05, * p$<$0.1."
)

note_base_rav_2005 <- paste0(
  "Within each chemical, columns show mean measured concentration ",
  "from the EPA 6-Year Review. ",
  "Non-detect values replaced by MDL$/\\sqrt{2}$ following Ravalli et al.~(2022). ",
  "Explanatory variable is cumulative coal production since 1985 ",
  "(in 10 million short tons) one watershed upstream of the CWS intake. ",
  "Sample: community water systems strictly downstream of a coal mine. ",
  "Standard errors clustered at the CWS level. ",
  "*** p$<$0.01, ** p$<$0.05, * p$<$0.1."
)

note_main_std  <- paste0("\\textit{Notes:} Sample period 1998--2011. ", note_base_std)
note_2005_std  <- paste0("\\textit{Notes:} Sample period 1998--2005. ", note_base_std_2005)
note_main_rav  <- paste0("\\textit{Notes:} Sample period 1998--2011. ", note_base_rav)
note_2005_rav  <- paste0("\\textit{Notes:} Sample period 1998--2005. ", note_base_rav_2005)

note_tc_main_std <- paste0(
  "\\textit{Notes:} Sample period 2006--2008 (EPA Six-Year Review 3; TCR data not included in SYR2). ",
  note_base_std,
  " Outcome is the fraction of annual samples testing positive for total coliform."
)
note_tc_main_rav <- paste0(
  "\\textit{Notes:} Sample period 2006--2008 (EPA Six-Year Review 3; TCR data not included in SYR2). ",
  note_base_rav,
  " Outcome is the fraction of annual samples testing positive for total coliform. ",
  "Total coliform presence/absence encoding is binary; MDL imputation is not applied."
)

dict_global <- c(
  VALUE                           = "Mean conc.",
  share_above_mcl                 = "Share $>$ MCL",
  detect_share                    = "Share of samples detected",
  coal_prod_upstream_cumsum_10mst = "Cumul. upstream coal prod. (10M ST)",
  num_facilities                  = "Num. intake facilities",
  "PWSID"                         = "CWS"
)

# ---------------------------------------------------------------------------
# Chemical groups (SDWA categories)
# ---------------------------------------------------------------------------
chem_groups <- list(
  list(
    group_label = "Inorganic Chemicals",
    file_label  = "inorg",
    # Cadmium (1.8%) and mercury (1.6%) dropped by detection-rate filter
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
    outcomes    = "value_only",   # VALUE = fraction positive; share_above_mcl identical
    is_tc       = TRUE,           # flag used by run_group_tables to select TC note
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
    "arsenic"                = "Arsenic",
    "nitrate"                = "Nitrate",
    "thallium"               = "Thallium",
    "barium"                 = "Barium",
    "cadmium"                = "Cadmium",
    "chromium"               = "Chromium",
    "mercury"                = "Mercury",
    "selenium"               = "Selenium",
    "2,4-D"                  = "2,4-D",
    "2,4,5-TP (Silvex)"      = "Silvex",
    "endrin"                 = "Endrin",
    "lindane"                = "Lindane",
    "methoxychlor"           = "Methoxychlor",
    "toxaphene"              = "Toxaphene",
    "benzene"                = "Benzene",
    "carbon tetrachloride"   = "Carbon tet.",
    "1,2-dichloroethane"     = "1,2-DCE",
    "p-dichlorobenzene"      = "p-DCB",
    "1,1-dichloroethylene"   = "1,1-DCE",
    "1,1,1-trichloroethane"  = "1,1,1-TCA",
    "trichloroethylene"      = "TCE",
    "vinyl chloride"         = "Vinyl Cl.",
    "alpha particles"        = "Alpha part.",
    "beta particles"         = "Beta part.",
    "radium"                 = "Radium",
    "uranium"                = "Uranium",
    "total coliform"         = "Total coliform",
    tools::toTitleCase(x)
  )
}

# ---------------------------------------------------------------------------
# run_group_tables(): estimate and write one table per chemical group.
#   df        — analysis dataset (already filtered to desired sample period)
#   note      — default table footnote string (used for non-TC groups)
#   note_tc   — footnote for the total coliforms group
#   file_sfx  — suffix appended to output file name (e.g. "", "_2005", "_ravalli")
#   title_sfx — appended to table title
# ---------------------------------------------------------------------------
run_group_tables <- function(df, note, file_sfx, title_sfx, note_tc = note_tc_main_std,
                             detect_for = character(0), exclude_chems = character(0),
                             only_groups = NULL, no_r2_groups = character(0),
                             title_override = list(), note_override = list(),
                             note_present_override = list(),
                             dict_override = list(),
                             header_rule_for = character(0)) {
  for (grp in chem_groups) {
    if (!is.null(only_groups) && !(grp$file_label %in% only_groups)) next
    cat("\n--- Group:", grp$group_label, file_sfx, "---\n")

    if (length(grp$chems) == 0) {
      cat("  No chemicals defined — skipping.\n")
      next
    }

    outcomes_mode <- if (!is.null(grp$outcomes)) grp$outcomes else "both"
    grp_dict      <- if (grp$file_label %in% names(dict_override)) dict_override[[grp$file_label]]
                      else if (!is.null(grp$dict))                 grp$dict
                      else                                         dict_global
    # TC group uses note_tc; all others use note
    grp_note      <- if (grp$file_label %in% names(note_override)) note_override[[grp$file_label]]
                      else if (isTRUE(grp$is_tc))                  note_tc
                      else                                         note
    grp_chems     <- setdiff(grp$chems, exclude_chems)

    models_list   <- list()
    hdr_vec       <- character(0)
    val_chems_ok  <- character(0)  # chems that produced a mean-conc. model (for detect block)

    for (chem in grp_chems) {
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
          models_list  <- c(models_list, list(m_val))
          hdr_vec      <- c(hdr_vec, nm)
          val_chems_ok <- c(val_chems_ok, chem)
          cat("  n_val =", m_val$nobs,
              "| coef_val =", round(coef(m_val)["coal_prod_upstream_cumsum_10mst"], 4), "\n")
        }
      }

      if (outcomes_mode %in% c("both", "shr_only")) {
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
            hdr_vec     <- c(hdr_vec, nm)
            cat("  n_shr =", m_shr$nobs,
                "| coef_shr =", round(coef(m_shr)["coal_prod_upstream_cumsum_10mst"], 4), "\n")
          }
        }
      }
    }

    # ---- Detection-share block -----------------------------------------------
    # For requested groups, append a trailing block of detect_share models, one
    # per contaminant that produced a mean-conc. model. Appending after all the
    # mean-conc. models keeps the depvar header a single "Share of samples
    # detected" span mirroring the "Mean conc." span, rather than interleaving.
    if (grp$file_label %in% detect_for) {
      for (chem in val_chems_ok) {
        d <- df[df$CHEMID_name == chem, ]
        dsh_var <- var(d$detect_share, na.rm = TRUE)
        if (is.na(dsh_var) || dsh_var == 0) {
          cat("  detect_share constant for", chem, "— skipping detection-share model.\n")
          next
        }
        m_dsh <- tryCatch(
          feols(fml_dsh, data = d, cluster = ~PWSID),
          error = function(e) { cat("  ERROR (detect_share):", conditionMessage(e), "\n"); NULL }
        )
        if (!is.null(m_dsh)) {
          models_list <- c(models_list, list(m_dsh))
          hdr_vec     <- c(hdr_vec, nice_chem(chem))
          cat("  n_dsh =", m_dsh$nobs,
              "| coef_dsh =", round(coef(m_dsh)["coal_prod_upstream_cumsum_10mst"], 4), "\n")
        }
      }
      grp_note <- paste0(
        grp_note,
        " The ``Share of samples detected'' columns report the share of a ",
        "CWS-year's samples that were detections (above the reporting/detection ",
        "limit)."
      )
    }

    if (length(models_list) == 0) {
      cat("  No models estimated — skipping table output.\n")
      next
    }

    out <- file.path(OUTPUT_DIR,
                     paste0("6yr_huc02fe_", grp$file_label, file_sfx, ".tex"))

    grp_fitstat <- if (grp$file_label %in% no_r2_groups) ~ n else ~ . + n + r2

    grp_postprocess <- if (grp$file_label %in% header_rule_for) {
      function(x) move_notes_below_adjustbox(add_cmidrule_under_superheader(x))
    } else {
      move_notes_below_adjustbox
    }

    grp_title <- if (grp$file_label %in% names(title_override)) {
      title_override[[grp$file_label]]
    } else {
      paste0("Effect of cumulative upstream coal production on ",
             grp$group_label, " (6-Year Review, downstream CWSs",
             title_sfx, ")")
    }

    etable(
      models_list,
      headers         = hdr_vec,
      fitstat         = grp_fitstat,
      style.tex       = style.tex("aer", adjustbox = TRUE),
      tex             = TRUE,
      drop            = "^num_facilities$",
      title           = grp_title,
      label           = paste0("tab:6yr_huc02fe_", grp$file_label, file_sfx),
      dict            = grp_dict,
      notes           = grp_note,
      postprocess.tex = grp_postprocess,
      file            = out
    )
    cat("  Written:", out, "\n")

    # Presentation companion: same table, notes stripped to FE + clustering +
    # stars only, only for groups explicitly requested via
    # note_present_override (see
    # .claude/logs/2026-08-31-presentation-notes-tables.md).
    if (grp$file_label %in% names(note_present_override)) {
      out_present <- sub("\\.tex$", "_present.tex", out)
      etable(
        models_list,
        headers         = hdr_vec,
        fitstat         = grp_fitstat,
        style.tex       = style.tex("aer", adjustbox = TRUE),
        tex             = TRUE,
        drop            = "^num_facilities$",
        title           = grp_title,
        label           = paste0("tab:6yr_huc02fe_", grp$file_label, file_sfx),
        dict            = grp_dict,
        notes           = note_present_override[[grp$file_label]],
        postprocess.tex = grp_postprocess,
        file            = out_present
      )
      cat("  Presentation table written:", out_present, "\n")
    }
  }
}

# ---------------------------------------------------------------------------
# Notes and dict for count (num_measurements) tables
# ---------------------------------------------------------------------------
note_cnt_base_std <- paste0(
  "Outcome is the number of annual measurements of the analyte recorded ",
  "for each CWS in the EPA 6-Year Review. ",
  "Non-detect values are not imputed. ",
  "Explanatory variable is cumulative coal production since 1985 ",
  "(in 10 million short tons) in the HUC12 one step upstream of the CWS intake. ",
  "Fixed effects: PWSID and HUC02$\\times$year (first two digits of intake HUC12 ",
  "interacted with year). ",
  "Sample: CWSs at most one HUC12 downstream of a coal mine ",
  "(minehuc\\_downstream\\_of\\_mine = 1, minehuc\\_mine = 0). ",
  "Standard errors clustered at PWSID level."
)

note_cnt_base_rav <- paste0(
  "Outcome is the number of annual measurements of the analyte recorded ",
  "for each CWS in the EPA 6-Year Review. ",
  "Non-detect values replaced by MDL$/\\sqrt{2}$ following Ravalli et al.~(2022). ",
  "Explanatory variable is cumulative coal production since 1985 ",
  "(in 10 million short tons) in the HUC12 one step upstream of the CWS intake. ",
  "Fixed effects: PWSID and HUC02$\\times$year (first two digits of intake HUC12 ",
  "interacted with year). ",
  "Sample: CWSs at most one HUC12 downstream of a coal mine ",
  "(minehuc\\_downstream\\_of\\_mine = 1, minehuc\\_mine = 0). ",
  "Standard errors clustered at PWSID level."
)

note_cnt_main_std <- paste0("Sample period 1998--2011. ", note_cnt_base_std)
note_cnt_2005_std <- paste0("Sample period 1998--2005 (robustness). ", note_cnt_base_std)
note_cnt_main_rav <- paste0("Sample period 1998--2011. ", note_cnt_base_rav)
note_cnt_2005_rav <- paste0("Sample period 1998--2005 (robustness). ", note_cnt_base_rav)

note_tc_cnt_main_std <- paste0(
  "Sample period 2006--2008 (EPA Six-Year Review 3; TCR data not included in SYR2). ",
  note_cnt_base_std,
  " Number of presence/absence coliform tests conducted under the Total Coliform Rule ",
  "(40 CFR 141.63; 54 FR 27544, Jun 29 1989)."
)
note_tc_cnt_main_rav <- paste0(
  "Sample period 2006--2008 (EPA Six-Year Review 3; TCR data not included in SYR2). ",
  note_cnt_base_rav,
  " Number of presence/absence coliform tests conducted under the Total Coliform Rule ",
  "(40 CFR 141.63; 54 FR 27544, Jun 29 1989). ",
  "MDL imputation not applied to total coliform (binary encoding)."
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
# run_count_tables(): num_measurements, mean VALUE, and max VALUE as outcomes.
# ---------------------------------------------------------------------------
run_count_tables <- function(df, note, file_sfx, title_sfx, note_tc_cnt = note_tc_cnt_main_std) {
  for (grp in chem_groups) {
    cat("\n--- Count | Group:", grp$group_label, file_sfx, "---\n")

    if (length(grp$chems) == 0) {
      cat("  No chemicals defined — skipping.\n")
      next
    }

    grp_note <- if (isTRUE(grp$is_tc)) note_tc_cnt else note

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
                               "measurements and concentration --- ", grp$group_label,
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
# run_inorg_val_table(): mean concentration for inorganic chemicals (no R^2).
#   df6_arg   — prepared dataset
#   file_sfx  — appended to output file name (e.g. "" or "_ravalli")
#   title_sfx — appended to table title
#   note_val  — footnote for the regression table
# ---------------------------------------------------------------------------
run_inorg_val_table <- function(df6_arg, file_sfx, title_sfx, note_val,
                               note_ss_period = "Sample period 1998--2011. ",
                               entity_label = "CWS",
                               add_panel_b_above_median = FALSE,
                               sumstats_exclude_chems = character(0),
                               include_sample_sentence = TRUE,
                               also_present = FALSE) {
  cat("\n=== INORGANIC CHEMICALS --- MEAN CONCENTRATION", file_sfx, "===\n")

  grp_inorg <- chem_groups[[1]]  # inorganic chemicals
  # Thallium excluded: 86% of values cluster at two detection-limit values,
  # making mean concentration unreliable.
  inorg_val_chems <- setdiff(grp_inorg$chems, "thallium")

  models_val <- list()
  hdr_val    <- character(0)

  for (chem in inorg_val_chems) {
    d <- df6_arg[df6_arg$CHEMID_name == chem, ]
    cat("  Chemical:", chem, "| n rows:", nrow(d), "\n")
    if (nrow(d) < 30) { cat("  Skipping --- too few obs.\n"); next }

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

  out_val <- file.path(OUTPUT_DIR, paste0("6yr_huc02fe_inorg_val", file_sfx, ".tex"))
  etable(
    models_val,
    headers         = hdr_val,
    fitstat         = ~ n,
    style.tex       = style.tex("aer", adjustbox = TRUE),
    tex             = TRUE,
    drop            = "Num\\.",
    title           = paste0("Effect of cumulative upstream coal production on ",
                             "mean measured concentration ",
                             "(6-Year Review, downstream CWSs", title_sfx, ")"),
    label           = paste0("tab:6yr_huc02fe_inorg_val", file_sfx),
    dict            = dict_global,
    notes           = note_val,
    postprocess.tex = move_notes_below_adjustbox,
    file            = out_val
  )
  cat("  Written:", out_val, "\n")

  # ---- Summary statistics ----
  cat("\n--- Summary statistics for inorg_val", file_sfx, "---\n")

  mcl_labels <- c(
    "arsenic"  = "Pre-2006: 0.050 mg/L, 2006+: 0.010 mg/L",
    "nitrate"  = "10.0 mg/L",
    "barium"   = "2.000 mg/L",
    "cadmium"  = "0.005 mg/L",
    "chromium" = "0.100 mg/L",
    "mercury"  = "0.002 mg/L",
    "selenium" = "0.050 mg/L"
  )

  # Numeric MCL values (mg/L), matching _MCL_RECORDS in cws_6year_review.py.
  # Arsenic is time-varying: 0.050 through 2005, 0.010 from 2006 onward.
  mcl_values <- c(
    "nitrate"  = 10.000,
    "barium"   = 2.000,
    "cadmium"  = 0.005,
    "chromium" = 0.100,
    "mercury"  = 0.002,
    "selenium" = 0.050
  )
  mcl_value_for <- function(chem, year) {
    if (chem == "arsenic") return(ifelse(year <= 2005, 0.050, 0.010))
    rep(unname(mcl_values[[chem]]), length(year))
  }

  # build_sumstats(): compute the summary-statistics data frame (one row per
  # inorganic chemical plus a trailing coal-production row) for a given copy
  # of the prepared dataset. Reused for Panel A (full sample) and, when
  # requested, Panel B (above-median cumulative coal production subsample).
  build_sumstats <- function(df_subset) {
    sum_rows  <- list()
    coal_list <- list()
    chems_ss  <- setdiff(inorg_val_chems, sumstats_exclude_chems)

    for (chem in chems_ss) {
      d_s <- df_subset[df_subset$CHEMID_name == chem, ]
      if (nrow(d_s) == 0) next

      keep_s <- complete.cases(d_s[, c("VALUE", "VALUE_max", "coal_prod_upstream_cumsum_10mst",
                                        "num_facilities", "huc02", "year", "PWSID")])
      d_reg_s <- d_s[keep_s, ]
      if (nrow(d_reg_s) == 0) next
      cat("  ", chem, ": n_complete =", nrow(d_reg_s), "\n")

      near_mcl_share <- if (chem %in% names(mcl_values) || chem == "arsenic") {
        half_mcl <- 0.5 * mcl_value_for(chem, d_reg_s$year)
        mean(d_reg_s$VALUE > half_mcl, na.rm = TRUE)
      } else {
        NA_real_
      }

      sum_rows[[chem]] <- data.frame(
        variable  = paste0(nice_chem(chem), " (mg/L)"),
        mcl_label = ifelse(chem %in% names(mcl_labels), mcl_labels[[chem]], "---"),
        mean_val  = mean(d_reg_s$VALUE,     na.rm = TRUE),
        max_val   = max(d_reg_s$VALUE_max,  na.rm = TRUE),
        sd_val    = sd(d_reg_s$VALUE,       na.rm = TRUE),
        n_obs     = nrow(d_reg_s),
        near_mcl  = near_mcl_share,
        stringsAsFactors = FALSE
      )
      coal_list[[chem]] <- d_reg_s[, c("PWSID", "year", "coal_prod_upstream_cumsum_10mst")]
    }

    if (length(coal_list) == 0) return(list(sum_df = NULL, coal_df = NULL))

    coal_df <- unique(do.call(rbind, coal_list))
    coal_df <- coal_df[!duplicated(coal_df[, c("PWSID", "year")]), ]
    sum_rows[["coal"]] <- data.frame(
      variable  = "Cumul. upstream coal prod. (10M ST)",
      mcl_label = "---",
      mean_val  = mean(coal_df$coal_prod_upstream_cumsum_10mst, na.rm = TRUE),
      max_val   = max(coal_df$coal_prod_upstream_cumsum_10mst,  na.rm = TRUE),
      sd_val    = sd(coal_df$coal_prod_upstream_cumsum_10mst,   na.rm = TRUE),
      n_obs     = sum(!is.na(coal_df$coal_prod_upstream_cumsum_10mst)),
      near_mcl  = NA_real_,
      stringsAsFactors = FALSE
    )

    list(sum_df = do.call(rbind, sum_rows), coal_df = coal_df)
  }

  panel_a   <- build_sumstats(df6_arg)
  sum_df_a  <- panel_a$sum_df

  panel_b_df <- NULL
  if (add_panel_b_above_median) {
    median_cum_prod <- median(panel_a$coal_df$coal_prod_upstream_cumsum_10mst, na.rm = TRUE)
    cat("  Median cumulative upstream coal production (10M ST):", median_cum_prod, "\n")
    df6_above  <- df6_arg[df6_arg$coal_prod_upstream_cumsum_10mst > median_cum_prod, ]
    panel_b    <- build_sumstats(df6_above)
    panel_b_df <- panel_b$sum_df
  }

  fmt_num <- function(x) {
    if (is.na(x)) return("---")
    sprintf("%.4f", x)
  }
  fmt_n <- function(x) formatC(x, format = "d", big.mark = ",")
  fmt_pct <- function(x) if (is.na(x)) "---" else sprintf("%.1f\\%%", 100 * x)

  note_ss_parts <- c(
    paste0("\\textit{Notes:} ", trimws(note_ss_period, which = "right")),
    paste0("Cumulative upstream coal production (10M ST) is cumulative coal production ",
           "since 1985, in units of 10 million short tons, in the watershed immediately ",
           "upstream of the ", entity_label, "'s intake."),
    paste0("For cumulative upstream coal production, statistics are computed over unique ",
           entity_label, "$\\times$year pairs that appear in at least one regression sample."),
    paste0("``Near MCL'' is the share of ", entity_label,
           "-year mean concentrations exceeding 50\\% of the applicable MCL.")
  )
  if (include_sample_sentence) {
    note_ss_parts <- c(note_ss_parts,
      "Sample: community water systems strictly downstream of a coal mine.")
  }
  if (add_panel_b_above_median) {
    note_ss_parts <- c(note_ss_parts,
      paste0("Panel B restricts Panel A's sample to ", entity_label,
             "-year observations with cumulative upstream coal production above the ",
             "sample median of ", fmt_num(median_cum_prod), " (10M ST)."))
  }
  note_ss <- paste(note_ss_parts, collapse = " ")

  tab_label <- paste0("tab:6yr_huc02fe_inorg_val_sumstats", file_sfx)

  # Fixed-width columns (rather than auto-fit l/r) so that, when Panel B is
  # rendered as a second, independent tabular, its columns line up exactly
  # with Panel A's despite each tabular sizing itself independently — the
  # same reasoning used for the label column in enforcement_visit_type_panels.r.
  col_spec <- paste0(
    ">{\\raggedright\\arraybackslash}p{4.4cm}",
    ">{\\raggedright\\arraybackslash}p{3.6cm}",
    ">{\\raggedleft\\arraybackslash}p{1.3cm}",
    ">{\\raggedleft\\arraybackslash}p{1.3cm}",
    ">{\\raggedleft\\arraybackslash}p{1.3cm}",
    ">{\\raggedleft\\arraybackslash}p{1.15cm}",
    ">{\\raggedleft\\arraybackslash}p{1.3cm}"
  )
  header_row <- "Variable & MCL & Mean & Max & Std.\\ Dev. & $N$ & Near MCL \\\\"

  make_ss_row <- function(r) {
    paste0(
      "         ", r$variable, " & ",
      r$mcl_label, " & ",
      fmt_num(r$mean_val), " & ",
      fmt_num(r$max_val), " & ",
      fmt_num(r$sd_val), " & ",
      fmt_n(r$n_obs), " & ",
      fmt_pct(r$near_mcl), " \\\\"
    )
  }

  # When Panel B is present, the panel-title row is not followed by its own
  # rule (no line directly below "Panel A/B: ..."), and only a single rule
  # (Panel A's \bottomrule) separates the two panels — Panel B's tabular has
  # no \toprule of its own, avoiding a doubled rule where Panel A's closing
  # line and Panel B's opening line would otherwise sit right on top of
  # each other.
  # The very top and bottom rules of the whole (possibly two-panel) table use
  # a doubled \hline\hline. When Panel B is present, Panel A's closing rule
  # is instead the single rule separating the two panels (see comment above),
  # and the doubled bottom rule moves to the end of Panel B's tabular.
  top_rule    <- if (add_panel_b_above_median) "         \\hline\\hline" else "         \\toprule"
  bottom_rule <- if (add_panel_b_above_median) "         \\hline\\hline" else "         \\bottomrule"

  panel_a_lines <- c(
    "   \\begin{adjustbox}{width = 0.9\\textwidth, center}",
    paste0("      \\begin{tabular}{", col_spec, "}"),
    top_rule,
    paste0("         ", header_row),
    "         \\midrule"
  )
  if (add_panel_b_above_median) {
    panel_a_lines <- c(panel_a_lines,
      "         \\multicolumn{7}{l}{\\textbf{Panel A: Full sample}} \\\\")
  }
  panel_a_lines <- c(panel_a_lines,
    vapply(seq_len(nrow(sum_df_a)), function(i) make_ss_row(sum_df_a[i, ]), character(1)),
    if (add_panel_b_above_median) "         \\bottomrule" else bottom_rule,
    "      \\end{tabular}",
    "   \\end{adjustbox}"
  )

  panel_b_lines <- character(0)
  if (add_panel_b_above_median) {
    panel_b_lines <- c(
      "   \\bigskip",
      "   \\begin{adjustbox}{width = 0.9\\textwidth, center}",
      paste0("      \\begin{tabular}{", col_spec, "}"),
      "         \\multicolumn{7}{l}{\\textbf{Panel B: Utility exposed to above median cumulative tons of coal extraction}} \\\\",
      vapply(seq_len(nrow(panel_b_df)), function(i) make_ss_row(panel_b_df[i, ]), character(1)),
      bottom_rule,
      "      \\end{tabular}",
      "   \\end{adjustbox}"
    )
  }

  tex_ss <- c(
    "",
    "\\begin{table}[htbp]",
    paste0("   \\caption{\\label{", tab_label, "} ",
           "Summary statistics: mean concentration for inorganic chemicals and cumulative upstream coal production}"),
    "   \\bigskip",
    "   \\centering",
    panel_a_lines,
    panel_b_lines,
    "   \\begin{minipage}{\\linewidth}",
    "   \\vspace{4pt}",
    paste0("   {\\tiny\\linespread{1}\\selectfont\\raggedright ", note_ss, "}"),
    "   \\end{minipage}",
    "\\end{table}",
    ""
  )

  out_ss <- file.path(PROJECT_ROOT, "output", "sum",
                      paste0("6yr_huc02fe_inorg_val_sumstats", file_sfx, ".tex"))
  writeLines(tex_ss, out_ss)
  cat("  Written:", out_ss, "\n")

  # Presentation companion: same table body, notes block omitted entirely
  # (summary statistics carry no clustering/FE/stars) -- see
  # .claude/logs/2026-08-31-presentation-notes-tables.md.
  if (also_present) {
    tex_ss_present <- c(
      "",
      "\\begin{table}[htbp]",
      paste0("   \\caption{\\label{", tab_label, "} ",
             "Summary statistics: mean concentration for inorganic chemicals and cumulative upstream coal production}"),
      "   \\bigskip",
      "   \\centering",
      panel_a_lines,
      panel_b_lines,
      "\\end{table}",
      ""
    )
    out_ss_present <- sub("\\.tex$", "_present.tex", out_ss)
    writeLines(tex_ss_present, out_ss_present)
    cat("  Presentation table written:", out_ss_present, "\n")
  }
}

# ---------------------------------------------------------------------------
# Note text for inorg_val tables
# ---------------------------------------------------------------------------
note_inorg_val_std <- paste0(
  "Sample period 1998--2011. ",
  "Outcome is the mean measured concentration of the analyte in a given CWS-year ",
  "from the EPA 6-Year Review. ",
  "Non-detect values are not imputed (SYR2 non-detects recorded as MRL; ",
  "SYR3 non-detects missing). ",
  "For arsenic, the MCL is 0.050 mg/L through 2005 and 0.010 mg/L from 2006 onward. ",
  "Explanatory variable is cumulative coal production since 1985 ",
  "(in 10 million short tons) in the HUC12 one step upstream of the CWS intake. ",
  "Fixed effects: PWSID and HUC02$\\times$year (first two digits of intake HUC12 ",
  "interacted with year). ",
  "Sample: CWSs at most one HUC12 downstream of a coal mine ",
  "(minehuc\\_downstream\\_of\\_mine = 1, minehuc\\_mine = 0). ",
  "Standard errors clustered at PWSID level."
)

note_inorg_val_rav <- paste0(
  "Sample period 1998--2011. ",
  "Outcome is the mean measured concentration of the analyte in a given CWS-year ",
  "from the EPA 6-Year Review (Ravalli et al.~2022 cleaning: non-detects replaced ",
  "by MDL$/\\sqrt{2}$). ",
  "For arsenic, the MCL is 0.050 mg/L through 2005 and 0.010 mg/L from 2006 onward. ",
  "Explanatory variable is cumulative coal production since 1985 ",
  "(in 10 million short tons) in the HUC12 one step upstream of the CWS intake. ",
  "Fixed effects: PWSID and HUC02$\\times$year (first two digits of intake HUC12 ",
  "interacted with year). ",
  "Sample: CWSs at most one HUC12 downstream of a coal mine ",
  "(minehuc\\_downstream\\_of\\_mine = 1, minehuc\\_mine = 0). ",
  "Standard errors clustered at PWSID level."
)

note_inorg_val_rav_2005 <- paste0(
  "Sample period 1998--2005 (robustness). ",
  "Outcome is the mean measured concentration of the analyte in a given CWS-year ",
  "from the EPA 6-Year Review (Ravalli et al.~2022 cleaning: non-detects replaced ",
  "by MDL$/\\sqrt{2}$). ",
  "For arsenic, the MCL is 0.050 mg/L through 2005. ",
  "Explanatory variable is cumulative coal production since 1985 ",
  "(in 10 million short tons) in the HUC12 one step upstream of the CWS intake. ",
  "Fixed effects: PWSID and HUC02$\\times$year (first two digits of intake HUC12 ",
  "interacted with year). ",
  "Sample: CWSs at most one HUC12 downstream of a coal mine ",
  "(minehuc\\_downstream\\_of\\_mine = 1, minehuc\\_mine = 0). ",
  "Standard errors clustered at PWSID level."
)

# ===========================================================================
# STANDARD PIPELINE TABLES
# ===========================================================================

cat("\n\n### STANDARD PIPELINE ###\n")

cat("\n=== MAIN SAMPLE: 1998-2011 ===\n")
run_group_tables(df6, note_main_std, file_sfx = "", title_sfx = "",
                 note_tc = note_tc_main_std)

cat("\n=== ROBUSTNESS: 1998-2005 ===\n")
df6_2005 <- df6[df6$year <= 2005, ]
cat("Rows (1998-2005):", nrow(df6_2005),
    "| year range:", min(df6_2005$year), "-", max(df6_2005$year), "\n")
run_group_tables(df6_2005, note_2005_std, file_sfx = "_2005",
                 title_sfx = ", robustness 1998--2005",
                 note_tc = note_tc_main_std)

cat("\n=== COUNT TABLES: MAIN SAMPLE 1998-2011 ===\n")
run_count_tables(df6, note_cnt_main_std, file_sfx = "", title_sfx = "",
                 note_tc_cnt = note_tc_cnt_main_std)

cat("\n=== COUNT TABLES: ROBUSTNESS 1998-2005 ===\n")
run_count_tables(df6_2005, note_cnt_2005_std, file_sfx = "_2005",
                 title_sfx = ", robustness 1998--2005",
                 note_tc_cnt = note_tc_cnt_main_std)

run_inorg_val_table(df6, file_sfx = "", title_sfx = "",
                    note_val = note_inorg_val_std)

# ===========================================================================
# RAVALLI ET AL. (2022) PIPELINE TABLES
# ===========================================================================

cat("\n\n### RAVALLI ET AL. (2022) PIPELINE (MDL/sqrt(2) imputation) ###\n")

cat("\n=== MAIN SAMPLE: 1998-2011 ===\n")
run_group_tables(df6r, note_main_rav, file_sfx = "_ravalli",
                 title_sfx = ", Ravalli et al.~(2022) cleaning",
                 note_tc = note_tc_main_rav)

cat("\n=== ROBUSTNESS: 1998-2005 ===\n")
df6r_2005 <- df6r[df6r$year <= 2005, ]
cat("Rows (1998-2005):", nrow(df6r_2005),
    "| year range:", min(df6r_2005$year), "-", max(df6r_2005$year), "\n")
run_group_tables(df6r_2005, note_2005_rav, file_sfx = "_ravalli_2005",
                 title_sfx = ", Ravalli et al.~(2022) cleaning, robustness 1998--2005",
                 note_tc = note_tc_main_rav, exclude_chems = "chromium",
                 no_r2_groups = "inorg",
                 title_override = list(
                   inorg = "Effect of cumulative upstream coal production on Inorganic Chemicals, SYR2 1998--2005"
                 ),
                 note_override = list(
                   inorg = "\\textit{Notes:} Standard errors clustered at the utility level. *** p$<$0.01, ** p$<$0.05, * p$<$0.1."
                 ),
                 # Presentation companion: the main note above already contains
                 # only clustering + stars (FE shown via checkmark rows), so
                 # reuse it verbatim -- see
                 # .claude/logs/2026-08-31-presentation-notes-tables.md.
                 note_present_override = list(
                   inorg = "\\textit{Notes:} Standard errors clustered at the utility level. *** p$<$0.01, ** p$<$0.05, * p$<$0.1."
                 ),
                 dict_override = list(
                   inorg = { d <- dict_global; d["PWSID"] <- "Utility"; d }
                 ),
                 header_rule_for = "inorg")

# ---------------------------------------------------------------------------
# Surface-water subsample: re-estimate the inorganic-chemicals 1998-2005
# robustness table on CWSs whose primary water source is surface water, to
# test whether the main results are driven by surface-water or groundwater
# systems.
# ---------------------------------------------------------------------------
note_base_rav_sw <- paste0(
  "Within each chemical, columns show mean measured concentration ",
  "from the EPA 6-Year Review. ",
  "Non-detect values replaced by MDL$/\\sqrt{2}$ following Ravalli et al.~(2022). ",
  "Explanatory variable is cumulative coal production since 1985 ",
  "(in 10 million short tons) one watershed upstream of the CWS intake. ",
  "Sample: community water systems strictly downstream of a coal mine. ",
  "Sample further restricted to community water systems whose primary water source is surface water. ",
  "Standard errors clustered at the CWS level. ",
  "*** p$<$0.01, ** p$<$0.05, * p$<$0.1."
)
note_2005_rav_sw <- paste0("\\textit{Notes:} Sample period 1998--2005. ", note_base_rav_sw)

cat("\n=== ROBUSTNESS: 1998-2005, SURFACE WATER SYSTEMS ===\n")
stopifnot("PRIMARY_SOURCE_CODE" %in% names(df6r_2005))
df6r_2005_sw <- df6r_2005[df6r_2005$PRIMARY_SOURCE_CODE %in% c("SW", "SWP"), ]
cat("Rows (1998-2005, surface water):", nrow(df6r_2005_sw),
    "| CWSs:", length(unique(df6r_2005_sw$PWSID)), "\n")
run_group_tables(df6r_2005_sw, note_2005_rav_sw,
                 file_sfx  = "_ravalli_2005_surfacewater",
                 title_sfx = ", Ravalli et al.~(2022) cleaning, robustness 1998--2005, surface water systems",
                 note_tc = note_tc_main_rav, exclude_chems = "chromium",
                 only_groups = "inorg")

cat("\n=== COUNT TABLES: MAIN SAMPLE 1998-2011 ===\n")
run_count_tables(df6r, note_cnt_main_rav, file_sfx = "_ravalli",
                 title_sfx = ", Ravalli et al.~(2022) cleaning",
                 note_tc_cnt = note_tc_cnt_main_rav)

cat("\n=== COUNT TABLES: ROBUSTNESS 1998-2005 ===\n")
run_count_tables(df6r_2005, note_cnt_2005_rav, file_sfx = "_ravalli_2005",
                 title_sfx = ", Ravalli et al.~(2022) cleaning, robustness 1998--2005",
                 note_tc_cnt = note_tc_cnt_main_rav)

run_inorg_val_table(df6r, file_sfx = "_ravalli",
                    title_sfx = ", Ravalli et al.~(2022) cleaning",
                    note_val = note_inorg_val_rav)

run_inorg_val_table(df6r_2005, file_sfx = "_ravalli_2005",
                    title_sfx = ", Ravalli et al.~(2022) cleaning, robustness 1998--2005",
                    note_val = note_inorg_val_rav_2005,
                    note_ss_period = "SYR2 sample from 1998--2005. ",
                    entity_label = "utility",
                    add_panel_b_above_median = TRUE,
                    sumstats_exclude_chems = "chromium",
                    include_sample_sentence = FALSE,
                    also_present = TRUE)

# ---------------------------------------------------------------------------
# Scatter plot: beta particle mean concentration vs cumulative upstream coal
# production. Uses the standard dataset. One dot per PWSID-year observation.
# ---------------------------------------------------------------------------
cat("\n=== SCATTER: beta particles vs cumulative upstream coal production ===\n")
suppressPackageStartupMessages(library(ggplot2))

beta_df <- df6[df6$CHEMID_name == "beta particles", ]
cat("Beta particles observations:", nrow(beta_df), "\n")
cat("Unique PWSIDs:", length(unique(beta_df$PWSID)), "\n")

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
