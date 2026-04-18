# ============================================================
# Script: population_exposure_map.r
# Purpose: Maps of population served by CWSs downstream of
#          active coal mines, pre-ARP vs. post-ARP, and net change
# Inputs:  clean_data/cws_data/prod_vio_sulfur.parquet
# Outputs: output/fig/pop_exposed_two_panel.png
#          output/fig/pop_exposed_change.png
# Author: EK  Date: 2026-04-17
# ============================================================

.libPaths("Z:/ek559/RPackages")
library(arrow)
library(dplyr)
library(tidyr)
library(ggplot2)
library(sf)
library(tigris)

options(tigris_use_cache = TRUE)

full <- read_parquet("Z:/ek559/mining_wq/clean_data/cws_data/prod_vio_sulfur.parquet")
full <- full[full$year < 2006 & full$year > 1984, ]
full <- full[full$PWSID != "WV3303401", ]

cat("Rows in full:", nrow(full), "\n")
cat("Non-NA POPULATION_SERVED_COUNT:", sum(!is.na(full$POPULATION_SERVED_COUNT)), "\n")

# Downstream-only CWSs with at least one active upstream mine
dset <- full %>%
  filter(minehuc_downstream_of_mine == 1,
         minehuc_mine == 0,
         num_coal_mines_upstream > 0,
         !is.na(POPULATION_SERVED_COUNT))

cat("Downstream + active mine rows:", nrow(dset), "\n")

# For each state × year, sum population served across qualifying CWSs
pop_state_year <- dset %>%
  group_by(STATE_CODE, year) %>%
  summarise(pop_exposed = sum(POPULATION_SERVED_COUNT, na.rm = TRUE),
            .groups = "drop")

# Assign periods and average within each period
pop_state_period <- pop_state_year %>%
  mutate(period = case_when(
    year >= 1985 & year <= 1989 ~ "early",
    year >= 2000 & year <= 2005 ~ "late",
    TRUE ~ NA_character_
  )) %>%
  filter(!is.na(period)) %>%
  group_by(STATE_CODE, period) %>%
  summarise(avg_pop = mean(pop_exposed, na.rm = TRUE), .groups = "drop")

# Net change: late minus early
pop_wide <- pop_state_period %>%
  pivot_wider(names_from = period, values_from = avg_pop, values_fill = 0) %>%
  mutate(net_change = late - early)

cat("\nPeriod averages by state:\n")
print(pop_state_period %>% arrange(desc(avg_pop)))

cat("\nNet changes (largest declines):\n")
print(pop_wide %>% arrange(net_change) %>% head(10))

# ── Shapefile ──────────────────────────────────────────────────────────────────
exclude <- c("AK", "HI", "PR", "VI", "GU", "MP", "AS")
states_sf <- tigris::states(cb = TRUE, resolution = "20m", year = 2020) %>%
  filter(!STUSPS %in% exclude)

# Cross-join all states × both periods so every state appears in both facets;
# states with no matching data keep NA fill → rendered as grey via na.value
early_sf <- states_sf %>%
  left_join(pop_state_period %>% filter(period == "early"),
            by = c("STUSPS" = "STATE_CODE")) %>%
  mutate(period_label = "1985\u20131989 (pre-ARP)")

late_sf <- states_sf %>%
  left_join(pop_state_period %>% filter(period == "late"),
            by = c("STUSPS" = "STATE_CODE")) %>%
  mutate(period_label = "2000\u20132005 (post-ARP)")

map_periods <- bind_rows(early_sf, late_sf) %>%
  mutate(period_label = factor(period_label,
                               levels = c("1985\u20131989 (pre-ARP)",
                                          "2000\u20132005 (post-ARP)")))

# Change map: states with no data stay NA → grey
map_change <- states_sf %>%
  left_join(pop_wide, by = c("STUSPS" = "STATE_CODE"))

# ── Two-panel map ──────────────────────────────────────────────────────────────
caption_two <- paste(strwrap(paste0(
  "Population served by community water systems (CWSs) located downstream of at least one ",
  "active coal mine, summed by state and averaged within each period. ",
  "Left panel: 1985\u20131989 (pre-ARP Phase I). Right panel: 2000\u20132005 (post-ARP Phase I). ",
  "Color scale is log-transformed (log\u2081\u208a(population)). ",
  "States with no downstream CWSs adjacent to active upstream mines are shown in light grey."
), width = 120), collapse = "\n")

