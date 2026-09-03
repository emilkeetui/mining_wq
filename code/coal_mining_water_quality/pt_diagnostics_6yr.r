# ============================================================
# Script: pt_diagnostics_6yr.r
# Purpose: Parallel-trends diagnostics for the 6-Year Review
#          continuous-dose regressions (Table 6yr_huc02fe_inorg_*).
#          (A) Cross-sectional balance test: pre-determined CWS
#              characteristics vs. subsequent upstream coal dose,
#              on the actual 6YR estimation sample.
#          (B) Continuous-dose event study on SDWA violations for
#              CWSs whose upstream mining begins 1986-1997, where
#              pre-treatment outcome periods are observable.
# Inputs:  clean_data/cws_6year_review_ravalli.parquet
#          clean_data/cws_data/pwsid_huc02.parquet
#          clean_data/cws_data/cws_geopop_annual.parquet
#          clean_data/cws_data/prod_vio_sulfur.parquet
# Outputs: output/reg/pt_balance_6yr.tex
#          output/reg/pt_eventstudy_violations.tex
#          output/fig/pt_eventstudy_violations.png
# Author: EK  Date: 2026-07-27
# ============================================================

.libPaths("Z:/ek559/RPackages")
suppressPackageStartupMessages({
  library(fixest)
  library(arrow)
  library(dplyr)
  library(ggplot2)
})

PROJECT_ROOT <- "Z:/ek559/mining_wq"
SIX_YR_PATH  <- file.path(PROJECT_ROOT, "clean_data", "cws_6year_review_ravalli.parquet")
HUC02_PATH   <- file.path(PROJECT_ROOT, "clean_data", "cws_data", "pwsid_huc02.parquet")
GEOPOP_PATH  <- file.path(PROJECT_ROOT, "clean_data", "cws_data", "cws_geopop_annual.parquet")
VIOL_PATH    <- file.path(PROJECT_ROOT, "clean_data", "cws_data", "prod_vio_sulfur.parquet")
OUT_REG      <- file.path(PROJECT_ROOT, "output", "reg")
OUT_FIG      <- file.path(PROJECT_ROOT, "output", "fig")

PROD_VAR <- "production_short_tons_coal_upstream_sum"

# ---------------------------------------------------------------------------
# LaTeX helper (copied from cws_6year_review_huc02fe.r)
# ---------------------------------------------------------------------------
move_notes_below_adjustbox <- function(x) {
  x <- paste(x, collapse = "\n")
  end_adj <- "\\end{adjustbox}"
  par_rag <- "\\par \\raggedright"
  par_pos     <- regexpr(par_rag, x, fixed = TRUE)
  end_adj_pos <- regexpr(end_adj, x, fixed = TRUE)
  if (par_pos[1] == -1 || end_adj_pos[1] == -1) return(x)
  note_block <- substr(x, par_pos[1], end_adj_pos[1] - 1)
  x <- sub(note_block, "", x, fixed = TRUE)
  x <- sub(end_adj, paste0(end_adj, "\n   {\\tiny\\linespread{1}\\selectfont ",
                            trimws(note_block), "}"), x, fixed = TRUE)
  x
}

# Right-align the model-coefficient columns (fixest's default is centered,
# which does not decimal-align numbers of differing digit-width), leaving the
# leading row-label column ('l') untouched. Copied from run_main_tables.r.
right_align_tabular <- function(x) {
  x <- paste(x, collapse = "\n")
  m <- regmatches(x, regexpr("\\\\begin\\{tabular\\}\\{l+c+\\}", x))
  if (length(m) == 1 && nzchar(m)) {
    x <- sub(m, gsub("c", "r", m), x, fixed = TRUE)
  }
  x
}

postprocess_bal_table <- function(x) right_align_tabular(move_notes_below_adjustbox(x))

# ---------------------------------------------------------------------------
# Load
# ---------------------------------------------------------------------------
cat("Reading 6YR (Ravalli):", SIX_YR_PATH, "\n")
df6_raw <- read_parquet(SIX_YR_PATH)
huc02   <- read_parquet(HUC02_PATH)
geopop  <- read_parquet(GEOPOP_PATH)

stopifnot(is.character(df6_raw$PWSID), is.character(huc02$PWSID))
cat("Loaded:", nrow(df6_raw), "rows\n")

