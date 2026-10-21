# ============================================================
# Script: run_k2_event_study_highlow.r
# Purpose: Pre-trend check of the sulfur x post95 instrument using a binary
#          high- vs low-sulfur split on the k=2 main sample: raw annual means
#          by group, binary event studies (first stage, MR violations,
#          regulator visits, enforcement), pre-period slope and 1985-92 joint
#          test diagnostics. Sources k2_common.r; writes only new
#          `means_highlow_*` / `es_highlow_*` files.
# Inputs:
#   clean_data/cws_data/step_instruments.parquet (via k2_common.r)
#   clean_data/cws_data/cws_covariates_steps.parquet (via k2_common.r)
#   clean_data/cws_data/sdwa_vio_agg_steps.parquet (via k2_common.r)
#   clean_data/cws_data/sdwa_visit_agg_k2.parquet (via k2_common.r)
#   clean_data/cws_data/sdwa_enf_agg_k2.parquet (via k2_common.r)
#   output/reg/2sls_dwnstrm_minevio_mr_ivsum_binvio_k2.tex (N for RF gate)
# Outputs:
#   output/fig/means_highlow_{mr,visit,enf,firststage}_k2.png
#   output/fig/es_highlow_{headline,mr,visit,enf}_k2.png
#   output/fig/es_highlow_headline_k2_{nozero,tercile}.png
#   output/reg/es_highlow_pretrend_k2.tex
#   Run with --means-only to regenerate only the means_highlow_* figures.
# Author: EK  Date: 2026-10-20
# ============================================================

source("Z:/ek559/mining_wq/code/coal_mining_water_quality/k2_common.r")
library(ggplot2)
library(scales)

# --means-only: regenerate only the means_highlow_* figures (Figure A), then stop.
means_only <- "--means-only" %in% commandArgs(trailingOnly = TRUE)

# Refuse to overwrite existing outputs (CLAUDE.md file-safety rule).
out_files <- c(
  file.path("output/fig", c(paste0("means_highlow_", c("mr", "visit", "enf", "firststage"), "_k2.png"),
                            paste0("es_highlow_", c("headline", "mr", "visit", "enf"), "_k2.png"),
                            "es_highlow_headline_k2_nozero.png", "es_highlow_headline_k2_tercile.png")),
  "output/reg/es_highlow_pretrend_k2.tex")
if (!means_only && any(file.exists(file.path(ROOT, out_files))))
  stop("Output exists: ", paste(out_files[file.exists(file.path(ROOT, out_files))], collapse = ", "))

main_dat <- build_k2_panel("main")

# Stable-sample screen, verbatim from run_k2_event_study_rf.r:31-42.
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

REF_YEAR   <- 1994
PRE_YEARS  <- 1985:1993
POST_YEARS <- 1995:2005
FE_STATE   <- "PWSID + STATE_CODE^year"
FE_YEAR    <- "PWSID + year"

# ── Gate 1: sulfur is time-invariant within utility and years are 1985-2005 ──
sulfur_nd <- main_dat %>% dplyr::group_by(PWSID) %>%
  dplyr::summarise(n = dplyr::n_distinct(sulfur_mean0), .groups = "drop")
stopifnot(all(sulfur_nd$n == 1))
stopifnot(setequal(unique(main_dat$year), c(PRE_YEARS, REF_YEAR, POST_YEARS)))
cat("Sulfur time-invariance / year-range gate PASSED.\n")

# Parent table N (stable-sample gate for the main variant).
# The parent table reports N in its notes ("Number of observations: 10,641;").
parent_tex   <- paste(readLines(file.path(ROOT, "output/reg/2sls_dwnstrm_minevio_mr_ivsum_binvio_k2.tex")), collapse = " ")
parent_n_obs <- as.integer(gsub(",", "", sub(".*Number of observations: ([0-9,]+);.*", "\\1", parent_tex)))
stopifnot(length(parent_n_obs) == 1, !is.na(parent_n_obs))

