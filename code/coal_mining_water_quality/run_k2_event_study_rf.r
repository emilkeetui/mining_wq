# ============================================================
# Script: run_k2_event_study_rf.r
# Purpose: Event-study reduced form for the main-arm k=2 tables: replaces
#          post95 in the instrument with a full set of year indicators
#          interacted with upstream sulfur (1994 omitted), for the 17
#          outcomes of the allcat/MR/MCL violation, visit-type and
#          enforcement-type tables. Pre-1995 joint Wald test = parallel-
#          trends evidence. Sources k2_common.r; writes only new `es_rf_*`
#          files.
# Inputs:
#   clean_data/cws_data/step_instruments.parquet (via k2_common.r)
#   clean_data/cws_data/cws_covariates_steps.parquet (via k2_common.r)
#   clean_data/cws_data/sdwa_vio_agg_steps.parquet (via k2_common.r)
#   clean_data/cws_data/sdwa_visit_agg_k2.parquet (via k2_common.r)
#   clean_data/cws_data/sdwa_enf_agg_k2.parquet (via k2_common.r)
#   output/reg/2sls_dwnstrm_minevio_mr_ivsum_binvio_k2.tex (N for RF gate)
# Outputs:
#   output/fig/es_rf_{allcat_binvio,mr_binvio,mcl_binvio,h2_snsv,h3_enf,headline}_k2.png
#   output/reg/es_rf_pretrend_k2.tex (+ _present.tex)
#   output/reg/es_rf_pretrend_{vio,visenf}_k2_present.tex (two-slide split)
#   output/reg/es_rf_coefs_{allcat,mr,mcl,h2,h3}_k2.tex
# Author: EK  Date: 2026-09-23
# ============================================================

source("Z:/ek559/mining_wq/code/coal_mining_water_quality/k2_common.r")
library(ggplot2)
library(scales)

main_dat <- build_k2_panel("main")

# Stable-sample screen, verbatim from run_k2_main_tables.r:34-44.
lone_states <- main_dat %>%
  dplyr::filter(!is.na(STATE_CODE)) %>%
  dplyr::group_by(STATE_CODE) %>%
  dplyr::summarise(n_util = dplyr::n_distinct(PWSID), .groups = "drop") %>%
  dplyr::filter(n_util == 1) %>%
  dplyr::pull(STATE_CODE)
n_util_before <- dplyr::n_distinct(main_dat$PWSID); n_obs_before <- nrow(main_dat)
main_dat <- main_dat %>% dplyr::filter(!is.na(STATE_CODE), !(STATE_CODE %in% lone_states))
cat(sprintf("Stable-sample screen: dropped %d utilities / %d obs (lone-state: %s; missing state)\n",
            n_util_before - dplyr::n_distinct(main_dat$PWSID), n_obs_before - nrow(main_dat),
            paste(lone_states, collapse = ", ")))

REF_YEAR  <- 1994
PRE_YEARS <- 1985:1993
POST_YEARS <- 1995:2005
FE_TWO   <- c("PWSID + year", "PWSID + STATE_CODE^year")
FE_STATE <- "PWSID + STATE_CODE^year"

# ── Gate 1: sulfur is time-invariant within utility and years are 1985-2005 ──
sulfur_nd <- main_dat %>% dplyr::group_by(PWSID) %>%
  dplyr::summarise(n = dplyr::n_distinct(sulfur_mean0), .groups = "drop")
stopifnot(all(sulfur_nd$n == 1))
stopifnot(setequal(unique(main_dat$year), c(PRE_YEARS, REF_YEAR, POST_YEARS)))
cat("Sulfur time-invariance / year-range gate PASSED.\n")

# ── Gate 2: pooled RF reproduces the MR inorganic-chemicals table ─────────
parent_obs_line <- grep("^Observations &", readLines(file.path(ROOT, "output/reg/2sls_dwnstrm_minevio_mr_ivsum_binvio_k2.tex")), value = TRUE)
parent_n_obs    <- unique(as.integer(gsub("[^0-9]", "", trimws(strsplit(sub("^Observations &", "", sub("\\\\\\\\.*$", "", parent_obs_line)), "&")[[1]]))))
stopifnot(length(parent_n_obs) == 1)
rf_pool <- fixest::feols(inorganic_chemicals_MR_bin ~ post95:sulfur_mean0 + num_facilities | PWSID + STATE_CODE^year,
                         data = main_dat[!is.na(main_dat$inorganic_chemicals_MR_bin), ],
                         cluster = ~PWSID, warn = FALSE, notes = FALSE)
