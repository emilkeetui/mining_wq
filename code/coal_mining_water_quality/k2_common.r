# ============================================================
# Script: k2_common.r
# Purpose: Shared helpers for the k=2 A-full step-instrument-grid table
#          set (run_k2_main_tables.r, run_k2_placebo_tables.r,
#          run_k2_sum_tables.r, run_k2_6yr_tables.r, run_k2_figures.r):
#          panel construction, the display-label dictionary, coefficient
#          formatting helpers (ported verbatim from run_main_tables.r),
#          the clustered first-stage F helper, the grouped-outcome panel
#          table renderer, and the table-notes string builder. Read-only
#          against step_instruments.parquet / cws_covariates_steps.parquet
#          / sdwa_vio_agg_steps.parquet / sdwa_visit_agg_k2.parquet /
#          sdwa_enf_agg_k2.parquet / step_purity_flags.parquet.
# Inputs:
#   clean_data/cws_data/step_instruments.parquet
#   clean_data/cws_data/cws_covariates_steps.parquet
#   clean_data/cws_data/sdwa_vio_agg_steps.parquet
#   clean_data/cws_data/sdwa_visit_agg_k2.parquet
#   clean_data/cws_data/sdwa_enf_agg_k2.parquet
#   clean_data/cws_data/step_purity_flags.parquet
# Outputs: none (sourced by run_k2_*.r scripts)
# Sample switch: env var WQ_SAMPLE = "k2" (default; `_k2` outputs) or
#   "step23" (nearest mine 2-3 flow steps upstream; main arm k=3 rows;
#   callers write `_step23` outputs via SFX), or "step2" (nearest mine exactly
#   2 flow steps upstream; main arm k=2 rows; `_step2` outputs).
# Author: EK  Date: 2026-09-14
# ============================================================

.libPaths(c(.libPaths(), "Z:/ek559/RPackages"))
library(fixest)
library(arrow)
library(dplyr)

ROOT <- "Z:/ek559/mining_wq"

# ── 0. A2 intake-purity screen ───────────────────────────────────────────
# A utility enters only if every intake HUC is correctly classified in that
# arm's direction (downstream-only for main; mirror upstream-only for
# placebo) at the given flow-step depth k. Replaces "at least one
# qualifying intake" (n_mine_hucs_linked >= 1) as the estimation sample,
# per plan a2-intake-purity-sample-pipeline.md.
step_purity <- read_parquet(file.path(ROOT, "clean_data/cws_data/step_purity_flags.parquet"))
apply_a2 <- function(df) df %>%
  dplyr::inner_join(dplyr::filter(step_purity, a2_pure == 1) %>%
                      dplyr::select(PWSID, arm, k), by = c("PWSID", "arm", "k"))

# ── 0b. Sample switch (WQ_SAMPLE env var) ───────────────────────────────
# "k2" (default): mine within two flow steps, A2-pure at k=2 -> `_k2` outputs.
# "step23": nearest mine two or three flow steps upstream -> `_step23` outputs,
# per plan step23-sample-main-tables.md.
WQ_SAMPLE <- Sys.getenv("WQ_SAMPLE", "k2")
stopifnot(WQ_SAMPLE %in% c("k2", "step23", "step2"))
SFX <- switch(WQ_SAMPLE, step23 = "_step23", step2 = "_step2", "_k2")
# "Nearest-mine" samples: main arm, no mine within one flow step, nearest mine at
# step 2 ("step2": k=2 rows) or at step 2-3 ("step23": k=3 rows).
IS_NEAREST <- WQ_SAMPLE %in% c("step23", "step2")
NEAREST_K  <- if (WQ_SAMPLE == "step2") 2L else 3L
# main arm: max n_mine_hucs_linked at k=1 == 0, at k_max >= 1, a2_pure at k_max
nearest_step_pwsids <- function(si, k_max) {
  si_main <- si %>% dplyr::filter(arm == "main")
  no_k1  <- si_main %>% dplyr::filter(k == 1) %>% dplyr::group_by(PWSID) %>%
    dplyr::summarise(m = max(n_mine_hucs_linked), .groups = "drop") %>%
    dplyr::filter(m == 0) %>% dplyr::pull(PWSID)
  any_k  <- si_main %>% dplyr::filter(k == k_max) %>% dplyr::group_by(PWSID) %>%
    dplyr::summarise(m = max(n_mine_hucs_linked), .groups = "drop") %>%
    dplyr::filter(m >= 1) %>% dplyr::pull(PWSID)
  pure_k <- step_purity %>% dplyr::filter(arm == "main", k == k_max, a2_pure == 1) %>%
    dplyr::pull(PWSID)
  sort(Reduce(intersect, list(no_k1, any_k, pure_k)))
}
step23_pwsids <- function(si) nearest_step_pwsids(si, 3)
step2_pwsids  <- function(si) nearest_step_pwsids(si, 2)
SAMPLE_DESC_STEP23 <- "utilities with no coal mine in their intake watershed or in any watershed draining directly into it, and a coal mine in at least one watershed two or three flow steps upstream of their intake"
SAMPLE_DESC_STEP2  <- "utilities with no coal mine in their intake watershed or in any watershed draining directly into it, and a coal mine in at least one watershed exactly two flow steps upstream of their intake"
SAMPLE_DESC_NEAREST <- if (WQ_SAMPLE == "step2") SAMPLE_DESC_STEP2 else SAMPLE_DESC_STEP23
STEP_PHRASE <- if (WQ_SAMPLE == "step2") "exactly two flow steps" else "two and three flow steps"
INSTR_STEP_PHRASE <- if (WQ_SAMPLE == "step2") "two" else "three"

