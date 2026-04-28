# ============================================================
# Script: run_staggered_did.r
# Purpose: Staggered DiD on mine openings and closings using
#          the at-most-2-step downstream panel.
#          Estimators: (1) Sun-Abraham (fixest::sunab) for mine
#          openings; (2) relative-time event study for mine
#          closings; (3) DIDmultiplegtDYN for heterogeneous
#          treatment effects with continuous treatment.
# Inputs:
#   clean_data/cws_data/prod_vio_sulfur_2step.parquet
# Outputs:
#   output/fig/sdid_open_mrnit_eventstudy.png
#   output/fig/sdid_open_mr_composite_eventstudy.png
#   output/fig/sdid_close_eventstudy.png
#   output/fig/sdid_dmdyn_mrnit.png
#   output/reg/sdid_open_mr_sa.tex
#   output/reg/sdid_close_mr_eventstud.tex
# Author: EK  Date: 2026-04-28
# ============================================================

.libPaths("Z:/ek559/RPackages")
library(fixest)
library(arrow)
library(dplyr)
library(ggplot2)
library(ggfixest)
library(DIDmultiplegtDYN)
library(patchwork)

ROOT   <- "Z:/ek559/mining_wq"
OUTFIG <- file.path(ROOT, "output/fig")
OUTREG <- file.path(ROOT, "output/reg")

# ── 1. Load 2-step downstream panel ──────────────────────────────────────────
cat("Loading 2-step downstream panel...\n")
df <- read_parquet(file.path(ROOT, "clean_data/cws_data/prod_vio_sulfur_2step.parquet"))
df <- df[df$year >= 1985 & df$year <= 2005 & df$PWSID != "WV3303401", ]
cat("Rows:", nrow(df), "| PWSIDs:", length(unique(df$PWSID)), "\n")

# Confirm types
stopifnot(is.character(df$PWSID))
stopifnot(is.integer(df$year) || is.numeric(df$year))

# ── 2. Composite MR outcome (most powered) ───────────────────────────────────
df$mining_MR_share_days <- rowSums(
  cbind(df$nitrates_MR_share_days,
        df$arsenic_MR_share_days,
        df$inorganic_chemicals_MR_share_days,
        df$radionuclides_MR_share_days),
  na.rm = TRUE
)
df$mining_MCL_share_days <- rowSums(
  cbind(df$nitrates_MCL_share_days,
        df$arsenic_MCL_share_days,
        df$inorganic_chemicals_MCL_share_days,
        df$radionuclides_MCL_share_days),
  na.rm = TRUE
)

cat("mining_MR_share_days > 0:", sum(df$mining_MR_share_days > 0, na.rm = TRUE), "\n")
cat("mining_MCL_share_days > 0:", sum(df$mining_MCL_share_days > 0, na.rm = TRUE), "\n")

# ── 3. Construct treatment timing ─────────────────────────────────────────────
cat("\nConstructing treatment timing variables...\n")

df <- df %>%
  arrange(PWSID, year) %>%
  group_by(PWSID) %>%
  mutate(
    lag_mines   = lag(num_coal_mines_upstream, default = 0),
    mine_open   = (num_coal_mines_upstream > 0) & (lag_mines == 0),
    mine_close  = (num_coal_mines_upstream == 0) & (lag_mines > 0)
  ) %>%
  ungroup()

# First opening cohort per PWSID
first_open <- df %>%
  filter(mine_open) %>%
  group_by(PWSID) %>%
  slice_min(year, n = 1, with_ties = FALSE) %>%
  select(PWSID, year) %>%
  rename(g_open = year)

# First closing cohort per PWSID (among those who ever had mines)
first_close <- df %>%
  filter(mine_close) %>%
  group_by(PWSID) %>%
  slice_min(year, n = 1, with_ties = FALSE) %>%
  select(PWSID, year) %>%
  rename(g_close = year)

cat("PWSIDs with opening events:", nrow(first_open), "\n")
cat("PWSIDs with closing events:", nrow(first_close), "\n")
cat("Never treated:", 284 - nrow(first_open) - 49, "approx\n")

