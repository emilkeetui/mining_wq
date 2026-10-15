# ============================================================
# Script: plot_k2_ring_coefs.r
# Purpose: Horizontal coefficient plots comparing three mine-exposure
#          definitions (within two watersheds upstream, exactly two, two to
#          three) on the k=2 utility sample. Plot only; no estimation.
# Inputs: clean_data/cws_data/k2_ring_coefs.parquet
# Outputs:
#   output/fig/k2_ring_coefs_mr_mcl.png
#   output/fig/k2_ring_coefs_visit_enf.png
#   output/fig/k2_ring_coefs_syr2.png
# Author: EK  Date: 2026-10-15
# ============================================================

.libPaths(c(.libPaths(), "Z:/ek559/RPackages"))
library(ggplot2); library(patchwork); library(scales); library(dplyr); library(arrow)

ROOT <- "Z:/ek559/mining_wq"
res <- read_parquet(file.path(ROOT, "clean_data/cws_data/k2_ring_coefs.parquet"))
stopifnot(nrow(res) == 54)

series_levels <- c("k2", "ring2", "ring23")
series_labels <- c("Within two watersheds upstream", "Exactly two watersheds upstream",
                   "Two to three watersheds upstream")
series_cols   <- c("#000000", "#E69F00", "#56B4E9")
series_shapes <- c(16, 17, 15)
offsets       <- c(k2 = 0.22, ring2 = 0, ring23 = -0.22)

prep <- function(fam, order) {
  d <- res %>% dplyr::filter(family == fam)
  stopifnot(setequal(unique(d$outcome_label), order))
  d$y_base <- match(d$outcome_label, rev(order))
  d$y <- d$y_base + offsets[d$series]
  d$series_label <- factor(d$series_label, levels = series_labels)
  d$lo <- d$coef - 1.96 * d$se
  d$hi <- d$coef + 1.96 * d$se
  d
}

base_layers <- function(p) {
  p +
    geom_vline(xintercept = 0, linetype = "dashed", colour = "grey50") +
    geom_linerange(aes(xmin = lo, xmax = hi, colour = series_label), orientation = "y") +
    geom_point(aes(colour = series_label, shape = series_label), size = 2) +
    scale_colour_manual(values = setNames(series_cols, series_labels), name = NULL) +
    scale_shape_manual(values = setNames(series_shapes, series_labels), name = NULL) +
    theme_classic(base_size = 11) +
    theme(legend.position = "bottom", panel.grid = element_blank())
}

plot_ring_panel <- function(fam, order, heading, x_lab, accuracy) {
  d <- prep(fam, order)
  base_layers(ggplot(d, aes(x = coef, y = y))) +
    scale_y_continuous(breaks = seq_along(order), labels = rev(order),
                       expand = expansion(add = 0.5)) +
    scale_x_continuous(labels = scales::label_number(accuracy = accuracy)) +
    labs(title = heading, x = x_lab, y = NULL) +
    theme(plot.title = element_text(size = 11))
}

save_fig <- function(p, name, w, h) {
  path <- file.path(ROOT, "output/fig", name)
  if (file.exists(path)) cat("WARNING:", path, "already exists -- overwriting\n")
  ggsave(path, p, width = w, height = h, dpi = 300)
  cat(sprintf("Wrote %s (%d bytes)\n", path, file.info(path)$size))
}

x_pp <- "2SLS coefficient (percentage points)"

# ── Figure 1: MR and MCL violations ─────────────────────────────────────
inorg_order <- c("Arsenic", "Nitrates", "Inorganic chemicals")
p_mr  <- plot_ring_panel("mr",  inorg_order, "Monitoring and reporting violations", x_pp, 0.1)
p_mcl <- plot_ring_panel("mcl", inorg_order, "Maximum contaminant level violations", x_pp, 0.1) +
  theme(axis.text.y = element_blank(), axis.ticks.y = element_blank())
fig1 <- (p_mr | p_mcl) + plot_layout(guides = "collect") & theme(legend.position = "bottom")
save_fig(fig1, "k2_ring_coefs_mr_mcl.png", 9, 4)

# ── Figure 2: visits and enforcement ───────────────────────────────────
p_visit <- plot_ring_panel("visit",
  c("Sanitary", "Technical assistance", "Enforcement", "Sample collection", "Inspection"),
  "Regulator visits", x_pp, 0.1)
p_enf <- plot_ring_panel("enf", c("Informal", "Formal", "None"),
  "Enforcement actions", x_pp, 0.1)
fig2 <- (p_visit | p_enf) + plot_layout(guides = "collect") & theme(legend.position = "bottom")
save_fig(fig2, "k2_ring_coefs_visit_enf.png", 9, 4.5)

# ── Figure 3: SYR2 concentrations ──────────────────────────────────────
# Chemicals differ by orders of magnitude (arsenic CIs are ~1/100 of nitrate's), so each
# chemical gets its own free x scale in a facet with the strip on the left.
syr2_order <- c("Arsenic", "Nitrate", "Barium", "Selenium")
d3 <- prep("syr2", syr2_order)
d3$outcome_label <- factor(d3$outcome_label, levels = syr2_order)
d3$y <- as.numeric(d3$series_label %in% series_labels[1]) * offsets[["k2"]] +
  as.numeric(d3$series_label == series_labels[3]) * offsets[["ring23"]]
fmt_plain <- function(x) format(x, scientific = FALSE, trim = TRUE, drop0trailing = FALSE)
fig3 <- base_layers(ggplot(d3, aes(x = coef, y = y))) +
  facet_wrap(~ outcome_label, ncol = 1, scales = "free_x", strip.position = "left") +
  guides(colour = guide_legend(nrow = 3), shape = guide_legend(nrow = 3)) +
  scale_y_continuous(breaks = NULL, expand = expansion(add = 0.4)) +
  scale_x_continuous(labels = fmt_plain) +
  labs(x = "OLS coefficient (mg/L per million short tons)", y = NULL) +
  theme(strip.placement = "outside", strip.background = element_blank(),
        strip.text.y.left = element_text(angle = 0, hjust = 1))
save_fig(fig3, "k2_ring_coefs_syr2.png", 6, 5)
