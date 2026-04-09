.libPaths("Z:/ek559/RPackages")
library(fixest)
library(arrow)
library(dplyr)

full <- read_parquet("Z:/ek559/mining_wq/clean_data/cws_data/prod_vio_sulfur.parquet")
full <- full[full$year < 2006 & full$year > 1984, ]
full <- full[full$PWSID != "WV3303401", ]
full$minehuc_upstream_of_mine[full$minehuc_upstream_of_mine == 1] <- "Upstream of mining"
full$minehuc_upstream_of_mine[full$minehuc_upstream_of_mine == 0] <- "Colocated/Downstream of mining"
cat("Rows in full:", nrow(full), "\n")

vio_dict <- c(
  nitrates_share_days                      = "Nitrates",
  arsenic_share_days                       = "Arsenic",
  inorganic_chemicals_share_days           = "Inorganic chemicals",
  radionuclides_share_days                 = "Radionuclides",
  nitrates_MCL_share_days                  = "Nitrates (MCL)",
  arsenic_MCL_share_days                   = "Arsenic (MCL)",
  inorganic_chemicals_MCL_share_days       = "Inorganic chemicals (MCL)",
  radionuclides_MCL_share_days             = "Radionuclides (MCL)",
  nitrates_MR_share_days                   = "Nitrates (MR)",
  arsenic_MR_share_days                    = "Arsenic (MR)",
  inorganic_chemicals_MR_share_days        = "Inorganic chemicals (MR)",
  radionuclides_MR_share_days              = "Radionuclides (MR)",
  total_coliform_share_days                = "Total coliform",
  surface_ground_water_rule_share_days     = "S/G water rule",
  voc_share_days                           = "VOCs",
  soc_share_days                           = "SOCs",
  total_coliform_MCL_share_days            = "Total coliform (MCL)",
  surface_ground_water_rule_MCL_share_days = "S/G water rule (MCL)",
  voc_MCL_share_days                       = "VOCs (MCL)",
  soc_MCL_share_days                       = "SOCs (MCL)",
  total_coliform_MR_share_days             = "Total coliform (MR)",
  surface_ground_water_rule_MR_share_days  = "S/G water rule (MR)",
  voc_MR_share_days                        = "VOCs (MR)",
  soc_MR_share_days                        = "SOCs (MR)"
)

move_notes_below_adjustbox <- function(x) {
  x <- paste(x, collapse = "\n")
  end_adj <- "\\end{adjustbox}"
  par_rag <- "\\par \\raggedright"
  par_pos     <- regexpr(par_rag, x, fixed = TRUE)
  end_adj_pos <- regexpr(end_adj, x, fixed = TRUE)
  if (par_pos[1] == -1 || end_adj_pos[1] == -1) return(x)
  note_block <- substr(x, par_pos[1], end_adj_pos[1] - 1)
  x <- sub(note_block, "", x, fixed = TRUE)
  x <- sub(end_adj, paste0(end_adj, "\n   {\\tiny\\linespread{1}\\selectfont ", trimws(note_block), "}"), x, fixed = TRUE)
  x
}

