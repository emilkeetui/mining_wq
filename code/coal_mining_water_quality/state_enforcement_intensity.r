# ============================================================
# Script: state_enforcement_intensity.r
# Purpose: Step 1-2 of the enforcement-intensity check. Build a state-level
#          formal-enforcement-per-violation measure (lambda-hat_s) and locate
#          PA's rank/percentile, both among all states and among the states
#          that identify the downstream inorganic-MR 2SLS.
# Inputs:  Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.csv
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_PUB_WATER_SYSTEMS.csv
#          clean_data/cws_data/prod_vio_sulfur.parquet   (downstream-sample states)
# Outputs: output/sum/state_enforcement_intensity.csv
#          output/fig/state_enforcement_intensity.png
# Author: EK  Date: 2026-06-06
# Definition: lambda-hat_s = (distinct violations escalated to a Formal enforcement
#             action) / (distinct violations), by state. Measures regulator
#             stringency per violation -- the empirical analog of lambda in
#             theoreticalmodel.md Prop 3. Computed over community water systems only.
# ============================================================

.libPaths("Z:/ek559/RPackages")
library(arrow)
library(data.table)
library(ggplot2)

ROOT <- "Z:/ek559/mining_wq"
SDWA <- "Z:/ek559/sdwa_violations/SDWA_latest_downloads"
setwd(ROOT)

MIN_VIOL <- 100  # min distinct violations for a state to enter the ranking

# ---- CWS universe ----
cat("Loading CWS PWSIDs...\n")
pws <- fread(file.path(SDWA, "SDWA_PUB_WATER_SYSTEMS.csv"),
             select = c("PWSID", "PWS_TYPE_CODE"))
cws_ids <- unique(pws[PWS_TYPE_CODE == "CWS", PWSID])
cat(sprintf("CWS PWSIDs: %d\n", length(cws_ids)))

# ---- Downstream-sample states (the states that identify the MR result) ----
df <- arrow::read_parquet("clean_data/cws_data/prod_vio_sulfur.parquet")
dsamp <- df[df$minehuc_downstream_of_mine == 1 & df$minehuc_mine == 0 &
            df$year >= 1985 & df$year <= 2005 & df$PWSID != "WV3303401", ]
dstates <- sort(unique(substr(dsamp$PWSID, 1, 2)))
cat(sprintf("Downstream-sample states (%d): %s\n", length(dstates), paste(dstates, collapse = ", ")))

# ---- Enforcement / violations ----
cat("Reading SDWA_VIOLATIONS_ENFORCEMENT.csv (3.7 GB, selected cols)...\n")
enf <- fread(file.path(SDWA, "SDWA_VIOLATIONS_ENFORCEMENT.csv"),
             select = c("PWSID", "VIOLATION_ID", "COMPL_PER_BEGIN_DATE",
                        "VIOLATION_CATEGORY_CODE", "ENF_ACTION_CATEGORY"))
enf <- enf[PWSID %in% cws_ids]
enf[, year := as.integer(substr(trimws(COMPL_PER_BEGIN_DATE),
                                nchar(trimws(COMPL_PER_BEGIN_DATE)) - 3,
                                nchar(trimws(COMPL_PER_BEGIN_DATE))))]
enf <- enf[!is.na(year) & year >= 1985 & year <= 2005]
enf[, state := substr(PWSID, 1, 2)]
cat(sprintf("CWS enforcement/violation rows 1985-2005: %d\n", nrow(enf)))

# ---- Collapse to distinct violation: did it get a Formal action? ----
viol <- enf[, .(any_formal = any(ENF_ACTION_CATEGORY == "Formal", na.rm = TRUE),
                year = year[1], state = state[1],
                viol_cat = VIOLATION_CATEGORY_CODE[1]),
            by = .(PWSID, VIOLATION_ID)]
cat(sprintf("Distinct CWS violations: %d (formal-escalated: %d, %.2f%%)\n",
            nrow(viol), sum(viol$any_formal), 100 * mean(viol$any_formal)))

# ---- State-level lambda-hat (full period + pre-1995 robustness) ----
state_lambda <- function(vtab) {
  vtab[, .(n_viol = .N,
           n_formal = sum(any_formal),
           lambda = mean(any_formal)), by = state][order(-lambda)]
}
lam_all  <- state_lambda(viol)
lam_pre  <- state_lambda(viol[year < 1995])

