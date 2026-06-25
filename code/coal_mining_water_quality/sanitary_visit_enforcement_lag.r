# ============================================================
# Script: sanitary_visit_enforcement_lag.r
# Purpose: Test whether sanitary visits inform enforcement (Q1: visit -> enforcement
#          in next 6/12 months) and whether MR violations trigger sanitary visits
#          (Q2: any MR violation -> visit in next 6/12 months), at the downstream
#          CWS-month level. Empirical companion to the K&S inspection-as-
#          information-channel question.
# Inputs:  clean_data/cws_data/prod_vio_sulfur.parquet
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_SITE_VISITS.csv
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.parquet
# Outputs: output/reg/sanitary_visit_to_enforcement.tex
#          output/reg/mr_to_sanitary_visit.tex
# Author: EK  Date: 2026-06-24
# ============================================================

.libPaths("Z:/ek559/RPackages")
library(arrow)
library(data.table)
library(fixest)

ROOT     <- "Z:/ek559/mining_wq"
SDWA_DIR <- "Z:/ek559/sdwa_violations/SDWA_latest_downloads"

# ── wrap_for_beamer() — copied verbatim from enforcement_chain_d12.r:451 ──────
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

# ── 0. Sample: strictly-downstream CWSs ───────────────────────────────────────
panel <- as.data.table(
  arrow::read_parquet(file.path(ROOT, "clean_data/cws_data/prod_vio_sulfur.parquet"),
    col_select = c("PWSID", "STATE_CODE", "minehuc_downstream_of_mine", "minehuc_mine")))
downstream_mask <- panel$minehuc_downstream_of_mine == 1 & panel$minehuc_mine == 0
sample_pwsids   <- unique(panel$PWSID[downstream_mask])
cat("Downstream CWSs in sample:", length(sample_pwsids), "\n")

month_idx_of <- function(d) {
  yr <- as.integer(format(d, "%Y"))
  mo <- as.integer(format(d, "%m"))
  (yr - 1985L) * 12L + (mo - 1L) + 1L
}

# ── 1. Site visits ─────────────────────────────────────────────────────────────
sv <- fread(file.path(SDWA_DIR, "SDWA_SITE_VISITS.csv"),
  select = c("PWSID", "VISIT_DATE", "VISIT_REASON_CODE"),
  colClasses = list(character = "PWSID"), na.strings = c("", "NA"), showProgress = FALSE)
sv <- sv[PWSID %in% sample_pwsids]
sv[, visit_dt := as.Date(VISIT_DATE, "%m/%d/%Y")]
sv <- sv[!is.na(visit_dt)]
sv[, yr := as.integer(format(visit_dt, "%Y"))]
sv <- sv[yr >= 1985 & yr <= 2005]
sv[, month_idx := month_idx_of(visit_dt)]

san_reasons <- c("SNSV", "SNSP", "SSVF")
enf_reasons <- c("FENF", "IENF")
sv[, is_san := VISIT_REASON_CODE %in% san_reasons]
sv[, is_any := !(VISIT_REASON_CODE %in% enf_reasons)]

visit_pm <- sv[, .(visit_san = as.integer(any(is_san)),
                    visit_any = as.integer(any(is_any))),
               by = .(PWSID, month_idx)]
cat("Site-visit PWSID-months:", nrow(visit_pm),
    "| visit_san=1:", sum(visit_pm$visit_san),
    "| visit_any=1:", sum(visit_pm$visit_any), "\n")

# ── 2. Violations/enforcement parquet ─────────────────────────────────────────
ve <- as.data.table(arrow::read_parquet(
  file.path(SDWA_DIR, "SDWA_VIOLATIONS_ENFORCEMENT.parquet"),
  col_select = c("PWSID", "VIOLATION_ID", "ENFORCEMENT_ID",
                 "NON_COMPL_PER_BEGIN_DATE", "VIOLATION_CATEGORY_CODE", "RULE_CODE",
                 "ENFORCEMENT_DATE", "ENF_ACTION_CATEGORY")))
