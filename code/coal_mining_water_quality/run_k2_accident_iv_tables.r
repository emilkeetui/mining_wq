# ============================================================
# Script: run_k2_accident_iv_tables.r
# Purpose: Progressive-instrument 2SLS of MR violations, enforcement types
#          and visit types on annual upstream (and downstream) coal
#          production within two flow steps of the intake, adding
#          instruments in order: upstream Part 50 accident reports ->
#          + post95 x upstream sulfur -> + downstream production
#          instrumented by downstream accident reports -> + post95 x
#          downstream sulfur. State x year FE only. Same stable k=2
#          sample as run_k2_updn_annprod_tables.r (565 utilities /
#          10,641 obs). Writes only new `_k2accprog`-suffixed files.
# Inputs:
#   clean_data/cws_data/msha_accidents_k2.parquet
#   clean_data/cws_data/step_instruments.parquet (directly + via k2_common.r)
#   clean_data/cws_data/cws_covariates_steps.parquet (via k2_common.r)
#   clean_data/cws_data/sdwa_vio_agg_steps.parquet (via k2_common.r)
#   clean_data/cws_data/sdwa_visit_agg_k2.parquet (via k2_common.r)
#   clean_data/cws_data/sdwa_enf_agg_k2.parquet (via k2_common.r)
#   clean_data/cws_data/step_purity_flags.parquet (via k2_common.r)
# Outputs:
#   output/reg/2sls_dwnstrm_minevio_mr_ivsum_binvio_k2accprog.tex (+ _present.tex)
#   output/reg/h3_inf_formal_d12_k2accprog.tex (+ _present.tex)
#   output/reg/h2_snsv_d12_k2accprog.tex (+ _present.tex)
# Author: EK  Date: 2026-09-24
# ============================================================

source("Z:/ek559/mining_wq/code/coal_mining_water_quality/k2_common.r")

# Accident reports enter in units of ACC_UNIT reports so first-stage
# coefficients are legible at 2 decimals.
ACC_UNIT <- 10

# ── 1. Panel (verbatim from run_k2_updn_annprod_tables.r §1) ─────────────
main_dat <- build_k2_panel("main")

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

si_dn <- read_parquet(file.path(ROOT, "clean_data/cws_data/step_instruments.parquet")) %>%
  dplyr::filter(arm == "placebo", k == 2) %>%
  dplyr::select(PWSID, year,
                production_linked_sum_down = production_linked_sum,
                sulfur_down_mean0          = sulfur_mean0)
stopifnot(is.character(si_dn$PWSID),
          !any(duplicated(si_dn[, c("PWSID", "year")])))

n_util_pre <- dplyr::n_distinct(main_dat$PWSID); n_obs_pre <- nrow(main_dat)
main_dat <- main_dat %>% dplyr::left_join(si_dn, by = c("PWSID", "year"))
stopifnot(
  is.character(main_dat$PWSID),
  nrow(main_dat) == n_obs_pre,
  dplyr::n_distinct(main_dat$PWSID) == n_util_pre,
  !anyNA(main_dat$sulfur_down_mean0)
)

main_dat$coal_prod_upstream_1mst   <- replace(main_dat$production_linked_sum,
                                              is.na(main_dat$production_linked_sum), 0) / 1e6
main_dat$coal_prod_downstream_1mst <- replace(main_dat$production_linked_sum_down,
                                              is.na(main_dat$production_linked_sum_down), 0) / 1e6

main_dat$z_up <- main_dat$post95 * main_dat$sulfur_mean0
main_dat$z_dn <- main_dat$post95 * main_dat$sulfur_down_mean0

# Part 50 accident reports (all records: accidents, injuries, illnesses) at
# coal mines within two flow steps upstream / downstream of the intake.
acc <- read_parquet(file.path(ROOT, "clean_data/cws_data/msha_accidents_k2.parquet")) %>%
  dplyr::select(PWSID, year, acc_n_records_upstream_k2, acc_n_records_downstream_k2)
str(acc)
stopifnot(is.character(acc$PWSID), !any(duplicated(acc[, c("PWSID", "year")])))
acc$year <- as.integer(acc$year)
main_dat$year_join <- as.integer(main_dat$year)
main_dat <- main_dat %>%
  dplyr::left_join(acc, by = c("year_join" = "year", "PWSID")) %>%
  dplyr::select(-year_join)
