# ============================================================
# Script: test_h2_snsv_chem.r
# Purpose: TEST version of h2_snsv_d12.tex — restricts the "Enforcement
#          visits" outcome (any_enfvisit) to PWSID-years that also have
#          an active arsenic, nitrate, or IOC violation on record.
#          SDWA_SITE_VISITS.csv has no contaminant/violation link, so the
#          chemical restriction is proxied by co-occurrence: a PWSID-year
#          counts as a chemical-linked enforcement visit only if it had
#          BOTH an enforcement-reason visit (FENF/INVG/EMRG) AND at least
#          one arsenic/nitrate/IOC violation that year.
#          RULE_CODE mapping (same as enf_action_by_viol_type_dwnstrm.r):
#            331 = nitrate, 332 = arsenic, 333 = inorganic chemicals (IOC)
#          Other visit-type outcomes (sanitary, technical assistance,
#          sample collection, inspection) are unchanged from h2_snsv_d12.tex.
# Inputs:
#   clean_data/cws_data/prod_vio_sulfur.parquet
#   Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_SITE_VISITS.csv
#   Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.csv
# Outputs:
#   output/reg/test_h2_snsv_chem.tex
# Author: EK  Date: 2026-07-15
# ============================================================

.libPaths("Z:/ek559/RPackages")
library(arrow)
library(data.table)
library(fixest)
library(dplyr)

ROOT <- "Z:/ek559/mining_wq"
SDWA <- "Z:/ek559/sdwa_violations/SDWA_latest_downloads"
setwd(ROOT)

# ── Step 1: D1 main panel (same sample as h2_snsv_d12.tex) ──────────────────
cat("Loading D1 main panel (prod_vio_sulfur.parquet)...\n")
main_pvs <- read_parquet("clean_data/cws_data/prod_vio_sulfur.parquet")
d1_main  <- main_pvs[main_pvs$minehuc_downstream_of_mine == 1 &
                      main_pvs$minehuc_mine == 0 &
                      main_pvs$year >= 1985 & main_pvs$year <= 2005 &
                      main_pvs$PWSID != "WV3303401", ]
ids_d1_main <- unique(d1_main$PWSID)
cat(sprintf("D1 main panel: %d PWSIDs x %d PWSID-years\n\n",
            length(ids_d1_main), nrow(d1_main)))
rm(main_pvs); gc()

# ── Step 2: Site visits ───────────────────────────────────────────────────────
cat("Reading SDWA_SITE_VISITS.csv (355 MB)...\n")
sv <- fread(file.path(SDWA, "SDWA_SITE_VISITS.csv"),
            select = c("PWSID", "VISIT_DATE", "VISIT_REASON_CODE"))
sv <- sv[PWSID %in% ids_d1_main]

sv[, year := as.integer(substr(trimws(VISIT_DATE),
                               nchar(trimws(VISIT_DATE)) - 3,
                               nchar(trimws(VISIT_DATE))))]
sv <- sv[!is.na(year) & year >= 1985 & year <= 2005]

sv_agg <- sv[, .(any_snsv     = any(VISIT_REASON_CODE %in% c("SNSV", "SSVF")),
                  any_tech     = any(VISIT_REASON_CODE %in% c("TECH", "ENGR", "OM")),
                  any_enfvisit = any(VISIT_REASON_CODE %in% c("FENF", "INVG", "EMRG")),
                  any_smpl     = any(VISIT_REASON_CODE == "SMPL"),
                  any_insp     = any(VISIT_REASON_CODE %in% c("SITE", "RSCH", "INFI"))),
              by = .(PWSID, year)]
cat(sprintf("PWSID-years with enforcement visit (unrestricted): %d\n",
    sum(sv_agg$any_enfvisit)))
rm(sv); gc()

# ── Step 3: Chemical-specific violations (arsenic/nitrate/IOC) ──────────────
cat("\nReading SDWA_VIOLATIONS_ENFORCEMENT.csv (3.7 GB, cols for RULE_CODE) ...\n")
vio <- fread(file.path(SDWA, "SDWA_VIOLATIONS_ENFORCEMENT.csv"),
             select = c("PWSID", "COMPL_PER_BEGIN_DATE", "RULE_CODE", "VIOLATION_ID"))
vio <- vio[PWSID %in% ids_d1_main & !is.na(VIOLATION_ID)]

vio[, year := as.integer(substr(trimws(COMPL_PER_BEGIN_DATE),
                                nchar(trimws(COMPL_PER_BEGIN_DATE)) - 3,
                                nchar(trimws(COMPL_PER_BEGIN_DATE))))]
vio <- vio[!is.na(year) & year >= 1985 & year <= 2005]
vio[, rule_num := suppressWarnings(as.numeric(RULE_CODE))]

