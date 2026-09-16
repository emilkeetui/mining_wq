# ============================================================
# Script: compare_k2_intake_purity.r
# Purpose: Compare the k2 two-step-linkage main-spec results (first stage,
#          MR, visits, enforcement, SYR2) across three nested utility
#          samples -- status quo (SQ, the published k2 main arm),
#          no-upstream (A1), and downstream-only (A2) -- to test whether
#          utilities with "impure" intake portfolios drive the k2 results.
#          Terminal comparison report + one tidy parquet. No .tex output,
#          no edits to existing scripts.
# Inputs:
#   clean_data/cws_data/k2_intake_purity.parquet
#   clean_data/cws_data/step_instruments.parquet (via k2_common.r)
#   clean_data/cws_data/cws_covariates_steps.parquet (via k2_common.r)
#   clean_data/cws_data/sdwa_vio_agg_steps.parquet (via k2_common.r)
#   clean_data/cws_data/sdwa_visit_agg_k2.parquet (via k2_common.r)
#   clean_data/cws_data/sdwa_enf_agg_k2.parquet (via k2_common.r)
#   clean_data/cws_6year_review_ravalli.parquet
#   clean_data/cws_data/pwsid_huc02.parquet
#   output/reg/fs_dwnstrm_minevio_ivsum.tex (reference only)
#   output/reg/2sls_dwnstrm_minevio_mr_ivsum_binvio.tex (reference only)
#   output/reg/h2_snsv_d12.tex (reference only)
#   output/reg/h3_inf_formal_d12.tex (reference only)
#   output/reg/6yr_huc02fe_inorg_ravalli_2005.tex (reference only)
# Outputs:
#   clean_data/cws_data/k2_intake_purity_compare.parquet
# Author: EK  Date: 2026-09-15
# ============================================================

source("Z:/ek559/mining_wq/code/coal_mining_water_quality/k2_common.r")

purity <- read_parquet(file.path(ROOT, "clean_data/cws_data/k2_intake_purity.parquet"))
str(purity)
stopifnot(is.character(purity$PWSID))

ids_sq <- purity$PWSID[purity$in_sq]
ids_a1 <- purity$PWSID[purity$in_a1]
ids_a2 <- purity$PWSID[purity$in_a2]
cat(sprintf("\nSample sizes: SQ=%d  A1=%d  A2=%d\n", length(ids_sq), length(ids_a1), length(ids_a2)))
stopifnot(all(ids_a2 %in% ids_a1), all(ids_a1 %in% ids_sq))
cat("Nesting check PASSED: A2 subset of A1 subset of SQ.\n")

main_dat <- build_k2_panel("main", a2_only = FALSE)
stopifnot(setequal(ids_sq, unique(main_dat$PWSID)))

samples <- list(status_quo = ids_sq, a1_no_upstream = ids_a1, a2_downstream_only = ids_a2)

FE_TWO      <- c("PWSID + year", "PWSID + year + STATE_CODE^year")
fe_state_yr <- "PWSID + year + STATE_CODE^year"
COALVAR <- "num_coal_mines_linked_sum"
INSTR   <- "post95:sulfur_mean0"

# ── SYR2 setup ────────────────────────────────────────────────────────────
si <- read_parquet(file.path(ROOT, "clean_data/cws_data/step_instruments.parquet"))
stopifnot(is.character(si$PWSID))
d6r <- read_parquet(file.path(ROOT, "clean_data/cws_6year_review_ravalli.parquet"))
stopifnot(is.character(d6r$PWSID), "STATE_CODE" %in% names(d6r))
d6r <- d6r %>% dplyr::filter(year >= 1985, PWSID != "WV3303401")
huc02_map <- read_parquet(file.path(ROOT, "clean_data/cws_data/pwsid_huc02.parquet")) %>%
  dplyr::select(PWSID, huc02)
stopifnot(is.character(huc02_map$PWSID))

CHEMS <- c("arsenic", "nitrate", "barium", "selenium")

