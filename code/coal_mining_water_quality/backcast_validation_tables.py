# ============================================================
# Script: backcast_validation_tables.py
# Purpose: Results tables for the backcasting leave-one-out validation
#          (writeup/population_backcasting/main.tex validation section): LOAO
#          fold-by-tier accuracy of the Step 3 capture-ratio layer, and LODO
#          direction-by-tier accuracy of the Step 2 kappa-constant chaining.
# Inputs:  clean_data/cws_data/cws_loao_validation.parquet
#          clean_data/cws_data/cws_lodo_validation.parquet
# Outputs: writeup/population_backcasting/sum/backcast_loao.tex
#          writeup/population_backcasting/sum/backcast_lodo.tex
# Author: EK  Date: 2026-07-29 (repointed to standalone writeup 2026-08-28)
# ============================================================

from pathlib import Path

import pandas as pd

PROJECT_ROOT = Path(__file__).resolve().parents[2]
CLEAN_CWS = PROJECT_ROOT / "clean_data" / "cws_data"
SUM_DIR = PROJECT_ROOT / "writeup" / "population_backcasting" / "sum"

LOAO = CLEAN_CWS / "cws_loao_validation.parquet"
LODO = CLEAN_CWS / "cws_lodo_validation.parquet"

FOLD_LABEL = {
    "A_2010_2011": r"2010--2011 (from SYR2 + 2006)",
    "B_2006": r"2006 (from SYR2 + 2010/2011)",
    "C_SYR2": r"1998--2005 (from 2006 + 2010/2011)",
}
FOLD_ORDER = ["A_2010_2011", "B_2006", "C_SYR2"]
TIER_LABEL = {"service_area": "Service-area", "county": "County"}


def fmt_pct(x, signed=False):
    if pd.isna(x):
        return "---"
    sign = "+" if (signed and x >= 0) else ""
    return f"{sign}{100*x:.1f}\\%"


def write_tex(path: Path, body: str):
    path.write_text(body, encoding="utf-8")
    print(f"Wrote {path}")


def table_loao(loao: pd.DataFrame):
    rows = []
    for fold in FOLD_ORDER:
        for tier in ["service_area", "county"]:
            g = loao[(loao["fold"] == fold) & (loao["geo_tier"] == tier)]
            if not len(g):
                continue
            agg_true, agg_pred = g["pop_reported"].sum(), g["pop_served_hat"].sum()
            agg_err = (agg_pred - agg_true) / agg_true if agg_true else float("nan")
            rows.append(
                rf"{FOLD_LABEL[fold] if tier == 'service_area' else ''} & {TIER_LABEL[tier]} & "
                rf"{g['PWSID'].nunique()} & {fmt_pct(agg_err, signed=True)} & "
                rf"{fmt_pct(g['ape'].median())} & {fmt_pct(g['ape'].mean())} & "
                rf"{fmt_pct((g['ape'] <= 0.25).mean())} \\"
            )
        rows.append(r"\addlinespace")

    lines = [
        r"\begin{table}[ht]",
        r"\centering",
        r"\caption{Leave-one-anchor-out validation of the reported-served layer "
        r"$\hat S_{i,t}$. Each fold withholds a whole era of anchors and predicts it "
        r"from the survivors using the production estimator.}",
        r"\label{tab:backcast_loao}",
        r"\begin{adjustbox}{max width=\textwidth}",
        r"\begin{tabular}{llrrrrr}",
        r"\toprule",
        r"Held-out era & Tier & Systems & Aggregate error & Median APE & Mean APE & Share $\le\!25\%$ \\",
        r"\midrule",
    ] + rows[:-1] + [
        r"\bottomrule",
        r"\end{tabular}",
        r"\end{adjustbox}",
        r"\begin{minipage}{\textwidth}\footnotesize\raggedright",
        r"\vspace{0.5em}",
        r"\textit{Notes:} Folds hold out a whole era rather than an individual anchor because "
        r"2010 and 2011 are near-duplicates (correlation 0.998; 90.8\% of systems report an "
        r"identical value in both years), so a per-anchor leave-one-out would predict 2011 from "
        r"2010 with near-zero error -- a vacuous test. Aggregate error is the \% deviation of the "
        r"summed prediction from the summed held-out truth, the estimand that matters for $E^S_t$. "
        r"APE is the per-system absolute percentage error; mean APE is inflated by small systems "
        r"off a near-zero base and is reported for completeness, not as the headline. County-tier "
        r"systems carry a reported level forward on the county growth factor rather than a ratio, "
        r"so their error is not comparable to the service-area tier and the two are never pooled.",
        r"\end{minipage}",
        r"\end{table}",
    ]
    write_tex(SUM_DIR / "backcast_loao.tex", "\n".join(lines) + "\n")