ve <- ve[PWSID %in% sample_pwsids]

# Enforcement events (Q1 outcome) — dedupe on ENFORCEMENT_ID, date = ENFORCEMENT_DATE
enf <- ve[!is.na(ENFORCEMENT_ID) & !is.na(ENFORCEMENT_DATE)]
enf[, enf_dt := as.Date(ENFORCEMENT_DATE, "%m/%d/%Y")]
enf <- enf[!is.na(enf_dt)]
enf[, enf_yr := as.integer(format(enf_dt, "%Y"))]
enf <- enf[enf_yr >= 1985 & enf_yr <= 2005]
enf <- unique(enf[, .(PWSID, ENFORCEMENT_ID, enf_dt, ENF_ACTION_CATEGORY)])
enf[, month_idx := month_idx_of(enf_dt)]

enf_pm <- enf[, .(
  enf_informal = as.integer(any(ENF_ACTION_CATEGORY == "Informal",  na.rm = TRUE)),
  enf_resolving= as.integer(any(ENF_ACTION_CATEGORY == "Resolving", na.rm = TRUE)),
  enf_formal   = as.integer(any(ENF_ACTION_CATEGORY == "Formal",    na.rm = TRUE))
), by = .(PWSID, month_idx)]
enf_pm[, enf_any := as.integer(enf_informal == 1 | enf_resolving == 1 | enf_formal == 1)]
cat("Enforcement PWSID-months:", nrow(enf_pm),
    "| informal:", sum(enf_pm$enf_informal),
    "| resolving:", sum(enf_pm$enf_resolving),
    "| formal:", sum(enf_pm$enf_formal),
    "| any:", sum(enf_pm$enf_any), "\n")

# MR begin event (Q2 regressor) — any MR violation, dedupe on VIOLATION_ID,
# date = NON_COMPL_PER_BEGIN_DATE
mr <- ve[VIOLATION_CATEGORY_CODE == "MR"]
mr[, begin_dt := as.Date(NON_COMPL_PER_BEGIN_DATE, "%m/%d/%Y")]
mr <- mr[!is.na(begin_dt)]
mr[, mr_yr := as.integer(format(begin_dt, "%Y"))]
mr <- mr[mr_yr >= 1985 & mr_yr <= 2005]
mr <- unique(mr[, .(PWSID, VIOLATION_ID, begin_dt)])
mr[, month_idx := month_idx_of(begin_dt)]

mr_pm <- mr[, .(mr_any = 1L), by = .(PWSID, month_idx)]
cat("MR-begin PWSID-months:", nrow(mr_pm),
    "(", uniqueN(mr$PWSID), "CWSs )\n")

# ── 3. Monthly skeleton: full cross of sample PWSID x months 1985-01..2005-12 ─
n_months <- month_idx_of(as.Date("2005-12-01"))
skel <- CJ(PWSID = sample_pwsids, month_idx = seq_len(n_months))

skel <- merge(skel, visit_pm, by = c("PWSID", "month_idx"), all.x = TRUE)
skel <- merge(skel, enf_pm,   by = c("PWSID", "month_idx"), all.x = TRUE)
skel <- merge(skel, mr_pm, by = c("PWSID", "month_idx"), all.x = TRUE)

fill_cols <- c("visit_san", "visit_any", "enf_informal", "enf_resolving",
               "enf_formal", "enf_any", "mr_any")
for (cl in fill_cols) skel[is.na(get(cl)), (cl) := 0L]

setorder(skel, PWSID, month_idx)
cat("\nFull monthly panel: ", nrow(skel), " PWSID-months (",
    length(sample_pwsids), " CWSs x ", n_months, " months)\n", sep = "")

# ── 4. Forward-window outcomes via frollsum on the lead of each event vector ──
build_forward <- function(dt, col, h) {
  out_name <- paste0(col, "_next", h)
  dt[, (out_name) := {
    lead_event <- shift(get(col), n = -1, fill = 0L)
    roll <- frollsum(lead_event, n = h, align = "left", fill = NA)
    as.integer(roll > 0)
  }, by = PWSID]
  invisible(dt)
}