# build_dose_sample(): k-step upstream cumulative dose, ported from
# run_k2_6yr_tables.r:47-74, with an `ids` argument added (plan Step 2) that
# filters arm_k to the sample's PWSIDs before cumulating.
build_dose_sample <- function(kk, ids) {
  arm_k <- si %>% dplyr::filter(arm == "main", k == kk, n_mine_hucs_linked >= 1, PWSID %in% ids) %>%
    dplyr::select(PWSID, year, production_linked_sum)

  linked_pwsids <- unique(arm_k$PWSID)
  d <- d6r %>% dplyr::filter(PWSID %in% linked_pwsids, CHEMID_name %in% CHEMS)

  cum_panel <- arm_k %>%
    dplyr::distinct(PWSID, year, production_linked_sum) %>%
    dplyr::arrange(PWSID, year) %>%
    dplyr::group_by(PWSID) %>%
    dplyr::mutate(coal_prod_upstream_cumsum =
             cumsum(replace(production_linked_sum, is.na(production_linked_sum), 0))) %>%
    dplyr::ungroup() %>%
    dplyr::select(PWSID, year, coal_prod_upstream_cumsum)

  d <- d %>% dplyr::inner_join(cum_panel, by = c("PWSID", "year"))

  chk <- d %>% dplyr::distinct(PWSID, year, coal_prod_upstream_cumsum) %>%
    dplyr::arrange(PWSID, year) %>% dplyr::group_by(PWSID) %>%
    dplyr::mutate(diff = coal_prod_upstream_cumsum - dplyr::lag(coal_prod_upstream_cumsum))
  stopifnot(all(chk$diff >= 0 | is.na(chk$diff)))

  d$coal_prod_upstream_cumsum_10mst <- d$coal_prod_upstream_cumsum / 1e7
  d <- d[!is.na(d$VALUE), ]
  d <- d[d$year <= 2005, ]
  d
}

# ── Generic safe-fit helper ───────────────────────────────────────────────
fit_safe <- function(fml, dat) {
  tryCatch(fixest::feols(fml, data = dat, cluster = ~PWSID, warn = FALSE, notes = FALSE),
           error = function(e) NULL)
}

n_cws_of <- function(m, dat_y) {
  tryCatch({
    fe <- fixest::fixef(m)$PWSID
    if (is.null(fe)) dplyr::n_distinct(dat_y$PWSID) else length(fe)
  }, error = function(e) dplyr::n_distinct(dat_y$PWSID))
}

make_row <- function(family, outcome, model, fe, sample, term_info, n_obs, n_cws, f_val = NA_real_) {
  data.frame(family = family, outcome = outcome, model = model, fe = fe, sample = sample,
             coef = term_info$est, se = term_info$se, pval = term_info$pval,
             n_obs = n_obs, n_cws = n_cws, f_clustered = f_val, stringsAsFactors = FALSE)
}

results <- list()
n_fail <- 0
add_result <- function(row) results[[length(results) + 1]] <<- row