# ── Step 2: high / low sulfur groups (utility level) ──────────────────────
util <- main_dat %>% dplyr::distinct(PWSID, STATE_CODE, sulfur_mean0)
stopifnot(nrow(util) == dplyr::n_distinct(util$PWSID))

HS_CUTOFF <- 1.5  # high sulfur = upstream sulfur >= 1.5%, as in didhet.r
util$hs_main <- as.integer(util$sulfur_mean0 >= HS_CUTOFF)

nz <- util$sulfur_mean0 > 0
util$hs_nozero <- NA_integer_
util$hs_nozero[nz] <- as.integer(util$sulfur_mean0[nz] >= HS_CUTOFF)

q_terc <- quantile(util$sulfur_mean0, c(1/3, 2/3))
util$hs_tercile <- NA_integer_
util$hs_tercile[util$sulfur_mean0 <= q_terc[1]] <- 0L
util$hs_tercile[util$sulfur_mean0 >  q_terc[2]] <- 1L

main_dat <- dplyr::left_join(main_dat, util[, c("PWSID", "hs_main", "hs_nozero", "hs_tercile")], by = "PWSID")

for (v in c("hs_main", "hs_nozero", "hs_tercile")) {
  cat(sprintf("\nGroup sizes, %s (utilities); mean upstream sulfur by group:\n", v))
  g <- util[!is.na(util[[v]]), ]
  print(table(group = g[[v]]))
  print(round(tapply(g$sulfur_mean0, g[[v]], mean), 2))
  cat("  By state (rows: state; cols: low = 0 / high = 1):\n")
  print(table(g$STATE_CODE, g[[v]]))
}

# ── Step 3: outcomes and display labels ───────────────────────────────────
families <- list(
  fs    = list(outcomes = "num_coal_mines_linked_sum", panel = "Upstream coal mines (first stage)"),
  mr    = list(outcomes = c("nitrates_MR_bin", "arsenic_MR_bin", "inorganic_chemicals_MR_bin"),
               panel = "Monitoring and reporting (MR) violation"),
  visit = list(outcomes = c("any_snsv", "any_insp", "any_enfvisit", "any_tech", "any_smpl"),
               panel = "Regulator visit"),
  enf   = list(outcomes = c("any_informal", "any_formal"), panel = "Enforcement action")
)
fig_lab <- c(
  num_coal_mines_linked_sum  = "Upstream coal mines",
  nitrates_MR_bin            = "Nitrates (MR violation)",
  arsenic_MR_bin             = "Arsenic (MR violation)",
  inorganic_chemicals_MR_bin = "Inorganic chemicals (MR violation)",
  any_snsv                   = "Sanitary survey visit",
  any_insp                   = "Inspection visit",
  any_enfvisit               = "Enforcement visit",
  any_tech                   = "Technical assistance visit",
  any_smpl                   = "Sample collection visit",
  any_informal               = "Informal enforcement action",
  any_formal                 = "Formal enforcement action"
)
tab_lab <- k2_dict
tab_lab["num_coal_mines_linked_sum"] <- "Upstream coal mines"
all_outcomes <- unlist(lapply(families, `[[`, "outcomes"), use.names = FALSE)
stopifnot(all(all_outcomes %in% names(main_dat)), all(all_outcomes %in% names(fig_lab)))

# ── Figure A: raw annual means by group ───────────────────────────────────
group_cols <- c("High sulfur" = "black", "Low sulfur" = "grey45")
group_lty  <- c("High sulfur" = "solid", "Low sulfur" = "dashed")