# ---------------------------------------------------------------------------
# Replicate the estimation-sample construction from cws_6year_review_huc02fe.r
# ---------------------------------------------------------------------------
df <- df6_raw |> left_join(huc02 |> select(PWSID, huc02), by = "PWSID")
df <- df[df$year >= 1985, ]
df <- df[df$PWSID != "WV3303401", ]
df <- df[df$minehuc_downstream_of_mine == 1 & df$minehuc_mine == 0, ]

cum_panel <- df |>
  distinct(PWSID, year, .data[[PROD_VAR]]) |>
  rename(prod_ann = all_of(PROD_VAR)) |>
  mutate(prod_ann = ifelse(is.na(prod_ann), 0, prod_ann)) |>
  arrange(PWSID, year) |>
  group_by(PWSID) |>
  mutate(coal_prod_upstream_cumsum = cumsum(prod_ann)) |>
  ungroup()

df <- df |> left_join(cum_panel |> select(PWSID, year, coal_prod_upstream_cumsum),
                      by = c("PWSID", "year"))
df$coal_prod_upstream_cumsum_10mst <- df$coal_prod_upstream_cumsum / 1e7

# Estimation sample = rows with a 6YR observation, robustness window 1998-2005
df_est <- df[!is.na(df$VALUE) & df$year <= 2005, ]
cat("Estimation sample (1998-2005) rows:", nrow(df_est),
    "| CWSs:", length(unique(df_est$PWSID)), "\n")

# ===========================================================================
# (A) CROSS-SECTIONAL BALANCE TEST
#     Dose (cumulative upstream production by 2005) regressed on
#     pre-determined CWS characteristics. Covariates restricted to:
#       - backcast population served (geopop_hat), pre-sample year 1997
#       - SYR2-native CWS characteristics (source type, ownership,
#         wholesaler, treatment, num_facilities, num_hucs)
# ===========================================================================
cat("\n=== (A) BALANCE TEST ===\n")

# Dose definitions, one value per CWS.
#   dose_post_10mst : production 1998-2005 -- strictly AFTER the 1997 covariates,
#                     so this is the specification that respects balance-test
#                     timing (characteristics fixed before treatment accrues).
#   dose_10mst      : production 1985-2005 -- the full window, matching the
#                     regressor in Table 6yr_huc02fe_inorg_ravalli_2005. Reported
#                     for comparison, but 66% of this dose accrues before 1997,
#                     so it is a contemporaneous association, not a balance test.
dose_cs <- cum_panel |>
  filter(PWSID %in% unique(df_est$PWSID)) |>
  group_by(PWSID) |>
  summarise(
    dose_10mst      = sum(prod_ann[year >= 1985 & year <= 2005]) / 1e7,
    dose_post_10mst = sum(prod_ann[year >= 1998 & year <= 2005]) / 1e7,
    dose_pre_10mst  = sum(prod_ann[year >= 1985 & year <= 1997]) / 1e7,
    .groups = "drop"
  ) |>
  mutate(
    any_dose      = as.integer(dose_10mst > 0),
    any_dose_post = as.integer(dose_post_10mst > 0)
  )

# Backcast population in 1997 (pre-dates the 1998-2005 outcome window)
pop97 <- geopop |>
  filter(year == 1997) |>
  select(PWSID, geopop_hat) |>
  mutate(log_pop_1997 = log(pmax(geopop_hat, 1))) |>
  select(PWSID, log_pop_1997)

# SYR2-native CWS characteristics: take the earliest observed record per CWS
syr2_chars <- df_est |>
  arrange(PWSID, year) |>
  group_by(PWSID) |>
  summarise(
    huc02             = first(huc02),
    num_facilities    = first(num_facilities),
    num_hucs          = first(num_hucs),
    pop_served_syr2   = first(POPULATION_SERVED_COUNT),
    surface_water     = as.integer(first(PRIMARY_SOURCE_CODE) %in% c("SW", "SWP")),
    owner_public      = as.integer(first(OWNER_TYPE_CODE) %in% c("L", "M", "F", "S")),
    is_wholesaler     = as.integer(first(IS_WHOLESALER_IND) == "Y"),
    source_protected  = as.integer(first(SOURCE_WATER_PROTECTION_CODE) == "Y"),
    .groups = "drop"
  ) |>
  mutate(log_pop_syr2 = log(pmax(pop_served_syr2, 1)))

bal <- dose_cs |>
  left_join(pop97,     by = "PWSID") |>
  left_join(syr2_chars, by = "PWSID")

cat("Balance sample CWSs:", nrow(bal), "\n")
cat("  with 1997 backcast population:", sum(!is.na(bal$log_pop_1997)), "\n")
cat("  zero-dose:", sum(bal$any_dose == 0), "| positive-dose:", sum(bal$any_dose == 1), "\n")

