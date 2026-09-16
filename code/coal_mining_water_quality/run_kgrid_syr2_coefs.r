# ============================================================
# Script: run_kgrid_syr2_coefs.r
# Purpose: Estimate the OLS effect of cumulative linked coal production on
#          mean measured SYR2 concentration (arsenic, nitrate, barium,
#          selenium) at k = 1..8 flow steps, main and purity-screened
#          placebo arms, utility + huc02 x year FE (matches the published
#          6yr_huc02fe_* tables' FE spec). `production_linked_sum`
#          (from step_instruments.parquet) is already direction-correct per
#          arm -- build_step_instruments.py sums production over ancestor
#          (upstream) HUCs for the main arm and descendant (downstream) HUCs
#          for the placebo arm (see main_pairs/placebo_pairs, lines 92-127),
#          so cumulating it here yields cumulative upstream production for
#          the main arm and cumulative downstream production for the
#          placebo arm. The step-grid's post95:sulfur_mean0 instrument is
#          degenerate on this sample (post95 is identically 1 on every
#          non-missing VALUE observation <= 2005), so only OLS is estimated
#          here (matches run_k2_6yr_tables.r / run_step_top3_outcomes.r).
#          Writes a tidy plotting table. Verifies against the k=1 main-arm
#          anchor in output/reg/6yr_huc02fe_inorg_ravalli_2005.tex, which a
#          prior diagnostic (run_step_top3_outcomes.r, see
#          .claude/logs/2026-09-14-step-top3-enforcement-visits-concentration.md)
#          confirmed reproduces exactly under this same sample + FE spec.
# Inputs:
#   clean_data/cws_data/step_instruments.parquet
#   clean_data/cws_6year_review_ravalli.parquet
#   clean_data/cws_data/pwsid_huc02.parquet
#   code/coal_mining_water_quality/k2_common.r (sourced: get_term)
# Outputs:
#   clean_data/cws_data/kgrid_syr2_coefs.parquet
# Author: EK  Date: 2026-09-15
# ============================================================

.libPaths(c(.libPaths(), "Z:/ek559/RPackages"))
library(fixest)
library(arrow)
library(dplyr)

ROOT <- "Z:/ek559/mining_wq"
source(file.path(ROOT, "code/coal_mining_water_quality/k2_common.r"))

# ── Read inputs once ──────────────────────────────────────────────────────
si    <- read_parquet(file.path(ROOT, "clean_data/cws_data/step_instruments.parquet"))
d6r   <- read_parquet(file.path(ROOT, "clean_data/cws_6year_review_ravalli.parquet"))
huc02 <- read_parquet(file.path(ROOT, "clean_data/cws_data/pwsid_huc02.parquet"))

stopifnot(is.character(si$PWSID), is.character(d6r$PWSID), is.character(huc02$PWSID))
d6r <- d6r %>%
  dplyr::left_join(huc02 %>% dplyr::select(PWSID, huc02), by = "PWSID") %>%
  dplyr::filter(year >= 1985, PWSID != "WV3303401")

CHEMS <- c(arsenic = "Arsenic", nitrate = "Nitrate", barium = "Barium", selenium = "Selenium")
fml_huc02 <- VALUE ~ coal_prod_linked_cumsum_10mst + num_facilities | PWSID + huc02^year