for (samp_name in names(samples)) {
  ids   <- samples[[samp_name]]
  dat_s <- main_dat[main_dat$PWSID %in% ids, ]
  cat(sprintf("\n--- Sample: %s (%d utilities, %d utility-years) ---\n",
              samp_name, length(ids), nrow(dat_s)))

  # ── First stage ──────────────────────────────────────────────────────
  for (fe in FE_TWO) {
    fml <- as.formula(paste0(COALVAR, " ~ ", INSTR, " + num_facilities | ", fe))
    m <- fit_safe(fml, dat_s)
    if (is.null(m)) {
      n_fail <- n_fail + 1
      add_result(make_row("first_stage", COALVAR, "FS", fe, samp_name,
                           list(est = NA_real_, se = NA_real_, pval = NA_real_), NA_integer_, NA_integer_, NA_real_))
    } else {
      ti <- get_term(m, INSTR)
      fval <- f_clustered(dat_s, fe)
      add_result(make_row("first_stage", COALVAR, "FS", fe, samp_name, ti, nobs(m), n_cws_of(m, dat_s), fval))
    }
  }

  # ── Generic OLS/RF/IV family runner ─────────────────────────────────
  run_ivfamily <- function(family, outcomes, fe_specs) {
    for (oc in outcomes) {
      dat_y <- dat_s[!is.na(dat_s[[oc]]), ]
      for (fe in fe_specs) {
        f_ols <- as.formula(paste0(oc, " ~ ", COALVAR, " + num_facilities | ", fe))
        f_rf  <- as.formula(paste0(oc, " ~ ", INSTR, " + num_facilities | ", fe))
        f_iv  <- as.formula(paste0(oc, " ~ num_facilities | ", fe, " | ", COALVAR, " ~ ", INSTR))
        m_ols <- fit_safe(f_ols, dat_y)
        m_rf  <- fit_safe(f_rf,  dat_y)
        m_iv  <- fit_safe(f_iv,  dat_y)
        fval  <- if (!is.null(m_iv)) f_clustered(dat_y, fe) else NA_real_
        model_specs <- list(OLS = list(m = m_ols, term = COALVAR),
                             RF  = list(m = m_rf,  term = INSTR),
                             IV  = list(m = m_iv,  term = COALVAR))
        for (mod_name in names(model_specs)) {
          m <- model_specs[[mod_name]]$m
          if (is.null(m)) {
            n_fail <- n_fail + 1
            add_result(make_row(family, oc, mod_name, fe, samp_name,
                                 list(est = NA_real_, se = NA_real_, pval = NA_real_), NA_integer_, NA_integer_, NA_real_))
          } else {
            ti <- get_term(m, model_specs[[mod_name]]$term)
            add_result(make_row(family, oc, mod_name, fe, samp_name, ti, nobs(m), n_cws_of(m, dat_y),
                                 if (mod_name == "IV") fval else NA_real_))
          }
        }
      }
    }
  }

  run_ivfamily("MR", c("nitrates_MR_bin", "arsenic_MR_bin", "inorganic_chemicals_MR_bin"), FE_TWO)
  run_ivfamily("visits", c("any_snsv", "any_tech", "any_enfvisit", "any_smpl", "any_insp"), fe_state_yr)
  run_ivfamily("enforcement", c("any_informal", "any_formal", "no_enf"), fe_state_yr)

  # ── SYR2 ─────────────────────────────────────────────────────────────
  dose_s <- build_dose_sample(2, ids)
  cat(sprintf("  SYR2 dose sample: %d rows, %d utilities\n", nrow(dose_s), dplyr::n_distinct(dose_s$PWSID)))
  for (chem in CHEMS) {
    d_chem <- dose_s[dose_s$CHEMID_name == chem, ]
    fe_variants <- list(
      state_year = list(fml = VALUE ~ coal_prod_upstream_cumsum_10mst + num_facilities | PWSID + STATE_CODE^year,
                         dat = d_chem),
      huc02_year = list(fml = VALUE ~ coal_prod_upstream_cumsum_10mst + num_facilities | PWSID + huc02^year,
                         dat = dplyr::left_join(d_chem, huc02_map, by = "PWSID"))
    )
    for (fe_label in names(fe_variants)) {
      dat_fe <- fe_variants[[fe_label]]$dat
      if (nrow(dat_fe) < 30) {
        add_result(make_row("SYR2", chem, "OLS", fe_label, samp_name,
                             list(est = NA_real_, se = NA_real_, pval = NA_real_), nrow(dat_fe), NA_integer_, NA_real_))
        next
      }
      m <- fit_safe(fe_variants[[fe_label]]$fml, dat_fe)
      if (is.null(m)) {
        n_fail <- n_fail + 1
        add_result(make_row("SYR2", chem, "OLS", fe_label, samp_name,
                             list(est = NA_real_, se = NA_real_, pval = NA_real_), nrow(dat_fe), NA_integer_, NA_real_))
      } else {
        ti <- get_term(m, "coal_prod_upstream_cumsum_10mst")
        add_result(make_row("SYR2", chem, "OLS", fe_label, samp_name, ti, nobs(m), n_cws_of(m, dat_fe), NA_real_))
      }
    }
  }
}

cat(sprintf("\nTotal feols failures (NA rows): %d\n", n_fail))
compare_df <- do.call(rbind, results)
rownames(compare_df) <- NULL

# ── Gates on status quo ────────────────────────────────────────────────
get_cell <- function(family, outcome, model, fe, sample = "status_quo") {
  r <- compare_df[compare_df$family == family & compare_df$outcome == outcome &
                     compare_df$model == model & compare_df$fe == fe & compare_df$sample == sample, ]
  stopifnot(nrow(r) == 1)
  r
}

fs_sq <- get_cell("first_stage", COALVAR, "FS", fe_state_yr)
cat(sprintf("\nGate check -- first-stage F (SQ, state x year FE): %.2f [want 50.01]\n", fs_sq$f_clustered))
stopifnot(abs(fs_sq$f_clustered - 50.01) < 0.01)

mr_gates <- list(
  nitrates_MR_bin             = c(est = 3.28, se = 1.73),
  arsenic_MR_bin              = c(est = 3.11, se = 1.52),
  inorganic_chemicals_MR_bin  = c(est = 2.00, se = 1.60)
)
for (oc in names(mr_gates)) {
  r <- get_cell("MR", oc, "IV", fe_state_yr)
  cat(sprintf("Gate check -- MR IV %s (SQ, state x year FE): %.2f (%.2f) [want %.2f (%.2f)]\n",
              oc, r$coef, r$se, mr_gates[[oc]]["est"], mr_gates[[oc]]["se"]))
  stopifnot(abs(round(r$coef, 2) - mr_gates[[oc]]["est"]) < 0.01,
            abs(round(r$se,   2) - mr_gates[[oc]]["se"])  < 0.01)
}

