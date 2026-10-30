# ============================================================
# Script: plot_k2_scaled_compare.r
# Purpose: Coefficient plots comparing upstream coal mines with upstream annual
#          coal production as the regressor (SD units, elasticity at the means),
#          the first stage that drives their ratio, and a mines-vs-production
#          elasticity scatter. Plot only; no new estimation.
# Inputs: output/reg/scaled_compare_all_k2.csv,
#         clean_data/cws_data/k2_scaled_first_stage.parquet
# Outputs: output/fig/k2_scaled_compare_violations.png,
#          output/fig/k2_scaled_compare_visit_enf.png,
#          output/fig/k2_scaled_first_stage.png,
#          output/fig/k2_scaled_compare_scatter.png
# Author: EK  Date: 2026-10-15
# ============================================================

.libPaths(c(.libPaths(), "Z:/ek559/RPackages"))
library(ggplot2); library(patchwork); library(scales); library(dplyr); library(arrow)

ROOT <- "Z:/ek559/mining_wq"
res <- read.csv(file.path(ROOT, "output/reg/scaled_compare_all_k2.csv"), stringsAsFactors = FALSE)
fs  <- read_parquet(file.path(ROOT, "clean_data/cws_data/k2_scaled_first_stage.parquet"))

fe_sy <- "PWSID + STATE_CODE^year"
d2sls <- res %>% dplyr::filter(estimator == "2SLS", fe == fe_sy, scale %in% c("z", "m"))
dsyr2 <- res %>% dplyr::filter(table == "6yr_huc02fe_inorg_ravalli_2005", panel_ab == "B",
                               prod_type == "annual", estimator == "OLS", scale == "m")
stopifnot(nrow(d2sls) == 34, nrow(dsyr2) == 4)

# ── Anchor gates ─────────────────────────────────────────────────────────
anchor <- function(d, o, sc, bm, bp) {
  r <- d[d$outcome == o & d$scale == sc, ]
  stopifnot(nrow(r) == 1, round(r$coef_mines, 3) == bm, round(r$coef_prod, 3) == bp)
}
anchor(d2sls, "nitrates_bin", "m", 0.761, 0.924)
anchor(d2sls, "arsenic_MCL_bin", "m", 5.166, 6.274)
anchor(dsyr2, "selenium", "m", -0.083, 0.046)
for (sc in c("z", "m")) stopifnot(diff(range(d2sls$ratio[d2sls$scale == sc])) < 1e-6)
cat("Anchor and constant-ratio gates passed\n")

# ── Labels ───────────────────────────────────────────────────────────────
three <- c("Arsenic", "Nitrates", "Inorganic chemicals")
fam_def <- list(
  any   = list(heading = "Any violation",
               y = c("arsenic_bin", "nitrates_bin", "inorganic_chemicals_bin"), lab = three),
  mr    = list(heading = "Monitoring and reporting (MR) violations",
               y = c("arsenic_MR_bin", "nitrates_MR_bin", "inorganic_chemicals_MR_bin"), lab = three),
  mcl   = list(heading = "Maximum contaminant level (MCL) violations",
               y = c("arsenic_MCL_bin", "nitrates_MCL_bin", "inorganic_chemicals_MCL_bin"), lab = three),
  visit = list(heading = "Regulator visits",
               y = c("any_snsv", "any_tech", "any_enfvisit", "any_smpl", "any_insp"),
               lab = c("Sanitary", "Technical assistance", "Enforcement", "Sample collection", "Inspection")),
  enf   = list(heading = "Enforcement actions",
               y = c("any_informal", "any_formal", "no_enf"), lab = c("Informal", "Formal", "None")))
stopifnot(setequal(unlist(lapply(fam_def, `[[`, "y")), unique(d2sls$outcome)))
syr2_lab <- c(arsenic = "Arsenic", nitrate = "Nitrate", barium = "Barium", selenium = "Selenium")
scale_title <- c(z = "Standard deviation units", m = "Elasticity at the means")
scale_xlab  <- c(z = "2SLS coefficient (standard deviation units)", m = "2SLS elasticity at the sample means")