rf_pool_t <- get_term(rf_pool, "post95:sulfur_mean0")
cat(sprintf("Pooled RF (MR inorganic, state x year): %.2f (%.2f), N = %d [want -1.51 (0.79), N = %d]\n",
            rf_pool_t$est, rf_pool_t$se, nobs(rf_pool), parent_n_obs))
stopifnot(abs(round(rf_pool_t$est, 2) - (-1.51)) < 0.01, abs(round(rf_pool_t$se, 2) - 0.79) < 0.01,
          nobs(rf_pool) == parent_n_obs)
cat("Pooled RF reproduction gate PASSED.\n")

# ── Event-study fit ───────────────────────────────────────────────────────
# Coefficients named "year::<yyyy>:sulfur_mean0". Pre-trend test is the
# clustered Wald F on the nine 1985-1993 coefficients (same statistic as
# fixest::wald, computed explicitly so the term set is checked). The
# post - pre contrast averages 1985-1994 with the 1994 reference at zero,
# so it is the event-study analogue of the pooled post95 x sulfur term.
es_fit <- function(dat, oc, fe) {
  dat_y <- dat[!is.na(dat[[oc]]), ]
  fml_es <- as.formula(paste0(oc, " ~ i(year, sulfur_mean0, ref = ", REF_YEAR, ") + num_facilities | ", fe))
  m <- fixest::feols(fml_es, data = dat_y, cluster = ~PWSID, warn = FALSE, notes = FALSE)
  b <- coef(m); V <- vcov(m)
  es_names <- grep("^year::[0-9]{4}:sulfur_mean0$", names(b), value = TRUE)
  es_years <- as.integer(sub("^year::([0-9]{4}):.*$", "\\1", es_names))
  stopifnot(setequal(es_years, c(PRE_YEARS, POST_YEARS)))
  df_t <- fixest::degrees_freedom(m, "t")

  pre_nm <- es_names[es_years %in% PRE_YEARS]
  bp <- b[pre_nm]; Vp <- V[pre_nm, pre_nm]
  q  <- length(pre_nm)
  f_pre <- as.numeric(t(bp) %*% solve(Vp) %*% bp) / q
  p_pre <- pf(f_pre, q, df_t, lower.tail = FALSE)

  w <- setNames(numeric(length(es_names)), es_names)
  w[es_years %in% POST_YEARS] <- 1 / length(POST_YEARS)
  w[es_years %in% PRE_YEARS]  <- -1 / (length(PRE_YEARS) + 1)   # + 1: 1994 reference = 0
  contr    <- sum(w * b[es_names])
  contr_se <- sqrt(as.numeric(t(w) %*% V[es_names, es_names] %*% w))
  contr_p  <- 2 * pt(-abs(contr / contr_se), df_t)

  se <- sqrt(diag(V))[es_names]
  pv <- 2 * pt(-abs(b[es_names] / se), df_t)
  coefs <- rbind(
    data.frame(year = es_years, est = unname(b[es_names]), se = unname(se), pval = unname(pv)),
    data.frame(year = REF_YEAR, est = 0, se = NA_real_, pval = NA_real_)
  )
  coefs <- coefs[order(coefs$year), ]
  coefs$lo <- coefs$est - 1.96 * coefs$se
  coefs$hi <- coefs$est + 1.96 * coefs$se

  list(coefs = coefs, f_pre = f_pre, p_pre = p_pre, df_pre = c(q, df_t),
       contr = contr, contr_se = contr_se, contr_p = contr_p,
       n_obs = nobs(m), n_utils = length(fixest::fixef(m)$PWSID), outcome = oc, fe = fe)
}