syr2_gates <- list(
  arsenic  = c(est = 0.0001, se = 0.0001),
  nitrate  = c(est = 0.1037, se = 0.0281),
  barium   = c(est = 0.0130, se = 0.0116),
  selenium = c(est = 0.0004, se = 0.0002)
)
for (chem in names(syr2_gates)) {
  r <- get_cell("SYR2", chem, "OLS", "state_year")
  cat(sprintf("Gate check -- SYR2 %s (SQ, state x year FE): %.4f (%.4f) [want %.4f (%.4f)]\n",
              chem, r$coef, r$se, syr2_gates[[chem]]["est"], syr2_gates[[chem]]["se"]))
  stopifnot(abs(round(r$coef, 4) - syr2_gates[[chem]]["est"]) < 0.0001,
            abs(round(r$se,   4) - syr2_gates[[chem]]["se"])  < 0.0001)
}
cat("\nAll status-quo gates PASSED.\n")

# ── N obs non-increasing SQ -> A1 -> A2, per cell ─────────────────────
cell_keys <- unique(compare_df[, c("family", "outcome", "model", "fe")])
n_monotone_violations <- 0
for (i in seq_len(nrow(cell_keys))) {
  k <- cell_keys[i, ]
  sub <- compare_df[compare_df$family == k$family & compare_df$outcome == k$outcome &
                       compare_df$model == k$model & compare_df$fe == k$fe, ]
  n_sq_i <- sub$n_obs[sub$sample == "status_quo"]
  n_a1_i <- sub$n_obs[sub$sample == "a1_no_upstream"]
  n_a2_i <- sub$n_obs[sub$sample == "a2_downstream_only"]
  if (length(n_sq_i) == 1 && length(n_a1_i) == 1 && length(n_a2_i) == 1 &&
      !is.na(n_sq_i) && !is.na(n_a1_i) && !is.na(n_a2_i)) {
    if (!(n_sq_i >= n_a1_i && n_a1_i >= n_a2_i)) n_monotone_violations <- n_monotone_violations + 1
  }
}
cat(sprintf("N-obs monotonicity check: %d cells violate SQ >= A1 >= A2 (of %d cells checked)\n",
            n_monotone_violations, nrow(cell_keys)))

# ── Write compare parquet ──────────────────────────────────────────────
compare_df$PWSID <- NULL
out_path <- file.path(ROOT, "clean_data/cws_data/k2_intake_purity_compare.parquet")
if (file.exists(out_path)) cat(sprintf("WARNING: %s already exists -- overwriting\n", out_path))
write_parquet(compare_df, out_path)
result_check <- read_parquet(out_path)
cat(sprintf("\nWritten %d rows to %s\n", nrow(result_check), out_path))
stopifnot(!any(is.na(result_check$sample)), !any(is.na(result_check$outcome)), !any(is.na(result_check$model)))

# ── Terminal report ──────────────────────────────────────────────────
fmt_cell <- function(coef, se, pval, digits = 2) {
  if (is.na(coef)) return("NA")
  stars <- if (is.na(pval)) "" else if (pval < 0.01) "***" else if (pval < 0.05) "**" else if (pval < 0.1) "*" else ""
  sprintf(paste0("%.", digits, "f(%.", digits, "f)%s"), coef, se, stars)
}

