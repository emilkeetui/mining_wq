# ============================================================
# Script: run_step_top3_outcomes.r
# Purpose: For the top-3 ranked step-instrument grid cells (k=2, k=7, k=8;
#          main arm, A-full column, PWSID+year+state x year FE — see
#          .claude/logs/2026-09-14-step-grid-ranking-and-fstat-mechanism.md),
#          report how enforcement, regulator visits, and mean measured
#          contaminant concentration move. Part A queries the existing
#          step-grid results (no re-estimation). Part B re-estimates a
#          concentration outcome using the k-step linkage in place of the
#          fixed downstream sample filter used by cws_6year_review_huc02fe.r,
#          since the grid's IV is degenerate on the concentration sample
#          (post95 is identically 1 on all non-missing VALUE obs <= 2005).
#          Terminal-only diagnostic: no .tex, no output/ writes, no changes
#          to the production pipeline.
# Inputs:
#   clean_data/cws_data/step_grid_results.parquet
#   clean_data/cws_data/step_grid_firststage.parquet
#   clean_data/cws_data/step_instruments.parquet
#   clean_data/cws_data/cws_covariates_steps.parquet
#   clean_data/cws_6year_review_ravalli.parquet
#   clean_data/cws_data/pwsid_huc02.parquet
# Outputs: terminal printout only
# Author: EK  Date: 2026-09-14
# ============================================================

.libPaths(c(.libPaths(), "Z:/ek559/RPackages"))
library(fixest)
library(arrow)
library(dplyr)

ROOT <- "Z:/ek559/mining_wq"
K_TOP3 <- c(2, 7, 8)
K_ALL  <- c(1, 2, 7, 8)  # k=1 is a reproduction anchor, not a ranked result

fmt <- function(x, d = 4) ifelse(is.na(x), "NA", sprintf(paste0("%.", d, "f"), x))
stars <- function(p) ifelse(is.na(p), "", ifelse(p < 0.01, "***", ifelse(p < 0.05, "**", ifelse(p < 0.1, "*", ""))))

# ============================================================
# PART A — Enforcement & visits: query existing grid results, no re-estimation
# ============================================================
cat("==================== PART A: Enforcement & Visits (main arm, A-full) ====================\n")
cat("Source: clean_data/cws_data/step_grid_results.parquet / step_grid_firststage.parquet\n")
cat("(estimated in the 2026-09-13 run; not previously displayed for k=2,7,8)\n")
cat("Units: percentage points (binary outcomes x100). Stars: *** p<0.01, ** p<0.05, * p<0.1.\n\n")

res_path <- file.path(ROOT, "clean_data/cws_data/step_grid_results.parquet")
fs_path  <- file.path(ROOT, "clean_data/cws_data/step_grid_firststage.parquet")
stopifnot(file.exists(res_path), file.exists(fs_path))

res_df <- read_parquet(res_path)
fs_df  <- read_parquet(fs_path)
cat("Cross-language schema check: step_grid_results PWSID-free tidy table, k class:", class(res_df$k), "\n\n")

visit_enf_outcomes <- c(
  any_snsv     = "Sanitary visit",
  any_enfvisit = "Enforcement visit",
  any_formal   = "Formal enforcement",
  any_informal = "Informal enforcement"
)

cat("---- First stage (main vs placebo), A-full, both FE specs ----\n")
cat(sprintf("%-4s %-24s %-8s %6s %6s %12s %8s\n", "k", "FE", "arm", "N_CWS", "N_obs", "coef(SE)", "F"))
fs_a <- fs_df %>% filter(column == "A-full", k %in% K_ALL) %>% arrange(k, fe, desc(arm == "main"))
for (i in seq_len(nrow(fs_a))) {
  r <- fs_a[i, ]
  coef_se <- sprintf("%s(%s)", fmt(r$fs_coef), fmt(r$fs_se))
  f_flag  <- if (!is.na(r$f_clustered) && r$f_clustered < 10) paste0(fmt(r$f_clustered, 2), " WEAK") else fmt(r$f_clustered, 2)
  cat(sprintf("%-4d %-24s %-8s %6d %6d %12s %8s\n", r$k, r$fe, r$arm, r$n_cws, r$n_obs, coef_se, f_flag))
}

