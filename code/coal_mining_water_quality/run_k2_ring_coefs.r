# ============================================================
# Script: run_k2_ring_coefs.r
# Purpose: Coefficients on three mine-exposure definitions estimated on the
#          SAME k=2 utility sample: mines within two flow steps upstream
#          (k2), mines exactly two flow steps upstream (ring 2), and mines
#          two or three flow steps upstream (ring 2-3). 2SLS (SYR2: OLS on
#          annual production). Writes a tidy parquet for plot_k2_ring_coefs.r.
# Inputs:
#   clean_data/cws_data/step_instruments.parquet (via k2_common.r)
#   clean_data/cws_data/cws_covariates_steps.parquet (via k2_common.r)
#   clean_data/cws_data/sdwa_vio_agg_steps.parquet (via k2_common.r)
#   clean_data/cws_data/sdwa_visit_agg_k2.parquet (via k2_common.r)
#   clean_data/cws_data/sdwa_enf_agg_k2.parquet (via k2_common.r)
#   clean_data/cws_6year_review_ravalli.parquet
#   clean_data/cws_data/pwsid_huc02.parquet
# Outputs:
#   clean_data/cws_data/k2_ring_coefs.parquet
# Author: EK  Date: 2026-10-15
# ============================================================

source("Z:/ek559/mining_wq/code/coal_mining_water_quality/k2_common.r")
stopifnot(WQ_SAMPLE == "k2")
library(tidyr)

out_path <- file.path(ROOT, "clean_data/cws_data/k2_ring_coefs.parquet")
if (file.exists(out_path)) cat("WARNING:", out_path, "already exists -- overwriting\n")

# ── 1. k2 estimation sample (identical to run_k2_main_tables.r:30-46) ──────
main_dat <- build_k2_panel("main")
lone_states <- main_dat %>%
  dplyr::filter(!is.na(STATE_CODE)) %>%
  dplyr::group_by(STATE_CODE) %>%
  dplyr::summarise(n_util = dplyr::n_distinct(PWSID), .groups = "drop") %>%
  dplyr::filter(n_util == 1) %>%
  dplyr::pull(STATE_CODE)
n_util_before <- dplyr::n_distinct(main_dat$PWSID); n_obs_before <- nrow(main_dat)
main_dat <- main_dat %>% dplyr::filter(!is.na(STATE_CODE), !(STATE_CODE %in% lone_states))
cat(sprintf("Stable-sample screen: dropped %d utilities / %d obs\n",
            n_util_before - dplyr::n_distinct(main_dat$PWSID), n_obs_before - nrow(main_dat)))
cat(sprintf("k2 sample: %d rows, %d utilities\n", nrow(main_dat), dplyr::n_distinct(main_dat$PWSID)))
stopifnot(nrow(main_dat) >= 1000)

# ── 2. Ring exposures from cumulative k=1..3 rows ───────────────────────────
si <- read_parquet(file.path(ROOT, "clean_data/cws_data/step_instruments.parquet"))
stopifnot(is.character(si$PWSID))

ring_wide <- si %>%
  dplyr::filter(arm == "main", k %in% 1:3) %>%
  dplyr::select(PWSID, year, k, num_coal_mines_linked_sum, production_linked_sum,
                n_hucs_linked, sulfur_mean0) %>%
  dplyr::mutate(dplyr::across(c(num_coal_mines_linked_sum, production_linked_sum,
                                n_hucs_linked, sulfur_mean0), ~ tidyr::replace_na(.x, 0))) %>%
  tidyr::pivot_wider(names_from = k, values_from = c(num_coal_mines_linked_sum,
                       production_linked_sum, n_hucs_linked, sulfur_mean0),
                     names_sep = "_")

# Ring sulfur recovered from cumulative sums: (n_b*s_b - n_a*s_a)/(n_b - n_a), 0 if no ring HUC.
ring_sulfur <- function(n_b, s_b, n_a, s_a) {
  ifelse(n_b > n_a, (n_b * s_b - n_a * s_a) / (n_b - n_a), 0)
}
ring_wide <- ring_wide %>%
  dplyr::mutate(
    mines_ring2      = num_coal_mines_linked_sum_2 - num_coal_mines_linked_sum_1,
    mines_ring23     = num_coal_mines_linked_sum_3 - num_coal_mines_linked_sum_1,
    sulfur_ring2     = ring_sulfur(n_hucs_linked_2, sulfur_mean0_2, n_hucs_linked_1, sulfur_mean0_1),
    sulfur_ring23    = ring_sulfur(n_hucs_linked_3, sulfur_mean0_3, n_hucs_linked_1, sulfur_mean0_1),
    prod_ring2_1mst  = (production_linked_sum_2 - production_linked_sum_1) / 1e6,
    prod_ring23_1mst = (production_linked_sum_3 - production_linked_sum_1) / 1e6
  ) %>%
  dplyr::select(PWSID, year, num_coal_mines_linked_sum_2, mines_ring2, mines_ring23,
                sulfur_ring2, sulfur_ring23, prod_ring2_1mst, prod_ring23_1mst)

