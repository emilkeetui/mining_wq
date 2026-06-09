# ============================================================
# Script: jackknife_state_snsv.r
# Purpose: Leave-one-state-out jackknife of the 2SLS sanitary-survey
#          effect reported in h2_snsv_d12.tex (any_snsv, 2SLS column),
#          to identify which states drive the result.
# Inputs:  clean_data/cws_data/prod_vio_sulfur_4step.parquet
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_SITE_VISITS.csv
# Outputs: output/fig/jackknife_state_snsv.png
#          output/fig/jackknife_state_map_snsv.png
# Author: EK  Date: 2026-06-06
# Note: any_snsv is NOT a column in the parquet — it is built here by merging
#       SDWA site-visit records, exactly as in enforcement_chain_d12.r (the
#       source of h2_snsv_d12.tex). The h2_snsv table uses the D1-D2 panel
#       (downstream_step <= 2) with num_coal_mines_upstream / sulfur_upstream,
#       which live in prod_vio_sulfur_4step.parquet.
# ============================================================

.libPaths("Z:/ek559/RPackages")
library(arrow)
library(data.table)
library(fixest)
library(dplyr)
library(ggplot2)

if (!require("sf", quietly = TRUE)) {
  install.packages("sf", repos = "https://cloud.r-project.org")
  library(sf)
}
if (!require("tigris", quietly = TRUE)) {
  install.packages("tigris", repos = "https://cloud.r-project.org")
  library(tigris)
}
options(tigris_use_cache = TRUE)

ROOT <- "Z:/ek559/mining_wq"
SDWA <- "Z:/ek559/sdwa_violations/SDWA_latest_downloads"
setwd(ROOT)

# ---- Build D1-D2 panel (same as h2_snsv_d12: panel from d12) ----
cat("Loading D1-D2 panel (prod_vio_sulfur_4step.parquet)...\n")
step4 <- arrow::read_parquet("clean_data/cws_data/prod_vio_sulfur_4step.parquet")
d12 <- step4[step4$downstream_step <= 2 &
             step4$year >= 1985 & step4$year <= 2005, ]
d12 <- d12[d12$PWSID != "WV3303401", ]
ids_d12 <- unique(d12$PWSID)
cat(sprintf("D1-D2 panel: %d PWSIDs x %d PWSID-years\n", length(ids_d12), nrow(d12)))
rm(step4); gc()

# ---- Merge site visits to build any_snsv (as in enforcement_chain_d12.r) ----
cat("Reading SDWA_SITE_VISITS.csv (355 MB, selected cols)...\n")
sv <- fread(file.path(SDWA, "SDWA_SITE_VISITS.csv"),
            select = c("PWSID", "VISIT_DATE", "VISIT_REASON_CODE"))
sv <- sv[PWSID %in% ids_d12]
sv[, year := as.integer(substr(trimws(VISIT_DATE),
                               nchar(trimws(VISIT_DATE)) - 3,
                               nchar(trimws(VISIT_DATE))))]
sv <- sv[!is.na(year) & year >= 1985 & year <= 2005]

sv_agg <- sv[, .(any_snsv = any(VISIT_REASON_CODE == "SNSV")), by = .(PWSID, year)]
rm(sv); gc()

panel <- d12 %>%
  left_join(as.data.frame(sv_agg), by = c("PWSID", "year"))
panel$any_snsv[is.na(panel$any_snsv)] <- FALSE
panel$any_snsv <- as.integer(panel$any_snsv)

sample <- panel
sample$state <- substr(sample$PWSID, 1, 2)
sample <- sample[!is.na(sample$sulfur_upstream) & !is.na(sample$post95), ]
cat(sprintf("Panel: %d obs; any_snsv = 1 in %d (%.1f%%)\n",
            nrow(sample), sum(sample$any_snsv), 100 * mean(sample$any_snsv)))

# ---- Filter out states with too few observations ----
state_counts <- table(sample$state)
sparse_states <- names(state_counts[state_counts < 30])
if (length(sparse_states) > 0) {
  cat("Dropping sparse states (< 30 obs): ", paste(sparse_states, collapse = ", "), "\n")
  sample <- sample[!(sample$state %in% sparse_states), ]
}
cat(sprintf("After sparse filter: %d obs, %d states\n\n",
            nrow(sample), length(unique(sample$state))))

