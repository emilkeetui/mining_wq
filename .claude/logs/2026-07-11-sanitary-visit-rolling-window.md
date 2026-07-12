# Session: 2026-07-11 — Sanitary visit rolling 12-month window

## Objective
Build a version of output/reg/monitoring_retesting_hazard.tex cols 1-3 with dependent
variable = "sanitary visit in t+1," using a true rolling 365-day window (exact test date
to exact visit date) rather than calendar-year adjacency.

## Changes Made
- code/coal_mining_water_quality/monitoring_retesting_sanitary_visit.r: new script,
  cols 1-3 only, outcome = sanitary visit in following calendar year (v1, calendar-year
  based). Ran successfully; output/reg/monitoring_retesting_sanitary_visit.tex written.
- Follow-up: user asked to add year FE to cols 2-3 (col 1 stays no-FE). Done, re-ran, confirmed.
- Follow-up: user asked for a true rolling 12-month window using exact dates, since
  cws_6year_review.parquet is year-collapsed (VALUE = mean of within-year readings; no
  single test date). Requires a new measurement-level (non-year-collapsed) build.

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| Build new full-population measurement-date parquet rather than reusing existing downstream/IOC-only file | Existing clean_data/cws_6year_review_measurement_level_syr2.parquet is restricted to downstream-only CWSs + 14 IOC chemicals; monitoring_retesting_hazard.r uses the full mining sample + all 28 chemicals. User confirmed via AskUserQuestion they want the matching full-population build. |
| New build reads SYR2 (.mdb) only, standard (non-Ravalli) pipeline | year<=2005 filter in R script is entirely within SYR2 window; cws_6year_review.parquet (read by the R script) is the standard non-Ravalli output. |
| Outcome = visit in (sample_date, sample_date+365] via data.table non-equi join | True rolling window using exact dates on both sides, per user request. |

## Verification Results
- [x] New Python build script (cws_6year_review_measurement_dates_full.py) runs end-to-end:
      2,038,342 measurement rows, 9 chemicals survive detection-rate filter (arsenic,
      barium, chromium, nitrate, selenium, alpha/beta particles, radium, uranium),
      written to clean_data/cws_6year_review_measurement_level_full.parquet
- [x] Updated R script runs end-to-end after fixing two bugs:
      (1) sample_date read from parquet as POSIXct, not Date -- caused a type-mismatch
      warning and 0 LPM rows; fixed with as.Date(sample_date).
      (2) data.table non-equi join direction bug: sv_dt[lpm_dt, on=.(visit_dt>=window_start,
      visit_dt<=window_end)] silently fabricates the join-column value (window_start) on
      UNMATCHED rows instead of returning NA, so "mean(outcome)==1" (every row falsely
      matched). Fixed by joining the other direction: lpm_dt[sv_dt, on=.(window_start<=
      visit_dt, window_end>=visit_dt), nomatch=NULL] (inner join, x-table = lpm_dt).
- [x] output/reg/monitoring_retesting_sanitary_visit.tex regenerated: N=1,120,579/
      1,113,388/821,410; mean(sanitary_visit_next365)=0.257.

## Design Decisions (cont.)
| Decision | Rationale |
|----------|-----------|
| data.table non-equi join: put the "base" table (lpm_dt, one row per test) as x, the interval-defining table (sv_dt, one row per visit) as i, with nomatch=NULL | X[Y, on=ineq] returns one row per Y row and back-fills the ON columns with Y's own values when unmatched instead of NA -- easy silent-bug trap. Always verify non-equi matches on a small hand-built example before trusting at scale. |

## Follow-up: restrict to downstream-only, 5 IOCs
- cws_6year_review_measurement_dates_full.py: CHEMICALS trimmed to
  ["arsenic","barium","chromium","nitrate","selenium"]; added downstream-only PWSID
  filter from prod_vio_sulfur.parquet (minehuc_downstream_of_mine==1 & minehuc_mine==0,
  349 PWSIDs). Output: 2,635 downstream-only measurement rows.
- Bug caught and fixed: initially computed the 10% detection-rate filter on the
  downstream-only subsample (small N per chemical), which spuriously dropped
  arsenic/chromium/selenium (their downstream-only detection rates were below 10% by
  sample-size noise even though national rates are 36.9%/15.3%/12.2%, all above
  threshold). Fixed by computing detection rates on the national (pre-downstream-filter)
  read first, matching the existing pattern in cws_6year_review_measurement_dates.py's
  build_chemical_panel/report_detection_rates -- always check this file's docstring
  before reimplementing detection-rate filtering logic.
- Re-ran monitoring_retesting_sanitary_visit.r: N=1,319/1,314/1,056,
  mean(sanitary_visit_next365)=0.376. No regressor significant once CWS+year FE added
  (small sample). Notes/header updated to describe downstream-only + 5-IOC sample
  (previously incorrectly claimed "same population as Table monitoring_retesting").

## Open Questions / Blockers
- None.

## Next Steps
- None outstanding for this task.
