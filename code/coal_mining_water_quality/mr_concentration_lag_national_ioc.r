# ============================================================
# Script: mr_concentration_lag_national_ioc.r
# Purpose: National-sample (all PWSIDs) ratchet-avoidance test for
#          inorganic contaminants -- arsenic, barium, selenium -- the
#          IOC analog of mr_concentration_lag_national.r (nitrate).
#          Unlike nitrate's 40 CFR 141.23(d)(2) trigger at 50% of the
#          MCL, the IOC quarterly-monitoring trigger is MCL exceedance
#          itself (40 CFR 141.23(c)(7)), and 141.23(c)(2)-(6) waivers
#          (down to 1 sample / 9 years) require all previous results
#          below the MCL; arsenic pre-2006 instead triggered mandatory
#          confirmation sampling (old 40 CFR 141.23(m)) rather than a
#          sustained quarterly ratchet. near_mcl (50-100% of MCL) here
#          therefore proxies ratchet risk on the NEXT reading rather
#          than a sub-MCL statutory trigger. Produces a pooled
#          (arsenic+barium+selenium, chemical FE) table and an
#          arsenic-only table.
# Inputs:  clean_data/mr_concentration_lag_national_ioc.parquet
# Outputs: output/reg/mr_concentration_lag_national_ioc.tex
#          output/reg/mr_concentration_lag_national_arsenic.tex
# Author: EK  Date: 2026-07-14
# ============================================================

.libPaths("Z:/ek559/RPackages")
library(arrow)
library(fixest)

ROOT <- "Z:/ek559/mining_wq"
setwd(ROOT)

# ── Step 1: Load + schema check ───────────────────────────────────────────────
cat("Loading national IOC analysis dataset...\n")
df <- read_parquet("clean_data/mr_concentration_lag_national_ioc.parquet")
str(df)   # PWSID must be <chr>, YEAR must be <int>

cat(sprintf("\nRows: %d | unique PWSID: %d | years %d-%d\n",
            nrow(df), length(unique(df$PWSID)), min(df$YEAR), max(df$YEAR)))
cat("\nRows by chemical:\n")
print(table(df$CHEMID_name))

n_near_mcl  <- sum(df$near_mcl == 1, na.rm = TRUE)
n_above_mcl <- sum(df$above_mcl == 1, na.rm = TRUE)
n_pwsid     <- length(unique(df$PWSID))
cat(sprintf("\nnear_mcl==1 readings (pooled): %d\n", n_near_mcl))
cat(sprintf("above_mcl==1 readings (pooled): %d\n", n_above_mcl))
cat(sprintf("Unique PWSIDs (pooled): %d\n", n_pwsid))

near_by_chem <- tapply(df$near_mcl, df$CHEMID_name, sum, na.rm = TRUE)
cat("\nnear_mcl by chemical:\n"); print(near_by_chem)

# mean_ratio = PWSID-YEAR-CHEMICAL mean of ratio (VALUE/MCL); concentrations
# are not comparable across chemicals, so ratio (not raw VALUE) is the pooled
# control, z-scored WITHIN chemical.
df$mean_ratio <- ave(df$ratio, df$PWSID, df$YEAR, df$CHEMID_name, FUN = mean)
df$mean_ratio_z <- ave(df$mean_ratio, df$CHEMID_name,
                        FUN = function(x) as.numeric(scale(x)))

# ── Raw-means frequency table (console only, pooled) ───────────────────────────
cat("\n--- Raw means: mr_same_fwd by near_mcl (pooled) ---\n")
print(tapply(df$mr_same_fwd, df$near_mcl, mean, na.rm = TRUE))
cat("\n--- Raw means: mr_same_fwd6mon by near_mcl (pooled) ---\n")
print(tapply(df$mr_same_fwd6mon, df$near_mcl, mean, na.rm = TRUE))
cat("\n--- Raw means: mr_same_past by near_mcl (pooled) ---\n")
print(tapply(df$mr_same_past, df$near_mcl, mean, na.rm = TRUE))
cat("\n--- Raw means: mr_same_past6mon by near_mcl (pooled) ---\n")
print(tapply(df$mr_same_past6mon, df$near_mcl, mean, na.rm = TRUE))

# ── Step 2: Named formulas ─────────────────────────────────────────────────────
fml_fwd_pooled      <- mr_same_fwd      ~ near_mcl + mean_ratio_z | PWSID + YEAR + CHEMID_name
fml_fwd6mon_pooled  <- mr_same_fwd6mon  ~ near_mcl + mean_ratio_z | PWSID + YEAR + CHEMID_name
fml_past_pooled     <- mr_same_past     ~ near_mcl + mean_ratio_z | PWSID + YEAR + CHEMID_name
fml_past6mon_pooled <- mr_same_past6mon ~ near_mcl + mean_ratio_z | PWSID + YEAR + CHEMID_name