vio_chem <- vio[rule_num %in% c(331, 332, 333)]  # nitrate, arsenic, IOC
cat(sprintf("Arsenic/nitrate/IOC violation records: %d\n", nrow(vio_chem)))

chem_vio_yrs <- unique(vio_chem[, .(PWSID, year)])
chem_vio_yrs[, has_chem_vio := TRUE]
cat(sprintf("PWSID-years with an arsenic/nitrate/IOC violation: %d\n", nrow(chem_vio_yrs)))

rm(vio, vio_chem); gc()

# ── Step 4: Build D1 regression panel ────────────────────────────────────────
cat("\nBuilding D1 regression panel with chemical-restricted enforcement visits...\n")
panel_d1 <- d1_main %>%
  left_join(as.data.frame(sv_agg),        by = c("PWSID", "year")) %>%
  left_join(as.data.frame(chem_vio_yrs),  by = c("PWSID", "year"))

panel_d1$any_snsv[is.na(panel_d1$any_snsv)]         <- FALSE
panel_d1$any_tech[is.na(panel_d1$any_tech)]         <- FALSE
panel_d1$any_enfvisit[is.na(panel_d1$any_enfvisit)] <- FALSE
panel_d1$any_smpl[is.na(panel_d1$any_smpl)]         <- FALSE
panel_d1$any_insp[is.na(panel_d1$any_insp)]         <- FALSE
panel_d1$has_chem_vio[is.na(panel_d1$has_chem_vio)] <- FALSE

panel_d1$any_snsv     <- as.integer(panel_d1$any_snsv)
panel_d1$any_tech     <- as.integer(panel_d1$any_tech)
panel_d1$any_smpl     <- as.integer(panel_d1$any_smpl)
panel_d1$any_insp     <- as.integer(panel_d1$any_insp)

# Chemical-restricted enforcement visit: enforcement visit AND a chem violation that year
panel_d1$any_enfvisit_chem <- as.integer(panel_d1$any_enfvisit & panel_d1$has_chem_vio)
panel_d1$any_enfvisit      <- as.integer(panel_d1$any_enfvisit)

cat(sprintf("D1 panel: %d PWSID-years\n", nrow(panel_d1)))
cat(sprintf("any_enfvisit (unrestricted)      = 1 in %d (%.2f%%)\n",
    sum(panel_d1$any_enfvisit), 100 * mean(panel_d1$any_enfvisit)))
cat(sprintf("any_enfvisit_chem (arsenic/nitrate/IOC) = 1 in %d (%.2f%%)\n",
    sum(panel_d1$any_enfvisit_chem), 100 * mean(panel_d1$any_enfvisit_chem)))

stopifnot("post95"                      %in% names(panel_d1))
stopifnot("sulfur_unified_mean"         %in% names(panel_d1))
stopifnot("num_coal_mines_upstream_sum" %in% names(panel_d1))

# ── Step 5: H2b regressions — same 5 visit-type outcomes, enfvisit replaced ──
visit_outcomes <- c(any_snsv          = "Sanitary visits",
                     any_tech          = "Technical assistance",
                     any_enfvisit_chem = "Enforcement visits (arsenic/nitrate/IOC)",
                     any_smpl          = "Sample collection",
                     any_insp          = "Inspection")

cat("\n=== H2b TEST: Any visit by type (binary, LPM) ~ mining (D1 main panel) ===\n")

models_b <- list()
for (oc in names(visit_outcomes)) {
  cat(sprintf("\n%s (%s) = 1 in %d / %d CWS-years (%.2f%%)\n",
      oc, visit_outcomes[oc], sum(panel_d1[[oc]]), nrow(panel_d1),
      100 * mean(panel_d1[[oc]])))

  fml_ols_oc <- as.formula(paste0(oc, " ~ num_coal_mines_upstream_sum + num_facilities | PWSID + year"))
  fml_rf_oc  <- as.formula(paste0(oc, " ~ post95:sulfur_unified_mean + num_facilities | PWSID + year"))
  fml_iv_oc  <- as.formula(paste0(oc, " ~ num_facilities | PWSID + year | num_coal_mines_upstream_sum ~ post95:sulfur_unified_mean"))

  models_b[[paste0(oc, "_ols")]] <- feols(fml_ols_oc, data = panel_d1, cluster = ~PWSID)
  models_b[[paste0(oc, "_rf")]]  <- feols(fml_rf_oc,  data = panel_d1, cluster = ~PWSID)
  models_b[[paste0(oc, "_iv")]]  <- feols(fml_iv_oc,  data = panel_d1, cluster = ~PWSID)
}

# Clustered first-stage F-stat (no state FE, matches table spec) — identical
# across outcomes (same treatment/instrument/sample), computed once.
f_fs_b <- feols(num_coal_mines_upstream_sum ~ post95:sulfur_unified_mean + num_facilities |
                PWSID + year, data = panel_d1, cluster = ~PWSID)
