# Verification Protocol

**Never mark a task "done" without having run the code and confirmed expected output.**

## After Editing an R Script

1. Run end-to-end:
   ```bash
   "C:/Program Files/R/R-4.6.1/bin/x64/Rscript.exe" --vanilla code/coal_mining_water_quality/<script>.r
   ```
2. Confirm the script exits 0 (no error message)
3. Confirm expected output file exists (e.g., `.tex` in `output/reg/`, `.png` in `output/fig/`)
4. For regression scripts: spot-check one coefficient — verify sign and rough magnitude
   are consistent with the identifying assumption (ARP reduced high-sulfur mine production)

## After Editing a Python Script

1. Run with the full venv path:
   ```bash
   "Z:/ek559/nys_algal_bloom/NYS algal bloom/code2/Scripts/python.exe" code/coal_mining_water_quality/<script>.py
   ```
2. Confirm exit 0
3. Confirm parquet/csv output exists in `clean_data/`
4. Check row count printed by the script — flag if 0 or suspiciously small
5. If the output is consumed by an R script: load it in R and run `str(df)` to confirm
   PWSID is character and year is integer

## After Generating a LaTeX Table

1. Visually inspect the `.tex` file — confirm column headers match the intended sample cut
2. Confirm sample size N in the footnote is plausible
3. If the table is embedded in a paper: compile the paper and confirm no `??` references
4. Confirm formatting matches `table-figure-formatting.md`: left-justified notes,
   no scientific notation, consistent significant figures, decimal-aligned
   numeric columns, capitalized display labels, ×100 scaling on binary-outcome
   coefficients, and FE checkmark row omitted (with FEs stated in notes) only
   when every column shares the same fixed effects

## Hard Gates (block completion if any fail)

- Script exits with non-zero code → must fix before marking done
- Output file does not exist → must fix before marking done
- Output row count is 0 → must investigate and fix
- PWSID loaded as integer in R after parquet read → must fix Python writer

## Econometric Sanity Checks

After generating 2SLS tables:
- First-stage F-statistic > 10 (weak instrument rule of thumb)
- Reduced-form coefficient sign matches 2SLS sign
- Mining-related outcomes (inorganic chemicals, radionuclides) show
  positive and significant 2SLS estimates in the primary specification
- Do NOT use VOC, SOC, or total coliform as chemical placebos — coal mining affects them
  directly or indirectly (SOC PAHs produced by mining; VOCs lower where farming is displaced
  by mining; total coliform co-moves with inorganic chemicals via nitrate nutrients).
  Use temporal or geographical placebos instead.
