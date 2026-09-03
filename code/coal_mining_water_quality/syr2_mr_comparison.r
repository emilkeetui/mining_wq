# ============================================================
# Script: syr2_mr_comparison.r
# Purpose: Compare MR/MCL violation rates between utilities with
#          and without SYR2 readings for inorganic chemicals
#          of interest (arsenic, nitrate, selenium, barium)
# Inputs:  clean_data/cws_data/prod_vio_sulfur.parquet
#          clean_data/cws_6year_review.parquet
# Outputs: output/sum/syr2_mr_comparison.tex
# Author: EK  Date: 2026-07-01
# ============================================================

library(arrow)
library(dplyr)
library(tidyr)

# ── Load data ────────────────────────────────────────────────
panel <- read_parquet("clean_data/cws_data/prod_vio_sulfur.parquet")
syr2  <- read_parquet("clean_data/cws_6year_review.parquet")

cat("Panel:", nrow(panel), "rows,", n_distinct(panel$PWSID), "unique utilities\n")
cat("SYR2 :", nrow(syr2),  "rows,", n_distinct(syr2$PWSID),  "unique utilities\n")

# ── Restrict to strictly downstream 2SLS sample ──────────────
panel <- panel |>
  filter(minehuc_downstream_of_mine == 1 & minehuc_mine == 0)

cat("Downstream sample:", nrow(panel), "rows,", n_distinct(panel$PWSID), "unique utilities\n")

# ── Identify groups ──────────────────────────────────────────
# Target chemicals for SYR2 reading eligibility
target_chems <- c("arsenic", "nitrate", "selenium", "barium")

# Group 1: utilities with >= 1 SYR2 reading for a target chemical
pws_with_readings <- syr2 |>
  filter(
    CHEMID_name %in% target_chems,
    !is.na(num_measurements) & num_measurements > 0
  ) |>
  distinct(PWSID) |>
  pull(PWSID)

# States that have at least one such utility
states_with_readings <- syr2 |>
  filter(PWSID %in% pws_with_readings) |>
  distinct(STATE_CODE) |>
  pull(STATE_CODE)

cat("Group 1 utilities (has target-chemical SYR2 reading):", length(pws_with_readings), "\n")
cat("States with any target-chemical SYR2 reading:", length(states_with_readings), "\n")

# Assign groups using panel's STATE_CODE
pwsid_state <- panel |> distinct(PWSID, STATE_CODE)

group_assign <- pwsid_state |>
  mutate(
    group = case_when(
      PWSID %in% pws_with_readings ~ 1L,
      STATE_CODE %in% states_with_readings & !(PWSID %in% pws_with_readings) ~ 2L,
      TRUE ~ NA_integer_
    )
  ) |>
  filter(!is.na(group))

cat("Group 1:", sum(group_assign$group == 1), "utilities\n")
cat("Group 2:", sum(group_assign$group == 2), "utilities\n")

# ── Attach group to panel ────────────────────────────────────
panel_grp <- panel |>
  inner_join(group_assign |> select(PWSID, group), by = "PWSID")

# ── Construct outcome indicators per PWSID-year ──────────────
# MR binary: any of arsenic_MR, nitrates_MR, inorganic_chemicals_MR > 0
# MCL binary: any of arsenic_MCL, nitrates_MCL, inorganic_chemicals_MCL > 0
# Mean violations count: sum of the six indicators above per year

panel_grp <- panel_grp |>
  mutate(
    any_mr  = (arsenic_MR_share > 0 | nitrates_MR_share > 0 |
               inorganic_chemicals_MR_share > 0) & !is.na(arsenic_MR_share),
    any_mcl = (arsenic_MCL_share > 0 | nitrates_MCL_share > 0 |
               inorganic_chemicals_MCL_share > 0) & !is.na(arsenic_MCL_share),
    # Count of violation categories triggered (0–6)
    vio_count = as.integer(arsenic_MR_share > 0 & !is.na(arsenic_MR_share)) +
                as.integer(nitrates_MR_share > 0 & !is.na(nitrates_MR_share)) +
                as.integer(inorganic_chemicals_MR_share > 0 & !is.na(inorganic_chemicals_MR_share)) +
                as.integer(arsenic_MCL_share > 0 & !is.na(arsenic_MCL_share)) +
                as.integer(nitrates_MCL_share > 0 & !is.na(nitrates_MCL_share)) +
                as.integer(inorganic_chemicals_MCL_share > 0 & !is.na(inorganic_chemicals_MCL_share))
  )

