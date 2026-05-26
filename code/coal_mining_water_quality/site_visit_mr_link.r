# ============================================================
# Script: site_visit_mr_link.r
# Purpose: Summarize how site visits (SDWA_SITE_VISITS) relate to MR violations
#          in the downstream 2SLS sample. Three linkage approaches:
#          (A) PWSID-year co-occurrence in the main panel
#          (B) Temporal proximity of visit date to active MR violation window
#          (C) Enforcement-coded site visits (SID actions) — sparsity check
# Inputs:  clean_data/cws_data/prod_vio_sulfur.parquet
#          SDWA_SITE_VISITS.csv
#          SDWA_VIOLATIONS_ENFORCEMENT.csv
# Outputs: output/sum/site_visit_mr_link.tex
# Author: EK  Date: 2026-05-25
# ============================================================

.libPaths("Z:/ek559/RPackages")
library(arrow)
library(data.table)

SDWA_DIR <- "Z:/ek559/sdwa_violations/SDWA_latest_downloads"
fn <- function(x) format(as.integer(round(x)), big.mark = ",")
fp <- function(x) sprintf("%.1f", x)

# ── 0. Downstream PWSID list and main panel ───────────────────────────────────
panel <- as.data.table(
  arrow::read_parquet("Z:/ek559/mining_wq/clean_data/cws_data/prod_vio_sulfur.parquet",
    col_select = c("PWSID", "year", "minehuc_downstream_of_mine", "minehuc_mine")))
panel <- panel[minehuc_downstream_of_mine == 1 & minehuc_mine == 0]
pws_ids <- unique(panel$PWSID)
cat("Downstream PWSIDs:", length(pws_ids), "\n")
cat("Panel PWSID-years:", nrow(panel), "\n")

# ── 1. Load violations (MR only) ─────────────────────────────────────────────
ve <- fread(file.path(SDWA_DIR, "SDWA_VIOLATIONS_ENFORCEMENT.csv"),
  select = c("PWSID", "VIOLATION_ID", "NON_COMPL_PER_BEGIN_DATE", "CALCULATED_RTC_DATE",
             "VIOLATION_CATEGORY_CODE", "RULE_CODE", "ENFORCEMENT_ID",
             "ENFORCEMENT_DATE", "ENFORCEMENT_ACTION_TYPE_CODE", "ENF_ACTION_CATEGORY"),
  colClasses = list(character = "PWSID"), na.strings = c("", "NA"), showProgress = FALSE)
ve[, yr := as.integer(substr(NON_COMPL_PER_BEGIN_DATE, 7, 10))]
ve <- ve[PWSID %in% pws_ids & yr >= 1985 & yr <= 2005]

mr <- ve[VIOLATION_CATEGORY_CODE == "MR"]
cat("MR enforcement rows:", nrow(mr), "\n")
cat("Unique MR violations:", uniqueN(mr$VIOLATION_ID), "\n")

# ── 2. Load site visits ───────────────────────────────────────────────────────
sv <- fread(file.path(SDWA_DIR, "SDWA_SITE_VISITS.csv"),
  select = c("PWSID", "VISIT_ID", "VISIT_DATE", "VISIT_REASON_CODE", "COMPLIANCE_EVAL_CODE"),
  colClasses = list(character = "PWSID"), na.strings = c("", "NA"), showProgress = FALSE)
sv[, yr := as.integer(substr(VISIT_DATE, 7, 10))]
sv <- sv[PWSID %in% pws_ids & yr >= 1985 & yr <= 2005]
cat("Site visits:", nrow(sv), "\n")

# ── Panel A: PWSID-year co-occurrence in the main regression panel ────────────
sv_py <- sv[, .(has_visit = 1L), by = .(PWSID, yr)]
mr_py <- mr[, .(has_mr   = 1L), by = .(PWSID, yr)]