stopifnot(nrow(main_dat) == n_obs_pre,
          !anyNA(main_dat$acc_n_records_upstream_k2),
          !anyNA(main_dat$acc_n_records_downstream_k2))
main_dat$acc_up <- main_dat$acc_n_records_upstream_k2 / ACC_UNIT
main_dat$acc_dn <- main_dat$acc_n_records_downstream_k2 / ACC_UNIT
for (v in c("coal_prod_upstream_1mst", "coal_prod_downstream_1mst", "acc_up", "acc_dn")) {
  cat(sprintf("%s: mean %.3f, max %.3f, share zero %.3f\n", v,
              mean(main_dat[[v]]), max(main_dat[[v]]), mean(main_dat[[v]] == 0)))
}

fe_state_yr <- "PWSID + STATE_CODE^year"
UP <- "coal_prod_upstream_1mst"
DN <- "coal_prod_downstream_1mst"
INSTR_ALL <- c("acc_up", "z_up", "acc_dn", "z_dn")

# Progressive specifications: each adds one excluded instrument; spec 3
# adds downstream production as a second endogenous regressor.
SPECS <- list(
  list(endo = UP,         instr = c("acc_up")),
  list(endo = UP,         instr = c("acc_up", "z_up")),
  list(endo = c(UP, DN),  instr = c("acc_up", "z_up", "acc_dn")),
  list(endo = c(UP, DN),  instr = c("acc_up", "z_up", "acc_dn", "z_dn"))
)

# ── 2. Sample-identity anchor (verbatim from run_k2_updn_annprod_tables.r §2)
single_iv <- function(dat, oc, fe) {
  dat_y <- dat[!is.na(dat[[oc]]), ]
  fixest::feols(as.formula(paste0(oc, " ~ num_facilities | ", fe, " | ", UP, " ~ post95:sulfur_mean0")),
                data = dat_y, cluster = ~PWSID, warn = FALSE, notes = FALSE)
}
anchor_want <- list(nitrates_MR_bin = c(19.39, 9.87), arsenic_MR_bin = c(18.58, 9.10),
                    inorganic_chemicals_MR_bin = c(15.02, 8.99))
anchor_n <- NULL
for (oc in names(anchor_want)) {
  m <- single_iv(main_dat, oc, fe_state_yr)
  t <- get_term(m, UP)
  cat(sprintf("Anchor (single instrument, state x year FE): %s %.2f (%.2f) [want %.2f (%.2f)]\n",
              oc, t$est, t$se, anchor_want[[oc]][1], anchor_want[[oc]][2]))
  stopifnot(abs(round(t$est, 2) - anchor_want[[oc]][1]) < 0.01,
            abs(round(t$se, 2)  - anchor_want[[oc]][2]) < 0.01)
  anchor_n <- rbind(anchor_n, c(n_obs = nobs(m), n_utils = length(fixest::fixef(m)$PWSID)))
}
stopifnot(all(anchor_n[, "n_obs"] == 10641), all(anchor_n[, "n_utils"] == 565))
cat("Sample-identity anchor gate PASSED (565 utilities / 10,641 obs).\n")

# ── 3. Helpers ───────────────────────────────────────────────────────────
acc_unit_lab <- if (ACC_UNIT == 1) "" else paste0(" (", ACC_UNIT, "s)")
k2_dict_acc <- c(k2_dict,
  coal_prod_upstream_1mst   = "Upstream coal prod. (1M ST)",
  coal_prod_downstream_1mst = "Downstream coal prod. (1M ST)",
  acc_up                    = paste0("Upstream accident reports", acc_unit_lab),
  acc_dn                    = paste0("Downstream accident reports", acc_unit_lab),
  z_up                      = "Post-1995 $\\times$ Upstream sulfur \\%",
  z_dn                      = "Post-1995 $\\times$ Downstream sulfur \\%"
)
k2_dict_acc <- k2_dict_acc[!duplicated(names(k2_dict_acc), fromLast = TRUE)]