lam_all <- lam_all[n_viol >= MIN_VIOL]
lam_all[, in_downstream := state %in% dstates]
lam_all[, pre95_lambda := lam_pre$lambda[match(state, lam_pre$state)]]

# ---- PA percentile ----
pct <- function(tab) {
  pa <- tab[state == "PA", lambda]
  if (length(pa) == 0) return(NA_real_)
  100 * mean(tab$lambda < pa)  # share of states strictly more lenient than PA
}
pa_pct_all  <- pct(lam_all)
pa_pct_down <- pct(lam_all[in_downstream == TRUE])
pa_rank_all  <- which(lam_all[order(lambda)]$state == "PA")
n_all        <- nrow(lam_all)
pa_lambda    <- lam_all[state == "PA", lambda]

cat("\n================ STATE FORMAL-ENFORCEMENT INTENSITY (lambda-hat) ================\n")
cat(sprintf("(states with >= %d distinct CWS violations; sorted low->high lambda)\n\n", MIN_VIOL))
print(lam_all[order(lambda),
              .(state, n_viol, n_formal,
                lambda = round(lambda, 4), pre95 = round(pre95_lambda, 4),
                in_downstream)], nrow = 60)

cat(sprintf("\nPA lambda-hat = %.4f (formal share of violations)\n", pa_lambda))
cat(sprintf("PA rank among all %d states: %d (1 = most lenient)\n", n_all, pa_rank_all))
cat(sprintf("PA percentile among ALL ranked states:        %.0f%% (%% of states stricter-below... i.e. more lenient than PA)\n", pa_pct_all))
cat(sprintf("PA percentile among DOWNSTREAM-SAMPLE states:  %.0f%%\n", pa_pct_down))
cat(sprintf("Median lambda (all): %.4f | Mean: %.4f | PA: %.4f\n",
            median(lam_all$lambda), mean(lam_all$lambda), pa_lambda))

# ---- Save table ----
fwrite(lam_all[order(lambda)], "output/sum/state_enforcement_intensity.csv")
cat("\nSaved: output/sum/state_enforcement_intensity.csv\n")

# ---- Figure ----
plotdf <- lam_all[order(lambda)]
plotdf[, state := factor(state, levels = state)]
plotdf[, fillgrp := ifelse(state == "PA", "PA",
                    ifelse(in_downstream, "downstream", "other"))]

p <- ggplot(plotdf, aes(x = lambda, y = state, fill = fillgrp)) +
  geom_col(width = 0.7) +
  scale_fill_manual(values = c("PA" = "#d62728", "downstream" = "#1f77b4", "other" = "grey75"),
                    breaks = c("PA", "downstream", "other"),
                    labels = c("Pennsylvania", "In downstream MR sample", "Other state"),
                    name = NULL) +
  geom_vline(xintercept = median(lam_all$lambda), linetype = "dashed",
             color = "grey30", linewidth = 0.6) +
  annotate("text", x = median(lam_all$lambda), y = 1,
           label = "median", hjust = -0.1, size = 3, color = "grey30") +
  theme_classic(base_size = 11) +
  labs(
    x = "λ̂: share of CWS violations escalated to a formal enforcement action",
    y = "State",
    title = "State formal-enforcement intensity (regulator stringency)",
    subtitle = sprintf("PA λ̂ = %.3f — %.0fth pct among all states, %.0fth pct among downstream-MR states (low = lenient)",
                       pa_lambda, pa_pct_all, pa_pct_down),
    caption = paste0(
      "λ̂_s = distinct CWS violations with ≥1 Formal enforcement action / distinct CWS violations, 1985-2005.\n",
      sprintf("Empirical analog of λ in Prop 3. States with ≥ %d distinct violations. Blue = states identifying the downstream MR 2SLS.", MIN_VIOL)
    )
  ) +
  theme(plot.caption = element_text(hjust = 0, size = 8),
        plot.title = element_text(face = "bold", size = 12),
        plot.subtitle = element_text(size = 9),
        legend.position = c(0.75, 0.25))

n_states_plot <- nrow(plotdf)
ggsave("output/fig/state_enforcement_intensity.png",
       p, width = 7, height = 0.32 * n_states_plot + 2, dpi = 300)
cat("Saved: output/fig/state_enforcement_intensity.png\n")
cat("\nDone.\n")
