.libPaths("Z:/ek559/RPackages")
# git change
install.packages('fixest')
install.packages('arrow')
install.packages('ggplot2')
install.packages('ISOweek')
install.packages("data.table")
install.packages("dplyr")
install.packages("modelsummary")
install.packages("grid")
install.packages('tinytable')
install.packages('patchwork')
install.packages('grid')
install.packages('estimatr')
install.packages("DIDmultiplegtDYN")
install.packages("ggfixest") 
install.packages("tidyr")
install.packages("magrittr")

library(tidyr)
library(ggfixest)   
library(DIDmultiplegtDYN)
library(patchwork)
library(grid)
library(tinytable)
library(grid)
library(dplyr)
library(fixest)
library(arrow)
library(ggplot2)
library(ISOweek)
library(tidyverse)
library(knitr)
library(kableExtra)
library(modelsummary)
library(lubridate)
library(magrittr)
#library(estimatr)

########################
# CWS data and analysis
########################
full <- read_parquet("Z:/ek559/mining_wq/clean_data/cws_data/prod_vio_sulfur.parquet")

### PRIOR TO 2006 and AFTER 1985
full <- full[full$year<2006 & full$year>1984,]
full <- full[full$PWSID!="WV3303401",]
full <- full[full$PWSID!="WV3303401",]

# Balance panel: keep only PWSIDs with all 21 observations (1985-2005)
# Balance panel
# 16 rows between 1985 and 2005
full <- full %>%
  group_by(PWSID) %>%
  mutate(total_pwsid_obs = n())
full <- full[full$total_pwsid_obs==21,]

# Binary violation variables
# specific mining violations
full[["nitrates"]] <- 0
full[["nitrates"]][full$RULE_CODE_331.0==1] <- 1

full[["arsenic"]] <- 0
full[["arsenic"]][full$RULE_CODE_332.0==1] <- 1

full[["inorganic_chemicals"]] <- 0
full[["inorganic_chemicals"]][full$RULE_CODE_333.0==1] <- 1

full[["radionuclides"]] <- 0
full[["radionuclides"]][full$RULE_CODE_340.0==1] <- 1

full[["lead_copper_rule"]] <- 0
full[["lead_copper_rule"]][full$RULE_CODE_350.0==1] <- 1

# non mining violations
full[["total_coliform"]] <- 0
full[["total_coliform"]][full$RULE_CODE_110.0==1 | full$RULE_CODE_111.0==1] <- 1

full[["surface_ground_water_rule"]] <- 0
full[["surface_ground_water_rule"]][full$RULE_CODE_121.0==1 | full$RULE_CODE_140.0==1 | full$RULE_CODE_122.0==1 | full$RULE_CODE_123.0==1] <- 1

full[["dbpr"]] <- 0
full[["dbpr"]][full$RULE_CODE_210.0==1 | full$RULE_CODE_220.0==1 | full$RULE_CODE_230.0==1] <- 1

full[["voc"]] <- 0
full[["voc"]][full$RULE_CODE_310.0==1] <- 1

full[["soc"]] <- 0
full[["soc"]][full$RULE_CODE_320.0==1] <- 1


### 2SLS regression
################################################
# ── Modified tsls_reg_output ────────────────────────────────────────────────

tsls_reg_output <- function(dset, varlist, coalvar, regoutname, title, label,
                             instr_str, storage_list_name = NULL,
                             subheader = NULL, fulldset = 1) {

  controls             <- c("num_facilities")
  drop_controls_exact  <- paste0("^(", paste(controls, collapse = "|"), ")$")
  fe                   <- "PWSID + STATE_CODE + year"
  controls_str         <- paste(controls, collapse = " + ")
  fe_str               <- fe

  get_data_subset <- function(outcome) {
    if (fulldset == 0) {
      dset[(dset[[outcome]] > 0) | (dset$no_violation == 1), , drop = FALSE]
    } else {
      dset
    }
  }

  result <- list()

  for (y in varlist) {
    dat_y <- get_data_subset(y)

    f_ols <- as.formula(
      paste0(y, " ~ ", paste(c(paste(coalvar, collapse = "+"), controls_str),
                              collapse = " + "), " | ", fe_str)
    )
    f_rf <- as.formula(
      paste0(y, " ~ ", paste(c(instr_str, controls_str), collapse = " + "),
             " | ", fe_str)
    )
    f_iv <- as.formula(
      paste0(y, " ~ ", controls_str,
             " | ", fe_str,
             " | ", paste(coalvar, collapse = "+"), " ~ ", instr_str)
    )
    print(f_rf)
    print(f_iv)

    mod_ols <- fixest::feols(f_ols, data = dat_y, cluster = ~ PWSID)
    mod_rf  <- fixest::feols(f_rf,  data = dat_y, cluster = ~ PWSID)
    mod_iv  <- fixest::feols(f_iv,  data = dat_y, cluster = ~ PWSID)
    print(summary(mod_rf))
    print(summary(mod_iv, stage = 2))
    print(mod_iv$fixef_removed)

    result[[y]] <- list(OLS = mod_ols, RF = mod_rf, IV = mod_iv)
  }

  # ── Persist first stages to global list ──────────────────────────────────
  if (!is.null(storage_list_name) && !is.null(subheader)) {

    # Create the list in .GlobalEnv if it doesn't exist yet
    if (!exists(storage_list_name, envir = .GlobalEnv)) {
      assign(storage_list_name, list(), envir = .GlobalEnv)
    }

    fs_list <- get(storage_list_name, envir = .GlobalEnv)

    # Initialise this subheader bucket if needed
    if (is.null(fs_list[[subheader]])) {
      fs_list[[subheader]] <- list()
    }

    # Store the first stage for every outcome; key = outcome depvar name
    # iv_first_stage is a named list of feols objects, one per endogenous var
    for (y in varlist) {
      for (cv in coalvar) {
        fs_list[[subheader]][[y]][[cv]] <- result[[y]]$IV$iv_first_stage[[cv]]
      }
    }

    assign(storage_list_name, fs_list, envir = .GlobalEnv)
  }

  # ── Main etable output (unchanged) ───────────────────────────────────────
  model_list <- unlist(
    lapply(varlist, function(y) list(result[[y]]$OLS, result[[y]]$RF, result[[y]]$IV)),
    recursive = FALSE
  )

  do.call(etable, c(
    model_list,
    list(
      fitstat   = ~ . + ivf1,
      style.tex = style.tex("aer", adjustbox = TRUE),
      tex       = TRUE,
      drop      = drop_controls_exact,
      title     = title,
      label     = label,
      file      = paste0("Z:/ek559/mining_wq/output/reg/", regoutname, ".tex")
    )
  ))
}