# First stage of each endogenous variable on all excluded instruments of the
# spec; F is the clustered Wald F of those instruments (never fixest's ivf1,
# which is HC1), as in fs_stats_updn() of run_k2_updn_annprod_tables.r.
fs_stats_prog <- function(dat, spec, fe) {
  out <- list()
  for (en in spec$endo) {
    fs <- fixest::feols(as.formula(paste0(en, " ~ ", paste(spec$instr, collapse = " + "),
                                          " + num_facilities | ", fe)),
                        data = dat, cluster = ~PWSID, warn = FALSE, notes = FALSE)
    keep_re <- paste0("^(", paste(spec$instr, collapse = "|"), ")$")
    out[[en]] <- list(fs = fs, f = unname(fixest::wald(fs, keep = keep_re, print = FALSE)$stat))
  }
  out
}

na_term <- list(est = NA_real_, se = NA_real_, pval = NA_real_)

# Decimal-aligned cells over every term in a column; missing terms are blank.
fmt_col_multi <- function(terms_list, f_vals, digits = 2) {
  int_w <- function(x) {
    if (is.na(x)) return(0L)
    nchar(sub("\\..*$", "", sprintf(paste0("%.", digits, "f"), abs(x))))
  }
  w <- max(sapply(terms_list, function(t) max(int_w(t$est), int_w(t$se))),
           sapply(f_vals, int_w))
  cells <- lapply(terms_list, function(t) {
    if (is.na(t$est)) list(coef = "", se = "") else fmt_num_wide(t$est, t$se, t$pval, w, digits)
  })
  f_cells <- lapply(f_vals, function(x) {
    if (is.na(x)) return("")
    s <- sprintf(paste0("%.", digits, "f"), x)
    pad <- w - nchar(sub("\\..*$", "", s))
    paste0("\\phantom{(}\\phantom{-}", strrep("\\phantom{0}", max(pad, 0)), s, "$^{\\phantom{***}}$")
  })
  list(cells = cells, f_cells = f_cells)
}