tsls_reg_output_main <- function(dset, varlist, coalvar, regoutname, title, label,
                                  instr_str, dict = NULL, notes = NULL) {
  controls            <- c("num_facilities")
  drop_controls_exact <- paste0("^(", paste(controls, collapse = "|"), ")$")
  fe_str              <- "PWSID + STATE_CODE + year"
  controls_str        <- paste(controls, collapse = " + ")
  result <- list()

  for (y in varlist) {
    cat("  Outcome:", y, "| n =", nrow(dset), "\n")
    f_ols <- as.formula(paste0(y, " ~ ", paste(coalvar, collapse="+"), " + ", controls_str, " | ", fe_str))
    f_rf  <- as.formula(paste0(y, " ~ ", instr_str, " + ", controls_str, " | ", fe_str))
    f_iv  <- as.formula(paste0(y, " ~ ", controls_str, " | ", fe_str, " | ", paste(coalvar, collapse="+"), " ~ ", instr_str))
    mods <- tryCatch({
      list(
        OLS = fixest::feols(f_ols, data = dset, cluster = ~ PWSID),
        RF  = fixest::feols(f_rf,  data = dset, cluster = ~ PWSID),
        IV  = fixest::feols(f_iv,  data = dset, cluster = ~ PWSID)
      )
    }, error = function(e) {
      cat("  Skipping", y, "-", conditionMessage(e), "\n")
      NULL
    })
    if (!is.null(mods)) result[[y]] <- mods
  }

  if (length(result) == 0) {
    cat("  No estimable outcomes for", regoutname, "- skipping etable.\n")
    return(invisible(NULL))
  }

  model_list <- unlist(
    lapply(names(result), function(y) list(result[[y]]$OLS, result[[y]]$RF, result[[y]]$IV)),
    recursive = FALSE
  )
  etable_args <- c(
    model_list,
    list(
      fitstat         = ~ . + ivf1,
      style.tex       = style.tex("aer", adjustbox = TRUE),
      tex             = TRUE,
      drop            = drop_controls_exact,
      title           = title,
      label           = label,
      postprocess.tex = move_notes_below_adjustbox,
      file            = paste0("Z:/ek559/mining_wq/output/reg/", regoutname, ".tex")
    )
  )
  if (!is.null(dict))  etable_args$dict  <- dict
  if (!is.null(notes)) etable_args$notes <- notes
  do.call(etable, etable_args)
}

std_note <- paste0(
  "Columns show OLS, reduced form, and 2SLS estimates. ",
  "Dependent variable is days out of the year in violation. ",
  "Instrument is post95 interacted with mean coal sulfur content of the intake watershed ",
  "(post95 x sulfur unified). ",
  "All regressions include PWSID, year, and state fixed effects. ",
  "Standard errors clustered at PWSID level. ",
  "Sample period 1985--2005."
)

sample_specs <- list(
  list(sample="dwnstrm",        dset=full[(full$minehuc_downstream_of_mine==1)&(full$minehuc_mine==0),],            coalvar="num_coal_mines_upstream", instr="post95*sulfur_unified", titlesamp="downstream PWS's"),
  list(sample="dwnstrmcolocate",dset=full[full$minehuc_upstream_of_mine=="Colocated/Downstream of mining",], coalvar="num_coal_mines_unified",  instr="post95*sulfur_unified", titlesamp="downstream and colocated PWS's")
)
vio_specs <- list(
  list(name="minevio",    allcat=c("nitrates_share_days","arsenic_share_days","inorganic_chemicals_share_days","radionuclides_share_days"),             mcl=c("nitrates_MCL_share_days","arsenic_MCL_share_days","inorganic_chemicals_MCL_share_days","radionuclides_MCL_share_days"),             mr=c("nitrates_MR_share_days","arsenic_MR_share_days","inorganic_chemicals_MR_share_days","radionuclides_MR_share_days"),             titlevio="mining violations"),
  list(name="nonminevio", allcat=c("total_coliform_share_days","surface_ground_water_rule_share_days","voc_share_days","soc_share_days"),                mcl=c("total_coliform_MCL_share_days","surface_ground_water_rule_MCL_share_days","voc_MCL_share_days","soc_MCL_share_days"),                mr=c("total_coliform_MR_share_days","surface_ground_water_rule_MR_share_days","voc_MR_share_days","soc_MR_share_days"),                titlevio="non-mining violations")
)
cat_specs <- list(
  list(name="allcat", varkey="allcat", titlecat="any violation category"),
  list(name="mcl",    varkey="mcl",    titlecat="MCL violations only"),
  list(name="mr",     varkey="mr",     titlecat="MR violations only")
)

for (sp in sample_specs) {
  for (vp in vio_specs) {
    for (cp in cat_specs) {
      fname     <- paste0("2sls_", sp$sample, "_", vp$name, "_", cp$name)
      tab_title <- paste0("Effect of coal mines on ", vp$titlevio, " (", cp$titlecat, ", ", sp$titlesamp, ")")
      varlist   <- vp[[cp$varkey]]
      cat("\nRunning:", fname, "\n")
      tsls_reg_output_main(dset=sp$dset, varlist=varlist, coalvar=sp$coalvar,
                           regoutname=fname, title=tab_title, label=fname,
                           instr_str=sp$instr, dict=vio_dict, notes=std_note)
    }
  }
}
cat("\nDone.\n")
