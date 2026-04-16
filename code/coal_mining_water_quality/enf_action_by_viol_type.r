# ============================================================
# Script: enf_action_by_viol_type.r
# Purpose: Distribution of specific enforcement action types conditional on
#          violation category (MR vs MCL) and contaminant group
#          (mining vs non-mining), 1985-2005
# Inputs:  clean_data/cws_data/prod_vio_sulfur.parquet (sample PWSID list)
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.csv
#          Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_REF_CODE_VALUES.csv
# Outputs: output/sum/enf_action_by_viol_type.tex
# Author: EK  Date: 2026-04-15
# ============================================================

.libPaths("Z:/ek559/RPackages")
library(arrow)
library(data.table)

# ── 0. Sample PWSID list — strictly downstream only ──────────────────────────
# Strictly downstream: minehuc_downstream_of_mine == 1 & minehuc_mine == 0
# (mirrors the "dwnstrm" sample cut in run_main_tables.r)
pws_sample <- as.data.frame(
  arrow::read_parquet("Z:/ek559/mining_wq/clean_data/cws_data/prod_vio_sulfur.parquet",
                      col_select = c("PWSID", "minehuc_downstream_of_mine", "minehuc_mine")))
pws_ids <- unique(pws_sample$PWSID[
  pws_sample$minehuc_downstream_of_mine == 1 & pws_sample$minehuc_mine == 0])
cat("Strictly downstream PWSIDs:", length(pws_ids), "\n")

# ── 1. Load violations (enforcement actions only) ─────────────────────────────
cat("Reading violations file...\n")
ve <- fread(
  "Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_VIOLATIONS_ENFORCEMENT.csv",
  select      = c("PWSID", "NON_COMPL_PER_BEGIN_DATE", "VIOLATION_CATEGORY_CODE",
                  "RULE_CODE", "ENFORCEMENT_ACTION_TYPE_CODE", "ENF_ACTION_CATEGORY",
                  "ENFORCEMENT_ID"),
  na.strings  = c("", "NA"),
  showProgress = FALSE
)

ve[, yr := as.integer(substr(NON_COMPL_PER_BEGIN_DATE, 7, 10))]
ve <- ve[PWSID %in% pws_ids & yr >= 1985 & yr <= 2005 & !is.na(ENFORCEMENT_ID)]
cat("Enforcement-action rows in sample (1985-2005):", nrow(ve), "\n")

# ── 2. Classify contaminant group ─────────────────────────────────────────────
mining_rules    <- c(331, 332, 333, 340)
nonmining_rules <- c(110, 111, 121, 122, 123, 140, 310, 320)
ve[, rule_num := suppressWarnings(as.numeric(RULE_CODE))]
ve[, cgrp := fcase(
  rule_num %in% mining_rules,    "mining",
  rule_num %in% nonmining_rules, "nonmining",
  default = "other"
)]

# ── 3. Load action-type descriptions ─────────────────────────────────────────
ref <- fread(
  "Z:/ek559/sdwa_violations/SDWA_latest_downloads/SDWA_REF_CODE_VALUES.csv",
  header = FALSE, col.names = c("VALUE_TYPE", "VALUE_CODE", "VALUE_DESCRIPTION")
)
ref <- ref[VALUE_TYPE == "ENFORCEMENT_ACTION_TYPE_CODE",
           .(VALUE_CODE, VALUE_DESCRIPTION)]

# ── 4. Build 4 conditioning groups ───────────────────────────────────────────
# Unit: enforcement action row (one per action; a violation can have multiple)
grp_names  <- c("mr_mine", "mr_non", "mcl_mine", "mcl_non")
grp_labels <- c("MR\\,(mining)", "MR\\,(non-mining)", "MCL\\,(mining)", "MCL\\,(non-mining)")

groups <- list(
  mr_mine  = ve[VIOLATION_CATEGORY_CODE == "MR"  & cgrp == "mining"],
  mr_non   = ve[VIOLATION_CATEGORY_CODE == "MR"  & cgrp == "nonmining"],
  mcl_mine = ve[VIOLATION_CATEGORY_CODE == "MCL" & cgrp == "mining"],
  mcl_non  = ve[VIOLATION_CATEGORY_CODE == "MCL" & cgrp == "nonmining"]
)

totals <- sapply(groups, nrow)
cat("\nGroup totals (enforcement actions):\n")
print(totals)

