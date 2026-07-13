# ============================================================
# Script: sanitary_visit_formal_enforcement_rate.r
# Purpose: CWS-year rate table (strictly-downstream 2SLS panel, 1985-2005)
#          testing whether formal enforcement is less likely when an MR
#          violation is accompanied by a sanitary visit. Row 1: formal
#          enforcement rate over all CWS-years. Row 2: rate restricted to
#          CWS-years with an MR violation onset. Row 3: rate further
#          restricted to CWS-years with an MR violation onset AND a
#          sanitary visit in that same year.
#          Second table: same 3 rows as above, plus row 4 ("CWS-years with
#          an MR violation following sanitary visit" -- a sanitary visit in
#          the 365 days immediately before the MR onset) and row 5 ("CWS-years
#          with an MR violation preceding sanitary visit" -- a sanitary visit
#          in the 365 days immediately after the MR onset), each evaluated
#          against the formal-enforcement outcome in the MR onset's calendar
#          year t (tests whether the row-3 same-calendar-year result depends
#          on visit ordering relative to the onset within a 365-day window).
# Inputs:  clean_data/cws_data/prod_vio_sulfur.parquet
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.parquet
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_SITE_VISITS.csv
# Outputs: output/sum/sanitary_visit_formal_enforcement_rate.tex
#          output/sum/sanitary_visit_timing_formal_enforcement_rate.tex
# Author: EK  Date: 2026-07-13
# ============================================================

.libPaths("Z:/ek559/RPackages")
library(arrow)
library(data.table)

ROOT     <- "Z:/ek559/mining_wq"
SDWA_DIR <- "Z:/ek559/sdwa_violations/SDWA_latest_downloads"

YR_LO <- 1985L
YR_HI <- 2005L

# ── 0. Sample: strictly-downstream CWSs ───────────────────────────────────────
panel <- as.data.table(
  arrow::read_parquet(file.path(ROOT, "clean_data/cws_data/prod_vio_sulfur.parquet"),
    col_select = c("PWSID", "minehuc_downstream_of_mine", "minehuc_mine")))
downstream_mask <- panel$minehuc_downstream_of_mine == 1 & panel$minehuc_mine == 0
sample_pwsids   <- unique(panel$PWSID[downstream_mask])
cat("Downstream CWSs in sample:", length(sample_pwsids), "\n")

# ── 1. Violations + enforcement ───────────────────────────────────────────────
ve <- as.data.table(arrow::read_parquet(
  file.path(SDWA_DIR, "SDWA_VIOLATIONS_ENFORCEMENT.parquet"),
  col_select = c("PWSID", "VIOLATION_ID", "NON_COMPL_PER_BEGIN_DATE", "NON_COMPL_PER_END_DATE",
                 "VIOLATION_CATEGORY_CODE", "ENFORCEMENT_ID", "ENFORCEMENT_DATE",
                 "ENF_ACTION_CATEGORY", "CALCULATED_RTC_DATE")))
ve <- ve[PWSID %in% sample_pwsids]

# ── 1a. MR violation onsets: dedupe on VIOLATION_ID, year of onset ───────────
onsets <- unique(ve[, .(PWSID, VIOLATION_ID, NON_COMPL_PER_BEGIN_DATE, VIOLATION_CATEGORY_CODE)])
onsets[, onset_dt := as.Date(NON_COMPL_PER_BEGIN_DATE, "%m/%d/%Y")]
onsets <- onsets[!is.na(onset_dt)]
onsets[, onset_yr := as.integer(format(onset_dt, "%Y"))]
onsets <- onsets[onset_yr >= YR_LO & onset_yr <= YR_HI]

mr_onsets <- onsets[VIOLATION_CATEGORY_CODE == "MR", .(PWSID, VIOLATION_ID, onset_dt, onset_yr)]
cat("MR violation onsets (event-level):", nrow(mr_onsets), "\n")

mr_py <- unique(mr_onsets[, .(PWSID, year = onset_yr, mr_violation = 1L)])
cat("CWS-years with an MR violation onset:", nrow(mr_py), "\n")

# ── 1b. Enforcement spans -> formal enforcement, expanded to CWS-year ────────
enf <- ve[!is.na(ENFORCEMENT_ID) & !is.na(ENFORCEMENT_DATE)]
enf[, enf_dt := as.Date(ENFORCEMENT_DATE, "%m/%d/%Y")]
enf <- enf[!is.na(enf_dt)]
enf[, enf_yr := as.integer(format(enf_dt, "%Y"))]
enf <- enf[enf_yr >= YR_LO & enf_yr <= YR_HI]
enf[, rtc_dt  := as.Date(CALCULATED_RTC_DATE,    "%m/%d/%Y")]
enf[, ncpe_dt := as.Date(NON_COMPL_PER_END_DATE, "%m/%d/%Y")]
enf[, end_dt  := fifelse(!is.na(rtc_dt), rtc_dt, fifelse(!is.na(ncpe_dt), ncpe_dt, enf_dt))]
enf[, start_yr := as.integer(format(enf_dt, "%Y"))]
enf[, end_yr   := pmax(as.integer(format(end_dt, "%Y")), start_yr)]
enf <- unique(enf[, .(PWSID, ENFORCEMENT_ID, enf_dt, start_yr, end_yr, ENF_ACTION_CATEGORY)])
cat("Enforcement actions (deduped):", nrow(enf), "\n")

