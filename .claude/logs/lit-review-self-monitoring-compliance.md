# Literature Review: Determinants of Environmental Self-Monitoring Compliance When Contamination Rises
Date: 2026-07-16

**Framing anchor.** This paper studies how compliance with *contamination self-reporting
requirements* responds to *rising pollution* when (i) testing/reporting is costly and borne
by the regulated entity, and (ii) a report that reveals abatement deficiencies triggers
enhanced monitoring and possible enforcement. The setting is US drinking-water utilities
(CWSs), which must test their water and report results to state primacy regulators. Because
adverse results move a utility onto a more burdensome monitoring schedule and expose it to
enforcement, the utility's privately optimal testing frequency is *below* the regulator's —
a principal–agent problem. Identification uses exogenous variation in upstream US coal
mining as a pollution shock. The headline result: an additional upstream coal mine raises
**monitoring-and-reporting (MR) violations** — i.e., utilities *reduce* testing precisely
when contamination (and thus the risk of an adverse test) rises, to avoid detection and the
enhanced-monitoring schedule.

This review covers the literature the *new framing* requires, distinct from the earlier
coal→water-quality / ARP-instrument review. The relevant strands are: (1) the theory of
self-reporting under enforcement; (2) empirical strategic self-monitoring and
"avoiding-the-measurement"; (3) dynamic enforcement and escalation of scrutiny (the mechanism
that makes an adverse test costly); (4) strategic behavior in *drinking-water* monitoring
specifically; and (5) monitoring/enforcement effects on compliance.

---

## Summary

The economics of enforcement has long recognized that when the regulated party controls the
measurement, the *act of measuring* becomes a choice variable, and firms will manage what
gets recorded. Kaplow & Shavell (1994) formalize when a regulator should induce
self-reporting and how penalties should be structured; the core tension is that self-reports
are only truthfully elicited if the expected sanction from reporting is not worse than the
expected sanction from staying silent and risking detection. A large empirical literature
now documents the corollary: where measurement is intermittent, self-scheduled, or
self-conducted, entities suppress or omit measurement exactly when true pollution is high.
Zou (2021) shows air quality is systematically worse on unmonitored days under the
once-every-six-days Clean Air Act schedule; Mu, Rubin & Zou (2026) show local governments
strategically shut down monitors on high-pollution days. In drinking water, Bennear, Jessoe
& Olmstead (2009) show utilities "sample out" of Total Coliform Rule violations by taking
extra samples, and Andarge, Ghanem, Keiser & Lade (2025) document threshold manipulation
(suspicious rounding just below the lead action level) that collapsed after Flint raised
scrutiny.

What makes an adverse self-report costly is dynamic enforcement: Blundell, Gowrisankaran &
Langer (2020) show the EPA escalates scrutiny on detected violators (the "high-priority
violator" designation), so a single revealed exceedance raises the present value of future
inspection and penalty burden — precisely the "enhanced monitoring schedule" mechanism in
this paper. The SDWA's own tiered monitoring (a detection triggers confirmation samples,
quarterly monitoring, and public notification) is the drinking-water analog. This paper's
contribution is to close the loop empirically: it uses an *exogenous pollution shock*
(upstream mining) rather than firm-chosen pollution, and shows the compliance margin that
moves is *reporting itself* (MR violations), consistent with utilities trading a cheap
monitoring infraction for avoidance of the costlier detected-contamination path. To my
knowledge no prior paper identifies the self-monitoring-compliance response to an exogenous
*rise in ambient contamination* — most strategic-monitoring papers exploit the monitoring
schedule or a threshold, holding the pollution process fixed or endogenous to the firm.

---

## Key Papers

### 1. THEORY OF SELF-REPORTING AND ENFORCEMENT

#### Kaplow & Shavell (1994) — "Optimal Law Enforcement with Self-Reporting of Behavior"
- **Contribution:** Foundational theory of when a regulator should induce self-reporting and
  how to structure sanctions so violators report rather than conceal.
