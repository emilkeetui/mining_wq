# ============================================================
# Script: mr_concentration_lag_logit.r
# Purpose: OLS+Logit variant of mr_concentration_lag.r's nitrate spec,
#          structured identically to
#          mr_concentration_lag_national_downstream_states.r (4 cols:
#          OLS 1-yr, OLS 6-mon, Logit 1-yr, Logit 6-mon) but estimated
#          on mr_concentration_lag.r's measurement-level downstream-only
#          mining sample (minehuc_downstream_of_mine==1) rather than the
#          national sample restricted by state.
# Inputs:  clean_data/mr_concentration_lag_measurement.parquet
# Outputs: output/reg/mr_concentration_lag_logit.tex
#          output/reg/mr_concentration_lag_logit_present.tex
# Author: EK  Date: 2026-09-02
# ============================================================

.libPaths(c("C:/Users/ek559/AppData/Local/R/win-library/4.6", "Z:/ek559/RPackages"))
library(arrow)
library(fixest)

ROOT <- "Z:/ek559/mining_wq"
setwd(ROOT)

# ── Step 1: Load + schema check ───────────────────────────────────────────────
cat("Loading measurement-level analysis dataset...\n")
df <- read_parquet("clean_data/mr_concentration_lag_measurement.parquet")
str(df)   # PWSID must be <chr>, YEAR must be <int>

cat(sprintf("\nRows: %d | unique PWSID: %d | years %d-%d\n",
            nrow(df), length(unique(df$PWSID)), min(df$YEAR), max(df$YEAR)))

# ── Step 2: Nitrate subsample (raw 0/1 outcomes retained for logit) ───────────
nit_df <- df[df$contaminant_code == "1040", ]

# mean_concentration = PWSID-YEAR mean VALUE (matches mr_concentration_lag.r)
nit_df$mean_concentration <- ave(nit_df$VALUE, nit_df$PWSID, nit_df$YEAR, FUN = mean)
nit_df$mean_conc_z <- scale(nit_df$mean_concentration)[, 1]

cat(sprintf("\nNitrate (1040) subset N = %d\n", nrow(nit_df)))

n_near_mcl <- sum(nit_df$near_mcl == 1, na.rm = TRUE)
cat(sprintf("near_mcl==1 readings: %d\n", n_near_mcl))

# LPM columns fit on a 0/100-coded copy so coefficients/SEs are already in
# percentage-point units; logit columns keep the genuine 0/1 outcome
# (required by the binomial family) — same split as
# mr_concentration_lag_national_downstream_states.r.
nit_df_lpm <- nit_df
nit_df_lpm$mr_same_fwd     <- as.numeric(nit_df$mr_same_fwd)     * 100
nit_df_lpm$mr_same_fwd6mon <- as.numeric(nit_df$mr_same_fwd6mon) * 100

# ── Step 3: Named formulas ─────────────────────────────────────────────────────
fml_fwd     <- mr_same_fwd     ~ near_mcl + mean_conc_z | PWSID + YEAR
fml_fwd6mon <- mr_same_fwd6mon ~ near_mcl + mean_conc_z | PWSID + YEAR

# ── Step 4: Regressions ────────────────────────────────────────────────────────
fwd     <- feols(fml_fwd,     data = nit_df_lpm, cluster = ~PWSID)
fwd6mon <- feols(fml_fwd6mon, data = nit_df_lpm, cluster = ~PWSID)

fwd_logit     <- feglm(fml_fwd,     data = nit_df, cluster = ~PWSID, family = binomial)
fwd6mon_logit <- feglm(fml_fwd6mon, data = nit_df, cluster = ~PWSID, family = binomial)

cat("\n--- Nitrate MR (1-yr), forward window ---\n");          print(summary(fwd))
cat("\n--- Nitrate MR (6-mon), forward window ---\n");         print(summary(fwd6mon))
cat("\n--- Nitrate MR (1-yr), forward window, logit ---\n");   print(summary(fwd_logit))
cat("\n--- Nitrate MR (6-mon), forward window, logit ---\n");  print(summary(fwd6mon_logit))

# ── Step 5: table helpers (copied from mr_concentration_lag_national_downstream_states.r) ─
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
    "\\begin{table}[htbp]",
    cap_line,
    "\\centering",
    lines[adj_start],
    lines[(adj_start + 1):tab_end],
    "\\end{adjustbox}",
    "",
    note_lines,
    "\\par",
    "\\end{table}"
  )

  before <- if (bg_line > 1) lines[seq_len(bg_line - 1)] else character(0)
  after  <- if (eg_line < length(lines)) lines[(eg_line + 1):length(lines)] else character(0)
  writeLines(c(before, new_body, after), path)
}

# rename_tex: CWS terminology used throughout (not "Utility"), per CLAUDE.md --
# always refer to the drinking water systems as Community Water Systems / CWS.
rename_tex <- function(path) {
  txt <- paste(readLines(path), collapse = "\n")
  subs <- list(
    c("near\\_mcl",           "Concen. $>$ 50\\% MCL"),
    c("mean\\_conc\\_z",      "Mean concen. (z-score)"),
    c("PWSID fixed-effects",   "CWS fixed-effects"),
    c("PWSID fixed effects",   "CWS fixed effects"),
    c("Clustered \\(PWSID\\) standard-errors in parentheses",
      "Clustered (CWS) standard-errors in parentheses"),
    c("mr\\_same\\_fwd6mon",   ""),
    c("mr\\_same\\_fwd",       "")
  )
  for (s in subs) txt <- gsub(s[[1]], s[[2]], txt, fixed = TRUE)
  txt <- gsub("(?<![a-zA-Z])ratio(?![a-zA-Z])", "Concen./MCL", txt, perl = TRUE)
  txt <- gsub("[ \t]*Dependent Variables:.*?\\\\\\\\\n", "", txt)
  # Blank dep-var row: 4 columns -> 4 "&" cells, all blank
  txt <- gsub("\n[ \t]*&[ \t]*&[ \t]*&[ \t]*&[ \t]*\\\\\\\\", "", txt)
  writeLines(strsplit(txt, "\n")[[1]], path)
}

