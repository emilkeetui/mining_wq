# Session: 2026-06-08 — Beamer table formatting for regulator response table

## Objective
Make `regulator_response_by_viol_type_main_states.tex` usable via `\input{}` in both a regular LaTeX document and a Beamer presentation.

## Changes Made
- `code/coal_mining_water_quality/regulator_response_by_viol_type_main_states.r`: removed `\begin{frame}{...}` / `\end{frame}` wrapper from `make_frame()` so the output file contains only the table body
- Same script: replaced `\resizebox{\textwidth}{!}{...}` with `\begin{adjustbox}{max width=\textwidth, max totalheight=\textheight, keepaspectratio, center}` so the table scales to fit a beamer slide both horizontally and vertically
- Re-ran script; output written to `output/sum/regulator_response_by_viol_type_main_states.tex`

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| Remove frame wrapper | User wants to control frame placement in beamer and use the same file in regular LaTeX with `\input{}` |
| Switch from `\resizebox` to `adjustbox` | `\resizebox{\textwidth}{!}` only constrains width; table was too tall for a beamer slide. `adjustbox` with `max totalheight=\textheight` handles both dimensions. `adjustbox` already in user's preamble. |

## Verification Results
- [x] Script runs end-to-end (exit 0)
- [x] Output exists at `output/sum/regulator_response_by_viol_type_main_states.tex`
- [x] No `\begin{frame}` in output file

## Required preamble packages
- `\usepackage{booktabs}` — for `\addlinespace`
- `\usepackage{adjustbox}` — for the resize wrapper (already in user's beamer preamble)
