# ============================================================
# Script: mr_concentration_lag.r
# Purpose: Test whether MR (monitoring/reporting) violations rise
#          after a CWS observes a high contaminant concentration
#          (regulator-pivot / strategic avoidance mechanism), using
#          the measurement-level downstream-only SYR2 sample built
#          by build_mr_concentration_lag.py.
#          Specs: (A) arsenic 1-yr, (B) arsenic 6-mon, (C) nitrate
#          1-yr, (D) nitrate 6-mon -- same-contaminant MR violation
#          in forward window; (E) pooled IOC -- MR violation under
#          RULE_CODE==333.0 1-365 days after.
#          Arsenic/nitrate include mean_concentration (PWSID-YEAR
#          mean VALUE) alongside ratio and near_mcl.
#          Pooled IOC adds separate ratio/near_mcl for selenium,
#          barium, and chromium (PWSID-YEAR means from build script).
#          Forward-window table + past-window placebo table.
# Inputs:  clean_data/mr_concentration_lag_measurement.parquet
# Outputs: output/reg/mr_concentration_lag.tex
#          output/reg/mr_concentration_lag_placebo.tex
# Author: EK  Date: 2026-06-23  Updated: 2026-07-01
# ============================================================

.libPaths("Z:/ek559/RPackages")
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
cat("Chemicals present:\n")
print(table(df$CHEMID_name))

ars_df  <- df[df$contaminant_code == "1005", ]
nit_df  <- df[df$contaminant_code == "1040", ]
pool_df <- df

# mean_concentration = PWSID-YEAR mean VALUE for that contaminant.
# Differs from ratio * MCL only for PWSID-YEARs with >1 measurement;
# for single-measurement cells it is proportional to ratio (both capture the
# same reading, only the scale differs). feols will note collinearity there.
ars_df$mean_concentration <- ave(ars_df$VALUE, ars_df$PWSID, ars_df$YEAR, FUN = mean)
nit_df$mean_concentration <- ave(nit_df$VALUE, nit_df$PWSID, nit_df$YEAR, FUN = mean)

# Z-score within each contaminant so coefficients are comparable across chemicals
ars_df$mean_conc_z <- scale(ars_df$mean_concentration)[, 1]
nit_df$mean_conc_z <- scale(nit_df$mean_concentration)[, 1]

cat(sprintf("\nArsenic (1005) subset N = %d\n", nrow(ars_df)))
cat(sprintf("Nitrate (1040) subset N = %d\n", nrow(nit_df)))
cat(sprintf("Pooled subset N = %d\n", nrow(pool_df)))

# ── Step 2: Named formulas ────────────────────────────────────────────────────
fml_ars      <- mr_same_fwd     ~ near_mcl + mean_conc_z | PWSID + YEAR
fml_ars_6mon <- mr_same_fwd6mon ~ near_mcl + mean_conc_z | PWSID + YEAR
fml_nit      <- mr_same_fwd     ~ near_mcl + mean_conc_z | PWSID + YEAR
fml_nit_6mon <- mr_same_fwd6mon ~ near_mcl + mean_conc_z | PWSID + YEAR

fml_pool      <- mr_anyioc_fwd    ~ ratio + near_mcl | PWSID + YEAR + contaminant_code
fml_pool_6mon <- mr_anyioc_fwd6mon ~ ratio + near_mcl | PWSID + YEAR + contaminant_code

fml_ars_placebo        <- mr_same_past     ~ near_mcl + mean_conc_z | PWSID + YEAR
fml_ars_6mon_placebo   <- mr_same_past6mon ~ near_mcl + mean_conc_z | PWSID + YEAR
fml_nit_placebo        <- mr_same_past     ~ near_mcl + mean_conc_z | PWSID + YEAR
fml_nit_6mon_placebo   <- mr_same_past6mon ~ near_mcl + mean_conc_z | PWSID + YEAR
fml_pool_placebo       <- mr_anyioc_past    ~ ratio + near_mcl | PWSID + YEAR + contaminant_code
fml_pool_6mon_placebo  <- mr_anyioc_past6mon ~ ratio + near_mcl | PWSID + YEAR + contaminant_code

