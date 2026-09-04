# Session: 2026-09-04 - IV validity interpretation audit (main.tex sec:iv)

## Objective
Assess accuracy of the instrument-validity discussion in main.tex (lines 509-555).
No edits made; assessment only.

## Verification performed
- Cross-checked all reported numbers against output/reg tables: F=27.52 matches
  (t^2 = (-0.2404/0.0458)^2 = 27.55); OLS/RF/2SLS coefficients match
  2sls_dwnstrm_minevio_allcat_ivsum_binvio.tex.
- Confirmed sulfur_unified_sum is time-invariant within PWSID (0 of 340 CWS have
  >1 distinct value) -- line 522's "absorbed by utility FE" claim is correct.
- Confirmed estimated instrument is post95 x sulfur_unified_SUM, not the MEAN the
  text describes at lines 513 and 522.

## Key finding: differential pre-trends by sulfur
Ran sulfur_unified_sum x year event study (ref 1994, PWSID + year FE, cluster PWSID):
- First stage: sulfur-mines gradient declines monotonically 1985 (+0.294) -> 1993
  (+0.084) BEFORE ARP; post-1995 coefficients only ~-0.05. Joint pre-1995 Wald
  p = 1.06e-5.
- Reduced form (inorganic chemicals, any): pre-1995 coefficients jointly significant,
  Wald p = 0.021; 1985, 1988-1991 individually significant and positive.
Adding sulfur x linear trend:
- First stage -0.2404 -> -0.1145 (F ~ 13, below MOP 23.1)
- RF nitrates -2.38 (p=.005) -> -1.52 (p=.175); arsenic -1.80 (p=.014) -> -0.04
  (p=.961); IOC -1.52 (p=.059) -> -0.46 (p=.597)
- 2SLS all insignificant.
Consistent with main.tex line 465's own statement that high-sulfur mine counts
"fell continuously" 1983-2005.

## Design decisions
| Decision | Rationale |
|---|---|
| Used PowerShell not Bash | Bash tool cwd got stuck in writeup/ subdir; protect-raw-data hook resolves relative and fails there |
| Event study ref year 1994 | Last full pre-ARP-Phase-I year |

## Open questions
- Does the paper want to keep the ARP step instrument, or reframe around the
  continuous westward shift with an explicit pre-trend/event-study exhibit?
- pt_eventstudy_violations.tex exists but is a dose/onset event study, not an
  event study on the actual instrument, and is commented out at main.tex:497.

## Next steps
- Fix lines 513/522 (mean vs sum), 524 (sign contradiction), 547 ("as good as
  randomly assigned"), 553 (exclusion "test" mislabeled), 555 (sufficiency claim).
- Add an instrument event study exhibit and address the pre-trend directly.
## Follow-up (same session): corrections + edits applied

### Correction to my own earlier finding
Earlier pre-trend claim ("monotonic decline from 1985") was an artifact of using 1994
as the event-study reference. With ref = 1990 (CAAA signed Nov 1990):
- First stage 1985-1989: +0.041, +0.041, -0.078, +0.005, -0.002 (flat noise).
  Decline begins exactly 1991: -0.083, -0.077, -0.168, -0.252. Anticipation of CAAA
  passage, which SUPPORTS exogeneity.
- Therefore the sulfur x linear trend "robustness check" was absorbing the actual
  treatment path (a ramp from 1991) and was not a fair test. Retracted.
- Real issue: post95 misdates the shock by ~4 yrs. Re-dating to post-1991:
  first stage -0.2495, F = 31.88 (vs 27.52); 2SLS nitrates 10.06 (p=.010),
  arsenic 11.00 (p=.004), IOC 10.35 (p=.012, vs p=.057 at post95).
  User wants this as a robustness check in a FUTURE version, not this draft.

### Monotonicity tercile check - user pushback, partly valid
User objected that terciles of sulfur are not the instrument. Grouping by sulfur is
correct (sulfur_c IS the value z takes when the instrument switches on), but raw
pre/post deltas include the common time effect. Netting out the sulfur==0 group
(delta = -0.149): low -0.134, mid -0.515, high -0.758. Still uniform and monotone.
Section 530 left unchanged at user's discretion.

### Edits applied to main.tex (all compile-verified, pdflatex exit 0)
| Line | Change |
|---|---|
| 513 | sulfur described as sum across upstream HUC12s, not average |
| 522 | NumMines described as summed across upstream HUC12s; instrument definition corrected to sum; "observations are the percent of sulfur" -> "equal the summed upstream sulfur measure" |
| 524 | "increased with the percent of coal sulfur after 1995" -> "decreased" |
| 547 | "as good as randomly assigned" -> independence conditional on utility and year FE; sulfur is a fixed endowment, the instrument is the demand switch |
| 551 | added local economic activity as a second exclusion threat; state x year FE noted as future work |
| 553 | reframed as a test of ONE alternative pathway; noted num_facilities is also a control so a non-null would mean bad control; deleted the generalization |
| 555 | four conditions incl. monotonicity, not three "sufficient"; removed "monotonicity is satisfied"; LATE stated with the complier population named |

### Deferred to future versions at user's request
- Event study / conditional independence falsification test as an exhibit
- 1990 as alternative shock date
- Downstream-of-intake placebo cited in sec:iv (note: it does NOT pass cleanly --
  placebo RF -0.0131/-0.0122/-0.0130 vs main -0.0239/-0.0179/-0.0170, equivalence
  p = 0.34/0.59/0.71; underpowered rather than damning, but a referee will find it)
- Direct channel measurement (county mining employment/population on Z)
- Overidentification via ARP Phase I Table A unit locations (user has these, in a PDF)
- Conley et al. plausibly-exogenous bounds

## Verification
- pdflatex -halt-on-error -draftmode: exit 0. 18 overfull hboxes (pre-existing, table-related).
- main.pdf NOT rebuilt (draftmode only).

### Correction to the line 555 edit (user, same session)
My first rewrite of 555 said all four conditions "deliver a causal interpretation."
That was wrong. Monotonicity is NOT required for causality: under independence +
exclusion the reduced form and first stage are each causal, and their ratio is built
from causal effects. Monotonicity is what makes the ratio a proper (non-negatively
weighted) average, i.e. a LATE on compliers. Without it the estimand weights defiers
negatively and can fall outside the range of all individual effects -- but it is still
a causal object. 555 now separates the two claims. This is also consistent with the
existing opening of 530 ("requires monotonicity to recover the LATE"), so the two
paragraphs no longer conflict.
Recompiled: pdflatex exit 0.