# ── 5. Compute shares for each group ─────────────────────────────────────────
tabs <- lapply(names(groups), function(nm) {
  g <- groups[[nm]]
  ct <- g[, .N, by = .(ENF_ACTION_CATEGORY, ENFORCEMENT_ACTION_TYPE_CODE)]
  ct[, share := 100 * N / nrow(g)]
  setnames(ct, c("N", "share"), paste0(c("n_", "s_"), nm))
  ct
})

# Merge all groups on category + code
wide <- Reduce(function(a, b)
  merge(a, b, by = c("ENF_ACTION_CATEGORY", "ENFORCEMENT_ACTION_TYPE_CODE"), all = TRUE),
  tabs)

# Fill NAs with 0
share_cols <- paste0("s_", grp_names)
n_cols     <- paste0("n_", grp_names)
for (col in c(share_cols, n_cols)) {
  set(wide, which(is.na(wide[[col]])), col, 0)
}

# Merge descriptions
wide <- merge(wide, ref,
              by.x = "ENFORCEMENT_ACTION_TYPE_CODE", by.y = "VALUE_CODE", all.x = TRUE)
wide[is.na(VALUE_DESCRIPTION), VALUE_DESCRIPTION := ENFORCEMENT_ACTION_TYPE_CODE]

# Max share across all groups (used to decide what to show)
wide[, max_share := pmax(s_mr_mine, s_mr_non, s_mcl_mine, s_mcl_non)]

# ── 6. Select rows for display ───────────────────────────────────────────────
# Keep all Formal and Resolving rows.
# For Informal: keep codes with max_share >= 1% in any group; lump rest as "Other".

formal_rows    <- wide[ENF_ACTION_CATEGORY == "Formal"]
resolving_rows <- wide[ENF_ACTION_CATEGORY == "Resolving"]
informal_keep  <- wide[ENF_ACTION_CATEGORY == "Informal" & max_share >= 1.0]
informal_other <- wide[ENF_ACTION_CATEGORY == "Informal" & max_share <  1.0]

# Summarise "Other informal" as a single lumped row
other_row <- data.table(
  ENFORCEMENT_ACTION_TYPE_CODE = "—",
  ENF_ACTION_CATEGORY          = "Informal",
  VALUE_DESCRIPTION            = "All other informal actions",
  s_mr_mine  = sum(informal_other$s_mr_mine),
  s_mr_non   = sum(informal_other$s_mr_non),
  s_mcl_mine = sum(informal_other$s_mcl_mine),
  s_mcl_non  = sum(informal_other$s_mcl_non),
  n_mr_mine  = sum(informal_other$n_mr_mine),
  n_mr_non   = sum(informal_other$n_mr_non),
  n_mcl_mine = sum(informal_other$n_mcl_mine),
  n_mcl_non  = sum(informal_other$n_mcl_non),
  max_share  = NA_real_
)

# Order within each section by average share (descending)
setorder(formal_rows,   -max_share)
setorder(informal_keep, -max_share)
setorder(resolving_rows,-max_share)

display <- rbindlist(list(formal_rows, informal_keep, other_row, resolving_rows),
                     use.names = TRUE, fill = TRUE)

cat("\nDisplay table:\n")
print(display[, .(ENF_ACTION_CATEGORY, ENFORCEMENT_ACTION_TYPE_CODE,
                  VALUE_DESCRIPTION, s_mr_mine, s_mr_non, s_mcl_mine, s_mcl_non)],
      nrows = 60)

# ── 7. Format helpers ─────────────────────────────────────────────────────────
fp  <- function(x) if (is.na(x)) "---" else if (x == 0) "0.0" else sprintf("%.1f", x)
fn  <- function(x) format(as.integer(x), big.mark = ",")
esc <- function(x) gsub("_", "\\\\_", x)  # escape underscores for LaTeX

# ── 8. Build LaTeX ────────────────────────────────────────────────────────────

header_comment <- paste0(
  "% ============================================================\n",
  "% Table: Enforcement Action Types by Violation Category and Contaminant Group\n",
  "% Purpose: Distribution of specific enforcement actions (share of all actions\n",
  "%          in each group), 1985-2005. Mining = rules 331/332/333/340;\n",
  "%          non-mining = rules 110/111/121-123/140/310/320.\n",
  "% Source:  SDWA_VIOLATIONS_ENFORCEMENT.csv\n",
  "% N (enforcement actions): MR mining=", fn(totals["mr_mine"]),
  ", MR non-mining=", fn(totals["mr_non"]),
  ", MCL mining=", fn(totals["mcl_mine"]),
  ", MCL non-mining=", fn(totals["mcl_non"]), "\n",
  "% ============================================================\n"
)

