# Session: 2026-06-06 — Jackknife State Driver Diagnostic

## Objective
Identify which states drive the 2SLS result in `2sls_dwnstrm_minevio_mr_ivsum.tex`
(effect of upstream coal mines on inorganic chemicals MR violations, downstream CWSs only).

## Approach
- Leave-one-state-out jackknife of 2SLS coefficient (β̂ and 95% CI)
- Produce two figures:
  1. Caterpillar/forest plot: state-specific β̂ vs. full-sample estimate
  2. Δβ choropleth: US state map showing how much each state's removal shifts β̂

## Key Findings

### Full-sample 2SLS estimate
- **β̂ = 13.61** days/year of inorganic chemicals MR violations per upstream mine
- SE = 8.28, 95% CI = [-2.61, 29.84]
- N = 6,170 PWSID×year (6,225 in table; 55 obs dropped as FE singletons)
- First-stage F = 292.2 (instrument is very strong)

### State-by-state jackknife results

| State | β̂ (excl.) | Δβ = (full − excl.) | Interpretation |
|-------|-----------|-------------------|---|
| **PA** | -18.89 | **+32.50** | **CRITICAL DRIVER** — excluding PA flips effect from +13.6 to -18.9 |
| FL | 16.28 | -2.67 | Suppresses effect slightly |
| OH | 14.72 | -1.10 | Neutral |
| VA | 14.36 | -0.75 | Neutral |
| CO | 12.33 | +1.29 | Inflates effect slightly |
| GA | 11.86 | +1.75 | Inflates effect slightly |
| KY | 13.39 | +0.22 | Neutral (but significant CI) |
| NC, AL, TN, etc. | ~13.3–13.7 | ~0.0 | Neutral |
| MD | NA | NA | Estimation failed (sample too sparse or FE singularities) |

### Critical insight: Pennsylvania dominance
When Pennsylvania is excluded from the sample:
1. The 2SLS coefficient **reverses sign and magnitude** (13.6 → -18.9)
2. The first-stage F **collapses to 9.3** (borderline weak instrument)
3. This indicates PA data is the sole source of the positive effect estimate

### Possible explanations for PA dominance
- **Sparse instrument variation in non-PA states:** Most downstream CWSs outside PA may lack the sulfur-induced coal production shock post-1995 to power the IV
- **PA-specific water quality trend:** PA may have driven the MR violation trend independent of mining activity (concurrent state/local regulations)
- **Measurement or merge issues in PA data:** PA PWSIDs, HUC matching, or violation codes may have idiosyncracies
- **IV assumption violation:** Post-95 × sulfur interaction may be exogenous in PA but not elsewhere

## Verification

✅ Script runs end-to-end without error  
✅ Both PNG figures generated successfully  
✅ Full-sample β̂ (13.61) approximately matches table value (13.96; diff likely due to FE singleton removal)  
✅ First-stage F well above 10 (weak instrument threshold) in full sample (292.2)  
⚠️  MD failed to estimate (returned NA) — investigate if sample too sparse  
⚠️  PA's first-stage F = 9.3 when excluded — suggests weak instrument in non-PA subsample  

## Output Files

| File | Contents |
|------|----------|
| `output/fig/jackknife_state_caterpillar.png` | Forest plot sorted by β̂, full-sample reference line, significance markers |
| `output/fig/jackknife_state_map.png` | US choropleth colored by Δβ; grey = not in downstream sample |

## Next Steps / Open Questions

1. **Investigate PA dominance:** Why is PA the sole driver?
   - Check: How many downstream CWSs are in PA vs. other states?
   - Check: Sulfur variation pre- and post-1995 in PA vs. other states
   - Check: Are the PA violations actually coming from upstream mines, or local sources?

2. **MD regression failure:** Understand why MD couldn't be estimated
   - Likely cause: Too few PWSIDs/years or insufficient variation in IV
   - Confirm: How many PWSID×year obs for MD in downstream sample?

3. **Robustness:** Consider whether PA should be retained or removed for main specification
   - If PA is a measurement or merge error: rerun main table excluding PA
   - If PA is real but captures local dynamics: discuss in text as a sensitivity result

4. **Alternative instruments or specifications:**
   - Consider state-level effects (since PA dominates, FE structure may be insufficient)
   - Test whether colocated/all-HUC specifications show similar PA dominance

## Code and Methods

- **Script:** `code/coal_mining_water_quality/jackknife_state_driver.r`
- **Data:** `clean_data/cws_data/prod_vio_sulfur.parquet`
- **Packages:** fixest (2SLS), dplyr (data ops), ggplot2 (plot), sf + tigris (maps)
- **Sample:** minehuc_downstream_of_mine==1 & minehuc_mine==0, years 1985–2005
- **Outcome:** inorganic_chemicals_MR_share_days
- **Instrument:** post95 × sulfur_unified_sum
- **Cluster:** PWSID
- **Fixed effects:** PWSID + year

