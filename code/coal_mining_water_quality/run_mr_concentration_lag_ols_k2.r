# ============================================================
# Script: run_mr_concentration_lag_ols_k2.r
# Purpose: Reproduce the mr_concentration_lag_ols.r nitrate MR-violation
#          lag regression (near_mcl / mean_conc_z -> forward-window MR
#          violation), swapping that script's fixed production
#          downstream-of-mine PWSID set for the step-instrument grid's
#          k=2 main-arm PWSID set (n_mine_hucs_linked >= 1). Same
#          measurement-level SYR2 file, same violation-window matching
#          logic (ported inline, nitrate-only — mr_same_fwd/fwd6mon do
#          not need the rule333/anyioc machinery), same regression
#          formula. Terminal-only diagnostic: no .tex, no clean_data/ or
#          output/ writes, no changes to the production pipeline.
# Inputs:
#   clean_data/cws_data/step_instruments.parquet
#   clean_data/cws_6year_review_measurement_level_syr2.parquet
#   Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.parquet
# Outputs: terminal printout, and (as of 2026-09-14, extending the original
#          terminal-only diagnostic per the k2 main.tex table plan)
#          output/reg/mr_concentration_lag_ols_k2.tex
# Author: EK  Date: 2026-09-14
# ============================================================

.libPaths(c(.libPaths(), "Z:/ek559/RPackages"))
library(fixest)
library(arrow)
library(dplyr)

ROOT <- "Z:/ek559/mining_wq"
VIOL_PATH <- "Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.parquet"
NITRATE_CODE <- "1040"

# ── Step 1: k=2 main-arm PWSID universe ─────────────────────────────────
si <- read_parquet(file.path(ROOT, "clean_data/cws_data/step_instruments.parquet"))
stopifnot(is.character(si$PWSID))
k2_pwsids <- si %>% filter(arm == "main", k == 2, n_mine_hucs_linked >= 1) %>%
  pull(PWSID) %>% unique()
cat(sprintf("k=2 main-arm PWSID universe: %d CWSs\n", length(k2_pwsids)))

# ── Step 2: SYR2 measurement-level nitrate readings, restricted to k=2 ──
meas <- read_parquet(file.path(ROOT, "clean_data/cws_6year_review_measurement_level_syr2.parquet"))
stopifnot(is.character(meas$PWSID))
meas <- meas %>% filter(PWSID %in% k2_pwsids, contaminant_code == NITRATE_CODE)
cat(sprintf("Nitrate SYR2 measurement rows in k=2 main arm: %d (%d distinct CWSs)\n",
            nrow(meas), n_distinct(meas$PWSID)))

# ── Step 3: MR violations, nitrate only, restricted to k=2 (same window ─
#    logic as build_mr_concentration_lag.py's mr_same_fwd/fwd6mon, ported
#    inline since only the same-contaminant match is needed here) ───────
cat("\nReading MR violations (column-projected, PWSID-filtered)...\n")
viol <- read_parquet(VIOL_PATH,
                      col_select = c("PWSID", "NON_COMPL_PER_BEGIN_DATE",
                                     "VIOLATION_CATEGORY_CODE", "CONTAMINANT_CODE"))
viol$PWSID <- as.character(viol$PWSID)
viol <- viol %>% filter(VIOLATION_CATEGORY_CODE == "MR", PWSID %in% k2_pwsids,
                         CONTAMINANT_CODE == NITRATE_CODE)
viol$viol_date <- as.Date(viol$NON_COMPL_PER_BEGIN_DATE, format = "%m/%d/%Y")
viol <- viol[!is.na(viol$viol_date) & format(viol$viol_date, "%Y") >= "1990", ]
cat(sprintf("Nitrate MR violations in k=2 main arm: %d rows (%d distinct CWSs)\n",
            nrow(viol), n_distinct(viol$PWSID)))

dates_by_pwsid <- viol %>% group_by(PWSID) %>%
  summarise(dates = list(sort(viol_date)), .groups = "drop")
dates_lookup <- setNames(dates_by_pwsid$dates, dates_by_pwsid$PWSID)

window_count <- function(sorted_dates, lo, hi) {
  if (is.null(sorted_dates) || length(sorted_dates) == 0) return(0L)
  sum(sorted_dates >= lo & sorted_dates <= hi)
}

