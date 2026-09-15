# ============================================================
# Script: run_kgrid_coefs.r
# Purpose: Estimate OLS / RF / 2SLS coefficients (with clustered SEs) for
#          the k2 outcome set (MR, MCL, visit-type, enforcement-type) at
#          k = 1..8 flow steps, main and purity-screened placebo arms,
#          utility + year + state x year FE, A-full sample. Writes a tidy
#          plotting table for downstream figures. Verifies against
#          step_grid_results.parquet / step_grid_firststage.parquet (10
#          shared outcomes) and the k2 h2/h3 .tex tables (4 new outcomes)
#          before writing output.
# Inputs:
#   clean_data/cws_data/step_instruments.parquet
#   clean_data/cws_data/cws_covariates_steps.parquet
#   clean_data/cws_data/sdwa_vio_agg_steps.parquet
#   clean_data/cws_data/sdwa_visit_agg_kgrid.parquet
#   clean_data/cws_data/sdwa_enf_agg_kgrid.parquet
#   clean_data/cws_data/step_grid_results.parquet      (read-only, verification)
#   clean_data/cws_data/step_grid_firststage.parquet   (read-only, verification)
#   code/coal_mining_water_quality/k2_common.r          (sourced: get_term, f_clustered)
# Outputs:
#   clean_data/cws_data/kgrid_coefs.parquet
#   clean_data/cws_data/kgrid_firststage.parquet
# Author: EK  Date: 2026-09-15
# ============================================================

.libPaths(c(.libPaths(), "Z:/ek559/RPackages"))
library(fixest)
library(arrow)
library(dplyr)

ROOT <- "Z:/ek559/mining_wq"
source(file.path(ROOT, "code/coal_mining_water_quality/k2_common.r"))

# ── Read inputs once ──────────────────────────────────────────────────────
si     <- read_parquet(file.path(ROOT, "clean_data/cws_data/step_instruments.parquet"))
covars <- read_parquet(file.path(ROOT, "clean_data/cws_data/cws_covariates_steps.parquet"))
vio    <- read_parquet(file.path(ROOT, "clean_data/cws_data/sdwa_vio_agg_steps.parquet"))
visit  <- read_parquet(file.path(ROOT, "clean_data/cws_data/sdwa_visit_agg_kgrid.parquet"))
enf    <- read_parquet(file.path(ROOT, "clean_data/cws_data/sdwa_enf_agg_kgrid.parquet"))

stopifnot(is.character(si$PWSID), is.character(covars$PWSID), is.character(vio$PWSID),
          is.character(visit$PWSID), is.character(enf$PWSID))

# ── Build the joined, zero-filled, x100-scaled panel once (all k, both arms) ──
# Mirrors build_k2_panel() (k2_common.r:36-91) with the kgrid visit/enf
# caches and no k restriction yet -- k/arm filtering happens per sample below.
panel <- covars %>%
  dplyr::left_join(vio,   by = c("PWSID", "year")) %>%
  dplyr::left_join(visit, by = c("PWSID", "year")) %>%
  dplyr::left_join(enf,   by = c("PWSID", "year"))

vio_share_cols <- grep("_share_days$", names(panel), value = TRUE)
for (v in vio_share_cols) panel[[v]][is.na(panel[[v]])] <- 0
zero_fill_cols <- c("n_visits", "any_snsv", "any_tech", "any_enfvisit", "any_smpl",
                     "any_insp", "any_formal", "any_informal", "any_enf")
for (v in zero_fill_cols) panel[[v]][is.na(panel[[v]])] <- 0

bin_src_vars <- c(
  "nitrates_share_days", "arsenic_share_days", "inorganic_chemicals_share_days",
  "nitrates_MCL_share_days", "arsenic_MCL_share_days", "inorganic_chemicals_MCL_share_days",
  "nitrates_MR_share_days", "arsenic_MR_share_days", "inorganic_chemicals_MR_share_days"
)
for (v in bin_src_vars) {
  bv <- sub("_share_days$", "_bin", v)
  panel[[bv]] <- as.integer(panel[[v]] > 0) * 100L
}
for (v in c("any_snsv", "any_tech", "any_enfvisit", "any_smpl", "any_insp",
            "any_formal", "any_informal", "any_enf")) {
  panel[[v]] <- panel[[v]] * 100
}
panel$no_enf <- 100 - panel$any_enf
panel$post95 <- as.integer(panel$year >= 1995)

