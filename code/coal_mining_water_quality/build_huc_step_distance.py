# ============================================================
# Script: build_huc_step_distance.py
# Purpose: For every HUC12, compute directed flow-network distance (in steps,
#          capped at 8) to the nearest coal-mine HUC12, both upstream and
#          downstream, plus the count of distinct mine HUCs reachable within
#          each k = 1..8. Diagnostic input for the instrument-imputation x
#          step-depth grid (see instrument-imputation-and-step-depth-grid.md).
#
# Direction convention (tohuc = this HUC's immediate downstream neighbor):
#   - A mine M is UPSTREAM of huc H if walking forward along tohuc from M
#     reaches H (H receives M's water). steps_to_mine_upstream[H] = the
#     shortest such forward distance from any mine.
#   - A mine M is DOWNSTREAM of huc H if walking forward along tohuc from H
#     reaches M (H's water reaches M). steps_to_mine_downstream[H] = the
#     shortest such forward distance to any mine.
#   These two quantities are computed by two independent algorithms (a
#   per-mine forward walk, and a backward fan-out BFS via the upstream
#   adjacency) and cross-checked against each other below.
#
# Inputs:
#   Z:/ek559/sdwa_violations/WBD_HUC12_CONUS_pulled10262020/WBD_HUC12_CONUS_pulled10262020.shp
#     (huc12, tohuc attributes only, via pyogrio — no geometry)
#   clean_data/huc_coal_charac_geom_match.csv (minehuc classification)
# Outputs:
#   clean_data/huc_step_distance.parquet
# Author: EK  Date: 2026-09-13
# ============================================================

import pandas as pd
import geopandas as gpd
from pathlib import Path
from collections import deque

ROOT     = Path("Z:/ek559/mining_wq")
HUC_SHP  = Path("Z:/ek559/sdwa_violations/WBD_HUC12_CONUS_pulled10262020/WBD_HUC12_CONUS_pulled10262020.shp")
HUC_CSV  = ROOT / "clean_data/huc_coal_charac_geom_match.csv"
OUT_PATH = ROOT / "clean_data/huc_step_distance.parquet"
MAX_K    = 8

print("Reading HUC network attrs (huc12, tohuc only, no geometry)...")
huc_net = gpd.read_file(str(HUC_SHP), columns=["huc12", "tohuc"])
huc_net = pd.DataFrame(huc_net[["huc12", "tohuc"]]).copy()
huc_net["huc12"] = huc_net["huc12"].astype(str).str.strip()
huc_net["tohuc"] = huc_net["tohuc"].astype(str).str.strip()
print(f"  {len(huc_net):,} HUC12s")

dup_tohuc = huc_net.groupby("huc12")["tohuc"].nunique()
n_multi = (dup_tohuc > 1).sum()
print(f"  HUCs with >1 distinct tohuc: {n_multi} (expect 0)")

all_hucs  = set(huc_net["huc12"])
tohuc_map = dict(zip(huc_net["huc12"], huc_net["tohuc"]))

# Upstream adjacency (fan-out): huc -> list of immediate parents (hucs whose
# water flows into it), used for the backward BFS.
upstream_map = {}
for h, to in tohuc_map.items():
    if to in all_hucs:
        upstream_map.setdefault(to, []).append(h)

def is_terminal(h):
    return h not in all_hucs

# ── Mine HUC set ─────────────────────────────────────────────────────────
huc_csv = pd.read_csv(HUC_CSV, dtype={"huc12": str, "fromhuc": str, "tohuc": str})
mine_hucs = set(huc_csv.loc[huc_csv["minehuc"] == "mine", "huc12"].unique()) & all_hucs
print(f"Mine HUCs: {len(mine_hucs)}")

# ── Guard against non-terminating chains ────────────────────────────────
KNOWN_BAD_TERMINAL = {"031002010400", "031102060605", "050500030801"}
n_bad_terminal_present = sum(1 for h in KNOWN_BAD_TERMINAL if h in all_hucs)
print(f"Known-bad terminal HUCs present in network: {n_bad_terminal_present} / {len(KNOWN_BAD_TERMINAL)}")

# ── steps_to_mine_upstream + n_mine_upstream_within_k ──────────────────
# Forward walk from each mine along tohuc: every huc visited within MAX_K
# steps has that mine UPSTREAM of it. A cycle guard (visited_chain, local
# per mine) prevents non-terminating chains from looping.
print("Walking forward from each mine (mine-upstream-of-huc distances)...")
steps_up  = {h: -1 for h in all_hucs}       # nearest mine upstream of h
n_up      = {h: [0] * (MAX_K + 1) for h in all_hucs}
cycles_forward = []