families <- list(
  allcat = list(outcomes = c("nitrates_bin", "arsenic_bin", "inorganic_chemicals_bin"),
                fe = FE_TWO, fig = "es_rf_allcat_binvio_k2", panel = "Any violation",
                superheader = "Any violation"),
  mr     = list(outcomes = c("nitrates_MR_bin", "arsenic_MR_bin", "inorganic_chemicals_MR_bin"),
                fe = FE_TWO, fig = "es_rf_mr_binvio_k2", panel = "Monitoring and reporting (MR) violation",
                superheader = "Monitoring and reporting (MR) violation"),
  mcl    = list(outcomes = c("nitrates_MCL_bin", "arsenic_MCL_bin", "inorganic_chemicals_MCL_bin"),
                fe = FE_TWO, fig = "es_rf_mcl_binvio_k2", panel = "Maximum contaminant level (MCL) violation",
                superheader = "Maximum contaminant level (MCL) violation"),
  h2     = list(outcomes = c("any_snsv", "any_tech", "any_enfvisit", "any_smpl", "any_insp"),
                fe = FE_STATE, fig = "es_rf_h2_snsv_k2", panel = "Regulator visit",
                superheader = "Regulator visit"),
  h3     = list(outcomes = c("any_informal", "any_formal", "no_enf"),
                fe = FE_TWO, fig = "es_rf_h3_enf_k2", panel = "Enforcement action",
                superheader = "Enforcement")
)

fits <- list()
for (fam in names(families)) {
  for (oc in families[[fam]]$outcomes) {
    for (fe in families[[fam]]$fe) {
      key <- paste(fam, oc, fe, sep = "|")
      fits[[key]] <- es_fit(main_dat, oc, fe)
    }
  }
}
cat(sprintf("Estimated %d event-study models.\n", length(fits)))
get_fit <- function(fam, oc, fe) fits[[paste(fam, oc, fe, sep = "|")]]

# Stable-sample gate: every model shares the parent table's N.
all_n <- vapply(fits, `[[`, numeric(1), "n_obs")
stopifnot(all(all_n == parent_n_obs))
cat(sprintf("Event-study stable-sample gate PASSED: N = %s in all models.\n", format(parent_n_obs, big.mark = ",")))

# ── Console report: pre-trend tests (state x year FE) ─────────────────────
cat("\nPre-trend joint tests and post - pre contrasts (utility + state x year FE):\n")
for (fam in names(families)) for (oc in families[[fam]]$outcomes) {
  f <- get_fit(fam, oc, FE_STATE)
  cat(sprintf("  %-6s %-28s F = %5.2f  p = %.3f%s   post-pre = %6.2f (%.2f)\n",
              fam, oc, f$f_pre, f$p_pre, if (f$p_pre < 0.10) " <-- p<0.10" else "          ",
              f$contr, f$contr_se))
}
f_mr <- get_fit("mr", "inorganic_chemicals_MR_bin", FE_STATE)
cat(sprintf("\nSanity: MR inorganic post-pre %.2f (%.2f) vs pooled RF %.2f (%.2f)\n",
            f_mr$contr, f_mr$contr_se, rf_pool_t$est, rf_pool_t$se))
if (sign(f_mr$contr) != sign(rf_pool_t$est)) cat("  WARNING: post-pre contrast sign differs from pooled RF.\n")

# ── Figures ───────────────────────────────────────────────────────────────
y_lab <- "Effect of 1 pp upstream sulfur (percentage points)"
# Pre-trend p-value goes in the facet strip (second line) so it never
# collides with the 1994/95 marker or the confidence intervals.
es_plot <- function(df, ncol) {
  lv <- levels(df$facet)
  p_by <- df %>% dplyr::distinct(facet, p_lab)
  new_lv <- paste0(lv, "\n", p_by$p_lab[match(lv, p_by$facet)])
  df$facet <- factor(new_lv[match(as.character(df$facet), lv)], levels = new_lv)
  ggplot(df, aes(x = year, y = est)) +
    geom_hline(yintercept = 0, linetype = "dashed", colour = "grey50") +
    geom_vline(xintercept = REF_YEAR + 0.5, linetype = "dashed", colour = "grey50") +
    geom_errorbar(aes(ymin = lo, ymax = hi), width = 0.3, colour = "grey30", na.rm = TRUE) +
    geom_point(size = 1.6) +
    facet_wrap(~facet, ncol = ncol, scales = "free_y") +
    scale_x_continuous(breaks = seq(1985, 2005, 5), limits = c(1984.5, 2005.5)) +
    scale_y_continuous(labels = label_number(accuracy = 0.1)) +
    labs(x = "Year", y = y_lab) +
    theme_classic(base_size = 10) +
    theme(strip.background = element_blank(), strip.text = element_text(face = "bold"))
}
plot_df <- function(fam, oc, facet_label) {
  f <- get_fit(fam, oc, FE_STATE)
  d <- f$coefs
  d$facet <- facet_label
  d$p_lab <- sprintf("Pre-1995 joint test p = %.2f", f$p_pre)
  d
}