# ── 1. Panel construction ────────────────────────────────────────────────
# Builds the joined, zero-filled, x100-scaled k=2 A-full panel for one arm.
# Mirrors run_step_instrument_grid.r:38-64, with the visit/enforcement
# sources swapped for the k2 caches (5 visit flags + any_enf, vs. the
# 2-flag/no-any_enf `_steps` caches) and the sample restricted to k=2,
# A-full (n_mine_hucs_linked >= 1, no n_hucs_covered filter), per plan 0.1.
# `a2_only = TRUE` (default) additionally screens to the A2 intake-purity
# sample; `compare_k2_intake_purity.r` passes FALSE to keep its
# status-quo baseline column meaningful.
build_k2_panel <- function(arm_choice = c("main", "placebo"), a2_only = TRUE) {
  arm_choice <- match.arg(arm_choice)

  si     <- read_parquet(file.path(ROOT, "clean_data/cws_data/step_instruments.parquet"))
  covars <- read_parquet(file.path(ROOT, "clean_data/cws_data/cws_covariates_steps.parquet"))
  vio    <- read_parquet(file.path(ROOT, "clean_data/cws_data/sdwa_vio_agg_steps.parquet"))
  visit  <- read_parquet(file.path(ROOT, "clean_data/cws_data/sdwa_visit_agg_k2.parquet"))
  enf    <- read_parquet(file.path(ROOT, "clean_data/cws_data/sdwa_enf_agg_k2.parquet"))

  stopifnot(is.character(si$PWSID), is.character(covars$PWSID),
            is.character(vio$PWSID), is.character(visit$PWSID), is.character(enf$PWSID))

  panel <- covars %>%
    dplyr::left_join(vio,   by = c("PWSID", "year")) %>%
    dplyr::left_join(visit, by = c("PWSID", "year")) %>%
    dplyr::left_join(enf,   by = c("PWSID", "year"))

  vio_share_cols <- grep("_share_days$", names(panel), value = TRUE)
  for (v in vio_share_cols) panel[[v]][is.na(panel[[v]])] <- 0
  zero_fill_cols <- c("n_visits", "any_snsv", "any_tech", "any_enfvisit", "any_smpl",
                       "any_insp", "any_formal", "any_informal", "any_enf")
  for (v in zero_fill_cols) panel[[v]][is.na(panel[[v]])] <- 0

  # Binary outcomes coded 0/100 (percentage points), table-figure-formatting.md Rule 6.
  # Any-category `_bin` outcomes are not built by run_step_instrument_grid.r (it builds
  # only MR/MCL) -- constructed here from `<contam>_share_days` (plan Step 4.1).
  bin_src_vars <- c(
    "nitrates_share_days", "arsenic_share_days", "inorganic_chemicals_share_days",
    "nitrates_MCL_share_days", "arsenic_MCL_share_days", "inorganic_chemicals_MCL_share_days",
    "nitrates_MR_share_days", "arsenic_MR_share_days", "inorganic_chemicals_MR_share_days"
  )
  for (v in bin_src_vars) {
    bv <- sub("_share_days$", "_bin", v)
    panel[[bv]] <- as.integer(panel[[v]] > 0) * 100L
  }
  for (v in c("any_snsv", "any_tech", "any_enfvisit", "any_smpl", "any_insp",
              "any_formal", "any_informal", "any_enf")) {
    panel[[v]] <- panel[[v]] * 100
  }
  panel$no_enf  <- 100 - panel$any_enf
  panel$post95  <- as.integer(panel$year >= 1995)

  full <- si %>% dplyr::inner_join(panel, by = c("PWSID", "year"))

  # Disjointness subtraction always uses the unscreened main set, never the
  # A2-screened one, so impure utilities cannot leak into the placebo arm
  # (the A2-placebo condition already excludes them; this is belt-and-braces).
  main_k2 <- full %>% dplyr::filter(arm == "main", k == 2, n_mine_hucs_linked >= 1)
  if (IS_NEAREST && arm_choice == "main") {
    # A2 purity is inside nearest_step_pwsids(), so apply_a2() is not called here.
    ids23 <- nearest_step_pwsids(si, NEAREST_K)
    out <- full %>% dplyr::filter(arm == "main", k == NEAREST_K, PWSID %in% ids23)
    k1_main_ids <- unique(dplyr::filter(full, arm == "main", k == 1, n_mine_hucs_linked >= 1)$PWSID)
    stopifnot(length(intersect(unique(out$PWSID), k1_main_ids)) == 0,
              all(out$k == NEAREST_K), is.character(out$PWSID))
    cat(sprintf("%s main panel: %d rows, %d utilities (%d nearest-mine PWSIDs in step_instruments)\n",
                WQ_SAMPLE, nrow(out), dplyr::n_distinct(out$PWSID), length(ids23)))
    return(out)
  }
  if (arm_choice == "main") {
    out <- main_k2
  } else {
    main_ids <- unique(main_k2$PWSID)
    out <- full %>% dplyr::filter(arm == "placebo", k == 2, n_mine_hucs_linked >= 1,
                                   !(PWSID %in% main_ids))
  }
  if (a2_only) out <- apply_a2(out)
  cat(sprintf("k2 %s panel: %d rows, %d utilities\n",
              arm_choice, nrow(out), dplyr::n_distinct(out$PWSID)))
  out
}