ring_vars <- c("mines_ring2", "mines_ring23", "sulfur_ring2", "sulfur_ring23",
               "prod_ring2_1mst", "prod_ring23_1mst")
stopifnot(!anyNA(ring_wide[ring_vars]), all(ring_wide[ring_vars] >= -1e-9))

dat <- main_dat %>% dplyr::left_join(ring_wide, by = c("PWSID", "year"))
stopifnot(nrow(dat) == nrow(main_dat), !anyNA(dat[ring_vars]),
          isTRUE(all.equal(dat$num_coal_mines_linked_sum_2, dat$num_coal_mines_linked_sum)))
cat(sprintf("Utilities ever exposed: ring2 %d, ring23 %d\n",
            dplyr::n_distinct(dat$PWSID[dat$mines_ring2 > 0]),
            dplyr::n_distinct(dat$PWSID[dat$mines_ring23 > 0])))

# ── 3. Series and outcome specs ─────────────────────────────────────────────
series_spec <- data.frame(
  series = c("k2", "ring2", "ring23"),
  endog  = c("num_coal_mines_linked_sum", "mines_ring2", "mines_ring23"),
  instr  = c("sulfur_mean0", "sulfur_ring2", "sulfur_ring23"),
  label  = c("Within two watersheds upstream", "Exactly two watersheds upstream",
             "Two to three watersheds upstream"),
  stringsAsFactors = FALSE
)
families <- list(
  mr    = c("arsenic_MR_bin", "nitrates_MR_bin", "inorganic_chemicals_MR_bin"),
  mcl   = c("arsenic_MCL_bin", "nitrates_MCL_bin", "inorganic_chemicals_MCL_bin"),
  visit = c("any_snsv", "any_tech", "any_enfvisit", "any_smpl", "any_insp"),
  enf   = c("any_informal", "any_formal", "no_enf")
)
fe_str <- "PWSID + STATE_CODE^year"

# Clustered first-stage F on the series-specific instrument (as f_clustered, k2_common.r:254).
fs_f_clustered <- function(d, fe, endog, instr) {
  term <- paste0("post95:", instr)
  fs <- tryCatch(
    fixest::feols(as.formula(paste0(endog, " ~ ", term, " + num_facilities | ", fe)),
                  data = d, cluster = ~PWSID, warn = FALSE, notes = FALSE),
    error = function(e) NULL)
  if (is.null(fs) || !(term %in% names(coef(fs)))) return(NA_real_)
  round((coef(fs)[term] / fixest::se(fs)[term])^2, 2)
}

rows <- list()
for (fam in names(families)) for (y in families[[fam]]) {
  d_y <- dat[!is.na(dat[[y]]), ]
  for (i in seq_len(nrow(series_spec))) {
    s <- series_spec[i, ]
    fml <- as.formula(paste0(y, " ~ num_facilities | ", fe_str, " | ", s$endog, " ~ post95:", s$instr))
    m <- fixest::feols(fml, data = d_y, cluster = ~PWSID, warn = FALSE, notes = FALSE)
    tm <- get_term(m, s$endog)
    rows[[length(rows) + 1]] <- data.frame(
      family = fam, outcome = y, outcome_label = unname(k2_dict[y]),
      series = s$series, series_label = s$label,
      coef = unname(tm$est), se = unname(tm$se), pval = unname(tm$pval),
      n_obs = nobs(m), n_utils = length(fixest::fixef(m)$PWSID),
      fs_f = unname(fs_f_clustered(d_y, fe_str, s$endog, s$instr)),
      stringsAsFactors = FALSE)
    cat(sprintf("%-6s %-28s %-7s coef %8.3f se %7.3f F %6.2f\n", fam, y, s$series,
                tm$est, tm$se, rows[[length(rows)]]$fs_f))
  }
}

# ── 4. SYR2 block: OLS on annual production (setup from run_k2_6yr_annprod_ab.r) ──
d6r <- read_parquet(file.path(ROOT, "clean_data/cws_6year_review_ravalli.parquet"))
stopifnot(is.character(d6r$PWSID))
d6r <- d6r %>% dplyr::filter(year >= 1985, PWSID != "WV3303401")
huc02_lookup <- read_parquet(file.path(ROOT, "clean_data/cws_data/pwsid_huc02.parquet"))
stopifnot(is.character(huc02_lookup$PWSID))
d6r <- d6r %>% dplyr::left_join(huc02_lookup %>% dplyr::select(PWSID, huc02), by = "PWSID")

CHEMS <- c("arsenic", "nitrate", "barium", "selenium")
nice_chem <- c(arsenic = "Arsenic", nitrate = "Nitrate", barium = "Barium", selenium = "Selenium")

arm_k <- si %>% dplyr::filter(arm == "main", k == 2, n_mine_hucs_linked >= 1) %>%
  apply_a2() %>%
  dplyr::select(PWSID, year, production_linked_sum)
