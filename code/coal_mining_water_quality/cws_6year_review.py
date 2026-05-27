# ============================================================
# Script: cws_6year_review.py
# Purpose: Build a PWSID-level panel from EPA 6-Year Review
#          MDB files and merge to the main 2SLS dataset
# Inputs:  - List of .mdb file paths (one per chemical)
#          - List of chemical name strings (same length)
#          - clean_data/cws_data/prod_vio_sulfur.parquet
# Outputs: clean_data/cws_6year_review.parquet
# Author: EK  Date: 2026-05-26
# ============================================================

import pathlib
import pyodbc
import pandas as pd

PROJECT_ROOT = pathlib.Path(r"Z:\ek559\mining_wq")
MAIN_DATASET = PROJECT_ROOT / "clean_data" / "cws_data" / "prod_vio_sulfur.parquet"
OUTPUT_PATH  = PROJECT_ROOT / "clean_data" / "cws_6year_review.parquet"

KEEP_COLS = ["PWSID", "CHEMID_name", "DETECT", "VALUE", "UNITS", "YEAR"]


def build_6year_review(mdb_paths: list[str], chem_names: list[str]) -> pd.DataFrame:
    """
    Reads each MDB file, tags it with the chemical name, extracts year from
    DATE, and stacks all chemicals into one master dataframe.

    NOTE on merge cardinality: the 6-year review data are sample-level
    (many samples per PWSID per year), while the 2SLS dataset is one row
    per PWSID x year. Merging produces a many-to-one join: many 6-year-review
    rows match each single 2SLS row. The merged file therefore has more rows
    than the 2SLS dataset.

    Parameters
    ----------
    mdb_paths : list of str
        Full paths to .mdb files.
    chem_names : list of str
        Chemical name labels corresponding to each .mdb file.

    Returns
    -------
    pd.DataFrame
        Merged dataframe (6-year review columns + all 2SLS columns).
    """
    if len(mdb_paths) != len(chem_names):
        raise ValueError(
            f"mdb_paths ({len(mdb_paths)}) and chem_names ({len(chem_names)}) "
            "must have the same length."
        )

    master = pd.DataFrame()

    for mdb_path, chem_name in zip(mdb_paths, chem_names):
        print(f"  Reading {pathlib.Path(mdb_path).name}  ->  CHEMID_name = '{chem_name}'")

        conn_str = r"DRIVER={Microsoft Access Driver (*.mdb, *.accdb)};DBQ=" + str(mdb_path)
        conn = pyodbc.connect(conn_str)

        # Each MDB contains exactly one table; discover it dynamically.
        cursor = conn.cursor()
        tables = [row.table_name for row in cursor.tables(tableType="TABLE")]
        if not tables:
            raise RuntimeError(f"No tables found in {mdb_path}")
        table_name = tables[0]

        cursor.execute(f"SELECT * FROM [{table_name}]")
        cols = [desc[0] for desc in cursor.description]
        rows = cursor.fetchall()
        conn.close()
        df = pd.DataFrame.from_records(rows, columns=cols)

        df["YEAR"]       = pd.to_datetime(df["DATE"]).dt.year
        df["CHEMID_name"] = chem_name

        df = df[KEEP_COLS].copy()

        # Compute summary stats at PWSID-YEAR level and collapse
        grp = df.groupby(["PWSID", "YEAR"])["VALUE"]
        df["mean"]   = grp.transform("mean")
        df["median"] = grp.transform("median")
        df["max"]    = grp.transform("max")
        df["min"]    = grp.transform("min")

        df = (
            df.groupby(["PWSID", "CHEMID_name", "YEAR"], as_index=False)
            .agg(VALUE=("VALUE", "mean"), UNITS=("UNITS", "first"),
                 mean=("mean", "first"), median=("median", "first"),
                 max=("max", "first"), min=("min", "first"))
        )

        master = pd.concat([master, df], ignore_index=True)
        print(f"    {len(df):,} PWSID-year rows  |  master total: {len(master):,} rows")

    print(f"\nMaster dataframe: {len(master):,} rows x {master.shape[1]} columns")

    # ------------------------------------------------------------------
    # Merge to main 2SLS dataset
    # ------------------------------------------------------------------
    print(f"\nReading main 2SLS dataset from {MAIN_DATASET}")
    main_df = pd.read_parquet(MAIN_DATASET, engine="pyarrow")
    print(f"  Main dataset: {len(main_df):,} rows × {main_df.shape[1]} columns")
    print(f"  Year range: {main_df['year'].min()} – {main_df['year'].max()}")

    # Align key types before joining
    master["PWSID"] = master["PWSID"].astype(str)
    master["YEAR"]  = master["YEAR"].astype("int64")
    main_df["PWSID"] = main_df["PWSID"].astype(str)
    main_df["year"]  = main_df["year"].astype("int64")

    # ------------------------------------------------------------------
    # Cardinality check
    # ------------------------------------------------------------------
    left_keys  = master.groupby(["PWSID", "YEAR"]).size()
    right_keys = main_df.groupby(["PWSID", "year"]).size()

    left_dup  = (left_keys > 1).sum()
    right_dup = (right_keys > 1).sum()

    print(
        f"\n[MERGE CARDINALITY NOTICE]\n"
        f"  6-year review: {left_dup:,} of {len(left_keys):,} (PWSID, year) keys "
        f"have >1 sample row -- many-to-one merge expected.\n"
        f"  2SLS dataset:  {right_dup:,} of {len(right_keys):,} (PWSID, year) keys "
        f"have >1 row (should be 0 for a clean panel).\n"
        f"  Result will have MORE rows than the 2SLS dataset because each 2SLS "
        f"observation can match multiple sample readings."
    )

    # Expand main 2SLS dataset: one row per PWSID × year × chemical.
    # Then left-join 6-year review data so that every PWSID-year-chemical
    # combination is present; VALUE is NaN where no chemical observation exists.
    unique_chems = master[["CHEMID_name"]].drop_duplicates()
    main_expanded = main_df.merge(unique_chems, how="cross")
    print(
        f"\nExpanded 2SLS dataset: {len(main_expanded):,} rows "
        f"({len(main_df):,} PWSID-years × {len(unique_chems):,} chemicals)"
    )

    merged = main_expanded.merge(
        master,
        left_on=["PWSID", "year", "CHEMID_name"],
        right_on=["PWSID", "YEAR", "CHEMID_name"],
        how="left",
    )
    # Drop the redundant YEAR column from master (equals year for matched rows)
    merged = merged.drop(columns=["YEAR"], errors="ignore")

    n_missing = merged["VALUE"].isna().sum()
    print(
        f"\nMerged dataframe: {len(merged):,} rows × {merged.shape[1]} columns\n"
        f"  VALUE missing (no 6-year-review obs): {n_missing:,} "
        f"({100 * n_missing / len(merged):.1f}%)"
    )

    # ------------------------------------------------------------------
    # Write output
    # ------------------------------------------------------------------
    if OUTPUT_PATH.exists():
        print(f"WARNING: {OUTPUT_PATH} already exists — overwriting")

    merged["PWSID"] = merged["PWSID"].astype(str)
    merged["year"]  = merged["year"].astype("int64")

    print(merged.dtypes)
    merged.to_parquet(OUTPUT_PATH, index=False, engine="pyarrow")

    verify = pd.read_parquet(OUTPUT_PATH, engine="pyarrow")
    print(f"\nWritten {len(verify):,} rows × {verify.shape[1]} columns to {OUTPUT_PATH}")

    return merged


