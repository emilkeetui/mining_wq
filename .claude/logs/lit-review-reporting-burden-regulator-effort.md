# Literature Review: Reporting Burden → Self-Reporting Behavior; Regulator Effort Under Rising Task Cost
Date: 2026-07-31

**Framing anchor.** This review covers two strands requested for the JMP that are
*distinct* from the strategic-concealment literature already synthesized in
[`lit-review-self-monitoring-compliance.md`](lit-review-self-monitoring-compliance.md)
(Kaplow-Shavell, Zou 2021, Mu-Rubin-Zou 2026, Andarge et al. 2025, Bennear et al. 2009,
Blundell-Gowrisankaran-Langer 2020). That literature is about entities *choosing* to hide
or manipulate what gets measured because an adverse reading is costly. The two strands below
are about a *different*, non-strategic channel: reporting/testing falls simply because doing
it has gotten more onerous or costly — a mechanical burden response — and about whether
regulators themselves sustain enforcement effort when their job gets harder. Both bear on
this paper's identification: if contamination raises the CWS's own monitoring workload
(more required tests, more confirmation samples, more paperwork), the observed reporting
decline could reflect burden/capacity constraints rather than (or in addition to) deliberate
avoidance — and if regulators' oversight capacity is itself strained by rising violations,
that's a confound for any analysis that treats enforcement responses as fixed.

---

## Summary

**Strand 1 — burden-driven (mechanical) reduction in reporting.** A growing public/labor
and public economics literature shows that compliance/reporting *costs* — not just the
penalty for non-compliance — are themselves a first-order determinant of whether agents
report at all, and this operates even absent any incentive to conceal bad news. Benzarti
(2020) uses a revealed-preference design (taxpayers forgoing itemization savings) to show
tax-filing compliance costs are large, rise with income, and have grown over time — people
leave money on the table simply because complying is costly, not because they are hiding
anything. Harju, Matikka & Rauhanen (2019) show bunching below Finland's VAT registration
threshold is driven by the *compliance cost* of VAT reporting (frequent filing, administrative
burden) rather than the tax rate itself, and that bunching fell sharply after a 2010 reform
that reduced filing burden — direct evidence that reporting-burden reductions mechanically
increase reporting/registration. Breuer, Leuz & Vanhaverbeke (2025) show mandatory financial
disclosure *reduces the number of firms that report innovation activity at all* and lowers
average reported R&D spending — again a burden effect on the extensive margin of reporting,
not a concealment story, since the regulator is imposing the reporting requirement, not
detecting evasion. Cross-disciplinary survey-methodology work (Bogen 1996; Yan & Williams
2022) documents the general mechanism this paper needs: longer/more burdensome reporting
instruments causally raise item non-response, break-off, and future non-participation —
i.e., burden degrades reporting *quality and completion* through respondent fatigue/cost,
independent of any incentive to conceal.

**Strand 2 — does regulator effort hold up when the job gets harder?** The evidence here is
mixed and identifies a key contrast. Two papers show regulators sustain or *increase*
effort when their task gets more demanding, provided they retain discretion or receive
better information: Duflo, Greenstone, Pande & Ryan (2018) show Gujarat's environmental
regulator, given discretion, targets inspections at the worst polluters and gets 3x the
abatement of an equivalent number of randomly-assigned (undiscretioned) inspections — more
information lets the regulator work *harder and smarter*, not less. Axbard & Deng (2024)
show real-time pollution monitors *increase* local Chinese enforcement effort and improve
targeting, precisely because officials face performance incentives tied to the new data.
But two other papers show enforcement effort erodes when the burden and no
countervailing accountability pressure are present: Jung & Makowsky (2013/14) show
*state*-run OSHA enforcement (as opposed to federally-run) is significantly more lenient
when local economic conditions worsen — a 1 percentage-point rise in local unemployment is
associated with a 1.6 percentage-point drop in the probability an inspection finds a
violation — while federally-run enforcement shows minimal sensitivity, suggesting slack
enters exactly where local political/administrative capacity is most exposed to strain.
Johnson, Levine & Toffel (2023) show OSHA's actual (human-targeted) inspection allocation is
far from optimal — a machine-learning targeting rule could have averted up to ~2x as many
injuries with the same inspection budget — consistent with a resource-constrained regulator
falling well short of its enforcement potential even without an explicit "shock." Together,
these four papers suggest the deciding factor is not task difficulty per se but whether the
regulator has *discretion + information + accountability*: given those, harder tasks are met
with more effort (Duflo et al., Axbard & Deng); absent them, burden turns into enforcement
slack (Jung & Makowsky, Johnson et al.).