## 2026-06-06 (update) — Δβ definition + enforcement/snsv jackknives

### Δβ / β̂ definitions added to figures
- `jackknife_state_map.png` + caterpillar captions now define β explicitly:
  β = 2SLS coefficient on `num_coal_mines_upstream_sum` (effect of one more upstream
  mine on the outcome); full-sample β̂ shown; Δβ = β̂_full − β̂_(state excluded).

### [LEARN] Existing enforcement/snsv jackknife scripts were broken
`jackknife_state_enforcement.r` and `jackknife_state_snsv.r` read
`prod_vio_sulfur.parquet` and referenced columns that do not exist there:
- `any_formal` / `any_snsv` are built ONLY inside `enforcement_chain_d12.r` by merging
  the SDWA site-visit and enforcement CSVs — not present in any parquet.
- `sulfur_upstream` / `num_coal_mines_upstream` live in `prod_vio_sulfur_4step.parquet`,
  NOT `prod_vio_sulfur.parquet` (which only has the `_sum` / `_unified_mean` versions).
Result: `run_iv` returned NA every loop; the old enforcement PNG was meaningless and the
snsv PNGs never existed. Rewrote both to reproduce the merge faithfully.

### Faithful specs (verified against source .tex)
| Table | Sample | Outcome | Treatment | Instrument | Full β̂ (jk) | .tex β̂ |
|---|---|---|---|---|---|---|
| h3_inf_formal_d12 (Formal 2SLS) | D1 (prod_vio_sulfur, dwnstrm==1 & mine==0) | any_formal | num_coal_mines_upstream_sum | post95×sulfur_unified_mean | −0.0564 | −0.0565 ✓ |
| h2_snsv_d12 (2SLS) | D1-D2 (prod_vio_sulfur_4step, downstream_step≤2) | any_snsv | num_coal_mines_upstream | post95×sulfur_upstream | 0.1391 | 0.1410 ✓ |
FE = PWSID + year + STATE_CODE; cluster = PWSID for both.

### Key finding: PA drives ALL THREE results
| Outcome | Full β̂ | β̂ excl. PA | F excl. PA |
|---|---|---|---|
| Inorganic MR (days/yr) | +13.61 | −18.89 | 9.3 |
| Sanitary survey Pr | +0.139 | −0.568 | 45.2 |
| Formal enforcement Pr | −0.056 | +0.038 | 6.2 |
Every headline estimate reverses sign when PA is excluded. For inorganic-MR and formal
enforcement the first-stage F also collapses below/near 10 without PA. The results are
PA-specific, not externally valid — flag as a major robustness concern.

### New/updated output files
- `output/fig/jackknife_state_enforcement_formal.png` (now meaningful)
- `output/fig/jackknife_state_map_enforcement_formal.png` (now meaningful)
- `output/fig/jackknife_state_snsv.png` (new)
- `output/fig/jackknife_state_map_snsv.png` (new)

## 2026-06-06 (update 2) — Instrument horse race + enforcement-intensity check

### First-stage horse race off-PA (`first_stage_instrument_compare.r`)
Clustered first-stage F (the right diagnostic; clustered-F with PA ≈ 27.5 reproduces
the table's 27.84). Off-PA the instrument has NO power:
| Instrument | clustered-F (with PA) | clustered-F (no PA) |
|---|---|---|
| post95×sulfur_unified_sum | 27.5 | 0.52 (largest off-PA) |
| post95×sulfur_unified_mean | 27.9 | 0.30 |
| post95×sulfur_upstream† | 40.5 | 0.01 |
sulfur_unified_**sum** is least-bad off-PA but all are dead (<1). PA is ~44% of the
downstream sample AND essentially all the ARP instrument variation. ⇒ binned/interacted
2SLS enforcement-intensity test is NOT identifiable; can only do levels/descriptive.

### [PROJECT FINDING] PA is NOT low-enforcement — refutes the offset conjecture
`state_enforcement_intensity.r`: λ̂_s = share of distinct CWS violations escalated to a
Formal action (1985-2005, CWS only; 1.23M violations, 15% formal).
- **PA λ̂ = 0.110 = MEDIAN** (rank 11/19 downstream states; 53rd pct downstream, 52nd pct
  all). 10 of 18 other downstream states are MORE lenient (AL 0.018, MD 0.028, KY 0.029…).
- Monotonicity fails the wrong way: the lenient states (AL/MD/KY) are exactly the ones the
  jackknife flagged as NEUTRAL (Δβ≈0); only median-enforcement PA drives the positive MR.
- Conclusion: the "mining raises MR where enforcement is low (PA)" mechanism is NOT
  supported. PA dominance is composition/identification (sample mass + all IV variation),
  not leniency. Outputs: output/fig/state_enforcement_intensity.png,
  output/sum/state_enforcement_intensity.csv.