ser_levels <- c("Coal mines", "Coal production")
ser_cols   <- c("Coal mines" = "#000000", "Coal production" = "#E69F00")
ser_shapes <- c("Coal mines" = 16, "Coal production" = 17)
offs       <- c("Coal mines" = 0.15, "Coal production" = -0.15)

long_fmt <- function(d) {
  rbind(
    data.frame(outcome = d$outcome, scale = d$scale, series = "Coal mines",
               coef = d$coef_mines, se = d$se_mines, stringsAsFactors = FALSE),
    data.frame(outcome = d$outcome, scale = d$scale, series = "Coal production",
               coef = d$coef_prod, se = d$se_prod, stringsAsFactors = FALSE)) %>%
    dplyr::mutate(series = factor(series, levels = ser_levels), lo = coef - 1.96 * se, hi = coef + 1.96 * se)
}
dl <- long_fmt(d2sls)

save_fig <- function(p, name, w, h) {
  path <- file.path(ROOT, "output/fig", name)
  if (file.exists(path)) cat("WARNING:", path, "already exists -- overwriting\n")
  ggsave(path, p, width = w, height = h, dpi = 300)
  cat(sprintf("Wrote %s (%d bytes)\n", path, file.info(path)$size))
}
theme_cmp <- function() theme_classic(base_size = 11) +
  theme(legend.position = "bottom", panel.grid = element_blank(), plot.title = element_text(size = 11))

