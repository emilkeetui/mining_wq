# ============================================================
# Script: run_k2_scaled_comparison.r
# Purpose: Re-estimate six k2 tables with the upstream mine count and upstream
#          coal production as the main regressor on common unit-free scales
#          (standard-deviation units; elasticity at the means; log(1+x)),
#          test equality of the two scaled coefficients with a stacked
#          regression, and write comparison tables + a CSV. Sources k2_common.r.
# Inputs:
#   clean_data/cws_data/step_instruments.parquet (via k2_common.r)
#   clean_data/cws_data/cws_covariates_steps.parquet (via k2_common.r)
#   clean_data/cws_data/sdwa_vio_agg_steps.parquet (via k2_common.r)
#   clean_data/cws_data/sdwa_visit_agg_k2.parquet (via k2_common.r)
#   clean_data/cws_data/sdwa_enf_agg_k2.parquet (via k2_common.r)
#   clean_data/cws_6year_review_ravalli.parquet
#   clean_data/cws_data/pwsid_huc02.parquet
# Outputs (all new, under output/reg/):
#   <stem>_k2_{sd,elas}_{mines,prod}.tex for the six parent tables (24 files)
#   scaled_compare_sd_k2.tex, scaled_compare_elas_k2.tex, scaled_compare_all_k2.csv
# Author: EK  Date: 2026-10-12
# ============================================================

source("Z:/ek559/mining_wq/code/coal_mining_water_quality/k2_common.r")

gate <- function(name, ok) {
  cat(sprintf("GATE %-72s %s\n", name, if (isTRUE(ok)) "PASS" else "FAIL"))
  if (!isTRUE(ok)) stop("Gate failed: ", name)
}
near <- function(a, b, tol = 1e-8) all(abs(a - b) < tol * pmax(1, abs(b)))

# ── Output guard: every output is new ─────────────────────────────────────
parent_stems <- c("2sls_dwnstrm_minevio_allcat_ivsum_binvio", "2sls_dwnstrm_minevio_mr_ivsum_binvio",
                  "2sls_dwnstrm_minevio_mcl_ivsum_binvio", "h2_snsv_d12", "h3_inf_formal_d12",
                  "6yr_huc02fe_inorg_ravalli_2005")
expected_out <- c(
  as.vector(outer(parent_stems, c("_k2_sd_mines", "_k2_sd_prod", "_k2_elas_mines", "_k2_elas_prod"), paste0)),
  "scaled_compare_sd_k2", "scaled_compare_elas_k2")
expected_paths <- c(file.path(ROOT, "output/reg", paste0(expected_out, ".tex")),
                    file.path(ROOT, "output/reg/scaled_compare_all_k2.csv"))
if (any(file.exists(expected_paths))) {
  stop("Output already exists: ", paste(basename(expected_paths[file.exists(expected_paths)]), collapse = ", "))
}

# ── 2a. Main panel ────────────────────────────────────────────────────────
main_dat <- build_k2_panel("main")
lone_states <- main_dat %>%
  dplyr::filter(!is.na(STATE_CODE)) %>%
  dplyr::group_by(STATE_CODE) %>%
  dplyr::summarise(n_util = dplyr::n_distinct(PWSID), .groups = "drop") %>%
  dplyr::filter(n_util == 1) %>%
  dplyr::pull(STATE_CODE)
main_dat <- main_dat %>% dplyr::filter(!is.na(STATE_CODE), !(STATE_CODE %in% lone_states))

FE_TWO      <- c("PWSID + year", "PWSID + STATE_CODE^year")
fe_state_yr <- "PWSID + STATE_CODE^year"
INSTR       <- "post95:sulfur_mean0"

OUT_VIO_ANY <- c(nitrates_bin = "Nitrates", arsenic_bin = "Arsenic", inorganic_chemicals_bin = "Inorganic chemicals")
OUT_VIO_MR  <- c(nitrates_MR_bin = "Nitrates", arsenic_MR_bin = "Arsenic", inorganic_chemicals_MR_bin = "Inorganic chemicals")
OUT_VIO_MCL <- c(nitrates_MCL_bin = "Nitrates", arsenic_MCL_bin = "Arsenic", inorganic_chemicals_MCL_bin = "Inorganic chemicals")
OUT_VISIT   <- c(any_snsv = "Sanitary", any_tech = "Technical assistance", any_enfvisit = "Enforcement",
                 any_smpl = "Sample collection", any_insp = "Inspection")
OUT_ENF     <- c(any_informal = "Informal", any_formal = "Formal", no_enf = "None")

tabs <- list(
  list(stem = "2sls_dwnstrm_minevio_allcat_ivsum_binvio", outcomes = OUT_VIO_ANY, fe = FE_TWO,
       super = "Any violation", panel = "Any violation", kind = "vio",
       topic = "inorganic chemical violations at utilities"),
  list(stem = "2sls_dwnstrm_minevio_mr_ivsum_binvio", outcomes = OUT_VIO_MR, fe = FE_TWO,
       super = "Monitoring and reporting (MR) violation", panel = "Monitoring and reporting violation",
       kind = "vio", topic = "inorganic chemical violations at utilities"),
  list(stem = "2sls_dwnstrm_minevio_mcl_ivsum_binvio", outcomes = OUT_VIO_MCL, fe = FE_TWO,
       super = "Maximum contaminant level (MCL) violation", panel = "Maximum contaminant level violation",
       kind = "vio", topic = "inorganic chemical violations at utilities"),
  list(stem = "h2_snsv_d12", outcomes = OUT_VISIT, fe = fe_state_yr, super = NULL,
       panel = "Regulator visits", kind = "visit", topic = "regulator visit probability by visit type"),
  list(stem = "h3_inf_formal_d12", outcomes = OUT_ENF, fe = FE_TWO, super = "Enforcement",
       panel = "Enforcement", kind = "enf", topic = "enforcement actions by type")
)
all_y <- unlist(lapply(tabs, function(tb) names(tb$outcomes)))