---

## Key Papers

### STRAND 1: REPORTING BURDEN → MECHANICAL (NON-STRATEGIC) REDUCTION IN REPORTING

#### Benzarti (2020) — "How Taxing Is Tax Filing? Using Revealed Preferences to Estimate Compliance Costs"
- **Contribution:** First revealed-preference estimate of tax-filing compliance costs, using
  the fact that some taxpayers forgo itemized-deduction tax savings rather than pay the
  compliance cost of itemizing.
- **Method:** Bunching/discrete-choice revealed preference on IRS taxpayer-level data; the
  forgone tax savings at the margin reveal the perceived filing cost.
- **Finding:** Filing compliance costs are large, rise with income (consistent with an
  opportunity-cost-of-time story), and have grown over time — aggregate compliance costs
  rose from ~$150B (1984) to ~$200B (2006, both 2016 USD), reaching roughly 1.2% of GDP in
  recent years.
- **Relevance:** The cleanest "burden alone reduces reporting/claims-taking" result in
  economics — no strategic-concealment story is needed; agents simply forgo a
  reporting-contingent benefit because the reporting itself is costly. Directly supports
  treating rising CWS monitoring burden as a channel independent of the strategic-avoidance
  channel already in this paper's literature review.
- **Citation:** *American Economic Journal: Economic Policy* 12(4): 38–57, 2020. (NBER WP
  23903, 2017)
- **BibTeX key:** `benzarti2020taxing`

#### Harju, Matikka & Rauhanen (2019) — "Compliance Costs vs. Tax Incentives: Why Do Entrepreneurs Respond to Size-Based Regulations?"
- **Contribution:** Isolates *compliance cost* (as distinct from the tax-rate incentive) as
  the driver of firms bunching below a size-based regulatory threshold.
- **Method:** Universe of Finnish firm tax-register data around the VAT registration
  threshold; bunching estimation; exploits a 2010 reform that reduced VAT filing/compliance
  burden without changing the tax-rate incentive.
- **Finding:** Bunching below the threshold is driven by the compliance costs of VAT
  reporting (frequent filing, administrative burden — compliance cost ≈17% of value-added at
  the threshold), not by the VAT rate itself; when the 2010 reform reduced compliance costs,
  excess bunching mass fell sharply and voluntary registration rose.
- **Relevance:** A rare case where a *reduction* in reporting burden is shown to mechanically
  *increase* reporting/registration, holding the underlying incentive structure fixed — the
  direct empirical analogue to this paper's implied counterfactual (if monitoring burden
  falls, self-reporting should mechanically rise, independent of any change in the
  incentive to conceal).