t_cl_b <- coef(f_fs_b)["post95:sulfur_unified_mean"] / se(f_fs_b)["post95:sulfur_unified_mean"]
f_cl_b <- round(t_cl_b^2, 2)
cat(sprintf("\nClustered first-stage F-stat (H2b TEST, D1): %.2f\n", f_cl_b))

# ── Step 6: Beamer/aer table helpers (copied from enforcement_chain_d12.r) ──
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

rename_col_numbers_to_labels <- function(x) {
  x     <- paste(x, collapse = "\n")
  lines <- strsplit(x, "\n")[[1]]
  for (i in seq_along(lines)) {
    nums <- regmatches(lines[i], gregexpr("\\(\\d+\\)", lines[i]))[[1]]
    if (length(nums) >= 2) {
      num_vals <- as.integer(gsub("[()]", "", nums))
      if (identical(num_vals, seq_along(num_vals))) {
        labels <- rep(c("OLS", "RF", "2SLS"), length.out = length(nums))
        line   <- lines[i]
        for (j in seq_along(nums)) line <- sub(nums[j], labels[j], line, fixed = TRUE)
        lines[i] <- line
      }
    }
  }
  paste(lines, collapse = "\n")
}

postprocess_table <- function(x) rename_col_numbers_to_labels(move_notes_below_adjustbox(x))

# ── Step 7: Assemble table (same style as h2_snsv_d12.tex) ──────────────────
dir.create(file.path(ROOT, "output/reg"), showWarnings = FALSE, recursive = TRUE)
out_tex_b <- file.path(ROOT, "output/reg/test_h2_snsv_chem.tex")

f_label_b   <- "F-test (1st stage, clustered), Upstream coal mines (sum)"
f_vec_b     <- rep(c("", "", format(f_cl_b, nsmall = 2)), length(visit_outcomes))
el_b        <- list(f_vec_b)
names(el_b) <- f_label_b

dict_b <- c(
  "any_snsv"                        = "Sanitary visits",
  "any_tech"                        = "Technical assistance",
  "any_enfvisit_chem"               = "Enforcement visits",
  "any_smpl"                        = "Sample collection",
  "any_insp"                        = "Inspection",
  "num_coal_mines_upstream_sum"     = "Upstream coal mines (sum)",
  "fit_num_coal_mines_upstream_sum" = "Upstream coal mines (sum)",
  "post95:sulfur_unified_mean"      = "post95 $\\times$ Upstream sulfur \\%",
  "PWSID"                           = "CWS"
)

enfvisit_chem_pct <- 100 * mean(panel_d1$any_enfvisit_chem)

etable(models_b,
       title          = "TEST: Effect of Coal Mining on Regulator Visit Probability by Visit Type, Enforcement Visits Restricted to Arsenic/Nitrate/IOC Violations (D1 Downstream Sample, LPM)",
       label          = "tab:test_h2_snsv_chem",
       dict           = dict_b,
       drop           = "num_facilities",
       extralines     = el_b,
       fitstat        = ~n,
       notes          = paste0("TEST TABLE. D1 downstream sample (minehuc_downstream_of_mine = 1, minehuc_mine = 0). ",
                               "N = ", nrow(panel_d1), " CWS-years. Each panel of 3 columns (OLS, RF, 2SLS) ",
                               "reports a separate binary outcome: any visit of that type in a CWS-year. ",
                               "Sanitary visits are sanitary surveys and follow-up sanitary surveys. ",
                               "Technical assistance includes technical assistance, engineering ",
                               "determination/advice/plan review, and operation and maintenance visits. ",
                               "Enforcement visits include formal enforcement, investigation, and emergency ",
                               "assistance visits, restricted to CWS-years with a co-occurring arsenic (RULE_CODE 332), ",
                               "nitrate (331), or inorganic chemicals (333) violation on record (",
                               sprintf("%.2f", enfvisit_chem_pct), "% of panel; SDWA_SITE_VISITS.csv has no ",
                               "direct contaminant link, so the restriction is proxied by same-CWS-year co-occurrence ",
                               "with a chemical violation). Sample collection is sample collection visits. Inspection ",
                               "includes site inspections, regularly scheduled visits, and informal system ",
                               "inspections. Treatment: num_coal_mines_upstream_sum. ",
                               "Instrument: post95 x sulfur_unified_mean. SEs clustered at CWS level."),
       style.tex      = style.tex("aer", adjustbox = TRUE),
       tex            = TRUE,
       postprocess.tex = postprocess_table,
       file           = out_tex_b,
       replace        = TRUE)
cat(sprintf("\nTable saved to: %s\n", out_tex_b))
if (file.exists(out_tex_b) && file.info(out_tex_b)$size > 0) {
  cat("Output verified: file exists and is non-zero.\n")
} else {
  stop("Output file missing or empty — check etable() call.")
}