# ---- IV regression helper (matches iv_b in enforcement_chain_d12.r) ----
run_iv_snsv <- function(data) {
  tryCatch({
    fit <- feols(
      any_snsv ~ num_facilities |
        PWSID + year + STATE_CODE |
        num_coal_mines_upstream ~ post95:sulfur_upstream,
      data = data,
      cluster = ~ PWSID
    )

    coef_vec <- coef(fit)
    se_vec <- se(fit)

    coef_name <- "fit_num_coal_mines_upstream"
    if (!(coef_name %in% names(coef_vec))) {
      alt_names <- names(coef_vec)[grepl("num_coal_mines_upstream", names(coef_vec))]
      if (length(alt_names) > 0) coef_name <- alt_names[1]
      else stop("Could not find coefficient for num_coal_mines_upstream")
    }

    beta <- as.numeric(coef_vec[coef_name])
    se_val <- as.numeric(se_vec[coef_name])
    if (is.na(beta) || is.na(se_val)) stop("Beta or SE is NA")

    ci_lo <- beta - 1.96 * se_val
    ci_hi <- beta + 1.96 * se_val
    n_obs_val <- nobs(fit)

    fstat_first <- NA
    tryCatch({
      fs <- fitstat(fit, "ivf")
      if (!is.null(fs) && length(fs) > 0) fstat_first <- as.numeric(fs[[1]]$stat)
    }, error = function(e) NULL)

    list(beta = beta, se = se_val, ci_lo = ci_lo, ci_hi = ci_hi,
         fstat_first = fstat_first, n_obs = n_obs_val)
  }, error = function(e) {
    cat("ERROR in run_iv_snsv:", e$message, "\n")
    list(beta = NA_real_, se = NA_real_, ci_lo = NA_real_, ci_hi = NA_real_,
         fstat_first = NA_real_, n_obs = NA_integer_)
  })
}

# ---- Full-sample estimate ----
cat("Estimating full-sample 2SLS for any_snsv (D1-D2)...\n")
full_est <- run_iv_snsv(sample)
cat(sprintf("Beta: %.4f (SE: %.4f)  95%% CI: [%.4f, %.4f]\n",
            full_est[["beta"]], full_est[["se"]], full_est[["ci_lo"]], full_est[["ci_hi"]]))
cat(sprintf("First-stage F: %.2f  N: %d\n\n", full_est[["fstat_first"]], full_est[["n_obs"]]))

# ---- Jackknife loop ----
cat("Running jackknife (leave-one-state-out)...\n")
states_in_sample <- sort(unique(sample$state))
results <- lapply(states_in_sample, function(s) {
  sub <- sample[sample$state != s, ]
  row_list <- run_iv_snsv(sub)
  data.frame(
    state_excluded = s,
    beta = row_list[["beta"]], se = row_list[["se"]],
    ci_lo = row_list[["ci_lo"]], ci_hi = row_list[["ci_hi"]],
    fstat_first = row_list[["fstat_first"]], n_obs = row_list[["n_obs"]],
    n_obs_excl = nrow(sub), stringsAsFactors = FALSE
  )
})
jk <- dplyr::bind_rows(results)
jk$delta_beta <- full_est[["beta"]] - jk$beta

cat("Jackknife results:\n")
print(jk[, c("state_excluded", "beta", "se", "delta_beta", "fstat_first")], digits = 4)
cat("\n")

# ---- Caterpillar plot ----
cat("Generating caterpillar plot...\n")
jk_sorted <- jk[order(jk$beta), ]
jk_sorted$state_excluded <- factor(jk_sorted$state_excluded, levels = jk_sorted$state_excluded)
jk_sorted$sig <- (jk_sorted$ci_lo > 0) | (jk_sorted$ci_hi < 0)