main_dat$mines     <- main_dat$num_coal_mines_linked_sum
main_dat$prod_tons <- replace(main_dat$production_linked_sum, is.na(main_dat$production_linked_sum), 0)
main_dat$prod      <- main_dat$prod_tons / 1e6
need <- c(all_y, "mines", "prod", "num_facilities", "sulfur_mean0", "post95", "STATE_CODE")
main_dat <- main_dat[complete.cases(main_dat[, need]), ]
# fixest drops utilities observed once (singleton utility fixed effect) in every parent
# column; drop them up front so the scaling moments use the exact estimation sample.
n_singleton <- sum(table(main_dat$PWSID) == 1)
main_dat <- main_dat[main_dat$PWSID %in% names(which(table(main_dat$PWSID) > 1)), ]
cat(sprintf("Dropped %d single-observation utilities (singleton utility FE)\n", n_singleton))
cat(sprintf("Main sample: %d obs, %d utilities\n", nrow(main_dat), dplyr::n_distinct(main_dat$PWSID)))
gate("Stable-sample N == 10641", nrow(main_dat) == 10641L)

# ── 2b. Transform helper ──────────────────────────────────────────────────
add_scaled <- function(dat, yvars, xvars) {
  for (v in c(yvars, xvars)) {
    dat[[paste0(v, "_z")]] <- (dat[[v]] - mean(dat[[v]])) / sd(dat[[v]])
    dat[[paste0(v, "_m")]] <- dat[[v]] / mean(dat[[v]])
  }
  for (v in xvars) dat[[paste0(v, "_l")]] <- log1p(dat[[v]])
  dat
}
main_dat <- add_scaled(main_dat, all_y, c("mines", "prod"))
# units sensitivity for the log variant: production in short tons / thousand ST / million ST (= prod_l)
main_dat$prod_l_tons <- log1p(main_dat$prod_tons)
main_dat$prod_l_kst  <- log1p(main_dat$prod_tons / 1e3)

k2_dict_sc <- c(k2_dict,
  mines_z = "Upstream coal mines (std.)", prod_z = "Upstream coal prod. (std.)",
  mines_m = "Upstream coal mines (rel. to mean)", prod_m = "Upstream coal prod. (rel. to mean)")
for (y in all_y) {
  k2_dict_sc[paste0(y, "_z")] <- k2_dict[[y]]
  k2_dict_sc[paste0(y, "_m")] <- k2_dict[[y]]
}

# ── model / test helpers ──────────────────────────────────────────────────
fit_one <- function(dat, y, x, fe, est) {
  f <- if (est == "ols") as.formula(paste0(y, " ~ ", x, " + num_facilities | ", fe))
       else as.formula(paste0(y, " ~ num_facilities | ", fe, " | ", x, " ~ ", INSTR))
  fixest::feols(f, data = dat, cluster = ~PWSID, warn = FALSE, notes = FALSE)
}
within_sd <- function(dat, v, fe) {
  sd(resid(fixest::feols(as.formula(paste0(v, " ~ 1 | ", fe)), data = dat, warn = FALSE, notes = FALSE)))
}
mom <- function(dat, v, fe) c(xbar = mean(dat[[v]]), sd = sd(dat[[v]]), wsd = within_sd(dat, v, fe))

# Stacked data: two copies of the sample, group g in {mines, prod}.
stack_two <- function(dat, xa, xb, ycols, idcols, z0 = NULL) {
  base <- dat[, c(idcols, "num_facilities", ycols)]
  mk <- function(g, x1, x2, first) {
    b <- base; b$g <- g; b$x1 <- x1; b$x2 <- x2
    b$nf1 <- if (first) b$num_facilities else 0
    b$nf2 <- if (first) 0 else b$num_facilities
    if (!is.null(z0)) { b$z1 <- if (first) z0 else 0; b$z2 <- if (first) 0 else z0 }
    b
  }
  rbind(mk("mines", xa, 0, TRUE), mk("prod", 0, xb, FALSE))
}
stk_fit <- function(st, y, fe_str, est) {
  fe_g <- paste(paste0(trimws(strsplit(fe_str, "\\+")[[1]]), "^g"), collapse = " + ")
  f <- if (est == "iv") as.formula(paste0(y, " ~ nf1 + nf2 | ", fe_g, " | x1 + x2 ~ z1 + z2"))
       else as.formula(paste0(y, " ~ x1 + x2 + nf1 + nf2 | ", fe_g))
  fixest::feols(f, data = st, cluster = ~PWSID, warn = FALSE, notes = FALSE)
}
# Equality p-value of the two stacked coefficients; also returns the coefficients for the gate.
stk_eval <- function(m) {
  nm <- names(coef(m))
  i1 <- grep("(^|_)x1$", nm); i2 <- grep("(^|_)x2$", nm)
  stopifnot(length(i1) == 1, length(i2) == 1)
  b <- coef(m); V <- vcov(m)
  se <- sqrt(V[i1, i1] + V[i2, i2] - 2 * V[i1, i2])
  tstat <- (b[i1] - b[i2]) / se
  list(p = unname(2 * stats::pt(-abs(tstat), df = fixest::degrees_freedom(m, type = "t"))),
       b1 = unname(b[i1]), b2 = unname(b[i2]))
}
stk_check <- function(m, bm, bp, tag) {
  r <- stk_eval(m)
  gate(paste("Stacked coefs == separate:", tag), near(c(r$b1, r$b2), c(bm, bp), 1e-6))
  r$p
}