# ── Panel builder ────────────────────────────────────────────────────────
plot_cmp_panel <- function(fam, sc, show_y = TRUE, show_x = TRUE) {
  fd <- fam_def[[fam]]
  d <- dl %>% dplyr::filter(scale == sc, outcome %in% fd$y)
  d$y <- match(d$outcome, rev(fd$y)) + offs[as.character(d$series)]
  p <- ggplot(d, aes(x = coef, y = y)) +
    geom_vline(xintercept = 0, linetype = "dashed", colour = "grey50") +
    geom_linerange(aes(xmin = lo, xmax = hi, colour = series), orientation = "y") +
    geom_point(aes(colour = series, shape = series), size = 2) +
    scale_colour_manual(values = ser_cols, name = NULL) +
    scale_shape_manual(values = ser_shapes, name = NULL) +
    scale_y_continuous(breaks = seq_along(fd$y), labels = rev(fd$lab), expand = expansion(add = 0.5)) +
    scale_x_continuous(labels = scales::label_number(accuracy = 0.01)) +
    labs(title = paste0(fd$heading, "
", scale_title[[sc]]),
         x = if (show_x) scale_xlab[[sc]] else NULL, y = NULL) +
    theme_cmp()
  if (!show_y) p <- p + theme(axis.text.y = element_blank(), axis.ticks.y = element_blank())
  p
}
grid_fig <- function(fams) {
  ps <- list()
  for (i in seq_along(fams)) for (sc in c("z", "m")) {
    ps[[length(ps) + 1]] <- plot_cmp_panel(fams[i], sc, show_y = (sc == "z"), show_x = (i == length(fams)))
  }
  wrap_plots(ps, ncol = 2, byrow = TRUE) + plot_layout(guides = "collect") & theme(legend.position = "bottom")
}

# ── Figures 1 and 2 ──────────────────────────────────────────────────────
save_fig(grid_fig(c("any", "mr", "mcl")), "k2_scaled_compare_violations.png", 9, 8)
save_fig(grid_fig(c("visit", "enf")), "k2_scaled_compare_visit_enf.png", 9, 6)

# ── Figure 3: first stage ────────────────────────────────────────────────
fs$series <- factor(fs$regressor_label, levels = ser_levels)
fs$lo <- fs$coef - 1.96 * fs$se; fs$hi <- fs$coef + 1.96 * fs$se
fs_panel <- function(sc, xl) {
  d <- fs[fs$scale == sc, ]
  ggplot(d, aes(x = coef, y = series)) +
    geom_vline(xintercept = 0, linetype = "dashed", colour = "grey50") +
    geom_linerange(aes(xmin = lo, xmax = hi, colour = series), orientation = "y") +
    geom_point(aes(colour = series, shape = series), size = 2) +
    geom_text(aes(label = sprintf("F = %.1f", F)), vjust = -1, size = 3) +
    scale_colour_manual(values = ser_cols, guide = "none") +
    scale_shape_manual(values = ser_shapes, guide = "none") +
    scale_y_discrete(limits = rev(ser_levels), expand = expansion(add = 0.7)) +
    scale_x_continuous(labels = scales::label_number(accuracy = 0.1)) +
    labs(x = xl, y = NULL) + theme_cmp()
}
fig3 <- fs_panel("m", "Change after 1995 per percentage point of sulfur
(% of sample mean)") |
  fs_panel("z", "Change after 1995 per percentage point of sulfur
(standard deviation units)") &
  theme(axis.title.x = element_text(size = 10))
fig3[[2]] <- fig3[[2]] + theme(axis.text.y = element_blank(), axis.ticks.y = element_blank())
save_fig(fig3, "k2_scaled_first_stage.png", 9, 3)

# ── Figure 4: elasticity scatter ─────────────────────────────────────────
fam_of <- setNames(rep(names(fam_def), vapply(fam_def, function(f) length(f$y), 1L)), unlist(lapply(fam_def, `[[`, "y")))
fam_cols <- c(any = "#000000", mr = "#E69F00", mcl = "#56B4E9", visit = "#009E73", enf = "#CC79A7")
fam_head <- vapply(fam_def, `[[`, "", "heading")
dm <- d2sls %>% dplyr::filter(scale == "m")
dm$family <- factor(fam_of[dm$outcome], levels = names(fam_def), labels = unname(fam_head))
ratio_m <- unique(round(dm$ratio, 6)); stopifnot(length(ratio_m) == 1)
sc_theme_scale <- scale_x_continuous(labels = scales::label_number(accuracy = 0.1))
cross <- function(d) list(
  geom_errorbar(aes(ymin = coef_prod - 1.96 * se_prod, ymax = coef_prod + 1.96 * se_prod), colour = "grey60", width = 0),
  geom_linerange(aes(xmin = coef_mines - 1.96 * se_mines, xmax = coef_mines + 1.96 * se_mines), colour = "grey60", orientation = "y"))
p_iv <- ggplot(dm, aes(x = coef_mines, y = coef_prod)) +
  geom_hline(yintercept = 0, colour = "grey80") + geom_vline(xintercept = 0, colour = "grey80") +
  cross(dm) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed") +
  geom_abline(slope = 1 / ratio_m, intercept = 0, colour = "grey40") +
  geom_point(aes(colour = family), size = 2) +
  annotate("text", x = Inf, y = Inf, label = "Dashed: equal elasticity\nSolid: implied by the first stage",
           hjust = 1.05, vjust = 1.3, size = 3) +
  scale_colour_manual(values = setNames(unname(fam_cols), unname(fam_head)), name = NULL) +
  scale_x_continuous(labels = scales::label_number(accuracy = 0.1)) +
  scale_y_continuous(labels = scales::label_number(accuracy = 0.1)) +
  labs(title = "Two-stage least squares", x = "Coal mines elasticity", y = "Coal production elasticity") +
  theme_cmp() + guides(colour = guide_legend(nrow = 3))
dsyr2$label <- syr2_lab[dsyr2$outcome]
p_syr <- ggplot(dsyr2, aes(x = coef_mines, y = coef_prod)) +
  geom_hline(yintercept = 0, colour = "grey80") + geom_vline(xintercept = 0, colour = "grey80") +
  cross(dsyr2) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed") +
  geom_point(size = 2) +
  geom_text(aes(label = label), hjust = 0, nudge_x = 0.01, nudge_y = 0.01, size = 3) +
  scale_x_continuous(labels = scales::label_number(accuracy = 0.1)) +
  scale_y_continuous(labels = scales::label_number(accuracy = 0.1)) +
  labs(title = "Six-Year Review concentrations (OLS)", x = "Coal mines elasticity", y = "Coal production elasticity") +
  theme_cmp()
save_fig(p_iv | p_syr, "k2_scaled_compare_scatter.png", 10, 4.5)
