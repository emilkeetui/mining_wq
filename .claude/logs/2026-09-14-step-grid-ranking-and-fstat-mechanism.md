# Session: 2026-09-14 — Step-grid results: re-rendering, cell ranking, F-stat mechanism

## Objective
Re-render the 96-cell instrument-imputation x flow-step-depth grid from
`.claude/logs/2026-09-13-instrument-step-grid.md` without re-estimating, then answer three
follow-up questions the raw terminal blocks don't answer directly: (1) which single cell in
the grid is cleanest (main significant, placebo null, both first stages strong), (2) what are
the next-best two flow-step depths `k` and why, and (3) why do the main and placebo arms'
first-stage F-statistics diverge so sharply at high `k`.

## Approach
1. Wrote `code/coal_mining_water_quality/render_step_instrument_grid.r` — reads only
   `step_grid_results.parquet` / `step_grid_firststage.parquet` (no re-estimation, no writes)
   and reprints Blocks 2-8 + the Step 5 reproduction checks. Block 1 is skipped: its inputs
   (`n_hucs_covered`, `cov_share`, `n_hucs_linked`, `any_active_mine_in_window`) were never
   persisted to either saved parquet.
2. Ran it end-to-end (exit 0, 788 lines). Output reproduced the 2026-09-13 log's anchor
   numbers exactly (k=1 main A-full F=33.48, main B F=16.97/22.54, the 385/340-CWS deviation
   note, and the BOTH SIG / NULL BOTH / VACUOUS verdict pattern) — confirms the saved
   parquets are a faithful, re-renderable record of that session's estimation.
3. Scanned all 96 (k x column x FE) cells in `step_grid_results.parquet` /
   `step_grid_firststage.parquet` for cells where at least one of the three MR outcomes
   (nitrates, arsenic, inorganic chemicals) is significant at p<0.1 in the main arm, and both
   arms' clustered first-stage F >= 10 (i.e. not "VACUOUS" per the origin script's own flag).
4. Ranked candidates by (count of significant main MR outcomes) minus (count of significant
   placebo MR outcomes), tie-broken by main-arm F-stat.
5. Investigated the F-stat asymmetry by pulling `num_coal_mines_linked_sum` (the first-stage
   outcome / second-stage endogenous regressor) directly from `step_instruments.parquet` and
   comparing its mean/SD/max by arm and k.

## Correction made mid-session
**"Colocated" mislabel.** In an earlier answer this session, the k=2/A-full cell was
described as a "colocated + downstream" sample, borrowing the CLAUDE.md production-pipeline
sample-cut glossary. That is wrong for this diagnostic. Per
`~/.claude/plans/instrument-imputation-and-step-depth-grid.md` line 28 and
`build_step_instruments.py:217-219`, **both arms of the step-grid exclude any PWSID whose
intake HUC12 is itself a mine HUC** before the arm/instrument table is built at all — i.e.
colocated utilities never enter either arm's sample, at any k. The main arm here is strictly
"downstream of a mine, not colocated," not "colocated + downstream." This diagnostic's arm
definitions are a distinct construct from the production paper's `minehuc_mine`/
`minehuc_downstream_of_mine` sample cuts and should not be described with that glossary's
labels.

## Findings

### 1. The single cleanest cell in the grid
Out of 96 cells, exactly **one** has main significant on >=1 MR outcome, **zero** of the three
placebo MR outcomes significant, and both first stages >= F=10:

**k=2, A-full, PWSID+year+state x year FE** — F_main=50.01, F_placebo=53.17
- Main: arsenic 3.11 (1.52), p=.042**; nitrates 3.28 (1.73), p=.058*; inorganic chemicals 2.00
  (1.60), p=.213 (not sig)
- Placebo: all three null (p=.42, .26, .17)

Caveat: only 2 of 3 MR outcomes significant (not inorganic chemicals, which CLAUDE.md flags
as a primary mining-related outcome), and it is 1 of 96 cells — plausibly a multiple-testing
artifact rather than a robust signal, especially set against the grid's headline pattern
(placebo significant in 66% of MR cells overall, see 2026-09-13 log).

