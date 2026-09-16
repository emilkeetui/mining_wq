# ============================================================
# Script: run_k2_figures.r
# Purpose: Two k2 companion figures for main.tex:
#          (1) scatterhuccoalsulfur_pooled_k2.png -- binscatter of sulfur %
#              vs. number of coal mines, over mine HUC12s linked (<=2 flow
#              steps upstream) to a k2 main-arm utility intake. Ports
#              regen_scatterhuccoalsulfur_pooled.r.
#          (2) first_stage_scatter_dwnstrm_k2.png -- Frisch-Waugh scatter of
#              the k2 main-arm first stage, residualizing on PWSID + year +
#              STATE_CODE^year via fixest::demean() (not lm() dummies --
#              666 utilities x 27 states x 21 years makes the dense dummy
#              design matrix prohibitive). Ports first_stage_scatter.r.
# Inputs:
#   clean_data/cws_data/step_huc_links_k2.parquet
#   clean_data/huc_coal_charac_geom_match.csv
#   clean_data/coal_huc_prod.csv
#   clean_data/huc_sulfur_extended.parquet
#   clean_data/cws_data/step_instruments.parquet (via k2_common.r)
#   clean_data/cws_data/cws_covariates_steps.parquet (via k2_common.r)
#   clean_data/cws_data/sdwa_vio_agg_steps.parquet (via k2_common.r)
#   clean_data/cws_data/sdwa_visit_agg_k2.parquet (via k2_common.r)
#   clean_data/cws_data/sdwa_enf_agg_k2.parquet (via k2_common.r)
# Outputs:
#   output/fig/scatterhuccoalsulfur_pooled_k2.png
#   output/fig/first_stage_scatter_dwnstrm_k2.png
# Author: EK  Date: 2026-09-14
# ============================================================

source("Z:/ek559/mining_wq/code/coal_mining_water_quality/k2_common.r")
library(ggplot2)
library(patchwork)
library(scales)

# ── 8.1 scatterhuccoalsulfur_pooled_k2.png ───────────────────────────────
huc_links <- read_parquet(file.path(ROOT, "clean_data/cws_data/step_huc_links_k2.parquet"))
linked_hucs <- unique(huc_links$linked_huc12)

huc_csv <- read.csv(file.path(ROOT, "clean_data/huc_coal_charac_geom_match.csv"),
                     colClasses = c(huc12 = "character"))
mine_hucs <- unique(huc_csv$huc12[huc_csv$minehuc == "mine"])
target_hucs <- intersect(linked_hucs, mine_hucs)
cat(sprintf("Linked HUCs: %d | mine HUCs: %d | linked mine HUCs: %d\n",
            length(linked_hucs), length(mine_hucs), length(target_hucs)))

coal_prod <- read.csv(file.path(ROOT, "clean_data/coal_huc_prod.csv"), colClasses = c(huc12 = "character"))
coal_prod <- coal_prod[coal_prod$year >= 1985 & coal_prod$year <= 2005, ]
active_hucs <- unique(coal_prod$huc12[coal_prod$num_coal_mines > 0])
target_hucs <- intersect(target_hucs, active_hucs)
cat(sprintf("Scatter sample -- linked mine HUC12s with >= 1 mine year (1985-2005): %d\n", length(target_hucs)))

sulfur_ext <- read_parquet(file.path(ROOT, "clean_data/huc_sulfur_extended.parquet"))

huc_years <- expand.grid(huc12 = target_hucs, year = 1985:2005, stringsAsFactors = FALSE)
huc_years <- merge(huc_years, coal_prod[, c("huc12", "year", "num_coal_mines", "production_short_tons_coal")],
                    by = c("huc12", "year"), all.x = TRUE)
huc_years$num_coal_mines[is.na(huc_years$num_coal_mines)] <- 0
huc_years$production_short_tons_coal[is.na(huc_years$production_short_tons_coal)] <- 0
huc_years <- merge(huc_years, sulfur_ext[, c("huc12", "sulfur_colocated")], by = "huc12", all.x = TRUE)
huc_years <- huc_years[!is.na(huc_years$sulfur_colocated), ]
huc_years$num_coal_mines_colocated <- huc_years$num_coal_mines
cat(sprintf("Scatter sample rows: %d\n", nrow(huc_years)))

make_binscatter_panel <- function(df, panel_title) {
  binned <- df %>%
    dplyr::group_by(num_coal_mines_colocated) %>%
    dplyr::summarise(mean_sulfur = mean(sulfur_colocated, na.rm = TRUE),
                      sd_sulfur   = sd(sulfur_colocated, na.rm = TRUE), .groups = "drop")

  fit <- lm(sulfur_colocated ~ num_coal_mines_colocated, data = df)
  fit_line <- data.frame(
    num_coal_mines_colocated = seq(min(df$num_coal_mines_colocated, na.rm = TRUE),
                                    max(df$num_coal_mines_colocated, na.rm = TRUE), length.out = 100)
  )
  fit_line$sulfur_colocated <- predict(fit, newdata = fit_line)

  ggplot(mapping = aes(x = num_coal_mines_colocated, y = sulfur_colocated)) +
    geom_line(data = fit_line, color = "black", linewidth = 0.9, alpha = 0.25) +
    geom_pointrange(data = binned,
                     aes(y = mean_sulfur, ymin = mean_sulfur - sd_sulfur, ymax = mean_sulfur + sd_sulfur),
                     color = "steelblue", size = 0.4) +
    labs(title = panel_title, x = "Number of coal mines", y = "Sulfur (%)") +
    scale_x_continuous(labels = scales::label_number(accuracy = 1)) +
    scale_y_continuous(labels = scales::label_number(accuracy = 0.1)) +
    theme_bw() +
    theme(panel.grid = element_blank())
}