full <- si %>% dplyr::inner_join(panel, by = c("PWSID", "year"))
cat(sprintf("Full joined table (arm x k x PWSID x year): %d rows\n", nrow(full)))

# ── Panel builder: per (k, arm) A-full sample, purity-screened placebo ──────
# Mirrors build_k2_panel() (k2_common.r:80-87) with k==2 replaced by k==kk.
build_kgrid_panel <- function(arm_choice, kk) {
  main_k <- full %>% dplyr::filter(arm == "main", k == kk, n_mine_hucs_linked >= 1)
  if (arm_choice == "main") {
    out <- main_k
  } else {
    main_ids <- unique(main_k$PWSID)
    out <- full %>% dplyr::filter(arm == "placebo", k == kk, n_mine_hucs_linked >= 1,
                                   !(PWSID %in% main_ids))
  }
  out
}

# ── Constants ────────────────────────────────────────────────────────────
FE_STR  <- "PWSID + year + STATE_CODE^year"
COALVAR <- "num_coal_mines_linked_sum"
INSTR   <- "post95:sulfur_mean0"
FAMILIES <- list(
  mr    = c(nitrates_MR_bin = "Nitrates", arsenic_MR_bin = "Arsenic", inorganic_chemicals_MR_bin = "Inorganic chemicals"),
  mcl   = c(nitrates_MCL_bin = "Nitrates", arsenic_MCL_bin = "Arsenic", inorganic_chemicals_MCL_bin = "Inorganic chemicals"),
  visit = c(any_snsv = "Sanitary", any_tech = "Technical assistance", any_enfvisit = "Enforcement",
            any_smpl = "Sample collection", any_insp = "Inspection"),
  enf   = c(any_informal = "Informal", any_formal = "Formal", no_enf = "None")
)

# ── Estimation: 8 k x 2 arms x 14 outcomes x 3 models = 672 regressions ────
coef_rows <- list(); fs_rows <- list()
row_i <- 1L; fs_i <- 1L

for (kk in 1:8) {
  for (arm in c("main", "placebo")) {
    dat <- build_kgrid_panel(arm, kk)
    n_cws_arm <- dplyr::n_distinct(dat$PWSID)
    cat(sprintf("k=%d %-7s: %5d rows, %4d utilities\n", kk, arm, nrow(dat), n_cws_arm))

    fs <- tryCatch(
      fixest::feols(as.formula(paste0(COALVAR, " ~ ", INSTR, " + num_facilities | ", FE_STR)),
                    data = dat, cluster = ~PWSID, warn = FALSE, notes = FALSE),
      error = function(e) NULL
    )
    fs_coef <- NA_real_; fs_se <- NA_real_
    if (!is.null(fs) && INSTR %in% names(coef(fs))) {
      fs_coef <- coef(fs)[INSTR]
      fs_se   <- fixest::se(fs)[INSTR]
    }
    fclust <- f_clustered(dat, FE_STR)
    fs_rows[[fs_i]] <- data.frame(k = kk, arm = arm, fs_coef = fs_coef, fs_se = fs_se,
                                   f_clustered = fclust, n_obs = nrow(dat), n_cws = n_cws_arm)
    fs_i <- fs_i + 1L

    for (fam in names(FAMILIES)) {
      outcomes <- FAMILIES[[fam]]
      for (oc in names(outcomes)) {
        oc_label <- outcomes[[oc]]
        dat_y <- dat[!is.na(dat[[oc]]), ]

        f_ols <- as.formula(paste0(oc, " ~ ", COALVAR, " + num_facilities | ", FE_STR))
        f_rf  <- as.formula(paste0(oc, " ~ ", INSTR, " + num_facilities | ", FE_STR))
        f_iv  <- as.formula(paste0(oc, " ~ num_facilities | ", FE_STR, " | ", COALVAR, " ~ ", INSTR))

        ols <- tryCatch(fixest::feols(f_ols, data = dat_y, cluster = ~PWSID, warn = FALSE, notes = FALSE), error = function(e) NULL)
        rf  <- tryCatch(fixest::feols(f_rf,  data = dat_y, cluster = ~PWSID, warn = FALSE, notes = FALSE), error = function(e) NULL)
        iv  <- tryCatch(fixest::feols(f_iv,  data = dat_y, cluster = ~PWSID, warn = FALSE, notes = FALSE), error = function(e) NULL)

        add_row <- function(model, term, model_label) {
          if (is.null(model)) {
            tm <- list(est = NA_real_, se = NA_real_, pval = NA_real_)
            n_obs_r <- NA_integer_
          } else {
            tm <- get_term(model, term)
            n_obs_r <- nobs(model)
          }
          coef_rows[[row_i]] <<- data.frame(
            k = kk, arm = arm, family = fam, outcome = oc, outcome_label = oc_label,
            model = model_label, coef = tm$est, se = tm$se, pval = tm$pval,
            n_obs = n_obs_r, n_cws = dplyr::n_distinct(dat_y$PWSID)
          )
          row_i <<- row_i + 1L
        }
        add_row(ols, COALVAR, "OLS")
        add_row(rf,  INSTR,   "RF")
        add_row(iv,  COALVAR, "2SLS")
      }
    }
  }
}

