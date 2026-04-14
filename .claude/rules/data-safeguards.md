# Data Safeguards

**raw_data/ is strictly read-only. Violations are blocked by the protect-raw-data hook.**

## raw_data/ Rules

- Never write, modify, overwrite, or delete any file in `raw_data/`
- Never run `rm`, `unlink()`, `file.remove()`, or any destructive operation on `raw_data/`
- Never use `>` redirection into `raw_data/`
- All cleaning and transformation outputs go to `clean_data/`

The `protect-raw-data.py` hook will hard-block (exit 2) any such attempt.

## Before Writing Any Intermediate File

1. Check whether the file already exists at the output path
2. If it exists: stop and ask the user whether to overwrite, and explain what will change
3. Only overwrite if the user explicitly confirms

**Exception:** if important changes to a build script mean downstream scripts need the
new version to run correctly, flag this and propose the overwrite with a diff summary.

## Before Loading Large Files

- R: `file.info("path/to/file")$size` — flag if > 100 MB before loading
- Python: `os.path.getsize("path/to/file")` — flag if > 100 MB before loading
- Flag if an operation will produce output > 500 MB

## Pipeline Output Paths

| Step | Script | Output |
|------|--------|--------|
| 1 | `readmshatxt.r` | `clean_data/coal_mine_prod_charac.parquet` |
| 2 | `minegeomatch.py` | `clean_data/huc_coal_charac_geom_match.parquet` |
| 3 | `huc_coal_charac_geom_match.py` | `clean_data/huc_coal_charac_geom_match.parquet` |
| 4 | `sdwismatch*.py` | `clean_data/cws_data/...` |
| 5 | `match_prod_vio_sulfur.py` | `clean_data/cws_data/prod_vio_sulfur.parquet` |
| 6 | `didhet.r` / `run_main_tables.r` | `output/reg/*.tex`, `output/fig/*.png` |