# ── 2. Display-label dictionary (CLAUDE.md glossary -> capitalized label) ──
# "utilities", never "CWS"/"PWS" (plan Step 0.6); (MR)/(MCL) suffix stripped
# from outcome labels since the table superheader already carries it.
k2_dict <- c(
  PWSID                          = "Utility",
  num_coal_mines_linked_sum      = "Upstream coal mines (sum)",
  post95                         = "Post-1995",
  sulfur_mean0                   = "Upstream sulfur \\%",
  num_facilities                 = "Number of intake facilities",
  nitrates_bin                   = "Nitrates",
  arsenic_bin                    = "Arsenic",
  inorganic_chemicals_bin        = "Inorganic chemicals",
  nitrates_MR_bin                = "Nitrates",
  arsenic_MR_bin                 = "Arsenic",
  inorganic_chemicals_MR_bin     = "Inorganic chemicals",
  nitrates_MCL_bin               = "Nitrates",
  arsenic_MCL_bin                = "Arsenic",
  inorganic_chemicals_MCL_bin    = "Inorganic chemicals",
  any_snsv                       = "Sanitary",
  any_tech                       = "Technical assistance",
  any_enfvisit                   = "Enforcement",
  any_smpl                       = "Sample collection",
  any_insp                       = "Inspection",
  any_informal                   = "Informal",
  any_formal                     = "Formal",
  no_enf                         = "None",
  VALUE                          = "Mean conc.",
  coal_prod_upstream_cumsum_10mst = "Cumul. upstream coal prod. (10M ST)",
  coal_prod_upstream_1mst         = "Upstream coal prod. (1M ST)"
)

# ── 3. Coefficient formatting helpers (verbatim, run_main_tables.r:345-393) ──
fmt_num_wide <- function(est, se, pval, w, digits = 2, tight = FALSE) {
  if (tight) {
    # Right-aligned column: the sign, "(" and ")" are zero-width boxes hanging
    # outside the digits, so the decimal points line up down the column and no
    # gap separates "(" from the first digit of the standard error.
    stars_n <- if (is.na(pval)) 0L else if (pval < 0.01) 3L else if (pval < 0.05) 2L else if (pval < 0.1) 1L else 0L
    stars_render <- paste0(vapply(1:3, function(i) if (i <= stars_n) "*" else "\\phantom{*}", character(1)), collapse = "")
    sign_hang <- if (est < 0) "\\makebox[0pt][r]{-}" else ""
    return(list(
      coef = paste0(sign_hang, sprintf(paste0("%.", digits, "f"), abs(est)), "$^{", stars_render, "}$"),
      se   = paste0("\\makebox[0pt][r]{(}", sprintf(paste0("%.", digits, "f"), se),
                    "\\makebox[0pt][l]{)}\\phantom{$^{***}$}")
    ))
  }
  sign_coef <- if (est < 0) "-" else "\\phantom{-}"
  num       <- sprintf(paste0("%.", digits, "f"), abs(est))
  se_num    <- sprintf(paste0("%.", digits, "f"), se)
  int_w  <- function(s) nchar(sub("\\..*$", "", s))
  pad_to <- function(s) {
    cur <- int_w(s)
    if (cur < w) paste0(strrep("\\phantom{0}", w - cur), s) else s
  }
  num    <- pad_to(num)
  se_num <- pad_to(se_num)
  stars_n <- if (is.na(pval)) 0L else if (pval < 0.01) 3L else if (pval < 0.05) 2L else if (pval < 0.1) 1L else 0L
  stars_render <- paste0(vapply(1:3, function(i) if (i <= stars_n) "*" else "\\phantom{*}", character(1)), collapse = "")
  list(
    coef = paste0("\\phantom{(}", sign_coef, num, "$^{", stars_render, "}$"),
    se   = paste0("(", "\\phantom{-}", se_num, ")\\phantom{$^{***}$}")
  )
}

fmt_col <- function(ols_t, rf_t, iv_t, digits = 2, tight = FALSE) {
  int_w <- function(x) {
    if (is.na(x)) return(0L)
    nchar(sub("\\..*$", "", sprintf(paste0("%.", digits, "f"), abs(x))))
  }
  w <- max(int_w(ols_t$est), int_w(ols_t$se),
           int_w(rf_t$est),  int_w(rf_t$se),
           int_w(iv_t$est),  int_w(iv_t$se))
  list(
    ols = fmt_num_wide(ols_t$est, ols_t$se, ols_t$pval, w, digits, tight),
    rf  = fmt_num_wide(rf_t$est,  rf_t$se,  rf_t$pval,  w, digits, tight),
    iv  = fmt_num_wide(iv_t$est,  iv_t$se,  iv_t$pval,  w, digits, tight)
  )
}

fmt_single <- function(x, digits = 2) sprintf(paste0("%.", digits, "f"), x)

# ── 3b. Table formatting helpers (plan: standardize-table-figure-formatting) ──
# Fixed decimals; a value that rounds to zero never prints a minus sign.
fmt_fixed <- function(x, digits = 2) {
  out <- sprintf(paste0("%.", digits, "f"), x)
  out <- sub("^-(0\\.?0*)$", "\\1", out)
  out[is.na(x)] <- ""
  out
}

fmt_int <- function(x) {
  out <- formatC(x, format = "d", big.mark = ",")
  out[is.na(x)] <- ""
  out
}

# p-values: 2 decimals, anything below 0.005 prints as <0.01
fmt_p <- function(p) {
  ifelse(is.na(p), "", ifelse(p < 0.005, "$<$0.01", fmt_fixed(p, 2)))
}

# Significant figures (concentration cells); never scientific, no trailing "."
fmt_sig <- function(x, sig = 2) {
  out <- vapply(x, function(v) {
    if (is.na(v)) return("")
    if (v == 0) return(paste0("0.", strrep("0", sig - 1)))
    s <- formatC(signif(v, sig), digits = sig, format = "fg", flag = "#")
    sub("\\.$", "", s)
  }, character(1))
  unname(out)
}

