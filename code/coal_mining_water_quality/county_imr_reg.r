# ============================================================
# Script: county_imr_reg.r
# Purpose: 2SLS regressions of county infant mortality rate
#          on coal mine count, using post95 x county sulfur
#          as instrument. Mirrors the 2SLS spec in didhet.r.
# Inputs:  clean_data/county_imr_mining.parquet
# Outputs: output/reg/county_imr_dwnstrm.tex
#          output/reg/county_imr_dwnstrmcolocate.tex
# Author: EK  Date: 2026-04-09
# ============================================================

library(arrow)
library(fixest)

# ── Load data ─────────────────────────────────────────────────────────────────
df <- read_parquet("Z:/ek559/mining_wq/clean_data/county_imr_mining.parquet")
df$post95 <- as.integer(df$year >= 1995)

# ── Post-processor: move notes outside the adjustbox ─────────────────────────
# Copied from didhet.r. etable places notes inside \begin{adjustbox}...\end{adjustbox},
# which renders them squished. This moves them below for full-width display.
move_notes_below_adjustbox <- function(x) {
  x <- paste(x, collapse = "\n")
  end_adj <- "\\end{adjustbox}"
  par_rag <- "\\par \\raggedright"
  par_pos     <- regexpr(par_rag, x, fixed = TRUE)
  end_adj_pos <- regexpr(end_adj, x, fixed = TRUE)
  if (par_pos[1] == -1 || end_adj_pos[1] == -1) return(x)
  note_block <- substr(x, par_pos[1], end_adj_pos[1] - 1)
  x <- sub(note_block, "", x, fixed = TRUE)
  x <- sub(end_adj,
           paste0(end_adj, "\n   {\\tiny\\linespread{1}\\selectfont ", trimws(note_block), "}"),
           x, fixed = TRUE)
  x
}

# ── Regression function ───────────────────────────────────────────────────────
# Runs OLS, reduced form, and 2SLS for IMR. Mirrors tsls_reg_output_main()
# from didhet.r but uses county FE and no controls.
#
# dset        - data frame (already filtered to the desired subsample)
# coalvar     - name of the endogenous treatment variable (character)
# instr_str   - instrument string, e.g. "post95*sulfur_unified"
# regoutname  - output file stem (no path, no extension)
# title       - LaTeX table title
# label       - LaTeX table label
# notes       - character string for table notes (optional)

tsls_county_imr <- function(dset, coalvar, instr_str, regoutname,
                             title, label, notes = NULL) {

  fe_str  <- "fips5 + state + year"
  outcome <- "imr"

  f_ols <- as.formula(
    paste0(outcome, " ~ ", coalvar, " | ", fe_str)
  )
  f_rf <- as.formula(
    paste0(outcome, " ~ ", instr_str, " | ", fe_str)
  )
  f_iv <- as.formula(
    paste0(outcome, " ~ 1 | ", fe_str, " | ", coalvar, " ~ ", instr_str)
  )

  mods <- tryCatch({
    list(
      OLS = fixest::feols(f_ols, data = dset, cluster = ~ fips5),
      RF  = fixest::feols(f_rf,  data = dset, cluster = ~ fips5),
      IV  = fixest::feols(f_iv,  data = dset, cluster = ~ fips5)
    )
  }, error = function(e) {
    cat("  Error:", conditionMessage(e), "\n")
    NULL
  })

  if (is.null(mods)) return(invisible(NULL))

  model_list <- list(mods$OLS, mods$RF, mods$IV)

  dict_vec <- c(
    upstream_num_coal_mines            = "Upstream coal mines",
    num_coal_mines_unified             = "Coal mines (unified)",
    "post95:upstream_sulfur_county_pct" = "Post 1995 $\\times$ Upstream sulfur \\%",
    "post95:sulfur_unified"             = "Post 1995 $\\times$ Sulfur (unified)",
    imr                                = "Infant mortality rate"
  )

  etable_args <- c(
    model_list,
    list(
      fitstat         = ~ . + ivf1,
      style.tex       = style.tex("aer", adjustbox = TRUE),
      tex             = TRUE,
      title           = title,
      label           = label,
      dict            = dict_vec,
      postprocess.tex = move_notes_below_adjustbox,
      file            = paste0("Z:/ek559/mining_wq/output/reg/", regoutname, ".tex")
    )
  )
  if (!is.null(notes)) etable_args$notes <- notes

  do.call(etable, etable_args)
}

# ── Table note ────────────────────────────────────────────────────────────────
imr_note <- paste0(
  "Columns show OLS, reduced form, and 2SLS estimates. ",
  "Dependent variable is infant mortality rate (deaths per live birth). ",
  "Instrument is post95 interacted with mean coal sulfur content of the county ",
  "(post95 $\\times$ sulfur unified). ",
  "All regressions include county, year, and state fixed effects. ",
  "Standard errors clustered at county level. ",
  "Sample period 1985--2005."
)

# ── Sample 1: downstream counties only ───────────────────────────────────────
# Analogous to "dwnstrm" in didhet.r.
# Treatment: upstream_num_coal_mines (mines in the neighboring mining county)
# Instrument: post95 x upstream_sulfur_county_pct
cat("Running downstream-only regression...\n")
dset_dwnstrm <- df[df$is_strictly_downstream == TRUE, ]
cat("  N county-years:", nrow(dset_dwnstrm),
    "  N with IMR:", sum(!is.na(dset_dwnstrm$imr)), "\n")

tsls_county_imr(
  dset       = dset_dwnstrm,
  coalvar    = "upstream_num_coal_mines",
  instr_str  = "post95*upstream_sulfur_county_pct",
  regoutname = "county_imr_dwnstrm",
  title      = "Effect of upstream coal mines on infant mortality (downstream counties)",
  label      = "tab:county_imr_dwnstrm",
  notes      = imr_note
)

# ── Sample 2: downstream + mining counties ────────────────────────────────────
# Analogous to "dwnstrmcolocate" in didhet.r.
# Treatment: num_coal_mines_unified (own for mining, upstream for downstream)
# Instrument: post95 x sulfur_unified
cat("Running downstream + mining regression...\n")
dset_both <- df[df$is_strictly_downstream == TRUE | df$is_mining_county == TRUE, ]
cat("  N county-years:", nrow(dset_both),
    "  N with IMR:", sum(!is.na(dset_both$imr)), "\n")

tsls_county_imr(
  dset       = dset_both,
  coalvar    = "num_coal_mines_unified",
  instr_str  = "post95*sulfur_unified",
  regoutname = "county_imr_dwnstrmcolocate",
  title      = "Effect of coal mines on infant mortality (downstream and mining counties)",
  label      = "tab:county_imr_dwnstrmcolocate",
  notes      = imr_note
)

cat("Done. Tables written to output/reg/.\n")