fml_fwd_as      <- mr_same_fwd      ~ near_mcl + mean_ratio_z | PWSID + YEAR
fml_fwd6mon_as  <- mr_same_fwd6mon  ~ near_mcl + mean_ratio_z | PWSID + YEAR
fml_past_as     <- mr_same_past     ~ near_mcl + mean_ratio_z | PWSID + YEAR
fml_past6mon_as <- mr_same_past6mon ~ near_mcl + mean_ratio_z | PWSID + YEAR

# ── Step 3: Regressions ────────────────────────────────────────────────────────
fwd_pooled      <- feols(fml_fwd_pooled,      data = df, cluster = ~PWSID)
fwd6mon_pooled  <- feols(fml_fwd6mon_pooled,  data = df, cluster = ~PWSID)
past_pooled     <- feols(fml_past_pooled,     data = df, cluster = ~PWSID)
past6mon_pooled <- feols(fml_past6mon_pooled, data = df, cluster = ~PWSID)

df_as <- df[df$CHEMID_name == "arsenic", ]
fwd_as      <- feols(fml_fwd_as,      data = df_as, cluster = ~PWSID)
fwd6mon_as  <- feols(fml_fwd6mon_as,  data = df_as, cluster = ~PWSID)
past_as     <- feols(fml_past_as,     data = df_as, cluster = ~PWSID)
past6mon_as <- feols(fml_past6mon_as, data = df_as, cluster = ~PWSID)

cat("\n--- Pooled IOC MR (1-yr), forward window ---\n");   print(summary(fwd_pooled))
cat("\n--- Pooled IOC MR (6-mon), forward window ---\n");  print(summary(fwd6mon_pooled))
cat("\n--- Pooled placebo: past (1-yr) ---\n");             print(summary(past_pooled))
cat("\n--- Pooled placebo: past (6-mon) ---\n");            print(summary(past6mon_pooled))

cat("\n--- Arsenic MR (1-yr), forward window ---\n");   print(summary(fwd_as))
cat("\n--- Arsenic MR (6-mon), forward window ---\n");  print(summary(fwd6mon_as))
cat("\n--- Arsenic placebo: past (1-yr) ---\n");         print(summary(past_as))
cat("\n--- Arsenic placebo: past (6-mon) ---\n");        print(summary(past6mon_as))

# ── Step 4: table helpers (copied verbatim from mr_concentration_lag_national.r) ──
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

# rename_tex: adapted from mr_concentration_lag_national.r -- blank-dep-var-row
# regex for 4 columns (4 "&" cells instead of 6).
rename_tex <- function(path) {
  txt <- paste(readLines(path), collapse = "\n")
  subs <- list(
    c("near\\_mcl",           "Concen. $>$ 50\\% MCL"),
    c("mean\\_ratio\\_z",     "Mean concen./MCL (z-score)"),
    c("PWSID fixed-effects",   "CWS fixed-effects"),
    c("PWSID fixed effects",   "CWS fixed effects"),
    c("CHEMID\\_name fixed-effects", "Chemical fixed-effects"),
    c("CHEMID\\_name fixed effects", "Chemical fixed effects"),
    c("Clustered \\(PWSID\\) standard-errors in parentheses",
      "Clustered (CWS) standard-errors in parentheses"),
    c("mr\\_same\\_fwd6mon",   ""),
    c("mr\\_same\\_fwd",       ""),
    c("mr\\_same\\_past6mon",  ""),
    c("mr\\_same\\_past",      "")
  )
  for (s in subs) txt <- gsub(s[[1]], s[[2]], txt, fixed = TRUE)
  txt <- gsub("(?<![a-zA-Z])ratio(?![a-zA-Z])", "Concen./MCL", txt, perl = TRUE)
  txt <- gsub("[ \t]*Dependent Variables:.*?\\\\\\\\\n", "", txt)
  # Blank dep-var row: 4 columns -> 4 "&" cells, all blank
  txt <- gsub("\n[ \t]*&[ \t]*&[ \t]*&[ \t]*&[ \t]*\\\\\\\\", "", txt)
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
  new_lines <- c(
    lines[1:adj_end],
    sprintf("{\\tiny\\linespread{1}\\selectfont \\par \\raggedright %s}", note_text),
    "\\end{table}"
  )
  writeLines(new_lines, path)
}

# ── Step 5: LaTeX tables ─────────────────────────────────────────────────────────
dir.create(file.path(ROOT, "output/reg"), showWarnings = FALSE, recursive = TRUE)