for (oc in names(visit_enf_outcomes)) {
  cat(sprintf("\n---- %s (IV, A-full, percentage points) ----\n", visit_enf_outcomes[[oc]]))
  cat(sprintf("%-4s %-24s %-20s %-20s\n", "k", "FE", "main coef(SE)", "placebo coef(SE)"))
  for (kk in K_ALL) {
    for (fe_lab in c("PWSID+year", "PWSID+year+state x year")) {
      m <- res_df %>% filter(k == kk, arm == "main",    column == "A-full", fe == fe_lab, outcome == oc, model == "IV")
      p <- res_df %>% filter(k == kk, arm == "placebo", column == "A-full", fe == fe_lab, outcome == oc, model == "IV")
      if (nrow(m) == 0 && nrow(p) == 0) next
      m_str <- if (nrow(m) == 1) sprintf("%s%s(%s)", fmt(m$coef, 2), stars(m$pval), fmt(m$se, 2)) else "--"
      p_str <- if (nrow(p) == 1) sprintf("%s%s(%s)", fmt(p$coef, 2), stars(p$pval), fmt(p$se, 2)) else "--"
      flag  <- if (kk %in% K_TOP3) "  <-- top3" else ""
      cat(sprintf("%-4d %-24s %-20s %-20s%s\n", kk, fe_lab, m_str, p_str, flag))
    }
  }
}

# ============================================================
# PART B — Mean contaminant concentration (new estimation)
# ============================================================
cat("\n\n==================== PART B: Mean Contaminant Concentration (main arm) ====================\n")
cat("NOTE: the grid's IV is degenerate on this sample (post95 is identically 1 on every\n")
cat("non-missing VALUE observation <= 2005; sulfur_mean0 is time-invariant within\n")
cat("PWSID x arm x k). This block reports the OLS cumulative-dose specification from\n")
cat("6yr_huc02fe_inorg_ravalli_2005 (cws_6year_review_huc02fe.r), with that table's fixed\n")
cat("one-step-downstream sample filter swapped for the step-grid's k-step linkage.\n\n")

d6r   <- read_parquet(file.path(ROOT, "clean_data/cws_6year_review_ravalli.parquet"))
huc02 <- read_parquet(file.path(ROOT, "clean_data/cws_data/pwsid_huc02.parquet"))
si    <- read_parquet(file.path(ROOT, "clean_data/cws_data/step_instruments.parquet"))
stopifnot(is.character(d6r$PWSID), is.character(huc02$PWSID), is.character(si$PWSID))
stopifnot("STATE_CODE" %in% names(d6r))
cat("Cross-language schema check: d6r PWSID", class(d6r$PWSID), "year", class(d6r$year),
    "| si PWSID", class(si$PWSID), "year", class(si$year), "\n\n")

CHEMS <- c("arsenic", "nitrate", "barium", "selenium")
nice_chem <- c(arsenic = "Arsenic", nitrate = "Nitrate", barium = "Barium", selenium = "Selenium")

d6r <- d6r %>%
  left_join(huc02 %>% select(PWSID, huc02), by = "PWSID") %>%
  filter(year >= 1985, PWSID != "WV3303401")

build_dose_sample <- function(kk) {
  arm_k <- si %>% filter(arm == "main", k == kk, n_mine_hucs_linked >= 1) %>%
    select(PWSID, year, production_linked_sum)

  linked_pwsids <- unique(arm_k$PWSID)
  d <- d6r %>% filter(PWSID %in% linked_pwsids, CHEMID_name %in% CHEMS)

  cum_panel <- arm_k %>%
    distinct(PWSID, year, production_linked_sum) %>%
    arrange(PWSID, year) %>%
    group_by(PWSID) %>%
    mutate(coal_prod_upstream_cumsum =
             cumsum(replace(production_linked_sum, is.na(production_linked_sum), 0))) %>%
    ungroup() %>%
    select(PWSID, year, coal_prod_upstream_cumsum)

  d <- d %>% inner_join(cum_panel, by = c("PWSID", "year"))

  chk <- d %>% distinct(PWSID, year, coal_prod_upstream_cumsum) %>%
    arrange(PWSID, year) %>% group_by(PWSID) %>%
    mutate(diff = coal_prod_upstream_cumsum - lag(coal_prod_upstream_cumsum))
  stopifnot(all(chk$diff >= 0 | is.na(chk$diff)))

  d$coal_prod_upstream_cumsum_10mst <- d$coal_prod_upstream_cumsum / 1e7

  d <- d[!is.na(d$VALUE), ]
  d <- d[d$year <= 2005, ]
  d
}