# Formal enforcement spell starts (event-level, retains date), for the
# timing breakdown in section 4b below.
formal_starts <- unique(enf[ENF_ACTION_CATEGORY == "Formal", .(PWSID, enf_dt)])
cat("Formal enforcement spell starts (event-level):", nrow(formal_starts), "\n")

year_lists <- Map(seq, enf$start_yr, enf$end_yr)
n_per_row  <- lengths(year_lists)
enf_long <- data.table(
  PWSID               = rep(enf$PWSID, n_per_row),
  ENF_ACTION_CATEGORY = rep(enf$ENF_ACTION_CATEGORY, n_per_row),
  year                = unlist(year_lists)
)
enf_long <- enf_long[year >= YR_LO & year <= YR_HI]

enf_formal_py <- enf_long[, .(formal_enforcement = as.integer(any(ENF_ACTION_CATEGORY == "Formal", na.rm = TRUE))),
                           by = .(PWSID, year)]
cat("CWS-years with ongoing formal enforcement:", sum(enf_formal_py$formal_enforcement), "\n")

rm(ve, enf, enf_long); gc()

# ── 2. Sanitary visits, year of visit ─────────────────────────────────────────
sv <- fread(file.path(SDWA_DIR, "SDWA_SITE_VISITS.csv"),
  select = c("PWSID", "VISIT_DATE", "VISIT_REASON_CODE"),
  colClasses = list(character = "PWSID"), na.strings = c("", "NA"), showProgress = FALSE)
sv <- sv[PWSID %in% sample_pwsids]
sv[, visit_dt := as.Date(VISIT_DATE, "%m/%d/%Y")]
sv <- sv[!is.na(visit_dt)]
sv[, yr := as.integer(format(visit_dt, "%Y"))]
sv <- sv[yr >= YR_LO & yr <= YR_HI]

san <- sv[VISIT_REASON_CODE %in% c("SNSV", "SNSP", "SSVF")]
san_events <- unique(san[, .(PWSID, visit_dt)])
cat("Sanitary visit events (event-level):", nrow(san_events), "\n")

san_py <- unique(san[, .(PWSID, year = yr)])
san_py[, sanitary_visit := 1L]
cat("CWS-years with a sanitary visit:", nrow(san_py), "\n")

rm(sv, san); gc()

# ── 3. Full CWS-year skeleton and merge ───────────────────────────────────────
skel <- CJ(PWSID = sample_pwsids, year = YR_LO:YR_HI)
skel <- merge(skel, mr_py,           by = c("PWSID", "year"), all.x = TRUE)
skel <- merge(skel, enf_formal_py,   by = c("PWSID", "year"), all.x = TRUE)
skel <- merge(skel, san_py,          by = c("PWSID", "year"), all.x = TRUE)

fill0_cols <- c("mr_violation", "formal_enforcement", "sanitary_visit")
for (cl in fill0_cols) skel[is.na(get(cl)), (cl) := 0L]

cat("\nFull CWS-year panel:", nrow(skel), "rows (", length(sample_pwsids),
    "CWSs x", YR_HI - YR_LO + 1L, "years)\n")

# ── 4. Three rows: rate of formal enforcement across nested samples ─────────
row1_dt <- skel
row2_dt <- skel[mr_violation == 1]
row3_dt <- skel[mr_violation == 1 & sanitary_visit == 1]

rate <- function(dt) 100 * mean(dt$formal_enforcement)

rows <- data.table(
  sample = c("All CWS-years (downstream 2SLS panel)",
             "CWS-years with an MR violation",
             "CWS-years with an MR violation and a sanitary visit (same year)"),
  n    = c(nrow(row1_dt), nrow(row2_dt), nrow(row3_dt)),
  rate = c(rate(row1_dt), rate(row2_dt), rate(row3_dt))
)
cat("\n--- Formal enforcement rate table ---\n")
print(rows)

# ── 5. LaTeX table (hand-assembled; no wrap_for_beamer -- has \begin{table}) ─
dir.create(file.path(ROOT, "output/sum"), showWarnings = FALSE, recursive = TRUE)

fmt_n    <- function(x) gsub(",", "{,}", formatC(x, format = "d", big.mark = ","))
fmt_pct  <- function(x) sprintf("%.2f", x)