have_ars <- nrow(ars_df) > 0
if (!have_ars) {
  cat("\n[NOTE] Arsenic subset is empty (N=0) -- arsenic columns omitted from both tables.\n")
}

# ── Step 3: Forward-window regressions ────────────────────────────────────────
nit      <- feols(fml_nit,      data = nit_df,  cluster = ~PWSID)
nit_6mon <- feols(fml_nit_6mon, data = nit_df,  cluster = ~PWSID)
pool     <- feols(fml_pool,     data = pool_df, cluster = ~PWSID)
pool_6mon <- feols(fml_pool_6mon, data = pool_df, cluster = ~PWSID)

cat("\n--- (C) Nitrate 1-yr, forward window ---\n");          print(summary(nit))
cat("\n--- (D) Nitrate 6-mon, forward window ---\n");         print(summary(nit_6mon))
cat("\n--- (E) Pooled any-IOC 1-yr, forward window ---\n");   print(summary(pool))
cat("\n--- (F) Pooled any-IOC 6-mon, forward window ---\n");  print(summary(pool_6mon))

if (have_ars) {
  ars      <- feols(fml_ars,      data = ars_df, cluster = ~PWSID)
  ars_6mon <- feols(fml_ars_6mon, data = ars_df, cluster = ~PWSID)
  cat("\n--- (A) Arsenic 1-yr, forward window ---\n");  print(summary(ars))
  cat("\n--- (B) Arsenic 6-mon, forward window ---\n"); print(summary(ars_6mon))
}

# ── Step 4: Past-window placebo regressions ───────────────────────────────────
nit_p        <- feols(fml_nit_placebo,       data = nit_df,  cluster = ~PWSID)
nit_6mon_p   <- feols(fml_nit_6mon_placebo,  data = nit_df,  cluster = ~PWSID)
pool_p       <- feols(fml_pool_placebo,      data = pool_df, cluster = ~PWSID)
pool_6mon_p  <- feols(fml_pool_6mon_placebo, data = pool_df, cluster = ~PWSID)

cat("\n--- (C) Nitrate 1-yr, past-window placebo ---\n");          print(summary(nit_p))
cat("\n--- (D) Nitrate 6-mon, past-window placebo ---\n");         print(summary(nit_6mon_p))
cat("\n--- (E) Pooled any-IOC 1-yr, past-window placebo ---\n");   print(summary(pool_p))
cat("\n--- (F) Pooled any-IOC 6-mon, past-window placebo ---\n");  print(summary(pool_6mon_p))

if (have_ars) {
  ars_p      <- feols(fml_ars_placebo,      data = ars_df, cluster = ~PWSID)
  ars_6mon_p <- feols(fml_ars_6mon_placebo, data = ars_df, cluster = ~PWSID)
  cat("\n--- (A) Arsenic 1-yr, past-window placebo ---\n");  print(summary(ars_p))
  cat("\n--- (B) Arsenic 6-mon, past-window placebo ---\n"); print(summary(ars_6mon_p))
}

# ── Step 5: wrap_for_beamer (copied from enforcement_chain_d12.r) ────────────
wrap_for_beamer <- function(path, beamer_height = "0.78\\textheight") {
  header <- c(
    "\\makeatletter",
    paste0("\\@ifclassloaded{beamer}{%\n",
           "  \\begin{adjustbox}{max width=\\linewidth,",
           " max totalheight=", beamer_height, ", center}%\n",
           "}{%\n",
           "  \\begin{adjustbox}{max width=\\linewidth, center}%\n",
           "}%"),
    "\\makeatother"
  )
  lines <- readLines(path)
  note_start  <- grep("^\\\\par \\\\raggedright\\s*$", lines)
  endgroup_ln <- grep("^\\\\par\\\\endgroup\\s*$",     lines)
  if (length(note_start) == 1 && length(endgroup_ln) == 1 && note_start < endgroup_ln) {
    note_text <- lines[(note_start + 1):(endgroup_ln - 1)]
    body      <- c(lines[seq_len(note_start - 1)], "\\par\\endgroup")
    writeLines(c(header, body, "\\end{adjustbox}", "",
                 "\\par \\raggedright", note_text, "\\par"), path)
  } else {
    writeLines(c(header, lines, "\\end{adjustbox}"), path)
  }
}