dose_panel <- arm_k %>%
  dplyr::distinct(PWSID, year, production_linked_sum) %>%
  dplyr::mutate(prod_k2_1mst = replace(production_linked_sum, is.na(production_linked_sum), 0) / 1e6) %>%
  dplyr::select(PWSID, year, prod_k2_1mst) %>%
  dplyr::left_join(ring_wide %>% dplyr::select(PWSID, year, prod_ring2_1mst, prod_ring23_1mst),
                   by = c("PWSID", "year"))
stopifnot(!anyNA(dose_panel))
b_df <- d6r %>%
  dplyr::filter(PWSID %in% unique(arm_k$PWSID), CHEMID_name %in% CHEMS) %>%
  dplyr::inner_join(dose_panel, by = c("PWSID", "year"))
b_df <- b_df[!is.na(b_df$VALUE) & b_df$year <= 2005, ]
cat(sprintf("SYR2 Panel B: %d rows, %d utilities\n", nrow(b_df), dplyr::n_distinct(b_df$PWSID)))
stopifnot(nrow(b_df) >= 100)

syr2_spec <- data.frame(series = series_spec$series, dose = c("prod_k2_1mst", "prod_ring2_1mst", "prod_ring23_1mst"),
                        label = series_spec$label, stringsAsFactors = FALSE)
for (chem in CHEMS) {
  d_chem <- b_df[b_df$CHEMID_name == chem, ]
  for (i in seq_len(nrow(syr2_spec))) {
    s <- syr2_spec[i, ]
    fml <- as.formula(paste0("VALUE ~ ", s$dose, " + num_facilities | PWSID + huc02^year"))
    m <- fixest::feols(fml, data = d_chem, cluster = ~PWSID, warn = FALSE, notes = FALSE)
    tm <- get_term(m, s$dose)
    rows[[length(rows) + 1]] <- data.frame(
      family = "syr2", outcome = chem, outcome_label = unname(nice_chem[chem]),
      series = s$series, series_label = s$label,
      coef = unname(tm$est), se = unname(tm$se), pval = unname(tm$pval),
      n_obs = m$nobs, n_utils = length(fixest::fixef(m)$PWSID), fs_f = NA_real_,
      stringsAsFactors = FALSE)
    cat(sprintf("syr2   %-10s %-7s coef %9.5f se %8.5f\n", chem, s$series, tm$est, tm$se))
  }
}

res <- dplyr::bind_rows(rows)

# ── 5. Anchor gates: k2 series must reproduce the existing k2 tables ────────
# Targets read off the 2SLS state x year columns of output/reg/
# 2sls_dwnstrm_minevio_{mr,mcl}_ivsum_binvio_k2.tex, h2_snsv_d12_k2.tex,
# h3_inf_formal_d12_k2.tex, and Panel B of 6yr_huc02fe_inorg_ravalli_2005_annprod_ab.tex.
anchors <- c(
  nitrates_MR_bin = 3.94, arsenic_MR_bin = 3.78, inorganic_chemicals_MR_bin = 3.06,
  nitrates_MCL_bin = -0.11, arsenic_MCL_bin = 0.22, inorganic_chemicals_MCL_bin = -0.20,
  any_snsv = 0.78, any_tech = 0.67, any_enfvisit = 1.07, any_smpl = 0.48, any_insp = 2.13,
  any_informal = -0.71, any_formal = -1.08, no_enf = -0.42
)
k2_rows <- res[res$series == "k2" & res$family != "syr2", ]
for (v in names(anchors)) {
  got <- k2_rows$coef[match(v, k2_rows$outcome)]
  if (abs(round(got, 2) - anchors[[v]]) > 0.005 + 1e-9)
    stop(sprintf("Anchor mismatch %s: got %.4f, table %.2f", v, got, anchors[[v]]))
}
anchors_syr2 <- c(arsenic = 0.0004, nitrate = 0.0610, barium = 0.0137, selenium = 0.0004)
for (v in names(anchors_syr2)) {
  got <- res$coef[res$family == "syr2" & res$series == "k2" & res$outcome == v]
  if (abs(round(got, 4) - anchors_syr2[[v]]) > 5e-5 + 1e-12)
    stop(sprintf("SYR2 anchor mismatch %s: got %.5f, table %.4f", v, got, anchors_syr2[[v]]))
}
iv_f <- res$fs_f[res$family != "syr2"]
stopifnot(!anyNA(iv_f), all(iv_f > 10))
cat("Anchor gates and F > 10 gate passed.\n")

# ── 6. Write ───────────────────────────────────────────────────────────────
res$n_obs <- as.integer(res$n_obs); res$n_utils <- as.integer(res$n_utils)
str(res)
write_parquet(res, out_path)
chk <- read_parquet(out_path)
cat(sprintf("Written %d rows x %d cols to %s\n", nrow(chk), ncol(chk), out_path))
stopifnot(nrow(chk) == (3 + 3 + 5 + 3 + 4) * 3)