- **Citation:** *Journal of Public Economics* 173: 139–164, 2019. (Related earlier working
  paper: VATT/CESifo WP, "The Effects of Size-Based Regulation on Small Firms: Evidence from
  VAT Threshold")
- **BibTeX key:** `harju2019compliance`

#### Breuer, Leuz & Vanhaverbeke (2025) — "Reporting Regulation and Corporate Innovation"
- **Contribution:** Shows that *mandating* disclosure/reporting itself changes the extensive
  margin of what gets reported — fewer firms report innovation activity at all once
  disclosure becomes mandatory.
- **Method:** Firm-level panel around thresholds/events that trigger mandatory financial
  reporting; compares reported-innovation outcomes for firms just above vs. below reporting
  triggers.
- **Finding:** Mandatory financial reporting requirements reduce the number of firms
  reporting (i.e., engaging in and disclosing) innovation activity and reduce the average
  reporting firm's innovation spending, but do not reduce industry-wide aggregate innovation
  spending — some activity moves to non-reporting firms rather than disappearing.
- **Relevance:** Direct evidence that imposing a reporting *requirement* (the regulator's
  side of the burden, analogous to more frequent/costly required water tests) mechanically
  shrinks the reporting margin — an extensive-margin "opt out of reporting" effect distinct
  from strategic concealment of a specific bad outcome.
- **Citation:** *Journal of Accounting and Economics* 80(1), 2025. (NBER WP 26291)
- **BibTeX key:** `breuer2025reporting`

#### Bogen (1996) — "The Effect of Questionnaire Length on Response Rates: A Review of the Literature"
- **Contribution:** Synthesizes survey-methodology evidence that respondent burden
  (questionnaire length, complexity, frequency) causally depresses response rates and data
  quality.
- **Method:** Literature review/meta-synthesis of experimental and observational survey
  studies.
- **Finding:** Longer, more burdensome survey instruments increase item non-response,
  break-off before completion, and reduce willingness to respond to future survey requests;
  effects operate through respondent fatigue/cost, not any incentive to conceal information.
- **Relevance:** Establishes the general behavioral mechanism (burden → non-response,
  independent of concealment incentives) that this paper's CWS setting instantiates in an
  administrative/regulatory context rather than a survey context.
- **Citation:** *Proceedings of the Survey Research Methods Section, American Statistical
  Association*, 1996.
- **BibTeX key:** `bogen1996effect`

#### Yan & Williams (2022) — "Response Burden: A Conceptual Framework"
- **Contribution:** Formalizes response burden as a multidimensional cost (time, cognitive
  effort, sensitivity of the ask) and reviews its causal effects on nonresponse and
  measurement error.
- **Method:** Conceptual/methodological review of the survey-burden literature.
- **Finding:** Burden operates on multiple margins — unit nonresponse, item nonresponse,
  break-off, and measurement error/satisficing — with effects distinct from and additive to
  any strategic non-disclosure motive.
- **Relevance:** Gives this paper vocabulary and a citable methodological framework for
  separating the "burden" channel from the "concealment" channel when interpreting a decline
  in CWS reporting.
- **Citation:** *Journal of Official Statistics* 38(1), 2022.
- **BibTeX key:** `yan2022response`

---

### STRAND 2: REGULATOR EFFORT WHEN THE TASK GETS MORE ONEROUS

#### Duflo, Greenstone, Pande & Ryan (2018) — "The Value of Regulatory Discretion: Estimates from Environmental Inspections in India"
- **Contribution:** Field experiment showing a resource-constrained regulator, given
  discretion over where to direct additional inspection effort, targets it far more
  effectively than random assignment.
- **Method:** RCT with Gujarat's environmental regulator; treatment plants were randomly
  assigned to receive inspections up to the legally mandated minimum frequency (more than
  2x as likely to be inspected as control plants), while separately observing the
  regulator's own discretionary inspection choices.
- **Finding:** The regulator's discretionary inspections are targeted at the most-polluting
  plants and induce roughly **3x more abatement** than an inspection added at random —
  discretion, not just inspection quantity, is what makes enforcement effort effective.
- **Relevance:** Shows regulator effort does *not* collapse when inspection targets are
  numerous/costly to reach, provided the regulator retains discretion — a contrast case
  against the "onerous task → weaker enforcement" hypothesis, conditional on institutional
  design.
- **Citation:** *Econometrica* 86(6): 2123–2160, 2018. (NBER WP 20590)
- **BibTeX key:** `duflo2018value`

#### Duflo, Greenstone, Pande & Ryan (2013) — "Truth-telling by Third-Party Auditors and the Response of Polluting Firms: Experimental Evidence from India"
- **Contribution:** RCT reforming the market structure for third-party pollution auditors
  (who report plant emissions to the regulator) to remove the conflict of interest created
  by plants paying their own auditors.
- **Method:** Field experiment in Gujarat randomizing auditor assignment/pay structure away
  from direct plant control.
- **Finding:** Under the status quo, auditors systematically under-reported emissions,
  rounding down to just below the regulatory standard; the reform caused auditors to report
  substantially more truthfully and sharply reduced the share of plants falsely reported as
  compliant.
- **Relevance:** Companion result to Duflo et al. (2018) — shows that when the *reporting
  intermediary's* incentives are fixed (not the regulated firm's), truthful reporting effort
  rises. Relevant as background on how third-party/self-reporting integrity interacts with
  regulator design, distinct from the CWS's own self-testing burden.