# wrap_table_float: for style.tex("aer", adjustbox=TRUE) output — adds
# \begin{table}/\caption and moves notes outside the adjustbox. fixest 0.14
# does not auto-create the float wrapper even when title= is supplied.
wrap_table_float <- function(path, caption_text, label = NULL) {
  lines <- readLines(path)

  # Locate structural landmarks
  bg_line   <- grep("^\\\\begingroup\\s*$", lines)[1]
  eg_line   <- grep("^\\\\par\\\\endgroup\\s*$", lines)
  eg_line   <- eg_line[length(eg_line)]
  adj_start <- grep("^\\s*\\\\begin\\{adjustbox\\}", lines)[1]
  adj_end   <- grep("^\\s*\\\\end\\{adjustbox\\}", lines)
  adj_end   <- adj_end[length(adj_end)]
  tab_end   <- grep("^\\s*\\\\end\\{tabular\\}", lines)
  tab_end   <- tab_end[length(tab_end)]

  # Notes sit between \end{tabular} and \end{adjustbox}
  note_lines <- trimws(lines[(tab_end + 1):(adj_end - 1)])
  note_lines <- note_lines[note_lines != ""]

  # Float header
  cap_line <- if (!is.null(label)) {
    sprintf("\\caption{%s}\\label{%s}", caption_text, label)
  } else {
    sprintf("\\caption{%s}", caption_text)
  }

  new_body <- c(
    "\\begin{table}[htbp]",
    cap_line,
    "\\centering",
    lines[adj_start],                          # \begin{adjustbox}{...}
    lines[(adj_start + 1):tab_end],            # tabular content
    "\\end{adjustbox}",
    "",
    note_lines,                                # already contains \par \raggedright + notes
    "\\par",
    "\\end{table}"
  )

  before <- if (bg_line > 1) lines[seq_len(bg_line - 1)] else character(0)
  after  <- if (eg_line < length(lines)) lines[(eg_line + 1):length(lines)] else character(0)
  writeLines(c(before, new_body, after), path)
}

# ── Step 6: LaTeX tables ──────────────────────────────────────────────────────
dir.create(file.path(ROOT, "output/reg"), showWarnings = FALSE, recursive = TRUE)

# post-process: rename variables in .tex after etable output
rename_tex <- function(path) {
  txt <- paste(readLines(path), collapse = "\n")
  subs <- list(
    c("near\\_mcl",           "Concen. $>$ 50\\% MCL"),
    c("mean\\_conc\\_z",      "Mean concen. (z-score)"),
    # fixed-effect labels
    c("PWSID fixed-effects",   "CWS fixed-effects"),
    c("PWSID fixed effects",   "CWS fixed effects"),
    c("contaminant\\_code fixed-effects", "Contaminant fixed-effects"),
    c("contaminant\\_code fixed effects", "Contaminant fixed effects"),
    # SE footer
    c("Clustered \\(PWSID\\) standard-errors in parentheses",
      "Clustered (CWS) standard-errors in parentheses"),
    # dep var cells (appear as empty cell after dict maps them to "")
    c("mr\\_same\\_fwd6mon",   ""),
    c("mr\\_same\\_fwd",       ""),
    c("mr\\_anyioc\\_fwd6mon", ""),
    c("mr\\_anyioc\\_fwd",     ""),
    c("mr\\_same\\_past6mon",  ""),
    c("mr\\_same\\_past",      ""),
    c("mr\\_anyioc\\_past6mon",""),
    c("mr\\_anyioc\\_past",    "")
  )
  for (s in subs) txt <- gsub(s[[1]], s[[2]], txt, fixed = TRUE)
  # "ratio" as a standalone row label — word-boundary match to avoid hitting "concentration"
  txt <- gsub("(?<![a-zA-Z])ratio(?![a-zA-Z])", "Concen./MCL", txt, perl = TRUE)
  # Remove the "Dependent Variables:" header row entirely
  # Row looks like: "   Dependent Variables: & ... \\\\"
  txt <- gsub("[ \t]*Dependent Variables:.*?\\\\\\\\\n", "", txt)
  # Remove a blank dep-var row (all cells empty, produced by "" substitution)
  # Pattern: "   & & & & & \\\\" (6 cells, all blank)
  txt <- gsub("\n[ \t]*&[ \t]*&[ \t]*&[ \t]*&[ \t]*&[ \t]*&[ \t]*\\\\\\\\", "", txt)
  writeLines(strsplit(txt, "\n")[[1]], path)
}

