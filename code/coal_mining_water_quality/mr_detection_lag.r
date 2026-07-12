# ============================================================
# Script: mr_detection_lag.r
# Purpose: Test whether a contaminant DETECTION (reading above the
#          detection limit, at ANY level -- not necessarily near the
#          MCL) predicts a subsequent same-contaminant MR violation.
#          This tests the detection/monitoring-status trigger channel
#          (a detection can revoke a monitoring waiver and bump a CWS
#          to a more frequent sampling schedule -> more chances to miss
#          a required sample -> MR violation), which -- unlike the
#          50%-MCL magnitude trigger in mr_concentration_lag.r -- can
#          operate for arsenic and the other IOCs, none of which ever
#          approach 50% of their MCL in this sample.
#          Forward-window table + past-window placebo table, mirroring
#          mr_concentration_lag.r column-for-column but with DETECT as
#          the sole regressor. Windows: 1-year and 3-year (forward and
#          matching past-window placebos).
# Inputs:  clean_data/mr_concentration_lag_measurement.parquet
# Outputs: output/reg/mr_detection_lag.tex
#          output/reg/mr_detection_lag_placebo.tex
# Author: EK  Date: 2026-07-03
# ============================================================

.libPaths("Z:/ek559/RPackages")
library(arrow)
library(fixest)

ROOT <- "Z:/ek559/mining_wq"
setwd(ROOT)

# ── Step 1: Load + schema check ───────────────────────────────────────────────
cat("Loading measurement-level analysis dataset...\n")
df <- read_parquet("clean_data/mr_concentration_lag_measurement.parquet")
str(df)   # PWSID must be <chr>, YEAR must be <int>, DETECT present

cat(sprintf("\nRows: %d | unique PWSID: %d | years %d-%d\n",
            nrow(df), length(unique(df$PWSID)), min(df$YEAR), max(df$YEAR)))
cat("DETECT rate by chemical:\n")
print(round(tapply(df$DETECT, df$CHEMID_name, mean, na.rm = TRUE), 3))

ars_df  <- df[df$contaminant_code == "1005", ]
nit_df  <- df[df$contaminant_code == "1040", ]
pool_df <- df

cat(sprintf("\nArsenic (1005) subset N = %d (detects = %d)\n", nrow(ars_df), sum(ars_df$DETECT, na.rm = TRUE)))
cat(sprintf("Nitrate (1040) subset N = %d (detects = %d)\n", nrow(nit_df), sum(nit_df$DETECT, na.rm = TRUE)))
cat(sprintf("Pooled subset N = %d (detects = %d)\n", nrow(pool_df), sum(pool_df$DETECT, na.rm = TRUE)))

# ── Step 2: Named formulas — DETECT as sole regressor ─────────────────────────
# Windows: 1-year (mr_*_fwd) and 3-year (mr_*_fwd3yr) forward; placebos use the
# matching past windows (mr_*_past / mr_*_past3yr).
fml_ars      <- mr_same_fwd     ~ DETECT | PWSID + YEAR
fml_ars_3yr  <- mr_same_fwd3yr  ~ DETECT | PWSID + YEAR
fml_nit      <- mr_same_fwd     ~ DETECT | PWSID + YEAR
fml_nit_3yr  <- mr_same_fwd3yr  ~ DETECT | PWSID + YEAR
fml_pool      <- mr_anyioc_fwd     ~ DETECT | PWSID + YEAR + contaminant_code
fml_pool_3yr  <- mr_anyioc_fwd3yr  ~ DETECT | PWSID + YEAR + contaminant_code

fml_ars_placebo       <- mr_same_past      ~ DETECT | PWSID + YEAR
fml_ars_3yr_placebo   <- mr_same_past3yr   ~ DETECT | PWSID + YEAR
fml_nit_placebo       <- mr_same_past      ~ DETECT | PWSID + YEAR
fml_nit_3yr_placebo   <- mr_same_past3yr   ~ DETECT | PWSID + YEAR
fml_pool_placebo      <- mr_anyioc_past     ~ DETECT | PWSID + YEAR + contaminant_code
fml_pool_3yr_placebo  <- mr_anyioc_past3yr  ~ DETECT | PWSID + YEAR + contaminant_code

# Fit helper: arsenic DETECT has little within-cell variation (30 detects); if
# the model can't be identified, skip that column rather than halting.
safe_feols <- function(fml, data, tag) {
  tryCatch(feols(fml, data = data, cluster = ~PWSID),
           error = function(e) { cat(sprintf("[SKIPPED %s] %s\n", tag, conditionMessage(e))); NULL })
}