# ── PWSID-level collapse ─────────────────────────────────────
pws_outcomes <- panel_grp |>
  group_by(PWSID, group) |>
  summarise(
    ever_mr_9705  = as.integer(any(any_mr  & year >= 1997 & year <= 2005, na.rm = TRUE)),
    ever_mr_8505  = as.integer(any(any_mr  & year >= 1985 & year <= 2005, na.rm = TRUE)),
    ever_mcl_9705 = as.integer(any(any_mcl & year >= 1997 & year <= 2005, na.rm = TRUE)),
    ever_mcl_8505 = as.integer(any(any_mcl & year >= 1985 & year <= 2005, na.rm = TRUE)),
    mean_num_vio  = mean(vio_count[year >= 1997 & year <= 2005], na.rm = TRUE),
    .groups = "drop"
  )

# ── Group-level means ────────────────────────────────────────
group_means <- pws_outcomes |>
  group_by(group) |>
  summarise(
    n_cws         = n(),
    ever_mr_9705  = mean(ever_mr_9705,  na.rm = TRUE),
    ever_mr_8505  = mean(ever_mr_8505,  na.rm = TRUE),
    ever_mcl_9705 = mean(ever_mcl_9705, na.rm = TRUE),
    ever_mcl_8505 = mean(ever_mcl_8505, na.rm = TRUE),
    mean_num_vio  = mean(mean_num_vio,  na.rm = TRUE),
    .groups = "drop"
  )

cat("\nGroup means:\n")
print(group_means)

# ── t-tests for differences ──────────────────────────────────
g1 <- filter(pws_outcomes, group == 1)
g2 <- filter(pws_outcomes, group == 2)

pvals <- list(
  ever_mr_9705  = t.test(g1$ever_mr_9705,  g2$ever_mr_9705)$p.value,
  ever_mr_8505  = t.test(g1$ever_mr_8505,  g2$ever_mr_8505)$p.value,
  ever_mcl_9705 = t.test(g1$ever_mcl_9705, g2$ever_mcl_9705)$p.value,
  ever_mcl_8505 = t.test(g1$ever_mcl_8505, g2$ever_mcl_8505)$p.value,
  mean_num_vio  = t.test(g1$mean_num_vio,  g2$mean_num_vio)$p.value
)

cat("\np-values for group differences:\n")
for (nm in names(pvals)) cat(" ", nm, ":", round(pvals[[nm]], 4), "\n")

# ── Build LaTeX table ────────────────────────────────────────
fmt_pct  <- function(x) sprintf("%.1f\\%%", x * 100)
fmt_mean <- function(x) sprintf("%.2f", x)
star_str <- function(p) {
  if (p < 0.01) "^{***}" else if (p < 0.05) "^{**}" else if (p < 0.1) "^{*}" else ""
}

g1_row <- filter(group_means, group == 1)
g2_row <- filter(group_means, group == 2)

diffs <- c(
  ever_mr_9705  = g1_row$ever_mr_9705  - g2_row$ever_mr_9705,
  ever_mr_8505  = g1_row$ever_mr_8505  - g2_row$ever_mr_8505,
  ever_mcl_9705 = g1_row$ever_mcl_9705 - g2_row$ever_mcl_9705,
  ever_mcl_8505 = g1_row$ever_mcl_8505 - g2_row$ever_mcl_8505,
  mean_num_vio  = g1_row$mean_num_vio  - g2_row$mean_num_vio
)

rows <- list(
  list(label = "Ever MR violation, 1997--2005",
       g1 = fmt_pct(g1_row$ever_mr_9705), g2 = fmt_pct(g2_row$ever_mr_9705),
       diff = fmt_pct(diffs["ever_mr_9705"]), p = pvals$ever_mr_9705),
  list(label = "Ever MR violation, 1985--2005",
       g1 = fmt_pct(g1_row$ever_mr_8505), g2 = fmt_pct(g2_row$ever_mr_8505),
       diff = fmt_pct(diffs["ever_mr_8505"]), p = pvals$ever_mr_8505),
  list(label = "Ever MCL violation, 1997--2005",
       g1 = fmt_pct(g1_row$ever_mcl_9705), g2 = fmt_pct(g2_row$ever_mcl_9705),
       diff = fmt_pct(diffs["ever_mcl_9705"]), p = pvals$ever_mcl_9705),
  list(label = "Ever MCL violation, 1985--2005",
       g1 = fmt_pct(g1_row$ever_mcl_8505), g2 = fmt_pct(g2_row$ever_mcl_8505),
       diff = fmt_pct(diffs["ever_mcl_8505"]), p = pvals$ever_mcl_8505),
  list(label = "Mean annual violations (count, 0--6), 1997--2005",
       g1 = fmt_mean(g1_row$mean_num_vio), g2 = fmt_mean(g2_row$mean_num_vio),
       diff = fmt_mean(diffs["mean_num_vio"]), p = pvals$mean_num_vio)
)