# post-process: wrap table notes in tiny font (matching monitoring_retesting_hazard.tex style)
reformat_notes_tiny <- function(path) {
  lines <- readLines(path)
  adj_end   <- grep("^\\s*\\\\end\\{adjustbox\\}\\s*$", lines)
  end_table <- grep("^\\\\end\\{table\\}\\s*$", lines)
  if (length(adj_end) == 0 || length(end_table) == 0) return(invisible(NULL))
  adj_end   <- adj_end[length(adj_end)]
  end_table <- end_table[length(end_table)]
  note_raw  <- lines[(adj_end + 1):(end_table - 1)]
  # Drop structural-only lines: blank, \par, \par\raggedright, \par\endgroup
  drop_pat  <- "^\\s*(\\\\par(\\\\endgroup|\\s*(\\\\raggedright)?)?|\\\\begingroup|\\\\raggedright)?\\s*$"
  note_text <- paste(trimws(note_raw[!grepl(drop_pat, note_raw)]), collapse = " ")
  new_lines <- c(
    lines[1:adj_end],
    sprintf("{\\tiny\\linespread{1}\\selectfont \\par \\raggedright %s}", note_text),
    "\\end{table}"
  )
  writeLines(new_lines, path)
}

main_models  <- if (have_ars) list(ars, ars_6mon, nit, nit_6mon, pool, pool_6mon) else list(nit, nit_6mon, pool, pool_6mon)
main_headers <- if (have_ars) {
  c("Arsenic MR (1-yr)", "Arsenic MR (6-mon)", "Nitrate MR (1-yr)", "Nitrate MR (6-mon)",
    "Pooled IOC (1-yr)", "Pooled IOC (6-mon)")
} else {
  c("Nitrate MR (1-yr)", "Nitrate MR (6-mon)", "Pooled IOC (1-yr)", "Pooled IOC (6-mon)")
}

note_main <- paste0(
  "SYR2 only (1998--2005). Outcome: same-contaminant MR violation within the year following ",
  "the contaminant reading or the 6 months following the contaminant reading. ",
  "Pooled IOC MR violations exclude arsenic and nitrate, which have their own rule codes. ",
  "Mean concentration z-scored within chemical. ",
  "*** p$<$0.01, ** p$<$0.05, * p$<$0.1. SEs clustered at the CWS level."
)

