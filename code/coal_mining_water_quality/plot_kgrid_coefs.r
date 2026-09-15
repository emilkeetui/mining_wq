# ============================================================
# Script: plot_kgrid_coefs.r
# Purpose: Render coefficient-vs-flow-step-k figures (OLS/RF/2SLS x
#          main/placebo arm) for each outcome family (MR, MCL, visit-type,
#          enforcement-type), plus a combined first-stage figure. Error
#          bars show 90% confidence intervals (coef +/- 1.645*se). Reads
#          only the tidy Step-2 output parquets -- no estimation here, so
#          figure tweaks never re-run regressions.
# Inputs:
#   clean_data/cws_data/kgrid_coefs.parquet
#   clean_data/cws_data/kgrid_firststage.parquet
# Outputs:
#   output/fig/kgrid_mr_coefs.png
#   output/fig/kgrid_mcl_coefs.png
#   output/fig/kgrid_visit_coefs.png
#   output/fig/kgrid_enf_coefs.png
#   output/fig/kgrid_first_stage.png
# Author: EK  Date: 2026-09-15
# ============================================================

.libPaths(c(.libPaths(), "Z:/ek559/RPackages"))
library(arrow)
library(dplyr)
library(ggplot2)
library(patchwork)
library(scales)

ROOT <- "Z:/ek559/mining_wq"

coef_df <- read_parquet(file.path(ROOT, "clean_data/cws_data/kgrid_coefs.parquet"))
fs_df   <- read_parquet(file.path(ROOT, "clean_data/cws_data/kgrid_firststage.parquet"))

OKABE_ITO <- c("#E69F00", "#56B4E9", "#009E73", "#D55E00", "#CC79A7")
CI90 <- qnorm(0.95)  # two-sided 90% CI multiplier on the SE

model_labels <- c(OLS = "OLS: coal mines", RF = "Reduced form: post-1995 \u00d7 sulfur", "2SLS" = "2SLS: coal mines")
arm_labels   <- c(main = "Coal mine upstream of intake",
                   placebo = "Coal mine downstream of intake, none upstream")

FAMILY_META <- list(
  mr    = list(order = c("Nitrates", "Arsenic", "Inorganic chemicals"),    legend = "MR violation"),
  mcl   = list(order = c("Nitrates", "Arsenic", "Inorganic chemicals"),    legend = "MCL violation"),
  visit = list(order = c("Sanitary", "Technical assistance", "Enforcement", "Sample collection", "Inspection"),
               legend = "Regulator visit type"),
  enf   = list(order = c("Informal", "Formal", "None"),                   legend = "Enforcement action")
)

theme_kgrid <- theme_classic(base_size = 11) +
  theme(legend.position = "bottom",
        strip.background = element_rect(fill = "grey95", colour = NA),
        panel.spacing = unit(0.8, "lines"),
        panel.border = element_rect(colour = "grey40", fill = NA, linewidth = 0.4))

plot_family <- function(fam) {
  meta <- FAMILY_META[[fam]]
  dat <- coef_df %>%
    dplyr::filter(family == fam) %>%
    dplyr::mutate(
      model = factor(model, levels = c("OLS", "RF", "2SLS")),
      arm   = factor(arm, levels = c("main", "placebo")),
      outcome_label = factor(outcome_label, levels = meta$order)
    )

  y_span <- max(dat$coef + CI90 * dat$se, na.rm = TRUE) - min(dat$coef - CI90 * dat$se, na.rm = TRUE)
  accuracy <- if (y_span < 1) 0.01 else 0.1

  dodge <- position_dodge(width = 0.6)

  p <- ggplot(dat, aes(x = k, y = coef, colour = outcome_label)) +
    geom_hline(yintercept = 0, linetype = "dashed", colour = "grey50") +
    geom_errorbar(aes(ymin = coef - CI90 * se, ymax = coef + CI90 * se), width = 0, position = dodge) +
    geom_point(position = dodge, size = 1.8) +
    facet_grid(model ~ arm, scales = "free_y",
               labeller = labeller(model = model_labels, arm = arm_labels)) +
    scale_x_continuous(breaks = 1:8, name = "Flow steps from intake (k)") +
    scale_y_continuous(labels = scales::label_number(accuracy = accuracy), name = "Coefficient (percentage points)") +
    scale_colour_manual(values = OKABE_ITO, name = meta$legend) +
    theme_kgrid

  p
}

fig_specs <- list(
  mr    = "kgrid_mr_coefs.png",
  mcl   = "kgrid_mcl_coefs.png",
  visit = "kgrid_visit_coefs.png",
  enf   = "kgrid_enf_coefs.png"
)

for (fam in names(fig_specs)) {
  p <- plot_family(fam)
  out_path <- file.path(ROOT, "output/fig", fig_specs[[fam]])
  if (file.exists(out_path)) cat("WARNING: overwriting existing", out_path, "\n")
  ggsave(out_path, p, width = 9, height = 8, dpi = 300)
  cat("Wrote", out_path, "\n")
}

# ── First-stage figure: coefficient panel + F-statistic panel (patchwork) ──
fs_dat <- fs_df %>%
  dplyr::mutate(arm = factor(arm, levels = c("main", "placebo"),
                              labels = c("Coal mine upstream of intake",
                                         "Coal mine downstream of intake, none upstream")))

p_fs_coef <- ggplot(fs_dat, aes(x = k, y = fs_coef, colour = arm)) +
  geom_hline(yintercept = 0, linetype = "dashed", colour = "grey50") +
  geom_errorbar(aes(ymin = fs_coef - CI90 * fs_se, ymax = fs_coef + CI90 * fs_se), width = 0,
                position = position_dodge(width = 0.3)) +
  geom_point(position = position_dodge(width = 0.3), size = 1.8) +
  scale_x_continuous(breaks = 1:8, name = "Flow steps from intake (k)") +
  scale_y_continuous(labels = scales::label_number(accuracy = 0.1),
                      name = "First-stage coefficient\n(post-1995 \u00d7 sulfur)") +
  scale_colour_manual(values = OKABE_ITO[1:2], name = NULL) +
  theme_kgrid

p_fs_f <- ggplot(fs_dat, aes(x = k, y = f_clustered, colour = arm)) +
  geom_hline(yintercept = 10, linetype = "dashed", colour = "grey50") +
  annotate("text", x = 8, y = 10, label = "F = 10", vjust = -0.6, hjust = 1, size = 3, colour = "grey30") +
  geom_line(position = position_dodge(width = 0.3)) +
  geom_point(position = position_dodge(width = 0.3), size = 1.8) +
  scale_x_continuous(breaks = 1:8, name = "Flow steps from intake (k)") +
  scale_y_continuous(labels = scales::label_number(accuracy = 1),
                      name = "First-stage F-statistic (clustered)") +
  scale_colour_manual(values = OKABE_ITO[1:2], name = NULL) +
  theme_kgrid

p_first_stage <- (p_fs_coef + p_fs_f) +
  patchwork::plot_layout(guides = "collect") &
  theme(legend.position = "bottom")

out_fs_path <- file.path(ROOT, "output/fig/kgrid_first_stage.png")
if (file.exists(out_fs_path)) cat("WARNING: overwriting existing", out_fs_path, "\n")
ggsave(out_fs_path, p_first_stage, width = 9, height = 4, dpi = 300)
cat("Wrote", out_fs_path, "\n")

cat("\nDone.\n")
