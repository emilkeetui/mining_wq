# ============================================================
# Script: mr_concentration_lag_national_downstream_states.r
# Purpose: State-restricted variant of mr_concentration_lag_national.r.
#          Re-estimates the identical ratchet-avoidance (MR-following-
#          near-MCL-reading) specification on the national SYR2
#          nitrate sample, restricted to CWSs located in states that
#          have at least one CWS in the main downstream 2SLS sample
#          (minehuc_downstream_of_mine==1 & minehuc_mine==0, sample
#          years 1985-2005). This tightens external validity relative
#          to the fully unrestricted national sample: the mechanism is
#          tested in the same states the main mining results come from.
#          State is not present in the national nitrate parquet, so it
#          is derived from the standard SDWIS PWSID prefix (first two
#          characters = state postal code).
# Inputs:  clean_data/mr_concentration_lag_national_nitrate.parquet
# Outputs: output/reg/mr_concentration_lag_national_downstream_states.tex
# Author: EK  Date: 2026-07-14
# ============================================================

.libPaths("Z:/ek559/RPackages")
library(arrow)
library(fixest)

ROOT <- "Z:/ek559/mining_wq"
setwd(ROOT)

# ── Step 1: Load + schema check ───────────────────────────────────────────────
cat("Loading national nitrate analysis dataset...\n")
df <- read_parquet("clean_data/mr_concentration_lag_national_nitrate.parquet")
str(df)   # PWSID must be <chr>, YEAR must be <int>

cat(sprintf("\nRows: %d | unique PWSID: %d | years %d-%d\n",
            nrow(df), length(unique(df$PWSID)), min(df$YEAR), max(df$YEAR)))

# ── Step 1b: restrict to states in the main downstream 2SLS sample ────────────
# States with >=1 CWS in prod_vio_sulfur.parquet under
# minehuc_downstream_of_mine==1 & minehuc_mine==0, year 1985-2005
# (excludes one spurious STATE_CODE=="0", 1 PWSID, a data artifact).
downstream_states <- c("AL", "CA", "CO", "FL", "GA", "IL", "KS", "KY", "LA", "MD", "NC", "NJ",
                        "NY", "OH", "OR", "PA", "SC", "TN", "UT", "VA", "WA", "WV")

df$state <- substr(df$PWSID, 1, 2)
df <- df[df$state %in% downstream_states, ]

n_states_kept <- length(unique(df$state))
n_pwsid <- length(unique(df$PWSID))
cat(sprintf("\nAfter restricting to downstream-2SLS-sample states (%d states):\n",
            length(downstream_states)))
cat(sprintf("Rows: %d | unique PWSID: %d | states represented: %d\n",
            nrow(df), n_pwsid, n_states_kept))

n_near_mcl <- sum(df$near_mcl == 1, na.rm = TRUE)
n_above_mcl <- sum(df$above_mcl == 1, na.rm = TRUE)
cat(sprintf("near_mcl==1 readings: %d\n", n_near_mcl))
cat(sprintf("above_mcl==1 readings: %d\n", n_above_mcl))

# mean_concentration = PWSID-YEAR mean VALUE (matches mr_concentration_lag.r)
df$mean_concentration <- ave(df$VALUE, df$PWSID, df$YEAR, FUN = mean)
df$mean_conc_z <- scale(df$mean_concentration)[, 1]

# ── Raw-means frequency table (console only) ──────────────────────────────────
cat("\n--- Raw means: mr_same_fwd by near_mcl ---\n")
print(tapply(df$mr_same_fwd, df$near_mcl, mean, na.rm = TRUE))
cat("\n--- Raw means: mr_same_fwd6mon by near_mcl ---\n")
print(tapply(df$mr_same_fwd6mon, df$near_mcl, mean, na.rm = TRUE))
cat("\n--- Raw means: mr_same_past by near_mcl ---\n")
print(tapply(df$mr_same_past, df$near_mcl, mean, na.rm = TRUE))
cat("\n--- Raw means: mr_same_past6mon by near_mcl ---\n")
print(tapply(df$mr_same_past6mon, df$near_mcl, mean, na.rm = TRUE))

