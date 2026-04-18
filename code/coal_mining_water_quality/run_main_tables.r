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
                                  instr_str, dict = NULL, notes = NULL,
                                  storage_list_name = NULL, subheader = NULL) {
  controls            <- c("num_facilities")
  drop_controls_exact <- paste0("^(", paste(controls, collapse = "|"), ")$")
  fe_str              <- "PWSID + STATE_CODE + year"
  controls_str        <- paste(controls, collapse = " + ")
  result <- list()

  for (y in varlist) {
    # Subset to non-missing rows for this outcome so N reflects actual sample
    dset_y <- dset[!is.na(dset[[y]]), ]
    cat("  Outcome:", y, "| n =", nrow(dset_y), "\n")
    f_ols <- as.formula(paste0(y, " ~ ", paste(coalvar, collapse="+"), " + ", controls_str, " | ", fe_str))
    f_rf  <- as.formula(paste0(y, " ~ ", instr_str, " + ", controls_str, " | ", fe_str))
    f_iv  <- as.formula(paste0(y, " ~ ", controls_str, " | ", fe_str, " | ", paste(coalvar, collapse="+"), " ~ ", instr_str))
    ols <- tryCatch(fixest::feols(f_ols, data = dset_y, cluster = ~ PWSID),
                    error = function(e) { cat("  OLS error", y, "-", conditionMessage(e), "\n"); NULL })
    rf  <- tryCatch(fixest::feols(f_rf,  data = dset_y, cluster = ~ PWSID),
                    error = function(e) { cat("  RF error",  y, "-", conditionMessage(e), "\n"); NULL })
    iv  <- tryCatch(fixest::feols(f_iv,  data = dset_y, cluster = ~ PWSID),
                    error = function(e) { cat("  IV error",  y, "-", conditionMessage(e), "\n"); NULL })
    # Only include outcome if all three models succeeded
    if (!is.null(ols) && !is.null(rf) && !is.null(iv)) {
      result[[y]] <- list(OLS = ols, RF = rf, IV = iv)
    } else {
      cat("  Dropping", y, "- not all three models succeeded\n")
    }
  }

  if (length(result) == 0) {
    cat("  No estimable outcomes for", regoutname, "- skipping etable.\n")
    return(invisible(NULL))
  }

  # ── Persist first stages to global list ──────────────────────────────────
  if (!is.null(storage_list_name) && !is.null(subheader)) {
    if (!exists(storage_list_name, envir = .GlobalEnv)) {
      assign(storage_list_name, list(), envir = .GlobalEnv)
    }
    fs_list <- get(storage_list_name, envir = .GlobalEnv)
    if (is.null(fs_list[[subheader]])) {
      fs_list[[subheader]] <- list()
    }
    for (y in names(result)) {
      for (cv in coalvar) {
        fs_list[[subheader]][[y]][[cv]] <- result[[y]]$IV$iv_first_stage[[cv]]
      }
    }
    assign(storage_list_name, fs_list, envir = .GlobalEnv)
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

first_stage_table <- function(storage_list_name, outfile, title = NULL,
                               label = NULL, which_coalvar = NULL,
                               drop = NULL) {
  fs_list       <- get(storage_list_name, envir = .GlobalEnv)
  model_list    <- list()
  inner_headers <- list()
  outer_headers <- list()

  for (subheader in names(fs_list)) {
    depvar_bucket <- fs_list[[subheader]]
    n_cols        <- 0
    for (depvar in names(depvar_bucket)) {
      coal_models <- depvar_bucket[[depvar]]
      cv <- if (!is.null(which_coalvar)) which_coalvar else names(coal_models)[1]
      model_list              <- c(model_list, list(coal_models[[cv]]))
      inner_headers[[depvar]] <- 1L
      n_cols                  <- n_cols + 1L
    }
    outer_headers[[subheader]] <- n_cols
  }

  two_level_headers <- list(outer_headers, inner_headers)
  do.call(etable, c(
    model_list,
    list(
      fitstat   = ~ . + ivf1,
      style.tex = style.tex("aer", adjustbox = TRUE),
      tex       = TRUE,
      drop      = drop,
      headers   = two_level_headers,
      title     = title,
      label     = label,
      file      = paste0("Z:/ek559/mining_wq/output/reg/", outfile, ".tex")
    )
  ))
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
  list(sample="dwnstrm",        dset=full[(full$minehuc_downstream_of_mine==1)&(full$minehuc_mine==0),],            coalvar="num_coal_mines_upstream", instr="post95:sulfur_unified", titlesamp="downstream PWS's"),
  list(sample="dwnstrmcolocate",dset=full[full$minehuc_upstream_of_mine=="Colocated/Downstream of mining",], coalvar="num_coal_mines_unified",  instr="post95:sulfur_unified", titlesamp="downstream and colocated PWS's")
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
    fs_store_name <- paste0("fs_store_", sp$sample, "_", vp$name)
    for (cp in cat_specs) {
      fname     <- paste0("2sls_", sp$sample, "_", vp$name, "_", cp$name)
      tab_title <- paste0("Effect of coal mines on ", vp$titlevio, " (", cp$titlecat, ", ", sp$titlesamp, ")")
      varlist   <- vp[[cp$varkey]]
      cat("\nRunning:", fname, "\n")
      tsls_reg_output_main(dset=sp$dset, varlist=varlist, coalvar=sp$coalvar,
                           regoutname=fname, title=tab_title, label=fname,
                           instr_str=sp$instr, dict=vio_dict, notes=std_note,
                           storage_list_name = fs_store_name,
                           subheader         = cp$titlecat)
    }
    fs_outfile <- paste0("fs_", sp$sample, "_", vp$name)
    fs_title   <- paste0("First Stage: ", vp$titlevio, " (", sp$titlesamp, ")")
    cat("\nProducing first-stage table:", fs_outfile, "\n")
    first_stage_table(
      storage_list_name = fs_store_name,
      outfile           = fs_outfile,
      title             = fs_title,
      label             = paste0("tab:", fs_outfile),
      drop              = "num_facilities"
    )
  }
}
cat("\nDone.\n")
