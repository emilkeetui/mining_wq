# ============================================================
# Script: monitoring_retesting_sanitary_visit.r
# Purpose: Version of monitoring_retesting_hazard.r cols 1-3 (LPM/LPM-FE/logit
#          on the CWS x chemical x test LPM sample) with the dependent
#          variable replaced by "sanitary visit at the CWS within a rolling
#          365-day window after the test" instead of "re-tested for this
#          chemical in t+1". Uses exact sample dates (not calendar years) on
#          both sides of the window. Restricted to the main 2SLS downstream-
#          only CWS sample and the 5 IOC contaminants (arsenic, barium,
#          chromium, nitrate, selenium). Hazard-panel columns (4-6 in the
#          original table) are not recreated.
# Inputs:  clean_data/cws_6year_review_measurement_level_full.parquet
#          (downstream-only, 5-IOC measurement-level panel; built by
#          cws_6year_review_measurement_dates_full.py)
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_SITE_VISITS.csv
# Outputs: output/reg/monitoring_retesting_sanitary_visit.tex
# Author: EK  Date: 2026-07-11
# ============================================================

library(arrow)
library(dplyr)
library(tidyr)
library(data.table)
library(fixest)

ROOT     <- "z:/ek559/mining_wq"
SDWA_DIR <- "Z:/ek559/sdwa_violations/SDWA_latest_downloads"

# ── 1. Load measurement readings (measurement-level, exact sample_date) ─────
df_raw <- read_parquet(file.path(ROOT, "clean_data/cws_6year_review_measurement_level_full.parquet"))

meas <- df_raw |>
  filter(!is.na(VALUE), YEAR <= 2005L) |>
  select(PWSID, sample_date, YEAR, CHEMID_name, VALUE) |>
  mutate(sample_date = as.Date(sample_date)) |>
  arrange(PWSID, CHEMID_name, sample_date)

cat("Measurement rows:", nrow(meas), "\n")
cat("PWSID x chemical combos:", n_distinct(paste(meas$PWSID, meas$CHEMID_name)), "\n")

# ── 2. Z-score VALUE within CWS x chemical (removes CWS baseline-level differences) ──
pwsid_chem_stats <- meas |>
  group_by(PWSID, CHEMID_name) |>
  summarise(v_mean = mean(VALUE), v_sd = sd(VALUE), .groups = "drop")

meas <- meas |>
  left_join(pwsid_chem_stats, by = c("PWSID", "CHEMID_name")) |>
  mutate(value_z = (VALUE - v_mean) / v_sd)

cat("PWSID x chemical combos with singleton SD (value_z = NA):",
    sum(is.na(meas$v_sd)), "of", n_distinct(paste(meas$PWSID, meas$CHEMID_name)), "combos\n\n")

# ── 3. Build features, sorted by exact sample_date within CWS x chemical ────
meas_feats <- meas |>
  group_by(PWSID, CHEMID_name) |>
  arrange(sample_date, .by_group = TRUE) |>
  mutate(
    running_mean_z         = cummean(value_z),
    years_since_last_test  = as.numeric(sample_date - lag(sample_date)) / 365.25
  ) |>
  ungroup()

# ── 4. LPM dataset (PWSID x chemical x test date) ────────────────────────────
# Right-censor: drop tests whose forward 365-day window extends past the last
# date covered by the sanitary-visit data pull (2005-12-31) -- outcome would
# be unobservable.
CENSOR_DATE <- as.Date("2005-12-31")

lpm_data <- meas_feats |>
  filter(sample_date + 365 <= CENSOR_DATE) |>
  rename(last_level_z = value_z, mean_level_z = running_mean_z) |>
  select(PWSID, CHEMID_name, sample_date, YEAR, last_level_z, mean_level_z, years_since_last_test) |>
  mutate(row_id = row_number())

cat("LPM rows:", nrow(lpm_data), "\n\n")

# ── 5. Sanitary visit indicator: any sanitary-survey visit at the CWS within ──
#      (sample_date, sample_date + 365] -- true rolling 12-month window using
#      exact dates on both sides. Visit reasons SNSV/SNSP/SSVF, consistent
#      with sanitary_visit_enforcement_lag.r.
san_reasons <- c("SNSV", "SNSP", "SSVF")

sv <- read.csv(file.path(SDWA_DIR, "SDWA_SITE_VISITS.csv"),
                colClasses = "character", na.strings = c("", "NA"))
sv <- sv |>
  select(PWSID, VISIT_DATE, VISIT_REASON_CODE) |>
  mutate(visit_dt = as.Date(VISIT_DATE, "%m/%d/%Y")) |>
  filter(!is.na(visit_dt), VISIT_REASON_CODE %in% san_reasons) |>
  filter(visit_dt >= as.Date("1985-01-01"), visit_dt <= CENSOR_DATE) |>
  select(PWSID, visit_dt)

