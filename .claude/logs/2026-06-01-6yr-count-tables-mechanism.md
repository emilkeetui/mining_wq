# Session: 2026-06-01 — 6yr count tables: add mean & max VALUE as outcomes

## Objective
Extend `run_count_tables()` in `cws_6year_review_huc02fe.r` so that the `cnt_*` tables
include three outcome columns per chemical: `num_measurements`, mean `VALUE`, and max `VALUE`.
Motivation: test whether cumulative upstream coal production shifts both measurement frequency
and typical/peak concentration (reduced-form mechanism check).

## Research Design Decisions
- Mean and max VALUE go on the LEFT (dependent variables), not as controls — bad control
  problem if placed on RHS alongside cumulative production.
- Simultaneity concern noted: if CWSs reduce tests strategically, fewer obs mechanically
  changes mean/max. Proper test would be 2SLS with VALUE instrumented by coal production.
  User chose reduced-form cnt tables first; 2SLS left for later.

## Where We Stopped
Discovered that the parquet (`clean_data/cws_6year_review.parquet`) does NOT contain a
`max_value` column. The Python build script (`cws_6year_review.py`, line ~408) aggregates
to PWSID × CHEMID_name × YEAR using only `mean` for VALUE:

```python
agg_spec = dict(
    VALUE            = ("VALUE", "mean"),
    DETECT           = ("DETECT", "max"),
    UNITS            = ("UNITS", "first"),
    num_measurements = ("VALUE", "count"),
)
```

## Next Steps (pick up here)
1. **Option A — add max to Python build script**: Add `VALUE_max = ("VALUE", "max")` to
   `agg_spec` in `cws_6year_review.py`, re-run the build, and write a new parquet.
   Then use `VALUE_max` in the R regression formulas.
   - Check: does parquet already exist? YES — `clean_data/cws_6year_review.parquet`
   - Must confirm with user before overwriting (data safeguard rule).

2. **Option B — compute max on the fly in R**: If max per PWSID×chem×year cannot be
   recovered from the already-collapsed data, Option A is required.

   The collapsed parquet only has `VALUE` (mean) — individual measurements are lost.
   Therefore **Option A is required**: must re-run `cws_6year_review.py` with max added.

3. After parquet is updated:
   - Add `fml_max <- VALUE_max ~ coal_prod_upstream_cumsum_10mst + num_facilities | PWSID + huc02^year`
   - Extend `run_count_tables()` to estimate and collect three models per chemical:
     `num_measurements`, `VALUE` (mean), `VALUE_max` (max)
   - Update `dict_cnt` to label new outcomes
   - Update table notes
   - Run script, verify `.tex` outputs

## Files to Touch
- `code/coal_mining_water_quality/cws_6year_review.py` — add `VALUE_max` to agg_spec
- `clean_data/cws_6year_review.parquet` — will be overwritten (confirm with user first)
- `code/coal_mining_water_quality/cws_6year_review_huc02fe.r` — add max formula + extend run_count_tables()