means_df <- function(oc, treat = "hs_main") {
  d <- main_dat[!is.na(main_dat[[oc]]) & !is.na(main_dat[[treat]]), ]
  m <- stats::aggregate(d[[oc]], list(year = d$year, grp = d[[treat]]), mean)
  names(m)[3] <- "mean"
  m$group <- factor(ifelse(m$grp == 1, "High sulfur", "Low sulfur"), levels = names(group_cols))
  m$outcome <- fig_lab[[oc]]
  m
}
means_plot <- function(ocs, y_lab, digits_acc = 0.1) {
  d <- do.call(rbind, lapply(ocs, means_df))
  d$outcome <- factor(d$outcome, levels = unname(fig_lab[ocs]))
  ggplot(d, aes(x = year, y = mean, colour = group, linetype = group)) +
    geom_vline(xintercept = REF_YEAR + 0.5, linetype = "dashed", colour = "grey50") +
    geom_line(linewidth = 0.6) +
    facet_wrap(~outcome, nrow = 1, scales = "free_y") +
    scale_colour_manual(values = group_cols, name = NULL) +
    scale_linetype_manual(values = group_lty, name = NULL) +
    scale_x_continuous(breaks = seq(1985, 2005, 5), limits = c(1984.5, 2005.5)) +
    scale_y_continuous(labels = label_number(accuracy = digits_acc)) +
    labs(x = "Year", y = y_lab) +
    theme_classic(base_size = 10) +
    theme(strip.background = element_blank(), strip.text = element_text(face = "bold"),
          legend.position = "bottom")
}
save_means <- function(ocs, name, y_lab, w) {
  out <- file.path(ROOT, "output/fig", paste0("means_highlow_", name, "_k2.png"))
  ggsave(out, means_plot(ocs, y_lab), width = w, height = 3.2, dpi = 300)
  cat("  Figure written:", out, "\n")
}
save_means(families$mr$outcomes,    "mr",         "Share of utilities (percent)", 9)
save_means(families$visit$outcomes, "visit",      "Share of utilities (percent)", 12)
save_means(families$enf$outcomes,   "enf",        "Share of utilities (percent)", 7)
save_means(families$fs$outcomes,    "firststage", "Average number of upstream coal mines", 5)

if (means_only) { cat("Means-only mode: Figure A written, stopping.\n"); quit(save = "no", status = 0) }

# ── Figure B: binary event-study fit ──────────────────────────────────────
# Coefficients named "year::<yyyy>:<treat>". Same clustered Wald F and
# post - pre contrast as es_fit() in run_k2_event_study_rf.r, plus a pre-period
# linear slope (1985-1994, 1994 = 0) and a 1985-1992 joint test.
es_fit_bin <- function(dat, oc, fe, treat) {
  dat_y <- dat[!is.na(dat[[oc]]) & !is.na(dat[[treat]]), ]
  fml_es <- as.formula(paste0(oc, " ~ i(year, ", treat, ", ref = ", REF_YEAR, ") + num_facilities | ", fe))
  m <- fixest::feols(fml_es, data = dat_y, cluster = ~PWSID, warn = FALSE, notes = FALSE)
  b <- coef(m); V <- vcov(m)
  es_names <- grep(paste0("^year::[0-9]{4}:", treat, "$"), names(b), value = TRUE)
  es_years <- as.integer(sub("^year::([0-9]{4}):.*$", "\\1", es_names))
  stopifnot(setequal(es_years, c(PRE_YEARS, POST_YEARS)))
  df_t <- fixest::degrees_freedom(m, "t")

  # Wald F with a rank-aware pseudo-inverse: identical to solve(Vp) when Vp is
  # full rank; drops zero-variance directions (years with no within-FE
  # variation) otherwise, with q = rank.
  joint <- function(yrs) {
    nm <- es_names[es_years %in% yrs]
    bp <- b[nm]; Vp <- V[nm, nm]
    ev <- eigen(Vp, symmetric = TRUE)
    keep <- ev$values > max(ev$values) * 1e-9
    q <- sum(keep)
    z <- as.numeric(t(ev$vectors[, keep, drop = FALSE]) %*% bp)
    f <- sum(z^2 / ev$values[keep]) / q
    list(f = f, p = pf(f, q, df_t, lower.tail = FALSE), q = q)
  }
  j_pre <- joint(PRE_YEARS)
  j_9092 <- joint(1985:1992)

  # Pre-period OLS slope of the coefficient path on year over 1985-1994 (1994 = 0).
  pre_nm <- es_names[es_years %in% PRE_YEARS]
  tt <- c(PRE_YEARS, REF_YEAR); wt <- (tt - mean(tt)) / sum((tt - mean(tt))^2)
  w_sl <- setNames(wt[match(es_years[es_years %in% PRE_YEARS], tt)], pre_nm)
  slope    <- sum(w_sl * b[pre_nm])
  slope_se <- sqrt(as.numeric(t(w_sl) %*% V[pre_nm, pre_nm] %*% w_sl))
  slope_p  <- 2 * pt(-abs(slope / slope_se), df_t)

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

  list(coefs = coefs, f_pre = j_pre$f, p_pre = j_pre$p, p_9092 = j_9092$p,
       slope = slope, slope_se = slope_se, slope_p = slope_p,
       contr = contr, contr_se = contr_se, contr_p = contr_p,
       n_obs = nobs(m), n_utils = length(fixest::fixef(m)$PWSID), outcome = oc, fe = fe)
}

