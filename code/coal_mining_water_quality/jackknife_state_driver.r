# ============================================================
# Script: jackknife_state_driver.r
# Purpose: Leave-one-state-out jackknife of 2SLS effect to identify
#          which states drive the inorganic chemicals MR violation result
# Inputs:  clean_data/cws_data/prod_vio_sulfur.parquet
# Outputs: output/fig/jackknife_state_caterpillar.png
#          output/fig/jackknife_state_map.png
# Author: EK  Date: 2026-06-06
# ============================================================

library(arrow)
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

# ---- Load and filter data ----
df <- arrow::read_parquet("clean_data/cws_data/prod_vio_sulfur.parquet")
df <- df[df$PWSID != "WV3303401", ]

sample <- df |>
  dplyr::filter(
    minehuc_downstream_of_mine == 1,
    minehuc_mine == 0,
    year >= 1985, year <= 2005,
    !is.na(sulfur_unified_sum),
    !is.na(post95)
  )

sample$state <- substr(sample$PWSID, 1, 2)

cat("Sample loaded: ", nrow(sample), " obs\n")
cat("Unique states: ", length(unique(sample$state)), "\n")

# ---- Filter out states with too few observations ----
state_counts <- table(sample$state)
sparse_states <- names(state_counts[state_counts < 30])
if (length(sparse_states) > 0) {
  cat("Dropping sparse states (< 30 obs): ", paste(sparse_states, collapse = ", "), "\n")
  sample <- sample[!(sample$state %in% sparse_states), ]
}

cat("After sparse filter: ", nrow(sample), " obs, ", length(unique(sample$state)), " states\n\n")

# ---- IV regression helper ----
run_iv <- function(data) {
  tryCatch({
    fit <- feols(
      inorganic_chemicals_MR_share_days ~ num_facilities |
        PWSID + year |
        num_coal_mines_upstream_sum ~ post95:sulfur_unified_sum,
      data = data,
      cluster = ~ PWSID
    )

    coef_vec <- coef(fit)
    se_vec <- se(fit)

    # Debug: print what coefficients we have
    # cat("Coef names:", names(coef_vec), "\n")

    # Extract the IV coefficient (should be "fit_num_coal_mines_upstream_sum")
    coef_name <- "fit_num_coal_mines_upstream_sum"
    if (!(coef_name %in% names(coef_vec))) {
      # Try alternate name patterns
      alt_names <- names(coef_vec)[grepl("num_coal_mines_upstream_sum", names(coef_vec))]
      if (length(alt_names) > 0) {
        coef_name <- alt_names[1]
      } else {
        stop("Could not find coefficient for num_coal_mines_upstream_sum")
      }
    }

    beta <- as.numeric(coef_vec[coef_name])
    se_val <- as.numeric(se_vec[coef_name])

    if (is.na(beta) || is.na(se_val)) {
      stop("Beta or SE is NA")
    }

    ci_lo <- beta - 1.96 * se_val
    ci_hi <- beta + 1.96 * se_val
    n_obs_val <- nobs(fit)

    # First-stage F — optional detail, not critical for jackknife
    fstat_first <- NA
    tryCatch({
      fs <- fitstat(fit, "ivf")
      if (!is.null(fs) && length(fs) > 0) {
        fstat_first <- as.numeric(fs[[1]]$stat)
      }
    }, error = function(e) NULL)

    list(
      beta = beta,
      se = se_val,
      ci_lo = ci_lo,
      ci_hi = ci_hi,
      fstat_first = fstat_first,
      n_obs = n_obs_val
    )
  }, error = function(e) {
    cat("ERROR in run_iv:", e$message, "\n")
    list(
      beta = NA_real_,
      se = NA_real_,
      ci_lo = NA_real_,
      ci_hi = NA_real_,
      fstat_first = NA_real_,
      n_obs = NA_integer_
    )
  })
}

# ---- Full-sample estimate ----
cat("Estimating full-sample 2SLS...\n")
full_est <- run_iv(sample)
cat(sprintf("Beta: %.4f (SE: %.4f)  95%% CI: [%.4f, %.4f]\n",
            full_est[["beta"]], full_est[["se"]], full_est[["ci_lo"]], full_est[["ci_hi"]]))
cat(sprintf("First-stage F: %.2f  N: %d\n\n", full_est[["fstat_first"]], full_est[["n_obs"]]))

# ---- Jackknife loop ----
cat("Running jackknife (leave-one-state-out)...\n")
states_in_sample <- sort(unique(sample$state))

