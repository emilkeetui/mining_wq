# ============================================================
# Script: run_k2_scaled_first_stage.r
# Purpose: First stage of post95 x sulfur on upstream coal mines and on annual
#          upstream coal production, scaled to % of the mean and to SD units.
#          Explains the constant 2SLS mines/production ratio.
# Inputs: k2_common.r inputs (step_instruments, covariates, violations, visits,
#         enforcement); output/reg/scaled_compare_all_k2.csv (identity gate)
# Outputs: clean_data/cws_data/k2_scaled_first_stage.parquet
# Author: EK  Date: 2026-10-15
# ============================================================

source("Z:/ek559/mining_wq/code/coal_mining_water_quality/k2_common.r")

# ── Sample: copied from run_k2_scaled_comparison.r ───────────────────────
main_dat <- build_k2_panel("main")
lone_states <- main_dat %>%
  dplyr::filter(!is.na(STATE_CODE)) %>%
  dplyr::group_by(STATE_CODE) %>%
  dplyr::summarise(n_util = dplyr::n_distinct(PWSID), .groups = "drop") %>%
  dplyr::filter(n_util == 1) %>%
  dplyr::pull(STATE_CODE)
main_dat <- main_dat %>% dplyr::filter(!is.na(STATE_CODE), !(STATE_CODE %in% lone_states))

fe_state_yr <- "PWSID + STATE_CODE^year"
OUT_VIO_ANY <- c("nitrates_bin", "arsenic_bin", "inorganic_chemicals_bin")
OUT_VIO_MR  <- c("nitrates_MR_bin", "arsenic_MR_bin", "inorganic_chemicals_MR_bin")
OUT_VIO_MCL <- c("nitrates_MCL_bin", "arsenic_MCL_bin", "inorganic_chemicals_MCL_bin")
OUT_VISIT   <- c("any_snsv", "any_tech", "any_enfvisit", "any_smpl", "any_insp")
OUT_ENF     <- c("any_informal", "any_formal", "no_enf")
all_y <- c(OUT_VIO_ANY, OUT_VIO_MR, OUT_VIO_MCL, OUT_VISIT, OUT_ENF)

main_dat$mines     <- main_dat$num_coal_mines_linked_sum
main_dat$prod_tons <- replace(main_dat$production_linked_sum, is.na(main_dat$production_linked_sum), 0)
main_dat$prod      <- main_dat$prod_tons / 1e6
need <- c(all_y, "mines", "prod", "num_facilities", "sulfur_mean0", "post95", "STATE_CODE")
main_dat <- main_dat[complete.cases(main_dat[, need]), ]
# drop utilities observed once (singleton utility FE), as in the parent script
main_dat <- main_dat[main_dat$PWSID %in% names(which(table(main_dat$PWSID) > 1)), ]
cat(sprintf("Main sample: %d obs, %d utilities\n", nrow(main_dat), dplyr::n_distinct(main_dat$PWSID)))
stopifnot(nrow(main_dat) == 10641L)

# ── First stages ─────────────────────────────────────────────────────────
fs_one <- function(xp) {
  m <- fixest::feols(as.formula(paste0(xp, " ~ post95:sulfur_mean0 + num_facilities | ", fe_state_yr)),
                     data = main_dat, cluster = ~PWSID, warn = FALSE, notes = FALSE)
  nm <- "post95:sulfur_mean0"
  list(pi = unname(coef(m)[nm]), pi_se = unname(fixest::se(m)[nm]), n_obs = nobs(m),
       xbar = mean(main_dat[[xp]]), sdx = sd(main_dat[[xp]]))
}
fs <- list(mines = fs_one("mines"), prod = fs_one("prod"))
reg_lab   <- c(mines = "Coal mines", prod = "Coal production")
scale_lab <- c(m = "Elasticity at the means", z = "Standard deviation units")

res <- do.call(rbind, lapply(names(fs), function(xp) {
  f <- fs[[xp]]
  do.call(rbind, lapply(c("m", "z"), function(sc) {
    div <- if (sc == "m") f$xbar / 100 else f$sdx   # % of mean per pp / SD units
    data.frame(regressor = xp, regressor_label = reg_lab[[xp]], scale = sc, scale_label = scale_lab[[sc]],
               coef = f$pi / div, se = f$pi_se / div, pi = f$pi, pi_se = f$pi_se,
               xbar = f$xbar, sdx = f$sdx, F = (f$pi / f$pi_se)^2, n_obs = f$n_obs,
               stringsAsFactors = FALSE)
  }))
}))

# ── Gates ────────────────────────────────────────────────────────────────
gate <- function(name, ok) {
  cat(sprintf("GATE %-72s %s\n", name, if (isTRUE(ok)) "PASS" else "FAIL"))
  if (!isTRUE(ok)) stop("Gate failed: ", name)
}
fm <- unique(res$F[res$regressor == "mines"]); fp <- unique(res$F[res$regressor == "prod"])
gate("F mines == 49.2", round(fm, 1) == 49.2)
gate("F prod == 11.8", round(fp, 1) == 11.8)
cmp <- read.csv(file.path(ROOT, "output/reg/scaled_compare_all_k2.csv"), stringsAsFactors = FALSE)
cmp <- cmp[cmp$estimator == "2SLS" & cmp$fe == fe_state_yr & cmp$outcome == "nitrates_MR_bin", ]
r_m <- cmp$ratio[cmp$scale == "m"]; r_z <- cmp$ratio[cmp$scale == "z"]
pm <- fs$mines; pp <- fs$prod
gate("Ratio identity, elasticity (pi_prod/xbar_prod)/(pi_mines/xbar_mines)",
     abs((pp$pi / pp$xbar) / (pm$pi / pm$xbar) - r_m) < 1e-6)
gate("Ratio identity, SD units (pi_prod/sd_prod)/(pi_mines/sd_mines)",
     abs((pp$pi / pp$sdx) / (pm$pi / pm$sdx) - r_z) < 1e-6)
stopifnot(!anyNA(res), nrow(res) == 4)

# ── Write ────────────────────────────────────────────────────────────────
res$n_obs <- as.integer(res$n_obs)
out_path <- file.path(ROOT, "clean_data/cws_data/k2_scaled_first_stage.parquet")
if (file.exists(out_path)) cat("WARNING:", out_path, "already exists -- overwriting\n")
arrow::write_parquet(res, out_path)
chk <- arrow::read_parquet(out_path)
str(chk)
print(chk[, c("regressor", "scale", "coef", "se", "pi", "F")], digits = 4)
cat(sprintf("Written %d rows x %d columns to %s\n", nrow(chk), ncol(chk), out_path))