- **Method:** Optimal-enforcement model; injurers choose whether to self-report given the
  probability of detection and the sanction schedule.
- **Finding:** Self-reporting is efficient because it saves enforcement resources and reduces
  risk, but is elicited only if the sanction conditional on reporting is set *below* the
  expected sanction from non-reporting (detection × penalty). If reporting carries a higher
  expected cost than concealment, truthful self-reports collapse.
- **Relevance:** The theoretical core of this paper's mechanism. When rising contamination
  makes an adverse *reported* test more likely to trigger enhanced monitoring + enforcement,
  the expected cost of reporting rises relative to the MR penalty for simply not testing —
  the exact wedge Kaplow-Shavell identify, now operating on the *testing* margin. Motivates
  the policy conclusion (raise MR penalties to restore the reporting incentive).
- **Citation:** *Journal of Political Economy* 102(3): 583–606, 1994. (NBER WP 3822)
- **BibTeX key:** `kaplow1994optimal`

#### Mookherjee & Png (1994) — "Marginal Deterrence in Enforcement of Law" *(already cited)*
- **Relevance:** Marginal-deterrence logic explains why the *relative* penalties on MR vs.
  MCL violations matter: if the MR penalty is too low relative to the detected-contamination
  penalty, utilities substitute into the lesser offense (not testing). Directly supports the
  "raise MR penalties" conclusion.
- **Citation:** *Journal of Political Economy* 102(5): 1039–1066, 1994.
- **BibTeX key:** `mookherjee1994marginal`

---

### 2. EMPIRICAL STRATEGIC SELF-MONITORING ("AVOIDING THE MEASUREMENT")

#### Zou (2021) — "Unwatched Pollution: The Effect of Intermittent Monitoring on Air Quality"
- **Contribution:** First clean causal evidence that regulated areas suppress pollution on
  monitored days and let it rise on unmonitored days, exploiting a mechanical monitoring
  schedule.
- **Method:** The Clean Air Act's once-every-six-days PM monitoring rotation; satellite
  aerosol data provide ground truth on unmonitored days; event-study around the monitoring
  cycle.
- **Finding:** Air quality is significantly worse on unmonitored days; the gap is largest in
  high-pollution periods when a city's non-attainment risk is high — i.e., strategic
  suppression scales with the stakes of being caught.
- **Relevance:** Closest methodological cousin: strategic behavior on the *monitoring* margin
  that intensifies exactly when contamination/violation risk is high. This paper's analog is
  utilities cutting testing when upstream mining raises contamination — the same
  "manage the measurement when stakes are high" logic, on a different margin (frequency of
  self-testing rather than day-of-monitoring pollution).
- **Citation:** *American Economic Review* 111(7): 2101–2126, 2021.
- **BibTeX key:** `zou2021unwatched`

#### Mu, Rubin & Zou (2026) — "What's Missing in Environmental Self-Monitoring: Evidence from Strategic Shutdowns of Pollution Monitors" *(already cited as `mu2024s`)*
- **Contribution:** Develops a large-scale inference method to detect deliberate monitor
  shutdowns timed to high-pollution days.
- **Method:** Tests whether monitor "downtime" coincides with counties' own air-quality
  alerts; validated on the Jersey City "Bridgegate" monitor, then scaled to 1,300+ US
  monitors.
- **Finding:** The Jersey City monitor's sampling rate fell 33% on pollution-alert days; 14
  metro areas show clusters of monitors with similar strategic shutdown patterns.
- **Relevance:** The purest statement of the paper's mechanism — regulated entities *stop
  measuring* when they expect a bad reading. This paper provides the drinking-water,
  exogenous-shock counterpart: MR violations (failure to test/report) rise with upstream
  mining.
- **Citation:** *Review of Economics and Statistics* 108(3): 597, 2026. (NBER WP 28735)
- **BibTeX key:** `mu2024s`