for (fam in names(families)) {
  ocs <- families[[fam]]$outcomes
  labs_oc <- unname(k2_dict[ocs])
  df <- do.call(rbind, lapply(seq_along(ocs), function(i) plot_df(fam, ocs[i], labs_oc[i])))
  df$facet <- factor(df$facet, levels = labs_oc)
  n_f <- length(ocs)
  ncol <- min(3, n_f)
  p <- es_plot(df, ncol)
  out_png <- file.path(ROOT, "output/fig", paste0(families[[fam]]$fig, ".png"))
  ggsave(out_png, p, width = 9, height = 3.2 * ceiling(n_f / ncol), dpi = 300)
  cat("  Figure written:", out_png, "\n")
}

headline_spec <- list(
  c("mr",  "inorganic_chemicals_MR_bin",  "Inorganic chemicals (MR violation)"),
  c("mcl", "inorganic_chemicals_MCL_bin", "Inorganic chemicals (MCL violation)"),
  c("h2",  "any_snsv",                    "Sanitary survey visit"),
  c("h3",  "any_formal",                  "Formal enforcement action")
)
df_head <- do.call(rbind, lapply(headline_spec, function(s) plot_df(s[1], s[2], s[3])))
df_head$facet <- factor(df_head$facet, levels = vapply(headline_spec, `[`, character(1), 3))
p_head <- es_plot(df_head, 2)
out_head <- file.path(ROOT, "output/fig/es_rf_headline_k2.png")
ggsave(out_head, p_head, width = 8, height = 6, dpi = 300)
cat("  Figure written:", out_head, "\n")

# ── Table helpers ─────────────────────────────────────────────────────────
DIGITS <- 2
int_w <- function(x) if (is.na(x)) 0L else nchar(sub("\\..*$", "", sprintf(paste0("%.", DIGITS, "f"), abs(x))))
pad_num <- function(x, w) {
  s <- sprintf(paste0("%.", DIGITS, "f"), x)
  cur <- nchar(sub("\\..*$", "", s))
  if (cur < w) paste0(strrep("\\phantom{0}", w - cur), s) else s
}
star_legend <- "*** p$<$0.01, ** p$<$0.05, * p$<$0.1."
sample_sentence <- paste0(
  "The sample is utilities with a coal mine within two flow steps upstream of their ",
  "intake and no coal mine colocated with their intake, in states with at least one ",
  "other such utility."
)
es_sentence <- paste0(
  "Each regression interacts the average coal sulfur content of watersheds within two ",
  "flow steps upstream of the utility's intake with year indicators; 1994 is the omitted ",
  "year, and each regression controls for the number of intake facilities. Outcomes equal ",
  "100 if the utility had a violation, regulator visit, or enforcement action of that type ",
  "during the year (for \"None,\" no enforcement action) and 0 otherwise, so coefficients are ",
  "in percentage points per percentage point of upstream sulfur."
)

table_shell <- function(tabular, label, title, note) c(
  "\\begin{table}[htbp]",
  "\\raggedright",
  "\\begin{minipage}{\\linewidth}",
  paste0("\\caption{\\label{", label, "} ", title, "}"),
  "\\end{minipage}",
  "\\small",
  "{\\setlength{\\tabcolsep}{4pt}%",
  "\\begin{adjustbox}{max width=\\linewidth}",
  tabular,
  "\\end{adjustbox}",
  "}",
  "\\begin{minipage}{\\linewidth}",
  "\\vspace{4pt}",
  "\\footnotesize",
  "\\raggedright",
  note,
  "\\end{minipage}",
  "\\end{table}"
)

# ── Main-text summary table (state x year FE only -> no FE rows) ──────────
summ_rows <- list()
f_w <- max(vapply(fits[grepl(FE_STATE, names(fits), fixed = TRUE)], function(f) int_w(f$f_pre), integer(1)))
c_w <- max(vapply(fits[grepl(FE_STATE, names(fits), fixed = TRUE)],
                  function(f) max(int_w(f$contr), int_w(f$contr_se)), integer(1)))