specs <- rbind(
  expand.grid(variant = "main",    treat = "hs_main",    fe = c(FE_STATE, FE_YEAR), stringsAsFactors = FALSE),
  data.frame(variant = "nozero",   treat = "hs_nozero",  fe = FE_STATE, stringsAsFactors = FALSE),
  data.frame(variant = "tercile",  treat = "hs_tercile", fe = FE_STATE, stringsAsFactors = FALSE)
)
fits <- list()
for (i in seq_len(nrow(specs))) for (oc in all_outcomes) {
  key <- paste(specs$variant[i], specs$fe[i], oc, sep = "|")
  fits[[key]] <- es_fit_bin(main_dat, oc, specs$fe[i], specs$treat[i])
}
cat(sprintf("\nEstimated %d binary event-study models.\n", length(fits)))
get_fit <- function(variant, fe, oc) fits[[paste(variant, fe, oc, sep = "|")]]

# Stable-sample gate: main-variant models share the parent table's N.
main_n <- vapply(fits[grepl("^main\\|", names(fits))], `[[`, numeric(1), "n_obs")
cat("Main-variant N by model:", paste(unique(main_n), collapse = ", "), sprintf("(parent N = %d)\n", parent_n_obs))
stopifnot(all(main_n == parent_n_obs))
cat("Event-study stable-sample gate PASSED.\n")
for (v in c("nozero", "tercile")) {
  n_v <- vapply(fits[grepl(paste0("^", v, "\\|"), names(fits))], `[[`, numeric(1), "n_obs")
  cat(sprintf("Robustness '%s' N: %s\n", v, paste(unique(n_v), collapse = ", ")))
}

# ── Step 7: console report ────────────────────────────────────────────────
cat("\nPre-trend tests and post - pre contrasts (high - low sulfur):\n")
cat(sprintf("  %-8s %-6s %-27s %6s %6s %7s %17s %17s\n", "variant", "FE", "outcome",
            "preF", "p", "p85-92", "slope(SE)", "post-pre(SE)"))