- **Citation:** *Quarterly Journal of Economics* 128(4): 1499–1545, 2013. (NBER WP 19259)
- **BibTeX key:** `duflo2013truthtelling`

#### Axbard & Deng (2024) — "Informed Enforcement: Lessons from Pollution Monitoring in China"
- **Contribution:** Shows that giving a regulator better real-time information *increases*
  enforcement effort and improves targeting, rather than overwhelming capacity.
- **Method:** Staggered rollout of real-time air-pollution monitors across 177 Chinese
  cities (2015); difference-in-differences on local enforcement actions and pollution
  outcomes.
- **Finding:** Monitor rollout (i) increases enforcement actions against local firms, (ii)
  improves the targeting of enforcement toward higher-emitting firms, and (iii) reduces
  aggregate pollution; effects are driven by officials facing performance incentives and are
  stronger where data manipulation is harder.
- **Relevance:** A second contrast case: more information (a heavier monitoring/reporting
  load, in a sense) raises rather than lowers regulator effort when officials face
  performance accountability for the data. Useful for framing what has to be *absent* (local
  accountability) for burden to translate into regulator slack, per Jung & Makowsky below.
- **Citation:** *American Economic Journal: Applied Economics* 16(1): 213–252, 2024.
- **BibTeX key:** `axbard2024informed`

#### Jung & Makowsky (2013/2014) — "The Determinants of Federal and State Enforcement of Workplace Safety Regulations: OSHA Inspections 1990–2010"
- **Contribution:** Shows enforcement leniency is systematically tied to local economic
  strain, and that this sensitivity is concentrated in state-run (not federally-run)
  enforcement.
- **Method:** ~1.6 million OSHA inspection records, 1990–2010; compares outcomes across
  state-plan vs. federal OSHA jurisdictions as a function of local unemployment.
- **Finding:** A 1 percentage-point rise in local unemployment is associated with a **1.6
  percentage-point decrease** in the probability that a state-run inspection finds a
  violation; federally-run enforcement shows minimal sensitivity to local unemployment.
  State inspectors report concern about "contributing to unemployment" during downturns.
- **Relevance:** Direct evidence that regulatory effort erodes under strain when the
  regulator is closer to (and more politically exposed to) the local costs of enforcement —
  the mirror image of this paper's question: whether a *state* SDWA primacy regulator's
  oversight/follow-up effort weakens when mining-driven contamination raises its own
  enforcement caseload.
- **Citation:** *Journal of Regulatory Economics* 45(1): 1–33, 2014 (online 2013).
- **BibTeX key:** `jung2014determinants`

#### Johnson, Levine & Toffel (2023) — "Improving Regulatory Effectiveness through Better Targeting: Evidence from OSHA"
- **Contribution:** Quantifies how far a real-world, capacity-constrained regulator falls
  short of its enforcement potential, using machine-learning counterfactual targeting.
- **Method:** ML model trained on historical OSHA inspection/injury data; compares realized
  injury reductions from actual inspection targeting against a counterfactual optimal-
  targeting policy holding the inspection budget fixed.