# Panels are lettered from A within each table, so a subset table (slides)
# starts at Panel A. Column widths (f_w, c_w) are shared across all subsets.
build_summ_tab <- function(fams) {
  tab <- c("\\begin{tabular}{p{5cm}rrrr}", "\\toprule",
           paste0(" & \\multicolumn{1}{c}{Pre-1995} & \\multicolumn{1}{c}{Pre-1995} & ",
                  "\\multicolumn{1}{c}{Post $-$ pre} & \\\\"),
           paste0(" & \\multicolumn{1}{c}{joint F} & \\multicolumn{1}{c}{p-value} & ",
                  "\\multicolumn{1}{c}{mean coefficient} & \\multicolumn{1}{c}{Observations} \\\\"),
           "\\hline")
  for (i in seq_along(fams)) {
    fam <- fams[i]
    tab <- c(tab,
             if (i > 1) "\\hline" else NULL,
             paste0("\\multicolumn{5}{l}{\\textit{Panel ", LETTERS[i], ": ", families[[fam]]$panel, "}} \\\\"))
    for (oc in families[[fam]]$outcomes) {
      f <- get_fit(fam, oc, FE_STATE)
      cf <- fmt_num_wide(f$contr, f$contr_se, f$contr_p, c_w, DIGITS)
      tab <- c(tab,
               paste0("\\quad ", k2_dict[[oc]], " & ", pad_num(f$f_pre, f_w), " & ", pad_num(f$p_pre, 1),
                      " & ", cf$coef, " & ", format(f$n_obs, big.mark = ","), " \\\\"),
               paste0(" & & & ", cf$se, " & \\\\"))
    }
  }
  c(tab, "\\bottomrule", "\\end{tabular}")
}
tab_s <- build_summ_tab(names(families))

summ_note_body <- paste0(
  es_sentence, " The pre-1995 joint F-statistic and p-value test that the 1985--1993 ",
  "coefficients are jointly zero. The post $-$ pre mean coefficient is the average ",
  "1995--2005 coefficient minus the average 1985--1994 coefficient (with 1994 equal to zero). ",
  "All specifications include utility and state $\\times$ year fixed effects. ", sample_sentence
)
summ_title <- "Event-study reduced form: pre-1995 trends in outcomes by upstream sulfur content"
writeLines(table_shell(tab_s, "tab:es_rf_pretrend_k2", summ_title, notes_k2(summ_note_body)),
           file.path(ROOT, "output/reg/es_rf_pretrend_k2.tex"))
cat("  Table written: output/reg/es_rf_pretrend_k2.tex\n")
summ_note_present <- paste0(
  "\\textit{Notes:} All specifications include utility and state $\\times$ year fixed effects. ",
  "Standard errors clustered at the utility level. ", star_legend
)
writeLines(table_shell(tab_s, "tab:es_rf_pretrend_k2", summ_title, summ_note_present),
           file.path(ROOT, "output/reg/es_rf_pretrend_k2_present.tex"))
cat("  Table written: output/reg/es_rf_pretrend_k2_present.tex\n")

# Two-slide split of the summary table: violations | visits + enforcement.
slide_split <- list(
  vio    = list(fams = c("allcat", "mr", "mcl"),
                title = "Event-study reduced form: pre-1995 trends in violations by upstream sulfur content"),
  visenf = list(fams = c("h2", "h3"),
                title = "Event-study reduced form: pre-1995 trends in regulator visits and enforcement by upstream sulfur content")
)
stopifnot(setequal(unlist(lapply(slide_split, `[[`, "fams")), names(families)))
for (part in names(slide_split)) {
  sp <- slide_split[[part]]
  out <- paste0("output/reg/es_rf_pretrend_", part, "_k2_present.tex")
  writeLines(table_shell(build_summ_tab(sp$fams), paste0("tab:es_rf_pretrend_", part, "_k2"),
                         sp$title, summ_note_present),
             file.path(ROOT, out))
  cat("  Table written:", out, "\n")
}