mk_row <- function(table, panel, outcome, fe, estimator, scale, bm, bp, N, Fm = NA_real_, Fp = NA_real_,
                   mm = c(NA_real_, NA_real_, NA_real_), mp = c(NA_real_, NA_real_, NA_real_),
                   p_equal = NA_real_, panel_ab = NA_character_, prod_type = NA_character_) {
  same_sign <- sign(bm$est) == sign(bp$est)
  same_sig5 <- (bm$pval < 0.05) == (bp$pval < 0.05)
  data.frame(table = table, panel = panel, outcome = outcome, fe = fe, estimator = estimator,
             scale = scale, panel_ab = panel_ab, prod_type = prod_type,
             coef_mines = bm$est, se_mines = bm$se, p_mines = bm$pval,
             coef_prod = bp$est, se_prod = bp$se, p_prod = bp$pval,
             ratio = bm$est / bp$est, same_sign = same_sign, same_sig5 = same_sig5,
             p_equal = p_equal,
             close_flag = if (is.na(p_equal)) NA else (same_sign & same_sig5 & p_equal >= 0.05),
             N = N, F_mines = Fm, F_prod = Fp,
             xbar_mines = mm[1], sd_mines = mm[2], wsd_mines = mm[3],
             xbar_prod = mp[1], sd_prod = mp[2], wsd_prod = mp[3],
             stringsAsFactors = FALSE)
}
scale_term <- function(t, f) list(est = t$est * f, se = t$se * f, pval = t$pval)

# ── note sentences ────────────────────────────────────────────────────────
instr_sentence <- paste0(
  "The instrument interacts an indicator for the post-1995 period with the average ",
  "coal sulfur content of watersheds within two flow steps upstream of the utility's intake.")
sample_sentence <- paste0(
  "The sample is utilities with a coal mine within two flow steps upstream of their ",
  "intake and no coal mine colocated with their intake, in states with at least one ",
  "other such utility.")
outcome_sentence <- c(
  vio   = "The dependent variable equals 1 if the utility had a violation of that type during the year, 0 otherwise.",
  visit = "The dependent variable equals 1 if the utility received a regulator visit of that type during the year, 0 otherwise.",
  enf   = paste0("The dependent variable equals 1 if the utility had an enforcement action of that type ",
                 "during the year (\"None\" equals 1 if it had no enforcement action), 0 otherwise."))
scale_sentence <- function(sc, xp) {
  xdesc <- if (xp == "mines") "the number of active coal mines" else "annual coal production"
  geo   <- "in watersheds within two flow steps upstream of the utility's intake, summed across those watersheds"
  if (sc == "z") paste0(
    "The dependent variable and the endogenous regressor (", xdesc, " ", geo, ") are each converted to ",
    "standard deviation units (mean zero, standard deviation one) on the estimation sample, so coefficients ",
    "give the standard-deviation change in the outcome per one-standard-deviation change in ", xdesc, ".")
  else paste0(
    "The dependent variable and the endogenous regressor (", xdesc, " ", geo, ") are each divided by their ",
    "sample mean, so OLS and 2SLS coefficients are elasticities evaluated at the sample means.")
}
sc_tag   <- c(z = "sd", m = "elas")
sc_title <- c(z = "standard deviation units", m = "elasticities at the sample means")

# ── 2c. Scaled main tables (20 files) ─────────────────────────────────────
rows <- list()
add_row <- function(r) rows[[length(rows) + 1]] <<- r
stk_cache <- list()
ycols_all <- c(paste0(all_y, "_z"), paste0(all_y, "_m"))
z0_main   <- main_dat$post95 * main_dat$sulfur_mean0
ids_main  <- c("PWSID", "year", "STATE_CODE")
stk_main <- list(
  z = stack_two(main_dat, main_dat$mines_z, main_dat$prod_z, ycols_all, ids_main, z0_main),
  m = stack_two(main_dat, main_dat$mines_m, main_dat$prod_m, ycols_all, ids_main, z0_main),
  l = stack_two(main_dat, main_dat$mines_l, main_dat$prod_l, ycols_all, ids_main, z0_main)
)
f_flags <- character(0)

