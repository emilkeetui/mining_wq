# Copy-edit and citation review — `main.tex`

**Date:** 2026-09-07
**Branch:** `copyedit-main-tex-aea-citations` (not merged to `master`)
**Files touched:** `main.tex`, `citation.bib`
**Scope:** grammar and punctuation; citation format (AEA); numeric claims checked
against the generated tables; broken table/figure/equation references; front-matter
page fit; argument consistency across abstract, introduction and conclusion.

Every item below is tagged:

- **[CHANGED]** — applied to the file.
- **[SUGGESTED]** — *not* applied. Your call.
- **[CONFIRM]** — applied, but rests on an assumption you should verify.

---

## Build verification

Compiled with `latexmk -pdf` after every stage. Final state:

| Check | Result |
|---|---|
| Exit code | 0 |
| LaTeX errors | 0 |
| Undefined references | 0 |
| Undefined citations | 0 |
| Biber warnings | 0 |
| Overfull hboxes | 18 → **15** (the 3 removed were in the new bibliography; the remaining 15 are pre-existing — wide tables and one unbreakable `utility × contaminant × year` string) |
| Pages | 67 |
| Introduction begins on page | 3 → **2** (front matter now fits one page) |

All eight numeric corrections were re-checked in the rendered PDF text, not just
in the source.

---

# PART 1 — CHANGES APPLIED

## 1. Citation format → AEA

### 1.1 Citation system **[CHANGED]**

AEA reference style *is* Chicago author-date. Replaced the generic `biblatex`
`authoryear` style with `biblatex-chicago` `authordate`:

```latex
% was
\usepackage[backend=biber, style=authoryear]{biblatex}

% now
\usepackage[authordate, backend=biber, maxbibnames=99, dashed=false]{biblatex-chicago}
```

- `maxbibnames=99` — AEA lists **every** author in the reference list. You were
  silently truncating: "Bingham, Tayler et al." (7 authors), "Ravalli, Filippo
  et al." (8 authors).
- `dashed=false` — repeat the author name on consecutive entries by the same
  author rather than using a 3-em dash. Matches AER practice; you have three
  Keiser entries and six EPA entries where this shows.

Output before and after, same entry:

> **Before:** Allaire, Maura, Haowei Wu, and Upmanu Lall (2018). "National trends in drinking water quality violations". In: *Proceedings of the National Academy of Sciences* 115.9, pp. 2078–2083.
>
> **After:** Allaire, Maura, Haowei Wu, and Upmanu Lall. 2018. "National Trends in Drinking Water Quality Violations." *Proceedings of the National Academy of Sciences* 115 (9): 2078–2083.

In-text citations were already AEA-compatible and are unchanged in form:
`Keiser and Shapiro (2019a)`, `(Duflo et al. 2018; Zou 2021)`.

`\emergencystretch=3em` was added around `\printbibliography` so the long agency
URLs break instead of overrunning the right margin (removed 3 overfull hboxes).

### 1.2 All 64 cited entries rewritten **[CHANGED]**

Applied uniformly across every cited entry in `citation.bib`:

- Headline-case (title-case) article titles — AEA convention.
- Full journal names, title-cased.
- Scraped Google-Scholar `publisher` strings removed from `@article` entries
  (e.g. `publisher={American Economic Association 2014 Broadway, Suite 305,
  Nashville, TN 37203}`, `publisher={MIT Press ... journals-info~…}`).
- Page ranges normalised from en-dash characters to `--`.
- Author initials given periods; abbreviated given names expanded where the bib
  already contained enough information (`Gallego, JR` → `Gallego, José Luis R.`,
  `Wheelock, TD` → `Wheelock, Thomas D.`).

### 1.3 Citations that were genuinely broken **[CHANGED]**