out_tex <- file.path(ROOT, "output/reg/mr_concentration_lag.tex")
# Direct etable() calls avoid a fixest 0.14.0/R 4.5.2 do.call incompatibility
# (||/vector coercion bug triggered only via do.call with >=6 model args).
if (have_ars) {
  etable(ars, ars_6mon, nit, nit_6mon, pool, pool_6mon,
         headers   = main_headers,
         notes     = note_main,
         fitstat   = ~n,
         style.tex = style.tex("aer", adjustbox = TRUE),
         file      = out_tex,
         replace   = TRUE)
} else {
  etable(nit, nit_6mon, pool, pool_6mon,
         headers   = main_headers,
         notes     = note_main,
         fitstat   = ~n,
         style.tex = style.tex("aer", adjustbox = TRUE),
         file      = out_tex,
         replace   = TRUE)
}
rename_tex(out_tex)
wrap_table_float(out_tex,
  "Monitoring and Reporting (MR) violations following contaminant concentration readings",
  label = "tab:mr_concentration_lag")
reformat_notes_tiny(out_tex)
cat(sprintf("\nTable saved to: %s\n", out_tex))

note_placebo <- paste0(
  "Past-window placebo: same specifications as the forward-window table but outcome is ",
  "an MR violation occurring BEFORE the sample date (1--365 days before for 1-yr columns; ",
  "1--182 days before for 6-mon columns). ",
  "*** p$<$0.01, ** p$<$0.05, * p$<$0.1. SEs clustered at the CWS level."
)
out_tex_placebo <- file.path(ROOT, "output/reg/mr_concentration_lag_placebo.tex")
if (have_ars) {
  etable(ars_p, ars_6mon_p, nit_p, nit_6mon_p, pool_p, pool_6mon_p,
         headers   = main_headers,
         notes     = note_placebo,
         fitstat   = ~n,
         style.tex = style.tex("aer", adjustbox = TRUE),
         file      = out_tex_placebo,
         replace   = TRUE)
} else {
  etable(nit_p, nit_6mon_p, pool_p, pool_6mon_p,
         headers   = main_headers,
         notes     = note_placebo,
         fitstat   = ~n,
         style.tex = style.tex("aer", adjustbox = TRUE),
         file      = out_tex_placebo,
         replace   = TRUE)
}
rename_tex(out_tex_placebo)
wrap_table_float(out_tex_placebo,
  "Placebo: MR Violations Preceding High Contaminant Concentration (Past Window)",
  label = "tab:mr_concentration_lag_placebo")
reformat_notes_tiny(out_tex_placebo)
cat(sprintf("Placebo table saved to: %s\n", out_tex_placebo))

for (p in c(out_tex, out_tex_placebo)) {
  if (file.exists(p) && file.info(p)$size > 0) {
    cat(sprintf("Output verified: %s exists and is non-zero.\n", p))
  } else {
    cat(sprintf("[ERROR] %s missing or empty.\n", p))
  }
}

# ── Step 7: TEST — ratio (VALUE/MCL) version for arsenic and nitrate ──────────
# Replace mean_concentration with ratio (reading as % of MCL).
# Collinearity check: ratio = VALUE/MCL is a linear transform of VALUE;
# mean_concentration = PWSID-YEAR mean VALUE. With multiple readings per cell
# they differ, but we let feols flag any aliasing. If collinear, feols drops
# one silently — we detect this and move to ratio-only spec.

cat("\n\n==== RATIO TEST (mr_concentration_lag_ratio.tex) ====\n")

check_collinear <- function(fit, drop_var = "mean_concentration") {
  # Returns TRUE if drop_var was aliased/dropped by feols
  aliased <- tryCatch(fit$aliased, error = function(e) NULL)
  if (!is.null(aliased) && drop_var %in% names(aliased) && aliased[[drop_var]]) return(TRUE)
  # Also check: coefficient is NA
  coefs <- coef(fit)
  if (drop_var %in% names(coefs) && is.na(coefs[[drop_var]])) return(TRUE)
  # Check if variable simply absent from coefs (dropped silently)
  if (!drop_var %in% names(coefs)) return(TRUE)
  return(FALSE)
}