stars_slots <- function(n_stars) {
  vapply(n_stars, function(n) {
    paste0("$^{", paste0(vapply(1:3, function(i) if (i <= n) "*" else "\\phantom{*}", character(1)), collapse = ""), "}$")
  }, character(1))
}

stars_from_p <- function(p) {
  ifelse(is.na(p), 0L, ifelse(p < 0.01, 3L, ifelse(p < 0.05, 2L, ifelse(p < 0.1, 1L, 0L))))
}

# Decimal-aligned cells for one column of formatted numbers with differing
# decimals (significant-figure columns). Integer part and fraction sit in
# fixed-width boxes; the sign and parentheses hang at zero width.
split_align_cells <- function(strings, stars = NULL, paren = FALSE) {
  strings <- as.character(strings)
  blank   <- is.na(strings) | strings == ""
  neg     <- !blank & startsWith(strings, "-")
  bare    <- sub("^-", "", strings)
  int_p   <- sub("\\..*$", "", bare)
  frac_p  <- ifelse(grepl("\\.", bare), sub("^[^.]*\\.", "", bare), NA_character_)
  int_w   <- max(c(1, nchar(int_p[!blank])))
  frac_w  <- max(c(0, ifelse(is.na(frac_p[!blank]), 0, nchar(frac_p[!blank]) + 1)))
  slot_w  <- if (isFALSE(stars)) 0 else 1.1  # em, width reserved for the three star slots
  star_tx <- if (isFALSE(stars)) rep("", length(strings))  # stars = FALSE: no star slot at all
             else if (is.null(stars)) rep("\\phantom{$^{***}$}", length(strings))
             else stars_slots(stars)
  paren   <- rep_len(paren, length(strings))  # may flag individual cells (SE rows)
  if (!isFALSE(stars)) star_tx[paren] <- "\\phantom{$^{***}$}"
  sign_tx <- ifelse(neg, "\\makebox[0pt][r]{-}", "")
  frac_tx <- ifelse(is.na(frac_p), "", paste0(".", frac_p))
  close_tx <- ifelse(paren, "\\makebox[0pt][l]{)}", "")
  open_tx  <- ifelse(paren, "\\makebox[0pt][r]{(}", "")
  cells <- paste0(open_tx,
                  "\\makebox[", 0.5 * int_w, "em][r]{", sign_tx, int_p, "}",
                  "\\makebox[", 0.5 * frac_w + slot_w, "em][l]{", frac_tx, close_tx, star_tx, "}")
  cells[blank] <- ""
  cells
}

chk_cell <- function(on, data_w) {
  ifelse(on, paste0("\\multicolumn{1}{>{\\centering\\arraybackslash}p{", data_w, "}}{$\\checkmark$}"), "")
}

# Fixed-effects rows: drop rows that are empty everywhere; if every remaining
# row is uniform across columns, drop the block and return a notes sentence.
fe_block <- function(fe_list, data_w) {
  fe_list <- fe_list[vapply(fe_list, any, logical(1))]
  if (length(fe_list) == 0) return(list(rows = NULL, note = NULL))
  uniform <- all(vapply(fe_list, function(v) length(unique(v)) == 1, logical(1)))
  if (uniform) {
    words <- tolower(gsub(" \\$\\\\times\\$ ", "-by-", names(fe_list)))
    joined <- if (length(words) == 1) words else paste0(paste(words[-length(words)], collapse = ", "),
                                                        if (length(words) > 2) "," else "", " and ", words[length(words)])
    return(list(rows = NULL, note = paste0("All specifications include ", joined, " fixed effects.")))
  }
  rows <- vapply(names(fe_list), function(nm) {
    paste0(nm, " fixed effects & ", paste(chk_cell(fe_list[[nm]], data_w), collapse = " & "), " \\\\")
  }, character(1))
  list(rows = unname(rows), note = NULL)
}

# Observations / utilities: rows only when they differ across columns.
n_block <- function(n_obs, n_utils) {
  # n_utils = NULL: the table has no separate utility count
  uni_o <- length(unique(n_obs)) == 1
  uni_u <- !is.null(n_utils) && length(unique(n_utils)) == 1
  pad   <- "\\phantom{$^{***}$}"
  rows  <- c(
    if (!is.null(n_utils) && !uni_u) paste0("Utilities & ", paste0(fmt_int(n_utils), pad, collapse = " & "), " \\\\"),
    if (!uni_o) paste0("Observations & ", paste0(fmt_int(n_obs), pad, collapse = " & "), " \\\\")
  )
  note_parts <- c(
    if (uni_o) paste0("number of observations: ", fmt_int(n_obs[1])),
    if (uni_u) paste0("number of utilities: ", fmt_int(n_utils[1]))
  )
  note <- if (length(note_parts)) {
    s <- paste(note_parts, collapse = "; ")
    paste0(toupper(substr(s, 1, 1)), substr(s, 2, nchar(s)), ".")
  } else NULL
  list(rows = rows, note = note)
}

# Float shell: centered table, caption and notes in minipages of table width.
table_shell <- function(label, title, total_w, body_lines, note_text) {
  c(
    "\\begin{table}[htbp]",
    "\\centering",
    paste0("\\begin{minipage}{", total_w, "}"),
    paste0("\\caption{\\label{", label, "} ", title, "}"),
    "\\end{minipage}",
    "\\small",
    "{\\setlength{\\tabcolsep}{4pt}%",
    body_lines,
    "}",
    if (!is.null(note_text)) c(
      paste0("\\begin{minipage}{", total_w, "}"),
      "\\vspace{4pt}",
      "\\footnotesize",
      "\\raggedright",
      note_text,
      "\\end{minipage}"
    ),
    "\\end{table}"
  )
}

