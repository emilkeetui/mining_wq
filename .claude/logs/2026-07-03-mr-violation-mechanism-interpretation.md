# Session: 2026-07-03 — Interpreting why MR violations rise with mining

## Objective
Trace the chains of supporting results to explain *why* upstream coal mining
raises MR (monitoring/reporting) violations. Reconcile three tables the user
found contradictory: `mr_concentration_lag`, `monitoring_retesting_hazard`,
`syr2_mr_comparison`. No code changes — interpretation/advice only.

## Key finding: the unifying mechanism
`near_mcl = (ratio >= 0.5) & (ratio < 1.0)` (defined in
`cws_6year_review_measurement_dates.py:358`) is the **SDWA increased-monitoring
trigger**. A nitrate detection >=50% of MCL bumps a system to quarterly
monitoring for the following year. So a high reading mechanically *raises the
number of required tests*, raising the chance of missing one -> MR violation,
**without the system reducing testing**. This "regulatory-burden/trigger"
channel jointly predicts "high reading -> MR violation" AND "high reading ->
more testing," dissolving the apparent contradiction.

## Design Decisions / Conclusions
| Question | Resolution |
|----------|-----------|
| Which retesting spec is reliable? | Col 2 (LPM + **CWS FE**), the only sig estimate (+0.0187**). Hazard cols 4-6 have **no CWS FE** -> cross-sectional artifact. Reliable answer: testing *rises* after a high reading. |
| Does retesting contradict `mr_concentration_lag`? | No. MR = failure vs a *schedule* that scales with contamination. Test more AND violate more simultaneously. |
| Nitrate but not arsenic? | Nitrate has a sharp single-detection quarterly trigger; arsenic pre-2006 MCL high, monitored ~3-yearly, no sharp trigger, 0.010 MCL binds only from 2006 (outside sample). Mechanism predicts exactly where it appears. |
| Placebo (past window) negative | Confirms ordering: high reading precedes MR violation, not vice versa. Currently `\input` but never interpreted in draft. |
| `syr2_mr_comparison` (SYR2 systems have more MR) | Exposure/selection, NOT negligence. MR violation requires enrollment in IOC monitoring; SYR2 reading is a marker of that enrollment. Draft line 399 over-reads it ("more negligent CWSs"). |
| Strategic-avoidance vs burden mechanism | Positive retesting result cuts AGAINST strategic hiding (which predicts testing falls). Weight of evidence (positive retesting, no MCL exceedances, less formal enforcement, more sanitary visits) favors burden/trigger channel. Recommend reframing draft away from "regulator pivot" toward burden. |

## Diligence-after-violation event study — built and run (2026-07-03)
New script `code/coal_mining_water_quality/mr_reading_event_study.r`, mirrors
`sanitary_visit_event_study.r`'s stacked design (CWS FE, ref month -1,
window [-6,+6]). Reused `clean_data/mr_concentration_lag_measurement.parquet`
for reading dates (no new build step). Outcome = any SYR2 reading in
CWS-month; onsets = MR violations, split into 4 chemical groups (Arsenic,
Nitrate, Pooled IOC, Any target chemical).

**Design fix during implementation:** original spec used `PWSID + month_idx`
FE (matching the sanitary-visit script exactly) but blew up with SEs in the
thousands. Root cause: heavy onset repetition per CWS within the narrow
SYR2-covered window (~11 onsets/CWS for Pooled IOC) makes many (PWSID,
month_idx) cells appear identically across overlapping onset windows with
different rel_month, leaving rel_month collinear with the FE. Switched to
`PWSID + cal_year` FE (coarser, matches this project's usual convention —
`mr_concentration_lag.r` uses PWSID+YEAR, not month FE). This resolved it;
only the sparse Arsenic group (23 onsets) still drops one collinear dummy
(rendered as "--" in the table, not "NA").

**Onset restriction:** onset dates restricted to 1998-07 through 2005-06 so
the full [-6,+6] window falls inside SYR2 coverage (1998-2005) — avoids
false "no reading" near sample edges from data censoring, not CWS behavior.

