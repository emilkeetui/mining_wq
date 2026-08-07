# Table Notes Conventions

**Applies to every table `\input{}`'d into the main body of `main.tex`** (summary
tables in `output/sum/` and regression tables in `output/reg/`, and their mirrored
copies in `writeup/Mining_and_Water_Quality (1)/sum/` and `.../reg/`). Appendix
tables (anything under a commented-out or `\subsection{Appendix...}`-style block)
are exempt.

## The Rules

1. **Notes must begin with `\textit{Notes:}`** — every table's footer text starts
   with this literal string, styled in italics.
2. **No variable names.** Never refer to a variable by its code identifier (e.g.
   `minehuc_downstream_of_mine`, `sulfur_unified_sum`, `ENF_ACTION_CATEGORY`,
   `VISIT_REASON_CODE`). Describe it in plain language instead (e.g. "strictly
   downstream", "sum of coal sulfur content across upstream watersheds", "a
   formal enforcement action").
3. **No cross-references to other tables.** Do not write `Table~\ref{...}` or
   otherwise point the reader to another table in the notes.
4. **No file paths.** Never write a `clean_data/...` or `output/...` path in a
   table note.
5. **No individual sample IDs.** Do not name which specific PWSID/CWS was
   dropped from the sample (e.g. "excluding PWSID WV3303401"). If a note must
   describe an exclusion, describe the rule, not the identifier it removed.
6. **Every regression table must include the significance-stars legend**
   (`*** p<0.01, ** p<0.05, * p<0.1`) in its notes, even if the table itself
   never produces a starred coefficient.
7. **No discussion of fixed effects in the notes text.** Checkmark rows for
   fixed effects inside the table body (e.g. a "CWS fixed effects" row with
   `\checkmark` cells) are fine — that's table structure, not notes prose. The
   notes paragraph itself must not describe which fixed effects are included.
8. **No description of how the sample was cleaned.** Don't narrate cleaning
   steps (imputation choices, drop thresholds, filters applied) in the notes —
   describe only the resulting sample in plain terms (e.g. "community water
   systems strictly downstream of a coal mine").
9. **No mention of whether the table is a robustness check.** Do not write
   "(robustness)" or otherwise flag a table's role relative to a main
   specification in its caption or notes.

## Where This Lives in Code

Table notes are built as R string literals (usually `paste0(...)` chains) passed
to `etable(..., notes = ...)` or hand-assembled into `writeLines()`-based LaTeX.
When writing or editing a table-generating script:

- Put `\textit{Notes:}` at the very start of the note string, before any other
  prefix (e.g. a "Sample period ..." clause) — if you build the note by
  concatenating a period-specific prefix with a shared base string, put the
  `\textit{Notes:}` marker on the *outer* concatenation, not baked into the
  base string, or it will land in the wrong place.
- Watch for **later-loaded packages clobbering your fixes** the same way you'd
  watch for it in the preamble — e.g. if a shared `notes` helper is reused
  across many `run_*_tables()` calls, fix the shared string once rather than
  patching each call site.
- For tables built with `tinytable`/`tt()`, prefer hand-assembled LaTeX
  (`writeLines()` of a `c(...)` vector) instead, since `tinytable`'s footnote
  API does not cleanly support the italicized `\textit{Notes:}` prefix
  required here.

## Verification

After editing a table-generating script and re-running it:
1. Read the regenerated `.tex` file and check it against all nine rules above.
2. Confirm the note text is inside `{\tiny\linespread{1}\selectfont \par
   \raggedright ...}` (or the `\begin{minipage}...\end{minipage}` equivalent
   for `\hline`-style tables), positioned per the nesting rules in
   `r-code-conventions.md` / the beamer-table nesting rules in `CLAUDE.md`.
3. If the table is mirrored into `writeup/Mining_and_Water_Quality (1)/sum/` or
   `.../reg/`, copy the regenerated file there and recompile `main.tex` to
   confirm it still builds.