# Grouped-outcome table: outcome x 4 progressive specs. Panel A = 2SLS
# coefficients on upstream / downstream production; Panel B = first-stage
# coefficients on each instrument for each endogenous variable, plus the
# clustered joint first-stage F. Layout adapted from render_panel_k2_updn().
render_panel_k2_accprog <- function(dat, outcomes, fe, dict, title, label, outfile,
                                    depvar_sentence, superheader = NULL,
                                    notes_present = NULL) {
  n_oc  <- length(outcomes)
  n_sp  <- length(SPECS)
  n_col <- n_oc * n_sp
  oc_labels <- unname(sapply(names(outcomes), function(v) if (v %in% names(dict)) dict[[v]] else v))
  col_oc <- rep(names(outcomes), each = n_sp)
  col_sp <- rep(seq_len(n_sp), times = n_oc)

  # First stages depend only on the spec (the stable-sample gate below
  # asserts every outcome column uses the same rows), but are refit on each
  # column's estimation sample to be safe.
  iv_list <- vector("list", n_col); fs_list <- vector("list", n_col)
  f_up <- rep(NA_real_, n_col); f_dn <- rep(NA_real_, n_col)
  n_utils <- integer(n_col); n_obs <- integer(n_col)
  for (j in seq_len(n_col)) {
    oc <- col_oc[j]; sp <- SPECS[[col_sp[j]]]
    dat_y <- dat[!is.na(dat[[oc]]), ]
    f_iv <- as.formula(paste0(oc, " ~ num_facilities | ", fe, " | ",
                              paste(sp$endo, collapse = " + "), " ~ ",
                              paste(sp$instr, collapse = " + ")))
    iv_list[[j]] <- fixest::feols(f_iv, data = dat_y, cluster = ~PWSID, warn = FALSE, notes = FALSE)
    fs_list[[j]] <- fs_stats_prog(dat_y, sp, fe)
    f_up[j] <- fs_list[[j]][[UP]]$f
    if (DN %in% sp$endo) f_dn[j] <- fs_list[[j]][[DN]]$f
    n_utils[j] <- length(fixest::fixef(iv_list[[j]])$PWSID)
    n_obs[j]   <- nobs(iv_list[[j]])
  }

  fs_term <- function(j, en, z) {
    if (!(en %in% SPECS[[col_sp[j]]]$endo) || !(z %in% SPECS[[col_sp[j]]]$instr)) return(na_term)
    get_term(fs_list[[j]][[en]]$fs, z)
  }
  iv_term <- function(j, en) if (en %in% SPECS[[col_sp[j]]]$endo) get_term(iv_list[[j]], en) else na_term

  # Row order of terms within each column's formatted list:
  # 1-2 2SLS (UP, DN); 3-6 first stage UP on INSTR_ALL; 7-10 first stage DN on INSTR_ALL.
  col_fmts <- lapply(seq_len(n_col), function(j) fmt_col_multi(
    c(list(iv_term(j, UP), iv_term(j, DN)),
      lapply(INSTR_ALL, function(z) fs_term(j, UP, z)),
      lapply(INSTR_ALL, function(z) fs_term(j, DN, z))),
    f_vals = c(f_up[j], f_dn[j])))
  cells_k <- function(k) lapply(col_fmts, function(cf) cf$cells[[k]])
  f_cells_k <- function(k) sapply(col_fmts, function(cf) cf$f_cells[[k]])

  # Widths sized to the widest cell ("-00.00***") and row label, so the
  # 12- and 20-column tables are shrunk by adjustbox as little as possible.
  label_w_cm <- 5.8
  data_w_cm  <- 1.7
  col_spec   <- paste0(">{\\raggedright\\arraybackslash}p{", label_w_cm, "cm}",
                       paste(rep(paste0(">{\\raggedleft\\arraybackslash}p{", data_w_cm, "cm}"), n_col), collapse = ""))
  centered_data_col <- paste0(">{\\centering\\arraybackslash}p{", data_w_cm, "cm}")

  superheader_lines <- if (!is.null(superheader)) paste0(" & \\multicolumn{", n_col, "}{c}{", superheader, "} \\\\") else NULL
  grp_header <- paste0(" & ", paste(paste0("\\multicolumn{", n_sp, "}{c}{", oc_labels, "}"), collapse = " & "), " \\\\")
  cmid <- paste(sapply(seq_len(n_oc), function(i) {
    a <- 2 + (i - 1) * n_sp; paste0("\\cmidrule(lr){", a, "-", a + n_sp - 1, "}")
  }), collapse = " ")
  colnum_row <- paste0(" & ", paste(paste0("\\multicolumn{1}{", centered_data_col, "}{(", seq_len(n_col), ")}"),
                                    collapse = " & "), " \\\\")

  title_row <- function(lab) paste0("\\multicolumn{", n_col + 1, "}{l}{", lab, "} \\\\")
  pair <- function(k, row_label) {
    cl <- cells_k(k)
    c(paste0(row_label, " & ", paste(sapply(cl, `[[`, "coef"), collapse = " & "), " \\\\"),
      paste0(" & ", paste(sapply(cl, `[[`, "se"), collapse = " & "), " \\\\"))
  }
  indent <- function(s) paste0("\\hspace{1em}", s)
  f_row  <- function(k, lab) paste0(lab, " & ", paste(f_cells_k(k), collapse = " & "), " \\\\")

  tabcolsep_pt <- 4
  natural_w_cm <- label_w_cm + n_col * data_w_cm + 2 * (n_col + 1) * tabcolsep_pt * 2.54 / 72.27
  needs_scale  <- natural_w_cm > 16.51
  total_w      <- if (needs_scale) "\\linewidth" else paste0(round(natural_w_cm, 4), "cm")
  wrap_panel <- function(lines) {
    if (!needs_scale) return(lines)
    c("\\begin{adjustbox}{max width=\\linewidth}", lines, "\\end{adjustbox}")
  }

  panel_iv <- wrap_panel(c(
    paste0("\\begin{tabular}{", col_spec, "}"),
    "\\toprule",
    superheader_lines,
    grp_header, cmid, colnum_row,
    "\\hline",
    title_row("Panel A: 2SLS"),
    pair(1, dict[[UP]]), pair(2, dict[[DN]]),
    "\\end{tabular}"
  ))
  panel_fs <- wrap_panel(c(
    paste0("\\begin{tabular}{", col_spec, "}"),
    "\\hline",
    title_row("Panel B: First stage"),
    title_row(paste0("\\textit{", dict[[UP]], "}")),
    unlist(lapply(seq_along(INSTR_ALL), function(i) pair(2 + i, indent(dict[[INSTR_ALL[i]]])))),
    f_row(1, indent("First-stage F")),
    title_row(paste0("\\textit{", dict[[DN]], "}")),
    unlist(lapply(seq_along(INSTR_ALL), function(i) pair(6 + i, indent(dict[[INSTR_ALL[i]]])))),
    f_row(2, indent("First-stage F")),
    "\\hline",
    paste0("Utilities & ", paste(format(n_utils, big.mark = ","), collapse = " & "), " \\\\"),
    paste0("Observations & ", paste(format(n_obs, big.mark = ","), collapse = " & "), " \\\\"),
    "\\bottomrule",
    "\\end{tabular}"
  ))

  f_note <- paste0(
    "The first-stage F-statistic is the Wald statistic, clustered at the utility level, for the joint ",
    "significance of all excluded instruments in that endogenous variable's first stage."
  )
  note_text <- notes_k2(depvar_sentence, f_note = f_note,
                        extra = "All specifications include utility and state-by-year fixed effects.")

  build_table_lines <- function(note_text_val) c(
    "\\begin{table}[htbp]",
    "\\raggedright",
    paste0("\\begin{minipage}{", total_w, "}"),
    paste0("\\caption{\\label{", label, "} ", title, "}"),
    "\\end{minipage}",
    "\\small",
    "{\\setlength{\\tabcolsep}{4pt}%",
    panel_iv,
    panel_fs,
    "}",
    paste0("\\begin{minipage}{", total_w, "}"),
    "\\vspace{4pt}",
    "\\footnotesize",
    "\\raggedright",
    note_text_val,
    "\\end{minipage}",
    "\\end{table}"
  )

  out_path <- file.path(ROOT, "output/reg", paste0(outfile, ".tex"))
  writeLines(build_table_lines(note_text), out_path)
  cat("  k2accprog table written to:", out_path, "\n")
  if (!is.null(notes_present)) {
    out_path_present <- file.path(ROOT, "output/reg", paste0(outfile, "_present.tex"))
    writeLines(build_table_lines(notes_present), out_path_present)
    cat("  k2accprog presentation table written to:", out_path_present, "\n")
  }

  invisible(list(f_up = f_up, f_dn = f_dn, n_utils = n_utils, n_obs = n_obs,
                 col_oc = col_oc, col_sp = col_sp, iv_list = iv_list, fs_list = fs_list))
}