coef_df <- dplyr::bind_rows(coef_rows)
fs_df   <- dplyr::bind_rows(fs_rows)

cat(sprintf("\nEstimated %d coefficient rows, %d first-stage rows.\n", nrow(coef_df), nrow(fs_df)))
stopifnot(nrow(coef_df) == 16 * 14 * 3, nrow(fs_df) == 16)

# ── Verification gate 1: 10 shared outcomes vs step_grid_results.parquet ───
cat("\n==================== Verification gate 1: vs step_grid_results.parquet ====================\n")
grid_res <- read_parquet(file.path(ROOT, "clean_data/cws_data/step_grid_results.parquet"))
shared_outcomes <- c("nitrates_MR_bin", "arsenic_MR_bin", "inorganic_chemicals_MR_bin",
                      "nitrates_MCL_bin", "arsenic_MCL_bin", "inorganic_chemicals_MCL_bin",
                      "any_snsv", "any_enfvisit", "any_formal", "any_informal")
model_map <- c(OLS = "OLS", RF = "RF", "2SLS" = "IV")

grid_ref <- grid_res %>%
  dplyr::filter(column == "A-full", fe == "PWSID+year+state x year", outcome %in% shared_outcomes) %>%
  dplyr::select(k, arm, outcome, model, coef_ref = coef, se_ref = se)

cmp1 <- coef_df %>%
  dplyr::filter(outcome %in% shared_outcomes) %>%
  dplyr::mutate(model_grid = model_map[model]) %>%
  dplyr::inner_join(grid_ref, by = c("k", "arm", "outcome", "model_grid" = "model"))

stopifnot(nrow(cmp1) == 16 * 10 * 3)
max_coef_diff <- max(abs(cmp1$coef - cmp1$coef_ref), na.rm = TRUE)
max_se_diff   <- max(abs(cmp1$se - cmp1$se_ref), na.rm = TRUE)
cat(sprintf("Compared %d rows. Max |coef diff| = %.2e, max |se diff| = %.2e\n",
            nrow(cmp1), max_coef_diff, max_se_diff))
stopifnot(max_coef_diff < 1e-6, max_se_diff < 1e-6)
cat("Gate 1 PASSED.\n")

# ── Verification gate 2: first stage vs step_grid_firststage.parquet ───────
cat("\n==================== Verification gate 2: vs step_grid_firststage.parquet ====================\n")
grid_fs <- read_parquet(file.path(ROOT, "clean_data/cws_data/step_grid_firststage.parquet")) %>%
  dplyr::filter(column == "A-full", fe == "PWSID+year+state x year") %>%
  dplyr::select(k, arm, f_ref = f_clustered)

cmp2 <- fs_df %>% dplyr::inner_join(grid_fs, by = c("k", "arm"))
stopifnot(nrow(cmp2) == 16)
max_f_diff <- max(abs(cmp2$f_clustered - cmp2$f_ref), na.rm = TRUE)
cat(sprintf("Compared %d (k, arm) rows. Max |F diff| = %.4f\n", nrow(cmp2), max_f_diff))
print(cmp2 %>% dplyr::select(k, arm, f_clustered, f_ref))
stopifnot(max_f_diff < 0.01)
cat("Gate 2 PASSED.\n")