# --- Arsenic ---
if (have_ars) {
  ars_ratio_test <- feols(mr_same_fwd ~ ratio + near_mcl + mean_concentration | PWSID + YEAR,
                          data = ars_df, cluster = ~PWSID)
  cat("\n--- Arsenic 1-yr: ratio + near_mcl + mean_concentration ---\n")
  print(summary(ars_ratio_test))

  if (check_collinear(ars_ratio_test)) {
    cat("[COLLINEAR] mean_concentration dropped for arsenic -- using ratio + near_mcl only.\n")
    fml_ars_ratio      <- mr_same_fwd     ~ ratio + near_mcl | PWSID + YEAR
    fml_ars_6mon_ratio <- mr_same_fwd6mon ~ ratio + near_mcl | PWSID + YEAR
    fml_ars_ratio_p    <- mr_same_past     ~ ratio + near_mcl | PWSID + YEAR
    fml_ars_6mon_ratio_p <- mr_same_past6mon ~ ratio + near_mcl | PWSID + YEAR
  } else {
    cat("[NOT collinear] Keeping ratio + near_mcl + mean_concentration for arsenic.\n")
    fml_ars_ratio      <- mr_same_fwd     ~ ratio + near_mcl + mean_concentration | PWSID + YEAR
    fml_ars_6mon_ratio <- mr_same_fwd6mon ~ ratio + near_mcl + mean_concentration | PWSID + YEAR
    fml_ars_ratio_p    <- mr_same_past     ~ ratio + near_mcl + mean_concentration | PWSID + YEAR
    fml_ars_6mon_ratio_p <- mr_same_past6mon ~ ratio + near_mcl + mean_concentration | PWSID + YEAR
  }

  ars_r      <- feols(fml_ars_ratio,      data = ars_df, cluster = ~PWSID)
  ars_6mon_r <- feols(fml_ars_6mon_ratio, data = ars_df, cluster = ~PWSID)
  ars_r_p    <- feols(fml_ars_ratio_p,    data = ars_df, cluster = ~PWSID)
  ars_6mon_r_p <- feols(fml_ars_6mon_ratio_p, data = ars_df, cluster = ~PWSID)
  cat("\n--- (A) Arsenic 1-yr ratio spec ---\n");     print(summary(ars_r))
  cat("\n--- (B) Arsenic 6-mon ratio spec ---\n");    print(summary(ars_6mon_r))
}

# --- Nitrate ---
nit_ratio_test <- feols(mr_same_fwd ~ ratio + near_mcl + mean_concentration | PWSID + YEAR,
                        data = nit_df, cluster = ~PWSID)
cat("\n--- Nitrate 1-yr: ratio + near_mcl + mean_concentration ---\n")
print(summary(nit_ratio_test))

if (check_collinear(nit_ratio_test)) {
  cat("[COLLINEAR] mean_concentration dropped for nitrate -- using ratio + near_mcl only.\n")
  fml_nit_ratio      <- mr_same_fwd     ~ ratio + near_mcl | PWSID + YEAR
  fml_nit_6mon_ratio <- mr_same_fwd6mon ~ ratio + near_mcl | PWSID + YEAR
  fml_nit_ratio_p    <- mr_same_past     ~ ratio + near_mcl | PWSID + YEAR
  fml_nit_6mon_ratio_p <- mr_same_past6mon ~ ratio + near_mcl | PWSID + YEAR
} else {
  cat("[NOT collinear] Keeping ratio + near_mcl + mean_concentration for nitrate.\n")
  fml_nit_ratio      <- mr_same_fwd     ~ ratio + near_mcl + mean_concentration | PWSID + YEAR
  fml_nit_6mon_ratio <- mr_same_fwd6mon ~ ratio + near_mcl + mean_concentration | PWSID + YEAR
  fml_nit_ratio_p    <- mr_same_past     ~ ratio + near_mcl + mean_concentration | PWSID + YEAR
  fml_nit_6mon_ratio_p <- mr_same_past6mon ~ ratio + near_mcl + mean_concentration | PWSID + YEAR
}

