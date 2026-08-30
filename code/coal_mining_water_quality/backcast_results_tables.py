# ============================================================
# Script: backcast_results_tables.py
# Purpose: Produce the results tables for the population-backcasting section
#          of writeup/population_backcasting/main.tex: recovery counts
#          (how many downstream CWSs and which years), summary statistics of
#          the backcast residential population, and the average change from
#          the earliest backcast year (1990) to 2005.
# Inputs:  clean_data/cws_data/downstream_mine_exposure_geo.parquet
#          clean_data/cws_data/cws_geopop_annual.parquet
#          clean_data/cws_data/cws_residential_exposure_annual.parquet
#          clean_data/cws_data/prod_vio_sulfur.parquet
# Outputs: writeup/population_backcasting/sum/backcast_recovery.tex
#          writeup/population_backcasting/sum/backcast_popsum.tex
#          writeup/population_backcasting/sum/backcast_change_9005.tex
#          writeup/population_backcasting/sum/backcast_exposure_series.tex
# Author: EK  Date: 2026-07-27 (repointed to standalone writeup 2026-08-28)
# ============================================================

from pathlib import Path

import geopandas as gpd
import pandas as pd

PROJECT_ROOT = Path(__file__).resolve().parents[2]
CLEAN_CWS = PROJECT_ROOT / "clean_data" / "cws_data"
SUM_DIR = PROJECT_ROOT / "writeup" / "population_backcasting" / "sum"

EXPOSURE_GEO = CLEAN_CWS / "downstream_mine_exposure_geo.parquet"
GEOPOP_ANNUAL = CLEAN_CWS / "cws_geopop_annual.parquet"
RESID_EXPOSURE = CLEAN_CWS / "cws_residential_exposure_annual.parquet"
PROD_VIO_SULFUR = CLEAN_CWS / "prod_vio_sulfur.parquet"

BASE_YEAR = 1990
END_YEAR = 2005


def fmt(x, dec=0):
    """Thousands-separated fixed-decimal formatter for LaTeX cells."""
    return f"{x:,.{dec}f}"


def summarize(s: pd.Series) -> dict:
    return {
        "N": len(s), "mean": s.mean(), "sd": s.std(), "p10": s.quantile(0.10),
        "p25": s.quantile(0.25), "median": s.median(), "p75": s.quantile(0.75),
        "p90": s.quantile(0.90), "max": s.max(),
    }


def write_tex(path: Path, body: str):
    path.write_text(body, encoding="utf-8")
    print(f"Wrote {path}")


def table_recovery(crosswalk, annual, roster):
    """How many downstream CWSs were recovered, and for which years."""
    n_ever = roster["PWSID"].nunique()
    tiers = crosswalk["geo_tier"].value_counts()
    n_service = int(tiers.get("service_area", 0))
    n_county = int(tiers.get("county", 0))
    n_unmatched = int(tiers.get("unmatched", 0))
    n_recovered = annual["PWSID"].nunique()
    n_states = crosswalk.loc[crosswalk["geo_tier"] != "unmatched", "state"].nunique()
    n_counties = crosswalk.loc[crosswalk["geo_tier"] == "county", "county_fips"].nunique()
    yr_min, yr_max, n_years = annual["year"].min(), annual["year"].max(), annual["year"].nunique()

    lines = [
        r"\begin{table}[ht]",
        r"\centering",
        r"\caption{Recovery of residential population for community water systems one HUC12 "
        r"directly downstream of coal mining.}",
        r"\label{tab:backcast_recovery}",
        r"\begin{adjustbox}{max width=\textwidth}",
        r"\begin{tabular}{lrl}",
        r"\toprule",
        r"& Systems & Notes \\",
        r"\midrule",
        r"\multicolumn{3}{l}{\textit{Panel A: Coverage of the downstream roster}} \\",
        rf"Ever downstream of a mine, 1983--2024 & {n_ever} & Target set, "
        rf"$\mathcal{{D}}=\bigcup_t \mathcal{{D}}_t$ \\",
        rf"\quad Matched to an EPA SABS service-area polygon & {n_service} & Preferred tier \\",
        rf"\quad Matched to a county polygon (fallback) & {n_county} & {n_counties} distinct counties \\",
        rf"\quad Unmatched (no polygon, no county) & {n_unmatched} & Dropped \\",
        rf"\textbf{{Population recovered}} & \textbf{{{n_recovered}}} & "
        rf"{100 * n_recovered / n_ever:.1f}\% of the roster, across {n_states} states \\",
        r"\midrule",
        r"\multicolumn{3}{l}{\textit{Panel B: Years recovered}} \\",
        rf"Backcast window & {yr_min}--{yr_max} & {n_years} annual observations per system \\",
        r"\quad Decennial anchor years & 4 & 1990, 2000, 2010, 2020 (block apportionment) \\",
        rf"\quad Intercensal years & {n_years - 4} & PEP county growth, re-anchored each decade \\",
        rf"System $\times$ year panel & {fmt(len(annual))} & Balanced, no missing values \\",
        r"Roster years not recovered & --- & 1983--1989: no nationwide block geography \\",
        r"\bottomrule",
        r"\end{tabular}",
        r"\end{adjustbox}",
        r"\begin{minipage}{\textwidth}\footnotesize\raggedright",
        r"\vspace{0.5em}",
        r"\textit{Notes:} A community water system is downstream if at least one of its intakes lies "
        r"in a HUC12 directly downstream of a HUC12 with an active coal mine, and none lies in a "
        r"mining HUC12 itself. Residential population inside each system's exposure polygon is "
        r"apportioned from decennial Census blocks by areal weights and carried to intercensal years "
        r"with county Population Estimates Program growth. The 1990 floor binds because nationwide "
        r"digital block boundaries begin with the 1990 TIGER/Line release.",
        r"\end{minipage}",
        r"\end{table}",
    ]
    write_tex(SUM_DIR / "backcast_recovery.tex", "\n".join(lines) + "\n")