#### Andarge, Ghanem, Keiser & Lade (2025) — "Quantifying Threshold Manipulation in the Presence of Rounding: The Case of Lead Monitoring in US Drinking Water" *(already cited as `Andarge2025lead`)*
- **Contribution:** Method to detect and quantify manipulation of reported readings around a
  regulatory threshold when rounding masks bunching; applied to lead in drinking water.
- **Method:** Bunching/rounding tests on the distribution of reported lead concentrations
  relative to the 15 ppb action level; before/after Flint.
- **Finding:** Systematic manipulation — utilities reported values suspiciously just below
  the action level; this rounding-based manipulation "virtually vanished" after the Flint
  crisis sharply raised federal scrutiny of lead reporting.
- **Relevance:** Direct drinking-water evidence that CWSs manage *what gets reported* to avoid
  crossing a threshold that triggers costly consequences. Complements this paper: Andarge et
  al. show manipulation of the *reported value*; this paper shows manipulation of *whether a
  test is conducted/reported at all* (the MR margin), and ties it to an exogenous rise in
  contamination.
- **Citation:** *American Economic Review: Insights* 7(3): 285–305, 2025.
- **BibTeX key:** `Andarge2025lead`

---

### 3. DYNAMIC ENFORCEMENT AND ESCALATION OF SCRUTINY (why an adverse test is costly)

#### Blundell, Gowrisankaran & Langer (2020) — "Escalation of Scrutiny: The Gains from Dynamic Enforcement of Environmental Regulations"
- **Contribution:** Shows the EPA enforces the Clean Air Act *dynamically* — detected
  violators are designated "high-priority violators" (HPV) and face escalated inspection and
  penalty exposure — and quantifies the deterrence value of this escalation.
- **Method:** Structural dynamic model of plant abatement investment and regulator
  enforcement, estimated on EPA air-enforcement data.
- **Finding:** Removing dynamic enforcement would raise pollution damages by 164% (holding
  fines fixed) or require a 519% increase in fines to hold damages constant — the escalation
  mechanism does most of the deterrence work.
- **Relevance:** Provides the economic foundation for *why a single revealed exceedance is
  costly*: it moves the utility onto a worse enforcement/monitoring trajectory. This is
  exactly the "enhanced monitoring schedule" this paper posits utilities are avoiding by not
  testing. The SDWA's confirmation-sampling / increased-monitoring / public-notice cascade is
  the drinking-water version of HPV escalation.
- **Citation:** *American Economic Review* 110(8): 2558–2585, 2020. (NBER WP 24810)
- **BibTeX key:** `blundell2020escalation`

#### Kang & Silveira (2021) — "Understanding Disparities in Punishment: Regulator Preferences and Expertise" *(already cited)*
- **Relevance:** Structural model of the enforcement machine facing regulated entities;
  supplies the discrete-choice/enforcement-state framing this paper draws on to model the
  utility's testing decision against an escalating regulator. Establishes that enforcement
  intensity is a choice with recoverable costs — supporting the principal-agent formalization.
- **Citation:** *Journal of Political Economy* 129(10): 2947–2992, 2021.
- **BibTeX key:** `kang2021understanding`

---

### 4. STRATEGIC BEHAVIOR IN DRINKING-WATER MONITORING & DISCLOSURE

#### Bennear, Jessoe & Olmstead (2009) — "Sampling Out: Regulatory Avoidance and the Total Coliform Rule"
- **Contribution:** First evidence that drinking-water systems avoid violations by
  *manipulating their own sampling* under the Total Coliform Rule.
- **Method:** Monthly data on 500+ Massachusetts water systems, 1993–2003; compares actual
  sampling to the legally required schedule and tests for strategic oversampling.
- **Finding:** Systems take *extra* samples to dilute the share of positive results and thereby
  avoid triggering a monthly TCR violation; a significant number of violations would have been
  recorded under strict compliance. The rule's structure creates the avoidance incentive.