# ── Step 3: Forward-window regressions ────────────────────────────────────────
ars      <- safe_feols(fml_ars,      ars_df,  "ars 1yr")
ars_3yr  <- safe_feols(fml_ars_3yr,  ars_df,  "ars 3yr")
nit      <- safe_feols(fml_nit,      nit_df,  "nit 1yr")
nit_3yr  <- safe_feols(fml_nit_3yr,  nit_df,  "nit 3yr")
pool     <- safe_feols(fml_pool,     pool_df, "pool 1yr")
pool_3yr <- safe_feols(fml_pool_3yr, pool_df, "pool 3yr")

have_ars <- !is.null(ars) && !is.null(ars_3yr)

for (nm in c("ars","ars_3yr","nit","nit_3yr","pool","pool_3yr")) {
  m <- get(nm)
  if (!is.null(m)) { cat(sprintf("\n--- forward: %s ---\n", nm)); print(summary(m)) }
}

# ── Step 4: Past-window placebo regressions ───────────────────────────────────
ars_p      <- safe_feols(fml_ars_placebo,      ars_df,  "ars 1yr placebo")
ars_3yr_p  <- safe_feols(fml_ars_3yr_placebo,  ars_df,  "ars 3yr placebo")
nit_p      <- safe_feols(fml_nit_placebo,      nit_df,  "nit 1yr placebo")
nit_3yr_p  <- safe_feols(fml_nit_3yr_placebo,  nit_df,  "nit 3yr placebo")
pool_p     <- safe_feols(fml_pool_placebo,     pool_df, "pool 1yr placebo")
pool_3yr_p <- safe_feols(fml_pool_3yr_placebo, pool_df, "pool 3yr placebo")

for (nm in c("ars_p","ars_3yr_p","nit_p","nit_3yr_p","pool_p","pool_3yr_p")) {
  m <- get(nm)
  if (!is.null(m)) { cat(sprintf("\n--- placebo: %s ---\n", nm)); print(summary(m)) }
}

# ── Step 5: table helpers (copied from mr_concentration_lag.r) ────────────────
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
  cap_line <- if (!is.null(label)) sprintf("\\caption{%s}\\label{%s}", caption_text, label) else sprintf("\\caption{%s}", caption_text)
  new_body <- c(
    "\\begin{table}[htbp]", cap_line, "\\centering",
    lines[adj_start], lines[(adj_start + 1):tab_end],
    "\\end{adjustbox}", "", note_lines, "\\par", "\\end{table}")
  before <- if (bg_line > 1) lines[seq_len(bg_line - 1)] else character(0)
  after  <- if (eg_line < length(lines)) lines[(eg_line + 1):length(lines)] else character(0)
  writeLines(c(before, new_body, after), path)
}

rename_tex <- function(path) {
  txt <- paste(readLines(path), collapse = "\n")
  subs <- list(
    c("DETECT",                          "Detected (1/0)"),
    c("PWSID fixed-effects",             "CWS fixed-effects"),
    c("PWSID fixed effects",             "CWS fixed effects"),
    c("contaminant\\_code fixed-effects","Contaminant fixed-effects"),
    c("contaminant\\_code fixed effects","Contaminant fixed effects"),
    c("Clustered \\(PWSID\\) standard-errors in parentheses",
      "Clustered (CWS) standard-errors in parentheses"),
    c("mr\\_same\\_fwd3yr",    ""), c("mr\\_same\\_fwd6mon",   ""), c("mr\\_same\\_fwd",       ""),
    c("mr\\_anyioc\\_fwd3yr",  ""), c("mr\\_anyioc\\_fwd6mon", ""), c("mr\\_anyioc\\_fwd",     ""),
    c("mr\\_same\\_past3yr",   ""), c("mr\\_same\\_past6mon",  ""), c("mr\\_same\\_past",      ""),
    c("mr\\_anyioc\\_past3yr", ""), c("mr\\_anyioc\\_past6mon",""), c("mr\\_anyioc\\_past",    "")
  )
  for (s in subs) txt <- gsub(s[[1]], s[[2]], txt, fixed = TRUE)
  txt <- gsub("[ \t]*Dependent Variables:.*?\\\\\\\\\n", "", txt)
  txt <- gsub("\n[ \t]*&[ \t]*&[ \t]*&[ \t]*&[ \t]*&[ \t]*&[ \t]*\\\\\\\\", "", txt)
  writeLines(strsplit(txt, "\n")[[1]], path)
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
  new_lines <- c(lines[1:adj_end],
    sprintf("{\\tiny\\linespread{1}\\selectfont \\par \\raggedright %s}", note_text),
    "\\end{table}")
  writeLines(new_lines, path)
}