def table_popsum(annual):
    """Summary statistics of the backcast population, pooled, by tier, and by year."""
    def row(label, d):
        return (rf"{label} & {fmt(d['N'])} & {fmt(d['mean'])} & {fmt(d['sd'])} & {fmt(d['p10'])} & "
                rf"{fmt(d['p25'])} & {fmt(d['median'])} & {fmt(d['p75'])} & {fmt(d['p90'])} & "
                rf"{fmt(d['max'])} \\")

    by_tier = {t: summarize(g["geopop_hat"]) for t, g in annual.groupby("geo_tier")}
    years = [1990, 1995, 2000, 2005]

    lines = [
        r"\begin{table}[ht]",
        r"\centering",
        r"\caption{Backcast residential population of downstream community water systems: "
        r"summary statistics.}",
        r"\label{tab:backcast_popsum}",
        r"\begin{adjustbox}{max width=\textwidth}",
        r"\begin{tabular}{lrrrrrrrrr}",
        r"\toprule",
        r" & N & Mean & SD & p10 & p25 & Median & p75 & p90 & Max \\",
        r"\midrule",
        r"\multicolumn{10}{l}{\textit{Panel A: Pooled system $\times$ year observations, 1990--2024}} \\",
        row("All systems", summarize(annual["geopop_hat"])),
        row(r"\quad Service-area tier", by_tier["service_area"]),
        row(r"\quad County tier", by_tier["county"]),
        r"\midrule",
        r"\multicolumn{10}{l}{\textit{Panel B: Cross-section of all recovered systems, selected years}} \\",
    ] + [
        row(str(y), summarize(annual.loc[annual["year"] == y, "geopop_hat"])) for y in years
    ] + [
        r"\bottomrule",
        r"\end{tabular}",
        r"\end{adjustbox}",
        r"\begin{minipage}{\textwidth}\footnotesize\raggedright",
        r"\vspace{0.5em}",
        r"\textit{Notes:} The unit is the residential population inside a system's exposure polygon "
        r"($\hat{G}_{i,t}$), not the population the utility reports serving. The distribution is "
        r"right-skewed and bimodal because the two geography tiers differ in scale: service-area "
        r"polygons delineate the utility's own footprint, whereas county-tier systems inherit their "
        r"entire county's population and so overstate the population attributable to any one system. "
        r"Panel B holds the set of systems fixed at all recovered systems, isolating population "
        r"change from roster entry and exit.",
        r"\end{minipage}",
        r"\end{table}",
    ]
    write_tex(SUM_DIR / "backcast_popsum.tex", "\n".join(lines) + "\n")