meas$sample_date <- as.Date(meas$sample_date)
meas$mr_same_fwd     <- 0L
meas$mr_same_fwd6mon <- 0L
for (i in seq_len(nrow(meas))) {
  pwsid <- meas$PWSID[i]
  d     <- dates_lookup[[pwsid]]
  s     <- meas$sample_date[i]
  meas$mr_same_fwd[i]     <- as.integer(window_count(d, s + 1,   s + 365) > 0)
  meas$mr_same_fwd6mon[i] <- as.integer(window_count(d, s + 1,   s + 182) > 0)
}
cat(sprintf("mr_same_fwd mean: %.4f | mr_same_fwd6mon mean: %.4f\n",
            mean(meas$mr_same_fwd), mean(meas$mr_same_fwd6mon)))

# ── Step 4: same spec as mr_concentration_lag_ols.r ──────────────────────
nit_df <- meas
nit_df$mean_concentration <- ave(nit_df$VALUE, nit_df$PWSID, nit_df$YEAR, FUN = mean)
nit_df$mean_conc_z <- scale(nit_df$mean_concentration)[, 1]

n_near_mcl <- sum(nit_df$near_mcl == 1, na.rm = TRUE)
cat(sprintf("Nitrate (k=2) subset N = %d | near_mcl==1 readings: %d\n", nrow(nit_df), n_near_mcl))

nit_df_lpm <- nit_df
nit_df_lpm$mr_same_fwd     <- as.numeric(nit_df$mr_same_fwd)     * 100
nit_df_lpm$mr_same_fwd6mon <- as.numeric(nit_df$mr_same_fwd6mon) * 100

fml_fwd     <- mr_same_fwd     ~ near_mcl + mean_conc_z | PWSID + YEAR
fml_fwd6mon <- mr_same_fwd6mon ~ near_mcl + mean_conc_z | PWSID + YEAR

fwd     <- tryCatch(feols(fml_fwd,     data = nit_df_lpm, cluster = ~PWSID, warn = FALSE, notes = FALSE),
                     error = function(e) { cat("ERROR (fwd):", conditionMessage(e), "\n"); NULL })
fwd6mon <- tryCatch(feols(fml_fwd6mon, data = nit_df_lpm, cluster = ~PWSID, warn = FALSE, notes = FALSE),
                     error = function(e) { cat("ERROR (fwd6mon):", conditionMessage(e), "\n"); NULL })

cat("\n==================== k=2 main-arm nitrate MR lag regression ====================\n")
cat("(same spec as output/reg/mr_concentration_lag_ols.tex; national downstream-of-mine\n")
cat(" sample swapped for the step-grid's k=2 main-arm sample)\n\n")
if (!is.null(fwd))     { cat("--- Nitrate MR (1-yr fwd window) ---\n");  print(summary(fwd)) }
if (!is.null(fwd6mon)) { cat("\n--- Nitrate MR (6-mon fwd window) ---\n"); print(summary(fwd6mon)) }

cat("\nFor comparison, published (national downstream-of-mine, N=851):\n")
cat("  1-yr:  near_mcl 58.97** (24.60) | mean_conc_z 1.28 (1.43)\n")
cat("  6-mon: near_mcl 26.11** (10.53) | mean_conc_z 0.05 (0.87)\n")

# ── Step 5: LaTeX table (extends the original terminal-only diagnostic per
# the k2 main.tex table plan; helpers copied from mr_concentration_lag_ols.r,
# with the "utility" wording from k2's Step 0.6 in place of the original's
# "CWS" substitutions) ──────────────────────────────────────────────────────
wrap_table_float <- function(path, caption_text, label = NULL) {
  lines <- readLines(path)
  bg_line   <- grep("^\\\\begingroup\\s*$", lines)[1]
  eg_line   <- grep("^\\\\par\\\\endgroup\\s*$", lines)
  eg_line   <- eg_line[length(eg_line)]
  adj_start <- grep("^\\s*\\\\begin\\{adjustbox\\}", lines)[1]
  adj_end   <- grep("^\\s*\\\\end\\{adjustbox\\}", lines)
  adj_end   <- adj_end[length(adj_end)]
  tab_end   <- grep("^\\s*\\\\end\\{tabular\\}", lines)
  tab_end   <- tab_end[length(tab_end)]
  note_lines <- trimws(lines[(tab_end + 1):(adj_end - 1)])
  note_lines <- note_lines[note_lines != ""]
  cap_line <- if (!is.null(label)) {
    sprintf("\\caption{%s}\\label{%s}", caption_text, label)
  } else {
    sprintf("\\caption{%s}", caption_text)
  }
  new_body <- c(
    "\\begin{table}[htbp]", cap_line, "\\centering",
    lines[adj_start], lines[(adj_start + 1):tab_end], "\\end{adjustbox}", "",
    note_lines, "\\par", "\\end{table}"
  )
  before <- if (bg_line > 1) lines[seq_len(bg_line - 1)] else character(0)
  after  <- if (eg_line < length(lines)) lines[(eg_line + 1):length(lines)] else character(0)
  writeLines(c(before, new_body, after), path)
}

