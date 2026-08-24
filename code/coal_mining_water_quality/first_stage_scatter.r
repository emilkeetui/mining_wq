# ============================================================
# Script: first_stage_scatter.r
# Purpose: Frisch-Waugh scatter of first-stage relationship —
#          residualized instrument vs. residualized mine count
# Inputs:  clean_data/cws_data/prod_vio_sulfur.parquet
# Outputs: output/fig/first_stage_scatter_dwnstrm.png
# Author: EK  Date: 2026-04-17
# ============================================================

.libPaths(c("C:/Users/ek559/AppData/Local/R/win-library/4.6", "Z:/ek559/RPackages"))
library(fixest)
library(arrow)
library(ggplot2)

full <- read_parquet("Z:/ek559/mining_wq/clean_data/cws_data/prod_vio_sulfur.parquet")
full <- full[full$year < 2006 & full$year > 1984, ]
full <- full[full$PWSID != "WV3303401", ]

# Downstream-only sample
# NOTE: prod_vio_sulfur.parquet's sulfur_unified/num_coal_mines_upstream were
# split into _mean/_sum variants; use _sum to match the "ivsum" first-stage
# specification (run_main_tables.r) that this scatter plot accompanies.
dset <- full[(full$minehuc_downstream_of_mine == 1) & (full$minehuc_mine == 0), ]
dset$instrument <- dset$post95 * dset$sulfur_unified_sum
dset <- dset[!is.na(dset$instrument) & !is.na(dset$num_coal_mines_upstream_sum), ]
rownames(dset) <- NULL   # reset so residual names index into dset cleanly
cat("Downstream sample rows:", nrow(dset), "\n")

# Frisch-Waugh: residualize both mine count and instrument on PWSID + year FEs
m_mines <- lm(num_coal_mines_upstream_sum ~ as.factor(PWSID) + as.factor(year), data = dset)
m_instr <- lm(instrument             ~ as.factor(PWSID) + as.factor(year), data = dset)

plot_df <- data.frame(
  e_instr = residuals(m_instr),
  e_mines = residuals(m_mines)
)

fs_coef <- coef(lm(e_mines ~ e_instr, data = plot_df))[["e_instr"]]
cat("FWL first-stage slope:", round(fs_coef, 4), "\n")

p <- ggplot(plot_df, aes(x = e_instr, y = e_mines)) +
  geom_point(alpha = 0.12, size = 0.5, color = "steelblue") +
  geom_smooth(method = "lm", se = TRUE, color = "black", linewidth = 0.8,
              fill = "grey70") +
  labs(
    title   = "First Stage: ARP \u00d7 Coal Sulfur Content and Upstream Mine Activity",
    x       = "Residualized instrument (post-1995 \u00d7 coal sulfur content)",
    y       = "Residualized upstream mine count"
  ) +
  theme_classic(base_size = 11) +
  theme(
    plot.title             = element_text(size = 11, face = "bold",
                                          margin = margin(b = 6)),
    plot.margin            = margin(t = 8, r = 12, b = 8, l = 8)
  )

out_path <- "Z:/ek559/mining_wq/output/fig/first_stage_scatter_dwnstrm.png"
ggsave(out_path, plot = p, width = 7, height = 5.8, dpi = 300)
cat("Saved:", out_path, "\n")