| Key | Problem | Fix |
|---|---|---|
| `epaarsenicbat` | No `author`, so it cited inline as **"(Arsenic Removal from Drinking Water by Coagulation/Filtration U.S. EPA Demonstration Project at Conneaut Lake Park in Conneaut Lake, PA Final Performance Evaluation Report 2011)"** — the entire multi-line title in running text | `author = {{U.S. Environmental Protection Agency}}`; title collapsed to title + subtitle; retyped `@report` → `@techreport` |
| `epaarpcoalemp` | Same — cited as "(Impacts of the Acid Rain Program on Coal Industry Employment 2001)" | Same |
| `epaviolationreliability` | Same | Same |
| `naylor5537637strategic` | **No `year` field at all.** Rendered "Naylor and Deaton (n.d.)" in text and left a dangling empty "()" in the reference list | Retyped as `@techreport`, SSRN working paper 5537637 — see **[CONFIRM]** below |
| `parfitt2024there` | `author = {Parfitt, Parfitt}` (duplicated), and the `journal` field held an SSRN scrape: `Illegal Mining, Mercury Pollution, and Infant Health in the Amazon Rainforest*(August 20, 2024)` | Retyped `@techreport`; junk journal removed — see **[CONFIRM]** below |
| `bingham2000` | `ﬁ` ligature characters (U+FB01) in "beneﬁts" and "Ofﬁce"; "pollutioncontrol" missing a space; typed `@article` though it is an RTI report to EPA | Plain letters; space restored; retyped `@techreport` with `institution` |
| `ceto2000abandoned` | `journal = {Agency, EP (Ed.). USEPA, Seattle, WA}` — a scrape, not a journal | Retyped `@techreport`, EPA, Seattle WA |
| `angrist1994identification` | Title words reversed vs. the published title; no volume/issue/pages | "Identification and Estimation of Local Average Treatment Effects", *Econometrica* 62 (2): 467–475 |
| `shimshack2014economics` | Journal abbreviated: `Annu. Rev. Resour. Econ.` | *Annual Review of Resource Economics* |
| `olmstead2010economics` | No volume/issue/pages; lowercase journal name | *Review of Environmental Economics and Policy* 4 (1): 44–62 |
| `bennear2009sampling` | Typed `@misc` with a publisher and no journal | Retyped `@article`, *Environmental Science & Technology* 43 (14): 5176–5182 |
| `lee2020essays` | Typed `@book` with `publisher={Columbia University}` | `@phdthesis`, `school={Columbia University}` — now renders "PhD diss., Columbia University" |
| `freme2000us` | `@book` for an EIA statistical report | `@techreport` |
| `lattanzio2022clean` | `@book` for a CRS report; embedded newline and trailing space in the title | `@techreport`, title cleaned |
| `stratford2015coalprod` | `@article` with a working-paper series in `journal` | `@techreport`, WVU College of Business and Economics Working Paper |
| `Sealey2000` | `@article` with `journal={ABC News}` | `@misc` with `howpublished` |
| `Trump2025EO14260/14261`, `Trump2025Proc10914` | `@article` with `journaltitle={Federal Register}` | `@misc` with the Fed. Reg. citation in `note` |
| `bennear2008impacts` | Title contained curly double quotes, which nested badly inside biblatex's own quotes: `"The Impacts of the "Right to Know": …"` | Inner quotes changed to single: `'Right to Know'` |
| `10.1162/rest_a_01477` | Full abstract and an `eprint` PDF URL were being dumped into the reference list | Removed; kept DOI |

### 1.4 Items resting on an assumption **[CONFIRM]**

I did **not** invent bibliographic facts. Two entries could not be completed
honestly and need you:

1. **`naylor5537637strategic` — year.** The entry had none. I set `year = {2025}`,
   inferred from the SSRN ID range (5537637). **Verify against the actual SSRN
   posting date.** Leaving it empty produced "(n.d.)" plus a dangling "()", so
   doing nothing was not an option.

2. **`parfitt2024there` — author's first name.** The field read "Parfitt, Parfitt".
   I removed the bogus given name rather than guess, so it now renders
   **"Parfitt. 2024."** and cites as "(Parfitt 2024)". **Please add the first name.**

Three entries had volume/issue/pages **added from memory** because the reference
was otherwise incomplete. Worth a spot-check:

- `angrist1994identification` — *Econometrica* 62 (2): 467–475
- `olmstead2010economics` — *REEP* 4 (1): 44–62
- `bennear2009sampling` — *ES&T* 43 (14): 5176–5182