p_before_k2 <- make_binscatter_panel(huc_years %>% dplyr::filter(year <= 1995), "Up to and Including 1995")
p_after_k2  <- make_binscatter_panel(huc_years %>% dplyr::filter(year > 1995), "After 1995")

(p_before_k2 + p_after_k2) +
  plot_annotation(
    title = "Descriptive evidence of first-stage relevance",
    caption = paste0(
      "Sample: HUC12 watersheds within two flow steps upstream of a utility water ",
      "intake, 1985-2005.\nPoints show the mean sulfur as a percent of coal weight ",
      "within each coal-mine-count bin; ranges show +/- 1 standard deviation within bin."
    ),
    theme = theme(plot.caption = element_text(hjust = 0))
  )

out_path_1 <- "Z:/ek559/mining_wq/output/fig/scatterhuccoalsulfur_pooled_k2.png"
ggsave(out_path_1, width = 8, height = 5, dpi = 500)
cat("Saved:", out_path_1, "\n")

# ── 8.2 first_stage_scatter_dwnstrm_k2.png ───────────────────────────────
main_dat <- build_k2_panel("main")
main_dat$instrument <- main_dat$post95 * main_dat$sulfur_mean0
dat_fs <- main_dat[!is.na(main_dat$instrument) & !is.na(main_dat$num_coal_mines_linked_sum), ]
rownames(dat_fs) <- NULL
cat(sprintf("\nMain-arm k2 sample rows for FWL scatter: %d\n", nrow(dat_fs)))

fe_df <- data.frame(
  PWSID      = dat_fs$PWSID,
  year       = factor(dat_fs$year),
  state_year = factor(paste(dat_fs$STATE_CODE, dat_fs$year))
)
res <- fixest::demean(as.matrix(dat_fs[, c("num_coal_mines_linked_sum", "instrument", "num_facilities")]), fe_df)

plot_df <- data.frame(e_instr = res[, "instrument"], e_mines = res[, "num_coal_mines_linked_sum"])

# Verification-only regression: partial num_facilities out too (Frisch-Waugh-
# Lovell requires residualizing on every other regressor, not just the FEs,
# to reproduce the full model's coefficient exactly). The plot itself stays
# the simpler FE-only bivariate residual scatter, matching the codebase's
# established first_stage_scatter.r design.
fs_coef_fwl <- coef(lm(e_mines ~ e_instr + e_fac, data = data.frame(
  e_instr = res[, "instrument"], e_mines = res[, "num_coal_mines_linked_sum"], e_fac = res[, "num_facilities"]
)))[["e_instr"]]
cat("FWL first-stage slope (partialling out num_facilities too):", round(fs_coef_fwl, 6), "\n")

fs_m_check <- fixest::feols(
  num_coal_mines_linked_sum ~ post95:sulfur_mean0 + num_facilities | PWSID + year + STATE_CODE^year,
  data = main_dat, cluster = ~PWSID, warn = FALSE, notes = FALSE
)
fs_coef_direct <- coef(fs_m_check)["post95:sulfur_mean0"]
cat(sprintf("Direct feols first-stage coefficient: %.6f\n", fs_coef_direct))
cat(sprintf("Difference: %.6f\n", abs(fs_coef_fwl - fs_coef_direct)))
stopifnot(round(fs_coef_fwl, 3) == round(fs_coef_direct, 3))
cat("FWL reproduction gate PASSED (matches Step 4.4 first stage to >=3 decimals).\n")

p2 <- ggplot(plot_df, aes(x = e_instr, y = e_mines)) +
  geom_point(alpha = 0.12, size = 0.5, color = "steelblue") +
  geom_smooth(method = "lm", se = TRUE, color = "black", linewidth = 0.8, fill = "grey70") +
  labs(
    title = "First Stage: ARP \u00d7 Coal Sulfur Content and Upstream Mine Activity",
    x     = "Residualized instrument (post-1995 \u00d7 coal sulfur content)",
    y     = "Residualized upstream mine count"
  ) +
  scale_x_continuous(labels = scales::label_number(accuracy = 0.1)) +
  scale_y_continuous(labels = scales::label_number(accuracy = 0.1)) +
  theme_classic(base_size = 11) +
  theme(
    plot.title  = element_text(size = 11, face = "bold", margin = margin(b = 6)),
    plot.margin = margin(t = 8, r = 12, b = 8, l = 8)
  )

out_path_2 <- "Z:/ek559/mining_wq/output/fig/first_stage_scatter_dwnstrm_k2.png"
ggsave(out_path_2, plot = p2, width = 7, height = 5.8, dpi = 300)
cat("Saved:", out_path_2, "\n")

cat("\n=== run_k2_figures.r DONE ===\n")