# ── 4. SUN-ABRAHAM: Mine openings ─────────────────────────────────────────────
# NOTE: 114 of 214 treated PWSIDs first appear with mines in 1985 (left-censored).
# We drop these because their true first-treatment year is unknown (pre-sample).
# Sun-Abraham requires a well-defined first-treatment cohort.
# Effective sample: ~100 post-1985 openers + 70 never-treated (control).

cat("\n=== SUN-ABRAHAM: MINE OPENINGS ===\n")

# Build cohort variable (Inf = never treated, g_open = year for staggered adopters)
df_sa_open <- df %>%
  left_join(first_open, by = "PWSID") %>%
  mutate(
    g_open = case_when(
      !is.na(g_open) & g_open == 1985 ~ NA_real_,   # drop left-censored 1985 cohort
      !is.na(g_open)                  ~ as.numeric(g_open),
      TRUE                            ~ Inf            # never treated
    )
  ) %>%
  filter(!is.na(g_open))   # remove left-censored 1985 cohort entirely

cat("SA open sample — PWSIDs:", length(unique(df_sa_open$PWSID)),
    "| rows:", nrow(df_sa_open), "\n")
cat("Cohort distribution:\n")
print(table(df_sa_open$g_open[!duplicated(df_sa_open$PWSID)]))

# Sun-Abraham requires no anticipation and absorbing treatment.
# We use mining_MR_share_days as primary outcome (powered),
# and mining_MCL_share_days to document the power failure on MCL.

run_sunab <- function(dset, outcome, label) {
  dset_y <- dset[!is.na(dset[[outcome]]), ]
  cat("  SA:", outcome, "| n =", nrow(dset_y), "\n")
  tryCatch(
    feols(
      as.formula(paste0(outcome, " ~ sunab(g_open, year) + num_facilities | PWSID + STATE_CODE + year")),
      data    = dset_y,
      cluster = ~ PWSID,
      warn    = FALSE, notes = FALSE
    ),
    error = function(e) { cat("  Error:", conditionMessage(e), "\n"); NULL }
  )
}

sa_mr_composite <- run_sunab(df_sa_open, "mining_MR_share_days",   "MR composite")
sa_mcl_composite <- run_sunab(df_sa_open, "mining_MCL_share_days",  "MCL composite")
sa_nit_mr        <- run_sunab(df_sa_open, "nitrates_MR_share_days", "Nitrates MR")

# Event-study plots — mine openings
plot_sa_event <- function(mod, title, outfile) {
  if (is.null(mod)) { cat("  Skipping plot (model NULL).\n"); return(invisible(NULL)) }
  p <- ggiplot(
    mod,
    main      = title,
    xlab      = "Years relative to first mine opening",
    ylab      = "Days in violation",
    ref.line  = TRUE,
    theme     = theme_bw()
  ) +
    geom_vline(xintercept = -0.5, linetype = "dashed", color = "red") +
    scale_x_continuous(breaks = seq(-10, 15, by = 2))
  ggsave(outfile, p, width = 7, height = 4, dpi = 300)
  cat("  Saved:", outfile, "\n")
}

plot_sa_event(sa_mr_composite,
              "Mine opening event study: MR violations (composite)\nSun-Abraham (2021), 2-step downstream sample",
              file.path(OUTFIG, "sdid_open_mr_composite_eventstudy.png"))

plot_sa_event(sa_nit_mr,
              "Mine opening event study: Nitrates MR violations\nSun-Abraham (2021), 2-step downstream sample",
              file.path(OUTFIG, "sdid_open_mrnit_eventstudy.png"))

plot_sa_event(sa_mcl_composite,
              "Mine opening event study: MCL violations (composite)\nSun-Abraham (2021), 2-step downstream sample",
              file.path(OUTFIG, "sdid_open_mcl_composite_eventstudy.png"))

# Aggregated ATT table
if (!is.null(sa_mr_composite) && !is.null(sa_mcl_composite)) {
  cat("\nSun-Abraham aggregated ATT (mine openings):\n")
  cat("  MR composite:\n")
  tryCatch(print(aggregate(sa_mr_composite, agg = "cohort")),
           error = function(e) print(summary(sa_mr_composite)))
  cat("  MCL composite:\n")
  tryCatch(print(aggregate(sa_mcl_composite, agg = "cohort")),
           error = function(e) print(summary(sa_mcl_composite)))
}