print_family_report <- function(family, digits = 2) {
  cat(sprintf("\n============ %s ============\n", toupper(family)))
  sub <- compare_df[compare_df$family == family, ]
  keys <- unique(sub[, c("outcome", "model", "fe")])
  keys <- keys[order(keys$outcome, keys$fe, keys$model), ]
  for (i in seq_len(nrow(keys))) {
    k <- keys[i, ]
    row <- sub[sub$outcome == k$outcome & sub$model == k$model & sub$fe == k$fe, ]
    sq <- row[row$sample == "status_quo", ]
    a1 <- row[row$sample == "a1_no_upstream", ]
    a2 <- row[row$sample == "a2_downstream_only", ]
    if (nrow(sq) != 1 || nrow(a1) != 1 || nrow(a2) != 1) next
    diff_a1 <- if (is.na(sq$coef) || is.na(a1$coef)) NA_real_ else a1$coef - sq$coef
    diff_a2 <- if (is.na(sq$coef) || is.na(a2$coef)) NA_real_ else a2$coef - sq$coef
    flip_a1 <- !is.na(sq$coef) && !is.na(a1$coef) && sign(sq$coef) != sign(a1$coef) && sq$coef != 0
    flip_a2 <- !is.na(sq$coef) && !is.na(a2$coef) && sign(sq$coef) != sign(a2$coef) && sq$coef != 0
    flag <- ""
    if (flip_a1 || flip_a2) flag <- paste0(flag, " <-- sign flip")
    weak_flag <- ""
    if (k$model == "IV" || k$model == "FS") {
      f_min <- min(c(sq$f_clustered, a1$f_clustered, a2$f_clustered), na.rm = TRUE)
      if (is.finite(f_min) && f_min < 10) weak_flag <- " <-- weak IV"
    }
    cat(sprintf("%-32s %-4s %-30s | SQ %-16s | A1 %-16s | A2 %-16s | dA1 %8s | dA2 %8s%s%s\n",
                k$outcome, k$model, k$fe,
                fmt_cell(sq$coef, sq$se, sq$pval, digits),
                fmt_cell(a1$coef, a1$se, a1$pval, digits),
                fmt_cell(a2$coef, a2$se, a2$pval, digits),
                if (is.na(diff_a1)) "NA" else sprintf(paste0("%.", digits, "f"), diff_a1),
                if (is.na(diff_a2)) "NA" else sprintf(paste0("%.", digits, "f"), diff_a2),
                flag, weak_flag))
    cat(sprintf("%74sN: SQ %s/%s  A1 %s/%s  A2 %s/%s", "",
                format(sq$n_obs, big.mark=","), format(sq$n_cws, big.mark=","),
                format(a1$n_obs, big.mark=","), format(a1$n_cws, big.mark=","),
                format(a2$n_obs, big.mark=","), format(a2$n_cws, big.mark=",")))
    if (k$model == "IV" || k$model == "FS") {
      cat(sprintf("  F: SQ %.2f  A1 %.2f  A2 %.2f", sq$f_clustered, a1$f_clustered, a2$f_clustered))
    }
    cat("\n")
  }
}

print_family_report("first_stage", digits = 2)
print_family_report("MR", digits = 2)
print_family_report("visits", digits = 2)
print_family_report("enforcement", digits = 2)
print_family_report("SYR2", digits = 4)

# ── Sample-size summary ─────────────────────────────────────────────────
cat("\n============ SAMPLE SIZE SUMMARY ============\n")
cat(sprintf("Utilities:      SQ=%d  A1=%d (dropped %d)  A2=%d (dropped %d from SQ, %d from A1)\n",
            length(ids_sq), length(ids_a1), length(ids_sq) - length(ids_a1),
            length(ids_a2), length(ids_sq) - length(ids_a2), length(ids_a1) - length(ids_a2)))
uy_sq <- nrow(main_dat[main_dat$PWSID %in% ids_sq, ])
uy_a1 <- nrow(main_dat[main_dat$PWSID %in% ids_a1, ])
uy_a2 <- nrow(main_dat[main_dat$PWSID %in% ids_a2, ])
cat(sprintf("Utility-years:  SQ=%d  A1=%d (dropped %d)  A2=%d (dropped %d from SQ, %d from A1)\n",
            uy_sq, uy_a1, uy_sq - uy_a1, uy_a2, uy_sq - uy_a2, uy_a1 - uy_a2))

# ── Static-sample reference block (print only, no estimation) ──────────
cat("\n============ OLD STATIC DOWNSTREAM SAMPLE (A1 = A2 = SQ by construction) ============\n")
cat("(340 utilities; different instrument/FE -- context only, not a like-for-like column)\n")
print_static_ref <- function(path, label) {
  cat(sprintf("\n--- %s ---\n%s\n", label, path))
  if (!file.exists(path)) { cat("  (file not found)\n"); return(invisible(NULL)) }
  lines <- readLines(path, warn = FALSE)
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]
  data_lines <- lines[grepl("&", lines) & grepl("\\\\\\\\", lines)]
  for (l in data_lines) cat("  ", l, "\n")
}
print_static_ref(file.path(ROOT, "output/reg/fs_dwnstrm_minevio_ivsum.tex"), "First stage")
print_static_ref(file.path(ROOT, "output/reg/2sls_dwnstrm_minevio_mr_ivsum_binvio.tex"), "MR violations")
print_static_ref(file.path(ROOT, "output/reg/h2_snsv_d12.tex"), "Visit types")
print_static_ref(file.path(ROOT, "output/reg/h3_inf_formal_d12.tex"), "Enforcement types")
print_static_ref(file.path(ROOT, "output/reg/6yr_huc02fe_inorg_ravalli_2005.tex"), "SYR2 concentrations")

cat("\n=== compare_k2_intake_purity.r DONE ===\n")