for (tb in tabs) {
  yv <- names(tb$outcomes); n_fe <- length(tb$fe)
  cat(sprintf("\n=== %s ===\n", tb$stem))
  rr <- list()
  for (sc in c("z", "m")) for (xp in c("mines", "prod")) {
    oc <- setNames(unname(tb$outcomes), paste0(yv, "_", sc))
    xdesc_title <- if (xp == "mines") "coal mines" else "upstream coal production"
    rr[[paste(sc, xp)]] <- render_panel_k2(
      dat = main_dat, outcomes = oc, fe_specs = tb$fe, dict = k2_dict_sc,
      coalvar = paste0(xp, "_", sc), instr_str = INSTR,
      title = paste0("Effect of ", xdesc_title, " on ", tb$topic, ", ", sc_title[[sc]]),
      label = paste0("tab:", tb$stem, "_k2_", sc_tag[[sc]], "_", xp),
      outfile = paste0(tb$stem, "_k2_", sc_tag[[sc]], "_", xp),
      depvar_sentence = paste(outcome_sentence[[tb$kind]], scale_sentence(sc, xp), instr_sentence, sample_sentence),
      superheader = tb$super, notes_present = NULL, digits = 3)
  }

  for (oi in seq_along(yv)) for (fi in seq_len(n_fe)) {
    j <- (oi - 1) * n_fe + fi; y <- yv[oi]; fe <- tb$fe[fi]
    tag <- paste0(y, " | ", fe)
    # moments
    mm <- mom(main_dat, "mines", fe); mp <- mom(main_dat, "prod", fe)
    ybar <- mean(main_dat[[y]]); sdy <- sd(main_dat[[y]])
    # level fits + F
    lv <- list()
    for (xp in c("mines", "prod")) for (est in c("ols", "iv")) lv[[paste(xp, est)]] <- fit_one(main_dat, y, xp, fe, est)
    for (m in lv) stopifnot(nobs(m) == nrow(main_dat))
    F_m <- f_clustered(main_dat, fe, endog = "mines"); F_p <- f_clustered(main_dat, fe, endog = "prod")
    gate(paste("F invariant to rescaling (z,m, mines & prod):", tag),
         near(c(rr[["z mines"]]$f_vals[j], rr[["m mines"]]$f_vals[j], rr[["z prod"]]$f_vals[j], rr[["m prod"]]$f_vals[j]),
              c(F_m, F_m, F_p, F_p), 0.01))
    if (F_m < 10 || F_p < 10) f_flags <- c(f_flags, sprintf("%s F_mines=%.2f F_prod=%.2f", tag, F_m, F_p))

    for (est in c("ols", "iv")) {
      est_lab <- if (est == "ols") "OLS" else "2SLS"
      lst <- paste0(est, "_list")
      raw_m <- get_term(lv[[paste("mines", est)]], "mines"); raw_p <- get_term(lv[[paste("prod", est)]], "prod")
      for (sc in c("z", "m")) {
        sm <- get_term(rr[[paste(sc, "mines")]][[lst]][[j]], paste0("mines_", sc))
        sp <- get_term(rr[[paste(sc, "prod")]][[lst]][[j]],  paste0("prod_", sc))
        fac_m <- if (sc == "z") mm[["sd"]] / sdy else mm[["xbar"]] / ybar
        fac_p <- if (sc == "z") mp[["sd"]] / sdy else mp[["xbar"]] / ybar
        gate(paste0("Identity ", sc, " ", est_lab, ": ", tag),
             near(c(sm$est, sp$est), c(raw_m$est * fac_m, raw_p$est * fac_p), 1e-8))
        stopifnot(nobs(rr[[paste(sc, "mines")]][[lst]][[j]]) == nrow(main_dat))
        st <- stk_main[[sc]]
        pe <- stk_check(stk_fit(st, paste0(y, "_", sc), fe, est), sm$est, sp$est, paste(sc, est_lab, tag))
        add_row(mk_row(tb$stem, tb$panel, y, fe, est_lab, sc, sm, sp, nrow(main_dat), F_m, F_p, mm, mp, pe))
        if (sc == "z") {
          # within-SD scaling: derived by identity (x rescaled by its SD after removing the FE)
          add_row(mk_row(tb$stem, tb$panel, y, fe, est_lab, "z_within",
                         scale_term(raw_m, mm[["wsd"]] / sdy), scale_term(raw_p, mp[["wsd"]] / sdy),
                         nrow(main_dat), F_m, F_p, mm, mp, NA_real_))
        }
        if (est == "iv" && fe == fe_state_yr && tb$stem == "2sls_dwnstrm_minevio_mr_ivsum_binvio" &&
            y == "nitrates_MR_bin" && sc == "z") {
          gate("Anchor: level 2SLS MR nitrates state x year, mines == 3.94", round(raw_m$est, 2) == 3.94)
          gate("Anchor: level 2SLS MR nitrates state x year, annual prod == 19.39", round(raw_p$est, 2) == 19.39)
        }
      }
      # log(1 + x) variant: y / ybar on log1p(x) -> coefficient is directly an elasticity
      ym <- paste0(y, "_m")
      lm_ <- fit_one(main_dat, ym, "mines_l", fe, est); lp_ <- fit_one(main_dat, ym, "prod_l", fe, est)
      tm <- get_term(lm_, "mines_l"); tp <- get_term(lp_, "prod_l")
      pe <- stk_check(stk_fit(stk_main$l, ym, fe, est), tm$est, tp$est, paste("log", est_lab, tag))
      Fl_m <- f_clustered(main_dat, fe, endog = "mines_l"); Fl_p <- f_clustered(main_dat, fe, endog = "prod_l")
      if (est == "iv" && (Fl_m < 10 || Fl_p < 10)) f_flags <- c(f_flags, sprintf("log %s F_mines=%.2f F_prod=%.2f", tag, Fl_m, Fl_p))
      add_row(mk_row(tb$stem, tb$panel, y, fe, est_lab, "log", tm, tp, nrow(main_dat), Fl_m, Fl_p,
                     mom(main_dat, "mines_l", fe), mom(main_dat, "prod_l", fe), pe))
      # units sensitivity of the production log coefficient (state x year only)
      if (fe == fe_state_yr) {
        unit_vars <- c(tons = "prod_l_tons", thousandST = "prod_l_kst", millionST = "prod_l")
        for (un in names(unit_vars)) {
          u <- unit_vars[[un]]
          up <- get_term(fit_one(main_dat, ym, u, fe, est), u)
          add_row(mk_row(tb$stem, tb$panel, y, fe, est_lab, paste0("log_units_", un),
                         tm, up, nrow(main_dat), Fl_m, f_clustered(main_dat, fe, endog = u),
                         mom(main_dat, "mines_l", fe), mom(main_dat, u, fe), NA_real_))
        }
      }
    }
  }
}
cat("\nFirst-stage F below 10 flagged:", if (length(f_flags)) paste0("\n  ", f_flags, collapse = "") else "none", "\n")

# ── 2e. 6yr scaled tables ─────────────────────────────────────────────────
si <- read_parquet(file.path(ROOT, "clean_data/cws_data/step_instruments.parquet"))
stopifnot(is.character(si$PWSID))
d6r <- read_parquet(file.path(ROOT, "clean_data/cws_6year_review_ravalli.parquet"))
stopifnot(is.character(d6r$PWSID), "STATE_CODE" %in% names(d6r))
d6r <- d6r %>% dplyr::filter(year >= 1985, PWSID != "WV3303401")
huc02_lookup <- read_parquet(file.path(ROOT, "clean_data/cws_data/pwsid_huc02.parquet"))
stopifnot(is.character(huc02_lookup$PWSID), is.character(huc02_lookup$huc02))
d6r <- d6r %>% dplyr::left_join(huc02_lookup %>% dplyr::select(PWSID, huc02), by = "PWSID")

CHEMS <- c("arsenic", "nitrate", "barium", "selenium")
nice_chem <- c(arsenic = "Arsenic", nitrate = "Nitrate", barium = "Barium", selenium = "Selenium")