build_table <- function(rows, n1, n2) {
  header <- paste0(
    "\\begin{table}[htbp]\n",
    "\\centering\n",
    "\\caption{MR and MCL violation rates by SYR2 contaminant reporting status}\n",
    "\\label{tab:syr2_mr_comparison}\n",
    "\\begin{adjustbox}{max width=\\textwidth}\n",
    "\\begin{tabular}{lrrrr}\n",
    "\\toprule\n",
    " & \\multicolumn{1}{c}{(1)} & \\multicolumn{1}{c}{(2)} & \\multicolumn{1}{c}{Diff.} & \\multicolumn{1}{c}{$p$-value} \\\\\n",
    " & Has SYR2 reading & No SYR2 reading & (1)$-$(2) & \\\\\n",
    "\\hline\n"
  )

  body <- ""
  for (i in seq_along(rows)) {
    r <- rows[[i]]
    stars <- star_str(r$p)
    diff_cell <- if (nzchar(stars)) paste0(r$diff, "$", stars, "$") else r$diff
    if (i == length(rows)) body <- paste0(body, "\\hline\n")
    body <- paste0(
      body,
      r$label, " & ", r$g1, " & ", r$g2, " & ", diff_cell,
      " & ", sprintf("%.3f", r$p), " \\\\\n"
    )
  }

  footer <- paste0(
    "\\bottomrule\n",
    "\\end{tabular}\n",
    "\\end{adjustbox}\n",
    "\\begin{minipage}{\\linewidth}\n",
    "\\vspace{4pt}\n",
    "\\footnotesize\n",
    "\\raggedright\n",
    "\\textit{Notes:} Sample restricted to utilities strictly downstream of a coal mine. ",
    "\\textit{Has SYR2 reading}: at least one Six-Year Review contaminant reading ",
    "for arsenic, nitrate, selenium, or barium. ",
    "\\textit{No SYR2 reading}: utility is in a state where at least one utility ",
    "has a SYR2 reading but the utility itself does not. ",
    "MR violation: IOC monitoring and reporting violation. ",
    "MCL violation: IOC maximum contaminant violation. ",
    "Mean annual violations: sum of MR and MCL violation indicators ",
    "across arsenic, nitrate, and inorganic chemicals categories (maximum of 6 per utility-year). ",
    "$N$ utilities: group 1 = ", n1, ", group 2 = ", n2, ". ",
    "Diff.~stars from two-sample $t$-test: ",
    "*** $p<0.01$, ** $p<0.05$, * $p<0.1$.\n",
    "\\end{minipage}\n",
    "\\end{table}\n"
  )

  # Presentation companion: same tabular, notes block omitted entirely
  # (summary statistics carry no clustering/FE; only the diff-stars legend
  # would apply, but the note text itself is dropped per the "no notes"
  # convention for summary tables) -- see
  # .claude/logs/2026-08-31-presentation-notes-tables.md.
  footer_present <- paste0(
    "\\bottomrule\n",
    "\\end{tabular}\n",
    "\\end{adjustbox}\n",
    "\\end{table}\n"
  )

  list(main = paste0(header, body, footer),
       present = paste0(header, body, footer_present))
}

tex_variants <- build_table(rows, g1_row$n_cws, g2_row$n_cws)
tex <- tex_variants$main

out_path <- "output/sum/syr2_mr_comparison.tex"
writeLines(tex, out_path)
cat("\nTable written to:", out_path, "\n")

out_path_present <- sub("\\.tex$", "_present.tex", out_path)
writeLines(tex_variants$present, out_path_present)
cat("Presentation table written to:", out_path_present, "\n")

cat("\n--- LaTeX preview ---\n")
cat(tex)