# ---------------------------------------------------------------------------
# Example invocation (edit paths/names as needed before running directly)
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    mdb_files = [
        r"Z:\ek559\mining_wq\raw_data\6_year_review_epa\six-year-review 2\sixyearreview_2_dh_part2_1\Arsenic_Chem1005.mdb",
        r"Z:\ek559\mining_wq\raw_data\6_year_review_epa\six-year-review 2\nitrate-as-n-_chem1040_update_mdb\Nitrate (as N)_Chem1040_update.mdb",
        r"Z:\ek559\mining_wq\raw_data\6_year_review_epa\six-year-review 2\sixyearreview_2_dh_part2_1\Benzene_Chem2990.mdb",
        r"Z:\ek559\mining_wq\raw_data\6_year_review_epa\six-year-review 2\sixyearreview_2_dh_part2_1\CarbonTetrachloride_Chem2982.mdb",
        r"Z:\ek559\mining_wq\raw_data\6_year_review_epa\six-year-review 2\sixyearreview_2_dh_part1_1\1,2-Dichloroethane_Chem2980.mdb",
        r"Z:\ek559\mining_wq\raw_data\6_year_review_epa\six-year-review 2\sixyearreview_2_dh_part1_1\1,1-Dichloroethylene_Chem2977.mdb",
        r"Z:\ek559\mining_wq\raw_data\6_year_review_epa\six-year-review 2\sixyearreview_2_dh_part1_1\1,1,1-Trichloroethane_Chem2981.mdb",
        r"Z:\ek559\mining_wq\raw_data\6_year_review_epa\six-year-review 2\sixyearreview_2_dh_part6\VinylChloride_Chem2976.mdb",
        r"Z:\ek559\mining_wq\raw_data\6_year_review_epa\six-year-review 2\sixyearreview_2_dh_part2_1\Alpha Particles_Chem4000.mdb",
        r"Z:\ek559\mining_wq\raw_data\6_year_review_epa\six-year-review 2\sixyearreview_2_dh_part2_1\Beta Particles (Gross beta)_Chem4100.mdb",
        r"Z:\ek559\mining_wq\raw_data\6_year_review_epa\six-year-review 2\sixyearreview_2_dh_part2_1\Combined Radium-226_228_Chem4010.mdb",
        r"Z:\ek559\mining_wq\raw_data\6_year_review_epa\six-year-review 2\sixyearreview_2_dh_part6\Thallium_Chem1085.mdb",
        r"Z:\ek559\mining_wq\raw_data\6_year_review_epa\six-year-review 2\sixyearreview_2_dh_part6\Uranium_Chem4006.mdb",
    ]
    chem_labels = [
        "arsenic",
        "nitrate",
        "benzene",
        "carbon tetrachloride",
        "1,2-dichloroethane",
        "1,1-dichloroethylene",
        "1,1,1-trichloroethane",
        "vinyl chloride",
        "alpha particles",
        "beta particles",
        "radium",
        "thallium",
        "uranium",
    ]

    result = build_6year_review(mdb_files, chem_labels)
    print("\nDone.")