# build_dose_sample(): generalized builder copied verbatim from run_k2_6yr_swap_tables.r
build_dose_sample <- function(sample_k, dose_k = sample_k,
                              dose_var = "production_linked_sum", cumulate = TRUE) {
  arm_k <- si %>% dplyr::filter(arm == "main", k == sample_k, n_mine_hucs_linked >= 1) %>%
    apply_a2() %>%
    dplyr::select(PWSID, year, dose = dplyr::all_of(dose_var))
  linked_pwsids <- unique(arm_k$PWSID)
  d <- d6r %>% dplyr::filter(PWSID %in% linked_pwsids, CHEMID_name %in% CHEMS)
  if (dose_k == sample_k) {
    dose_src <- arm_k
  } else {
    dose_src <- arm_k %>% dplyr::select(PWSID, year) %>%
      dplyr::left_join(
        si %>% dplyr::filter(arm == "main", k == dose_k) %>%
          dplyr::select(PWSID, year, dose = dplyr::all_of(dose_var)),
        by = c("PWSID", "year"))
  }
  out_var <- if (cumulate) "coal_prod_upstream_cumsum_10mst" else dose_var
  dose_panel <- dose_src %>%
    dplyr::distinct(PWSID, year, dose) %>%
    dplyr::arrange(PWSID, year) %>%
    dplyr::group_by(PWSID) %>%
    dplyr::mutate(dose = replace(dose, is.na(dose), 0),
                  dose = if (cumulate) cumsum(dose) / 1e7 else dose) %>%
    dplyr::ungroup()
  if (cumulate) {
    chk <- dose_panel %>% dplyr::group_by(PWSID) %>% dplyr::mutate(diff = dose - dplyr::lag(dose))
    stopifnot(all(chk$diff >= 0 | is.na(chk$diff)))
  }
  names(dose_panel)[names(dose_panel) == "dose"] <- out_var
  d <- d %>% dplyr::inner_join(dose_panel, by = c("PWSID", "year"))
  d <- d[!is.na(d$VALUE), ]
  d[d$year <= 2005, ]
}

mn_fr <- list(one = build_dose_sample(2, 1, "num_coal_mines_linked_sum", FALSE),
              two = build_dose_sample(2, 2, "num_coal_mines_linked_sum", FALSE))
ap_fr <- list(one = build_dose_sample(2, 1, cumulate = FALSE), two = build_dose_sample(2, 2, cumulate = FALSE))

key_cols  <- c("PWSID", "year", "CHEMID_name", "VALUE")
sort_keys <- function(df) { x <- df[order(df$PWSID, df$year, df$CHEMID_name), key_cols]; rownames(x) <- NULL; x }
for (df in c(mn_fr, ap_fr)) stopifnot(identical(sort_keys(df), sort_keys(ap_fr$two)))
gate("6yr: every regressor frame has the parent table's rows", TRUE)

join_keys <- c("PWSID", "year", "CHEMID_name")
six_base <- function(p) {
  b <- mn_fr[[p]]
  stopifnot(anyDuplicated(b[, join_keys]) == 0)
  b <- b %>%
    dplyr::left_join(ap_fr[[p]][, c(join_keys, "production_linked_sum")], by = join_keys)
  b$mines <- b$num_coal_mines_linked_sum
  b$ann   <- b$production_linked_sum / 1e6
  b
}
six <- list(one = six_base("one"), two = six_base("two"))
FE6 <- "PWSID + huc02^year"
panel_lab <- c(one = "A", two = "B")
ptype_lab <- c(ann = "annual")
six_models <- list()   # six_models[[scale]][[xp]][[panel]][[chem]] for annual production

for (p in names(six)) for (chem in CHEMS) {
  d0 <- six[[p]][six[[p]]$CHEMID_name == chem, ]
  d0 <- d0[complete.cases(d0[, c("VALUE", "mines", "ann", "num_facilities", "huc02")]), ]
  stopifnot(nrow(d0) >= 30, min(d0$VALUE) > 0)
  for (pt in "ann") {
    # estimation sample = observations the level model actually uses
    lvm <- fixest::feols(as.formula(paste0("VALUE ~ mines + num_facilities | ", FE6)), data = d0, cluster = ~PWSID, warn = FALSE, notes = FALSE)
    lvp <- fixest::feols(as.formula(paste0("VALUE ~ ", pt, " + num_facilities | ", FE6)), data = d0, cluster = ~PWSID, warn = FALSE, notes = FALSE)
    stopifnot(identical(fixest::obs(lvm), fixest::obs(lvp)))
    fr <- d0[fixest::obs(lvm), ]
    fr$prod <- fr[[pt]]
    fr <- add_scaled(fr, "VALUE", c("mines", "prod"))
    fr$VALUE_l <- log(fr$VALUE)
    tag <- paste("SYR2", chem, "panel", panel_lab[[p]], ptype_lab[[pt]])
    f6 <- function(y, x) fixest::feols(as.formula(paste0(y, " ~ ", x, " + num_facilities | ", FE6)),
                                       data = fr, cluster = ~PWSID, warn = FALSE, notes = FALSE)
    raw_m <- f6("VALUE", "mines"); raw_p <- f6("VALUE", "prod")
    gate(paste("nobs == frame rows:", tag), nobs(raw_m) == nrow(fr) && nobs(raw_p) == nrow(fr))
    rm_ <- get_term(raw_m, "mines"); rp_ <- get_term(raw_p, "prod")
    if (pt == "ann" && chem == "arsenic") {
      want <- if (p == "one") 0.0032 else 0.0004
      gate(paste("Anchor: level arsenic annual production, panel", panel_lab[[p]], "==", want), round(rp_$est, 4) == want)
    }
    mmx <- mom(fr, "mines", FE6); mpx <- mom(fr, "prod", FE6)
    ybar <- mean(fr$VALUE); sdy <- sd(fr$VALUE)
    st <- stack_two(fr, fr$mines_z, fr$prod_z, c("VALUE_z", "VALUE_m", "VALUE_l"), c("PWSID", "year", "huc02"))
    stm <- stack_two(fr, fr$mines_m, fr$prod_m, c("VALUE_z", "VALUE_m", "VALUE_l"), c("PWSID", "year", "huc02"))
    stl <- stack_two(fr, fr$mines_l, fr$prod_l, c("VALUE_z", "VALUE_m", "VALUE_l"), c("PWSID", "year", "huc02"))
    stk_by <- list(z = st, m = stm)
    for (sc in c("z", "m")) {
      fm <- f6(paste0("VALUE_", sc), paste0("mines_", sc)); fp <- f6(paste0("VALUE_", sc), paste0("prod_", sc))
      gate(paste("nobs == frame rows:", sc, tag), nobs(fm) == nrow(fr) && nobs(fp) == nrow(fr))
      sm <- get_term(fm, paste0("mines_", sc)); sp <- get_term(fp, paste0("prod_", sc))
      fac_m <- if (sc == "z") mmx[["sd"]] / sdy else mmx[["xbar"]] / ybar
      fac_p <- if (sc == "z") mpx[["sd"]] / sdy else mpx[["xbar"]] / ybar
      gate(paste("Identity", sc, "OLS:", tag), near(c(sm$est, sp$est), c(rm_$est * fac_m, rp_$est * fac_p), 1e-8))
      pe <- stk_check(stk_fit(stk_by[[sc]], paste0("VALUE_", sc), FE6, "ols"), sm$est, sp$est, paste(sc, tag))
      add_row(mk_row("6yr_huc02fe_inorg_ravalli_2005", "SYR2 concentrations", chem, FE6, "OLS", sc, sm, sp,
                     nrow(fr), mm = mmx, mp = mpx, p_equal = pe, panel_ab = panel_lab[[p]], prod_type = ptype_lab[[pt]]))
      if (sc == "z") {
        add_row(mk_row("6yr_huc02fe_inorg_ravalli_2005", "SYR2 concentrations", chem, FE6, "OLS", "z_within",
                       scale_term(rm_, mmx[["wsd"]] / sdy), scale_term(rp_, mpx[["wsd"]] / sdy),
                       nrow(fr), mm = mmx, mp = mpx, panel_ab = panel_lab[[p]], prod_type = ptype_lab[[pt]]))
      }
      if (pt == "ann") {
        six_models[[sc]][["mines"]][[p]][[chem]] <- fm
        six_models[[sc]][["prod"]][[p]][[chem]]  <- fp
      }
    }
    lgm <- f6("VALUE_l", "mines_l"); lgp <- f6("VALUE_l", "prod_l")
    tm <- get_term(lgm, "mines_l"); tp <- get_term(lgp, "prod_l")
    pe <- stk_check(stk_fit(stl, "VALUE_l", FE6, "ols"), tm$est, tp$est, paste("log", tag))
    add_row(mk_row("6yr_huc02fe_inorg_ravalli_2005", "SYR2 concentrations", chem, FE6, "OLS", "log", tm, tp,
                   nrow(fr), mm = mom(fr, "mines_l", FE6), mp = mom(fr, "prod_l", FE6), p_equal = pe,
                   panel_ab = panel_lab[[p]], prod_type = ptype_lab[[pt]]))
  }
}