### 1.5 Cite-key coverage **[verified, no change needed]**

All 64 `\parencite`/`\textcite` keys resolve against `citation.bib` (119 entries).
No `??` anywhere.

---

## 2. Numbers in the text that disagreed with the tables **[CHANGED]**

Each was checked against the generating file in `output/reg/` or `output/sum/`.

| § | Was | Now | Source |
|---|---|---|---|
| §5.2 Balance | "Columns one and **three** use cumulative production…; columns **two and four** use an indicator" | "Columns one and **two** … columns **three and four**" | `pt_balance_6yr.tex` groups cols 1–2 = cumulative production, cols 3–4 = any mining. This is stale text left over from your recent "group columns by spec" relayout. |
| §5.1 | median = "90,000 cumulative short tons" | **94,000** | Table note: median = 0.0094 (10M ST) |
| §5.3 | "average… of **4 million tons**", effects "**30 percent, 9 percent, and 28 percent**" | "**4.4 million short tons**", "**35 percent, 10 percent, and 30 percent**" | Mean cumulative production = 0.4402 (10M ST). Rescaling the 79 / 23 / 69 percent per-10M-ST effects by 0.4402 gives 34.9 / 10.1 / 30.3. |
| §8 | enforcement visits = "a **200%** increase over baseline" | **300%** | 3.67 pp ÷ 1.16% baseline ≈ 3.2× |
| §7 | OLS effect "**1.6** to 1.9 percentage points" | **1.7** to 1.9 | Coefficients 1.67, 1.75, 1.94 |
| §7 | "OLS impact is **five times** smaller than the IV coefficient" | "**four to five times** smaller" | Ratios 5.1, 4.5, 3.6 |
| §4.1 | visits "1.5 to 2 times the **conditional** rate" | "**1.4 to 2.1** times the **unconditional** rate" | Conditional/unconditional was the wrong way round; multiples are 2.09, 2.10, 1.42 |
| §4.1 | MR violations last "**ten to fifteen** days" | "**eleven to sixteen** days" | Means 10.69, 12.27, 15.53 — 15.53 does not round to 15 |

**Numbers I checked and found correct** (no change): the 26 total MCL violations;
250–377 MR violations; 21% / 19% / 3.5% enforcement rates; 71% and 65% conditional
rates; 14% sanitary and 4% inspection visit shares; first-stage F = 27.52 and the
23.1 critical value; 319–432 concentration observations; arsenic 0.0023 mg/L = 79%
of the 0.0029 mean, 23% of the 0.010 MCL, 4.6% of the 0.050 MCL; selenium 0.0033 /
69%; barium 0.0171 / 23%; nitrate 0.0572 / 7.6% and the 743 million short-ton
extrapolation; the 9.9 / 7.5 / 6.3 and 9.9 / 7.4 / 7.1 and −0.02 / −0.8 violation
coefficients and their stars; 14 pp sanitary visits; 5.7 pp formal enforcement;
59 and 26 pp nitrate-threshold effects; 18–23 pp and 1.3–3.7 pp SYR2 comparisons;
balance-test p-values 0.31 and 0.75; the $191,970 arsenic-system cost breakdown
(sums correctly); 4 / 6.1 / 4.6 percent mean MR violation rates.

---

## 3. Broken table / figure / equation references **[CHANGED]**

No reference was *undefined* — all 43 resolve. But two pointed at the wrong
**kind** of object, and several were inconsistently capitalised.

- **Wrong float type (2).** `\ref{map:map_huc12_main_sample}` and
  `\ref{map:proportionatecircle_upstream_mines_huc12_1985_2005}` are `figure`
  environments, so LaTeX numbers them "Figure N" — but the text called them
  "In map 5" and "Map 7". Both changed to **Figure**. (A third reference to a
  `map:` label already said "Figure" correctly, which is what exposed the
  inconsistency.)
- **Capitalisation (6).** Lowercase `table \ref{...}` → `Table \ref{...}` in
  §4.1 (×2), §4.2 and §5.1. Lowercase `equation \ref{...}` was left alone —
  AEA capitalises Table and Figure but not equation, and your usage is already
  consistent.

