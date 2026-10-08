# Session: 2026-09-23 — MSHA accident instrument (Part 50 data build)

## Objective
Build mine-accident variables (1985–2005) from MSHA Part 50 accident/injury files
as a candidate instrument: sum of accidents at coal mines within 2 HUC12 flow
steps upstream (main arm) and, separately, downstream (placebo arm) of each CWS intake.
Keep all record-level data for future instruments (water-related accidents,
shutdown-type accidents, total injuries, fatalities).

## Changes Made
- clean_data/msha_part50_raw/: 42 Part 50 zips (CAIM/CCTI 1985–2005) + unzipped txt,
  Part 50 handbook (.doc), MSHA OGI Accidents.zip (2000+, used only for code labels),
  Accidents_Definition_File.txt.

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| Raw downloads under clean_data/msha_part50_raw/ instead of raw_data/msha/part50/ | protect-raw-data hook only exempts sdwa_cws_pop and census; user chose Option A for now, will add hook exemption + $CLAUDE_PROJECT_DIR hook paths later (Option B) |
| Code labels from OGI Accidents.txt (codes + text side by side) | Handbook has layout but no code tables |
| Water-related = classification 15/16 (impoundment/inundation) or immediate-notify 04/10 | direct water-quality channel; exclusion-restriction risk |
| Shutdown proxy = immediately reportable accident (notify codes 01–12) | Part 50 has no shutdown field; these trigger 103(k) orders |
| Reuse build_step_instruments.py intake linkage + BFS at K=2, both directions, without modifying that script | consistency with existing k2 variables |

## Incidents
- A `cd` into code/ left the shell cwd in a subfolder; relative hook paths in settings.json then failed and blocked all Bash/Edit/Write. Fixed by resetting cwd to root. Option B will make hook paths absolute.

- code/coal_mining_water_quality/build_msha_accidents.py: new build script.
- clean_data/msha_accidents_records.parquet (273,385 x 64), msha_accidents_mine_year.parquet
  (32,471 x 18), cws_data/msha_accidents_k2.parquet (64,572 PWSID-years x 28).
- Mine locations from raw_data/msha/Mines.txt (mines.csv covers only 4,231/7,741 accident mine IDs).

## Verification Results
- [x] 42/42 files downloaded, 0 failures
- [x] Parser validated vs OGI 2000–2005: 45,985/45,987 doc numbers matched; mine_id, date,
      no_injuries 100%; degree 99.1%, classification 97.5%. immed_notify 75% / days_lost 73%
      mismatches are all 13-vs-'?' and 0-vs-blank (benign).
- [x] Coal fatalities 67 (1985) → 22 (2005), consistent with MSHA published totals
- [x] Mine HUC12 sjoin agrees 100% with production panel on 3,806 shared mines
- [x] k2 file covers 12,492/12,492 k=2 main-arm analysis rows; PWSID chr / year int in R
- Quality score: 85 (runs, validated, schema OK; not yet used in any regression)

## Open Questions / Blockers
- serious_reportable (immediately reportable, codes 01–11) is ~70% roof falls (code 08) —
  probably too broad as a "shutdown" proxy; user to choose definition.
- Narrative files (Part 50) not downloaded; would help classify water-related events.
- Hook Option B (exempt raw_data/msha/part50 + $CLAUDE_PROJECT_DIR hook paths) pending user.

## Next Steps
- Choose instrument definition(s); first-stage check against upstream k=2 mine regressor.

---
**[COMPACTION NOTE � 2026-09-24T16:40:03Z]**  
Auto-compact triggered. Active plan: `k2-updn-annual-production-robustness.md`.  
Resume by reading CLAUDE.md + most recent plan + `git log --oneline -5`.
---

## 2026-09-24 — Hook Option B + move Part 50 downloads to raw
- User approved hook change on condition that raw files still cannot be edited/deleted without explicit permission.
- protect-raw-data.py: added msha/part50 exemption; exempt dirs now accept NEW files only (Write/Edit of an existing
  file, cp/redirect onto an existing file, archive overwrite flags all blocked); `..` paths resolved before the
  exemption check; PowerShell delete/move/write verbs added. 23/23 allow/block test cases pass.
- settings.json: hook commands use "$CLAUDE_PROJECT_DIR/.claude/hooks/..."; PreToolUse matcher now includes
  PowerShell. Verified live from the code/ subfolder (Bash and PowerShell deletes blocked).
- Moved clean_data/msha_part50_raw/ to raw_data/msha/part50/ (87 files, md5 identical); removed the clean_data copy.
- build_msha_accidents.py: RAW_DIR now raw_data/msha/part50; input resolution + CAIM1995 parse (11,754 rows) verified.
  Full rebuild not run (would overwrite the 3 clean_data outputs; inputs byte-identical so outputs would not change).
- Known hook false positive: any shell command that mentions a raw_data path and uses a redirect (e.g. heredoc
  into a log) is blocked. Workaround: Write/Edit tools, or Python without redirects.
- Discussion: roof falls appear in classification 07 (49,076) and immediate-notify 08 (35,706); 34,931 overlap;
  96% of notify-08 roof falls are accident-only (no injury). No Part 50 field records closure; test via
  raw_data/msha/MinesProdQuarterly (hours/production by mine-quarter).
- User position: water-related accidents are not an exclusion violation (channel is water quality). Open point:
  regressor is mine count/production, so a spill's direct effect would load onto beta unless regressor is redefined.