col_spec <- "llp{5.8cm}rrrr"

lines <- c(
  "\\begin{table}[htbp]",
  "\\centering",
  "\\caption{Enforcement Action Types by Violation Category and Contaminant Group, 1985--2005}",
  "\\label{tab:enf_action_type}",
  "\\small",
  paste0("\\begin{tabular}{", col_spec, "}"),
  "\\hline\\hline",
  paste0("\\textbf{Cat.} & \\textbf{Code} & \\textbf{Description} & ",
         "\\textbf{MR} & \\textbf{MR} & \\textbf{MCL} & \\textbf{MCL} \\\\"),
  paste0(" & & & \\textbf{mining} & \\textbf{non-mining} & ",
         "\\textbf{mining} & \\textbf{non-mining} \\\\"),
  paste0(" & & & \\textit{(N=", fn(totals["mr_mine"]), ")} & \\textit{(N=",
         fn(totals["mr_non"]), ")} & \\textit{(N=", fn(totals["mcl_mine"]),
         ")} & \\textit{(N=", fn(totals["mcl_non"]), ")} \\\\"),
  "\\hline"
)

# Sections
sections <- list(
  list(label = "\\textit{Formal enforcement}", rows = formal_rows),
  list(label = "\\textit{Informal enforcement}", rows = rbindlist(list(informal_keep, other_row), fill=TRUE)),
  list(label = "\\textit{Resolving (compliance achieved)}", rows = resolving_rows)
)

for (sec in sections) {
  lines <- c(lines,
    "\\addlinespace[4pt]",
    paste0("\\multicolumn{7}{l}{", sec$label, "} \\\\"),
    "\\addlinespace[2pt]"
  )
  for (i in seq_len(nrow(sec$rows))) {
    r   <- sec$rows[i]
    cat <- if (i == 1) r$ENF_ACTION_CATEGORY else ""
    cd  <- esc(r$ENFORCEMENT_ACTION_TYPE_CODE)
    dsc <- esc(r$VALUE_DESCRIPTION)
    lines <- c(lines,
      paste0(cat, " & ", cd, " & ", dsc, " & ",
             fp(r$s_mr_mine), " & ", fp(r$s_mr_non), " & ",
             fp(r$s_mcl_mine), " & ", fp(r$s_mcl_non), " \\\\")
    )
  }
}

notes <- paste0(
  "\\textit{Notes:} Unit of observation is the enforcement action row in ",
  "SDWA\\_VIOLATIONS\\_ENFORCEMENT.csv. Entries show the share (\\%) of all enforcement ",
  "actions within each column group that are of the specified type. Column groups are defined by ",
  "violation category (MR = monitoring/reporting; MCL = maximum contaminant level) and contaminant ",
  "group (mining = rules 331 nitrate, 332 arsenic, 333 inorganic chemicals, 340 radionuclides; ",
  "non-mining = rules 110/111 total coliform, 121--123/140 surface/groundwater rule, 310 VOCs, 320 SOCs). ",
  "Sample: CWS in the coal mining analysis panel, 1985--2005. ",
  "A violation may generate multiple enforcement actions; rows are enforcement actions, not violations. ",
  "Enforcement categories follow EPA SDWIS classification: ",
  "\\textit{Formal} = legally binding instruments (administrative orders, consent decrees, penalties, ",
  "civil/criminal referrals); ",
  "\\textit{Informal} = advisory actions and notices (notices of violation, public notification requests, ",
  "compliance meetings, technical assistance visits, intentional no-action); ",
  "\\textit{Resolving} = closure actions recording that the system returned to compliance. ",
  "Code prefixes: S = state-initiated; E = federally initiated. ",
  "SFJ = State Formal Notice of Violation (coded Informal in SDWIS because it precedes formal legal action). ",
  "``All other informal actions'' aggregates codes each below 1\\% in every column group."
)

lines <- c(lines,
  "\\hline\\hline",
  "\\end{tabular}",
  "\\begin{minipage}{\\linewidth}",
  "\\vspace{4pt}",
  "\\footnotesize",
  notes,
  "\\end{minipage}",
  "\\end{table}"
)

# ── 9. Write output ───────────────────────────────────────────────────────────
out_path <- "Z:/ek559/mining_wq/output/sum/enf_action_by_viol_type.tex"
writeLines(c(header_comment, lines), out_path)
cat("\nOutput written to:", out_path, "\n")
cat("=== DONE ===\n")
