# ============================================================
# Script: monitoring_retesting_hazard.r
# Purpose: Estimate whether contaminant level predicts re-testing (SYR2)
# Inputs:  clean_data/cws_6year_review.parquet
# Outputs: output/reg/monitoring_retesting_hazard.tex
# Author: EK  Date: 2026-07-01
# ============================================================

library(arrow)
library(dplyr)
library(tidyr)
library(fixest)

ROOT <- "z:/ek559/mining_wq"

# ── 1. Load measurement readings ─────────────────────────────────────────────
df_raw <- read_parquet(file.path(ROOT, "clean_data/cws_6year_review.parquet"))

meas <- df_raw |>
  filter(!is.na(VALUE), year <= 2005L) |>
  select(PWSID, year, CHEMID_name, VALUE) |>
  arrange(PWSID, CHEMID_name, year)

cat("Measurement rows:", nrow(meas), "\n")
cat("PWSID x chemical combos:", n_distinct(paste(meas$PWSID, meas$CHEMID_name)), "\n")
cat("Chemicals:", paste(sort(unique(meas$CHEMID_name)), collapse = ", "), "\n")
cat("Year range:", range(meas$year), "\n\n")

# ── 2. Z-score VALUE within chemical (units differ across chemicals) ──────────
chem_stats <- meas |>
  group_by(CHEMID_name) |>
  summarise(v_mean = mean(VALUE), v_sd = sd(VALUE), .groups = "drop")

meas <- meas |>
  left_join(chem_stats, by = "CHEMID_name") |>
  mutate(value_z = (VALUE - v_mean) / v_sd)

# ── 3. Build features shared by both models ───────────────────────────────────
# Per PWSID x chemical, sorted by year:
#   running_mean_z      = cummean(value_z) through this test (inclusive)
#   year_next           = year of the next test (NA if this is the last)
#   year_prev           = year of the prior test (NA if this is the first)
#   years_since_last_test = gap to prior test; NA for first test in series
#   year_end            = min(year_next, 2011); determines end of at-risk window

CENSOR_YR <- 2005L

meas_feats <- meas |>
  group_by(PWSID, CHEMID_name) |>
  arrange(year, .by_group = TRUE) |>
  mutate(
    running_mean_z        = cummean(value_z),
    year_next             = lead(year),
    years_since_last_test = year - lag(year)
  ) |>
  ungroup() |>
  mutate(
    year_end = pmin(coalesce(year_next, CENSOR_YR), CENSOR_YR)
  )

# ── 4. LPM dataset (PWSID x chemical x test-year) ────────────────────────────
# Outcome: did they submit a reading in the immediately following calendar year?
# Covariates: level at this test (last_level_z), running mean through this test (mean_level_z)
# Drop year == CENSOR_YR: outcome unobservable (right-censored)

lpm_data <- meas_feats |>
  filter(year < CENSOR_YR) |>
  mutate(
    tested_next_yr = as.integer(!is.na(year_next) & year_next == year + 1L)
  ) |>
  rename(last_level_z = value_z, mean_level_z = running_mean_z) |>
  select(PWSID, CHEMID_name, year, last_level_z, mean_level_z,
         years_since_last_test, tested_next_yr)

cat("LPM rows:", nrow(lpm_data), "\n")
cat("Mean(tested_next_yr):", round(mean(lpm_data$tested_next_yr), 3), "\n\n")

# ── 5. Discrete-time hazard panel (PWSID x chemical x at-risk-year) ───────────
# After each test, expand to all subsequent at-risk years through year_end.
# Rows where year_at_risk == year_next are events (tested = 1); others are 0.
# last_level_z and mean_level_prior_z are constant within each spell.

hazard_data <- meas_feats |>
  filter(year + 1L <= year_end) |>            # skip if no at-risk years exist
  rowwise() |>
  mutate(year_at_risk = list(seq(year + 1L, year_end))) |>
  unnest(year_at_risk) |>
  mutate(
    tested           = as.integer(!is.na(year_next) & year_at_risk == year_next),
    years_since_test = year_at_risk - year
  ) |>
  rename(
    last_level_z       = value_z,
    mean_level_prior_z = running_mean_z
  ) |>
  select(PWSID, CHEMID_name, year_at_risk, last_level_z, mean_level_prior_z,
         years_since_test, tested)

cat("Hazard panel rows:", nrow(hazard_data), "\n")
cat("Events (tested = 1):", sum(hazard_data$tested), "\n")
cat("Event rate:", round(mean(hazard_data$tested), 3), "\n\n")

# ── 6. Regressions ───────────────────────────────────────────────────────────

# Col 1: LPM, no fixed effects; years_since_last_test captures persistence in testing schedule
m1 <- feols(tested_next_yr ~ last_level_z + mean_level_z + years_since_last_test,
            data    = lpm_data,
            cluster = ~PWSID)

# Col 2: LPM, CWS fixed effects
m2 <- feols(tested_next_yr ~ last_level_z + mean_level_z + years_since_last_test | PWSID,
            data    = lpm_data,
            cluster = ~PWSID)