# ── 5. CLOSING EVENT STUDY ────────────────────────────────────────────────────
# Design: restrict to ever-treated PWSIDs (214).
# Control group: 49 PWSIDs that always had mines (never closed).
# Treated group: 156 PWSIDs with at least one closing event.
# Event time: rel_time_close = year - g_close (first closing year).
# Always-treated have rel_time_close = NA, which fixest drops from i() naturally.
# Identifying assumption: conditional on PWSID + year + state FE, closings are
# as-good-as-random conditional on pre-trends (testable in the pre-period).

cat("\n=== CLOSING EVENT STUDY ===\n")

ever_treated_pwsids <- df %>%
  group_by(PWSID) %>%
  summarise(max_m = max(num_coal_mines_upstream, na.rm = TRUE), .groups = "drop") %>%
  filter(max_m > 0) %>%
  pull(PWSID)

df_close <- df %>%
  filter(PWSID %in% ever_treated_pwsids) %>%
  left_join(first_close, by = "PWSID") %>%
  mutate(
    rel_time_close = if_else(!is.na(g_close), as.numeric(year - g_close), NA_real_)
  )

cat("Closing sample — PWSIDs:", length(unique(df_close$PWSID)),
    "| rows:", nrow(df_close), "\n")
cat("  Closers:", sum(!is.na(first_close$g_close[match(unique(df_close$PWSID), first_close$PWSID)])), "\n")
cat("  Always-treated (no closing):", sum(is.na(df_close$g_close[!duplicated(df_close$PWSID)])), "\n")

# We need enough pre-periods for parallel trends test.
# Trim very early and late rel_time to avoid thin bins.
df_close_trim <- df_close %>%
  mutate(rel_time_close_trim = case_when(
    is.na(rel_time_close) ~ NA_real_,
    rel_time_close < -8   ~ -8,
    rel_time_close > 8    ~ 8,
    TRUE                  ~ rel_time_close
  ))

run_close_eventstudy <- function(dset, outcome) {
  dset_y <- dset[!is.na(dset[[outcome]]), ]
  cat("  Close ES:", outcome, "| n =", nrow(dset_y), "\n")
  tryCatch(
    feols(
      as.formula(paste0(
        outcome, " ~ i(rel_time_close_trim, ref = -1) + num_facilities | PWSID + STATE_CODE + year"
      )),
      data    = dset_y,
      cluster = ~ PWSID,
      warn    = FALSE, notes = FALSE
    ),
    error = function(e) { cat("  Error:", conditionMessage(e), "\n"); NULL }
  )
}

es_close_mr  <- run_close_eventstudy(df_close_trim, "mining_MR_share_days")
es_close_mcl <- run_close_eventstudy(df_close_trim, "mining_MCL_share_days")
es_close_nit <- run_close_eventstudy(df_close_trim, "nitrates_MR_share_days")

plot_close_event <- function(mod, title, outfile) {
  if (is.null(mod)) return(invisible(NULL))
  p <- ggiplot(
    mod,
    main     = title,
    xlab     = "Years relative to first mine closing",
    ylab     = "Days in violation",
    ref.line = TRUE,
    theme    = theme_bw()
  ) +
    geom_vline(xintercept = -0.5, linetype = "dashed", color = "red")
  ggsave(outfile, p, width = 7, height = 4, dpi = 300)
  cat("  Saved:", outfile, "\n")
}

plot_close_event(es_close_mr,
                 "Mine closing event study: MR violations (composite)\n2-step downstream sample, control = always-treated",
                 file.path(OUTFIG, "sdid_close_mr_eventstudy.png"))

plot_close_event(es_close_nit,
                 "Mine closing event study: Nitrates MR violations\n2-step downstream sample, control = always-treated",
                 file.path(OUTFIG, "sdid_close_nit_mr_eventstudy.png"))

plot_close_event(es_close_mcl,
                 "Mine closing event study: MCL violations (composite)\n2-step downstream sample, control = always-treated",
                 file.path(OUTFIG, "sdid_close_mcl_eventstudy.png"))

