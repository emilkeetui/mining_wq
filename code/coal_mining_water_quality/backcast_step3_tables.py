# ============================================================
# Script: backcast_step3_tables.py
# Purpose: Results tables for backcasting Step 3 (the reported-served layer):
#          the anchor inventory, the capture-ratio distribution and its drift
#          across anchors, and the reported-served exposure series E^S_t set
#          against the residential series E^G_t.
# Inputs:  clean_data/cws_data/cws_pop_anchors.parquet
#          clean_data/cws_data/cws_capture_ratio_annual.parquet
#          clean_data/cws_data/cws_reported_exposure_annual.parquet
#          clean_data/cws_data/cws_geopop_annual.parquet
#          clean_data/cws_data/prod_vio_sulfur.parquet
# Outputs: writeup/Mining_and_Water_Quality (1)/sum/backcast_anchors.tex
#          writeup/Mining_and_Water_Quality (1)/sum/backcast_ratio.tex
#          writeup/Mining_and_Water_Quality (1)/sum/backcast_reported_exposure.tex
# Author: EK  Date: 2026-07-27
# ============================================================

from pathlib import Path

import numpy as np
import pandas as pd

PROJECT_ROOT = Path(__file__).resolve().parents[2]
CLEAN_CWS = PROJECT_ROOT / "clean_data" / "cws_data"
SUM_DIR = PROJECT_ROOT / "writeup" / "Mining_and_Water_Quality (1)" / "sum"

ANCHORS = CLEAN_CWS / "cws_pop_anchors.parquet"
RATIO = CLEAN_CWS / "cws_capture_ratio_annual.parquet"
REPORTED = CLEAN_CWS / "cws_reported_exposure_annual.parquet"
GEOPOP_ANNUAL = CLEAN_CWS / "cws_geopop_annual.parquet"
PROD_VIO_SULFUR = CLEAN_CWS / "prod_vio_sulfur.parquet"

BASE_YEAR, END_YEAR = 1990, 2005


def fmt(x, dec=0):
    if pd.isna(x):
        return "---"
    return f"{x:,.{dec}f}"


def write_tex(path: Path, body: str):
    path.write_text(body, encoding="utf-8")
    print(f"Wrote {path}")


def table_anchors(anchors, tier):
    anchors = anchors.copy()
    anchors["geo_tier"] = anchors["PWSID"].map(tier)
    src_order = ["SYR2", "CWSS2006", "SDWIS2010", "SDWIS2011"]
    label = {"SYR2": r"SYR2 occurrence inventory", "CWSS2006": r"CWSS 2006 \texttt{cwssframe}",
             "SDWIS2010": r"SDWIS 2010 freeze", "SDWIS2011": r"SDWIS 2011 freeze"}
    yrs = {"SYR2": "1998--2005", "CWSS2006": "2006", "SDWIS2010": "2010", "SDWIS2011": "2011"}

    rows = []
    for s in src_order:
        g = anchors[anchors["source"].str.contains(s, na=False)]
        if not len(g):
            continue
        n_sa = (g["geo_tier"] == "service_area").sum()
        n_ct = (g["geo_tier"] == "county").sum()
        rows.append(rf"{label[s]} & {yrs[s]} & {g['PWSID'].nunique()} & {n_sa} & {n_ct} & "
                    rf"{fmt(g['pop_reported'].median())} \\")

    n_any = anchors["PWSID"].nunique()
    per_sys = anchors.groupby("PWSID").size()

    lines = [
        r"\begin{table}[ht]",
        r"\centering",
        r"\caption{Reported population-served anchors for downstream community water systems.}",
        r"\label{tab:backcast_anchors}",
        r"\begin{adjustbox}{max width=\textwidth}",
        r"\begin{tabular}{llrrrr}",
        r"\toprule",
        r"Source & Year(s) & Systems & Service-area & County & Median reported pop. \\",
        r"\midrule",
    ] + rows + [
        r"\midrule",
        rf"\textbf{{Any anchor}} & 1998--2011 & \textbf{{{n_any}}} & "
        rf"{(anchors.drop_duplicates('PWSID')['geo_tier'] == 'service_area').sum()} & "
        rf"{(anchors.drop_duplicates('PWSID')['geo_tier'] == 'county').sum()} & "
        rf"{fmt(anchors.groupby('PWSID')['pop_reported'].median().median())} \\",
        rf"\quad with 1 anchor & & {(per_sys == 1).sum()} & & & \\",
        rf"\quad with 2--3 anchors & & {per_sys.between(2, 3).sum()} & & & \\",
        rf"\quad with 4 anchors & & {(per_sys >= 4).sum()} & & & \\",
        rf"No anchor (imputed) & & {366 - n_any} & & & \\",
        r"\bottomrule",
        r"\end{tabular}",
        r"\end{adjustbox}",
        r"\begin{minipage}{\textwidth}\footnotesize",
        r"\vspace{0.5em}",
        r"\textit{Notes:} An anchor is a year in which a system's \emph{reported} population served "
        r"is directly observed and linkable to its \texttt{PWSID}. Each source supplies one "
        r"inventory value per system, not an annual series: the SYR2 occurrence databases carry a "
        r"single \texttt{POPULATION} field stamped on every sample record, which does not vary "
        r"across a system's 1998--2005 samples, so the SYR2 anchor is dated to the system's first "
        r"sample year. The 1995 and 2000 Community Water System Surveys are de-identified samples "
        r"and cannot be attached to a \texttt{PWSID}; the 2005 SDWIS ``freeze'' is a summary pivot "
        r"with no system records. No anchor of any kind exists before 1998.",
        r"\end{minipage}",
        r"\end{table}",
    ]
    write_tex(SUM_DIR / "backcast_anchors.tex", "\n".join(lines) + "\n")