pnl <- copy(panel)[, .(PWSID, yr = year)]
pnl <- merge(pnl, unique(sv_py), by = c("PWSID", "yr"), all.x = TRUE)
pnl <- merge(pnl, unique(mr_py), by = c("PWSID", "yr"), all.x = TRUE)
pnl[is.na(has_visit), has_visit := 0L]
pnl[is.na(has_mr),    has_mr    := 0L]

N_tot <- nrow(pnl)
N_v1m1 <- pnl[has_visit==1 & has_mr==1, .N]
N_v1m0 <- pnl[has_visit==1 & has_mr==0, .N]
N_v0m1 <- pnl[has_visit==0 & has_mr==1, .N]
N_v0m0 <- pnl[has_visit==0 & has_mr==0, .N]
N_visit <- N_v1m1 + N_v1m0
N_mr    <- N_v1m1 + N_v0m1

cat("\nPanel A (PWSID-years from main panel, N=", N_tot, "):\n", sep="")
cat("Visit=1, MR=1:", N_v1m1, "\n")
cat("Visit=1, MR=0:", N_v1m0, "\n")
cat("Visit=0, MR=1:", N_v0m1, "\n")
cat("Visit=0, MR=0:", N_v0m0, "\n")

# Conditional rates
p_mr_given_visit   <- 100 * N_v1m1 / N_visit
p_mr_given_novisit <- 100 * N_v0m1 / (N_tot - N_visit)
p_visit_given_mr   <- 100 * N_v1m1 / N_mr
p_visit_given_nomr <- 100 * N_v1m0 / (N_tot - N_mr)

cat("Pr(MR | visit):", round(p_mr_given_visit,1), "%\n")
cat("Pr(MR | no visit):", round(p_mr_given_novisit,1), "%\n")
cat("Pr(visit | MR):", round(p_visit_given_mr,1), "%\n")
cat("Pr(visit | no MR):", round(p_visit_given_nomr,1), "%\n")

# ── Panel B: Temporal proximity — visit date relative to MR violation window ──
mr_dates <- unique(mr[, .(PWSID, VIOLATION_ID,
  viol_begin = as.Date(NON_COMPL_PER_BEGIN_DATE, "%m/%d/%Y"),
  viol_rtc   = as.Date(CALCULATED_RTC_DATE,       "%m/%d/%Y"))])
mr_dates <- mr_dates[!is.na(viol_begin)]

sv_dates <- sv[!is.na(VISIT_DATE),
               .(PWSID, VISIT_ID, visit_dt = as.Date(VISIT_DATE, "%m/%d/%Y"),
                 reason = VISIT_REASON_CODE)]
sv_dates <- sv_dates[!is.na(visit_dt)]
n_visits_dated <- nrow(sv_dates)

# Cross join by PWSID — for each visit find all MR violations at same PWSID
sv_mr <- merge(sv_dates, mr_dates, by = "PWSID", allow.cartesian = TRUE)

sv_mr[, days_since_begin := as.numeric(visit_dt - viol_begin)]
sv_mr[, active := days_since_begin >= 0 & (is.na(viol_rtc) | visit_dt <= viol_rtc)]

# Per visit: tag the most informative relationship
visit_tag <- sv_mr[, .(
  active          = any(active,       na.rm = TRUE),
  before_365      = any(days_since_begin >= -365 & days_since_begin < 0, na.rm = TRUE),
  after_rtc_365   = any(!is.na(viol_rtc) &
                          as.numeric(visit_dt - viol_rtc) >= 0 &
                          as.numeric(visit_dt - viol_rtc) <= 365, na.rm = TRUE)
), by = .(PWSID, VISIT_ID)]

# Visits with no MR at same PWSID at all
pws_with_mr <- unique(mr_dates$PWSID)
visit_tag[, has_any_mr_at_pwsid := PWSID %in% pws_with_mr]

# Classify each visit (priority: active > before_365 > after_rtc_365 > same PWSID other)
visit_tag[, category := fcase(
  active,                                    "During active MR violation",
  !active & before_365,                      "Within 365 days before MR begins",
  !active & !before_365 & after_rtc_365,     "Within 365 days after MR resolves",
  default =                                  "Same PWSID, outside all windows"
)]