# ── Dose-sample builder: k-step cumulative linked production, per arm ──────
# Generalizes run_k2_6yr_tables.r:47-74 / run_step_top3_outcomes.r:112-140
# with an arm_choice argument and the placebo purity screen from
# run_kgrid_coefs.r::build_kgrid_panel() (drop PWSIDs also main-arm-linked
# at the same k). `production_linked_sum` is already arm-direction-correct
# (see header note), so the cumulative sum built here is upstream production
# for arm_choice=="main" and downstream production for arm_choice=="placebo"
# -- deliberately arm-neutral naming (coal_prod_linked_cumsum, not
# coal_prod_upstream_cumsum) to avoid mislabeling the placebo-arm quantity.
build_dose_sample <- function(kk, arm_choice) {
  main_k_ids <- si %>% dplyr::filter(arm == "main", k == kk, n_mine_hucs_linked >= 1) %>%
    dplyr::distinct(PWSID) %>% dplyr::pull(PWSID)

  if (arm_choice == "main") {
    arm_k <- si %>% dplyr::filter(arm == "main", k == kk, n_mine_hucs_linked >= 1) %>%
      apply_a2() %>%
      dplyr::select(PWSID, year, production_linked_sum)
  } else {
    arm_k <- si %>% dplyr::filter(arm == "placebo", k == kk, n_mine_hucs_linked >= 1,
                                   !(PWSID %in% main_k_ids)) %>%
      apply_a2() %>%
      dplyr::select(PWSID, year, production_linked_sum)
  }

  linked_pwsids <- unique(arm_k$PWSID)
  d <- d6r %>% dplyr::filter(PWSID %in% linked_pwsids, CHEMID_name %in% names(CHEMS))

  cum_panel <- arm_k %>%
    dplyr::distinct(PWSID, year, production_linked_sum) %>%
    dplyr::arrange(PWSID, year) %>%
    dplyr::group_by(PWSID) %>%
    dplyr::mutate(coal_prod_linked_cumsum =
             cumsum(replace(production_linked_sum, is.na(production_linked_sum), 0))) %>%
    dplyr::ungroup() %>%
    dplyr::select(PWSID, year, coal_prod_linked_cumsum)

  d <- d %>% dplyr::inner_join(cum_panel, by = c("PWSID", "year"))

  chk <- d %>% dplyr::distinct(PWSID, year, coal_prod_linked_cumsum) %>%
    dplyr::arrange(PWSID, year) %>% dplyr::group_by(PWSID) %>%
    dplyr::mutate(diff = coal_prod_linked_cumsum - dplyr::lag(coal_prod_linked_cumsum))
  stopifnot(all(chk$diff >= 0 | is.na(chk$diff)))

  d$coal_prod_linked_cumsum_10mst <- d$coal_prod_linked_cumsum / 1e7
  d <- d[!is.na(d$VALUE), ]
  d <- d[d$year <= 2005, ]
  d
}

# ── Estimation: 8 k x 2 arms x 4 chemicals = up to 64 OLS regressions ──────
coef_rows <- list(); row_i <- 1L
skip_rows <- list(); skip_i <- 1L

for (kk in 1:8) {
  for (arm in c("main", "placebo")) {
    dat <- build_dose_sample(kk, arm)
    cat(sprintf("k=%d %-7s: %5d rows, %4d utilities (all 4 chemicals pooled)\n",
                kk, arm, nrow(dat), dplyr::n_distinct(dat$PWSID)))

    for (chem in names(CHEMS)) {
      d_chem <- dat[dat$CHEMID_name == chem, ]
      if (nrow(d_chem) < 30) {
        skip_rows[[skip_i]] <- data.frame(k = kk, arm = arm, chemical = chem, n_obs = nrow(d_chem))
        skip_i <- skip_i + 1L
        coef_rows[[row_i]] <- data.frame(
          k = kk, arm = arm, chemical = chem, chemical_label = CHEMS[[chem]],
          coef = NA_real_, se = NA_real_, pval = NA_real_,
          n_obs = nrow(d_chem), n_cws = dplyr::n_distinct(d_chem$PWSID))
        row_i <- row_i + 1L
        next
      }
      m <- tryCatch(fixest::feols(fml_huc02, data = d_chem, cluster = ~PWSID, warn = FALSE, notes = FALSE),
                    error = function(e) NULL)
      if (is.null(m)) {
        tm <- list(est = NA_real_, se = NA_real_, pval = NA_real_)
        n_obs_r <- nrow(d_chem)
      } else {
        tm <- get_term(m, "coal_prod_linked_cumsum_10mst")
        n_obs_r <- nobs(m)
      }
      coef_rows[[row_i]] <- data.frame(
        k = kk, arm = arm, chemical = chem, chemical_label = CHEMS[[chem]],
        coef = tm$est, se = tm$se, pval = tm$pval,
        n_obs = n_obs_r, n_cws = dplyr::n_distinct(d_chem$PWSID))
      row_i <- row_i + 1L
    }
  }
}