def table_ratio(anchors, grid, tier):
    a = anchors.copy()
    a["geo_tier"] = a["PWSID"].map(tier)
    sa = a[a["geo_tier"] == "service_area"]
    ct = a[a["geo_tier"] == "county"]

    def q(s, p):
        return s.quantile(p)

    # drift across anchors, service tier
    sp = sa.groupby("PWSID")["ratio"].agg(["count", "min", "max"])
    sp = sp[sp["count"] > 1]
    rel = (sp["max"] / sp["min"].replace(0, np.nan)).dropna()

    lines = [
        r"\begin{table}[ht]",
        r"\centering",
        r"\caption{The capture ratio $r_{i,a}=S_{i,a}/G_{i,a}$ at anchor years, by geography tier.}",
        r"\label{tab:backcast_ratio}",
        r"\begin{adjustbox}{max width=\textwidth}",
        r"\begin{tabular}{lrrrrrr}",
        r"\toprule",
        r"& Anchors & p10 & p25 & Median & p75 & p90 \\",
        r"\midrule",
        rf"Service-area tier & {len(sa)} & {q(sa['ratio_raw'], .1):.3f} & {q(sa['ratio_raw'], .25):.3f} & "
        rf"{q(sa['ratio_raw'], .5):.3f} & {q(sa['ratio_raw'], .75):.3f} & {q(sa['ratio_raw'], .9):.3f} \\",
        rf"County tier & {len(ct)} & {q(ct['ratio_raw'], .1):.4f} & {q(ct['ratio_raw'], .25):.4f} & "
        rf"{q(ct['ratio_raw'], .5):.4f} & {q(ct['ratio_raw'], .75):.4f} & {q(ct['ratio_raw'], .9):.4f} \\",
        r"\midrule",
        r"\multicolumn{7}{l}{\textit{Ratio drift: within-system $\max r / \min r$ across anchors "
        r"(service-area tier)}} \\",
        rf"Systems with $>1$ anchor & {len(rel)} & {q(rel, .1):.2f} & {q(rel, .25):.2f} & "
        rf"{q(rel, .5):.2f} & {q(rel, .75):.2f} & {q(rel, .9):.2f} \\",
        r"\bottomrule",
        r"\end{tabular}",
        r"\end{adjustbox}",
        r"\begin{minipage}{\textwidth}\footnotesize",
        r"\vspace{0.5em}",
        r"\textit{Notes:} $S$ is reported population served, $G$ the residential population inside "
        r"the system's exposure polygon. For the service-area tier the ratio is interpretable and "
        r"well behaved: it centers slightly above one, consistent with systems serving some demand "
        r"beyond their resident population, and the median system's ratio moves only $1.15\times$ "
        r"between its earliest and latest anchor, which is what the constant- and "
        r"interpolated-$r$ assumptions require. For the county tier the denominator is an entire "
        r"county's population, so $r\approx 0.001$ measures the utility's share of its county "
        r"rather than a capture rate. Multiplying that ratio back by $G$ would simply return the "
        r"reported figure while discarding the backbone, so county-tier systems instead take their "
        r"reported population as the level and the county's growth as the trend.",
        r"\end{minipage}",
        r"\end{table}",
    ]
    write_tex(SUM_DIR / "backcast_ratio.tex", "\n".join(lines) + "\n")


