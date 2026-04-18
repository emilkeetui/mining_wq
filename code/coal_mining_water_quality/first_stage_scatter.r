# ============================================================
# Script: first_stage_scatter.r
# Purpose: Frisch-Waugh scatter of first-stage relationship —
#          residualized instrument vs. residualized mine count
# Inputs:  clean_data/cws_data/prod_vio_sulfur.parquet
# Outputs: output/fig/first_stage_scatter_dwnstrm.png
# Author: EK  Date: 2026-04-17
# ============================================================

.libPaths("Z:/ek559/RPackages")
library(fixest)
library(arrow)
library(ggplot2)

full <- read_parquet("Z:/ek559/mining_wq/clean_data/cws_data/prod_vio_sulfur.parquet")
full <- full[full$year < 2006 & full$year > 1984, ]
full <- full[full$PWSID != "WV3303401", ]

# Downstream-only sample
dset <- full[(full$minehuc_downstream_of_mine == 1) & (full$minehuc_mine == 0), ]
dset$instrument <- dset$post95 * dset$sulfur_unified
dset <- dset[!is.na(dset$instrument) & !is.na(dset$num_coal_mines_upstream), ]
rownames(dset) <- NULL   # reset so residual names index into dset cleanly
cat("Downstream sample rows:", nrow(dset), "\n")

# Frisch-Waugh: residualize both mine count and instrument on PWSID + year FEs
m_mines <- lm(num_coal_mines_upstream ~ as.factor(PWSID) + as.factor(year), data = dset)
m_instr <- lm(instrument             ~ as.factor(PWSID) + as.factor(year), data = dset)

plot_df <- data.frame(
  e_instr = residuals(m_instr),
  e_mines = residuals(m_mines)
)

fs_coef <- coef(lm(e_mines ~ e_instr, data = plot_df))[["e_instr"]]
cat("FWL first-stage slope:", round(fs_coef, 4), "\n")

caption_raw <- paste0(
  "Each point is a CWS \u00d7 year observation (downstream CWSs, 1985\u20132005, ",
  "n = ", format(nrow(plot_df), big.mark = ","), "). ",
  "Both axes show residuals from separate regressions of each variable on PWSID and year ",
  "fixed effects, retaining only within-CWS variation over time. ",
  "The vertical axis residualizes upstream mine count; the horizontal axis residualizes ",
  "the instrument (post-1995 indicator \u00d7 mean coal sulfur content of the upstream watershed). ",
  "By the Frisch-Waugh-Lovell theorem, the slope of the OLS line (\u03b2 = ",
  round(fs_coef, 3), ") equals the first-stage coefficient from the 2SLS specification."
)
caption_text <- paste(strwrap(caption_raw, width = 115), collapse = "\n")

p <- ggplot(plot_df, aes(x = e_instr, y = e_mines)) +
  geom_point(alpha = 0.12, size = 0.5, color = "steelblue") +
  geom_smooth(method = "lm", se = TRUE, color = "black", linewidth = 0.8,
              fill = "grey70") +
  labs(
    title   = "First Stage: ARP \u00d7 Coal Sulfur Content and Upstream Mine Activity",
    x       = "Residualized instrument (post-1995 \u00d7 coal sulfur content)",
    y       = "Residualized upstream mine count",
    caption = caption_text
  ) +
  theme_classic(base_size = 11) +
  theme(
    plot.title             = element_text(size = 11, face = "bold",
                                          margin = margin(b = 6)),
    plot.caption           = element_text(hjust = 0, size = 7.5, lineheight = 1.35,
                                          margin = margin(t = 8)),
    plot.caption.position  = "plot",
    plot.margin            = margin(t = 8, r = 12, b = 8, l = 8)
  )

out_path <- "Z:/ek559/mining_wq/output/fig/first_stage_scatter_dwnstrm.png"
ggsave(out_path, plot = p, width = 7, height = 5.8, dpi = 300)
cat("Saved:", out_path, "\n")