treat_of <- c(main = "hs_main", nozero = "hs_nozero", tercile = "hs_tercile")
for (i in seq_len(nrow(specs))) for (oc in all_outcomes) {
  f <- get_fit(specs$variant[i], specs$fe[i], oc)
  cat(sprintf("  %-8s %-6s %-27s %6.2f %6.3f %7.3f %8.3f (%6.3f) %8.3f (%6.3f)%s\n",
              specs$variant[i], if (specs$fe[i] == FE_STATE) "st*yr" else "year", oc,
              f$f_pre, f$p_pre, f$p_9092, f$slope, f$slope_se, f$contr, f$contr_se,
              if (f$p_pre < 0.10) " <-- p<0.10" else ""))
}
cat("\nPooled binary RF (post95 x high sulfur, state x year FE) vs event-study post - pre:\n")
for (oc in all_outcomes) {
  rf <- fixest::feols(as.formula(paste0(oc, " ~ post95:hs_main + num_facilities | ", FE_STATE)),
                      data = main_dat[!is.na(main_dat[[oc]]), ], cluster = ~PWSID, warn = FALSE, notes = FALSE)
  rt <- get_term(rf, "post95:hs_main")
  f <- get_fit("main", FE_STATE, oc)
  cat(sprintf("  %-27s pooled RF %7.3f (%6.3f)   post-pre %7.3f (%6.3f)%s\n", oc, rt$est, rt$se, f$contr, f$contr_se,
              if (sign(rt$est) != sign(f$contr)) "   WARNING: sign differs" else ""))
}
fs_f <- get_fit("main", FE_STATE, "num_coal_mines_linked_sum")
cat(sprintf("\nFirst-stage post - pre (upstream mines, high - low sulfur): %.3f (%.3f)\n", fs_f$contr, fs_f$contr_se))
if (fs_f$contr >= 0) stop("First-stage post - pre is not negative: high-sulfur utilities did not lose mines after 1995. Stopping to report.")