# Natural width (cm) of a tabular with the given column widths, plus the
# total_w string and whether it must be scaled to fit \linewidth.
table_width <- function(col_w_cm, tabcolsep_pt = 4, textwidth_cm = 16.51) {
  pad <- 2 * length(col_w_cm) * tabcolsep_pt * 2.54 / 72.27
  nat <- sum(col_w_cm) + pad
  list(natural_cm = nat, needs_scale = nat > textwidth_cm,
       total_w = if (nat > textwidth_cm) "\\linewidth" else paste0(round(nat, 4), "cm"))
}

get_term <- function(model, term) {
  ct <- fixest::coeftable(model)
  row <- if (term %in% rownames(ct)) term else paste0("fit_", term)
  if (row %in% rownames(ct)) {
    list(est = ct[row, "Estimate"], se = ct[row, "Std. Error"], pval = ct[row, "Pr(>|t|)"])
  } else {
    list(est = NA_real_, se = NA_real_, pval = NA_real_)
  }
}

# ── 4. Clustered first stage F (never fixest's ivf1 -- HC1, wrong here) ────
# Explicit (coef/se)^2 on post95:sulfur_mean0, exactly as
# run_step_instrument_grid.r:88-99. `endog` is the instrumented regressor
# (default: upstream mine count, so existing callers are unchanged).
f_clustered <- function(dat, fe_str, endog = "num_coal_mines_linked_sum") {
  fs <- tryCatch(
    fixest::feols(as.formula(paste0(endog, " ~ post95:sulfur_mean0 + num_facilities | ", fe_str)),
                  data = dat, cluster = ~PWSID, warn = FALSE, notes = FALSE),
    error = function(e) NULL
  )
  if (is.null(fs) || !("post95:sulfur_mean0" %in% names(coef(fs)))) return(NA_real_)
  fs_coef <- coef(fs)["post95:sulfur_mean0"]
  fs_se   <- fixest::se(fs)["post95:sulfur_mean0"]
  round((fs_coef / fs_se)^2, 2)
}

# ── 5. Table-notes string builder ───────────────────────────────────────
# FE text appears in the notes only when fe_block() dropped the FE rows
# (uniform across columns); otherwise the checkmark rows carry it and the
# notes stay silent (table-notes-conventions.md Rule 7). `depvar_sentence` must avoid variable names and
# describe the outcome/instrument in plain language (Step 0.7 terminology:
# "within two flow steps upstream", never "colocated + downstream").
notes_k2 <- function(depvar_sentence, f_note = NULL, extra = NULL, sample_period = TRUE) {
  paste0(
    "\\textit{Notes:} ", depvar_sentence, " ",
    "Standard errors clustered at the utility level. ",
    if (!is.null(f_note)) paste0(f_note, " ") else "",
    if (sample_period) "Sample period 1985--2005. " else "",
    if (!is.null(extra) && nzchar(extra)) paste0(extra, " ") else "",
    "*** p$<$0.01, ** p$<$0.05, * p$<$0.1."
  )
}

# ── 5b. etable() post-processing helpers (verbatim, run_main_tables.r) ─────
move_notes_below_adjustbox <- function(x) {
  x <- paste(x, collapse = "\n")
  end_adj <- "\\end{adjustbox}"
  par_rag <- "\\par \\raggedright"
  par_pos     <- regexpr(par_rag, x, fixed = TRUE)
  end_adj_pos <- regexpr(end_adj, x, fixed = TRUE)
  if (par_pos[1] == -1 || end_adj_pos[1] == -1) return(x)
  note_block <- substr(x, par_pos[1], end_adj_pos[1] - 1)
  x <- sub(note_block, "", x, fixed = TRUE)
  x <- sub(end_adj, paste0(end_adj, "\n   {\\tiny\\linespread{1}\\selectfont ", trimws(note_block), "}"), x, fixed = TRUE)
  x
}

right_align_tabular <- function(x) {
  x <- paste(x, collapse = "\n")
  m <- regmatches(x, regexpr("\\\\begin\\{tabular\\}\\{l+c+\\}", x))
  if (length(m) == 1 && nzchar(m)) {
    x <- sub(m, gsub("c", "r", m), x, fixed = TRUE)
  }
  x
}