def table_change(annual, roster):
    """Average change from the earliest backcast year to 2005."""
    wide = annual.pivot(index="PWSID", columns="year", values="geopop_hat")
    tier = annual.drop_duplicates("PWSID").set_index("PWSID")["geo_tier"]
    d = pd.DataFrame({"base": wide[BASE_YEAR], "end": wide[END_YEAR], "geo_tier": tier})
    d["abs_chg"] = d["end"] - d["base"]
    d["pct_chg"] = 100 * (d["end"] / d["base"] - 1)

    def block(g, label):
        a, p = summarize(g["abs_chg"]), summarize(g["pct_chg"])
        tot_b, tot_e = g["base"].sum(), g["end"].sum()
        return (rf"{label} & {fmt(a['N'])} & {fmt(tot_b)} & {fmt(tot_e)} & "
                rf"{100 * (tot_e / tot_b - 1):.2f} & {fmt(a['mean'])} & {fmt(a['median'])} & "
                rf"{p['mean']:.2f} & {p['median']:.2f} & {100 * (g['pct_chg'] < 0).mean():.2f} \\")

    # Roster-weighted totals, which also carry the extensive margin.
    r_base = set(roster.loc[roster["year"] == BASE_YEAR, "PWSID"]) & set(wide.index)
    r_end = set(roster.loc[roster["year"] == END_YEAR, "PWSID"]) & set(wide.index)
    stayers, exiters = list(r_base & r_end), list(r_base - r_end)
    entrants = list(r_end - r_base)
    e_base, e_end = wide.loc[list(r_base), BASE_YEAR].sum(), wide.loc[list(r_end), END_YEAR].sum()
    stay_base, stay_end = wide.loc[stayers, BASE_YEAR].sum(), wide.loc[stayers, END_YEAR].sum()
    exit_base = wide.loc[exiters, BASE_YEAR].sum() if exiters else 0.0
    entr_end = wide.loc[entrants, END_YEAR].sum() if entrants else 0.0

    lines = [
        r"\begin{table}[ht]",
        r"\centering",
        rf"\caption{{Change in backcast residential population, {BASE_YEAR}--{END_YEAR}.}}",
        r"\label{tab:backcast_change}",
        r"\begin{adjustbox}{max width=\textwidth}",
        r"\begin{tabular}{lrrrrrrrrr}",
        r"\toprule",
        r"& & \multicolumn{3}{c}{Total population} & \multicolumn{2}{c}{Change, levels} "
        r"& \multicolumn{2}{c}{Change, \%} & Share \\",
        r"\cmidrule(lr){3-5}\cmidrule(lr){6-7}\cmidrule(lr){8-9}",
        rf"& N & {BASE_YEAR} & {END_YEAR} & \% & Mean & Median & Mean & Median & declining \\",
        r"\midrule",
        r"\multicolumn{10}{l}{\textit{Panel A: Balanced set of recovered systems "
        r"(intensive margin only)}} \\",
        block(d, "All systems"),
        block(d[d["geo_tier"] == "service_area"], r"\quad Service-area tier"),
        block(d[d["geo_tier"] == "county"], r"\quad County tier"),
        r"\midrule",
        r"\multicolumn{10}{l}{\textit{Panel B: Exposed population over the annual roster "
        r"$\mathcal{D}_t$ (intensive $+$ extensive margin)}} \\",
        rf"Downstream in {BASE_YEAR} & {len(r_base)} & {fmt(e_base)} & & & & & & & \\",
        rf"Downstream in {END_YEAR} & {len(r_end)} & & {fmt(e_end)} & "
        rf"{100 * (e_end / e_base - 1):.2f} & & & & & \\",
        rf"\quad Stayers & {len(stayers)} & {fmt(stay_base)} & {fmt(stay_end)} & "
        rf"{100 * (stay_end / stay_base - 1):.2f} & & & & & \\",
        rf"\quad Exited the roster & {len(exiters)} & {fmt(exit_base)} & 0 & $-100.00$ & & & & & \\",
        rf"\quad Entered the roster & {len(entrants)} & 0 & {fmt(entr_end)} & & & & & & \\",
        r"\bottomrule",
        r"\end{tabular}",
        r"\end{adjustbox}",
        r"\begin{minipage}{\textwidth}\footnotesize\raggedright",
        r"\vspace{0.5em}",
        r"\textit{Notes:} Panel A holds the set of systems fixed and so measures only within-system "
        r"population growth. Percentage changes are computed per system and then averaged, so the "
        r"mean is inflated by a few very small systems growing from a near-zero base; the median is "
        r"the more informative central tendency. Panel B sums over the year-specific downstream "
        r"roster and therefore also captures systems entering and leaving the downstream set as "
        r"mines open and close.",
        r"\end{minipage}",
        r"\end{table}",
    ]
    write_tex(SUM_DIR / "backcast_change_9005.tex", "\n".join(lines) + "\n")


