# ============================================================
# Script: sanitary_visit_upstream_mines_ols.r
# Purpose: OLS of formal enforcement on sanitary visit (binary), an
#          above-median-upstream-mines binary, and an MR violation onset
#          binary, on the main D1 2SLS panel (downstream, one step from
#          mine, same sample as didhet.r / enforcement_chain_d12.r).
#          Col 1: no fixed effects. Col 2: year FE. Col 3: CWS (PWSID) FE.
#          Col 4: year + CWS FE. MR violation onset defined as in
#          sanitary_visit_formal_enforcement_rate.r (VIOLATION_CATEGORY_CODE
#          == "MR", deduped on VIOLATION_ID, year of NON_COMPL_PER_BEGIN_DATE).
# Inputs:  clean_data/cws_data/prod_vio_sulfur.parquet
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_SITE_VISITS.csv
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.csv
# Outputs: output/reg/sanitary_visit_upstream_mines_ols.tex
# Author: EK  Date: 2026-07-13
# ============================================================

.libPaths("Z:/ek559/RPackages")
library(arrow)
library(data.table)
library(fixest)
library(dplyr)

ROOT     <- "Z:/ek559/mining_wq"
SDWA_DIR <- "Z:/ek559/sdwa_violations/SDWA_latest_downloads"

YR_LO <- 1985L
YR_HI <- 2005L

# ── 1. D1 main panel: prod_vio_sulfur.parquet, downstream-of-mine sample ────
# Same sample definition as didhet.r / enforcement_chain_d12.r "D1 main panel".
main_pvs <- read_parquet(file.path(ROOT, "clean_data/cws_data/prod_vio_sulfur.parquet"))
d1_main  <- main_pvs[main_pvs$minehuc_downstream_of_mine == 1 &
                      main_pvs$minehuc_mine == 0 &
                      main_pvs$year >= YR_LO & main_pvs$year <= YR_HI &
                      main_pvs$PWSID != "WV3303401", ]
rm(main_pvs); gc()

ids_d1 <- unique(d1_main$PWSID)
cat(sprintf("D1 main panel: %d PWSIDs x %d PWSID-years\n", length(ids_d1), nrow(d1_main)))

# ── 2. Sanitary visits (SNSV, SSVF), year of visit ───────────────────────────
sv <- fread(file.path(SDWA_DIR, "SDWA_SITE_VISITS.csv"),
            select = c("PWSID", "VISIT_DATE", "VISIT_REASON_CODE"))
sv <- sv[PWSID %in% ids_d1]
sv[, year := as.integer(substr(trimws(VISIT_DATE),
                               nchar(trimws(VISIT_DATE)) - 3,
                               nchar(trimws(VISIT_DATE))))]
sv <- sv[!is.na(year) & year >= YR_LO & year <= YR_HI]

sv_agg <- sv[, .(any_snsv = any(VISIT_REASON_CODE %in% c("SNSV", "SSVF"))), by = .(PWSID, year)]
cat(sprintf("PWSID-years with a sanitary visit: %d\n", sum(sv_agg$any_snsv)))
rm(sv); gc()

# ── 3. Enforcement actions -> any formal enforcement, PWSID-year ────────────
enf <- fread(file.path(SDWA_DIR, "SDWA_VIOLATIONS_ENFORCEMENT.csv"),
             select = c("PWSID", "COMPL_PER_BEGIN_DATE", "ENF_ACTION_CATEGORY"))
enf <- enf[PWSID %in% ids_d1]
enf[, year := as.integer(substr(trimws(COMPL_PER_BEGIN_DATE),
                                nchar(trimws(COMPL_PER_BEGIN_DATE)) - 3,
                                nchar(trimws(COMPL_PER_BEGIN_DATE))))]
enf <- enf[!is.na(year) & year >= YR_LO & year <= YR_HI]

enf_agg <- enf[, .(any_formal = any(ENF_ACTION_CATEGORY == "Formal", na.rm = TRUE)), by = .(PWSID, year)]
cat(sprintf("PWSID-years with formal enforcement: %d\n", sum(enf_agg$any_formal)))
rm(enf); gc()