# Two-panel table assembly (helpers verbatim from run_k2_6yr_swap_tables.r)
extract_adjustbox <- function(tex_lines) {
  x <- paste(tex_lines, collapse = "\n")
  start_pos <- regexpr("\\\\begin\\{adjustbox\\}", x)
  end_pos   <- regexpr("\\\\end\\{adjustbox\\}", x)
  end_full  <- end_pos + attr(end_pos, "match.length") - 1
  substr(x, start_pos, end_full)
}
insert_panel_title <- function(tex_str, n_col, panel_label) {
  lines   <- strsplit(tex_str, "\n")[[1]]
  mid_idx <- which(trimws(lines) == "\\midrule")[1]
  title_line <- paste0("      \\multicolumn{", n_col + 1, "}{l}{\\textbf{", panel_label, "}} \\\\")
  c(lines[seq_len(mid_idx)], title_line, lines[(mid_idx + 1):length(lines)])
}
panel_tabular <- function(models_grp) {
  raw <- etable(models_grp, headers = list(":_:" = unname(nice_chem[CHEMS])), depvar = FALSE,
                fitstat = ~n, style.tex = style.tex("aer", adjustbox = TRUE), tex = TRUE,
                digits = "r3", drop = "Number of intake facilities", drop.section = "fixef", dict = k2_dict_sc)
  extract_adjustbox(raw)
}
strip_cmidrule <- function(tex_str) gsub(" *\\\\cmidrule\\(lr\\)\\{[0-9]+-[0-9]+\\}", "", tex_str)
drop_line <- function(tex_str, pattern) {
  lines <- strsplit(tex_str, "\n", fixed = TRUE)[[1]]
  paste(lines[!grepl(pattern, lines, fixed = TRUE)], collapse = "\n")
}
drop_colnum_row <- function(tex_str) {
  lines <- strsplit(tex_str, "\n", fixed = TRUE)[[1]]
  paste(lines[!(grepl("\\(1\\)", lines) & grepl("\\(4\\)", lines))], collapse = "\n")
}
build_panel_table <- function(body, title, label, notes, out_path) {
  lines <- c("\\begin{table}[htbp]", "   ", paste0("   \\caption{\\label{", label, "} ", title, "}"),
             "   \\bigskip", "   ", "   \\centering", "   ", body, "   ",
             "   {\\tiny\\linespread{1}\\selectfont \\par \\raggedright ", paste0("   ", notes, "}"),
             "   ", "\\end{table}", "", "")
  writeLines(lines, out_path)
}
write_scaled_6yr <- function(models_val, stem, title, scaling_sentence) {
  panel_a_tex <- strip_cmidrule(panel_tabular(models_val[1:4]))
  panel_a_tex <- drop_line(panel_a_tex, "Observations")
  panel_a_lines <- insert_panel_title(panel_a_tex, 4, "Panel A: Within one HUC12 upstream")
  panel_b_tex <- strip_cmidrule(panel_tabular(models_val[5:8]))
  panel_b_tex <- drop_line(panel_b_tex, "Arsenic & Nitrate & Barium & Selenium")
  panel_b_tex <- drop_colnum_row(panel_b_tex)
  panel_b_lines <- insert_panel_title(panel_b_tex, 4, "Panel B: Within two HUC12 upstream")
  top_a_idx <- which(trimws(panel_a_lines) == "\\bottomrule")[1] - 1
  mid_b_idx <- which(trimws(panel_b_lines) == "\\midrule")[1]
  merged <- c(panel_a_lines[seq_len(top_a_idx)], panel_b_lines[mid_b_idx:length(panel_b_lines)])
  note_reg <- paste0(
    "\\textit{Notes:} Within each chemical, the column shows mean measured concentration ",
    "from the EPA 6-Year Review. ", scaling_sentence, " ",
    "Sample: utilities with a coal mine within two flow steps upstream of their intake ",
    "and no coal mine colocated with their intake. Standard errors clustered at the ",
    "utility level. All specifications include utility and HUC02 $\\times$ year fixed ",
    "effects. *** p$<$0.01, ** p$<$0.05, * p$<$0.1.")
  out_reg <- file.path(ROOT, "output/reg", paste0(stem, ".tex"))
  build_panel_table(merged, title, paste0("tab:", stem), note_reg, out_reg)
  cat("Written:", out_reg, "\n")
}
for (sc in c("z", "m")) for (xp in c("mines", "prod")) {
  mods <- unlist(lapply(c("one", "two"), function(p) six_models[[sc]][[xp]][[p]][CHEMS]), recursive = FALSE)
  stopifnot(length(mods) == 8)
  xdesc <- if (xp == "mines") "the number of coal mines in the year" else "coal production during the year (in millions of short tons)"
  geo <- "in watersheds within one flow step upstream of the utility's intake (Panel A) or within two flow steps upstream (Panel B)"
  scaling_sentence <- if (sc == "z") paste0(
    "Mean concentration and the explanatory variable (", xdesc, " ", geo, ") are each converted to standard ",
    "deviation units within each chemical and panel, so coefficients give the standard-deviation change in ",
    "concentration per one-standard-deviation change in the explanatory variable.")
  else paste0(
    "Mean concentration and the explanatory variable (", xdesc, " ", geo, ") are each divided by their ",
    "sample mean within each chemical and panel, so coefficients are elasticities evaluated at the sample means.")
  write_scaled_6yr(mods, paste0("6yr_huc02fe_inorg_ravalli_2005_k2_", sc_tag[[sc]], "_", xp),
                   paste0("Effect of ", if (xp == "mines") "the number of upstream coal mines" else "upstream coal production",
                          " on inorganic chemicals by upstream distance, ", sc_title[[sc]], ", SYR2 1998--2005"),
                   scaling_sentence)
}