- **Relevance:** The closest drinking-water precedent for strategic self-monitoring. Note the
  *direction differs and that is the paper's novelty*: under the TCR, the profit-maximizing
  move is to over-sample (dilution); in this paper's setting, rising upstream contamination
  makes *any* test more likely to reveal an exceedance and trigger enhanced monitoring, so the
  optimal response flips to *under-testing* (MR violations). Same primitive (manage the
  measurement), opposite sign, driven by the enforcement structure.
- **Citation:** *Environmental Science & Technology* 43(14): 5176–5182, 2009.
- **BibTeX key:** `bennear2009sampling`

#### Bennear & Olmstead (2008) — "The Impacts of the 'Right to Know': Information Disclosure and the Violation of Drinking Water Standards" *(already cited)*
- **Contribution:** Shows mandatory Consumer Confidence Reports reduce violations, evidence
  that disclosure/observability changes utility compliance behavior.
- **Finding:** CCR requirements reduced total and health-based violations, concentrated among
  larger systems — observability of contamination changes utility incentives.
- **Relevance:** Establishes that CWS compliance responds to the *cost of a violation being
  seen*. Reinforces the mechanism: when the cost of a detected exceedance rises (enhanced
  monitoring, public notice), utilities adjust the compliance margin they control (testing).
- **Citation:** *Journal of Environmental Economics and Management* 56(2): 117–130, 2008.
- **BibTeX key:** `bennear2008impacts`

#### Marcus (2022) — "Testing the Water: Drinking Water Quality, Public Notification, and Child Outcomes"
- **Contribution:** Shows the consequences of a detected/reported violation operate through
  mandatory public notification, which drives averting behavior and child-health outcomes.
- **Method:** North Carolina coliform violations, 2004–2015; exploits the 24-hour public-notice
  requirement for *acute* violations vs. slower notice for others.
- **Finding:** Bottled-water purchases rise substantially (reported ~78%) in the month of an
  acute violation when 24-hour public notice is required; timely notification is a
  cost-effective driver of averting behavior. *(Direction confirmed; exact 78% magnitude
  taken from secondary summaries — verify against the full text before quoting the number.)*
- **Relevance:** Quantifies part of the *cost to the utility* of a reported exceedance —
  public notification, reputational and averting-behavior consequences — that utilities have
  an incentive to avoid by not testing. Explains why the reporting margin is where utilities
  economize.
- **Citation:** *Review of Economics and Statistics* 104(6): 1289–1303, 2022.
- **BibTeX key:** `marcus2022testing`

#### Naylor (2025) — "Strategic Reporting of Arsenic in US Drinking Water" *(local `lit/` PDF; details UNVERIFIED)*
- **Contribution (as understood):** Evidence that CWSs strategically report arsenic
  monitoring results to avoid crossing the MCL / triggering enforcement.
- **Relevance:** If confirmed, the most direct precedent for this paper — strategic
  self-reporting of a *chemical* (rather than coliform) contaminant in the SDWIS system.
- **Status:** ⚠️ Could not verify author, title, venue, or findings via web search or PDF
  extraction (poppler/pypdf unavailable in this environment). **Verify the exact citation
  and claims against the local PDF before including in the manuscript.**
- **BibTeX key:** `naylor2025arsenic` *(placeholder — confirm)*

---

### 5. MONITORING, ENFORCEMENT, AND SELF-POLICING (compliance response)

#### Helland (1998) — "The Enforcement of Pollution Control Laws: Inspections, Violations, and Self-Reporting" *(already cited)*
- **Contribution:** Early empirical study of how inspections and self-reporting interact under
  the Clean Water Act; finds firms self-report strategically in response to inspection
  probability.
- **Finding:** Inspection activity and self-reported violations are related in a way
  consistent with strategic reporting to *pre-empt* harsher treatment, not just mechanical
  detection.