cat("  post-1998 dose: zero for", sum(bal$dose_post_10mst == 0), "CWSs\n")
cat("  share of total dose accruing pre-1998:",
    round(sum(bal$dose_pre_10mst) / sum(bal$dose_10mst), 3), "\n")

# Balance specifications. Dose is measured 1998-2005 throughout, strictly after
# the 1997/SYR2 covariates, so the timing of a balance test is respected.
# Columns 1-2 omit HUC02 fixed effects (across-basin comparison); columns 3-4
# add them, so identification is within major river basin.
RHS <- "log_pop_1997 + log_pop_syr2 + num_facilities + num_hucs + surface_water + owner_public + is_wholesaler + source_protected"

fml_bal_1 <- as.formula(paste0("dose_post_10mst ~ ", RHS))
fml_bal_2 <- as.formula(paste0("any_dose_post   ~ ", RHS))
fml_bal_3 <- as.formula(paste0("dose_post_10mst ~ ", RHS, " | huc02"))
fml_bal_4 <- as.formula(paste0("any_dose_post   ~ ", RHS, " | huc02"))

m_bal <- list(
  feols(fml_bal_1, data = bal, vcov = "hetero"),
  feols(fml_bal_2, data = bal, vcov = "hetero"),
  feols(fml_bal_3, data = bal, vcov = "hetero"),
  feols(fml_bal_4, data = bal, vcov = "hetero")
)

for (i in seq_along(m_bal)) {
  cat("  Model", i, "-- n =", m_bal[[i]]$nobs, "\n")
}

# Joint F-test that all characteristics are unrelated to dose
cat("\nJoint significance of all covariates (Wald):\n")
wald_f <- character(0)
wald_p <- character(0)
for (i in seq_along(m_bal)) {
  # Joint test of the pre-determined covariates.
  w <- tryCatch(
    wald(m_bal[[i]],
         keep = "log_pop|num_|surface_water|owner_public|is_wholesaler|source_protected",
         print = FALSE),
    error = function(e) NULL
  )
  if (!is.null(w)) {
    cat("  Model", i, ": F =", round(w$stat, 3), " p =", round(w$p, 4), "\n")
    wald_f <- c(wald_f, format(round(w$stat, 2), nsmall = 2))
    wald_p <- c(wald_p, format(round(w$p, 3), nsmall = 3))
  } else {
    wald_f <- c(wald_f, "---")
    wald_p <- c(wald_p, "---")
  }
}

dict_bal <- c(
  dose_10mst       = "Dose 1985--2005 (10M ST)",
  dose_post_10mst  = "Dose 1998--2005 (10M ST)",
  dose_pre_10mst   = "Dose 1985--1997 (10M ST)",
  any_dose         = "Any upstream mining",
  any_dose_post    = "Any mining 1998--2005",
  log_pop_1997     = "Log backcast pop. 1997",
  log_pop_syr2     = "Log pop. served (SYR2)",
  num_facilities   = "Num. intake facilities",
  num_hucs         = "Num. source HUC12s",
  surface_water    = "Surface water source",
  owner_public     = "Public ownership",
  is_wholesaler    = "Wholesaler",
  source_protected = "Source water protection",
  huc02            = "HUC02"
)