# Col 3: Logit on lpm_data with same variables + CWS FE as col 2
m3 <- feglm(tested_next_yr ~ last_level_z + mean_level_z + years_since_last_test | PWSID,
            data    = lpm_data,
            cluster = ~PWSID,
            family  = binomial)

# Col 4: Discrete-time hazard LPM, no fixed effects
m4 <- feols(tested ~ last_level_z + mean_level_prior_z + years_since_test,
            data    = hazard_data,
            cluster = ~PWSID)

# Col 5: Discrete-time hazard LPM, year + chemical fixed effects
m5 <- feols(tested ~ last_level_z + mean_level_prior_z + years_since_test |
              year_at_risk + CHEMID_name,
            data    = hazard_data,
            cluster = ~PWSID)

# Col 6: Discrete-time hazard logit, year + chemical fixed effects
m6 <- feglm(tested ~ last_level_z + mean_level_prior_z + years_since_test |
              year_at_risk + CHEMID_name,
            data    = hazard_data,
            cluster = ~PWSID,
            family  = binomial)

cat("\n--- M1 (LPM no FE) ---\n");    print(summary(m1))
cat("\n--- M2 (LPM CWS FE) ---\n");  print(summary(m2))
cat("\n--- M3 (Logit CWS FE) ---\n"); print(summary(m3))
cat("\n--- M4 (Hazard LPM no FE) ---\n"); print(summary(m4))
cat("\n--- M5 (Hazard LPM FE) ---\n");   print(summary(m5))
cat("\n--- M6 (Logit hazard) ---\n");    print(summary(m6))

# ── 7. Post-processing helper ────────────────────────────────────────────────
# style.tex("aer", adjustbox=TRUE) places notes inside the adjustbox, causing
# them to be scaled. Move notes outside so they render at normal size.
move_notes_below_adjustbox <- function(x) {
  x           <- paste(x, collapse = "\n")
  end_adj     <- "\\end{adjustbox}"
  par_rag     <- "\\par \\raggedright"
  par_pos     <- regexpr(par_rag, x, fixed = TRUE)
  end_adj_pos <- regexpr(end_adj, x, fixed = TRUE)
  if (par_pos[1] == -1 || end_adj_pos[1] == -1) return(x)
  note_block <- substr(x, par_pos[1], end_adj_pos[1] - 1)
  x <- sub(note_block, "", x, fixed = TRUE)
  x <- sub(end_adj,
            paste0(end_adj, "\n   {\\tiny\\linespread{1}\\selectfont ",
                   trimws(note_block), "}"),
            x, fixed = TRUE)
  x
}

# ── 8. LaTeX table ───────────────────────────────────────────────────────────
# Clean display names for dep vars and FE labels
setFixest_dict(c(
  tested_next_yr = "Tested in $t+1$",
  tested         = "Tested",
  year_at_risk   = "Year",
  CHEMID_name    = "Chemical"
))

dir.create(file.path(ROOT, "output/reg"), showWarnings = FALSE, recursive = TRUE)
out_tex <- file.path(ROOT, "output/reg/monitoring_retesting_hazard.tex")

etable(
  m1, m2, m3, m4, m5, m6,
  style.tex = style.tex("aer", adjustbox = TRUE),
  title     = "Effect of Contaminant Level on Likelihood of Re-Testing (SYR2 CWSs)",
  label     = "tab:monitoring_retesting",
  dict      = c(
    last_level_z          = "Last level (z-score)",
    mean_level_z          = "Mean level (z-score)",
    mean_level_prior_z    = "Mean level (z-score)",
    years_since_last_test = "Years since last test",
    years_since_test      = "Years since last test",
    PWSID                 = "CWS",
    year_at_risk          = "Year",
    CHEMID_name           = "Chemical"
  ),
  notes = paste0(
    "Cols 1--3: unit = CWS $\\times$ chemical $\\times$ test year (LPM data); ",
    "outcome = 1 if CWS submitted a reading for the same chemical in the following ",
    "calendar year. Cols 1--2 are LPM; col 3 is logit; all include years since last test. ",
    "Cols 4--6: discrete-time hazard panel; ",
    "unit = CWS $\\times$ chemical $\\times$ at-risk year; ",
    "outcome = 1 if CWS tested that year. ",
    "Col 4 is LPM without fixed effects; col 5 is LPM with year and chemical fixed effects; ",
    "col 6 is logit with year and chemical fixed effects. ",
    "All contaminant levels z-scored within chemical. ",
    "Years since last test controls for persistence in the testing schedule (cols 1--3) ",
    "and baseline hazard shape (cols 4--6). ",
    "SEs clustered at CWS level. ",
    "Sample: SYR2 CWSs, 1998--2005."
  ),
  fitstat         = ~r2 + n,
  postprocess.tex = move_notes_below_adjustbox,
  file            = out_tex
)

cat("\nTable written to:", out_tex, "\n")
