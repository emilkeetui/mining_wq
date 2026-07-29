# ============================================================
# Script: backcast_validation.py
# Purpose: Backcasting validation per writeup/cws_exposure_backcasting.tex sec 3.8.
#          (1) Leave-one-anchor-out (LOAO): withhold an era of reported-population
#          anchors, re-run the production Step 3 estimator (imported, not
#          reimplemented) on the survivors, and compare the prediction to the
#          held-out truth. Folds are era-blocks rather than individual anchors
#          because 2010/2011 are near-duplicates (corr 0.998, 90.8% identical
#          values) and a per-anchor LOO would predict one from the other with
#          ~zero error -- a vacuous pass.
#          (2) Leave-one-decade-out (LODO): withhold the 2000 and 2010 block
#          apportionments, predict each from both neighboring decennials via the
#          same PEP chaining used in Step 2, and compare to the true apportionment.
#          Tests the kappa-constant assumption with no reported figure in the loop.
# Inputs:  clean_data/cws_data/cws_pop_anchors.parquet
#          clean_data/cws_data/cws_capture_ratio_annual.parquet
#          clean_data/cws_data/cws_geopop_annual.parquet
#          clean_data/cws_data/cws_geopop_decennial.parquet
#          clean_data/cws_data/cws_county_shares.parquet
#          clean_data/cws_data/pep_county_population.parquet
# Outputs: clean_data/cws_data/cws_loao_validation.parquet
#          clean_data/cws_data/cws_lodo_validation.parquet
# Author: EK  Date: 2026-07-29
# ------------------------------------------------------------
# See plan Z:\Users\ek559\.claude\plans\backcast-leave-one-out-validation.md.
# LOAO reuses compute_ratios()/carry_ratio() from build_cws_reported_ratio.py
# unmodified -- verified by direct call that they reproduce the committed
# cws_capture_ratio_annual.parquet's pop_served_hat bit-for-bit (max abs diff
# 0.0) when run on the full anchor set, so importing them for a filtered subset
# is exactly "the production estimator with less information", not a parallel
# code path.
# ============================================================

import sys
from pathlib import Path

import numpy as np
import pandas as pd

PROJECT_ROOT = Path(__file__).resolve().parents[2]
CLEAN_CWS = PROJECT_ROOT / "clean_data" / "cws_data"
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_cws_reported_ratio as ratio_mod  # noqa: E402

ANCHORS = CLEAN_CWS / "cws_pop_anchors.parquet"
RATIO_ANNUAL = CLEAN_CWS / "cws_capture_ratio_annual.parquet"
GEOPOP_ANNUAL = CLEAN_CWS / "cws_geopop_annual.parquet"
GEOPOP_DECENNIAL = CLEAN_CWS / "cws_geopop_decennial.parquet"
COUNTY_SHARES = CLEAN_CWS / "cws_county_shares.parquet"
PEP = CLEAN_CWS / "pep_county_population.parquet"

LOAO_OUT = CLEAN_CWS / "cws_loao_validation.parquet"
LODO_OUT = CLEAN_CWS / "cws_lodo_validation.parquet"

# Era-block folds (writeup sec 3.8; design decision 1 in the plan).
LOAO_FOLDS = {
    "A_2010_2011": [2010, 2011],
    "B_2006": [2006],
    "C_SYR2": list(range(1998, 2006)),
}

LODO_TARGETS = {
    2000: {"forward": 1990, "backward": 2010},
    2010: {"forward": 2000, "backward": 2020},
}