note_bal <- paste0(
  "\\textit{Notes:} Cross-sectional balance test on the 6-Year Review ",
  "estimation sample (1998--2005, Ravalli et al.~(2022) cleaning). ",
  "One observation per CWS. ",
  "The dependent variable is measured over 1998--2005. ",
  "Covariates differ in timing, and only population pre-dates the dose window. ",
  "Backcast population served in 1997 is constructed from decennial census ",
  "geography and interpolated between the 1990 and 2000 census anchors; it is ",
  "therefore dated before 1998 by construction but is not an observed 1997 ",
  "measurement. ",
  "The remaining covariates (population served, number of intake facilities, number ",
  "of source HUC12s, primary source type, ownership, wholesaler status, and source ",
  "water protection) are drawn from the SDWIS/SYR2 inventory and are recorded ",
  "contemporaneously with the dose window: each CWS contributes its first observed ",
  "record, which falls between 1998 and 2005 (41 CWSs in 1998, the remainder later). ",
  "These attributes are perfectly time-invariant within CWS over 1998--2005 --- no ",
  "system records more than one distinct value for any of them --- so the specific ",
  "year of the record does not affect the measured value. They are nonetheless not ",
  "verifiably pre-determined: a characteristic reported after mining occurred could ",
  "in principle respond to it, which is most relevant for the number of intake ",
  "facilities. No pre-1998 SDWIS attributes other than population are available. ",
  "The test therefore asks whether observable CWS characteristics predict treatment ",
  "intensity, and should be read as a comparability check rather than a strict ",
  "test of selection on pre-determined characteristics. ",
  "Columns 1 and 3 use cumulative upstream coal production (10 million short tons); ",
  "columns 2 and 4 use an indicator for any positive upstream production. ",
  "The reported $F$-statistic is a joint test of all covariates. ",
  "Of the 122 CWSs, 27 have positive upstream production over 1998--2005, so the ",
  "extensive-margin columns are identified off a small number of onsets. ",
  "Heteroskedasticity-robust standard errors. ",
  "A jointly insignificant $F$-statistic indicates that observable CWS ",
  "characteristics do not predict treatment intensity, which is consistent with ",
  "the conditional parallel trends assumption. ",
  "Sample: CWSs at most one HUC12 downstream of a coal mine. ",
  "*** p$<$0.01, ** p$<$0.05, * p$<$0.1."
)

out_bal <- file.path(OUT_REG, "pt_balance_6yr.tex")
etable(
  m_bal,
  headers = list(
    " " = list("No HUC02 FE" = 2, "HUC02 FE" = 2),
    "  " = c("Cumul. dose", "Any mining", "Cumul. dose", "Any mining")
  ),
  fitstat = ~ n + r2,
  extralines = list(
    "Joint $F$-test (all covariates)" = wald_f,
    "\\hspace{1em} $p$-value"         = wald_p
  ),
  style.tex = style.tex("aer", adjustbox = TRUE),
  tex = TRUE,
  digits = "r4",
  title = paste0("Balance test: pre-determined CWS characteristics and ",
                 "subsequent upstream coal production"),
  label = "tab:pt_balance_6yr",
  dict = dict_bal,
  notes = note_bal,
  postprocess.tex = postprocess_bal_table,
  file = out_bal, replace = TRUE
)
cat("Written:", out_bal, "\n")

# ===========================================================================
# (B) CONTINUOUS-DOSE EVENT STUDY ON VIOLATIONS
#     Restricted to CWSs whose upstream mining begins 1986-1997, so that
#     pre-treatment periods are observed in the violations panel (1985+).
# ===========================================================================
cat("\n=== (B) EVENT STUDY ON VIOLATIONS ===\n")

viol <- read_parquet(VIOL_PATH)
cat("Violations panel:", nrow(viol), "rows | year range:",
    min(viol$year, na.rm = TRUE), "-", max(viol$year, na.rm = TRUE), "\n")
stopifnot(is.character(viol$PWSID))

# Build G (first year of positive upstream production) and a time-invariant
# dose from the FULL downstream panel, not just the 6YR estimation sample.
g_tab <- cum_panel |>
  group_by(PWSID) |>
  summarise(
    G = if (any(prod_ann > 0)) min(year[prod_ann > 0]) else NA_integer_,
    .groups = "drop"
  )

# Time-invariant dose: mean annual upstream production over the 5 years
# following onset, in 10M ST. Fixed at onset, so it does not trend with t.
dose_ti <- cum_panel |>
  left_join(g_tab, by = "PWSID") |>
  filter(!is.na(G), year >= G, year <= G + 4) |>
  group_by(PWSID) |>
  summarise(dose_ti_10mst = mean(prod_ann) / 1e7, .groups = "drop")

# Treated cohort: onset 1986-1997 (pre-periods observable in violations panel)
treated <- g_tab |>
  filter(G >= 1986, G <= 1997) |>
  left_join(dose_ti, by = "PWSID")

# Never-treated: no positive upstream production at any point
never <- g_tab |> filter(is.na(G)) |> mutate(G = 0, dose_ti_10mst = 0)

es_units <- bind_rows(
  treated |> select(PWSID, G, dose_ti_10mst),
  never   |> select(PWSID, G, dose_ti_10mst)
)
cat("Event-study units -- treated (G 1986-1997):", nrow(treated),
    "| never-treated:", nrow(never), "\n")

# Downstream CWSs only, matching the 6YR sample definition
downstream_pws <- unique(df$PWSID)

