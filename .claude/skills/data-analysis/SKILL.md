---
name: data-analysis
description: End-to-end R data analysis workflow for this project — load prod_vio_sulfur.parquet, explore, run fixest regressions, produce publication-ready LaTeX tables and PNG figures.
argument-hint: "[analysis goal or 'prod_vio_sulfur' for main dataset]"
allowed-tools: ["Read", "Grep", "Glob", "Write", "Edit", "Bash", "Task"]
---

# Data Analysis Workflow

End-to-end analysis in R: load the project dataset, explore, run regressions with `fixest`,
and produce publication-ready output.

**Input:** `$ARGUMENTS` — an analysis goal (e.g., "event study for nitrates, colocated sample")
or a dataset path (e.g., `clean_data/cws_data/prod_vio_sulfur.parquet`).

---

## Constraints

- Follow `.claude/rules/r-code-conventions.md` at all times
- Use `arrow::read_parquet()` to load the main dataset — never `read_csv()`
- All scripts go in `code/coal_mining_water_quality/`
- All outputs: tables → `output/reg/*.tex`; figures → `output/fig/*.png`
- Run `review-r` on the generated script before presenting results

---

## Workflow Phases

### Phase 1: Setup

1. Read `.claude/rules/r-code-conventions.md`
2. Read `CLAUDE.md` — confirm variable names and empirical spec
3. Create script with header block (name, purpose, inputs, outputs, author, date)
4. Load packages: `arrow`, `fixest`, `ggplot2`, `dplyr`, `data.table`
5. Load dataset and check schema:

```r
df <- arrow::read_parquet("clean_data/cws_data/prod_vio_sulfur.parquet")
str(df)   # PWSID must be <chr>, year must be <int>
```

### Phase 2: Exploratory Check

- Summary statistics on key treatment and outcome variables
- Count observations by `minehuc` classification
- Verify balanced panel structure (1985-2005)
- Check for suspiciously zero or NA outcome variables

### Phase 3: Regression

The canonical 2SLS spec (from CLAUDE.md):

```r
# OLS
ols <- feols(outcome ~ num_coal_mines_unified + num_facilities |
               PWSID + year + state,
             data = df_sub, cluster = ~ PWSID)

# Reduced form
rf  <- feols(outcome ~ post95:sulfur_unified + num_facilities |
               PWSID + year + state,
             data = df_sub, cluster = ~ PWSID)

# 2SLS
iv  <- feols(outcome ~ num_facilities | PWSID + year + state |
               num_coal_mines_unified ~ post95:sulfur_unified,
             data = df_sub, cluster = ~ PWSID)
```

Apply sample cuts as defined in CLAUDE.md.

### Phase 4: Output

**Tables:**
```r
etable(ols, rf, iv,
       file = "output/reg/[table_name].tex",
       tex = TRUE,
       notes = "Clustered SEs at PWSID level. N = XX.")
```

**Figures:**
```r
ggsave("output/fig/[fig_name].png", plot = p,
       width = 7, height = 5, dpi = 300, bg = "white")
```

### Phase 5: Review

Run `review-r` on the generated script. Address all Critical issues before presenting results.

---

## Sanity Checks Before Reporting

- First-stage F > 10 (weak instrument check)
- Reduced-form sign matches 2SLS sign
- Mining-related outcomes (nitrates, arsenic, inorganic chemicals, radionuclides): positive
- Placebo outcomes (total coliform, VOCs, SOCs): near-zero or insignificant