# ── Verification gate 3: k=2 anchors for the 4 new outcomes (h2/h3 .tex) ───
cat("\n==================== Verification gate 3: k=2 anchors (h2/h3 .tex, 4 new outcomes) ====================\n")
# Hand-transcribed 2SLS coef(SE) from output/reg/h2_snsv_d12_k2[placebo].tex
# and h3_inf_formal_d12_k2[placebo].tex (verified read during exploration).
anchors <- tibble::tribble(
  ~k, ~arm,      ~outcome,       ~coef_ref, ~se_ref,
   2, "main",    "any_tech",        -0.10,     0.98,
   2, "main",    "any_smpl",         0.08,     0.50,
   2, "main",    "any_insp",         2.10,     1.15,
   2, "main",    "no_enf",           0.68,     2.26,
   2, "placebo", "any_tech",         1.81,     1.43,
   2, "placebo", "any_smpl",         2.52,     1.16,
   2, "placebo", "any_insp",         3.03,     1.68,
   2, "placebo", "no_enf",           1.23,     3.71
)
cmp3 <- coef_df %>%
  dplyr::filter(model == "2SLS", k == 2, outcome %in% anchors$outcome) %>%
  dplyr::inner_join(anchors, by = c("k", "arm", "outcome")) %>%
  dplyr::mutate(coef_r = round(coef, 2), se_r = round(se, 2))
stopifnot(nrow(cmp3) == nrow(anchors))
print(cmp3 %>% dplyr::select(k, arm, outcome, coef_r, coef_ref, se_r, se_ref))
stopifnot(all(cmp3$coef_r == cmp3$coef_ref), all(cmp3$se_r == cmp3$se_ref))
cat("Gate 3 PASSED.\n")

# ── Verification gate 4: no NA coef in any row ──────────────────────────────
cat("\n==================== Verification gate 4: NA coefficient scan ====================\n")
na_rows <- coef_df %>% dplyr::filter(is.na(coef))
if (nrow(na_rows) > 0) {
  cat(sprintf("WARNING: %d rows have NA coefficients (reported, not dropped):\n", nrow(na_rows)))
  print(na_rows %>% dplyr::select(k, arm, family, outcome, model) %>% dplyr::distinct())
} else {
  cat("No NA coefficients in any of the 672 rows.\n")
}

# ── Write outputs ────────────────────────────────────────────────────────
out_coef <- file.path(ROOT, "clean_data/cws_data/kgrid_coefs.parquet")
out_fs   <- file.path(ROOT, "clean_data/cws_data/kgrid_firststage.parquet")
if (file.exists(out_coef)) cat("WARNING: overwriting existing", out_coef, "\n")
if (file.exists(out_fs))   cat("WARNING: overwriting existing", out_fs, "\n")
write_parquet(coef_df, out_coef)
write_parquet(fs_df, out_fs)
cat(sprintf("\nWrote %d rows to %s\n", nrow(coef_df), out_coef))
cat(sprintf("Wrote %d rows to %s\n", nrow(fs_df), out_fs))

# ── Terminal summary ─────────────────────────────────────────────────────
fmt <- function(x, d = 2) ifelse(is.na(x), "NA", sprintf(paste0("%.", d, "f"), x))

cat("\n\n==================== Summary: First-stage F by k x arm ====================\n")
print(fs_df %>% dplyr::mutate(F = fmt(f_clustered)) %>% dplyr::select(k, arm, n_cws, n_obs, F))

cat("\n\n==================== Summary: 2SLS coef(SE) by k, each outcome ====================\n")
for (fam in names(FAMILIES)) {
  outcomes <- FAMILIES[[fam]]
  for (oc in names(outcomes)) {
    cat(sprintf("\n-- %s (%s) --\n", outcomes[[oc]], fam))
    cat(sprintf("%-4s %-20s %-20s\n", "k", "main coef(SE)", "placebo coef(SE)"))
    for (kk in 1:8) {
      m <- coef_df %>% dplyr::filter(k == kk, arm == "main", outcome == oc, model == "2SLS")
      p <- coef_df %>% dplyr::filter(k == kk, arm == "placebo", outcome == oc, model == "2SLS")
      m_str <- if (nrow(m) == 1) sprintf("%s(%s)", fmt(m$coef), fmt(m$se)) else "--"
      p_str <- if (nrow(p) == 1) sprintf("%s(%s)", fmt(p$coef), fmt(p$se)) else "--"
      cat(sprintf("%-4d %-20s %-20s\n", kk, m_str, p_str))
    }
  }
}

cat("\nDone.\n")