rename_tex_k2 <- function(path) {
  txt <- paste(readLines(path), collapse = "\n")
  subs <- list(
    c("near\\_mcl",           "Concen. $>$ 50\\% MCL"),
    c("mean\\_conc\\_z",      "Mean concen. (z-score)"),
    c("PWSID fixed-effects",   "Utility fixed-effects"),
    c("PWSID fixed effects",   "Utility fixed effects"),
    c("Clustered \\(PWSID\\) standard-errors in parentheses",
      "Clustered (Utility) standard-errors in parentheses"),
    c("mr\\_same\\_fwd6mon",   ""),
    c("mr\\_same\\_fwd",       "")
  )
  for (s in subs) txt <- gsub(s[[1]], s[[2]], txt, fixed = TRUE)
  txt <- gsub("(?<![a-zA-Z])ratio(?![a-zA-Z])", "Concen./MCL", txt, perl = TRUE)
  txt <- gsub("[ \t]*Dependent Variables:.*?\\\\\\\\\n", "", txt)
  txt <- gsub("\n[ \t]*&[ \t]*&[ \t]*\\\\\\\\", "", txt)
  writeLines(strsplit(txt, "\n")[[1]], path)
}

right_align_tabular_k2 <- function(path) {
  lines <- readLines(path)
  txt   <- paste(lines, collapse = "\n")
  m     <- regmatches(txt, regexpr("\\\\begin\\{tabular\\}\\{l+c+\\}", txt))
  if (length(m) == 1 && nzchar(m)) {
    txt <- sub(m, gsub("c", "r", m), txt, fixed = TRUE)
    writeLines(strsplit(txt, "\n")[[1]], path)
  }
}

pad_stars_for_decimal_align_k2 <- function(path) {
  lines <- readLines(path)
  mid_line  <- grep("^\\s*\\\\midrule\\s*$", lines)[1]
  blank_row <- grep("^\\s*\\\\\\\\\\s*$", lines)
  blank_row <- blank_row[blank_row > mid_line][1]
  if (is.na(mid_line) || is.na(blank_row)) return(invisible(NULL))
  block_idx <- (mid_line + 1):(blank_row - 1)
  block     <- lines[block_idx]
  cell_lists  <- lapply(block, function(l) strsplit(l, "&", fixed = TRUE)[[1]])
  is_coef_row <- vapply(cell_lists, function(cells) nzchar(trimws(cells[1])), logical(1))
  star_pat <- "\\$\\^\\{(\\*+)\\}\\$"
  star_count <- function(cell) {
    if (!grepl(star_pat, cell)) return(0)
    m <- regmatches(cell, regexpr(star_pat, cell))
    nchar(gsub("[^*]", "", m))
  }
  n_col     <- max(vapply(cell_lists, length, integer(1)))
  max_stars <- rep(0, n_col)
  for (i in which(is_coef_row)) {
    cells <- cell_lists[[i]]
    for (j in 2:length(cells)) max_stars[j] <- max(max_stars[j], star_count(cells[j]))
  }
  pad_cell <- function(cell, target) {
    if (target == 0) return(cell)
    if (grepl(star_pat, cell)) {
      n <- star_count(cell)
      if (n >= target) return(cell)
      phantom <- strrep("*", target - n)
      pos     <- regexpr(star_pat, cell)
      start   <- pos[1]; len <- attr(pos, "match.length")
      new_sup <- paste0("$^{", strrep("*", n), "\\phantom{", phantom, "}}$")
      paste0(substr(cell, 1, start - 1), new_sup, substr(cell, start + len, nchar(cell)))
    } else {
      num_pat <- "^\\s*-?[0-9][0-9,]*\\.?[0-9]*"
      pos     <- regexpr(num_pat, cell)
      start   <- pos[1]; len <- attr(pos, "match.length")
      phantom <- strrep("*", target)
      insert  <- paste0("$^{\\phantom{", phantom, "}}$")
      paste0(substr(cell, 1, start + len - 1), insert, substr(cell, start + len, nchar(cell)))
    }
  }
  for (i in which(is_coef_row)) {
    cells <- cell_lists[[i]]
    for (j in 2:length(cells)) if (max_stars[j] > 0) cells[j] <- pad_cell(cells[j], max_stars[j])
    block[i] <- paste(cells, collapse = "&")
  }
  lines[block_idx] <- block
  writeLines(lines, path)
}