event_cols <- c("enf_informal", "enf_resolving", "enf_formal", "enf_any",
                "visit_san", "visit_any")
for (cl in event_cols) {
  build_forward(skel, cl, 6)
  build_forward(skel, cl, 12)
}

# ── 5. Right-censoring trim (per horizon, applied at regression time) ────────
max_origin_6  <- month_idx_of(as.Date("2005-06-01"))
max_origin_12 <- month_idx_of(as.Date("2004-12-01"))

reg6  <- skel[month_idx <= max_origin_6]
reg12 <- skel[month_idx <= max_origin_12]
cat("Q1/Q2 regression N (h=6): ", nrow(reg6),  "\n", sep = "")
cat("Q1/Q2 regression N (h=12):", nrow(reg12), "\n", sep = "")

base_rate <- function(dt, col) round(100 * mean(dt[[col]], na.rm = TRUE), 2)

# ── 6. Q1 regressions: visit_t -> enforcement_{t+1..t+h} ─────────────────────
enf_labels <- c(enf_informal = "Informal", enf_resolving = "Resolving",
                enf_formal = "Formal", enf_any = "Any")

q1_models <- list()
for (vdef in c("visit_san", "visit_any")) {
  for (ecat in names(enf_labels)) {
    for (h in c(6, 12)) {
      dt   <- if (h == 6) reg6 else reg12
      yvar <- paste0(ecat, "_next", h)
      fml  <- as.formula(paste0(yvar, " ~ ", vdef, " | PWSID + month_idx"))
      key  <- paste0(vdef, "__", ecat, "__h", h)
      q1_models[[key]] <- feols(fml, data = dt, cluster = ~PWSID)
    }
  }
}

# ── 7. Q2 regressions: mr_any_t -> visit_{t+1..t+h} ───────────────────────────
q2_models <- list()
for (vdef in c("visit_san", "visit_any")) {
  for (h in c(6, 12)) {
    dt   <- if (h == 6) reg6 else reg12
    yvar <- paste0(vdef, "_next", h)
    fml  <- as.formula(paste0(yvar, " ~ mr_any | PWSID + month_idx"))
    key  <- paste0(vdef, "__h", h)
    q2_models[[key]] <- feols(fml, data = dt, cluster = ~PWSID)
  }
}

# ── 8. Output: Q1 table (two panels — visit_san, visit_any) ─────────────────
dict <- c(visit_san = "Sanitary visit (t)", visit_any = "Any non-enforcement visit (t)",
          mr_any = "MR violation begins (t)")

q1_panel_a <- q1_models[grep("^visit_san__", names(q1_models))]
q1_panel_b <- q1_models[grep("^visit_any__", names(q1_models))]
col_order  <- as.vector(outer(names(enf_labels), c(6, 12),
                               function(e, h) paste0("visit_san__", e, "__h", h)))
q1_panel_a <- q1_panel_a[col_order]
col_order_b <- sub("^visit_san__", "visit_any__", col_order)
q1_panel_b <- q1_panel_b[col_order_b]

# headers/base-rates must follow the same h-major, category-minor order as
# col_order (outer() flattens column-major: all categories for h=6, then h=12)
ecat_order <- rep(names(enf_labels), 2)
h_order    <- rep(c(6, 12), each = 4)
headers_q1 <- paste0(rep(enf_labels, 2), " (", h_order, "mo)")
base_rates_a <- mapply(function(e, h) base_rate(if (h == 6) reg6 else reg12,
                                                 paste0(e, "_next", h)),
                        ecat_order, h_order)

# fixest::etable() has no "append" mode for stacking two model sets into one
# file, so each panel's tabular is rendered separately (tex=TRUE, no file=)
# and the two are stacked by hand inside one \table environment.
ta_q1 <- etable(q1_panel_a, headers = list("Outcome: enforcement in next h months" = headers_q1),
                 dict = dict, tex = TRUE)