# ── 6. Panel table renderer ──────────────────────────────────────────────
# Generalizes run_main_tables.r's render_panel_binary_table (lines 495-714)
# to a list of (outcome, FE spec) column specs, grouped by outcome with a
# multicolumn superheader when more than one FE spec is supplied per outcome
# (collapses to the original one-column-per-outcome layout when fe_specs has
# length 1 -- h2/h3 tables, plan Step 4.6/4.7).
render_panel_k2 <- function(dat, outcomes, fe_specs, dict,
                             coalvar = "num_coal_mines_linked_sum",
                             instr_str = "post95:sulfur_mean0",
                             title, label, outfile,
                             depvar_sentence, extra_note = NULL, superheader = NULL,
                             notes_present = NULL, digits = 2, compact_layout = FALSE) {
  # compact_layout = TRUE: first-stage F-statistic as a table row (not in the
  # notes), N and number of utilities in the notes (not as table rows), and
  # decimal-aligned figures with no gap between "(" and the standard error.
  n_oc  <- length(outcomes)
  n_fe  <- length(fe_specs)
  n_col <- n_oc * n_fe

  oc_labels <- unname(sapply(names(outcomes), function(v) if (v %in% names(dict)) dict[[v]] else v))
  coal_lab  <- if (coalvar %in% names(dict)) dict[[coalvar]] else coalvar
  instr_parts <- strsplit(instr_str, ":")[[1]]
  instr_lab   <- paste(sapply(instr_parts, function(p) if (p %in% names(dict)) dict[[p]] else p), collapse = " $\\times$ ")

  col_oc <- rep(names(outcomes), each = n_fe)
  col_fe <- rep(fe_specs, times = n_oc)

  ols_list <- vector("list", n_col); rf_list <- vector("list", n_col); iv_list <- vector("list", n_col)
  f_vals   <- numeric(n_col); n_utils <- integer(n_col); n_obs <- integer(n_col)

  for (j in seq_len(n_col)) {
    oc <- col_oc[j]; fe <- col_fe[j]
    dat_y <- dat[!is.na(dat[[oc]]), ]
    f_ols <- as.formula(paste0(oc, " ~ ", coalvar, " + num_facilities | ", fe))
    f_rf  <- as.formula(paste0(oc, " ~ ", instr_str, " + num_facilities | ", fe))
    f_iv  <- as.formula(paste0(oc, " ~ num_facilities | ", fe, " | ", coalvar, " ~ ", instr_str))
    ols_list[[j]] <- fixest::feols(f_ols, data = dat_y, cluster = ~PWSID, warn = FALSE, notes = FALSE)
    rf_list[[j]]  <- fixest::feols(f_rf,  data = dat_y, cluster = ~PWSID, warn = FALSE, notes = FALSE)
    iv_list[[j]]  <- fixest::feols(f_iv,  data = dat_y, cluster = ~PWSID, warn = FALSE, notes = FALSE)
    f_vals[j]     <- f_clustered(dat_y, fe, endog = coalvar)
    n_utils[j]    <- length(fixest::fixef(iv_list[[j]])$PWSID)
    n_obs[j]      <- nobs(iv_list[[j]])
  }

  ols_terms <- lapply(seq_len(n_col), function(j) get_term(ols_list[[j]], coalvar))
  rf_terms  <- lapply(seq_len(n_col), function(j) get_term(rf_list[[j]],  instr_str))
  iv_terms  <- lapply(seq_len(n_col), function(j) get_term(iv_list[[j]],  coalvar))

  label_w_cm <- 5.5
  max_w_cm   <- 16
  data_w_cm  <- min(3, (max_w_cm - label_w_cm) / n_col)
  label_w    <- paste0(label_w_cm, "cm")
  data_w     <- paste0(data_w_cm, "cm")
  col_spec   <- paste0("p{", label_w, "}",
                        paste(rep(paste0(">{\\raggedleft\\arraybackslash}p{", data_w, "}"), n_col), collapse = ""))
  centered_data_col <- paste0(">{\\centering\\arraybackslash}p{", data_w, "}")

  superheader_lines <- if (!is.null(superheader)) {
    paste0(" & \\multicolumn{", n_col, "}{c}{", superheader, "} \\\\")
  } else NULL

  if (n_fe > 1) {
    grp_header_cells <- paste0("\\multicolumn{", n_fe, "}{c}{", oc_labels, "}")
    grp_header_row   <- paste0(" & ", paste(grp_header_cells, collapse = " & "), " \\\\")
    colnum_cells <- paste0("\\multicolumn{1}{", centered_data_col, "}{(", seq_len(n_col), ")}")
    colnum_row   <- paste0(" & ", paste(colnum_cells, collapse = " & "), " \\\\")
    header_block <- c(grp_header_row, colnum_row)
  } else {
    # narrow data columns: footnotesize header words so e.g. "Enforcement" fits
    hdr_font <- if (data_w_cm < 2.5) "\\footnotesize " else ""
    header_cells <- paste0("\\multicolumn{1}{", centered_data_col, "}{", hdr_font, oc_labels, "}")
    header_row   <- paste0(" & ", paste(header_cells, collapse = " & "), " \\\\")
    colnum_cells <- paste0("\\multicolumn{1}{", centered_data_col, "}{(", seq_len(n_col), ")}")
    colnum_row   <- paste0(" & ", paste(colnum_cells, collapse = " & "), " \\\\")
    header_block <- c(header_row, colnum_row)
  }

  title_row <- function(model_label) paste0("\\multicolumn{", n_col + 1, "}{l}{", model_label, "} \\\\")

  col_fmts  <- lapply(seq_len(n_col), function(j) fmt_col(ols_terms[[j]], rf_terms[[j]], iv_terms[[j]], digits = digits, tight = compact_layout))
  ols_cells <- lapply(col_fmts, `[[`, "ols")
  rf_cells  <- lapply(col_fmts, `[[`, "rf")
  iv_cells  <- lapply(col_fmts, `[[`, "iv")

  coef_line <- function(cells, row_label) paste0(row_label, " & ", paste(sapply(cells, `[[`, "coef"), collapse = " & "), " \\\\")
  se_line   <- function(cells) paste0(" & ", paste(sapply(cells, `[[`, "se"), collapse = " & "), " \\\\")

  fe_state     <- vapply(col_fe, function(fe) grepl("STATE_CODE^year", fe, fixed = TRUE), logical(1))
  fe_year      <- vapply(col_fe, function(fe) "year" %in% trimws(strsplit(fe, "\\+")[[1]]), logical(1))
  if (compact_layout) {
    fe_res <- fe_block(list("Utility" = rep(TRUE, n_col), "Year" = fe_year, "State $\\times$ year" = fe_state), data_w)
    fe_rows_out <- fe_res$rows
  } else {
    chk_all      <- paste(rep("$\\checkmark$", n_col), collapse = " & ")
    chk_state    <- paste(ifelse(fe_state, "$\\checkmark$", ""), collapse = " & ")
    chk_year     <- paste(ifelse(fe_year, "$\\checkmark$", ""), collapse = " & ")
    fe_rows_out  <- c(paste0("Utility fixed effects & ", chk_all, " \\\\"),
                      paste0("Year fixed effects & ", chk_year, " \\\\"),
                      paste0("State $\\times$ year fixed effects & ", chk_state, " \\\\"))
  }
  n_util_row   <- paste0("Utilities & ", paste(format(n_utils, big.mark = ","), collapse = " & "), " \\\\")
  n_obs_row    <- paste0("Observations & ", paste(format(n_obs, big.mark = ","), collapse = " & "), " \\\\")
  f_stat_row   <- paste0("First-stage F-statistic & ",
                         paste0(fmt_single(f_vals, digits), "\\phantom{$^{***}$}", collapse = " & "), " \\\\")

  tabcolsep_pt    <- 4
  cm_per_pt       <- 2.54 / 72.27
  textwidth_cm    <- 16.51
  intercol_pad_cm <- 2 * (n_col + 1) * tabcolsep_pt * cm_per_pt
  natural_w_cm    <- label_w_cm + n_col * data_w_cm + intercol_pad_cm
  needs_scale     <- natural_w_cm > textwidth_cm
  total_w         <- if (needs_scale) "\\linewidth" else paste0(round(natural_w_cm, 4), "cm")

  wrap_panel <- function(lines) {
    if (!needs_scale) return(lines)
    tab_start <- grep("^\\\\begin\\{tabular\\}", lines)[1]
    tab_end   <- max(grep("^\\\\end\\{tabular\\}", lines))
    c(lines[seq_len(tab_start - 1)],
      "\\begin{adjustbox}{max width=\\linewidth}",
      lines[tab_start:tab_end],
      "\\end{adjustbox}",
      if (tab_end < length(lines)) lines[(tab_end + 1):length(lines)] else NULL)
  }

  panel_ols <- wrap_panel(c(
    paste0("\\begin{tabular}{", col_spec, "}"),
    "\\toprule",
    superheader_lines,
    header_block,
    "\\hline",
    title_row("OLS"),
    coef_line(ols_cells, coal_lab),
    se_line(ols_cells),
    "\\end{tabular}"
  ))
  panel_iv <- wrap_panel(c(
    paste0("\\begin{tabular}{", col_spec, "}"),
    "\\hline",
    title_row("2SLS"),
    coef_line(iv_cells, coal_lab),
    se_line(iv_cells),
    "\\end{tabular}"
  ))
  panel_rf <- wrap_panel(c(
    paste0("\\begin{tabular}{", col_spec, "}"),
    "\\hline",
    title_row("RF"),
    coef_line(rf_cells, instr_lab),
    se_line(rf_cells),
    "\\hline",
    fe_rows_out,
    if (compact_layout) c(n_block(n_obs, n_utils)$rows, f_stat_row) else c(n_util_row, n_obs_row),
    "\\bottomrule",
    "\\end{tabular}"
  ))

  f_unique <- unique(round(f_vals, 2))
  f_note <- if (length(f_unique) == 1) {
    paste0("The first-stage F-statistic (clustered at the utility level) for the instrumented ",
           "variable, ", coal_lab, ", is ", fmt_single(f_unique), ".")
  } else {
    paste0("The first-stage F-statistic (clustered at the utility level) for the instrumented ",
           "variable, ", coal_lab, ", ranges from ", fmt_single(min(f_vals)),
           " to ", fmt_single(max(f_vals)), " across columns.")
  }
  if (compact_layout) {
    f_note <- NULL
    nb <- n_block(n_obs, n_utils)
    extra_note <- paste(c(extra_note, fe_res$note, nb$note), collapse = " ")
  }
  note_text <- notes_k2(depvar_sentence, f_note = f_note, extra = extra_note)

  build_table_lines <- function(note_text_val) c(
    "\\begin{table}[htbp]",
    "\\centering",
    paste0("\\begin{minipage}{", total_w, "}"),
    paste0("\\caption{\\label{", label, "} ", title, "}"),
    "\\end{minipage}",
    "\\small",
    "{\\setlength{\\tabcolsep}{4pt}%",
    panel_ols,
    panel_iv,
    panel_rf,
    "}",
    paste0("\\begin{minipage}{", total_w, "}"),
    "\\vspace{4pt}",
    "\\footnotesize",
    "\\raggedright",
    note_text_val,
    "\\end{minipage}",
    "\\end{table}"
  )

  table_lines <- build_table_lines(note_text)
  out_path <- file.path(ROOT, "output/reg", paste0(outfile, ".tex"))
  writeLines(table_lines, out_path)
  cat("  k2 panel table written to:", out_path, "\n")

  # Presentation companion: same panels, notes stripped to clustering + stars
  # only (FE checkmark rows already shown in panel_rf, so per
  # table-notes-conventions.md Rule 7 the present notes say nothing about FE
  # either -- see .claude/logs/2026-08-31-presentation-notes-tables.md).
  if (!is.null(notes_present)) {
    table_lines_present <- build_table_lines(notes_present)
    out_path_present <- file.path(ROOT, "output/reg", paste0(outfile, "_present.tex"))
    writeLines(table_lines_present, out_path_present)
    cat("  k2 panel presentation table written to:", out_path_present, "\n")
  }

  invisible(list(f_vals = f_vals, n_utils = n_utils, n_obs = n_obs,
                 iv_list = iv_list, rf_list = rf_list, ols_list = ols_list))
}