# ── First-stage table function ───────────────────────────────────────────────
#
# Produces a single etable from every first stage stored in `storage_list_name`.
#
# Column layout (two-level header):
#   Top row    – subheader label, spanning as many columns as outcomes in that call
#   Bottom row – outcome (structural-equation depvar) name, one column each
#
# If coalvar had multiple endogenous regressors, pass the one you want via
# `which_coalvar`; defaults to the first one found.

first_stage_table <- function(storage_list_name, outfile, title = NULL,
                               label = NULL, which_coalvar = NULL,
                               drop = NULL) {

  fs_list <- get(storage_list_name, envir = .GlobalEnv)

  model_list      <- list()   # flat list of feols first-stage objects
  inner_headers   <- list()   # one entry per column: depvar name, spans 1
  outer_headers   <- list()   # one entry per subheader: name, spans N cols

  for (subheader in names(fs_list)) {

    depvar_bucket <- fs_list[[subheader]]   # list keyed by structural depvar
    n_cols        <- 0

    for (depvar in names(depvar_bucket)) {

      coal_models <- depvar_bucket[[depvar]]   # named list by coalvar

      # Pick the endogenous regressor to tabulate
      cv <- if (!is.null(which_coalvar)) {
        which_coalvar
      } else {
        names(coal_models)[1]
      }

      model_list             <- c(model_list, list(coal_models[[cv]]))
      inner_headers[[depvar]] <- 1L   # each depvar spans exactly 1 column
      n_cols                 <- n_cols + 1L
    }

    outer_headers[[subheader]] <- n_cols
  }

  # etable accepts a list-of-lists for multi-row headers:
  #   first list  = top    header row (subheaders)
  #   second list = bottom header row (depvar labels)
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

# Each call names the global list ("fs_store") and its own subheader.
# Repeated calls with the same list name append rather than overwrite.

tsls_reg_output(
  full[(full$minehuc_downstream_of_mine == 0) & (full$minehuc_mine == 1), ],
  c("nitrates_share", "arsenic_share", "inorganic_chemicals_share", "radionuclides_share"),
  c("num_coal_mines_unified"),
  "olsrf2sls_nummine_mine_vio_1985to2005colocate_coalunified",
  "Effect of number of mines on PWS violations (only colocated PWS's)",
  "olsrf2sls_nummine_mine_vio_1985to2005colocate_coalunified",
  "post95*sulfur_unified",
  storage_list_name = "fs_store_minevio",
  subheader         = "Colocated"
)

tsls_reg_output(
  full[(full$minehuc_downstream_of_mine == 1) & (full$minehuc_mine == 0), ],
  c("nitrates_share", "arsenic_share", "inorganic_chemicals_share", "radionuclides_share"),
  c("num_coal_mines_upstream"),
  "olsrf2sls_nummine_mine_vio_1985to2005dwnstrm_coalunified",
  "Effect of number of mines on PWS violations (only downstream PWS's)",
  "olsrf2sls_nummine_mine_vio_1985to2005dwnstrm_coalunified",
  "post95*sulfur_unified",
  storage_list_name = "fs_store_minevio",
  subheader         = "Downstream"
)

# ... remaining calls ...

# After all calls, produce the combined first-stage table
first_stage_table(
  storage_list_name = "fs_store_minevio",
  outfile           = "first_stages_combined",
  title             = "First Stage Results Across Samples",
  label             = "tab:first_stages",
  drop              = "num_facilities"
)



## rather than a separate upstream and colocate production variable
# this specification uses one variable which is upstream if the production is downstream
# and and average of upstream and colocated if the production is in the huc
tsls_reg_output(full[(full$minehuc_downstream_of_mine == 0) & (full$minehuc_mine == 1),],
                c("nitrates_share",
                "arsenic_share",
                "inorganic_chemicals_share",
                "radionuclides_share"),
                c("num_coal_mines_unified"),
                "olsrf2sls_nummine_mine_vio_1985to2005colocate_coalunified",
                "Effect of number of mines on PWS violations (only colocated PWS's)",
                "olsrf2sls_nummine_mine_vio_1985to2005colocate_coalunified",
                "post95*sulfur_unified")

tsls_reg_output(full[(full$minehuc_downstream_of_mine == 1) & (full$minehuc_mine == 0),],
                c("nitrates_share",
                "arsenic_share",
                "inorganic_chemicals_share",
                "radionuclides_share"),
                c("num_coal_mines_upstream"),
                "olsrf2sls_nummine_mine_vio_1985to2005dwnstrm_coalunified",
                "Effect of number of mines on PWS violations (only downstream PWS's)",
                "olsrf2sls_nummine_mine_vio_1985to2005dwnstrm_coalunified",
                "post95*sulfur_unified")

tsls_reg_output(full[full$minehuc_upstream_of_mine == 0, ],
                c("nitrates_share",
                "arsenic_share",
                "inorganic_chemicals_share",
                "radionuclides_share"),
                c("num_coal_mines_unified"),
                "olsrf2sls_nummine_mine_vio_1985to2005colocateddownstream_coalunified",
                "Effect of number of mines on PWS violations (colocated and downstream PWS's)",
                "olsrf2sls_nummine_mine_vio_1985to2005colocateddownstream_coalunified",
                "post95*sulfur_unified")

tsls_reg_output(full,
                c("nitrates_share",
                "arsenic_share",
                "inorganic_chemicals_share",
                "radionuclides_share"),
                c("num_coal_mines_unified"),
                "olsrf2sls_nummine_mine_vio_1985to2005allhucs_coalunified",
                "Effect of number of mines on PWS violations (all PWS's)",
                "olsrf2sls_nummine_mine_vio_1985to2005allhucs_coalunified",
                "post95*sulfur_unified")

## number of mines related violations and robustness checks 
tsls_reg_output(full[(full$minehuc_downstream_of_mine == 0) & (full$minehuc_mine == 1),],
                c("nitrates_share",
                "arsenic_share",
                "inorganic_chemicals_share",
                "radionuclides_share"),
                c("num_coal_mines_colocated"),
                "olsrf2sls_nummine_mine_vio_1985to2005colocate",
                "Effect of number of mines on PWS violations (only colocated PWS's)",
                "olsrf2sls_nummine_mine_vio_1985to2005colocate",
                "post95*sulfur_colocated")

tsls_reg_output(full[(full$minehuc_downstream_of_mine == 1) & (full$minehuc_mine == 0),],
                c("nitrates_share",
                "arsenic_share",
                "inorganic_chemicals_share",
                "radionuclides_share"),
                c("num_coal_mines_upstream"),
                "olsrf2sls_nummine_mine_vio_1985to2005dwnstrm",
                "Effect of number of mines on PWS violations (only downstream PWS's)",
                "olsrf2sls_nummine_mine_vio_1985to2005dwnstrm",
                "post95*sulfur_upstream")

tsls_reg_output(full[full$minehuc_upstream_of_mine==0,],
                c("nitrates_share",
                "arsenic_share",
                "inorganic_chemicals_share",
                "radionuclides_share"),
                c("num_coal_mines_colocated"),
                "olsrf2sls_nummine_mine_vio_1985to2005_colocateddownstream",
                "Effect of number of mines on PWS violations (colocated & downstream PWS's)",
                "olsrf2sls_nummine_mine_vio_1985to2005_colocateddownstream",
                "post95*sulfur_colocated")

tsls_reg_output(full,
                c("nitrates_share",
                "arsenic_share",
                "inorganic_chemicals_share",
                "radionuclides_share"),
                c("num_coal_mines_colocated"),
                "olsrf2sls_nummine_mine_vio_1985to2005allhucs",
                "Effect of number of mines on PWS violations (all PWS's)",
                "olsrf2sls_nummine_mine_vio_1985to2005allhucs",
                "post95*sulfur_colocated")

## number of mines related violations and robustness checks binary outcome
tsls_reg_output(full[(full$minehuc_downstream_of_mine == 0) & (full$minehuc_mine == 1),],
                c("nitrates",
                "arsenic",
                "inorganic_chemicals",
                "radionuclides"),
                c("num_coal_mines_colocated"),
                "olsrf2sls_nummine_mine_vio_binary_1985to2005colocate",
                "Effect of number of mines on PWS violations (only colocated PWS's)",
                "olsrf2sls_nummine_mine_vio_binary_1985to2005colocate",
                "post95*sulfur_colocated")

tsls_reg_output(full[(full$minehuc_downstream_of_mine == 1) & (full$minehuc_mine == 0),],
                c("nitrates",
                "arsenic",
                "inorganic_chemicals",
                "radionuclides"),
                c("num_coal_mines_upstream"),
                "olsrf2sls_nummine_mine_vio_binary_1985to2005dwnstrm",
                "Effect of number of mines on PWS violations (only downstream PWS's)",
                "olsrf2sls_nummine_mine_vio_binary_1985to2005dwnstrm",
                "post95*sulfur_upstream")

tsls_reg_output(full[full$minehuc_upstream_of_mine==0,],
                c("nitrates",
                "arsenic",
                "inorganic_chemicals",
                "radionuclides"),
                c("num_coal_mines_colocated"),
                "olsrf2sls_nummine_mine_vio_binary_1985to2005_colocateddownstream",
                "Effect of number of mines on PWS violations (colocated & downstream PWS's)",
                "olsrf2sls_nummine_mine_vio_binary_1985to2005_colocateddownstream",
                "post95*sulfur_colocated")

tsls_reg_output(full,
                c("nitrates",
                "arsenic",
                "inorganic_chemicals",
                "radionuclides"),
                c("num_coal_mines_colocated"),
                "olsrf2sls_nummine_mine_vio_binary_1985to2005allhucs",
                "Effect of number of mines on PWS violations (all PWS's)",
                "olsrf2sls_nummine_mine_vio_binary_1985to2005allhucs",
                "post95*sulfur_colocated")

###############
## non-mine vio
###############
tsls_reg_output(full[(full$minehuc_downstream_of_mine == 0) & (full$minehuc_mine == 1),],
                c("total_coliform_share",
                  "surface_ground_water_rule_share",
                  "voc_share",
                  "soc_share"),
                c("num_coal_mines_unified"),
                "olsrf2sls_nummine_non_mine_vio_1985to2005colocate_coalunified",
                "Effect of number of mines on PWS violations (only colocated PWS's)",
                "olsrf2sls_nummine_non_mine_vio_1985to2005colocate_coalunified",
                "post95*sulfur_unified")

tsls_reg_output(full[(full$minehuc_downstream_of_mine == 1) & (full$minehuc_mine == 0),],
                c("total_coliform_share",
                  "surface_ground_water_rule_share",
                  "voc_share",
                  "soc_share"),
                c("num_coal_mines_unified"),
                "olsrf2sls_nummine_non_mine_vio_1985to2005dwnstrm_coalunified",
                "Effect of number of mines on PWS violations (only downstream PWS's)",
                "olsrf2sls_nummine_non_mine_vio_1985to2005dwnstrm_coalunified",
                "post95*sulfur_unified")

tsls_reg_output(full,
                c("total_coliform_share",
                  "surface_ground_water_rule_share",
                  "voc_share",
                  "soc_share"),
                c("num_coal_mines_unified"),
                "olsrf2sls_nummine_non_mine_vio_1985to2005allhucs_coalunified",
                "Effect of number of mines on PWS violations (all PWS's)",
                "olsrf2sls_nummine_non_mine_vio_1985to2005allhucs_coalunified",
                "post95*sulfur_unified")

## number of mines related violations and robustness checks 
tsls_reg_output(full[(full$minehuc_downstream_of_mine == 0) & (full$minehuc_mine == 1),],
                c("total_coliform_share",
                  "surface_ground_water_rule_share",
                  "voc_share",
                  "soc_share"),
                c("num_coal_mines_colocated"),
                "olsrf2sls_nummine_non_mine_vio_1985to2005colocate",
                "Effect of number of mines on PWS violations (only colocated PWS's)",
                "olsrf2sls_nummine_non_mine_vio_1985to2005colocate",
                "post95*sulfur_colocated")

tsls_reg_output(full[(full$minehuc_downstream_of_mine == 1) & (full$minehuc_mine == 0),],
                c("total_coliform_share",
                  "surface_ground_water_rule_share",
                  "voc_share",
                  "soc_share"),
                c("num_coal_mines_upstream"),
                "olsrf2sls_nummine_non_mine_vio_1985to2005dwnstrm",
                "Effect of number of mines on PWS violations (only downstream PWS's)",
                "olsrf2sls_nummine_non_mine_vio_1985to2005dwnstrm",
                "post95*sulfur_upstream")

tsls_reg_output(full[full$minehuc_upstream_of_mine==0,],
                c("total_coliform_share",
                  "surface_ground_water_rule_share",
                  "voc_share",
                  "soc_share"),
                c("num_coal_mines_colocated"),
                "olsrf2sls_nummine_non_mine_vio_1985to2005_colocateddownstream",
                "Effect of number of mines on PWS violations (colocated & downstream PWS's)",
                "olsrf2sls_nummine_non_mine_vio_1985to2005_colocateddownstream",
                "post95*sulfur_colocated")

tsls_reg_output(full,
                c("total_coliform_share",
                  "surface_ground_water_rule_share",
                  "voc_share",
                  "soc_share"),
                c("num_coal_mines_colocated"),
                "olsrf2sls_nummine_non_mine_vio_1985to2005allhucs",
                "Effect of number of mines on PWS violations (all PWS's)",
                "olsrf2sls_nummine_non_mine_vio_1985to2005allhucs",
                "post95*sulfur_colocated")

## number of mines related violations and robustness checks binary outcome
tsls_reg_output(full[(full$minehuc_downstream_of_mine == 0) & (full$minehuc_mine == 1),],
                c("total_coliform",
                  "surface_ground_water_rule",
                  "voc",
                  "soc"),
                c("num_coal_mines_colocated"),
                "olsrf2sls_nummine_non_mine_vio_binary_1985to2005colocate",
                "Effect of number of mines on PWS violations (only colocated PWS's)",
                "olsrf2sls_nummine_non_mine_vio_binary_1985to2005colocate",
                "post95*sulfur_colocated")

tsls_reg_output(full[(full$minehuc_downstream_of_mine == 1) & (full$minehuc_mine == 0),],
                c("total_coliform",
                  "surface_ground_water_rule",
                  "voc",
                  "soc"),
                c("num_coal_mines_upstream"),
                "olsrf2sls_nummine_non_mine_vio_binary_1985to2005dwnstrm",
                "Effect of number of mines on PWS violations (only downstream PWS's)",
                "olsrf2sls_nummine_non_mine_vio_binary_1985to2005dwnstrm",
                "post95*sulfur_upstream")

tsls_reg_output(full[full$minehuc_upstream_of_mine==0,],
                c("total_coliform",
                  "surface_ground_water_rule",
                  "voc",
                  "soc"),
                c("num_coal_mines_colocated"),
                "olsrf2sls_nummine_non_mine_vio_binary_1985to2005_colocateddownstream",
                "Effect of number of mines on PWS violations (colocated and downstream PWS's)",
                "olsrf2sls_nummine_non_mine_vio_binary_1985to2005allhucs_colocateddownstream",
                "post95*sulfur_colocated")

tsls_reg_output(full,
                c("total_coliform",
                  "surface_ground_water_rule",
                  "voc",
                  "soc"),
                c("num_coal_mines_colocated"),
                "olsrf2sls_nummine_non_mine_vio_binary_1985to2005allhucs",
                "Effect of number of mines on PWS violations (all PWS's)",
                "olsrf2sls_nummine_non_mine_vio_binary_1985to2005allhucs",
                "post95*sulfur_colocated")

###################################################
# Num violations/mine violations/nonmine violations
###################################################

tsls_reg_output(full[(full$minehuc_downstream_of_mine == 0) & (full$minehuc_mine == 1),],
                c("num_violations",
                  "num_mining_violations",
                  "num_non_mining_violations"),
                c("num_coal_mines_unified"),
                "olsrf2sls_nummine_count_vio_1985to2005colocate_coalunified",
                "Effect of number of mines on PWS violations (only colocated PWS's)",
                "olsrf2sls_nummine_count_vio_1985to2005colocate_coalunified",
                "post95*sulfur_unified")

tsls_reg_output(full[(full$minehuc_downstream_of_mine == 1) & (full$minehuc_mine == 0),],
                c("num_violations",
                  "num_mining_violations",
                  "num_non_mining_violations"),
                c("num_coal_mines_unified"),
                "olsrf2sls_nummine_count_vio_1985to2005dwnstrm_coalunified",
                "Effect of number of mines on PWS violations (only downstream PWS's)",
                "olsrf2sls_nummine_count_vio_1985to2005dwnstrm_coalunified",
                "post95*sulfur_unified")

tsls_reg_output(full,
                c("num_violations",
                  "num_mining_violations",
                  "num_non_mining_violations"),
                c("num_coal_mines_unified"),
                "olsrf2sls_nummine_count_vio_1985to2005allhucs_coalunified",
                "Effect of number of mines on PWS violations (all PWS's)",
                "olsrf2sls_nummine_count_vio_1985to2005allhucs_coalunified",
                "post95*sulfur_unified")

## number of mines related violations and robustness checks 
tsls_reg_output(full[(full$minehuc_downstream_of_mine == 0) & (full$minehuc_mine == 1),],
                c("num_violations",
                  "num_mining_violations",
                  "num_non_mining_violations"),
                c("num_coal_mines_colocated"),
                "olsrf2sls_nummine_count_vio_1985to2005colocate",
                "Effect of number of mines on PWS violations (only colocated PWS's)",
                "olsrf2sls_nummine_count_vio_1985to2005colocate",
                "post95*sulfur_colocated")

tsls_reg_output(full[(full$minehuc_downstream_of_mine == 1) & (full$minehuc_mine == 0),],
                c("num_violations",
                  "num_mining_violations",
                  "num_non_mining_violations"),
                c("num_coal_mines_upstream"),
                "olsrf2sls_nummine_count_vio_1985to2005dwnstrm",
                "Effect of number of mines on PWS violations (only downstream PWS's)",
                "olsrf2sls_nummine_count_vio_1985to2005dwnstrm",
                "post95*sulfur_upstream")

tsls_reg_output(full,
                c("num_violations",
                  "num_mining_violations",
                  "num_non_mining_violations"),
                c("num_coal_mines_colocated"),
                "olsrf2sls_nummine_count_vio_1985to2005allhucs",
                "Effect of number of mines on PWS violations (all PWS's)",
                "olsrf2sls_nummine_count_vio_1985to2005allhucs",
                "post95*sulfur_colocated")

#############################################
# Num mines as above but years from 1990-2000
#############################################

tsls_reg_output(full[(full$minehuc_downstream_of_mine == 0) & (full$minehuc_mine == 1) &
                     (1990<=full$year & full$year<=2000),],
                c("nitrates_share",
                "arsenic_share",
                "inorganic_chemicals_share",
                "radionuclides_share"),
                c("num_coal_mines_unified"),
                "olsrf2sls_nummine_mine_vio_1990to2000colocate_coalunified",
                "Effect of number of mines on PWS violations 1990-2000 (only colocated PWS's)",
                "olsrf2sls_nummine_mine_vio_1990to2000colocate_coalunified",
                "post95*sulfur_unified")

tsls_reg_output(full[(full$minehuc_downstream_of_mine == 1) & (full$minehuc_mine == 0)
                     & (1990<=full$year & full$year<=2000),],
                c("nitrates_share",
                "arsenic_share",
                "inorganic_chemicals_share",
                "radionuclides_share"),
                c("num_coal_mines_unified"),
                "olsrf2sls_nummine_mine_vio_1990to2000dwnstrm_coalunified",
                "Effect of number of mines on PWS violations 1990-2000 (only downstream PWS's)",
                "olsrf2sls_nummine_mine_vio_1990to2000dwnstrm_coalunified",
                "post95*sulfur_unified")

tsls_reg_output(full[(1990<=full$year & full$year<=2000),],
                c("nitrates_share",
                "arsenic_share",
                "inorganic_chemicals_share",
                "radionuclides_share"),
                c("num_coal_mines_unified"),
                "olsrf2sls_nummine_mine_vio_1990to2000allhucs_coalunified",
                "Effect of number of mines on PWS violations 1990-2000 (all PWS's)",
                "olsrf2sls_nummine_mine_vio_1990to2000allhucs_coalunified",
                "post95*sulfur_unified")

## number of mines related violations and robustness checks 
tsls_reg_output(full[(full$minehuc_downstream_of_mine == 0) & (full$minehuc_mine == 1)
                     & (1990<=full$year & full$year<=2000),],
                c("nitrates_share",
                "arsenic_share",
                "inorganic_chemicals_share",
                "radionuclides_share"),
                c("num_coal_mines_colocated"),
                "olsrf2sls_nummine_mine_vio_1990to2000colocate",
                "Effect of number of mines on PWS violations 1990-2000 (only colocated PWS's)",
                "olsrf2sls_nummine_mine_vio_1990to2000colocate",
                "post95*sulfur_colocated")

tsls_reg_output(full[(full$minehuc_downstream_of_mine == 1) & (full$minehuc_mine == 0) &
                    (1990<=full$year & full$year<=2000),],
                c("nitrates_share",
                "arsenic_share",
                "inorganic_chemicals_share",
                "radionuclides_share"),
                c("num_coal_mines_upstream"),
                "olsrf2sls_nummine_mine_vio_1990to2000dwnstrm",
                "Effect of number of mines on PWS violations 1990-2000 (only downstream PWS's)",
                "olsrf2sls_nummine_mine_vio_1990to2000dwnstrm",
                "post95*sulfur_upstream")

tsls_reg_output(full[(1990<=full$year & full$year<=2000),],
                c("nitrates_share",
                "arsenic_share",
                "inorganic_chemicals_share",
                "radionuclides_share"),
                c("num_coal_mines_colocated"),
                "olsrf2sls_nummine_mine_vio_1990to2000allhucs",
                "Effect of number of mines on PWS violations 1990-2000 (all PWS's)",
                "olsrf2sls_nummine_mine_vio_1990to2000allhucs",
                "post95*sulfur_colocated")

###############
## non-mine vio
###############
tsls_reg_output(full[(full$minehuc_downstream_of_mine == 0) & (full$minehuc_mine == 1) &
                     (1990<=full$year & full$year<=2000),],
                c("total_coliform_share",
                  "surface_ground_water_rule_share",
                  "voc_share",
                  "soc_share"),
                c("num_coal_mines_unified"),
                "olsrf2sls_nummine_non_mine_vio_1990to2000colocate_coalunified",
                "Effect of number of mines on PWS violations 1990-2000 (only colocated PWS's)",
                "olsrf2sls_nummine_non_mine_vio_1990to2000colocate_coalunified",
                "post95*sulfur_unified")

tsls_reg_output(full[(full$minehuc_downstream_of_mine == 1) & (full$minehuc_mine == 0)&
                    (1990<=full$year & full$year<=2000),],
                c("total_coliform_share",
                  "surface_ground_water_rule_share",
                  "voc_share",
                  "soc_share"),
                c("num_coal_mines_unified"),
                "olsrf2sls_nummine_non_mine_vio_1990to2000dwnstrm_coalunified",
                "Effect of number of mines on PWS violations 1990-2000 (only downstream PWS's)",
                "olsrf2sls_nummine_non_mine_vio_1990to2000dwnstrm_coalunified",
                "post95*sulfur_unified")

tsls_reg_output(full[(1990<=full$year & full$year<=2000),],
                c("total_coliform_share",
                  "surface_ground_water_rule_share",
                  "voc_share",
                  "soc_share"),
                c("num_coal_mines_unified"),
                "olsrf2sls_nummine_non_mine_vio_1990to2000allhucs_coalunified",
                "Effect of number of mines on PWS violations 1990-2000 (all PWS's)",
                "olsrf2sls_nummine_non_mine_vio_1990to2000allhucs_coalunified",
                "post95*sulfur_unified")

## number of mines related violations and robustness checks 
tsls_reg_output(full[(full$minehuc_downstream_of_mine == 0) & (full$minehuc_mine == 1) &
                    (1990<=full$year & full$year<=2000),],
                c("total_coliform_share",
                  "surface_ground_water_rule_share",
                  "voc_share",
                  "soc_share"),
                c("num_coal_mines_colocated"),
                "olsrf2sls_nummine_non_mine_vio_1990to2000colocate",
                "Effect of number of mines on PWS violations 1990-2000 (only colocated PWS's)",
                "olsrf2sls_nummine_non_mine_vio_1990to2000colocate",
                "post95*sulfur_colocated")

tsls_reg_output(full[(full$minehuc_downstream_of_mine == 1) & (full$minehuc_mine == 0) &
                    (1990<=full$year & full$year<=2000),],
                c("total_coliform_share",
                  "surface_ground_water_rule_share",
                  "voc_share",
                  "soc_share"),
                c("num_coal_mines_upstream"),
                "olsrf2sls_nummine_non_mine_vio_1990to2000dwnstrm",
                "Effect of number of mines on PWS violations 1990-2000 (only downstream PWS's)",
                "olsrf2sls_nummine_non_mine_vio_1990to2000dwnstrm",
                "post95*sulfur_upstream")

tsls_reg_output(full[(1990<=full$year & full$year<=2000),],
                c("total_coliform_share",
                  "surface_ground_water_rule_share",
                  "voc_share",
                  "soc_share"),
                c("num_coal_mines_colocated"),
                "olsrf2sls_nummine_non_mine_vio_1990to2000allhucs",
                "Effect of number of mines on PWS violations 1990-2000 (all PWS's)",
                "olsrf2sls_nummine_non_mine_vio_1990to2000allhucs",
                "post95*sulfur_colocated")

###################################################
# Num violations/mine violations/nonmine violations
###################################################

tsls_reg_output(full[(full$minehuc_downstream_of_mine == 0) & (full$minehuc_mine == 1) &
                    (1990<=full$year & full$year<=2000),],
                c("num_violations",
                  "num_mining_violations",
                  "num_non_mining_violations"),
                c("num_coal_mines_unified"),
                "olsrf2sls_nummine_count_vio_1990to2000colocate_coalunified",
                "Effect of number of mines on PWS violations 1990-2000 (only colocated PWS's)",
                "olsrf2sls_nummine_count_vio_1990to2000colocate_coalunified",
                "post95*sulfur_unified")

tsls_reg_output(full[(full$minehuc_downstream_of_mine == 1) & (full$minehuc_mine == 0) &
                    (1990<=full$year & full$year<=2000),],
                c("num_violations",
                  "num_mining_violations",
                  "num_non_mining_violations"),
                c("num_coal_mines_unified"),
                "olsrf2sls_nummine_count_vio_1990to2000dwnstrm_coalunified",
                "Effect of number of mines on PWS violations 1990-2000 (only downstream PWS's)",
                "olsrf2sls_nummine_count_vio_1990to2000dwnstrm_coalunified",
                "post95*sulfur_unified")

tsls_reg_output(full[(1990<=full$year & full$year<=2000),],
                c("num_violations",
                  "num_mining_violations",
                  "num_non_mining_violations"),
                c("num_coal_mines_unified"),
                "olsrf2sls_nummine_count_vio_1990to2000allhucs_coalunified",
                "Effect of number of mines on PWS violations 1990-2000 (all PWS's)",
                "olsrf2sls_nummine_count_vio_1990to2000allhucs_coalunified",
                "post95*sulfur_unified")

## number of mines related violations and robustness checks 
tsls_reg_output(full[(full$minehuc_downstream_of_mine == 0) & (full$minehuc_mine == 1) &
                    (1990<=full$year & full$year<=2000),],
                c("num_violations",
                  "num_mining_violations",
                  "num_non_mining_violations"),
                c("num_coal_mines_colocated"),
                "olsrf2sls_nummine_count_vio_1990to2000colocate",
                "Effect of number of mines on PWS violations 1990-2000 (only colocated PWS's)",
                "olsrf2sls_nummine_count_vio_1990to2000colocate",
                "post95*sulfur_colocated")

tsls_reg_output(full[(full$minehuc_downstream_of_mine == 1) & (full$minehuc_mine == 0) &
                    (1990<=full$year & full$year<=2000),],
                c("num_violations",
                  "num_mining_violations",
                  "num_non_mining_violations"),
                c("num_coal_mines_upstream"),
                "olsrf2sls_nummine_count_vio_1990to2000dwnstrm",
                "Effect of number of mines on PWS violations 1990-2000 (only downstream PWS's)",
                "olsrf2sls_nummine_count_vio_1990to2000dwnstrm",
                "post95*sulfur_upstream")

tsls_reg_output(full[(1990<=full$year & full$year<=2000),],
                c("num_violations",
                  "num_mining_violations",
                  "num_non_mining_violations"),
                c("num_coal_mines_colocated"),
                "olsrf2sls_nummine_count_vio_1990to2000allhucs",
                "Effect of number of mines on PWS violations 1990-2000 (all PWS's)",
                "olsrf2sls_nummine_count_vio_1990to2000allhucs",
                "post95*sulfur_colocated")

##########################################################################
## Tonnes of coal produced mining related violations and robustness checks 
##########################################################################

tsls_reg_output(full[full$minehuc_downstream_of_mine == 1,],
                c("nitrates_share",
                "arsenic_share",
                "inorganic_chemicals_share",
                "radionuclides_share"),
                "production_short_tons_coal",
                "olsrf2sls_tonprod_mine_vio_1985to2005dwnstrmcolocate",
                "Effect of number of mines on PWS violations (downstream and colocated PWS's)",
                "olsrf2sls_tonprod_mine_vio_1985to2005dwnstrmcolocate")

tsls_reg_output(full[full$minehuc_downstream_of_mine == 1 & full$minehuc_mine == 0,],
                c("nitrates_share",
                "arsenic_share",
                "inorganic_chemicals_share",
                "radionuclides_share"),
                "production_short_tons_coal",
                "olsrf2sls_tonprod_mine_vio_1985to2005dwnstrm",
                "Effect of number of mines on PWS violations (only downstream PWS's)",
                "olsrf2sls_tonprod_mine_vio_1985to2005dwnstrm")

tsls_reg_output(full,
                c("nitrates_share",
                "arsenic_share",
                "inorganic_chemicals_share",
                "radionuclides_share"),
                "production_short_tons_coal",
                "olsrf2sls_tonprod_mine_vio_1985to2005allhucs",
                "Effect of number of mines on PWS violations (all PWS's)",
                "olsrf2sls_tonprod_mine_vio_1985to2005allhucs")

## non-mine vio
tsls_reg_output(full[full$minehuc_downstream_of_mine == 1,],
                c("total_coliform_share",
                  "surface_ground_water_rule_share",
                  "voc_share",
                  "soc_share"),
                "production_short_tons_coal",
                "olsrf2sls_tonprod_nonmine_vio_1985to2005dwnstrmcolocate",
                "Effect of number of mines on PWS violations (downstream and colocated PWS's)",
                "olsrf2sls_tonprod_nonmine_vio_1985to2005dwnstrmcolocate")

tsls_reg_output(full[full$minehuc_downstream_of_mine == 1 & full$minehuc_mine == 0,],
                c("total_coliform_share",
                  "surface_ground_water_rule_share",
                  "voc_share",
                  "soc_share"),
                "production_short_tons_coal",
                "olsrf2sls_tonprod_nonmine_vio_1985to2005dwnstrm",
                "Effect of number of mines on PWS violations (only downstream PWS's)",
                "olsrf2sls_tonprod_nonmine_vio_1985to2005dwnstrm")

tsls_reg_output(full,
                c("total_coliform_share",
                  "surface_ground_water_rule_share",
                  "voc_share",
                  "soc_share"),
                "production_short_tons_coal",
                "olsrf2sls_tonprod_nonmine_vio_1985to2005allhucs",
                "Effect of number of mines on PWS violations (all PWS's)",
                "olsrf2sls_tonprod_nonmine_vio_1985to2005allhucs")

####################
# poisson regression
####################

tsls_poisson_reg_output <- function(dset, varlist, coalvar, regoutname, title, label){
    no_fe_controls <- c("post95", "sulfur", "POPULATION_SERVED_COUNT","SOURCE_WATER_PROTECTION_CODE_Y",
                  "PRIMARY_SOURCE_CODE_GU", "PRIMARY_SOURCE_CODE_GUP", "PRIMARY_SOURCE_CODE_GW",
                  "PRIMARY_SOURCE_CODE_SW", "PRIMARY_SOURCE_CODE_SWP", "IS_WHOLESALER_IND_Y",
                  "IS_GRANT_ELIGIBLE_IND_Y", "IS_SOURCE_TREATED_IND_Y", "num_hucs",
                  "num_facilities", "PRIMARY_SOURCE_CODE_GWP")
    fe_controls <- paste(no_fe_controls, collapse = " + ")

    fe <- "PWSID + year"
    fe_controls <- paste(fe_controls, fe, sep = " | ")
    iv <- paste(coalvar, "~ post95*sulfur")

    poisson_no_fe <- paste(paste("~", coalvar, "+"), paste(no_fe_controls, collapse = " + "))
    poisson <- paste(paste("~", coalvar, "+"), paste(fe_controls, collapse = " + "))
    rf <- paste("~ post95*sulfur +", paste(fe_controls, collapse = " + "))
    tsls <- paste(paste(" ~ ", fe_controls), iv, sep = " | ")

    result <- list()
    num <- 0
    for (i in varlist) {
        num <- num + 1
        panelname <- paste0(paste0("Panel ", as.character(num), ": "), i)
        print(panelname)
        result[[panelname]] <- list(
            "Poisson" = fepois(as.formula(paste(i, poisson_no_fe)),
                        data = dset[(dset[[i]] > 0) |
                                    (dset$no_violation == 1), ],
                        cluster = ~ PWSID),
            "Poisson (FE)" = fepois(as.formula(paste(i, poisson)),
                        data = dset[(dset[[i]] > 0) |
                                    (dset$no_violation == 1), ],
                        cluster = ~ PWSID),
            "Poisson RF" = fepois(as.formula(paste(i, rf)),
                        data = dset[(dset[[i]] > 0) |
                                    (dset$no_violation == 1), ],
                        cluster = ~ PWSID))
        print(result[[panelname]][['Poisson']])
        print(result[[panelname]][['Poisson (FE)']])
        print(result[[panelname]][['Poisson RF']])
    }

    print(result[[panelname]])

    modelsummary(result,
                title = paste0(title, "\\label{tab:", label,"}"),
                stars = c('*' = .1, '**' = .05, '***' = .01),
                escape = FALSE,
                statistic = "conf.int",
                fmt = "%.3f",
                coef_omit = "^(?!.*post95|.*num_coal|.*production_short_tons_coal|.*fit_)",
                gof_omit = "BIC|AIC|R2 Within|Std",
                shape = "cbind",
                notes = c("Data is from 1990 to 2005.",
                          "Standard errors clustered at PWS level.")) |>                     
    format_tt(escape = FALSE) |>
    theme_latex(resize_width= 1, resize_direction="down") |>
    save_tt(paste0("Z:/ek559/mining_wq/output/reg/", regoutname, ".tex"), overwrite = TRUE)
}

## mining related violations and robustness checks 
tsls_poisson_reg_output(full[full$minehuc_downstream_of_mine == 1,],
                c("nitrates_share_days",
                "arsenic_share_days",
                "inorganic_chemicals_share_days",
                "radionuclides_share_days"),
                "num_coal_mines",
                "olsrf2slspoisson_nummine_mine_vio_1985to2005dwnstrmcolocate",
                "Effect of number of mines on PWS violations (downstream and colocated PWS's)",
                "poisson_nummine_mine_vio_1985to2005dwnstrmcolocate")

tsls_poisson_reg_output(full[full$minehuc_downstream_of_mine == 1 & full$minehuc_mine == 0,],
                c("nitrates_share_days",
                "arsenic_share_days",
                "inorganic_chemicals_share_days",
                "radionuclides_share_days"),
                "num_coal_mines",
                "olsrf2slspoisson_nummine_mine_vio_1985to2005dwnstrm",
                "Effect of number of mines on PWS violations (only downstream PWS's)",
                "poisson_nummine_mine_vio_1985to2005dwnstrm")

## non-mine vio
tsls_poisson_reg_output(full[full$minehuc_downstream_of_mine == 1,],
                c("total_coliform_share_days",
                  "surface_ground_water_rule_share_days",
                  "voc_share_days",
                  "soc_share_days"),
                "num_coal_mines",
                "poisson_nummine_nonmine_vio_1985to2005dwnstrmcolocate",
                "Effect of number of mines on PWS violations (downstream and colocated PWS's)",
                "poisson_nummine_nonmine_vio_1985to2005dwnstrmcolocate")

tsls_poisson_reg_output(full[full$minehuc_downstream_of_mine == 1 & full$minehuc_mine == 0,],
                c("total_coliform_share",
                  "surface_ground_water_rule_share",
                  "voc_share",
                  "soc_share"),
                "num_coal_mines",
                "poisson_nummine_nonmine_vio_1985to2005dwnstrm",
                "Effect of number of mines on PWS violations (only downstream PWS's)",
                "poisson_nummine_nonmine_vio_1985to2005dwnstrm")