p_cat <- ggplot(jk_sorted, aes(x = beta, y = state_excluded)) +
  geom_pointrange(aes(xmin = ci_lo, xmax = ci_hi, color = sig, fill = sig),
                  shape = 21, size = 3.5, linewidth = 0.8) +
  scale_color_manual(values = c("FALSE" = "grey50", "TRUE" = "#d62728"), guide = "none") +
  scale_fill_manual(values = c("FALSE" = "white", "TRUE" = "#d62728"), guide = "none") +
  geom_vline(xintercept = full_est[["beta"]], linetype = "dashed",
             color = "#d62728", linewidth = 0.9, alpha = 0.7) +
  annotate("text", x = full_est[["beta"]], y = 0.5,
           label = sprintf("Full: %.4f", full_est[["beta"]]),
           hjust = -0.1, vjust = -0.5, size = 3.5, color = "#d62728") +
  theme_classic(base_size = 11) +
  labs(
    x = "β̂: Δ Pr(sanitary survey) per upstream coal mine",
    y = "State excluded",
    title = "Leave-one-state-out sensitivity: Sanitary survey (h2_snsv_d12)",
    caption = paste0(
      "β̂ = 2SLS coefficient on num_coal_mines_upstream: effect of one more\n",
      "upstream mine on the probability of a sanitary survey (D1-D2 sample).\n",
      sprintf("Each dot is β̂ re-estimated with that state dropped; dashed red line is full-sample β̂ = %.4f.\n", full_est[["beta"]]),
      "Solid red = significantly different from zero at 95%. Hollow = includes zero in 95% CI."
    )
  ) +
  theme(plot.caption = element_text(hjust = 0, size = 9),
        plot.title = element_text(hjust = 0, face = "bold", size = 12))

n_states <- length(unique(jk$state_excluded))
ggsave("output/fig/jackknife_state_snsv.png",
       p_cat, width = 6.5, height = 0.4 * n_states + 2.5, dpi = 300)
cat("Saved: output/fig/jackknife_state_snsv.png\n")

# ---- Δβ choropleth ----
cat("Generating choropleth map...\n")
states_sf <- tigris::states(cb = TRUE, resolution = "20m", year = 2020) |>
  dplyr::filter(!STUSPS %in% c("AK", "HI", "PR", "VI", "GU", "MP", "AS"))
map_data <- dplyr::left_join(states_sf, jk, by = c("STUSPS" = "state_excluded"))

p_map <- ggplot(map_data) +
  geom_sf(aes(fill = delta_beta), color = "grey40", linewidth = 0.2) +
  scale_fill_gradient2(
    low = "#2166ac", mid = "white", high = "#d73027", midpoint = 0,
    na.value = "grey85",
    name = "Δβ\nβ̂_full − β̂_(excl. state)",
    limits = c(-max(abs(jk$delta_beta), na.rm = TRUE),
               max(abs(jk$delta_beta), na.rm = TRUE))
  ) +
  theme_void(base_size = 11) +
  labs(
    title = "Leave-one-state-out Δβ: Sanitary survey (h2_snsv_d12)",
    subtitle = sprintf("β = 2SLS effect of one additional upstream coal mine on Pr(sanitary survey); full-sample β̂ = %.4f (N=%d PWSID×year, D1-D2)",
                       full_est[["beta"]], full_est[["n_obs"]]),
    caption = paste0(
      "β is the 2SLS coefficient on num_coal_mines_upstream: the change in the probability of a sanitary survey\n",
      "per additional upstream coal mine. Δβ = β̂_full − β̂_(state excluded) is how much that coefficient moves when a state's data is dropped.\n",
      "Red (positive Δβ) = the state was inflating the effect. Blue (negative Δβ) = the state was suppressing it. Grey = state not in the D1-D2 sample."
    )
  ) +
  theme(
    plot.title = element_text(hjust = 0.5, face = "bold", size = 12),
    plot.subtitle = element_text(hjust = 0.5, size = 9),
    plot.caption = element_text(hjust = 0, size = 9),
    legend.position = "right"
  )

ggsave("output/fig/jackknife_state_map_snsv.png",
       p_map, width = 10, height = 5.5, dpi = 300)
cat("Saved: output/fig/jackknife_state_map_snsv.png\n")

# ---- Summary ----
cat("\n=== JACKKNIFE SUMMARY: any_snsv (D1-D2) ===\n")
cat(sprintf("Full-sample β̂: %.4f  SE: %.4f  95%% CI: [%.4f, %.4f]\n",
            full_est[["beta"]], full_est[["se"]], full_est[["ci_lo"]], full_est[["ci_hi"]]))
cat(sprintf("First-stage F: %.2f  N obs: %d\n", full_est[["fstat_first"]], full_est[["n_obs"]]))
cat(sprintf("States in jackknife: %d\n", nrow(jk)))
cat(sprintf("Range of leave-one-out β̂: [%.4f, %.4f]\n", min(jk$beta, na.rm = TRUE), max(jk$beta, na.rm = TRUE)))
cat(sprintf("Max |Δβ|: %.4f (state: %s)\n", max(abs(jk$delta_beta), na.rm = TRUE),
            jk$state_excluded[which.max(abs(jk$delta_beta))]))
cat("\nFigures saved to output/fig/\n")