# ── Step 5: CSV ───────────────────────────────────────────────────────────
res <- do.call(rbind, rows)
rownames(res) <- NULL
csv_path <- file.path(ROOT, "output/reg/scaled_compare_all_k2.csv")
write.csv(res, csv_path, row.names = FALSE)
cat(sprintf("CSV written: %d rows x %d cols\n", nrow(res), ncol(res)))

# ── Step 5: comparison tables ─────────────────────────────────────────────
panel_order <- c("Any violation", "Monitoring and reporting violation", "Maximum contaminant level violation",
                 "Regulator visits", "Enforcement", "SYR2 concentrations")
label_of <- function(panel, outcome) {
  if (panel == "SYR2 concentrations") return(nice_chem[[outcome]])
  tb <- tabs[[which(vapply(tabs, function(t) t$panel == panel, logical(1)))]]
  tb$outcomes[[outcome]]
}
sel_rows <- function(df) {
  main <- df[df$table != "6yr_huc02fe_inorg_ravalli_2005" & df$estimator == "2SLS" & df$fe == fe_state_yr, ]
  six_ <- df[df$table == "6yr_huc02fe_inorg_ravalli_2005" & df$panel_ab == "B" & df$prod_type == "annual", ]
  rbind(main, six_)
}
sel <- sel_rows(res)
get_cell <- function(panel, outcome, scale) {
  r <- sel[sel$panel == panel & sel$outcome == outcome & sel$scale == scale, ]
  stopifnot(nrow(r) == 1)
  r
}
num_cell <- function(x, w, digits = 3) {
  if (is.na(x)) return("--")
  sg  <- if (x < 0) "-" else "\\phantom{-}"
  s   <- sprintf(paste0("%.", digits, "f"), abs(x))
  iw  <- nchar(sub("\\..*$", "", s))
  paste0(sg, if (iw < w) strrep("\\phantom{0}", w - iw) else "", s)
}
int_w <- function(x) { x <- x[!is.na(x)]; max(nchar(sub("\\..*$", "", sprintf("%.3f", abs(x))))) }

