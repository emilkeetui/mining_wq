# ============================================================
# Script: plot_kgrid_syr2_coefs.r
# Purpose: Render coefficient-vs-flow-step-k figures for the SYR2 mean
#          concentration OLS effect of cumulative upstream coal production
#          (arsenic, nitrate, barium, selenium), one figure per chemical,
#          each faceted by arm (main | placebo). Error bars show 90%
#          confidence intervals (coef +/- 1.645*se), matching the house
#          convention from plot_kgrid_coefs.r. Reads only the tidy Step-1
#          output parquet -- no estimation here, so figure tweaks never
#          re-run regressions.
# Inputs:
#   clean_data/cws_data/kgrid_syr2_coefs.parquet
# Outputs:
#   output/fig/kgrid_syr2_arsenic_coefs.png
#   output/fig/kgrid_syr2_nitrate_coefs.png
#   output/fig/kgrid_syr2_barium_coefs.png
#   output/fig/kgrid_syr2_selenium_coefs.png
# Author: EK  Date: 2026-09-15
# ============================================================

.libPaths(c(.libPaths(), "Z:/ek559/RPackages"))
library(arrow)
library(dplyr)
library(ggplot2)
library(scales)

ROOT <- "Z:/ek559/mining_wq"

coef_df <- read_parquet(file.path(ROOT, "clean_data/cws_data/kgrid_syr2_coefs.parquet"))

# Colors/theme mirror plot_kgrid_coefs.r verbatim (arsenic/nitrate reuse the
# same Okabe-Ito slots as the MR/MCL figures; barium/selenium take the
# remaining two so all figures in this pipeline share one consistent palette).
OKABE_ITO <- c("#E69F00", "#56B4E9", "#009E73", "#D55E00", "#CC79A7")
CI90 <- qnorm(0.95)  # two-sided 90% CI multiplier on the SE

CHEM_COLOR <- c(arsenic = OKABE_ITO[2], nitrate = OKABE_ITO[1], barium = OKABE_ITO[4], selenium = OKABE_ITO[5])

arm_labels <- c(main = "Coal mine upstream of intake",
                 placebo = "Coal mine downstream of intake, none upstream")

theme_kgrid <- theme_classic(base_size = 11) +
  theme(legend.position = "bottom",
        strip.background = element_rect(fill = "grey95", colour = NA),
        panel.spacing = unit(0.8, "lines"),
        panel.border = element_rect(colour = "grey40", fill = NA, linewidth = 0.4))

CHEM_META <- list(
  arsenic  = "kgrid_syr2_arsenic_coefs.png",
  nitrate  = "kgrid_syr2_nitrate_coefs.png",
  barium   = "kgrid_syr2_barium_coefs.png",
  selenium = "kgrid_syr2_selenium_coefs.png"
)

plot_chem <- function(chem) {
  dat <- coef_df %>%
    dplyr::filter(chemical == chem) %>%
    dplyr::mutate(arm = factor(arm, levels = c("main", "placebo")))

  y_lo <- min(dat$coef - CI90 * dat$se, na.rm = TRUE)
  y_hi <- max(dat$coef + CI90 * dat$se, na.rm = TRUE)
  y_span <- y_hi - y_lo
  accuracy <- 10 ^ floor(log10(y_span)) / 10

  ggplot(dat, aes(x = k, y = coef)) +
    geom_hline(yintercept = 0, linetype = "dashed", colour = "grey50") +
    geom_errorbar(aes(ymin = coef - CI90 * se, ymax = coef + CI90 * se), width = 0,
                  colour = CHEM_COLOR[[chem]]) +
    geom_point(colour = CHEM_COLOR[[chem]], size = 1.8) +
    facet_grid(. ~ arm, labeller = labeller(arm = arm_labels)) +
    scale_x_continuous(breaks = 1:8, name = "Flow steps from intake (k)") +
    scale_y_continuous(labels = scales::label_number(accuracy = accuracy),
                        name = "Coefficient (mg/L per 10M short tons)") +
    theme_kgrid
}

for (chem in names(CHEM_META)) {
  p <- plot_chem(chem)
  out_path <- file.path(ROOT, "output/fig", CHEM_META[[chem]])
  if (file.exists(out_path)) cat("WARNING: overwriting existing", out_path, "\n")
  ggsave(out_path, p, width = 9, height = 4, dpi = 300)
  cat("Wrote", out_path, "\n")
}

cat("\nDone.\n")