tb_q1 <- etable(q1_panel_b, headers = list("Outcome: enforcement in next h months" = headers_q1),
                 dict = dict, tex = TRUE)

notes_q1 <- paste0("Sample: strictly downstream CWSs (", length(sample_pwsids),
                    "), PWSID-months 1985-01 to 2005-12. Panel A regressor is ",
                    "visit\\_san (sanitary survey: SNSV/SNSP/SSVF); Panel B regressor is ",
                    "visit\\_any (any visit reason except FENF/IENF). Base rates (\\%) of the ",
                    "next-h-month outcome: ",
                    paste(sprintf("%s = %s", headers_q1, as.vector(base_rates_a)), collapse = "; "),
                    ". LPM with PWSID and calendar-month fixed effects; SEs clustered by PWSID.")

out_q1 <- file.path(ROOT, "output/reg/sanitary_visit_to_enforcement.tex")
lines_q1 <- c(
  "\\begin{table}[htbp]",
  "\\centering",
  "\\caption{Sanitary Visits and Subsequent Enforcement (Downstream CWSs, 1985--2005)}",
  "\\label{tab:visit_to_enf}",
  "\\textbf{Panel A: Sanitary Visit (\\texttt{visit\\_san})}\\\\[4pt]",
  as.character(ta_q1),
  "\\vspace{8pt}",
  "\\textbf{Panel B: Any Non-Enforcement Visit (\\texttt{visit\\_any})}\\\\[4pt]",
  as.character(tb_q1),
  "\\begin{minipage}{\\linewidth}",
  "\\vspace{4pt}",
  "\\footnotesize",
  paste0("\\textit{Notes:} ", notes_q1),
  "\\end{minipage}",
  "\\end{table}"
)
writeLines(lines_q1, out_q1)
wrap_for_beamer(out_q1)
cat("\nWrote:", out_q1, "\n")

# ── 9. Output: Q2 table (san@6, san@12, anyvisit@6, anyvisit@12) ─────────────
q2_col_order <- c("visit_san__h6", "visit_san__h12", "visit_any__h6", "visit_any__h12")
q2_ordered   <- q2_models[q2_col_order]
headers_q2   <- c("Sanitary visit (6mo)", "Sanitary visit (12mo)",
                   "Any visit (6mo)", "Any visit (12mo)")
base_rates_q2 <- c(base_rate(reg6, "visit_san_next6"), base_rate(reg12, "visit_san_next12"),
                    base_rate(reg6, "visit_any_next6"), base_rate(reg12, "visit_any_next12"))

out_q2 <- file.path(ROOT, "output/reg/mr_to_sanitary_visit.tex")
etable(q2_ordered,
       headers = list("Outcome: site visit in next h months" = headers_q2),
       dict = dict,
       title = "MR Violations and Subsequent Sanitary Visits",
       label = "tab:mr_to_visit",
       notes = paste0("Sample: strictly downstream CWSs (", length(sample_pwsids),
                       "), PWSID-months 1985-01 to 2005-12. Regressor is any MR violation ",
                       "(VIOLATION_CATEGORY_CODE=MR, any rule code) beginning in month t. ",
                       "Base rates (\\%) of the next-h-month outcome: ",
                       paste(sprintf("%s = %s", headers_q2, base_rates_q2), collapse = "; "),
                       ". LPM with PWSID and calendar-month fixed effects; SEs clustered by PWSID."),
       tex = TRUE, file = out_q2, replace = TRUE)
wrap_for_beamer(out_q2)
cat("Wrote:", out_q2, "\n")

# ── 10. Verification ──────────────────────────────────────────────────────────
stopifnot(file.exists(out_q1), file.exists(out_q2))
stopifnot(file.info(out_q1)$size > 0, file.info(out_q2)$size > 0)
cat("\nOutput verified: both .tex files exist and are non-zero.\n")
cat("=== DONE ===\n")