def table_lodo(lodo: pd.DataFrame):
    rows = []
    for target in [2000, 2010]:
        for direction, dlabel in [("forward", "Forward"), ("backward", "Backward")]:
            for tier in ["service_area", "county"]:
                g = lodo[(lodo["target_year"] == target) & (lodo["direction"] == direction)
                         & (lodo["geo_tier"] == tier)]
                if not len(g):
                    continue
                agg_true, agg_pred = g["geopop_true"].sum(), g["geopop_pred"].sum()
                agg_err = (agg_pred - agg_true) / agg_true if agg_true else float("nan")
                lbl = f"{target} & {dlabel}" if tier == "service_area" else " & "
                within = f"{fmt_pct((g['ape'] <= 0.10).mean())} / {fmt_pct((g['ape'] <= 0.25).mean())}"
                rows.append(
                    rf"{lbl} & {TIER_LABEL[tier]} & {g['PWSID'].nunique()} & "
                    rf"{fmt_pct(agg_err, signed=True)} & {fmt_pct(g['ape'].median())} & "
                    rf"{within} \\"
                )
        rows.append(r"\addlinespace")

    lines = [
        r"\begin{table}[ht]",
        r"\centering",
        r"\caption{Leave-one-decade-out validation of the $G_{i,t}$ backbone. Each interior "
        r"decennial is predicted from each neighboring decennial by PEP-scaling (equation "
        r"\ref{eq:chain-closed}) and compared to the true block apportionment -- no reported "
        r"figure enters this test.}",
        r"\label{tab:backcast_lodo}",
        r"\begin{adjustbox}{max width=\textwidth}",
        r"\begin{tabular}{llrrrrr}",
        r"\toprule",
        r"Target year & Direction & Tier & Systems & Aggregate error & Median APE & "
        r"Share $\le\!10\%$ / $\le\!25\%$ \\",
        r"\midrule",
    ] + rows[:-1] + [
        r"\bottomrule",
        r"\end{tabular}",
        r"\end{adjustbox}",
        r"\begin{minipage}{\textwidth}\footnotesize\raggedright",
        r"\vspace{0.5em}",
        r"\textit{Notes:} ``Forward'' scales the earlier decennial's apportionment up to the "
        r"target using the county's PEP growth; ``backward'' scales the later decennial down. "
        r"All 366 systems have all four decennials, so there is no sample loss. County-tier "
        r"systems are the whole-county population by construction, so their apportionment moves "
        r"exactly with the county PEP series and this fold is a near-tautological check on the "
        r"PEP data itself, not on the polygon apportionment; the service-area tier is the "
        r"substantive test of the $\kappa$-constant assumption.",
        r"\end{minipage}",
        r"\end{table}",
    ]
    write_tex(SUM_DIR / "backcast_lodo.tex", "\n".join(lines) + "\n")


def main():
    SUM_DIR.mkdir(parents=True, exist_ok=True)
    loao = pd.read_parquet(LOAO, engine="pyarrow")
    lodo = pd.read_parquet(LODO, engine="pyarrow")
    table_loao(loao)
    table_lodo(lodo)


if __name__ == "__main__":
    main()