# ── Step 2: Named formulas ─────────────────────────────────────────────────────
fml_fwd       <- mr_same_fwd      ~ near_mcl + mean_conc_z | PWSID + YEAR
fml_fwd6mon   <- mr_same_fwd6mon  ~ near_mcl + mean_conc_z | PWSID + YEAR
fml_past      <- mr_same_past     ~ near_mcl + mean_conc_z | PWSID + YEAR
fml_past6mon  <- mr_same_past6mon ~ near_mcl + mean_conc_z | PWSID + YEAR

# ── Step 3: Regressions ────────────────────────────────────────────────────────
fwd      <- feols(fml_fwd,      data = df, cluster = ~PWSID)
fwd6mon  <- feols(fml_fwd6mon,  data = df, cluster = ~PWSID)
past     <- feols(fml_past,     data = df, cluster = ~PWSID)
past6mon <- feols(fml_past6mon, data = df, cluster = ~PWSID)

cat("\n--- Nitrate MR (1-yr), forward window ---\n");   print(summary(fwd))
cat("\n--- Nitrate MR (6-mon), forward window ---\n");  print(summary(fwd6mon))
cat("\n--- Placebo: past (1-yr) ---\n");                print(summary(past))
cat("\n--- Placebo: past (6-mon) ---\n");                print(summary(past6mon))

# ── Step 4: table helpers (copied verbatim from mr_concentration_lag_national.r) ─
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

# rename_tex: adapted from mr_concentration_lag.r -- blank-dep-var-row regex
# updated from 6 columns to 4 columns (4 "&" cells instead of 6).
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

# ── Step 5: LaTeX table ─────────────────────────────────────────────────────────
dir.create(file.path(ROOT, "output/reg"), showWarnings = FALSE, recursive = TRUE)

note_main <- paste0(
  "National SYR2 sample restricted to states with at least one CWS in the main downstream ",
  "2SLS sample (minehuc\\_downstream\\_of\\_mine==1 \\& minehuc\\_mine==0, 1985--2005), ",
  "nitrate only. Outcome: nitrate MR (monitoring/reporting) violation in the forward window ",
  "(1--365 days for the 1-yr column; 1--182 days for the 6-mon column) following the sample ",
  "date; placebo columns use the same windows measured BEFORE the sample date. near\\_mcl = ",
  "reading at 50--100\\% of the MCL, the 40 CFR 141.23(d)(2) quarterly-monitoring trigger. ",
  sprintf("States retained: %d. Unique PWSIDs: %d. ", n_states_kept, n_pwsid),
  sprintf("N of readings with concentration above 50 percent of the MCL: %d. ", n_near_mcl),
  "Mean concentration = PWSID-YEAR mean reading, z-scored across the sample. ",
  "*** p$<$0.01, ** p$<$0.05, * p$<$0.1. SEs clustered at the CWS (PWSID) level."
)

out_tex <- file.path(ROOT, "output/reg/mr_concentration_lag_national_downstream_states.tex")
etable(fwd, fwd6mon, past, past6mon,
       headers   = c("Nitrate MR (1-yr)", "Nitrate MR (6-mon)",
                      "Placebo: past (1-yr)", "Placebo: past (6-mon)"),
       notes     = note_main,
       fitstat   = ~n,
       style.tex = style.tex("aer", adjustbox = TRUE),
       file      = out_tex,
       replace   = TRUE)
rename_tex(out_tex)
wrap_table_float(out_tex,
  "Nitrate MR violations following a reading above 50\\% of the MCL (national sample, downstream-2SLS-sample states)",
  label = "tab:mr_concentration_lag_national_downstream_states")
reformat_notes_tiny(out_tex)
cat(sprintf("\nTable saved to: %s\n", out_tex))

if (file.exists(out_tex) && file.info(out_tex)$size > 0) {
  cat(sprintf("Output verified: %s exists and is non-zero.\n", out_tex))
} else {
  cat(sprintf("[ERROR] %s missing or empty.\n", out_tex))
}