- **Relevance:** Early demonstration that self-reports are a strategic choice tied to
  enforcement expectations — the behavioral primitive this paper measures in the CWS setting.
- **Citation:** *Review of Economics and Statistics* 80(1): 141–153, 1998.
- **BibTeX key:** `helland1998enforcement`

#### Shimshack & Ward (2005) — "Regulator Reputation, Enforcement, and Environmental Compliance" *(already cited)*
- **Relevance:** Shows enforcement actions have deterrence *spillovers* — a fine on one firm
  raises compliance among others. Establishes that utilities form expectations about
  enforcement, the belief that makes an escalating-scrutiny threat credible enough to deter
  testing.
- **Citation:** *JEEM* 50(3): 519–540, 2005.
- **BibTeX key:** `shimshack2005regulator`

#### Shimshack (2014) — "The Economics of Environmental Monitoring and Enforcement" (review) *(already cited)*
- **Relevance:** Canonical survey; situates this paper in the monitoring-and-enforcement
  literature and provides the framing that self-monitoring shifts detection costs onto the
  regulated entity, creating exactly the incentive problem studied here.
- **Citation:** *Annual Review of Resource Economics* 6: 339–360, 2014.
- **BibTeX key:** `shimshack2014economics`

#### Stafford (2002) — "The Effect of Punishment on Firm Compliance with Hazardous Waste Regulations" *(already cited)*
- **Relevance:** Direct evidence that raising penalties improves compliance with environmental
  monitoring/reporting requirements — empirical support for the paper's "raise MR penalties"
  policy conclusion.
- **Citation:** *JEEM* 44(2): 290–308, 2002.
- **BibTeX key:** `stafford2002effect`

---

## Gaps and Opportunities (what this paper contributes)

1. **Self-monitoring response to an *exogenous rise in ambient contamination*.** Existing
   strategic-monitoring papers exploit the *monitoring schedule* (Zou 2021), deliberate
   *shutdowns* (Mu-Rubin-Zou 2026), a *reporting threshold* (Andarge et al. 2025), or
   firm-chosen *sampling* (Bennear et al. 2009) — in each case the pollution process is either
   fixed, cyclic, or endogenous to the firm. No prior paper identifies how self-testing
   compliance responds to a *plausibly exogenous shock to the pollution the entity must
   detect*. Upstream coal mining supplies that shock; this is the paper's central novelty.

2. **The under-testing sign.** Bennear et al. (2009) find *over*-sampling under the TCR
   (dilution avoids a violation). This paper documents the opposite margin — *under*-testing
   (MR violations) — because with a rising chemical-contamination shock, every additional test
   raises the probability of a detected exceedance and the enhanced-monitoring cascade. Showing
   that the enforcement *structure* flips the sign of the avoidance response is a contribution.

3. **Principal–agent wedge in *public* utilities, not profit-max firms.** Most self-monitoring
   evidence is on private polluters. CWSs are frequently public/municipal; the wedge here is
   between a cost-minimizing utility manager and the regulator, not profit vs. abatement. The
   determinants of self-monitoring in this ownership structure are underexplored.

4. **Direct policy lever on the MR penalty.** Kaplow-Shavell (1994) and Mookherjee-Png (1994)
   imply the reporting incentive can be restored by re-pricing the MR-vs-MCL penalty gap. This
   paper can speak to the size of that gap empirically — a concrete, testable policy margin
   that the descriptive strategic-monitoring literature does not quantify.

5. **Ambient-pollution → reporting-compliance as a mismeasurement channel.** If utilities stop
   testing when contamination rises, *recorded* health-based (MCL) violations understate true
   exposure most exactly where exposure is worst — a systematic, direction-known measurement
   bias in SDWIS with health-cost implications (links to the mismeasured-pollution literature,
   Keiser 2019).

---

## BibTeX Entries