# ── Step 6: Build forward + placebo tables ────────────────────────────────────
dir.create(file.path(ROOT, "output/reg"), showWarnings = FALSE, recursive = TRUE)

if (have_ars) {
  headers <- c("Arsenic MR (1-yr)", "Arsenic MR (3-yr)", "Nitrate MR (1-yr)",
               "Nitrate MR (3-yr)", "Pooled IOC (1-yr)", "Pooled IOC (3-yr)")
} else {
  cat("\n[NOTE] Arsenic DETECT model not identified -- arsenic columns omitted.\n")
  headers <- c("Nitrate MR (1-yr)", "Nitrate MR (3-yr)", "Pooled IOC (1-yr)", "Pooled IOC (3-yr)")
}

note_main <- paste0(
  "SYR2 only (1998--2005), strictly-downstream mining sample. Regressor: Detected = 1 if the ",
  "reading is above the detection limit (at any level), 0 otherwise. Outcome: same-contaminant ",
  "MR violation within the year (1-yr) or three years (3-yr) following the reading; pooled IOC uses any ",
  "RULE\\_CODE 333 MR violation and excludes arsenic/nitrate, which have their own rule codes. ",
  "This tests the detection/monitoring-status trigger (a detection can revoke a monitoring waiver ",
  "and raise sampling frequency), which -- unlike the 50\\%-MCL magnitude trigger -- can operate ",
  "for IOCs that never approach their MCL. *** p$<$0.01, ** p$<$0.05, * p$<$0.1. SEs clustered at the CWS level."
)

out_tex <- file.path(ROOT, "output/reg/mr_detection_lag.tex")
# Direct etable() calls (not do.call) avoid a fixest 0.14.0/R 4.5.2 coercion bug.
if (have_ars) {
  etable(ars, ars_3yr, nit, nit_3yr, pool, pool_3yr,
         headers = headers, notes = note_main, fitstat = ~n,
         style.tex = style.tex("aer", adjustbox = TRUE), file = out_tex, replace = TRUE)
} else {
  etable(nit, nit_3yr, pool, pool_3yr,
         headers = headers, notes = note_main, fitstat = ~n,
         style.tex = style.tex("aer", adjustbox = TRUE), file = out_tex, replace = TRUE)
}
rename_tex(out_tex)
wrap_table_float(out_tex,
  "MR violations following a contaminant DETECTION (any level)",
  label = "tab:mr_detection_lag")
reformat_notes_tiny(out_tex)
cat(sprintf("\nForward table saved to: %s\n", out_tex))

note_placebo <- paste0(
  "Past-window placebo: same DETECT specification as the forward-window table but the outcome is ",
  "an MR violation occurring BEFORE the reading (1--365 days before for 1-yr columns; 1--1095 days ",
  "before for 3-yr columns). A detection should precede, not follow, the MR violation. ",
  "*** p$<$0.01, ** p$<$0.05, * p$<$0.1. SEs clustered at the CWS level."
)
out_tex_p <- file.path(ROOT, "output/reg/mr_detection_lag_placebo.tex")
if (have_ars) {
  etable(ars_p, ars_3yr_p, nit_p, nit_3yr_p, pool_p, pool_3yr_p,
         headers = headers, notes = note_placebo, fitstat = ~n,
         style.tex = style.tex("aer", adjustbox = TRUE), file = out_tex_p, replace = TRUE)
} else {
  etable(nit_p, nit_3yr_p, pool_p, pool_3yr_p,
         headers = headers, notes = note_placebo, fitstat = ~n,
         style.tex = style.tex("aer", adjustbox = TRUE), file = out_tex_p, replace = TRUE)
}
rename_tex(out_tex_p)
wrap_table_float(out_tex_p,
  "Placebo: MR violations preceding a contaminant DETECTION (past window)",
  label = "tab:mr_detection_lag_placebo")
reformat_notes_tiny(out_tex_p)
cat(sprintf("Placebo table saved to: %s\n", out_tex_p))

for (p in c(out_tex, out_tex_p)) {
  if (file.exists(p) && file.info(p)$size > 0) {
    cat(sprintf("Output verified: %s exists and is non-zero.\n", p))
  } else {
    cat(sprintf("[ERROR] %s missing or empty.\n", p))
  }
}
cat("=== DONE ===\n")