def table_reported_exposure(exposure, grid, ann, roster):
    e = exposure.sort_values("year")
    pre = e[e["year"] <= END_YEAR]

    g = grid.set_index(["PWSID", "year"])
    # Match the deduped basis of the series rows above: exclude the wholesale
    # sellers, so the decomposition reconciles with E^S_t rather than restating
    # a different (larger) system count.
    sellers = set(grid.loc[grid["is_seller"], "PWSID"]) if "is_seller" in grid.columns else set()
    r_base = (set(roster.loc[roster["year"] == BASE_YEAR, "PWSID"]) & set(ann["PWSID"])) - sellers
    r_end = (set(roster.loc[roster["year"] == END_YEAR, "PWSID"]) & set(ann["PWSID"])) - sellers
    stay, ex = list(r_base & r_end), list(r_base - r_end)

    def tot(pwsids, year, col):
        idx = [(p, year) for p in pwsids if (p, year) in g.index]
        return g.loc[idx, col].sum()

    s_base, s_end = tot(r_base, BASE_YEAR, "pop_served_hat"), tot(r_end, END_YEAR, "pop_served_hat")
    stay_b, stay_e = tot(stay, BASE_YEAR, "pop_served_hat"), tot(stay, END_YEAR, "pop_served_hat")
    ex_b = tot(ex, BASE_YEAR, "pop_served_hat")
    gex_b = tot(ex, BASE_YEAR, "geopop_hat") if "geopop_hat" in g.columns else np.nan

    rows = [rf"{int(r.year)} & {fmt(r.E_S)} & {fmt(r.E_G)} & {r.E_S / r.E_G:.3f} & {int(r.n_systems)} \\"
            for r in pre.itertuples()]

    lines = [
        r"\begin{table}[ht]",
        r"\centering",
        r"\caption{Reported-served exposure $E^{S}_t$ against residential exposure $E^{G}_t$.}",
        r"\label{tab:backcast_reported_exposure}",
        r"\begin{adjustbox}{max width=\textwidth}",
        r"\begin{tabular}{lrrrr}",
        r"\toprule",
        r"Year & $E^{S}_t$ (reported) & $E^{G}_t$ (residential) & Ratio & Systems \\",
        r"\midrule",
    ] + rows + [
        r"\midrule",
        r"\multicolumn{5}{l}{\textit{Decomposition of the change, 1990--2005}} \\",
        rf"Downstream in 1990 & {fmt(s_base)} & & & {len(r_base)} \\",
        rf"Downstream in 2005 & {fmt(s_end)} & & & {len(r_end)} \\",
        rf"\quad Change & {100 * (s_end / s_base - 1):.2f}\% & & & \\",
        rf"\quad Stayers & {fmt(stay_b)} $\rightarrow$ {fmt(stay_e)} & & "
        rf"{100 * (stay_e / stay_b - 1):.2f}\% & {len(stay)} \\",
        rf"\quad Exited the roster & {fmt(ex_b)} & {fmt(gex_b)} & & {len(ex)} \\",
        r"\bottomrule",
        r"\end{tabular}",
        r"\end{adjustbox}",
        r"\begin{minipage}{\textwidth}\footnotesize",
        r"\vspace{0.5em}",
        r"\textit{Notes:} $E^{S}_t$ sums estimated reported population served over the systems "
        r"downstream of an active mine in year $t$, after removing 27 wholesale sellers whose "
        r"population is already counted by a downstream buyer. The contrast with $E^{G}_t$ is the "
        r"substantive result. The 62 systems that leave the downstream roster between 1990 and 2005 "
        r"are almost entirely county-tier (61 of 62) with a median reported population of 60 "
        r"people, so they carry a large residential figure but a small reported one. The steep "
        r"decline in $E^{G}_t$ is therefore largely an artifact of the county fallback geography, "
        r"and $E^{S}_t$ is the more credible measure of how the exposed customer base actually "
        r"evolved.",
        r"\end{minipage}",
        r"\end{table}",
    ]
    write_tex(SUM_DIR / "backcast_reported_exposure.tex", "\n".join(lines) + "\n")


def main():
    SUM_DIR.mkdir(parents=True, exist_ok=True)
    anchors = pd.read_parquet(ANCHORS, engine="pyarrow")
    grid = pd.read_parquet(RATIO, engine="pyarrow")
    exposure = pd.read_parquet(REPORTED, engine="pyarrow")
    ann = pd.read_parquet(GEOPOP_ANNUAL, engine="pyarrow")
    ann["PWSID"] = ann["PWSID"].astype(str)
    tier = ann.drop_duplicates("PWSID").set_index("PWSID")["geo_tier"]

    grid = grid.merge(ann[["PWSID", "year", "geopop_hat"]], on=["PWSID", "year"], how="left")

    pv = pd.read_parquet(PROD_VIO_SULFUR,
                         columns=["PWSID", "year", "minehuc_downstream_of_mine"], engine="pyarrow")
    pv["PWSID"] = pv["PWSID"].astype(str)
    roster = pv.loc[pv["minehuc_downstream_of_mine"] == 1, ["PWSID", "year"]].drop_duplicates()

    table_anchors(anchors, tier)
    table_ratio(anchors, grid, tier)
    table_reported_exposure(exposure, grid, ann, roster)


if __name__ == "__main__":
    main()