cat("Sanitary visit records:", nrow(sv), "\n\n")

sv_dt  <- as.data.table(sv)
lpm_dt <- as.data.table(lpm_data)
lpm_dt[, window_start := sample_date + 1]
lpm_dt[, window_end   := sample_date + 365]

matches <- lpm_dt[sv_dt,
                   on = .(PWSID, window_start <= visit_dt, window_end >= visit_dt),
                   allow.cartesian = TRUE, nomatch = NULL]
matched_rows <- unique(matches$row_id)

lpm_dt[, sanitary_visit_next365 := as.integer(row_id %in% matched_rows)]
lpm_data <- as.data.frame(lpm_dt) |> select(-window_start, -window_end, -row_id)

cat("Mean(sanitary_visit_next365):", round(mean(lpm_data$sanitary_visit_next365), 3), "\n\n")

# ── 6. Regressions (cols 1-3 of monitoring_retesting_hazard.tex, new outcome) ─
# year used for the col 2/3 fixed effect is the calendar year of the test.
lpm_data <- lpm_data |> rename(year = YEAR)

# Col 1: LPM, no fixed effects
m1 <- feols(sanitary_visit_next365 ~ last_level_z + mean_level_z + years_since_last_test,
            data    = lpm_data,
            cluster = ~PWSID)

# Col 2: LPM, CWS + year fixed effects
m2 <- feols(sanitary_visit_next365 ~ last_level_z + mean_level_z + years_since_last_test | PWSID + year,
            data    = lpm_data,
            cluster = ~PWSID)

# Col 3: Logit, CWS + year fixed effects
m3 <- feglm(sanitary_visit_next365 ~ last_level_z + mean_level_z + years_since_last_test | PWSID + year,
            data    = lpm_data,
            cluster = ~PWSID,
            family  = binomial)

cat("\n--- M1 (LPM no FE) ---\n");         print(summary(m1))
cat("\n--- M2 (LPM CWS+year FE) ---\n");   print(summary(m2))
cat("\n--- M3 (Logit CWS+year FE) ---\n"); print(summary(m3))

# ── 7. Post-processing helper (identical to monitoring_retesting_hazard.r) ───
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
setFixest_dict(c(
  sanitary_visit_next365 = "Sanitary visit within 365 days"
))

dir.create(file.path(ROOT, "output/reg"), showWarnings = FALSE, recursive = TRUE)
out_tex <- file.path(ROOT, "output/reg/monitoring_retesting_sanitary_visit.tex")

etable(
  m1, m2, m3,
  style.tex = style.tex("aer", adjustbox = TRUE),
  title     = "Effect of Contaminant Level on Likelihood of a Sanitary Visit (SYR2 CWSs)",
  label     = "tab:monitoring_retesting_sanitary_visit",
  dict      = c(
    last_level_z          = "Last level (z-score)",
    mean_level_z          = "Mean level (z-score)",
    years_since_last_test = "Years since last test",
    PWSID                 = "CWS",
    year                  = "Year"
  ),
  notes = paste0(
    "Unit = CWS $\\times$ chemical $\\times$ test date (measurement-level SYR2 sample, ",
    "not collapsed to PWSID $\\times$ chemical $\\times$ year, so the rolling window ",
    "can be anchored to the exact test date); outcome = 1 if the CWS received a ",
    "sanitary survey visit (VISIT\\_REASON\\_CODE $\\in$ \\{SNSV, SNSP, SSVF\\}) with an ",
    "exact visit date within 365 days after the exact test date (rolling window, not ",
    "calendar-year adjacency). Cols 1--2 are LPM; col 3 is logit. ",
    "Col 1 has no fixed effects; cols 2--3 include CWS and calendar-year (of test) fixed effects. ",
    "Last level and mean level are z-scored against the distribution of all ",
    "observations of that contaminant at that CWS; mean level is the cumulative ",
    "mean of the z-scored readings through this test, in chronological order of the ",
    "exact test date. Years since last test = exact days since the prior test for ",
    "that CWS $\\times$ chemical, divided by 365.25. Tests whose 365-day forward ",
    "window would extend past 2005-12-31 are dropped (right-censored). ",
    "SEs clustered at CWS level. ",
    "Sample: strictly downstream-only CWSs (minehuc\\_downstream\\_of\\_mine==1 \\& ",
    "minehuc\\_mine==0, the main 2SLS sample cut), 5 IOC contaminants (arsenic, barium, ",
    "chromium, nitrate, selenium), 1998--2005."
  ),
  fitstat         = ~r2 + n,
  postprocess.tex = move_notes_below_adjustbox,
  file            = out_tex
)

cat("\nTable written to:", out_tex, "\n")

# ── 9. Verification ───────────────────────────────────────────────────────────
stopifnot(file.exists(out_tex), file.info(out_tex)$size > 0)
cat("Output verified: table exists and is non-zero.\n")
cat("=== DONE ===\n")