fml_huc02  <- VALUE ~ coal_prod_upstream_cumsum_10mst + num_facilities | PWSID + huc02^year
fml_state  <- VALUE ~ coal_prod_upstream_cumsum_10mst + num_facilities | PWSID + STATE_CODE^year

cat(sprintf("%-4s %-10s %-20s %-20s %8s %8s\n", "k", "chem", "coef(SE) huc02^yr", "coef(SE) state^yr", "N_huc02", "N_st"))
n_cws_track <- list()
for (kk in K_ALL) {
  dat <- build_dose_sample(kk)
  n_cws_track[[as.character(kk)]] <- n_distinct(dat$PWSID)
  for (chem in CHEMS) {
    d_chem <- dat[dat$CHEMID_name == chem, ]
    if (nrow(d_chem) < 30) {
      cat(sprintf("%-4d %-10s %-20s %-20s %8s %8s  (n=%d, skipped: <30 obs)\n",
                  kk, nice_chem[[chem]], "--", "--", "--", "--", nrow(d_chem)))
      next
    }
    m_h <- tryCatch(feols(fml_huc02, data = d_chem, cluster = ~PWSID, warn = FALSE, notes = FALSE),
                     error = function(e) NULL)
    m_s <- tryCatch(feols(fml_state, data = d_chem, cluster = ~PWSID, warn = FALSE, notes = FALSE),
                     error = function(e) NULL)

    get_str <- function(m) {
      if (is.null(m) || !("coal_prod_upstream_cumsum_10mst" %in% names(coef(m)))) return(list(str = "--", n = NA))
      ct <- coeftable(m)
      row <- "coal_prod_upstream_cumsum_10mst"
      list(str = sprintf("%s%s(%s)", fmt(ct[row, "Estimate"]), stars(ct[row, "Pr(>|t|)"]), fmt(ct[row, "Std. Error"])),
           n = nobs(m))
    }
    rh <- get_str(m_h)
    rs <- get_str(m_s)
    flag <- if (kk %in% K_TOP3) "  <-- top3" else if (kk == 1) "  (anchor)" else ""
    cat(sprintf("%-4d %-10s %-20s %-20s %8s %8s%s\n",
                kk, nice_chem[[chem]], rh$str, rs$str, fmt(rh$n, 0), fmt(rs$n, 0), flag))
  }
  cat(sprintf("  [k=%d] distinct CWSs in joined dose sample: %d, total obs: %d\n",
              kk, n_distinct(dat$PWSID), nrow(dat)))
}

cat("\nStars: *** p<0.01, ** p<0.05, * p<0.1. Coefficient units: mg/L per 10M short tons\n")
cat("cumulative upstream coal production since 1985. Estimator: OLS (not IV — see note above).\n")

# ---- Reproduction anchor check (k=1 vs published 6yr_huc02fe_inorg_ravalli_2005) ----
cat("\n---- Reproduction anchor (k=1, huc02^year FE) vs published table ----\n")
cat("Published (output/reg/6yr_huc02fe_inorg_ravalli_2005.tex):\n")
cat("  arsenic 0.0023*** (0.0004) | nitrate 0.0572 (0.0922) | barium 0.0171* (0.0093) | selenium 0.0033** (0.0016)\n")
cat("Exact equality not expected: step-grid linkage carries a documented CWS-count deviation\n")
cat("from the production sample (see .claude/logs/2026-09-13-instrument-step-grid.md).\n")
cat("Pass condition: same sign and rough magnitude, not exact match.\n")

cat("\nDone.\n")
