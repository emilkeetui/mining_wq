# Python Code Conventions

## Python Executable

**Always use the full venv path. Never use `python`, `python3`, or `py`.**

```bash
"Z:/ek559/nys_algal_bloom/NYS algal bloom/code2/Scripts/python.exe" script.py
# or inline:
"Z:/ek559/nys_algal_bloom/NYS algal bloom/code2/Scripts/python.exe" -c "import pandas; ..."
```

## Header Block (required on every script)

```python
# ============================================================
# Script: [name].py
# Purpose: [one-line description]
# Inputs: [files read]
# Outputs: [files written]
# Author: EK  Date: YYYY-MM-DD
# ============================================================
```

## Naming and Style

- Snake_case for all variable and function names
- Variable names must match the CLAUDE.md glossary exactly
- No hardcoded absolute paths — use `pathlib.Path` relative to the project root
- `random.seed()` / `np.random.seed()` required in any script using randomness

## Parquet I/O

- **Write:** `df.to_parquet(path, index=False, engine="pyarrow")`
- **Read:** `pd.read_parquet(path, engine="pyarrow")`
- Always specify `engine="pyarrow"` explicitly

**Cross-language schema rule (critical):** before writing any parquet that will be
read by an R script downstream, enforce correct types and drop geometry:

```python
# Enforce types
df["PWSID"] = df["PWSID"].astype(str)   # must be str, not int
df["year"]  = df["year"].astype("int64")

# Drop geometry if this is a GeoDataFrame
if hasattr(df, "geometry"):
    df = df.drop(columns="geometry")

# Log dtypes before write — catch silent mismatches
print(df.dtypes)

df.to_parquet(output_path, index=False, engine="pyarrow")
```

Failure to do this causes silent merge failures in R (PWSID int vs character).

## Spatial Operations

- Log CRS before and after every spatial join:
  ```python
  print(f"Left CRS: {left_gdf.crs}")
  print(f"Right CRS: {right_gdf.crs}")
  assert left_gdf.crs == right_gdf.crs, "CRS mismatch — reproject before joining"
  ```
- Standard CRS for this project: EPSG:4326 (WGS84) for storage; EPSG:5070 (Albers) for
  area/distance calculations

## Output and File Safety

- Write all outputs to `clean_data/`, never `raw_data/`
- Check for existing output before writing:
  ```python
  if output_path.exists():
      print(f"WARNING: {output_path} already exists — overwriting")
  ```
- After writing, validate row count:
  ```python
  result = pd.read_parquet(output_path, engine="pyarrow")
  print(f"Written {len(result):,} rows × {result.shape[1]} columns to {output_path}")
  ```