reformat_notes_tiny_k2 <- function(path) {
  lines <- readLines(path)
  adj_end   <- grep("^\\s*\\\\end\\{adjustbox\\}\\s*$", lines)
  end_table <- grep("^\\\\end\\{table\\}\\s*$", lines)
  if (length(adj_end) == 0 || length(end_table) == 0) return(invisible(NULL))
  adj_end   <- adj_end[length(adj_end)]
  end_table <- end_table[length(end_table)]
  note_raw  <- lines[(adj_end + 1):(end_table - 1)]
  drop_pat  <- "^\\s*(\\\\par(\\\\endgroup|\\s*(\\\\raggedright)?)?|\\\\begingroup|\\\\raggedright)?\\s*$"
  note_text <- paste(trimws(note_raw[!grepl(drop_pat, note_raw)]), collapse = " ")
  new_lines <- c(
    lines[1:adj_end],
    sprintf("{\\tiny\\linespread{1}\\selectfont \\par \\raggedright %s}", note_text),
    "\\end{table}"
  )
  writeLines(new_lines, path)
}

if (!is.null(fwd) && !is.null(fwd6mon)) {
  dir.create("Z:/ek559/mining_wq/output/reg", showWarnings = FALSE, recursive = TRUE)
  note_k2_tex <- paste0(
    "\\textit{Notes:} SYR2 sample restricted to utilities with a coal mine within two ",
    "flow steps upstream of their intake and no coal mine colocated with their intake ",
    "(1998--2005), nitrate only. Outcome: nitrate MR (monitoring/reporting) violation ",
    "in the forward window (1--365 days for the 1-yr column; 1--182 days for the ",
    "6-mon column) following the sample date. Concen. $>$ 50\\% MCL = reading at ",
    "50--100\\% of the MCL, the quarterly-monitoring trigger. Mean concentration = ",
    "utility-year mean reading, z-scored within chemical. Coefficients and standard ",
    "errors are in percentage points. All specifications include utility and year ",
    "fixed effects. *** p$<$0.01, ** p$<$0.05, * p$<$0.1. SEs clustered at the ",
    "utility level."
  )
  out_tex_k2 <- "Z:/ek559/mining_wq/output/reg/mr_concentration_lag_ols_k2.tex"
  etable(fwd, fwd6mon,
         headers      = c("Nitrate MR (1-yr)", "Nitrate MR (6-mon)"),
         notes        = note_k2_tex,
         fitstat      = ~n,
         digits       = "r4",
         drop.section = "fixef",
         style.tex    = style.tex("aer", adjustbox = TRUE),
         file         = out_tex_k2,
         replace      = TRUE)
  rename_tex_k2(out_tex_k2)
  right_align_tabular_k2(out_tex_k2)
  pad_stars_for_decimal_align_k2(out_tex_k2)
  wrap_table_float(out_tex_k2,
    "Nitrate MR violations following a reading above 50\\% of the MCL, two-step upstream watershed linkage",
    label = "tab:mr_concentration_lag_ols_k2")
  reformat_notes_tiny_k2(out_tex_k2)
  cat(sprintf("\nTable saved to: %s\n", out_tex_k2))
  if (file.exists(out_tex_k2) && file.info(out_tex_k2)$size > 0) {
    cat(sprintf("Output verified: %s exists and is non-zero.\n", out_tex_k2))
  } else {
    cat(sprintf("[ERROR] %s missing or empty.\n", out_tex_k2))
  }
} else {
  cat("\n[ERROR] fwd or fwd6mon model failed -- skipping .tex render.\n")
}

cat("\nDone.\n")