# ── 4. Tables ────────────────────────────────────────────────────────────
instr_clause <- paste0(
  "Coal production is coal production during the year, in millions of short tons, in watersheds ",
  "within two flow steps upstream and, separately, downstream of the utility's intake. ",
  "Accident reports are the number of accident, injury, and illness reports filed with the Mine ",
  "Safety and Health Administration during the year",
  if (ACC_UNIT == 1) "" else paste0(", in units of ", ACC_UNIT, " reports,"),
  " by coal mines in those watersheds. Within each outcome, the four columns add excluded ",
  "instruments in order: upstream accident reports; the post-1995 indicator interacted with the ",
  "average coal sulfur content of upstream watersheds; downstream accident reports, with downstream ",
  "coal production added as a second endogenous variable; and the post-1995 indicator interacted ",
  "with the average coal sulfur content of downstream watersheds."
)
sample_clause <- paste0(
  "The sample is utilities with a coal mine within two flow steps upstream of their ",
  "intake and no coal mine colocated with their intake, in states with at least one ",
  "other such utility."
)
pp_clause <- "0 otherwise; coefficients and standard errors are multiplied by 100 to show percentage point change."
notes_present_panel <- "\\textit{Notes:} Standard errors clustered at the utility level. *** p$<$0.01, ** p$<$0.05, * p$<$0.1."