coef_df <- dplyr::bind_rows(coef_rows)
cat(sprintf("\nEstimated %d coefficient rows (8 k x 2 arm x 4 chem = 64 possible).\n", nrow(coef_df)))
stopifnot(nrow(coef_df) == 8 * 2 * 4)

# ── Verification gate 1: k=1 main-arm anchor vs 6yr_huc02fe_inorg_ravalli_2005.tex ──
cat("\n==================== Verification gate 1: k=1 main-arm anchor (6yr_huc02fe_inorg_ravalli_2005.tex) ====================\n")
anchors <- tibble::tribble(
  ~chemical,  ~coef_ref, ~se_ref,
  "arsenic",     0.0023,  0.0004,
  "nitrate",     0.0572,  0.0922,
  "barium",      0.0171,  0.0093,
  "selenium",    0.0033,  0.0016
)
cmp1 <- coef_df %>%
  dplyr::filter(k == 1, arm == "main") %>%
  dplyr::mutate(coef_r = round(coef, 4), se_r = round(se, 4)) %>%
  dplyr::inner_join(anchors, by = "chemical")
stopifnot(nrow(cmp1) == 4)
print(cmp1 %>% dplyr::select(chemical, coef_r, coef_ref, se_r, se_ref, n_obs))
stopifnot(all(cmp1$coef_r == cmp1$coef_ref), all(cmp1$se_r == cmp1$se_ref))
cat("Gate 1 PASSED.\n")

# ── Verification gate 2: <30-obs skip scan ──────────────────────────────────
cat("\n==================== Verification gate 2: <30-obs skip scan ====================\n")
if (skip_i > 1L) {
  skip_df <- dplyr::bind_rows(skip_rows)
  cat(sprintf("%d cell(s) skipped for <30 obs:\n", nrow(skip_df)))
  print(skip_df)
  unexpected <- skip_df %>% dplyr::filter(k >= 2, arm == "main")
  if (nrow(unexpected) > 0) {
    stop("Unexpected <30-obs skip at k>=2 main arm -- k=2 main arm is known-good from the anchor gate. Stop and investigate.")
  }
} else {
  cat("No cells skipped for <30 obs (expected, per pre-flight sample-size check).\n")
}

# ── Write output ─────────────────────────────────────────────────────────
out_path <- file.path(ROOT, "clean_data/cws_data/kgrid_syr2_coefs.parquet")
if (file.exists(out_path)) cat("WARNING: overwriting existing", out_path, "\n")
write_parquet(coef_df, out_path)
cat(sprintf("\nWrote %d rows to %s\n", nrow(coef_df), out_path))

# ── Terminal summary ─────────────────────────────────────────────────────
fmt <- function(x, d = 4) ifelse(is.na(x), "NA", sprintf(paste0("%.", d, "f"), x))

cat("\n\n==================== Summary: OLS coef(SE) by k, arm, chemical ====================\n")
for (chem in names(CHEMS)) {
  cat(sprintf("\n-- %s --\n", CHEMS[[chem]]))
  cat(sprintf("%-4s %-20s %-20s\n", "k", "main coef(SE)", "placebo coef(SE)"))
  for (kk in 1:8) {
    m <- coef_df %>% dplyr::filter(k == kk, arm == "main", chemical == chem)
    p <- coef_df %>% dplyr::filter(k == kk, arm == "placebo", chemical == chem)
    m_str <- if (nrow(m) == 1) sprintf("%s(%s)", fmt(m$coef), fmt(m$se)) else "--"
    p_str <- if (nrow(p) == 1) sprintf("%s(%s)", fmt(p$coef), fmt(p$se)) else "--"
    cat(sprintf("%-4d %-20s %-20s\n", kk, m_str, p_str))
  }
}

cat("\nDone.\n")