# ── 3b. MR violation onsets, PWSID-year ──────────────────────────────────────
# Same definition as sanitary_visit_formal_enforcement_rate.r: dedupe on
# VIOLATION_ID, year of NON_COMPL_PER_BEGIN_DATE, VIOLATION_CATEGORY_CODE == "MR".
ve <- fread(file.path(SDWA_DIR, "SDWA_VIOLATIONS_ENFORCEMENT.csv"),
            select = c("PWSID", "VIOLATION_ID", "NON_COMPL_PER_BEGIN_DATE", "VIOLATION_CATEGORY_CODE"))
ve <- ve[PWSID %in% ids_d1]
onsets <- unique(ve[, .(PWSID, VIOLATION_ID, NON_COMPL_PER_BEGIN_DATE, VIOLATION_CATEGORY_CODE)])
onsets[, onset_dt := as.Date(NON_COMPL_PER_BEGIN_DATE, "%m/%d/%Y")]
onsets <- onsets[!is.na(onset_dt)]
onsets[, onset_yr := as.integer(format(onset_dt, "%Y"))]
onsets <- onsets[onset_yr >= YR_LO & onset_yr <= YR_HI]

mr_onsets <- onsets[VIOLATION_CATEGORY_CODE == "MR", .(PWSID, VIOLATION_ID, onset_dt, onset_yr)]
mr_agg <- unique(mr_onsets[, .(PWSID, year = onset_yr, mr_violation = 1L)])
cat(sprintf("PWSID-years with an MR violation onset: %d\n", nrow(mr_agg)))
rm(ve, onsets, mr_onsets); gc()

# ── 4. Merge onto D1 main panel ───────────────────────────────────────────────
panel_d1 <- d1_main %>%
  left_join(as.data.frame(sv_agg),  by = c("PWSID", "year")) %>%
  left_join(as.data.frame(enf_agg), by = c("PWSID", "year")) %>%
  left_join(as.data.frame(mr_agg),  by = c("PWSID", "year"))

panel_d1$any_snsv[is.na(panel_d1$any_snsv)]         <- FALSE
panel_d1$any_formal[is.na(panel_d1$any_formal)]     <- FALSE
panel_d1$mr_violation[is.na(panel_d1$mr_violation)] <- 0L
panel_d1$any_snsv   <- as.integer(panel_d1$any_snsv)
panel_d1$any_formal <- as.integer(panel_d1$any_formal)

cat(sprintf("Main 2SLS panel (D1): %d PWSID-years\n", nrow(panel_d1)))
cat(sprintf("any_snsv = 1 in %d (%.1f%%)\n", sum(panel_d1$any_snsv), 100 * mean(panel_d1$any_snsv)))
cat(sprintf("any_formal = 1 in %d (%.1f%%)\n", sum(panel_d1$any_formal), 100 * mean(panel_d1$any_formal)))
cat(sprintf("mr_violation = 1 in %d (%.1f%%)\n", sum(panel_d1$mr_violation), 100 * mean(panel_d1$mr_violation)))

# ── 5. Above-median-upstream-mines binary ────────────────────────────────────
# Median taken over CWS-years in this same D1 main downstream 2SLS panel.
median_upstream_mines <- median(panel_d1$num_coal_mines_upstream_sum, na.rm = TRUE)
cat(sprintf("Median num_coal_mines_upstream_sum (D1 main panel): %g\n", median_upstream_mines))
panel_d1$upstream_mines_above_median <- as.integer(
  panel_d1$num_coal_mines_upstream_sum > median_upstream_mines)
cat(sprintf("upstream_mines_above_median = 1 in %d (%.1f%%)\n",
    sum(panel_d1$upstream_mines_above_median), 100 * mean(panel_d1$upstream_mines_above_median)))

# ── 6. OLS regressions ────────────────────────────────────────────────────────
fml_nofe     <- any_formal ~ any_snsv + upstream_mines_above_median + mr_violation
fml_yearfe   <- any_formal ~ any_snsv + upstream_mines_above_median + mr_violation | year
fml_pwsidfe  <- any_formal ~ any_snsv + upstream_mines_above_median + mr_violation | PWSID
fml_bothfe   <- any_formal ~ any_snsv + upstream_mines_above_median + mr_violation | PWSID + year