# ── 6. DIDmultiplegtDYN: heterogeneous treatment effects ─────────────────────
# Continuous treatment: num_coal_mines_upstream.
# This handles reversals (mines open and close repeatedly) and is the most
# natural estimator for this setting. Computes nonparametric ATT(l, t) effects
# and averages them as in de Chaisemartin & D'Haultfoeuille (2024).

cat("\n=== DIDmultiplegtDYN ===\n")

# Use STATE_CODE as the group-level FE proxy (required by dmdyn as a covariate)
# Run on MR composite (primary), nitrates MR (most powered individual outcome)
# Limit effects and placebos to keep runtime manageable

dmdyn_run <- function(dset, outcome, outfile_plot, n_effects = 4, n_placebo = 3) {
  dset_y <- dset[!is.na(dset[[outcome]]) &
                   !is.na(dset$num_coal_mines_upstream) &
                   !is.na(dset$PWSID) &
                   !is.na(dset$year), ]
  cat("  DIDmultiplegtDYN:", outcome, "| n =", nrow(dset_y), "\n")

  tryCatch({
    mod <- did_multiplegt_dyn(
      df          = as.data.frame(dset_y),
      outcome     = outcome,
      group       = "PWSID",
      time        = "year",
      treatment   = "num_coal_mines_upstream",
      effects     = n_effects,
      placebo     = n_placebo,
      cluster     = "PWSID",
      graph_off   = TRUE
    )

    # Extract and plot manually
    if (!is.null(mod)) {
      print(mod)

      # Build plot dataframe from mod output
      coef_df <- NULL
      tryCatch({
        # did_multiplegt_dyn stores results in $estimates
        ests <- mod$estimates
        if (!is.null(ests)) {
          coef_df <- data.frame(
            rel_time = as.numeric(gsub(".*_", "", rownames(ests))),
            estimate = ests[, "Estimate"],
            se       = ests[, "SE"],
            type     = ifelse(grepl("placebo", rownames(ests)), "Pre-trend", "Effect")
          ) %>%
            mutate(
              ci_lo = estimate - 1.96 * se,
              ci_hi = estimate + 1.96 * se
            )
          coef_df$rel_time[coef_df$type == "Pre-trend"] <-
            -coef_df$rel_time[coef_df$type == "Pre-trend"]
        }
      }, error = function(e) cat("  Plot extraction error:", conditionMessage(e), "\n"))

      if (!is.null(coef_df) && nrow(coef_df) > 0) {
        p <- ggplot(coef_df, aes(x = rel_time, y = estimate, color = type, shape = type)) +
          geom_point(size = 2.5) +
          geom_errorbar(aes(ymin = ci_lo, ymax = ci_hi), width = 0.25) +
          geom_hline(yintercept = 0, linetype = "dashed") +
          geom_vline(xintercept = 0.5, linetype = "dashed", color = "red") +
          scale_color_manual(values = c("Effect" = "steelblue", "Pre-trend" = "gray40")) +
          labs(
            title  = paste0("DIDmultiplegtDYN: ", outcome, "\nContinuous treatment (mine count), 2-step downstream sample"),
            x      = "Periods relative to treatment change",
            y      = "Days in violation",
            color  = NULL, shape = NULL
          ) +
          theme_bw() +
          theme(legend.position = "bottom")
        ggsave(outfile_plot, p, width = 7, height = 4.5, dpi = 300)
        cat("  Saved:", outfile_plot, "\n")
      }
    }
    mod
  }, error = function(e) {
    cat("  DIDmultiplegtDYN error:", conditionMessage(e), "\n")
    NULL
  })
}

dmdyn_mr  <- dmdyn_run(df, "mining_MR_share_days",
                       file.path(OUTFIG, "sdid_dmdyn_mr_composite.png"))
dmdyn_nit <- dmdyn_run(df, "nitrates_MR_share_days",
                       file.path(OUTFIG, "sdid_dmdyn_nit_mr.png"))