p_two <- map_periods %>%
  ggplot() +
  geom_sf(aes(fill = avg_pop / 1e3), color = "grey30", linewidth = 0.2) +
  facet_wrap(~ period_label, ncol = 2) +
  scale_fill_distiller(
    palette   = "YlOrRd",
    direction = 1,
    trans     = "log1p",
    breaks    = c(0, 10, 50, 200, 1000),
    labels    = c("0", "10K", "50K", "200K", "1M"),
    na.value  = "white",
    name      = "Population\nexposed"
  ) +
  labs(
    title   = "Population Downstream of Active Coal Mines, Pre- and Post-ARP",
    caption = caption_two
  ) +
  theme_void(base_size = 11) +
  theme(
    plot.title         = element_text(size = 11, face = "bold", hjust = 0.5,
                                      margin = margin(b = 6)),
    strip.text         = element_text(size = 10, face = "bold", margin = margin(b = 4)),
    legend.position    = "bottom",
    legend.title       = element_text(size = 9),
    legend.text        = element_text(size = 8),
    legend.key.width   = unit(1.8, "cm"),
    plot.caption       = element_text(hjust = 0, size = 7.5, lineheight = 1.35,
                                      margin = margin(t = 8)),
    plot.caption.position = "plot",
    plot.margin        = margin(t = 6, r = 10, b = 6, l = 10)
  )

ggsave("Z:/ek559/mining_wq/output/fig/pop_exposed_two_panel.png",
       plot = p_two, width = 10, height = 5.5, dpi = 300)
cat("Saved: output/fig/pop_exposed_two_panel.png\n")

# ── Net-change map ─────────────────────────────────────────────────────────────
# PA's change (-831K) dominates a linear scale; apply symmetric log10 transform
# so small changes in lightly-exposed states remain perceptible.
map_change <- map_change %>%
  mutate(net_log = sign(net_change) * log10(abs(net_change / 1e3) + 1))

# Define breaks in original units; convert to log-transformed space for the scale
brk_orig <- c(-800, -100, -10, -1, 0, 1, 10, 100, 800)
brk_log  <- sign(brk_orig) * log10(abs(brk_orig) + 1)
brk_labs <- ifelse(brk_orig == 0, "0",
              paste0(ifelse(brk_orig > 0, "+", ""),
                     formatC(brk_orig, format = "d", big.mark = ","), "K"))

max_log <- max(abs(map_change$net_log), na.rm = TRUE)

caption_chg <- paste(strwrap(paste0(
  "Change in average annual population served by CWSs downstream of active coal mines ",
  "(2000\u20132005 average minus 1985\u20131989 average), by state. ",
  "Red indicates states where fewer people were exposed to upstream coal mining after ",
  "ARP Phase I (1995). Blue indicates increased exposure. Color scale is symmetric ",
  "log\u2081\u2080-transformed to show both large declines (Appalachia) and small shifts together. ",
  "The pattern reflects coal production shifting from densely populated Appalachian ",
  "watersheds toward sparsely populated western regions following the ARP-induced ",
  "decline in high-sulfur eastern coal."
), width = 120), collapse = "\n")

p_change <- map_change %>%
  ggplot() +
  geom_sf(aes(fill = net_log), color = "grey30", linewidth = 0.2) +
  scale_fill_gradient2(
    low      = "#b2182b",
    mid      = "white",
    high     = "#2166ac",
    midpoint = 0,
    limits   = c(-max_log, max_log),
    breaks   = brk_log,
    labels   = brk_labs,
    na.value = "white",
    name     = "Change in\npopulation"
  ) +
  labs(
    title   = "Change in Population Exposed to Upstream Coal Mining (2000\u20132005 minus 1985\u20131989)",
    caption = caption_chg
  ) +
  theme_void(base_size = 11) +
  theme(
    plot.title         = element_text(size = 11, face = "bold", hjust = 0.5,
                                      margin = margin(b = 8)),
    legend.position    = "right",
    legend.title       = element_text(size = 9),
    legend.text        = element_text(size = 8),
    plot.caption       = element_text(hjust = 0, size = 7.5, lineheight = 1.35,
                                      margin = margin(t = 8)),
    plot.caption.position = "plot",
    plot.margin        = margin(t = 6, r = 10, b = 6, l = 10)
  )

ggsave("Z:/ek559/mining_wq/output/fig/pop_exposed_change.png",
       plot = p_change, width = 9, height = 5.5, dpi = 300)
cat("Saved: output/fig/pop_exposed_change.png\n")