# ── 7. Generic coefficient table (single panel) ──────────────────────────────
# rows: list of list(label = "...", terms = list(<get_term() list or NULL> per column))
# fe_list: named list of logical vectors (see fe_block); spec_rows: named list of
# logical vectors shown as centered checkmark rows (differing specs);
# f_rows: named list label -> numeric vector of first-stage F-statistics.
# Coefficients are tight 2-decimal cells; N/FE rows follow the S4 rule.
render_coef_table_k2 <- function(rows, col_headers, superheader = NULL, colnums = TRUE,
                                 fe_list = NULL, spec_rows = NULL, f_rows = NULL,
                                 n_obs, n_utils, label, title, outfile,
                                 note_text_fn, notes_present = NULL,
                                 label_w_cm = 6.5, data_w_cm = 2.5, digits = 2,
                                 group_headers = NULL, stat_lines = NULL) {
  # group_headers: list of list(label, span) drawn above the column numbers
  # with a \cmidrule under each group; stat_lines: pre-formatted rows appended
  # after the F-statistic rows.
  n_col  <- length(rows[[1]]$terms)
  data_w <- paste0(data_w_cm, "cm")
  cen    <- paste0(">{\\centering\\arraybackslash}p{", data_w, "}")
  col_spec <- paste0(">{\\raggedright\\arraybackslash}p{", label_w_cm, "cm}",
                     paste(rep(paste0(">{\\raggedleft\\arraybackslash}p{", data_w, "}"), n_col), collapse = ""))
  pad <- "\\phantom{$^{***}$}"

  coef_lines <- unlist(lapply(rows, function(r) {
    cells <- lapply(r$terms, function(t) {
      if (is.null(t) || is.na(t$est)) list(coef = "", se = "")
      else fmt_num_wide(t$est, t$se, t$pval, 1, digits, tight = TRUE)
    })
    c(paste0(r$label, " & ", paste(sapply(cells, `[[`, "coef"), collapse = " & "), " \\\\"),
      paste0(" & ", paste(sapply(cells, `[[`, "se"), collapse = " & "), " \\\\"))
  }))

  fe_res <- if (!is.null(fe_list)) fe_block(fe_list, data_w) else list(rows = NULL, note = NULL)
  spec_lines <- if (!is.null(spec_rows)) vapply(names(spec_rows), function(nm)
    paste0(nm, " & ", paste(chk_cell(spec_rows[[nm]], data_w), collapse = " & "), " \\\\"), character(1)) else NULL
  nb <- n_block(n_obs, n_utils)
  f_lines <- if (!is.null(f_rows)) vapply(names(f_rows), function(nm)
    paste0(nm, " & ", paste0(fmt_fixed(f_rows[[nm]], digits), pad, collapse = " & "), " \\\\"), character(1)) else NULL

  grp_spans <- if (!is.null(group_headers)) cumsum(c(1, vapply(group_headers, function(g) g$span, numeric(1)))) else NULL
  hdr <- c(
    if (!is.null(superheader)) paste0(" & \\multicolumn{", n_col, "}{c}{", superheader, "} \\\\"),
    if (!is.null(group_headers)) c(
      # p-width spans the grouped columns (incl. inner column padding) so long labels wrap
      paste0(" & ", paste0("\\multicolumn{", vapply(group_headers, function(g) g$span, numeric(1)),
                           "}{>{\\centering\\arraybackslash}p{",
                           round(vapply(group_headers, function(g) g$span, numeric(1)) * data_w_cm +
                                   (vapply(group_headers, function(g) g$span, numeric(1)) - 1) * 2 * 4 * 2.54 / 72.27, 3),
                           "cm}}{", vapply(group_headers, function(g) g$label, character(1)), "}", collapse = " & "), " \\\\"),
      paste0("\\cmidrule(lr){", grp_spans[-length(grp_spans)] + 1, "-", grp_spans[-1], "}", collapse = "")
    ),
    if (!is.null(col_headers) && any(nzchar(col_headers)))
      paste0(" & ", paste0("\\multicolumn{1}{", cen, "}{", col_headers, "}", collapse = " & "), " \\\\"),
    if (colnums) paste0(" & ", paste0("\\multicolumn{1}{", cen, "}{(", seq_len(n_col), ")}", collapse = " & "), " \\\\")
  )
  tab_lines <- c(paste0("\\begin{tabular}{", col_spec, "}"), "\\toprule", hdr, "\\hline",
                 coef_lines,
                 if (length(c(fe_res$rows, spec_lines, nb$rows, f_lines, stat_lines))) "\\hline",
                 fe_res$rows, unname(spec_lines), nb$rows, unname(f_lines), stat_lines,
                 "\\bottomrule", "\\end{tabular}")
  tw <- table_width(c(label_w_cm, rep(data_w_cm, n_col)))
  if (tw$needs_scale) tab_lines <- c("\\begin{adjustbox}{max width=\\linewidth}", tab_lines, "\\end{adjustbox}")

  extra <- paste(c(fe_res$note, nb$note), collapse = " ")
  write_one <- function(note_text, path) {
    writeLines(table_shell(label, title, tw$total_w, tab_lines, note_text), path)
    cat("  Written:", path, "\n")
  }
  write_one(note_text_fn(extra), file.path(ROOT, "output/reg", paste0(outfile, ".tex")))
  if (!is.null(notes_present))
    write_one(notes_present, file.path(ROOT, "output/reg", paste0(outfile, "_present.tex")))
  invisible(tw)
}