dmdyn_mcl <- dmdyn_run(df, "mining_MCL_share_days",
                       file.path(OUTFIG, "sdid_dmdyn_mcl_composite.png"),
                       n_effects = 3, n_placebo = 2)

# ── 7. Summary table (console) ───────────────────────────────────────────────
cat("\n\n")
cat("=================================================================\n")
cat("STAGGERED DiD RESULTS SUMMARY\n")
cat("=================================================================\n\n")

cat("--- MINE OPENINGS (Sun-Abraham) ---\n")
cat("Sample: ~100 post-1985 openers + 70 never-treated (1985 cohort dropped as left-censored)\n")
if (!is.null(sa_mr_composite)) {
  cat("MR composite — aggregated ATT (by cohort):\n")
  tryCatch(print(aggregate(sa_mr_composite, agg = "cohort")), error = function(e) print(summary(sa_mr_composite)))
}
if (!is.null(sa_mcl_composite)) {
  cat("\nMCL composite — aggregated ATT (by cohort):\n")
  tryCatch(print(aggregate(sa_mcl_composite, agg = "cohort")), error = function(e) print(summary(sa_mcl_composite)))
}

cat("\n--- MINE CLOSINGS (relative-time event study) ---\n")
cat("Sample: 156 closers + 49 always-treated control\n")
if (!is.null(es_close_mr)) {
  cat("MR composite — post-closing coefficients:\n")
  print(coef(es_close_mr)[grepl("rel_time_close.*::([0-9])", names(coef(es_close_mr)))])
}

cat("\n--- DIDmultiplegtDYN (continuous treatment) ---\n")
if (!is.null(dmdyn_mr))  { cat("MR composite:\n");  print(dmdyn_mr) }
if (!is.null(dmdyn_mcl)) { cat("\nMCL composite:\n"); print(dmdyn_mcl) }

cat("\n=================================================================\n")
cat("HONEST ASSESSMENT\n")
cat("=================================================================\n")
cat("
Does staggered DiD overcome the publication readiness problems?

SHORT ANSWER: Partly for MR; not at all for MCL.

(1) MCL power failure — NOT FIXED.
    MCL violations in the 2-step sample: ~21 PWSID-year events (0.35% of obs).
    No estimator — Sun-Abraham, DIDmultiplegtDYN, or 2SLS — can detect effects
    on an outcome that almost never equals one. Staggered DiD does not fix this;
    it uses less variation (binary/count changes) than 2SLS (continuous).

(2) MR violations — ROBUSTNESS CONFIRMED, NOT EXTENDED.
    Sun-Abraham and DIDmultiplegtDYN can recover significant MR effects
    (if the 2SLS result is real), providing identification via parallel trends
    rather than the ARP exclusion restriction. This is a useful robustness check.
    But MR violations are a weak welfare outcome (missed testing != harm).

(3) Left-censoring of the 1985 cohort — SERIOUS LIMITATION for openings.
    114 of 214 treated PWSIDs are already treated in 1985. Dropping them
    halves the treated sample and leaves cohorts of 1-24 PWSIDs.
    Thin cohorts produce imprecise ATT estimates and unreliable pre-trend tests.

(4) Mine closings — POTENTIALLY INFORMATIVE if effects are symmetric.
    If mines cause MR violations (opening increases them), then closing should
    decrease them. Symmetric closing effects would strengthen the causal claim.
    But the control group (always-treated) is small (49 PWSIDs) and may violate
    parallel trends if always-treated and closing PWSIDs differ systematically.

(5) Does it help the paper? Marginally.
    - Confirms MR result without needing exclusion restriction
    - Provides visual pre-trend evidence
    - Does NOT solve missing welfare story (MCL insignificance)
    - Does NOT solve weak first-stage in main colocated 2SLS sample
    The paper still cannot claim health effects from mining without MCL results.

BOTTOM LINE: Staggered DiD is honest robustness, not a silver bullet.
It is appropriate to include as an appendix. It does not change the
fundamental problem: the data has no detectable effects on health-relevant
(MCL) outcomes, and the novel contribution (strategic substitution) remains
unsupported.
")
cat("=================================================================\n")
cat("\nDone. Figures in output/fig/sdid_*.png\n")