# Add visits at PWSIDs with no MR violations (dropped from cross-join; restore here)
pws_with_mr    <- unique(mr_dates$PWSID)
visits_no_mr_pws <- sv_dates[!PWSID %in% pws_with_mr,
                               .(PWSID, VISIT_ID,
                                 category = "No MR violations at this PWSID")]
visit_tag_full <- rbindlist(list(
  visit_tag[, .(PWSID, VISIT_ID, category)],
  visits_no_mr_pws
), use.names = TRUE)

cat("\nPanel B — visit classification:\n")
print(visit_tag_full[, .N, by=category])
stopifnot(nrow(visit_tag_full) == n_visits_dated)

b_tab <- visit_tag_full[, .N, by=category][order(-N)]
b_tab[, share := 100 * N / n_visits_dated]

n_visits_mr_pws <- visit_tag[.N, .N]
cat("Visits at PWSIDs with at least one MR violation:", nrow(visit_tag), "\n")

# ── Panel C: SID enforcement-coded site visits (sparsity check) ───────────────
sid <- ve[ENFORCEMENT_ACTION_TYPE_CODE == "SID"]
mr_sid <- sid[VIOLATION_CATEGORY_CODE == "MR"]
n_sid_total     <- nrow(sid)
n_sid_mr        <- nrow(mr_sid)
n_sid_mr_viols  <- uniqueN(mr_sid$VIOLATION_ID)
n_mr_viols_all  <- uniqueN(mr$VIOLATION_ID)
share_mr_with_sid <- 100 * n_sid_mr_viols / n_mr_viols_all

cat("\nPanel C:\n")
cat("Total SID enforcement actions:", n_sid_total, "\n")
cat("SID actions on MR violations:", n_sid_mr, "\n")
cat("Unique MR violations with SID:", n_sid_mr_viols, "\n")
cat("Share of all MR violations:", round(share_mr_with_sid, 2), "%\n")

# ── Build LaTeX ───────────────────────────────────────────────────────────────
lines <- c(
  "\\begin{table}[htbp]",
  "\\centering",
  "\\caption{Relationship Between Site Visits and MR Violations (Downstream 2SLS Sample, 1985--2005)}",
  "\\label{tab:site_visit_mr_link}",
  "\\small",
  "\\begin{tabular}{lrr}",
  "\\hline\\hline",
  " & \\multicolumn{1}{c}{N} & \\multicolumn{1}{c}{\\%} \\\\",
  "\\hline",

  # Panel A
  "\\multicolumn{3}{l}{\\textit{Panel A: PWSID--year co-occurrence in the main regression panel}} \\\\",
  paste0("\\multicolumn{3}{l}{\\footnotesize\\textit{Base: ", fn(N_tot),
         " PWSID--years from the downstream 2SLS panel (349 CWSs $\\times$ 1985--2005)}} \\\\[2pt]"),
  paste0("Site visit and MR violation & ", fn(N_v1m1), " & ", fp(100*N_v1m1/N_tot), " \\\\"),
  paste0("Site visit only (no MR violation) & ", fn(N_v1m0), " & ", fp(100*N_v1m0/N_tot), " \\\\"),
  paste0("MR violation only (no site visit) & ", fn(N_v0m1), " & ", fp(100*N_v0m1/N_tot), " \\\\"),
  paste0("Neither & ", fn(N_v0m0), " & ", fp(100*N_v0m0/N_tot), " \\\\"),
  "\\hline",
  paste0("\\multicolumn{3}{l}{\\footnotesize Pr(MR violation $|$ visit year) = ",
         fp(p_mr_given_visit), "\\%; Pr(MR violation $|$ no visit year) = ",
         fp(p_mr_given_novisit), "\\%} \\\\"),
  paste0("\\multicolumn{3}{l}{\\footnotesize Pr(visit $|$ MR violation year) = ",
         fp(p_visit_given_mr), "\\%; Pr(visit $|$ no MR violation year) = ",
         fp(p_visit_given_nomr), "\\%} \\\\[6pt]"),

  # Panel B
  "\\multicolumn{3}{l}{\\textit{Panel B: Temporal proximity of site visit date to MR violation window}} \\\\",
  paste0("\\multicolumn{3}{l}{\\footnotesize\\textit{Base: ", fn(n_visits_dated),
         " dated site visits matched to downstream CWSs}} \\\\[2pt]")
)