right_align_tabular <- function(path) {
  lines <- readLines(path)
  txt   <- paste(lines, collapse = "\n")
  m     <- regmatches(txt, regexpr("\\\\begin\\{tabular\\}\\{l+c+\\}", txt))
  if (length(m) == 1 && nzchar(m)) {
    txt <- sub(m, gsub("c", "r", m), txt, fixed = TRUE)
    writeLines(strsplit(txt, "\n")[[1]], path)
  }
}

pad_stars_for_decimal_align <- function(path) {
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

reformat_notes_tiny <- function(path) {
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

# ── Step 6: LaTeX table ─────────────────────────────────────────────────────────
dir.create(file.path(ROOT, "output/reg"), showWarnings = FALSE, recursive = TRUE)

note_main <- paste0(
  "\\textit{Notes:} SYR2 sample restricted to community water systems strictly ",
  "downstream of a coal mine (1998--2005), nitrate only. Outcome: nitrate MR ",
  "(monitoring/reporting) violation in the forward window (1--365 days for the 1-yr ",
  "column; 1--182 days for the 6-mon column) following the sample date. Concen. $>$ ",
  "50\\% MCL = reading at 50--100\\% of the MCL, the quarterly-monitoring trigger. ",
  "Mean concentration = CWS-year mean reading, z-scored within chemical. ",
  "Cols 1--2 are linear probability models, coefficients and standard errors in ",
  "percentage points; cols 3--4 are logit models on the underlying 0/1 outcome. ",
  "All specifications include CWS and year fixed effects. ",
  "*** p$<$0.01, ** p$<$0.05, * p$<$0.1. SEs clustered at the CWS level."
)

out_tex <- file.path(ROOT, "output/reg/mr_concentration_lag_logit.tex")
etable(fwd, fwd6mon, fwd_logit, fwd6mon_logit,
       headers      = list(":_:" = c("OLS", "OLS", "Logit", "Logit"),
                            " "   = c("Nitrate MR (1-yr)", "Nitrate MR (6-mon)",
                                      "Nitrate MR (1-yr)", "Nitrate MR (6-mon)")),
       family       = FALSE,
       notes        = note_main,
       fitstat      = ~n,
       digits       = "r4",
       drop.section = "fixef",
       style.tex    = style.tex("aer", adjustbox = TRUE),
       file         = out_tex,
       replace      = TRUE)
rename_tex(out_tex)
right_align_tabular(out_tex)
pad_stars_for_decimal_align(out_tex)
wrap_table_float(out_tex,
  "Nitrate MR violations following a reading above 50\\% of the MCL (downstream-of-mine sample)",
  label = "tab:mr_concentration_lag_logit")
reformat_notes_tiny(out_tex)
cat(sprintf("\nTable saved to: %s\n", out_tex))

if (file.exists(out_tex) && file.info(out_tex)$size > 0) {
  cat(sprintf("Output verified: %s exists and is non-zero.\n", out_tex))
} else {
  cat(sprintf("[ERROR] %s missing or empty.\n", out_tex))
}

# -- Presentation companion: notes stripped to FE + clustering + stars only
# (FE rows are dropped via drop.section="fixef" above, so the statement must
# stay) -- matches the _present.tex pattern in both source scripts.
note_main_present <- paste0(
  "\\textit{Notes:} All specifications include CWS and year fixed effects. ",
  "SEs clustered at the CWS level. *** p$<$0.01, ** p$<$0.05, * p$<$0.1."
)
out_tex_present <- sub("\\.tex$", "_present.tex", out_tex)
etable(fwd, fwd6mon, fwd_logit, fwd6mon_logit,
       headers      = list(":_:" = c("OLS", "OLS", "Logit", "Logit"),
                            " "   = c("Nitrate MR (1-yr)", "Nitrate MR (6-mon)",
                                      "Nitrate MR (1-yr)", "Nitrate MR (6-mon)")),
       family       = FALSE,
       notes        = note_main_present,
       fitstat      = ~n,
       digits       = "r4",
       drop.section = "fixef",
       style.tex    = style.tex("aer", adjustbox = TRUE),
       file         = out_tex_present,
       replace      = TRUE)
rename_tex(out_tex_present)
right_align_tabular(out_tex_present)
pad_stars_for_decimal_align(out_tex_present)
wrap_table_float(out_tex_present,
  "Nitrate MR violations following a reading above 50\\% of the MCL (downstream-of-mine sample)",
  label = "tab:mr_concentration_lag_logit")
reformat_notes_tiny(out_tex_present)
cat(sprintf("Presentation table saved to: %s\n", out_tex_present))

if (file.exists(out_tex_present) && file.info(out_tex_present)$size > 0) {
  cat(sprintf("Output verified: %s exists and is non-zero.\n", out_tex_present))
} else {
  cat(sprintf("[ERROR] %s missing or empty.\n", out_tex_present))
}
