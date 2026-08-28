# Table & Figure Formatting Conventions

**Applies to every table (`output/reg/`, `output/sum/`) and figure (`output/fig/`)
produced by the pipeline, and their mirrored copies in
`writeup/Mining_and_Water_Quality (1)/sum/` and `.../reg/`.** These are numeric-
and layout-formatting rules; see `table-notes-conventions.md` for notes-text
content rules specifically.

## The Rules

1. **Notes are left-justified.** Table notes and figure captions are set
   ragged-right (`\raggedright`), never centered or fully justified. (This is
   already implied by the `\raggedright` used inside the notes minipage/box —
   treat it as a hard requirement, not an incidental default.)

2. **No scientific notation.** Every number displayed in a table or figure
   (coefficients, SEs, N, F-stats, axis tick labels, etc.) must be written in
   fixed-point decimal form. Never show `1.2e-04`, `3.4E+06`, or similar —
   round to fixed decimal places instead (see Rule 3).

3. **Consistent significant figures within a table/figure.** Pick one number
   of decimal places for a given table (or a given figure's axis) and apply
   it uniformly to every numeric entry of the same kind — e.g. if
   coefficients are shown to 3 decimals, every coefficient and SE in that
   table is shown to 3 decimals, not a mix of 2 and 4. Do not let R's default
   `print`/`format` truncate trailing zeros inconsistently (`0.100` must not
   appear as `0.1` next to `0.123` in the same column).

4. **Decimal alignment within columns.** Numbers in the same table column
   must visually align on the decimal point when the column contains
   decimals. Use `dcolumn`/`siunitx` `S` columns (or manually pad with
   `\phantom{}`) — do not left- or right-align a mixed-decimal numeric column
   with plain `l`/`r` column specifiers.

5. **Capitalized display labels.** Any variable name shown to a reader —
   table row/column labels, figure axis labels, legend entries — must start
   with a capital letter (e.g. "Sulfur (Unified)", "Number of Coal Mines"),
   never the raw snake_case identifier (`sulfur_unified`, `num_coal_mines`).
   Build a label/`dict` mapping from the CLAUDE.md glossary name to a
   capitalized display string and pass it to `etable(..., dict = ...)` (or
   the figure's `labs()`/`scale_*_discrete()` call) rather than relabeling by
   hand at each call site.

6. **Binary-outcome coefficients are scaled to percentage points.** When the
   dependent variable is a 0/1 indicator, multiply the displayed coefficient
   and its SE by 100 so the table communicates percentage-point change units,
   not a fraction of one. Apply the scaling consistently to every column in
   the table that shares that binary outcome, and do not silently rescale a
   `_share` outcome that is a continuous share rather than a strict 0/1 —
   only true binary outcomes get the ×100 treatment. State the units in the
   table notes (e.g. "Coefficients are in percentage points.") per
   `table-notes-conventions.md`.

7. **No fixed-effects row when fixed effects are uniform across columns.**
   If every column in a regression table includes the same set of fixed
   effects, omit the fixed-effects checkmark row(s) from the table body
   entirely, and state which fixed effects are included in the notes text
   instead, in plain language (e.g. "All specifications include watershed,
   year, and state fixed effects."). If fixed effects differ across columns,
   keep the checkmark rows in the table body and do not discuss fixed
   effects in the notes — see the corresponding exception in
   `table-notes-conventions.md` Rule 7.

## Implementation Notes

- `etable()` accepts a `digits` argument — set it explicitly rather than
  relying on the default, and use the same value across all tables in a
  given output family (summary stats vs. regression tables can differ from
  each other, but must be internally consistent).
- For the binary-outcome ×100 scaling, rescale the underlying coefficient/SE
  vectors before passing them to `etable()` (or use `etable(..., scalefix =
  100)` per-model where supported) rather than hand-editing the rendered
  `.tex` — hand-edits get silently overwritten the next time the script runs.
- For hand-assembled multi-panel tables (see `r-code-conventions.md` /
  `CLAUDE.md` on `wrap_for_beamer()` vs. `style.tex("aer", adjustbox = TRUE)`
  nesting), apply `dcolumn`/`siunitx` alignment and the capitalized-label
  dict inside each panel individually.
- For figures (`ggplot2`), no-scientific-notation and consistent-digits map
  to `scale_*_continuous(labels = scales::label_number(accuracy = ...))`
  rather than the default `scales::label_scientific()`/auto formatter.

## Verification

After editing a table- or figure-generating script and re-running it:
1. Read the regenerated `.tex`/`.png` output and check it against all seven
   rules above.
2. Confirm no cell or axis label contains `e+`, `e-`, `E+`, or `E-` notation.
3. Confirm every numeric column that should align on the decimal point does
   so when rendered (compile the `.tex` and visually inspect, or check the
   `dcolumn`/`siunitx` column spec in the source).
4. If the table is mirrored into `writeup/Mining_and_Water_Quality (1)/sum/`
   or `.../reg/`, copy the regenerated file there and recompile `main.tex`
   to confirm it still builds.