# Order for Panel B display
b_order <- c("During active MR violation",
             "Within 365 days before MR begins",
             "Within 365 days after MR resolves",
             "Same PWSID, outside all windows",
             "No MR violations at this PWSID")
for (cat_label in b_order) {
  r <- b_tab[category == cat_label]
  if (nrow(r) == 0) next
  lines <- c(lines, paste0(cat_label, " & ", fn(r$N), " & ", fp(r$share), " \\\\"))
}
lines <- c(lines,
  "\\hline",
  paste0("\\textit{Total} & ", fn(n_visits_dated), " & 100.0 \\\\[6pt]"),

  # Panel C
  "\\multicolumn{3}{l}{\\textit{Panel C: Site visits recorded as enforcement responses (SID code)}} \\\\",
  paste0("\\multicolumn{3}{l}{\\footnotesize\\textit{SID = ``State Site Visit for enforcement ",
         "purposes'' in SDWA\\_VIOLATIONS\\_ENFORCEMENT}} \\\\[2pt]"),
  paste0("All SID enforcement actions (any violation type) & ", fn(n_sid_total), " & \\\\"),
  paste0("SID actions on MR violations & ", fn(n_sid_mr), " & \\\\"),
  paste0("Unique MR violations linked to a SID action & ", fn(n_sid_mr_viols), " & ",
         fp(share_mr_with_sid), " \\\\"),
  paste0("\\multicolumn{3}{l}{\\footnotesize (denominator: ", fn(n_mr_viols_all),
         " unique MR violations in downstream sample)} \\\\"),

  "\\hline\\hline",
  "\\end{tabular}",
  "\\begin{minipage}{\\linewidth}",
  "\\vspace{4pt}",
  "\\footnotesize",
  paste0("\\textit{Notes:} Sample is the strictly downstream 2SLS sample ",
         "(\\texttt{minehuc\\_downstream\\_of\\_mine}=1, \\texttt{minehuc\\_mine}=0), ",
         "1985--2005 (", fn(length(pws_ids)), " CWSs). ",
         "\\textit{Panel A} uses the PWSID--year panel from \\texttt{prod\\_vio\\_sulfur.parquet}; ",
         "a year is coded as having a site visit (MR violation) if any visit (MR violation) ",
         "begins in that calendar year. ",
         "\\textit{Panel B} classifies each site visit by its temporal relationship to the ",
         "nearest active MR violation at the same PWSID: ``during'' means the visit date falls ",
         "within an open violation window (begin $\\le$ visit $\\le$ RTC); the 365-day windows ",
         "are mutually exclusive from ``during'' and applied in priority order. ",
         "\\textit{Panel C} uses \\texttt{ENFORCEMENT\\_ACTION\\_TYPE\\_CODE}=SID, which records ",
         "site visits explicitly logged as enforcement responses to a specific violation. ",
         "There is no shared foreign key between \\texttt{SDWA\\_SITE\\_VISITS} and ",
         "\\texttt{SDWA\\_VIOLATIONS\\_ENFORCEMENT}; Panels A and B use temporal linkage ",
         "by PWSID and date. MR = monitoring/reporting violation."),
  "\\end{minipage}",
  "\\end{table}"
)

out_path <- "Z:/ek559/mining_wq/output/sum/site_visit_mr_link.tex"
writeLines(lines, out_path)
cat("\nOutput written to:", out_path, "\n")
cat("=== DONE ===\n")