note_pooled <- paste0(
  "National SYR2 sample (all PWSIDs, 1998--2005), arsenic + barium + selenium pooled. ",
  "Outcome: same-contaminant MR (monitoring/reporting) violation in the forward window ",
  "(1--365 days for the 1-yr column; 1--182 days for the 6-mon column) following the ",
  "sample date; placebo columns use the same windows measured BEFORE the sample date. ",
  "MCLs in force 1993--2005: arsenic 0.05 mg/L, barium 2.0 mg/L, selenium 0.05 mg/L. ",
  "near\\_mcl = reading at 50--100\\% of the MCL. Unlike nitrate (40 CFR 141.23(d)(2), ",
  "trigger at 50\\% of MCL), the IOC quarterly-monitoring trigger is MCL exceedance ",
  "itself (40 CFR 141.23(c)(7)), and 141.23(c)(2)--(6) waivers (down to 1 sample per ",
  "9-year cycle) require all previous results below the MCL; near\\_mcl therefore ",
  "proxies ratchet risk on the next reading rather than a sub-MCL statutory trigger. ",
  sprintf("N of readings with concentration at 50--100 percent of the MCL: %d (arsenic %d, barium %d, selenium %d). ",
          n_near_mcl, near_by_chem["arsenic"], near_by_chem["barium"], near_by_chem["selenium"]),
  sprintf("Unique PWSIDs: %d. ", n_pwsid),
  "Mean concen./MCL = PWSID-YEAR-chemical mean of reading/MCL, z-scored within chemical. ",
  "Chemical fixed effects included. ",
  "*** p$<$0.01, ** p$<$0.05, * p$<$0.1. SEs clustered at the CWS (PWSID) level."
)

n_near_as <- as.integer(near_by_chem["arsenic"])
n_pwsid_as <- length(unique(df_as$PWSID))
note_arsenic <- paste0(
  "National SYR2 sample (all PWSIDs, 1998--2005), arsenic only. ",
  "Outcome: arsenic MR (monitoring/reporting) violation in the forward window ",
  "(1--365 days for the 1-yr column; 1--182 days for the 6-mon column) following the ",
  "sample date; placebo columns use the same windows measured BEFORE the sample date. ",
  "MCL 1993--2005: 0.05 mg/L (interim rule, 40 CFR 141.11). Pre-2006, an exceedance ",
  "triggered mandatory confirmation sampling (3 additional analyses within one month; ",
  "old 40 CFR 141.23(m)) rather than a sustained quarterly ratchet -- the 2001 Arsenic ",
  "Rule's lower MCL (0.010 mg/L) and monitoring framework took effect Jan 23, 2006, ",
  "after the sample period. near\\_mcl = reading at 50--100\\% of the 0.05 mg/L MCL, ",
  "proxying risk of triggering confirmation sampling and losing waiver eligibility on ",
  "the next reading. ",
  sprintf("N of readings with concentration at 50--100 percent of the MCL: %d. ", n_near_as),
  sprintf("Unique PWSIDs: %d. ", n_pwsid_as),
  "Mean concen./MCL = PWSID-YEAR mean of reading/MCL, z-scored. ",
  "*** p$<$0.01, ** p$<$0.05, * p$<$0.1. SEs clustered at the CWS (PWSID) level."
)

out_tex_pooled <- file.path(ROOT, "output/reg/mr_concentration_lag_national_ioc.tex")
etable(fwd_pooled, fwd6mon_pooled, past_pooled, past6mon_pooled,
       headers   = c("IOC MR (1-yr)", "IOC MR (6-mon)",
                      "Placebo: past (1-yr)", "Placebo: past (6-mon)"),
       notes     = note_pooled,
       fitstat   = ~n,
       style.tex = style.tex("aer", adjustbox = TRUE),
       file      = out_tex_pooled,
       replace   = TRUE)
rename_tex(out_tex_pooled)
wrap_table_float(out_tex_pooled,
  "Inorganic-contaminant MR violations following a reading at 50--100\\% of the MCL (national SYR2 sample)",
  label = "tab:mr_concentration_lag_national_ioc")
reformat_notes_tiny(out_tex_pooled)
cat(sprintf("\nPooled table saved to: %s\n", out_tex_pooled))

out_tex_arsenic <- file.path(ROOT, "output/reg/mr_concentration_lag_national_arsenic.tex")
etable(fwd_as, fwd6mon_as, past_as, past6mon_as,
       headers   = c("Arsenic MR (1-yr)", "Arsenic MR (6-mon)",
                      "Placebo: past (1-yr)", "Placebo: past (6-mon)"),
       notes     = note_arsenic,
       fitstat   = ~n,
       style.tex = style.tex("aer", adjustbox = TRUE),
       file      = out_tex_arsenic,
       replace   = TRUE)
rename_tex(out_tex_arsenic)
wrap_table_float(out_tex_arsenic,
  "Arsenic MR violations following a reading at 50--100\\% of the MCL (national SYR2 sample)",
  label = "tab:mr_concentration_lag_national_arsenic")
reformat_notes_tiny(out_tex_arsenic)
cat(sprintf("Arsenic table saved to: %s\n", out_tex_arsenic))

# ── Step 6: verification ────────────────────────────────────────────────────────
for (p in c(out_tex_pooled, out_tex_arsenic)) {
  if (file.exists(p) && file.info(p)$size > 0) {
    cat(sprintf("Output verified: %s exists and is non-zero.\n", p))
  } else {
    cat(sprintf("[ERROR] %s missing or empty.\n", p))
  }
}