# ---------------------------------------------------------------- LOAO ----
def run_loao(anchors: pd.DataFrame, tier_map: pd.DataFrame, annual: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for fold_name, held_years in LOAO_FOLDS.items():
        held = anchors[anchors["year"].isin(held_years)]
        survivors = anchors[~anchors["year"].isin(held_years)]
        survivor_systems = set(survivors["PWSID"])
        held = held[held["PWSID"].isin(survivor_systems)]
        if held.empty:
            print(f"  [{fold_name}] WARNING: no eligible held-out anchors, skipping")
            continue

        ratios = ratio_mod.compute_ratios(
            survivors[["PWSID", "year", "pop_reported", "source"]], annual
        )
        grid = ratio_mod.carry_ratio(ratios, annual)

        pred = held.merge(
            grid[["PWSID", "year", "pop_served_hat"]], on=["PWSID", "year"], how="left"
        )
        n_missing = pred["pop_served_hat"].isna().sum()
        if n_missing:
            print(f"  [{fold_name}] WARNING: {n_missing} held-out anchors have no prediction "
                  f"(outside the 1990-2024 backbone window) -- dropped")
        pred = pred.dropna(subset=["pop_served_hat"])
        pred["fold"] = fold_name
        pred = pred.merge(tier_map, on="PWSID", how="left")
        pred["signed_err"] = pred["pop_served_hat"] - pred["pop_reported"]
        pred["ape"] = (pred["signed_err"] / pred["pop_reported"].replace(0, np.nan)).abs()
        rows.append(pred[["fold", "PWSID", "year", "geo_tier", "pop_reported",
                           "pop_served_hat", "signed_err", "ape"]])

        for tier, g in pred.groupby("geo_tier"):
            agg_pred, agg_true = g["pop_served_hat"].sum(), g["pop_reported"].sum()
            agg_pct = (agg_pred - agg_true) / agg_true if agg_true else np.nan
            print(f"  [{fold_name}][{tier}] n={len(g)} systems={g['PWSID'].nunique()} "
                  f"agg_err={agg_pct:+.1%} median_APE={g['ape'].median():.1%} "
                  f"mean_APE={g['ape'].mean():.1%} within25pct={(g['ape']<=0.25).mean():.1%}")

    return pd.concat(rows, ignore_index=True)


# ---------------------------------------------------------------- LODO ----
def blend_pep_from_anchor(theta_anchor: pd.DataFrame, pep: pd.DataFrame, years: list) -> pd.DataFrame:
    """P_blend[PWSID, year] = sum_c theta[PWSID,c] * pep[c,year], theta renormalized
    over counties present in PEP. Mirrors step2_annual() in
    build_cws_geopop_backcast.py but is not imported directly since that function
    is scoped to the full DECADE_WINDOWS sweep; the blend logic is short enough to
    duplicate here at the single-window grain LODO needs.
    """
    theta = theta_anchor.copy()
    renorm = theta.groupby("PWSID")["theta"].transform("sum")
    theta["theta"] = theta["theta"] / renorm.replace(0, np.nan)
    grid = theta.merge(pd.DataFrame({"year": years}), how="cross")
    grid = grid.merge(pep, on=["county_fips", "year"], how="left")
    grid["contrib"] = grid["theta"] * grid["population"]
    return grid.groupby(["PWSID", "year"])["contrib"].sum().reset_index().rename(columns={"contrib": "p_blend"})


def run_lodo(geopop_decennial: pd.DataFrame, county_shares: pd.DataFrame, pep: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for target, directions in LODO_TARGETS.items():
        truth = geopop_decennial[geopop_decennial["census_year"] == target][
            ["PWSID", "geopop", "geo_tier"]
        ].rename(columns={"geopop": "geopop_true"})

        for direction, source in directions.items():
            theta_src = county_shares[county_shares["census_year"] == source]
            p_blend = blend_pep_from_anchor(theta_src, pep, [source, target])
            p_src = p_blend[p_blend["year"] == source][["PWSID", "p_blend"]].rename(
                columns={"p_blend": "p_blend_src"}
            )
            p_tgt = p_blend[p_blend["year"] == target][["PWSID", "p_blend"]].rename(
                columns={"p_blend": "p_blend_tgt"}
            )
            src_geopop = geopop_decennial[geopop_decennial["census_year"] == source][
                ["PWSID", "geopop"]
            ].rename(columns={"geopop": "geopop_src"})

            pred = src_geopop.merge(p_src, on="PWSID", how="inner").merge(p_tgt, on="PWSID", how="inner")
            pred["geopop_pred"] = pred["geopop_src"] * pred["p_blend_tgt"] / pred["p_blend_src"].replace(0, np.nan)
            pred = pred.merge(truth, on="PWSID", how="inner")
            pred["target_year"] = target
            pred["direction"] = direction
            pred["signed_err"] = pred["geopop_pred"] - pred["geopop_true"]
            pred["ape"] = (pred["signed_err"] / pred["geopop_true"].replace(0, np.nan)).abs()
            rows.append(pred[["target_year", "direction", "PWSID", "geo_tier",
                               "geopop_true", "geopop_pred", "signed_err", "ape"]])

            for tier, g in pred.groupby("geo_tier"):
                agg_pred, agg_true = g["geopop_pred"].sum(), g["geopop_true"].sum()
                agg_pct = (agg_pred - agg_true) / agg_true if agg_true else np.nan
                print(f"  [target={target} dir={direction}][{tier}] n={len(g)} "
                      f"agg_err={agg_pct:+.1%} median_APE={g['ape'].median():.1%} "
                      f"within10pct={(g['ape']<=0.10).mean():.1%} within25pct={(g['ape']<=0.25).mean():.1%}")

    return pd.concat(rows, ignore_index=True)


def main():
    outputs = [LOAO_OUT, LODO_OUT]
    existing = [p for p in outputs if p.exists()]
    if existing:
        raise SystemExit(
            "The following outputs already exist -- confirm with the user before "
            f"overwriting: {[str(p) for p in existing]}"
        )

    anchors = pd.read_parquet(ANCHORS, engine="pyarrow", columns=["PWSID", "year", "pop_reported", "source"])
    anchors["PWSID"] = ratio_mod.norm_pwsid(anchors["PWSID"])
    tier_map = pd.read_parquet(RATIO_ANNUAL, engine="pyarrow", columns=["PWSID", "geo_tier"]).drop_duplicates()
    tier_map["PWSID"] = tier_map["PWSID"].astype(str)
    annual = pd.read_parquet(GEOPOP_ANNUAL, engine="pyarrow")
    annual["PWSID"] = ratio_mod.norm_pwsid(annual["PWSID"])

    print("--- Leave-one-anchor-out (LOAO) ---")
    loao = run_loao(anchors, tier_map, annual)

    geopop_decennial = pd.read_parquet(GEOPOP_DECENNIAL, engine="pyarrow")
    geopop_decennial["PWSID"] = geopop_decennial["PWSID"].astype(str)
    county_shares = pd.read_parquet(COUNTY_SHARES, engine="pyarrow")
    county_shares["PWSID"] = county_shares["PWSID"].astype(str)
    pep = pd.read_parquet(PEP, engine="pyarrow")

    print("\n--- Leave-one-decade-out (LODO) ---")
    lodo = run_lodo(geopop_decennial, county_shares, pep)

    for df, path, name in ((loao, LOAO_OUT, "loao_validation"), (lodo, LODO_OUT, "lodo_validation")):
        df["PWSID"] = df["PWSID"].astype(str)
        print(f"{name} dtypes:\n{df.dtypes}")
        df.to_parquet(path, index=False, engine="pyarrow")
        reread = pd.read_parquet(path, engine="pyarrow")
        print(f"Wrote {len(reread):,} rows x {reread.shape[1]} cols to {path}")


if __name__ == "__main__":
    main()