es <- viol |>
  filter(PWSID %in% es_units$PWSID, PWSID %in% downstream_pws,
         year >= 1985, year <= 2005) |>
  left_join(es_units, by = "PWSID") |>
  left_join(huc02 |> select(PWSID, huc02), by = "PWSID")

# Event time; never-treated get NA and are absorbed as the comparison group
es$event_time <- ifelse(es$G == 0, NA_integer_, es$year - es$G)

# Bin endpoints to keep cells populated
es$et_bin <- es$event_time
es$et_bin[!is.na(es$et_bin) & es$et_bin <= -6] <- -6
es$et_bin[!is.na(es$et_bin) & es$et_bin >=  6] <-  6

# Never-treated units have no event time. fixest's i() drops NA rows entirely,
# which would silently discard the never-treated comparison group. Assign them
# to the reference bin instead: their dose is 0, so every interaction
# et_bin::k x dose is 0 for these units regardless of the bin they sit in, and
# they contribute to identification only through the PWSID and HUC02^year
# fixed effects -- which is exactly the role of a never-treated control.
stopifnot(all(es$dose_ti_10mst[es$G == 0] == 0))
es$et_bin[is.na(es$et_bin)] <- -1L

cat("Event-study panel rows:", nrow(es), "| CWSs:", length(unique(es$PWSID)), "\n")
cat("Event-time distribution:\n")
print(table(es$et_bin, useNA = "ifany"))

# Outcome: inorganic chemicals violations (mining-related), share of year,
# plus the arsenic and nitrate MCL sub-contaminants.
OUTCOMES <- c("inorganic_chemicals_share", "inorganic_chemicals_MCL_share",
              "arsenic_share", "nitrates_share")
OUTCOMES <- OUTCOMES[OUTCOMES %in% names(es)]
cat("Outcomes used:", paste(OUTCOMES, collapse = ", "), "\n")

# Report how thin each outcome is on this sample -- the MCL sub-contaminants are
# extremely sparse and their coefficients are identified off a handful of CWSs.
for (yv in OUTCOMES) {
  x <- es[[yv]]
  cat(sprintf("  %-32s nonzero rows = %4d (%.4f) | CWSs with any = %3d\n",
              yv, sum(x > 0, na.rm = TRUE), mean(x > 0, na.rm = TRUE),
              length(unique(es$PWSID[which(x > 0)]))))
}

# Continuous-dose event study: dose x event-time dummies, k = -1 omitted.
# i(et_bin, dose_ti_10mst, ref = -1) interacts each event-time indicator with
# the time-invariant dose. Never-treated (et_bin = NA) form the comparison.
run_es <- function(yvar) {
  fml <- as.formula(paste0(
    yvar, " ~ i(et_bin, dose_ti_10mst, ref = -1) | PWSID + huc02^year"
  ))
  tryCatch(feols(fml, data = es, cluster = ~PWSID),
           error = function(e) { cat("  ERROR:", conditionMessage(e), "\n"); NULL })
}

es_models <- list(); es_names <- character(0)
for (yv in OUTCOMES) {
  m <- run_es(yv)
  if (!is.null(m)) {
    es_models <- c(es_models, list(m)); es_names <- c(es_names, yv)
    cat("  ", yv, "-- n =", m$nobs, "\n")
    # Joint test of pre-treatment coefficients
    pre_terms <- grep("et_bin::-", names(coef(m)), value = TRUE)
    pre_terms <- setdiff(pre_terms, "et_bin::-1:dose_ti_10mst")
    if (length(pre_terms) > 0) {
      w <- tryCatch(wald(m, keep = "et_bin::-", print = FALSE), error = function(e) NULL)
      if (!is.null(w)) cat("    Pre-trend joint test: F =", round(w$stat, 3),
                           " p =", round(w$p, 4), "\n")
    }
  }
}