**Result: no support for the diligence hypothesis.** All four groups show
flat-to-negative coefficients across the whole window relative to month -1,
with no post-onset increase and no coefficients reaching significance in a
clean post-onset pattern (Nitrate has a few marginal 10% hits scattered on
both sides of onset, not a post-onset jump). Pre-window vs post-window
reading probabilities (summary table) are similar or slightly lower
post-onset for every group (e.g. Any target chemical: 3.58% pre vs 2.31%
post). This is consistent with the burden/trigger mechanism and inconsistent
with "CWSs get cited then become diligent."

Outputs (all verified non-zero, script exits 0):
- `output/reg/mr_reading_event_study.tex`
- `output/fig/es_reading_onset.png`
- `output/sum/mr_reading_onset_summary.tex`

## Magnitude-trigger mechanism FALSIFIED; DETECT re-spec also null (2026-07-03)
User objected: the 50%-MCL burden/trigger story can't explain arsenic (arsenic
never approaches its MCL). Data check confirmed and worsened it:
- near_mcl (ratio>=0.5) count: arsenic 0, selenium 0, barium 0, chromium 0,
  nitrate ONLY 3 (of 855). Max ratios: arsenic 0.22, Se 0.30, Ba 0.17, Cr 0.25,
  nitrate 0.55. above_mcl = 0 everywhere (confirms nothing exceeds MCL).
- => The significant nitrate near_mcl coef (0.59**) in mr_concentration_lag.tex
  is identified off 3 observations. The magnitude-trigger mechanism is
  mechanically impossible for all IOCs and a 3-obs artifact for nitrate.
  I over-weighted it in the earlier interpretation. **Retract the 50%-MCL
  channel as a general mechanism.**
- Also: arsenic concentration does NOT predict arsenic MR (mean_conc_z ~0, ns),
  so the mining->arsenic-MR path does not run through arsenic's own reading.

Built `code/coal_mining_water_quality/mr_detection_lag.r` to test the DETECTION
trigger (any detect -> waiver loss -> more monitoring -> MR), which unlike
magnitude CAN operate for arsenic. Outputs: output/reg/mr_detection_lag.tex,
output/reg/mr_detection_lag_placebo.tex (both verified, script exits 0 after
switching etable from do.call to direct calls per the known fixest 0.14 bug).
**Result: NULL.** DETECT -> same-contaminant MR, forward window:
  arsenic 1yr +0.0137 (p .18), 6mo +0.0070 (p .35);
  nitrate 1yr +0.0024 (p .91), 6mo -0.0058 (p .73);
  pooled IOC 1yr +0.0096 (p .10), 6mo -0.0021 (p .70). Placebos all null.
Detection trigger not supported (though in-window MR outcomes are rare -> limited
power). Combined read: NO reading-level micro-mechanism (magnitude or detection)
links contamination to MR. The robust mining->MR effect lives only at the
CWS x year panel level => most consistent with diffuse system-level compliance
burden, NOT a contaminant-specific regulatory trigger. Paper should drop the
threshold-trigger claim and frame MR as a system-level burden outcome.

## Open Questions / Next Steps
- Possible follow-ups offered (not yet run): (a) bundling test — do arsenic-MR
  and Se/Ba/Cr-MR events co-occur (same PWSID/date)? If so "arsenic MR" is a
  bundled-IOC-panel artifact, not arsenic-specific. (b) broad burden test — does
  mining raise MR violations across contaminant classes unrelated to mining
  chemistry (general "stressed system misses samples" signal)?
- Draft edits pending user decision: reframe MR narrative toward burden/trigger
  channel; interpret placebo sign flip explicitly; downgrade
  `syr2_mr_comparison` to a selection caveat; incorporate the new event study
  as the closing piece of evidence against the diligence/self-monitoring-avoidance
  story.

## Verification
- `mr_reading_event_study.r` run end-to-end via
  `"C:/Program Files/R/R-4.5.2/bin/Rscript.exe" --vanilla`, exit 0.
- All 3 output files confirmed to exist and be non-zero (script's own checks
  + manual Read of .tex/.png).
- Earlier portion of session: read-only interpretation review of 3 .tex tables
  + 4 source scripts + main.tex, no files written.