rows_tex <- sprintf("%s & %s & %s\\%% \\\\", rows$sample, fmt_n(rows$n), fmt_pct(rows$rate))

notes_main <- paste0(
  "Sample: strictly downstream CWSs (", length(sample_pwsids), "), CWS-years ", YR_LO,
  "--", YR_HI, " (", nrow(row1_dt), " CWS-years). Formal enforcement = 1 if a violations-",
  "enforcement action with ENF\\_ACTION\\_CATEGORY = Formal is ongoing at any point during ",
  "the calendar year (spell runs from the month of ENFORCEMENT\\_DATE through the month of ",
  "CALCULATED\\_RTC\\_DATE, fallback NON\\_COMPL\\_PER\\_END\\_DATE if RTC missing, else the ",
  "enforcement month itself). MR violation = 1 if a violation onset with VIOLATION\\_CATEGORY\\_",
  "CODE = MR begins in that calendar year (NON\\_COMPL\\_PER\\_BEGIN\\_DATE). Sanitary visit = 1 ",
  "if a site visit with VISIT\\_REASON\\_CODE in \\{SNSV, SNSP, SSVF\\} occurs in that calendar ",
  "year. Row 2 restricts to CWS-years with an MR violation onset (N\\,=\\,", fmt_n(nrow(row2_dt)),
  "). Row 3 further restricts to CWS-years with an MR violation onset and a sanitary visit in ",
  "that same calendar year (N\\,=\\,", fmt_n(nrow(row3_dt)), ")."
)

out_tex <- file.path(ROOT, "output/sum/sanitary_visit_formal_enforcement_rate.tex")
lines_tex <- c(
  "\\begin{table}[htbp]",
  paste0("\\caption{\\label{tab:sanitary_visit_formal_enforcement_rate} Formal Enforcement ",
         "Rate, by Sample Restriction (Downstream CWSs, ", YR_LO, "--", YR_HI, ")}"),
  "\\bigskip",
  "\\centering",
  "\\begin{adjustbox}{width = \\textwidth, center}",
  "\\begin{tabular}{lcc}",
  "\\toprule",
  "Sample & N (CWS-years) & Formal enforcement rate \\\\",
  "\\midrule",
  rows_tex,
  "\\bottomrule",
  "\\end{tabular}",
  "\\end{adjustbox}",
  "{\\tiny\\linespread{1}\\selectfont \\par \\raggedright ",
  notes_main,
  "}",
  "\\end{table}"
)
writeLines(lines_tex, out_tex)
cat("\nTable saved to:", out_tex, "\n")

# ── 4b. 365-day-window rows: MR onset <-> sanitary visit ordering ───────────
# Row 4 ("following sanitary visit"): a sanitary visit occurred in the 365
# days immediately BEFORE the MR onset (visit -> then MR violation). Row 5
# ("preceding sanitary visit"): a sanitary visit occurred in the 365 days
# immediately AFTER the MR onset (MR violation -> then visit). Both rows use
# year t = the MR onset's calendar year for the formal_enforcement outcome
# (same CWS-year indicator as rows 1-3), and are evaluated on the same
# downstream CWS-year skeleton (skel), not year-agnostic onset counts.
mr_onsets[, dummy_id := .I]

visit_before_365 <- san_events[mr_onsets,
  on = .(PWSID, visit_dt < onset_dt),
  .(dummy_id = i.dummy_id, gap_days = as.integer(i.onset_dt - x.visit_dt)),
  nomatch = NULL]
following_ids <- unique(visit_before_365[gap_days <= 365]$dummy_id)

visit_after_365 <- san_events[mr_onsets,
  on = .(PWSID, visit_dt > onset_dt),
  .(dummy_id = i.dummy_id, gap_days = as.integer(x.visit_dt - i.onset_dt)),
  nomatch = NULL]
preceding_ids <- unique(visit_after_365[gap_days <= 365]$dummy_id)

mr_onsets[, following_visit := as.integer(dummy_id %in% following_ids)]
mr_onsets[, preceding_visit := as.integer(dummy_id %in% preceding_ids)]

cat("\nMR onsets with a sanitary visit in the 365 days before (following_visit):",
    sum(mr_onsets$following_visit), "\n")
cat("MR onsets with a sanitary visit in the 365 days after (preceding_visit): ",
    sum(mr_onsets$preceding_visit), "\n")

# CWS-years (from skel) containing >=1 MR onset flagged following_visit / preceding_visit
following_py <- unique(mr_onsets[following_visit == 1, .(PWSID, year = onset_yr)])
preceding_py <- unique(mr_onsets[preceding_visit == 1, .(PWSID, year = onset_yr)])

row4_dt <- skel[following_py, on = .(PWSID, year), nomatch = NULL]
row5_dt <- skel[preceding_py, on = .(PWSID, year), nomatch = NULL]