- **Finding:** Actual OSHA inspections reduce serious injuries by about 9% (≈2.4 fewer
  serious injuries per inspection over 5 years); with the *same* inspection budget,
  ML-based targeting could have averted up to roughly 2x as many injuries, worth up to
  ~$850 million in additional social value over the decade studied.
- **Relevance:** Even absent an explicit "shock" to task difficulty, this shows a
  resource-constrained regulator's realized enforcement effort/effectiveness is well below
  potential — consistent with capacity, not just willingness, binding regulatory follow-up.
  Useful complement to Jung & Makowsky for benchmarking "how much enforcement slack is normal"
  versus how much this paper's shock adds.
- **Companion paper:** Levine, Toffel & Johnson (2012), "Randomized Government Safety
  Inspections Reduce Worker Injuries with No Detectable Job Loss," *Science* 336(6083),
  2012 — establishes the causal ~9.4% injury-reduction effect of inspections via
  randomization, the empirical foundation the 2023 targeting paper builds on.
- **Citation:** *American Economic Journal: Applied Economics* 15(4): 30–67, 2023.
- **BibTeX key:** `johnson2023improving`

---

## Gaps and Opportunities

1. **No paper isolates the burden channel from the concealment channel in the same setting.**
   Strand 1 papers (Benzarti, Harju et al., Breuer et al.) show burden alone reduces
   reporting in tax/disclosure contexts with no adverse-detection stakes; the strategic
   literature already in this paper's review (Zou, Mu-Rubin-Zou, Andarge et al.) shows
   concealment when detection is costly to the *reporter*. No existing paper decomposes a
   *single* reporting decline into burden vs. concealment shares. If this paper's data allow
   it (e.g., comparing MR-violation responses in HUCs/years where monitoring requirements
   escalate mechanically — more required tests post-detection — versus where they do not),
   that decomposition would be a genuine contribution.

2. **No US drinking-water paper studies regulator (state primacy agency) effort as a function
   of local enforcement caseload/burden.** Jung & Makowsky is the closest analogue but is
   OSHA, not SDWA. Given the PA-dominance finding already in this project's memory
   ([[project_pa_dominance]]), a natural extension is testing whether state primacy-agency
   *enforcement* effort (not just CWS self-reporting) responds to rising violation caseload
   the way Jung & Makowsky's state OSHA offices do — i.e., whether the "PA doesn't offset"
   result reflects PA capacity strain rather than a null story.

3. **The discretion/accountability moderator (Duflo et al., Axbard & Deng vs. Jung & Makowsky)
   is a testable heterogeneity margin.** If SDWA primacy varies in how much discretion/
   performance accountability state regulators face, this paper could test whether MR-
   violation follow-up (formal enforcement, days-to-RTC) holds up better in states with more
   centralized/accountable oversight — directly extending the discretion-matters vs.
   discretion-absent contrast identified above.

---

## BibTeX Entries