results <- lapply(states_in_sample, function(s) {
  sub <- sample[sample$state != s, ]
  row_list <- run_iv(sub)
  # Convert to data.frame row
  data.frame(
    state_excluded = s,
    beta = row_list[["beta"]],
    se = row_list[["se"]],
    ci_lo = row_list[["ci_lo"]],
    ci_hi = row_list[["ci_hi"]],
    fstat_first = row_list[["fstat_first"]],
    n_obs = row_list[["n_obs"]],
    n_obs_excl = nrow(sub),
    stringsAsFactors = FALSE
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
jk_sorted$state_excluded <- factor(jk_sorted$state_excluded,
                                    levels = jk_sorted$state_excluded)
jk_sorted$sig <- (jk_sorted$ci_lo > 0) | (jk_sorted$ci_hi < 0)

p_cat <- ggplot(jk_sorted, aes(x = beta, y = state_excluded)) +
  geom_pointrange(aes(xmin = ci_lo, xmax = ci_hi, color = sig, fill = sig),
                  shape = 21, size = 3.5, linewidth = 0.8) +
  scale_color_manual(values = c("FALSE" = "grey50", "TRUE" = "#d62728"),
                     guide = "none") +
  scale_fill_manual(values = c("FALSE" = "white", "TRUE" = "#d62728"),
                    guide = "none") +
  geom_vline(xintercept = full_est[["beta"]], linetype = "dashed",
             color = "#d62728", linewidth = 0.9, alpha = 0.7) +
  annotate("text", x = full_est[["beta"]], y = 0.5,
           label = sprintf("Full: %.2f", full_est[["beta"]]),
           hjust = -0.1, vjust = -0.5, size = 3.5, color = "#d62728") +
  theme_classic(base_size = 11) +
  labs(
    x = "β̂: Days/year MR violation per upstream coal mine",
    y = "State excluded",
    title = "Leave-one-state-out sensitivity: Inorganic chemicals MR violations",
    caption = paste0(
      "β̂ = 2SLS coefficient on num_coal_mines_upstream_sum: effect of one more\n",
      "upstream mine on days/year of inorganic-chemicals MR violations.\n",
      sprintf("Each dot is β̂ re-estimated with that state dropped; dashed red line is full-sample β̂ = %.2f.\n", full_est[["beta"]]),
      "Solid red = significantly different from zero at 95%. Hollow = includes zero in 95% CI."
    )
  ) +
  theme(plot.caption = element_text(hjust = 0, size = 9),
        plot.title = element_text(hjust = 0, face = "bold", size = 12))

n_states <- length(unique(jk$state_excluded))
ggsave("output/fig/jackknife_state_caterpillar.png",
       p_cat, width = 6.5, height = 0.4 * n_states + 2.5, dpi = 300)
cat("Saved: output/fig/jackknife_state_caterpillar.png\n")

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
    name = "Δβ (days/yr)\nβ̂_full − β̂_(excl. state)",
    limits = c(-max(abs(jk$delta_beta), na.rm = TRUE),
               max(abs(jk$delta_beta), na.rm = TRUE))
  ) +
  theme_void(base_size = 11) +
  labs(
    title = "Leave-one-state-out Δβ: Inorganic chemicals MR violations",
    subtitle = sprintf("β = 2SLS effect of one additional upstream coal mine on days/year of inorganic MR violations; full-sample β̂ = %.2f (N=%d PWSID×year)",
                       full_est[["beta"]], full_est[["n_obs"]]),
    caption = paste0(
      "β is the 2SLS coefficient on num_coal_mines_upstream_sum: the change in days/year of inorganic-chemicals MR violations\n",
      "per additional upstream coal mine. Δβ = β̂_full − β̂_(state excluded) is how much that coefficient moves when a state's data is dropped.\n",
      "Red (positive Δβ) = the state was inflating the effect (dropping it lowers β̂). Blue (negative Δβ) = the state was suppressing it.\n",
      "Grey = state not in the downstream sample."
    )
  ) +
  theme(
    plot.title = element_text(hjust = 0.5, face = "bold", size = 12),
    plot.caption = element_text(hjust = 0, size = 9),
    legend.position = "right"
  )

ggsave("output/fig/jackknife_state_map.png",
       p_map, width = 10, height = 5.5, dpi = 300)
cat("Saved: output/fig/jackknife_state_map.png\n")

# ---- Summary ----
cat("\n=== JACKKNIFE SUMMARY ===\n")
cat(sprintf("Full-sample β̂: %.4f  SE: %.4f  95%% CI: [%.4f, %.4f]\n",
            full_est[["beta"]], full_est[["se"]], full_est[["ci_lo"]], full_est[["ci_hi"]]))
cat(sprintf("First-stage F: %.2f  N obs: %d\n", full_est[["fstat_first"]], full_est[["n_obs"]]))
cat(sprintf("States in jackknife: %d\n", nrow(jk)))
cat(sprintf("Range of leave-one-out β̂: [%.4f, %.4f]\n", min(jk$beta), max(jk$beta)))
cat(sprintf("Max |Δβ|: %.4f (state: %s)\n", max(abs(jk$delta_beta)),
            jk$state_excluded[which.max(abs(jk$delta_beta))]))
cat("\nFigures saved to output/fig/\n")