# ── Event-study figures ───────────────────────────────────────────────────
y_lab_es <- "High \u2212 low sulfur difference (percentage points; mines for upstream coal mines)"
es_plot <- function(df, ncol, y_lab) {
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
plot_df <- function(variant, oc) {
  f <- get_fit(variant, FE_STATE, oc)
  d <- f$coefs
  d$facet <- fig_lab[[oc]]
  d$p_lab <- sprintf("Pre-1995 joint test p = %.2f", f$p_pre)
  d
}
save_es <- function(ocs, file, variant = "main", ncol = min(3, length(ocs)), w = 9) {
  df <- do.call(rbind, lapply(ocs, plot_df, variant = variant))
  df$facet <- factor(df$facet, levels = unname(fig_lab[ocs]))
  out <- file.path(ROOT, "output/fig", file)
  ggsave(out, es_plot(df, ncol, y_lab_es), width = w, height = 3.2 * ceiling(length(ocs) / ncol), dpi = 300)
  cat("  Figure written:", out, "\n")
}
headline_ocs <- c("num_coal_mines_linked_sum", "inorganic_chemicals_MR_bin", "any_snsv",
                  "any_insp", "any_informal", "any_formal")
save_es(headline_ocs, "es_highlow_headline_k2.png", ncol = 3, w = 11)
save_es(c(families$fs$outcomes, families$mr$outcomes), "es_highlow_mr_k2.png", ncol = 2, w = 8)
save_es(families$visit$outcomes, "es_highlow_visit_k2.png", ncol = 3)
save_es(families$enf$outcomes, "es_highlow_enf_k2.png", ncol = 2, w = 8)
save_es(headline_ocs, "es_highlow_headline_k2_nozero.png", variant = "nozero", ncol = 3, w = 11)
save_es(headline_ocs, "es_highlow_headline_k2_tercile.png", variant = "tercile", ncol = 3, w = 11)

# ── Summary table (state x year FE only -> no FE rows) ────────────────────
DIGITS <- 2
int_w <- function(x) if (is.na(x)) 0L else nchar(sub("\\..*$", "", sprintf(paste0("%.", DIGITS, "f"), abs(x))))
pad_num <- function(x, w) {
  s <- sprintf(paste0("%.", DIGITS, "f"), x)
  cur <- nchar(sub("\\..*$", "", s))
  if (cur < w) paste0(strrep("\\phantom{0}", w - cur), s) else s
}
# p-values: "<0.01" below 0.01, else 2 dp; right-aligned on the decimal point.
fmt_p <- function(p) if (p < 0.005) "$<$0.01" else paste0("\\phantom{$<$}", sprintf("%.2f", p))

sample_sentence <- paste0(
  "The sample is utilities with a coal mine within two flow steps upstream of their ",
  "intake and no coal mine colocated with their intake, in states with at least one ",
  "other such utility."
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

main_fits <- fits[grepl(paste0("^main\\|", FE_STATE), names(fits), fixed = FALSE) | grepl("^main\\|PWSID \\+ STATE_CODE", names(fits))]
f_w <- max(vapply(main_fits, function(f) int_w(f$f_pre), integer(1)))
s_w <- max(vapply(main_fits, function(f) max(int_w(f$slope), int_w(f$slope_se)), integer(1)))
c_w <- max(vapply(main_fits, function(f) max(int_w(f$contr), int_w(f$contr_se)), integer(1)))

tab <- c("\\begin{tabular}{p{4.2cm}rrrrrr}", "\\toprule",
         paste0(" & \\multicolumn{1}{c}{Pre-1995} & \\multicolumn{1}{c}{Pre-1995} & \\multicolumn{1}{c}{1985--1992} & ",
                "\\multicolumn{1}{c}{Pre-period} & \\multicolumn{1}{c}{Post $-$ pre} & \\\\"),
         paste0(" & \\multicolumn{1}{c}{joint F} & \\multicolumn{1}{c}{p-value} & \\multicolumn{1}{c}{p-value} & ",
                "\\multicolumn{1}{c}{slope} & \\multicolumn{1}{c}{mean coefficient} & \\multicolumn{1}{c}{Observations} \\\\"),
         "\\hline")
fam_names <- names(families)
for (i in seq_along(fam_names)) {
  fam <- fam_names[i]
  tab <- c(tab, if (i > 1) "\\hline" else NULL,
           paste0("\\multicolumn{7}{l}{\\textit{Panel ", LETTERS[i], ": ", families[[fam]]$panel, "}} \\\\"))
  for (oc in families[[fam]]$outcomes) {
    f <- get_fit("main", FE_STATE, oc)
    sl <- fmt_num_wide(f$slope, f$slope_se, f$slope_p, s_w, DIGITS)
    cf <- fmt_num_wide(f$contr, f$contr_se, f$contr_p, c_w, DIGITS)
    tab <- c(tab,
             paste0("\\quad ", tab_lab[[oc]], " & ", pad_num(f$f_pre, f_w), " & ", fmt_p(f$p_pre), " & ", fmt_p(f$p_9092),
                    " & ", sl$coef, " & ", cf$coef, " & ", format(f$n_obs, big.mark = ","), " \\\\"),
             paste0(" & & & & ", sl$se, " & ", cf$se, " & \\\\"))
  }
}
tab <- c(tab, "\\bottomrule", "\\end{tabular}")

note_body <- paste0(
  "Each regression interacts an indicator for a utility whose average coal sulfur content in watersheds within two ",
  "flow steps upstream of its intake is at least 1.5 percent, interacted with year indicators; 1994 is the omitted ",
  "year, and each regression controls for the number of intake facilities. Outcomes equal ",
  "100 if the utility had a violation, regulator visit, or enforcement action of that type ",
  "during the year and 0 otherwise, so coefficients are in percentage points, except for upstream coal mines, ",
  "which are in mines. ",
  "Coefficients are the high-sulfur minus low-sulfur difference. The pre-1995 joint F-statistic and p-value test that the ",
  "1985--1993 coefficients are jointly zero, and the 1985--1992 p-value drops 1993. The pre-period slope is the linear trend in the ",
  "1985--1994 coefficients per year, with 1994 equal to zero. The post $-$ pre mean coefficient is the average ",
  "1995--2005 coefficient minus the average 1985--1994 coefficient. ",
  "All specifications include utility and state $\\times$ year fixed effects. ", sample_sentence
)
out_tex <- file.path(ROOT, "output/reg/es_highlow_pretrend_k2.tex")
writeLines(table_shell(tab, "tab:es_highlow_pretrend_k2",
                       "Event-study pre-trends: high- versus low-sulfur utilities",
                       notes_k2(note_body)), out_tex)
cat("  Table written:", out_tex, "\n")

cat("\n=== run_k2_event_study_highlow.r DONE ===\n")