if (length(es_models) > 0) {
  dict_es <- c(
    inorganic_chemicals_share     = "Inorg. chem. (any)",
    inorganic_chemicals_MCL_share = "Inorg. chem. (MCL)",
    arsenic_share                 = "Arsenic (any)",
    nitrates_share                = "Nitrate (any)",
    dose_ti_10mst                 = "Dose (10M ST/yr)",
    et_bin                        = "Event time",
    PWSID                         = "CWS"
  )

  note_es <- paste0(
    "Continuous-dose event study on SDWA violations, 1985--2005. ",
    "Sample: downstream CWSs whose upstream HUC12 begins coal production between ",
    "1986 and 1997 (so that pre-treatment periods are observed), plus never-treated ",
    "downstream CWSs with no upstream production in any year. ",
    "Each event-time indicator is interacted with a time-invariant dose, defined as ",
    "mean annual upstream coal production over the five years following onset ",
    "(10 million short tons). Dose is fixed at onset and therefore does not trend ",
    "mechanically with calendar time. ",
    "Event time $k = t - G$, where $G$ is the first year of upstream production; ",
    "$k = -1$ is the omitted category and endpoints are binned at $\\pm 6$. ",
    "Fixed effects: PWSID and HUC02$\\times$year. ",
    "Standard errors clustered at PWSID level. ",
    "Coefficients on $k < -1$ are the pre-trend estimates: jointly insignificant ",
    "pre-treatment coefficients support parallel trends. ",
    "Violation outcomes are a censored transformation of concentration (a violation ",
    "is recorded only when a measured concentration crosses the MCL) and are jointly ",
    "determined with monitoring behavior; this test is therefore a necessary but not ",
    "sufficient condition for parallel trends in the concentration regressions. ",
    "Columns 1, 3 and 4 use any-violation outcomes; column 2 is restricted to MCL ",
    "violations, which are rare. Of 2,822 CWS-year observations, positive values are ",
    "recorded in 111 (42 CWSs) for any inorganic chemical violation, 9 (3 CWSs) for ",
    "inorganic chemical MCL violations, 85 (36 CWSs) for any arsenic violation, and ",
    "130 (56 CWSs) for any nitrate violation. The pre-trend test in column 2 is ",
    "correspondingly low-powered and a null there is weak evidence. ",
    "Arsenic and nitrate are sub-contaminants of the inorganic chemicals category, ",
    "so columns 3 and 4 are nested within column 1 rather than independent of it. ",
    "Over 1985--2005, 1,207 of the 1,215 CWS-years with a positive arsenic violation ",
    "share also record a positive inorganic chemicals violation share, and the two ",
    "measures take identical values in 1,204 of them; the corresponding figure for ",
    "nitrate is 1,040 of 1,732 co-occurring and 952 identical. The four columns ",
    "should therefore be read as overlapping views of the same underlying violations, ",
    "not as four independent tests."
  )

  out_es <- file.path(OUT_REG, "pt_eventstudy_violations.tex")
  etable(
    es_models,
    headers = unname(dict_es[es_names]),
    fitstat = ~ n + r2,
    style.tex = style.tex("aer", adjustbox = TRUE),
    tex = TRUE,
    title = paste0("Continuous-dose event study on SDWA violations: ",
                   "pre-trends for CWSs with upstream mining onset 1986--1997"),
    label = "tab:pt_eventstudy_violations",
    dict = dict_es,
    notes = note_es,
    postprocess.tex = move_notes_below_adjustbox,
    file = out_es, replace = TRUE
  )
  cat("Written:", out_es, "\n")

  # ---- Event-study plot for the primary outcome ----
  m_main <- es_models[[1]]
  co <- as.data.frame(confint(m_main))
  names(co) <- c("lo", "hi")
  co$term <- rownames(co)
  co$est  <- coef(m_main)[co$term]
  co <- co[grepl("et_bin::", co$term), ]
  co$k <- as.integer(sub(".*et_bin::(-?[0-9]+).*", "\\1", co$term))
  # add the omitted reference period at zero
  co <- rbind(co, data.frame(lo = 0, hi = 0, term = "ref", est = 0, k = -1))
  co <- co[order(co$k), ]

  p_es <- ggplot(co, aes(x = k, y = est)) +
    geom_hline(yintercept = 0, colour = "grey40", linewidth = 0.4) +
    geom_vline(xintercept = -0.5, linetype = "dashed", colour = "grey60", linewidth = 0.4) +
    geom_errorbar(aes(ymin = lo, ymax = hi), width = 0.12, colour = "#2c6fad") +
    geom_point(size = 2.1, colour = "#2c6fad") +
    scale_x_continuous(name = "Years since upstream mining onset (k = t - G)",
                       breaks = seq(-6, 6, 2)) +
    scale_y_continuous(name = "Effect of dose on inorganic chemical\nviolation share") +
    theme_classic(base_size = 11) +
    theme(axis.line = element_line(colour = "black"), panel.grid = element_blank())

  out_fig <- file.path(OUT_FIG, "pt_eventstudy_violations.png")
  ggsave(out_fig, p_es, width = 6.5, height = 4.2, dpi = 300)
  cat("Written:", out_fig, "\n")
} else {
  cat("No event-study models estimated.\n")
}

cat("\nDone.\n")