def table_exposure_series(exposure):
    """The annual exposed-population series E^G_t, laid out in two column blocks."""
    e = exposure.sort_values("year")
    pre = [(int(r.year), r.E_G, int(r.n_systems)) for r in e[e["year"] <= END_YEAR].itertuples()]
    post = [(int(r.year), r.E_G, int(r.n_systems)) for r in e[e["year"] > END_YEAR].itertuples()]

    lines = [
        r"\begin{table}[ht]",
        r"\centering",
        r"\caption{Annual residential population downstream of active coal mining, $E^{G}_t$.}",
        r"\label{tab:backcast_exposure_series}",
        r"\begin{adjustbox}{max width=\textwidth}",
        r"\begin{tabular}{lrr@{\hskip 2.5em}lrr}",
        r"\toprule",
        r"Year & Population & Systems & Year & Population & Systems \\",
        r"\midrule",
    ]
    for i in range(max(len(pre), len(post))):
        left = f"{pre[i][0]} & {fmt(pre[i][1])} & {pre[i][2]}" if i < len(pre) else " & & "
        right = f"{post[i][0]} & {fmt(post[i][1])} & {post[i][2]}" if i < len(post) else " & & "
        lines.append(rf"{left} & {right} \\")
    lines += [
        r"\bottomrule",
        r"\end{tabular}",
        r"\end{adjustbox}",
        r"\begin{minipage}{\textwidth}\footnotesize\raggedright",
        r"\vspace{0.5em}",
        r"\textit{Notes:} $E^{G}_t=\sum_{i\in\mathcal{D}_t}\hat{G}_{i,t}$ sums backcast residential "
        r"population over the systems that are one HUC12 directly downstream of an active coal mine "
        r"in year $t$. Per-system population is roughly flat over the period, so the decline is "
        r"driven by systems leaving $\mathcal{D}_t$ as upstream mines close. Levels are inflated by "
        r"county-tier systems, which each contribute a whole county's population.",
        r"\end{minipage}",
        r"\end{table}",
    ]
    write_tex(SUM_DIR / "backcast_exposure_series.tex", "\n".join(lines) + "\n")


def main():
    SUM_DIR.mkdir(parents=True, exist_ok=True)

    crosswalk = gpd.read_parquet(EXPOSURE_GEO)
    crosswalk["PWSID"] = crosswalk["PWSID"].astype(str)
    annual = pd.read_parquet(GEOPOP_ANNUAL, engine="pyarrow")
    annual["PWSID"] = annual["PWSID"].astype(str)
    exposure = pd.read_parquet(RESID_EXPOSURE, engine="pyarrow")

    pv = pd.read_parquet(
        PROD_VIO_SULFUR, columns=["PWSID", "year", "minehuc_downstream_of_mine"], engine="pyarrow"
    )
    pv["PWSID"] = pv["PWSID"].astype(str)
    roster = pv.loc[pv["minehuc_downstream_of_mine"] == 1, ["PWSID", "year"]].drop_duplicates()

    print(f"roster: {roster['PWSID'].nunique()} ever-downstream PWSIDs, "
          f"years {roster['year'].min()}-{roster['year'].max()}")
    print(f"annual: {annual['PWSID'].nunique()} PWSIDs x {annual['year'].nunique()} years "
          f"= {len(annual):,} rows, {annual['geopop_hat'].isna().sum()} nulls")

    table_recovery(crosswalk, annual, roster)
    table_popsum(annual)
    table_change(annual, roster)
    table_exposure_series(exposure)


if __name__ == "__main__":
    main()