```bibtex
@article{benzarti2020taxing,
  author  = {Benzarti, Youssef},
  title   = {How Taxing Is Tax Filing? Using Revealed Preferences to Estimate Compliance Costs},
  journal = {American Economic Journal: Economic Policy},
  volume  = {12},
  number  = {4},
  pages   = {38--57},
  year    = {2020},
  publisher = {American Economic Association}
}

@article{harju2019compliance,
  author  = {Harju, Jarkko and Matikka, Tuomas and Rauhanen, Timo},
  title   = {Compliance Costs vs. Tax Incentives: Why Do Entrepreneurs Respond to Size-Based Regulations?},
  journal = {Journal of Public Economics},
  volume  = {173},
  pages   = {139--164},
  year    = {2019},
  publisher = {Elsevier}
}

@article{breuer2025reporting,
  author  = {Breuer, Matthias and Leuz, Christian and Vanhaverbeke, Steven},
  title   = {Reporting Regulation and Corporate Innovation},
  journal = {Journal of Accounting and Economics},
  volume  = {80},
  number  = {1},
  year    = {2025},
  publisher = {Elsevier}
}

@techreport{bogen1996effect,
  author = {Bogen, Karen},
  title  = {The Effect of Questionnaire Length on Response Rates: A Review of the Literature},
  institution = {Proceedings of the Survey Research Methods Section, American Statistical Association},
  year   = {1996}
}

@article{yan2022response,
  author  = {Yan, Ting and Williams, Douglas},
  title   = {Response Burden: A Conceptual Framework},
  journal = {Journal of Official Statistics},
  volume  = {38},
  number  = {1},
  year    = {2022}
}

@article{duflo2018value,
  author  = {Duflo, Esther and Greenstone, Michael and Pande, Rohini and Ryan, Nicholas},
  title   = {The Value of Regulatory Discretion: Estimates from Environmental Inspections in India},
  journal = {Econometrica},
  volume  = {86},
  number  = {6},
  pages   = {2123--2160},
  year    = {2018}
}

@article{duflo2013truthtelling,
  author  = {Duflo, Esther and Greenstone, Michael and Pande, Rohini and Ryan, Nicholas},
  title   = {Truth-telling by Third-Party Auditors and the Response of Polluting Firms: Experimental Evidence from India},
  journal = {Quarterly Journal of Economics},
  volume  = {128},
  number  = {4},
  pages   = {1499--1545},
  year    = {2013}
}

@article{axbard2024informed,
  author  = {Axbard, Sebastian and Deng, Zichen},
  title   = {Informed Enforcement: Lessons from Pollution Monitoring in China},
  journal = {American Economic Journal: Applied Economics},
  volume  = {16},
  number  = {1},
  pages   = {213--252},
  year    = {2024}
}

@article{jung2014determinants,
  author  = {Jung, Juergen and Makowsky, Michael D.},
  title   = {The Determinants of Federal and State Enforcement of Workplace Safety Regulations: {OSHA} Inspections 1990--2010},
  journal = {Journal of Regulatory Economics},
  volume  = {45},
  number  = {1},
  pages   = {1--33},
  year    = {2014}
}

@article{johnson2023improving,
  author  = {Johnson, Matthew S. and Levine, David I. and Toffel, Michael W.},
  title   = {Improving Regulatory Effectiveness through Better Targeting: Evidence from {OSHA}},
  journal = {American Economic Journal: Applied Economics},
  volume  = {15},
  number  = {4},
  pages   = {30--67},
  year    = {2023}
}

@article{levine2012randomized,
  author  = {Levine, David I. and Toffel, Michael W. and Johnson, Matthew S.},
  title   = {Randomized Government Safety Inspections Reduce Worker Injuries with No Detectable Job Loss},
  journal = {Science},
  volume  = {336},
  number  = {6083},
  pages   = {907--911},
  year    = {2012}
}
```

---

<details>
<summary>✅ Post-Flight Verification (CoVe) — PASS (9/9 core claims VERIFIED, 1 sub-citation corrected)</summary>

Independent `claim-verifier` pass (fresh context, claims-table only, no draft prose).

- **A1–A3, B1–B5**: all VERIFIED — author names, journal, volume/issue/pages, and stated
  findings/magnitudes confirmed against primary or near-primary sources (publisher pages,
  NBER Digest, PMC full text, AEA/Econometric Society abstracts).
- **A4**: general survey-burden characterization VERIFIED as accurate and non-fabricated.
  One originally-considered citation ("Jeong et al. 2023, *International Journal of Social
  Research*") could **not** be verified and was **dropped**; replaced with the two
  confirmed sources actually cited above (Bogen 1996; Yan & Williams 2022).
- **B4 (Jung & Makowsky)**: the "1.6 percentage point" magnitude was confirmed directly in
  PMC full text, but via an HTML-rendered fetch with minor OCR artifacts elsewhere in the
  document — recommend a spot-check against the typeset Table 2 before quoting the number
  verbatim in the manuscript.
- No citations were fabricated or misattributed. Nothing else required removal.

</details>