nit_r      <- feols(fml_nit_ratio,      data = nit_df, cluster = ~PWSID)
nit_6mon_r <- feols(fml_nit_6mon_ratio, data = nit_df, cluster = ~PWSID)
nit_r_p    <- feols(fml_nit_ratio_p,    data = nit_df, cluster = ~PWSID)
nit_6mon_r_p <- feols(fml_nit_6mon_ratio_p, data = nit_df, cluster = ~PWSID)
cat("\n--- (C) Nitrate 1-yr ratio spec ---\n");   print(summary(nit_r))
cat("\n--- (D) Nitrate 6-mon ratio spec ---\n");  print(summary(nit_6mon_r))

# Pooled column unchanged (already uses ratio)
pool_r   <- pool
pool_r_p <- pool_p

# ── Build and save ratio table + placebo ──────────────────────────────────────
out_tex_ratio <- file.path(ROOT, "output/reg/mr_concentration_lag_ratio.tex")

ratio_main_models  <- if (have_ars) list(ars_r, ars_6mon_r, nit_r, nit_6mon_r, pool_r) else list(nit_r, nit_6mon_r, pool_r)
ratio_main_headers <- if (have_ars) {
  c("Arsenic (1-yr)", "Arsenic (6-mon)", "Nitrate (1-yr)", "Nitrate (6-mon)", "Pooled inorganic")
} else {
  c("Nitrate (1-yr)", "Nitrate (6-mon)", "Pooled inorganic")
}

note_ratio <- paste0(
  "TEST VERSION: arsenic/nitrate columns use ratio (VALUE/MCL) instead of (or alongside) ",
  "mean_concentration. Collinearity check run; mean_concentration dropped if aliased by feols. ",
  "Downstream-only mining sample (minehuc_downstream_of_mine==1 & minehuc_mine==0), ",
  "SYR2 only (1998-2005). Outcome: same-contaminant MR violation within the forward window. ",
  "ratio = VALUE/MCL (individual reading as fraction of MCL); near_mcl = reading at 50-100% of MCL. ",
  "Pooled any-IOC unchanged from main table. SEs clustered at the CWS (PWSID) level."
)

do.call(etable, c(ratio_main_models,
       list(title   = "TEST: MR Violations Following High Concentration — ratio (VALUE/MCL) Spec",
            headers = ratio_main_headers,
            notes   = note_ratio,
            fitstat = ~r2 + n,
            file    = out_tex_ratio,
            replace = TRUE)))
wrap_for_beamer(out_tex_ratio)
cat(sprintf("\nRatio test table saved to: %s\n", out_tex_ratio))

out_tex_ratio_placebo <- file.path(ROOT, "output/reg/mr_concentration_lag_ratio_placebo.tex")
note_ratio_p <- paste0(
  "TEST VERSION (past-window placebo): same ratio specification as mr_concentration_lag_ratio.tex ",
  "but outcome is an MR violation BEFORE the sample date.",
  " SEs clustered at the CWS (PWSID) level."
)
ratio_placebo_models <- if (have_ars) list(ars_r_p, ars_6mon_r_p, nit_r_p, nit_6mon_r_p, pool_r_p) else list(nit_r_p, nit_6mon_r_p, pool_r_p)
do.call(etable, c(ratio_placebo_models,
       list(title   = "TEST Placebo: MR Violations Preceding High Concentration — ratio (VALUE/MCL) Spec",
            headers = ratio_main_headers,
            notes   = note_ratio_p,
            fitstat = ~r2 + n,
            file    = out_tex_ratio_placebo,
            replace = TRUE)))
wrap_for_beamer(out_tex_ratio_placebo)
cat(sprintf("Ratio placebo table saved to: %s\n", out_tex_ratio_placebo))

for (p in c(out_tex_ratio, out_tex_ratio_placebo)) {
  if (file.exists(p) && file.info(p)$size > 0) {
    cat(sprintf("Output verified: %s exists and is non-zero.\n", p))
  } else {
    cat(sprintf("[ERROR] %s missing or empty.\n", p))
  }
}
