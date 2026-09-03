# Session: 2026-09-02 — mr_concentration_lag_logit table

## Objective
Create a nitrate OLS+Logit table (4 cols: OLS 1-yr/6-mon, Logit 1-yr/6-mon) using the
downstream-of-mine measurement-level sample from mr_concentration_lag.r
(clean_data/mr_concentration_lag_measurement.parquet), styled/structured identically to
mr_concentration_lag_national_downstream_states.tex.

## Key Context
- mr_concentration_lag.tex: 6-col OLS table (arsenic/nitrate/pooled-IOC), downstream-mining
  sample, FE checkmark rows shown, CWS terminology.
- mr_concentration_lag_national_downstream_states.tex: 4-col OLS+Logit, nitrate only,
  national sample restricted to downstream-2SLS-sample states, FE dropped w/ note,
  "Utility" terminology (inconsistent with CLAUDE.md CWS rule).
- User confirmed via AskUserQuestion: nitrate only / 4 cols (exact structural mirror);
  filename `mr_concentration_lag_logit`.

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| Use CWS (not "Utility") for FE/clustering labels | CLAUDE.md hard rule; matches mr_concentration_lag.r's own convention since sample is from that script |
| Do not apply mr_concentration_lag.r's global ×100 recode before subsetting | Logit spec needs raw 0/1 outcome; instead build an LPM copy (nit_df_lpm) matching national_downstream_states.r's df_lpm pattern |
| Skip wiring into writeup/main.tex | Not requested; placement/prose is an editorial call, flagged as follow-up |

## Verification Results
- [x] Script runs end-to-end (exit 0, R 4.6.1)
- [x] Output exists at expected path: output/reg/mr_concentration_lag_logit.tex + _present.tex
- [x] Row counts plausible: nitrate N=851 (LPM cols), N=88/40 (logit cols, after FE-singleton drops)
- [x] Checked against table-figure-formatting.md / table-notes-conventions.md: passes

## Open Questions / Blockers
- Whether to wire the new table into writeup/main.tex via \outreg{} (both sibling tables are wired in) — deferred, not requested

## Next Steps
- None outstanding; awaiting user decision on writeup wiring