for m in mine_hucs:
    cur, d = m, 0
    visited_chain = {m}
    while d < MAX_K:
        nxt = tohuc_map.get(cur)
        if nxt is None or is_terminal(nxt):
            break
        if nxt in visited_chain:
            cycles_forward.append((m, nxt, d + 1))
            break
        visited_chain.add(nxt)
        d += 1
        if steps_up[nxt] == -1 or d < steps_up[nxt]:
            steps_up[nxt] = d
        for k in range(d, MAX_K + 1):
            n_up[nxt][k] += 1
        cur = nxt

if cycles_forward:
    print(f"  WARNING: {len(cycles_forward)} cycles in forward walk; first 5: {cycles_forward[:5]}")
else:
    print("  No cycles in forward walk.")

# ── steps_to_mine_downstream + n_mine_downstream_within_k ──────────────
# Backward BFS (ancestors) from each mine via upstream_map: every huc
# visited within MAX_K steps has that mine DOWNSTREAM of it (its water
# eventually reaches the mine).
print("BFS backward from each mine (mine-downstream-of-huc distances)...")
steps_down = {h: -1 for h in all_hucs}
n_down     = {h: [0] * (MAX_K + 1) for h in all_hucs}

for m in mine_hucs:
    seen = {m: 0}
    q = deque([m])
    while q:
        h = q.popleft()
        d = seen[h]
        if d >= MAX_K:
            continue
        for parent in upstream_map.get(h, []):
            if parent not in seen:
                seen[parent] = d + 1
                q.append(parent)
    for h, d in seen.items():
        if h == m:
            continue
        if steps_down[h] == -1 or d < steps_down[h]:
            steps_down[h] = d
        for k in range(d, MAX_K + 1):
            n_down[h][k] += 1

# ── Cross-check: an independent per-huc forward walk should reproduce
# steps_to_mine_downstream (huc's own forward chain hits a mine) ────────
print("Cross-checking steps_to_mine_downstream via independent per-huc walk...")
steps_down_walk = {}
for h in all_hucs:
    if h in mine_hucs:
        continue
    cur, d = h, 0
    visited_chain = {h}
    dist = -1
    while d < MAX_K:
        nxt = tohuc_map.get(cur)
        if nxt is None or is_terminal(nxt) or nxt in visited_chain:
            break
        visited_chain.add(nxt)
        d += 1
        if nxt in mine_hucs:
            dist = d
            break
        cur = nxt
    steps_down_walk[h] = dist

mismatches = sum(
    1 for h in all_hucs if h not in mine_hucs
    and steps_down.get(h, -1) != steps_down_walk.get(h, -1)
)
print(f"  Cross-check mismatches: {mismatches} / {len(all_hucs) - len(mine_hucs)} (expect 0)")

# ── Assemble output ───────────────────────────────────────────────────
print("Assembling output table...")
rows = []
for h in all_hucs:
    is_mine = h in mine_hucs
    row = {
        "huc12": h,
        "steps_to_mine_upstream": 0 if is_mine else steps_up.get(h, -1),
        "steps_to_mine_downstream": 0 if is_mine else steps_down.get(h, -1),
    }
    for k in range(1, MAX_K + 1):
        row[f"n_mine_hucs_within_{k}_up"]   = n_up[h][k]
        row[f"n_mine_hucs_within_{k}_down"] = n_down[h][k]
    rows.append(row)

out = pd.DataFrame(rows)
out["huc12"] = out["huc12"].astype(str)

# ── Gate: reproduce the existing downstream_of_mine classification at 1 step ──
# downstream_of_mine (existing) = HUCs one step downstream of a mine, i.e.
# the mine is UPSTREAM of them by exactly 1 step -> steps_to_mine_upstream == 1.
d1_hucs_existing = set(huc_csv.loc[huc_csv["minehuc"] == "downstream_of_mine", "huc12"].unique())
d1_hucs_new = set(out.loc[out["steps_to_mine_upstream"] == 1, "huc12"])
overlap       = d1_hucs_existing & d1_hucs_new
only_existing = d1_hucs_existing - d1_hucs_new
only_new      = d1_hucs_new - d1_hucs_existing
print(f"\nGATE: downstream_of_mine reproduction at k=1 (steps_to_mine_upstream==1)")
print(f"  Existing D1 HUCs:         {len(d1_hucs_existing)}")
print(f"  New (steps_up==1) HUCs:   {len(d1_hucs_new)}")
print(f"  Overlap:                  {len(overlap)}")
print(f"  Only in existing:         {len(only_existing)}")
print(f"  Only in new:              {len(only_new)}")
if only_existing:
    print(f"    sample only-existing: {list(only_existing)[:10]}")
if only_new:
    print(f"    sample only-new:      {list(only_new)[:10]}")

print("\nDtypes before write:")
print(out.dtypes)

if OUT_PATH.exists():
    print(f"WARNING: {OUT_PATH} already exists — overwriting")

out.to_parquet(str(OUT_PATH), index=False, engine="pyarrow")
result = pd.read_parquet(str(OUT_PATH), engine="pyarrow")
print(f"\nWritten {len(result):,} rows x {result.shape[1]} columns to {OUT_PATH}")