# 4.1 MR violations
r_mr <- render_panel_k2_accprog(
  dat        = main_dat,
  outcomes   = c(nitrates_MR_bin = "Nitrates", arsenic_MR_bin = "Arsenic",
                 inorganic_chemicals_MR_bin = "Inorganic chemicals"),
  fe         = fe_state_yr,
  dict       = k2_dict_acc,
  title      = "Effect of upstream and downstream coal production on inorganic chemical violations at utilities, instrumented with mine accident reports and coal sulfur",
  label      = "tab:2sls_dwnstrm_minevio_mr_ivsum_binvio_k2accprog",
  outfile    = "2sls_dwnstrm_minevio_mr_ivsum_binvio_k2accprog",
  depvar_sentence = paste("Dependent variable equals 1 if the utility had a violation of that type during the year,",
                          pp_clause, instr_clause, sample_clause),
  superheader = "Monitoring and reporting (MR) violation",
  notes_present = notes_present_panel
)

# 4.2 Enforcement types
r_enf <- render_panel_k2_accprog(
  dat        = main_dat,
  outcomes   = c(any_informal = "Informal", any_formal = "Formal", no_enf = "None"),
  fe         = fe_state_yr,
  dict       = k2_dict_acc,
  title      = "Effect of upstream and downstream coal production on enforcement actions by type, instrumented with mine accident reports and coal sulfur",
  label      = "tab:h3_inf_formal_d12_k2accprog",
  outfile    = "h3_inf_formal_d12_k2accprog",
  depvar_sentence = paste("Dependent variable equals 1 if the utility had an enforcement action of that type",
                          "during the year (\"None\" equals 1 if it had no enforcement action),",
                          pp_clause, instr_clause, sample_clause),
  superheader = "Enforcement",
  notes_present = notes_present_panel
)

# 4.3 Visit types
r_visit <- render_panel_k2_accprog(
  dat        = main_dat,
  outcomes   = c(any_snsv = "Sanitary", any_tech = "Technical assistance",
                 any_enfvisit = "Enforcement", any_smpl = "Sample collection",
                 any_insp = "Inspection"),
  fe         = fe_state_yr,
  dict       = k2_dict_acc,
  title      = "Effect of upstream and downstream coal production on regulator visit probability by visit type, instrumented with mine accident reports and coal sulfur",
  label      = "tab:h2_snsv_d12_k2accprog",
  outfile    = "h2_snsv_d12_k2accprog",
  depvar_sentence = paste("Dependent variable equals 1 if the utility received a regulator visit of that type",
                          "during the year,", pp_clause, instr_clause, sample_clause),
  superheader = "Regulator visit",
  notes_present = notes_present_panel
)

# ── 5. Gates and summary ─────────────────────────────────────────────────
for (nm in c("r_mr", "r_enf", "r_visit")) {
  r <- get(nm)
  stopifnot(length(unique(r$n_obs)) == 1, length(unique(r$n_utils)) == 1,
            r$n_obs[1] == 10641, r$n_utils[1] == 565)
  cat(sprintf("%s stable-sample gate PASSED: %s utilities / %s obs in every column.\n",
              nm, format(r$n_utils[1], big.mark = ","), format(r$n_obs[1], big.mark = ",")))
}

summ <- do.call(rbind, lapply(list(MR = r_mr, enf = r_enf, visit = r_visit), function(r) {
  do.call(rbind, lapply(seq_along(r$iv_list), function(j) {
    up <- get_term(r$iv_list[[j]], UP); dn <- get_term(r$iv_list[[j]], DN)
    fs_up <- r$fs_list[[j]][[UP]]$fs
    a_up <- get_term(fs_up, "acc_up")
    data.frame(outcome = r$col_oc[j], spec = r$col_sp[j],
               up_est = round(up$est, 2), up_se = round(up$se, 2), up_p = round(up$pval, 3),
               dn_est = round(dn$est, 2), dn_se = round(dn$se, 2), dn_p = round(dn$pval, 3),
               fs_accup = round(a_up$est, 3), f_up = round(r$f_up[j], 2), f_dn = round(r$f_dn[j], 2))
  }))
}))
options(width = 250)
cat("\n=== Progressive accident-instrument 2SLS summary (state x year FE) ===\n")
print(summ, row.names = FALSE)

cat("\n=== run_k2_accident_iv_tables.r DONE ===\n")