# ── Appendix coefficient tables (years x outcome/FE columns) ──────────────
for (fam in names(families)) {
  spec <- families[[fam]]
  ocs <- spec$outcomes; fes <- spec$fe
  n_fe <- length(fes); n_col <- length(ocs) * n_fe
  col_oc <- rep(ocs, each = n_fe); col_fe <- rep(fes, times = length(ocs))
  col_fits <- lapply(seq_len(n_col), function(j) get_fit(fam, col_oc[j], col_fe[j]))
  col_w <- vapply(col_fits, function(f) max(vapply(seq_len(nrow(f$coefs)), function(r)
    max(int_w(f$coefs$est[r]), int_w(f$coefs$se[r])), integer(1))), integer(1))

  oc_labels <- unname(k2_dict[ocs])
  hdr <- if (n_fe > 1) {
    paste0(" & ", paste0("\\multicolumn{", n_fe, "}{c}{", oc_labels, "}", collapse = " & "), " \\\\")
  } else {
    paste0(" & ", paste0("\\multicolumn{1}{c}{", oc_labels, "}", collapse = " & "), " \\\\")
  }
  tab <- c(paste0("\\begin{tabular}{l", strrep("r", n_col), "}"), "\\toprule",
           paste0(" & \\multicolumn{", n_col, "}{c}{", spec$superheader, "} \\\\"),
           hdr,
           paste0(" & ", paste0("\\multicolumn{1}{c}{(", seq_len(n_col), ")}", collapse = " & "), " \\\\"),
           "\\hline")
  for (yr in c(PRE_YEARS, REF_YEAR, POST_YEARS)) {
    if (yr == REF_YEAR) {
      tab <- c(tab, paste0(yr, " $\\times$ Upstream sulfur \\% & ",
                           paste(rep("\\multicolumn{1}{c}{---}", n_col), collapse = " & "), " \\\\"))
      next
    }
    cells <- lapply(seq_len(n_col), function(j) {
      r <- col_fits[[j]]$coefs[col_fits[[j]]$coefs$year == yr, ]
      fmt_num_wide(r$est, r$se, r$pval, col_w[j], DIGITS)
    })
    tab <- c(tab,
             paste0(yr, " $\\times$ Upstream sulfur \\% & ", paste(sapply(cells, `[[`, "coef"), collapse = " & "), " \\\\"),
             paste0(" & ", paste(sapply(cells, `[[`, "se"), collapse = " & "), " \\\\"))
  }
  fw <- max(vapply(col_fits, function(f) int_w(f$f_pre), integer(1)))
  tab <- c(tab, "\\hline",
           paste0("Pre-1995 joint F & ", paste(vapply(col_fits, function(f) pad_num(f$f_pre, fw), ""), collapse = " & "), " \\\\"),
           paste0("Pre-1995 joint p-value & ", paste(vapply(col_fits, function(f) pad_num(f$p_pre, 1), ""), collapse = " & "), " \\\\"))
  if (n_fe > 1) {
    fe_state <- grepl("STATE_CODE^year", col_fe, fixed = TRUE)
    tab <- c(tab,
             paste0("Utility fixed effects & ", paste(rep("$\\checkmark$", n_col), collapse = " & "), " \\\\"),
             paste0("Year fixed effects & ", paste(ifelse(!fe_state, "$\\checkmark$", ""), collapse = " & "), " \\\\"),
             paste0("State $\\times$ year fixed effects & ", paste(ifelse(fe_state, "$\\checkmark$", ""), collapse = " & "), " \\\\"))
  }
  tab <- c(tab,
           paste0("Utilities & ", paste(vapply(col_fits, function(f) format(f$n_utils, big.mark = ","), ""), collapse = " & "), " \\\\"),
           paste0("Observations & ", paste(vapply(col_fits, function(f) format(f$n_obs, big.mark = ","), ""), collapse = " & "), " \\\\"),
           "\\bottomrule", "\\end{tabular}")

  body <- paste0(es_sentence, " The pre-1995 joint F-statistic and p-value test that the ",
                 "1985--1993 coefficients are jointly zero. ",
                 if (n_fe == 1) "All specifications include utility and state $\\times$ year fixed effects. " else "",
                 sample_sentence)
  out_tex <- file.path(ROOT, "output/reg", paste0("es_rf_coefs_", fam, "_k2.tex"))
  writeLines(table_shell(tab, paste0("tab:es_rf_coefs_", fam, "_k2"),
                         paste0("Event-study reduced form by year: ",
                                tolower(substr(spec$panel, 1, 1)), substring(spec$panel, 2), " outcomes"),
                         notes_k2(body)),
             out_tex)
  cat("  Table written:", out_tex, "\n")
}

cat("\n=== run_k2_event_study_rf.r DONE ===\n")