rows5 <- data.table(
  sample = c("All CWS-years (downstream 2SLS panel)",
             "CWS-years with an MR violation",
             "CWS-years with an MR violation and a sanitary visit (same year)",
             "CWS-years with an MR violation following sanitary visit",
             "CWS-years with an MR violation preceding sanitary visit"),
  n    = c(nrow(row1_dt), nrow(row2_dt), nrow(row3_dt), nrow(row4_dt), nrow(row5_dt)),
  rate = c(rate(row1_dt), rate(row2_dt), rate(row3_dt), rate(row4_dt), rate(row5_dt))
)
cat("\n--- Formal enforcement rate table (5 rows) ---\n")
print(rows5)

rows5_tex <- sprintf("%s & %s & %s\\%% \\\\", rows5$sample, fmt_n(rows5$n), fmt_pct(rows5$rate))

notes_5row <- paste0(
  "Sample: strictly downstream CWSs (", length(sample_pwsids), "), CWS-years ", YR_LO, "--",
  YR_HI, " (", nrow(row1_dt), " CWS-years). Formal enforcement = 1 if a violations-enforcement ",
  "action with ENF\\_ACTION\\_CATEGORY = Formal is ongoing at any point during the calendar ",
  "year t (spell runs from the month of ENFORCEMENT\\_DATE through the month of CALCULATED\\_",
  "RTC\\_DATE, fallback NON\\_COMPL\\_PER\\_END\\_DATE if RTC missing, else the enforcement month ",
  "itself). MR violation = 1 if a violation onset with VIOLATION\\_CATEGORY\\_CODE = MR begins ",
  "in year t (NON\\_COMPL\\_PER\\_BEGIN\\_DATE). Sanitary visit = 1 if a site visit with VISIT\\_",
  "REASON\\_CODE in \\{SNSV, SNSP, SSVF\\} occurs in year t. Row 2 N\\,=\\,", fmt_n(nrow(row2_dt)),
  "; row 3 (visit in the same calendar year as the MR onset) N\\,=\\,", fmt_n(nrow(row3_dt)), ". ",
  "Row 4 (``following sanitary visit''): CWS-year t of an MR violation onset where a sanitary ",
  "visit occurred in the 365 days immediately preceding that onset date (visit, then MR ",
  "violation within a year), N\\,=\\,", fmt_n(nrow(row4_dt)), ". Row 5 (``preceding sanitary ",
  "visit''): CWS-year t of an MR violation onset where a sanitary visit occurred in the 365 ",
  "days immediately following that onset date (MR violation, then visit within a year), ",
  "N\\,=\\,", fmt_n(nrow(row5_dt)), ". Rows 4-5 use year t = the calendar year of the MR onset ",
  "for the formal-enforcement outcome, and the 365-day window is measured in calendar days and ",
  "may cross year boundaries; a CWS-year with more than one qualifying MR onset appears once. ",
  "Rows 4 and 5 are not mutually exclusive."
)

out_5row_tex <- file.path(ROOT, "output/sum/sanitary_visit_timing_formal_enforcement_rate.tex")
lines_5row_tex <- c(
  "\\begin{table}[htbp]",
  paste0("\\caption{\\label{tab:sanitary_visit_timing_formal_enforcement_rate} Formal ",
         "Enforcement Rate, by Sample Restriction and Visit Timing (Downstream CWSs, ",
         YR_LO, "--", YR_HI, ")}"),
  "\\bigskip",
  "\\centering",
  "\\begin{adjustbox}{width = \\textwidth, center}",
  "\\begin{tabular}{lcc}",
  "\\toprule",
  "Sample & N (CWS-years) & Formal enforcement rate \\\\",
  "\\midrule",
  rows5_tex,
  "\\bottomrule",
  "\\end{tabular}",
  "\\end{adjustbox}",
  "{\\tiny\\linespread{1}\\selectfont \\par \\raggedright ",
  notes_5row,
  "}",
  "\\end{table}"
)
writeLines(lines_5row_tex, out_5row_tex)
cat("\nTable saved to:", out_5row_tex, "\n")

# ── 6. Verification ──────────────────────────────────────────────────────────
stopifnot(file.exists(out_tex), file.info(out_tex)$size > 0)
stopifnot(nrow(row1_dt) > nrow(row2_dt), nrow(row2_dt) >= nrow(row3_dt), nrow(row3_dt) > 0)
stopifnot(file.exists(out_5row_tex), file.info(out_5row_tex)$size > 0)
stopifnot(nrow(row4_dt) > 0, nrow(row5_dt) > 0, nrow(row4_dt) <= nrow(row2_dt), nrow(row5_dt) <= nrow(row2_dt))
cat("Output verified: both files exist and are non-zero; row Ns consistent.\n")
cat("=== DONE ===\n")