### 3.1 Equation 3 had a real index error **[CHANGED]**

```latex
% was — the summand does not depend on the summation index
\beta\cdot\sum_{\tau=1985}^t \text{upstream coal prod}_{ct}

% now
\beta\cdot\sum_{\tau=1985}^t \text{upstream coal prod}_{c\tau}
```

Fixed in both the display equation and the sentence below it that repeats the term.

---

## 4. Grammar, punctuation and typography **[CHANGED]**

96 edits total (94 applied by an exact-match script that aborts unless each
target matches exactly once, plus 2 hand edits).

### 4.1 Substantive repairs

| § | Problem | Fix |
|---|---|---|
| §6 | **Sentence broken mid-list by a stray period:** "…did not affect the scope of the ARP**. the** stringency of the ARP law, the degree to which…" | Comma; list restored |
| §4.3 | "The NHDplus hydrological dataset identifies the boundaries and connectivity of watersheds across the US, **as well as an EPA dataset on** the watershed-level location of utility water intakes." — NHDplus does not identify an EPA dataset | Split into two sentences: "…across the US. I combine it with an EPA dataset on…" |
| §5.2 | "utility size does not predict how much coal is mined upstream, **how many water intakes it operates**, whether it draws on surface water…" — reverses the regression (size predicting its own intakes) | "neither utility size, nor the number of water intakes a utility operates, nor whether it draws on surface water, nor whether it is publicly owned **predicts how much coal is mined upstream**" |
| §6 | "an OLS **estimate of coal production on utility behavior**" — reversed | "an OLS **regression of utility behavior on coal production**" |
| §8 | "in order to **coneal** contaminant exceedances" | conceal |
| §7 | "Coal mining **increase** the likelihood" | increases |
| §4.1 | "**Enforcement more likely** to occur during a violation" — missing verb | "Enforcement **is** more likely" |
| §2 | "These systems serve at least 25 consumers **through** at least 15 connections" — the SDWA definition is 25 year-round residents **or** 15 service connections, not both | "serve at least 25 year-round residents **or** have at least 15 service connections" |
| §1 | "the **Toxic** Release Inventory" | **Toxics** Release Inventory (EPA's actual program name) |
| §2 | "receive **comparably** stricter enforcement" | "receive stricter enforcement" |
| §4.3 | "a unique **2-12 digit** code known as a HUC (**hydrological** unit code)" | "a unique **2- to 12-digit** code known as a **hydrologic** unit code (HUC)" |
| §4.4 | "in coal deposits in the **watershed's** upstream of the utility" — possessive for plural | watersheds |
| §4.4 | "while **low sulfur (less than two percent sulfur) was** more resilient" — missing noun | "while low-sulfur … **coal production** was more resilient" |
| §7 | "in **our** sample" — single-authored paper | my sample |
| §2 | "an on-site evaluation conducted by the state or tribal agency **of eight components**" — misplaced modifier | Commas: "an on-site evaluation, conducted by the state or tribal agency, of eight components" |
| §2 | "based on the **visit-reason**" | "based on the reason for the visit" |
| §3 | "support $[0,\bar c]$ **that does not vary with $m$**" immediately followed by "$G(\cdot;m)$ depends on $m$" — reads as a contradiction | "…, **where the support itself** does not vary with $m$" (see also Suggestion #4) |
| §3 | "it is one of the predictions **of** the empirical work" — model predicts, empirics test | "one of the predictions **tested in** the empirical work" |
| §8 | "imposes no direct monetary cost…, such as installing treatment machinery" | "…such as **the cost of** installing treatment machinery" |
| §8 | "including enforcement, **visits**, and inspections" (visits including visits) | "including sanitary surveys, enforcement visits, and inspections" |
| Appendix | "do not self-report (MR)" vs. "under-report (MR)" for the same branch in two equations | Both now "under-report (MR)" |
| Appendix | "summarised" (British) in an otherwise American-spelling document | summarized |
| §4.2 | "MCL of **0.01** mg/L" next to "0.010 mg/L" elsewhere; "which **became regulation** in 2006" | "0.010 mg/L, which **took effect** in 2006" |
| §4.1 heading | "Utility **characteristic**, regulator, and violation data" | characteristics |

### 4.2 Subject–verb agreement with multi-author citations

- `\textcite{bingham2000} **finds**` → **find** (7 authors, renders "Bingham et al.")
- `\textcite{10.1162/rest_a_01477} **documents**` → **document** (3 authors, renders "Mu, Rubin, and Zou")

Checked and left alone: `\textcite{zou2021unwatched} shows` (single author, correct),
`\textcite{malik1993self} finds` (single author, correct), `\textcite{duflo2018value}
find` (4 authors, already plural).

### 4.3 LaTeX quotation marks — 9 sites

Straight double quotes render in LaTeX as **two closing quotes**: `"SDWA"` came
out as ”SDWA”. All converted to `` ``…'' ``, which now renders "SDWA":

`("SDWA")`, `("IOC")`, `("MCL")`, `("MR")`, `("AMD")`, `("SDWIS")`, `("ECHO")`,
`("SYR2")`, `("MDL")`, `The "Whole panel" columns` (×2), `The "During MR year"
and "During MCL year" columns`.

### 4.4 Mechanical consistency fixes

| Rule | Count | Examples |
|---|---|---|
| `coal fired` → `coal-fired` | 4 | §1, §2 (×2), §6 |
| `high sulfur` / `low sulfur` → hyphenated before a noun | ~30 across 12 edits | The document was inconsistent *within a single sentence* in §4.4: "high-sulfur and low sulfur HUC12 watersheds" |
| Apostrophe plurals | 6 | `IOC's` → `IOCs`; `HUC12's` → `HUC12s` (×5) |
| `phase I` / `phase II` → `Phase I` / `Phase II` | 4 | §2 used lowercase, §6 used uppercase |
| Compound adjectives | 9 | `information gathering` → `information-gathering`; `point source pollution` → `point-source` (×2); `pollution producing` → `pollution-producing`; `court ordered` → `court-ordered`; `profit maximizing` → `profit-maximizing`; `within region` → `within-region`; `state by year` → `state-by-year`; `electricity generating` → `electricity-generating`; `two stage least squares` / `reduced form` → hyphenated |
| Adverb hyphens removed | 1 | `nationally-determined` → `nationally determined` |
| Other | 5 | `high polluting` → `highly polluting`; `on-going` → `ongoing`; `U.S.` → `US` (document uses US elsewhere); `proposition 2` → `Proposition 2`; `10 million cumulative tons` → `cumulative short tons` |
| Missing commas | 7 | before `so that`, `because`, `but`, `which`, and after introductory clauses |
| Punctuation | 2 | `is small $q(a)\to\epsilon$` → comma added; `falls; and the concentration readings` → semicolon → comma |
| Date range | 1 | `1998-2005` → `1998--2005` |

---

## 5. Front matter on one page **[CHANGED]**

**It was already spilling before I touched it** — the Introduction started on
page 3, with Keywords and JEL classification sitting alone on page 2.

Fixed typographically, without touching your prose:

```latex
% 1. ~1 inch of dead space sat between "August 2026" and "Abstract" —
%    \maketitle's trailing skip plus the center environment's \topsep.
\vspace{-2.5em}
\begin{center}\begin{abstract}

% 2. The center environment adds \topsep above AND below. That alone was
%    enough to push the keywords block onto page 2. \centering adds none.
\begingroup
\vspace{0.5em}
\centering
\begin{minipage}{0.85\textwidth}
\singlespacing\footnotesize      % was \small
...
\par\smallskip                   % was a blank line + \medskip
```

Title, abstract, keywords, JEL codes and the acknowledgements footnote now all
fit page 1, and the Introduction starts on page 2. Verified by rendering the page.

---

## 6. JEL codes — all six are correct **[verified]**

| Code | Meaning | Fit |
|---|---|---|
| D82 | Asymmetric and Private Information; Mechanism Design | Core — self-reporting under private information |
| K42 | Illegal Behavior and the Enforcement of Law | Core — enforcement, penalties |
| L95 | Gas Utilities; Pipelines; **Water Utilities** | Core — the industry |
| Q48 | Energy: Government Policy | The ARP / coal |
| Q53 | Air Pollution; **Water Pollution**; Hazardous Waste | Core — the contamination |
| Q58 | Environmental Economics: Government Policy | Core — SDWA |

**[CHANGED]** Reordered alphanumerically (`D82; K42; L95; Q48; Q53; Q58`) per AEA
convention — they were in `Q53; Q58; K42; L95; D82; Q48` order.

**[SUGGESTED]** Consider adding **L51 (Economics of Regulation)**. The paper's
headline contribution is about regulatory *design* — self-monitoring versus
inspection versus penalty — and L51 is where that literature sits. There is room
on the line without breaking the one-page fit.

---

## 7. Argument consistency: abstract / introduction / conclusion

Checked against your four-part argument:

1. Mining raises contamination but not above the MCL.
2. Under-reporting rises because of self-reporting costs.
3. Regulators respond with more visits and low penalties.
4. Utilities are likely not concealing — the high visit rate does not produce
   high penalties, which suggests nothing is found.

| | Abstract | Introduction | Conclusion |
|---|---|---|---|
| 1 | ✔ already | ✔ already | ✔ already |
| 2 | ✔ already | ✔ already | ✔ already |
| 3 | ✔ already | ✔ already | ✔ already |
| 4 | **fixed** | ✔ already (§1) | **added** |

### 7.1 Abstract **[CHANGED]**

The abstract claimed the visits come *"with little subsequent change in
contaminant levels."* **The paper never estimates post-visit contaminant
levels** — what §8 shows is that the visits turn up no violations. So this was
both unsupported and a weaker version of your own point. Replaced with:

> …an additional upstream mine raises the likelihood of a regulator visit by 14
> percentage points, **yet those visits uncover no contaminant limit violations.**

This is accurate to §8 *and* delivers argument element 4.

### 7.2 Conclusion **[CHANGED]**

Element 4 appeared in the Introduction (§1) and the Discussion (§9) but the
Conclusion stopped at "attention rather than sanction" and never drew the
inference. Added one sentence, worded from your own Discussion paragraph so the
voice matches:

> …while lowering the likelihood of formal enforcement by 5.7 percentage points.
> **That regulators visit these utilities so much more often without formal
> enforcement following suggests the visits find nothing to sanction, and that
> utilities are not under-reporting in order to conceal a contaminant exceedance.**
> The regulator can use sanitary visits to assess…

This is the one place I added new argumentative prose rather than only
suggesting. If you would rather phrase it yourself, it is a single self-contained
sentence and easy to swap.

---

# PART 2 — SUGGESTIONS ONLY (nothing below was changed)

## 8. Things that do not make sense, or that a referee will attack **[SUGGESTED]**

1. **SYR2 excludes Pennsylvania — but Pennsylvania is your biggest state.**
   §4.2 states SYR2 "excluded Pennsylvania, Mississippi, Kansas, and Louisiana
   because those states failed to submit records." §4.4 then states "The highest
   number of watersheds in my sample is located in **Pennsylvania**, Kentucky,
   and West Virginia," and §4.5 that "Coal production mostly decreased in
   Pennsylvania." So your entire concentration analysis (§5) drops the state
   contributing the most sample watersheds, and this is never reconciled. A
   referee goes straight here. Worth a sentence or two on how the surviving
   concentration sample compares to the full violations panel.

2. **§9 mischaracterises the 10M ST unit as an observed maximum.**
   "…even at the maximum contaminant level observed in the sample and the
   **highest single-year dose of upstream coal production: 10 million short
   tons**." 10 million short tons is your *coefficient scaling unit*, not an
   observed maximum — the maximum cumulative upstream production in the sample
   is 14.18 (10M ST) = **141.8 million** short tons. As written this reads as an
   empirical claim about the data and is wrong. The underlying arithmetic (that
   barium, nitrate and selenium stay under their MCLs) does hold; only the
   description of the dose is wrong.

3. **Notation collision in equation 3.** `τ` is simultaneously the summation
   index (`\sum_{\tau=1985}^t`) and the year fixed effect (`HUC02_h·τ_t`) in the
   same equation. Rename one of them.

4. **§3 model setup, self-reporting cost distribution.** Even after my
   disambiguation, check this is what you meant. The text says the support does
   not vary with `m`, then the next sentence says `G(·;m)` shifts with `m`. Those
   are compatible (a distribution can shift on fixed support only if it is not a
   strict first-order shift to the right of the *support*), but the pairing
   invites the reader to think you have contradicted yourself. Consider stating
   explicitly that `m` reweights mass within a fixed `[0,c̄]`.

5. **§5.3, nitrate insignificance.** "This small increase could explain why the
   coefficient lacks significance." A small point estimate does not explain
   insignificance — imprecision does. The SE is 0.0922 on an estimate of 0.0572.
   Say that instead.

6. **§7, circular sentence.** "Compliance costs rise with mining since the
   baseline water contamination and the effort required to treat water to any
   given standard increase, **raising compliance costs**." The premise restates
   the conclusion.

7. **§8, self-cancelling example.** "An enforcement visit, by contrast, imposes
   **no** direct monetary cost on the utility, **such as** installing treatment
   machinery." The "such as" clause illustrates a cost immediately after
   asserting there is none. (I patched the grammar to "the cost of installing
   treatment machinery" but the logic still needs your hand — I think you mean
   the visit imposes no cost *of the kind that formal enforcement does*.)

8. **§10, garbled sentence.** "Regulator preferences affect enforcement, not only
   violation severity." I believe you mean: enforcement responds to regulator
   preferences, not only to violation severity.

9. **§6 uses three names for one assumption.** "Exogeneity requires the
   instrument to only affect utilities through…", then "The **exclusion
   restriction** fails when…", then "Another **exogeneity** threat is local
   economic activity." These are the same condition. Pick one term (exclusion
   restriction) and use it throughout.

10. **Two notes-to-self are still in the running text.** §4.5: "However, I have
    ongoing work to estimate the size of the population served…"; §6: "Absorbing
    this channel requires state-by-year fixed effects, **which I plan to
    incorporate in the near future**." Both read as drafting notes. Cut, or move
    to footnotes.

11. **Two uncited empirical claims.** §1: "utilities provide drinking water to
    **85 percent** of US households." §10: "Small utilities find the burden of
    water quality management particularly heavy."

12. **§6 says "the 20 year time span I study."** 1985–2005 is 21 years, and your
    own table note says "up to 21 years (1985--2005)."

13. **`SO2` and `NOx` want subscripts** — SO₂, NOₓ. Four instances in §2. I left
    these because they are typography rather than grammar, but they read as typos
    in a chemistry-adjacent paper.

14. **Figure caption inconsistency, `map_huc12_main_sample`.** Its caption is a
    full explanatory sentence ("Shading distinguishes HUC12 watersheds that lie
    directly upstream…") where every other figure has a short title-style caption
    plus a separate `\textit{Notes:}` block. Meanwhile the green/red colour key
    lives only in the body text of §4.4. Suggest: short title caption + move the
    colour description into a Notes block, matching your other figures.

15. **Two label-hygiene issues in the pipeline** (harmless — both resolve — but
    worth fixing at the source script so they do not bite later):
    - `output/reg/mr_concentration_lag_ols.tex` carries the label
      `tab:mr_concentration_lag_logit`. Filename says OLS, label says logit.
    - `output/reg/exclusion_test_num_facilities.tex` uses the label
      `exclusion_test_num_facilities` — no `tab:` prefix, unlike every other table.

## 9. Prose and flow **[SUGGESTED]**

1. **§1:** "Self-reported compliance underpins regulations **as diverse as** the
   income tax, and wherever the cost of reporting rises…" — "as diverse as"
   promises a list and delivers a single item. Either add a second example or
   drop the phrase.

2. **§1:** "any inspection shifts the cost of monitoring onto regulators, **the
   efficiency of which** is discussed in the literature on fiscal federalism."
   The referent of "which" is ambiguous (the shift? the inspection? the cost?),
   and fiscal federalism arrives with no setup and is never returned to.

3. **§2:** "self-reporting costs, **which are expensive in and of themselves**"
   — costs are not expensive; they *are* the expense.

4. **§4.1:** "Regulators rarely use visits to respond to MCL violations. Visits
   rarely coincide with MCL violations" — consecutive sentences saying the same
   thing.

5. **§7:** "leads to a 1.5 to 2.4 percentage point reduction in the likelihood
   that a utility experiences an MCL or MR violation … of any kind **after 1995
   compared to before 1995**" — "after 1995" appears twice in one sentence.

6. **§2:** "Arsenic, nitrates, barium, and selenium are commonly **produced**
   during coal mining" — they are mobilised or released, not produced. Cheap
   accuracy win in a section a geochemist may read.

7. **§2:** "**Coal mines with high sulfur** have a limited ability to
   post-process the coal" — mines do not have sulfur; the coal does.

8. **Throughout:** you treat `data` as a singular mass noun ("The data
   contains…", "This data does not confirm…"), which is internally consistent.
   AEA house style prefers the plural. Worth one deliberate decision either way.

9. **§4.1:** "SDWIS ECHO often records violations as starting when utilities fail
   to meet regular testing schedules **and then continue** for a fixed period
   after they are issued rather than recording the precise dates…" — long, and
   the subject of "continue" drifts from "SDWIS ECHO" to "violations".

10. **§5.4:** "The section **establishes descriptive evidence for** how coal
    production affects…" — "provides descriptive evidence on" reads better.

11. **§3:** "$(r - ps)q(a)$ is the wedge between…" — starting a sentence with a
    math expression. AEA discourages this.

## 10. Structural suggestions **[SUGGESTED]**

1. **The literature review is doing two jobs at once.** §1 paragraphs 4–7
   alternate between *drinking-water and health* work and *self-reporting and
   enforcement theory*, and then the three-contributions paragraph has to re-sort
   them for the reader. Consider two clearly-signposted blocks — "self-reporting
   and monitoring" then "drinking water, mining and health" — so the reader can
   hold the map. Your contributions paragraph is genuinely strong; right now it
   is doing repair work the review should have done.

2. **§5 (concentrations) undercuts itself before it lands.** You open the
   section, then §5.1 closes with a full paragraph of disclaimers ("I do not
   treat these estimates as causal…"), and §5.4 repeats them. This section is
   what licenses the entire IV exercise — it is load-bearing. Consider stating
   the caveats once, compactly, up front, then letting the results stand.

3. **The nitrate-threshold test is buried.** It is contribution #1 in your
   introduction — the cleanest evidence you have that the *cost* channel, not
   concealment, drives under-reporting — but it appears in §9 Discussion. Consider
   promoting it to a short section right after §7 (violations), where the reader
   has just learned MR violations rise and is actively asking *why*. Currently
   they wait two sections for the answer.

4. **§4.5's population-backcasting paragraph** breaks the flow of the data
   section and describes work that is not in the paper. Footnote or appendix.

5. **§9 Discussion and §10 Conclusion overlap substantially.** Both walk through
   the visit/enforcement asymmetry and the non-concealment inference. Consider
   making §9 purely about mechanism and welfare (including the
   who-should-monitor question you raise), and §10 purely about the policy
   implication — that penalties for non-monitoring, not MCL stringency, are the
   lever.

---

# PART 3 — Open items

| Item | Owner | Note |
|---|---|---|
| Confirm `naylor5537637strategic` year (set to 2025) | You | See §1.4 |
| Add first name for `parfitt2024there` | You | See §1.4 |
| Spot-check 3 entries with volume/pages added from memory | You | See §1.4 |
| Reconcile Pennsylvania exclusion from SYR2 | You | Suggestion #1 — highest-priority referee risk |
| Fix "10 million short tons" dose description in §9 | You | Suggestion #2 |
| Decide on L51 JEL code | You | §6 |
| Fix two pipeline label issues | You | Suggestion #15 — in `run_main_tables.r`, not in `main.tex` |
| Merge branch to `master` | You | Nothing is committed yet |

**Branch:** `copyedit-main-tex-aea-citations`
**Session log:** `.claude/logs/2026-09-07-main-tex-copyedit-aea-citations.md`