Entries below are for papers **not already** in `writeup/mining_and_water_quality/citation.bib`.
(Already-cited keys reused above: `mu2024s`, `Andarge2025lead`, `bennear2009sampling`,
`bennear2008impacts`, `helland1998enforcement`, `shimshack2005regulator`,
`shimshack2014economics`, `stafford2002effect`, `mookherjee1994marginal`,
`kang2021understanding`, `keiser2019missing`.)

```bibtex
@article{kaplow1994optimal,
  author  = {Kaplow, Louis and Shavell, Steven},
  title   = {Optimal Law Enforcement with Self-Reporting of Behavior},
  journal = {Journal of Political Economy},
  volume  = {102},
  number  = {3},
  pages   = {583--606},
  year    = {1994},
  publisher = {University of Chicago Press}
}

@article{zou2021unwatched,
  author  = {Zou, Eric Yongchen},
  title   = {Unwatched Pollution: The Effect of Intermittent Monitoring on Air Quality},
  journal = {American Economic Review},
  volume  = {111},
  number  = {7},
  pages   = {2101--2126},
  year    = {2021},
  publisher = {American Economic Association}
}

@article{blundell2020escalation,
  author  = {Blundell, Wesley and Gowrisankaran, Gautam and Langer, Ashley},
  title   = {Escalation of Scrutiny: The Gains from Dynamic Enforcement of Environmental Regulations},
  journal = {American Economic Review},
  volume  = {110},
  number  = {8},
  pages   = {2558--2585},
  year    = {2020},
  publisher = {American Economic Association}
}

@article{marcus2022testing,
  author  = {Marcus, Michelle},
  title   = {Testing the Water: Drinking Water Quality, Public Notification, and Child Outcomes},
  journal = {The Review of Economics and Statistics},
  volume  = {104},
  number  = {6},
  pages   = {1289--1303},
  year    = {2022},
  publisher = {MIT Press}
}

% ---- UNVERIFIED: confirm all fields against the local lit/ PDF before use ----
@unpublished{naylor2025arsenic,
  author = {Naylor, [FIRST NAME UNCONFIRMED]},
  title  = {Strategic Reporting of Arsenic in {US} Drinking Water [TITLE UNCONFIRMED]},
  note   = {Working paper; details unverified --- see lit/naylor - arsenic strategic reporting 2025.pdf},
  year   = {2025}
}
```

**Note on `mu2024s` year:** the paper appears in *REStat* vol. 108(3), a **2026** issue. The
existing bib key/year says 2024 (accepted/online-first). Consider updating to 2026 to match
the print citation, or keep 2024 with a note.

**Note on `blundell2020escalation`:** confirm this key is not already present under another
name in the master `Bibliography_base.bib` before adding.

---

<details>
<summary>✅ Post-Flight Verification (CoVe) — PASS (13 PASS, 1 PARTIAL, 0 FAIL)</summary>

Independent `claim-verifier` pass (fresh context, claims-table only, no draft prose).
All 14 cited papers confirmed real and correctly attributed by author, year, venue,
volume, issue, and pages. No FAILs → nothing removed.

- **PARTIAL — Marcus (2022):** citation fully confirmed; the specific "~78%" bottled-water
  magnitude could not be independently verified from reachable (paywalled/binary) sources.
  Direction confirmed. Softened in text and flagged; verify the number against the open PDF
  before quoting it. (michellemmarcus.com hosts the full text.)
- **Cosmetic — Mu, Rubin & Zou:** NBER WP title is "...Environmental **(Self-)**Monitoring";
  the published *REStat* title drops the parenthetical to "Environmental Self-Monitoring"
  (used here — matches the journal of record). No correction needed.
- **Cosmetic — Bennear, Jessoe & Olmstead:** published title stylizes as "Sampling out"
  (lowercase o).

Naylor (2025) is **excluded from this verification** — it is a local `lit/` working paper
that could not be rendered (poppler/pypdf unavailable) or found on the web. It remains
flagged UNVERIFIED in the text and BibTeX; confirm all fields against the PDF before use.
</details>