### 2. Next-best two k's: k=8 and k=7 (same cut, same FE)
Ranking all cells by (# main MR outcomes significant) - (# placebo MR outcomes significant),
tie-broken by main-arm F, the next tier after k=2 is a three-way tie at score=2 (3 of 3 main
MR outcomes significant, 1 of 3 placebo outcomes significant) between k=4, k=7, k=8, all under
**A-full, PWSID+year+state x year**. Tie-broken by main-arm F-stat: k=8 (F=53.30) and k=7
(F=46.44) rank above k=4 (F=28.24).

| k | main: arsenic | main: inorganic | main: nitrates | placebo: arsenic | placebo: inorganic | placebo: nitrates | F_main | F_placebo |
|---|---|---|---|---|---|---|---|---|
| 8 | 0.39** (p=.047) | 0.37* (p=.069) | 0.57*** (p=.008) | p=.221 | p=.302 | **0.003**(sig) | 53.30 | 147.28 |
| 7 | 0.52* (p=.050) | 0.46* (p=.096) | 0.79*** (p=.007) | p=.357 | p=.450 | **0.007**(sig) | 46.44 | 136.36 |

At both k=7 and k=8, arsenic and inorganic chemicals are clean (main significant, placebo
null); the one outcome that keeps the cell from being fully clean at high k is **nitrates**,
whose placebo coefficient is significant at both depths. This matches the 2026-09-13 log's
note that nitrates is the MR outcome most prone to leaking through the placebo even after
state x year FE is added. Restricting to arsenic + inorganic chemicals only (CLAUDE.md's
designated primary mining-related pair, since it explicitly excludes nitrates-only framing)
would make k=7 and k=8 read as fully clean, on top of k=2.

### 3. Why the first-stage F-stat is so much higher for placebo than main at high k
Mechanism is the HUC12 flow-network topology, not instrument quality. Per CLAUDE.md, each
HUC12 has exactly one downstream neighbor (`tohuc`) — walking downstream is a single linear
chain, so a placebo utility can pick up mines from at most `k` HUCs at depth `k`. Walking
upstream is a fan: each HUC can have multiple tributaries, each with their own tributaries, so
the upstream-reachable HUC set grows combinatorially and unevenly across watersheds as `k`
grows.

Pulled `num_coal_mines_linked_sum` (the second-stage endogenous regressor / first-stage
outcome) directly from `step_instruments.parquet` by arm and k:

| k | arm | N | mean | SD | max |
|---|---|---|---|---|---|
| 1 | main | 7,140 | 0.66 | 1.22 | 8 |
| 1 | placebo | 8,502 | 0.47 | 1.04 | 15 |
| 7 | main | 30,091 | 2.69 | **7.20** | **105** |
| 7 | placebo | 37,831 | 0.92 | 1.73 | 29 |
| 8 | main | 32,120 | 3.20 | **8.83** | **123** |
| 8 | placebo | 40,958 | 0.99 | 1.86 | 37 |

At k=1 the two arms' exposure variables look similar. By k=7-8, the main arm's cumulative
upstream mine count has a heavy right tail (SD 7-9, max 100+) while the placebo's downstream
chain count stays compact (SD <2, max <40). The first stage regresses this variable on a
single PWSID-year-averaged instrument (`post95 x sulfur`); that instrument cannot track the
sum of ARP-driven declines across dozens of heterogeneous upstream mines nearly as well as it
tracks a short, bounded downstream chain. The residual variance for the main arm therefore
balloons with k even though its point estimate is also larger in magnitude (coef ~= -2.64 vs
-0.60 at k=8) — and since F = (coef/SE)^2, the SE inflation from that residual variance
dominates, leaving the placebo's tighter, more homogeneous outcome with the higher F-stat
despite its smaller coefficient. This also explains why the pattern is reversed at k=1 (main
F=33.48 > placebo F=5.17 WEAK): the upstream fan hasn't had room to diverge yet at low k, so
main's exposure variable is still tight, while the placebo arm's low-k purity screen (zero
mines upstream) shrinks its sample and adds its own noise.

## Verification
- [x] Render script output matches 2026-09-13 log's anchor numbers exactly (no drift between
  the saved parquets and the original run)
- [x] Colocated-exclusion claim checked against both the plan document and the actual
  `build_step_instruments.py` drop logic, not asserted from memory
- [x] F-stat mechanism checked against real `step_instruments.parquet` dispersion statistics,
  not asserted from topology alone

## Open Questions / Blockers
None. This is an interpretive/diagnostic exercise on a terminal-only deliverable — no
production pipeline files, tables, or figures were touched.

## Next Steps
None initiated. If the k=7/k=8 (arsenic + inorganic chemicals only) or k=2 result is to be
promoted toward a production specification, that would need a new plan (multiple-testing
treatment across the 8 k's, and a decision on whether nitrates' placebo failure is
disqualifying or excludable by outcome-scope).