m1 <- feols(fml_nofe,    data = panel_d1, cluster = ~ PWSID)
m2 <- feols(fml_yearfe,  data = panel_d1, cluster = ~ PWSID)
m3 <- feols(fml_pwsidfe, data = panel_d1, cluster = ~ PWSID)
m4 <- feols(fml_bothfe,  data = panel_d1, cluster = ~ PWSID)

cat("\n--- OLS: formal enforcement on sanitary visit + above-median upstream mines (D1 main 2SLS panel) ---\n")
etable(m1, m2, m3, m4,
  headers = list("Fixed effects" = list("None" = 1, "Year" = 1, "CWS" = 1, "Year + CWS" = 1)),
  se.below = TRUE, fitstat = ~ n + r2)

# ── 7. LaTeX table (style.tex("aer", adjustbox = TRUE); captioned/labeled) ──
move_notes_below_adjustbox <- function(x) {
  x           <- paste(x, collapse = "\n")
  end_adj     <- "\\end{adjustbox}"
  par_rag     <- "\\par \\raggedright"
  par_pos     <- regexpr(par_rag, x, fixed = TRUE)
  end_adj_pos <- regexpr(end_adj, x, fixed = TRUE)
  if (par_pos[1] == -1 || end_adj_pos[1] == -1) return(x)
  note_block <- substr(x, par_pos[1], end_adj_pos[1] - 1)
  x <- sub(note_block, "", x, fixed = TRUE)
  x <- sub(end_adj,
            paste0(end_adj, "\n   {\\tiny\\linespread{1}\\selectfont ",
                   trimws(note_block), "}"),
            x, fixed = TRUE)
  x
}
postprocess_table <- function(x) move_notes_below_adjustbox(x)

dir.create(file.path(ROOT, "output/reg"), showWarnings = FALSE, recursive = TRUE)
out_tex <- file.path(ROOT, "output/reg/sanitary_visit_upstream_mines_ols.tex")

dict_main <- c(
  "any_snsv"                     = "Sanitary visit",
  "upstream_mines_above_median"  = "Upstream mines $>$ median",
  "mr_violation"                 = "MR violation",
  "PWSID"                        = "CWS"
)

etable(m1, m2, m3, m4,
       title          = "Effect of Sanitary Visits and Upstream Coal Mining on Formal Enforcement (D1 Downstream Sample)",
       label          = "tab:sanitary_visit_upstream_mines_ols",
       dict           = dict_main,
       headers        = list("Fixed effects" = list("None" = 1, "Year" = 1, "CWS" = 1, "Year + CWS" = 1)),
       fitstat        = ~ n + r2,
       notes          = paste0(
         "D1 downstream sample (minehuc\\_downstream\\_of\\_mine = 1, minehuc\\_mine = 0), ",
         "CWS-years ", YR_LO, "--", YR_HI, " (N\\,=\\,", nrow(panel_d1), "). ",
         "Dependent variable: any formal enforcement action ongoing in the calendar year (",
         sprintf("%.1f", 100 * mean(panel_d1$any_formal)), "\\% of panel). Sanitary visit = 1 if a ",
         "site visit with VISIT\\_REASON\\_CODE in \\{SNSV, SSVF\\} occurs in that calendar year (",
         sprintf("%.1f", 100 * mean(panel_d1$any_snsv)), "\\% of panel). Upstream mines $>$ median = 1 ",
         "if num\\_coal\\_mines\\_upstream\\_sum exceeds the median (", median_upstream_mines,
         ") across CWS-years in this D1 main downstream 2SLS panel. MR violation = 1 if a ",
         "VIOLATION\\_CATEGORY\\_CODE = MR violation has its onset (NON\\_COMPL\\_PER\\_BEGIN\\_DATE) ",
         "in that calendar year (", sprintf("%.1f", 100 * mean(panel_d1$mr_violation)),
         "\\% of panel). Standard errors clustered by CWS."),
       style.tex       = style.tex("aer", adjustbox = TRUE),
       tex             = TRUE,
       postprocess.tex = postprocess_table,
       file            = out_tex,
       replace         = TRUE)

cat(sprintf("\nTable saved to: %s\n", out_tex))
if (file.exists(out_tex) && file.info(out_tex)$size > 0) {
  cat("Output verified: file exists and is non-zero.\n")
} else {
  stop("Output file missing or empty — check etable() call.")
}

cat("\n=== DONE ===\n")