write_compare <- function(cols, headers, outfile, title, label, note) {
  # cols: list of list(scale, kind = "coef_m"/"coef_p"/"ratio"/"p_equal")
  n_c <- length(cols)
  getv <- function(r, kind) switch(kind, coef_m = r$coef_mines, coef_p = r$coef_prod, ratio = r$ratio, p_equal = r$p_equal)
  # column widths from every displayed value
  wdt <- vapply(cols, function(cs) {
    vals <- unlist(lapply(seq_len(nrow(sel)), function(i) {
      r <- sel[i, ]
      cell <- sel[sel$panel == r$panel & sel$outcome == r$outcome & sel$scale == cs$scale, ]
      if (nrow(cell) != 1) return(NULL)
      if (cs$kind == "coef_m") c(cell$coef_mines, cell$se_mines) else if (cs$kind == "coef_p") c(cell$coef_prod, cell$se_prod) else getv(cell, cs$kind)
    }))
    int_w(vals)
  }, numeric(1))
  lines <- c(
    paste0("\\begin{tabular}{l", strrep("r", n_c), "}"), "\\toprule",
    paste0(" & ", paste0("\\multicolumn{1}{c}{", headers[[1]], "}", collapse = " & "), " \\\\"),
    paste0(" & ", paste0("\\multicolumn{1}{c}{", headers[[2]], "}", collapse = " & "), " \\\\"),
    "\\hline")
  for (pn in panel_order) {
    pr <- sel[sel$panel == pn & sel$scale == cols[[1]]$scale, ]
    if (!nrow(pr)) next
    lines <- c(lines, paste0("\\multicolumn{", n_c + 1, "}{l}{\\textbf{", pn, "}} \\\\"))
    for (oc in pr$outcome) {
      cells <- lapply(seq_len(n_c), function(k) {
        cs <- cols[[k]]; r <- get_cell(pn, oc, cs$scale)
        if (cs$kind %in% c("coef_m", "coef_p")) {
          f <- if (cs$kind == "coef_m") fmt_num_wide(r$coef_mines, r$se_mines, r$p_mines, wdt[k], 3)
               else fmt_num_wide(r$coef_prod, r$se_prod, r$p_prod, wdt[k], 3)
          list(coef = f$coef, se = f$se)
        } else {
          list(coef = paste0("\\phantom{(}", num_cell(getv(r, cs$kind), wdt[k]), "\\phantom{$^{***}$}"), se = "")
        }
      })
      lines <- c(lines,
                 paste0(label_of(pn, oc), " & ", paste(vapply(cells, `[[`, "", "coef"), collapse = " & "), " \\\\"),
                 paste0(" & ", paste(vapply(cells, `[[`, "", "se"), collapse = " & "), " \\\\"))
    }
  }
  lines <- c(lines, "\\bottomrule", "\\end{tabular}")
  out <- c("\\begin{table}[htbp]", "\\raggedright", "\\begin{minipage}{\\linewidth}",
           paste0("\\caption{\\label{", label, "} ", title, "}"), "\\end{minipage}", "\\small",
           "{\\setlength{\\tabcolsep}{4pt}%", "\\begin{adjustbox}{max width=\\linewidth}", lines, "\\end{adjustbox}", "}",
           "\\begin{minipage}{\\linewidth}", "\\vspace{4pt}", "\\footnotesize", "\\raggedright", note,
           "\\end{minipage}", "\\end{table}")
  writeLines(out, file.path(ROOT, "output/reg", paste0(outfile, ".tex")))
  cat("Written:", outfile, ".tex\n")
}

note_common <- paste0(
  "Each row reports the coefficient on the number of active coal mines and the coefficient on coal production ",
  "from separate regressions that differ only in the endogenous regressor. The first five panels report ",
  "two-stage least squares estimates with utility and state $\\times$ year fixed effects, where the regressor is ",
  "summed over watersheds within two flow steps upstream of the utility's intake and instrumented with the ",
  "interaction of a post-1995 indicator and average upstream coal sulfur content; production is annual. ",
  "The last panel reports ordinary least squares estimates of mean measured concentration within two flow steps ",
  "upstream with utility and HUC02 $\\times$ year fixed effects, where production is annual. ",
  "Standard errors clustered at the utility level in parentheses. ")
stars <- "*** p$<$0.01, ** p$<$0.05, * p$<$0.1."

write_compare(
  cols = list(list(scale = "z", kind = "coef_m"), list(scale = "z", kind = "coef_p"),
              list(scale = "z", kind = "ratio"), list(scale = "z_within", kind = "ratio"),
              list(scale = "z", kind = "p_equal")),
  headers = list(c("Mines", "Production", "Ratio", "Ratio", "Equality"),
                 c("(std.)", "(std.)", "", "(within-SD)", "p-value")),
  outfile = "scaled_compare_sd_k2",
  title = "Upstream coal mines versus upstream coal production, standard deviation units",
  label = "tab:scaled_compare_sd_k2",
  note = paste0("\\textit{Notes:} ", note_common,
                "The dependent variable and each regressor are converted to standard deviation units, so coefficients ",
                "give the standard-deviation change in the outcome per one-standard-deviation change in the regressor. ",
                "Ratio is the mines coefficient divided by the production coefficient; the within-SD ratio instead ",
                "scales each regressor by its standard deviation after removing the fixed effects. The equality ",
                "p-value tests that the two standardized coefficients are equal, using a joint regression clustered ",
                "at the utility level. ", stars))

write_compare(
  cols = list(list(scale = "m", kind = "coef_m"), list(scale = "m", kind = "coef_p"),
              list(scale = "m", kind = "ratio"), list(scale = "m", kind = "p_equal"),
              list(scale = "log", kind = "coef_m"), list(scale = "log", kind = "coef_p")),
  headers = list(c("Mines", "Production", "Ratio", "Equality", "Mines", "Production"),
                 c("(at means)", "(at means)", "", "p-value", "(log)", "(log)")),
  outfile = "scaled_compare_elas_k2",
  title = "Upstream coal mines versus upstream coal production, elasticities",
  label = "tab:scaled_compare_elas_k2",
  note = paste0("\\textit{Notes:} ", note_common,
                "The first two columns divide the dependent variable and each regressor by its sample mean, so ",
                "coefficients are elasticities evaluated at the sample means. The last two columns regress the ",
                "dependent variable divided by its sample mean on the natural logarithm of one plus the regressor, ",
                "with production measured in millions of short tons. Ratio is the mines elasticity divided by the ",
                "production elasticity. The equality p-value tests that the two elasticities at the means are equal, ",
                "using a joint regression clustered at the utility level. ", stars))

# ── Summary to stdout (for the report) ────────────────────────────────────
cat("\n=== Comparison rows (2SLS state x year; 6yr OLS panel B annual) ===\n")
for (sc in c("z", "z_within", "m", "log")) {
  s <- sel[sel$scale == sc, c("panel", "outcome", "coef_mines", "coef_prod", "ratio", "p_equal", "close_flag")]
  cat(sprintf("\n-- scale %s --\n", sc)); print(s, digits = 3, row.names = FALSE)
  if (sc != "z_within") cat(sprintf("close: %d of %d\n", sum(s$close_flag, na.rm = TRUE), nrow(s)))
}
cat("\n=== Log units sensitivity (2SLS, state x year): prod elasticity by units ===\n")
u <- res[grepl("^log_units_", res$scale) & res$estimator == "2SLS", c("table", "outcome", "scale", "coef_mines", "coef_prod")]
print(u, digits = 3, row.names = FALSE)
cat("\n=== run_k2_scaled_comparison.r DONE ===\n")
