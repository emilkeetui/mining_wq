---
name: review-paper
description: Comprehensive manuscript review covering argument structure, IV validity, econometric specification, citation completeness, and potential referee objections. Use for reviewing the dissertation chapter or related papers.
argument-hint: "[paper filename in lit/ or path to .tex/.pdf]"
allowed-tools: ["Read", "Grep", "Glob", "Write", "Task"]
---

# Manuscript Review

Produce a thorough, constructive review — the kind a top-field referee would write.

**Input:** `$ARGUMENTS` — path to a paper (.tex or .pdf), or a filename in `lit/`.

---

## Steps

1. **Locate and read the manuscript.** Check direct path, then `lit/`.

2. **Read the full paper** end-to-end. For long PDFs, read in 5-page chunks.

3. **Evaluate across 6 dimensions** (see below).

4. **Generate 3-5 "referee objections"** — tough questions a top-5 journal referee would ask.

5. **Save to** `.claude/logs/paper-review-[name].md`

---

## Review Dimensions

### 1. Argument Structure
- Research question clearly stated?
- Introduction motivates the question?
- Logical flow: question → method → results → conclusion?
- Conclusions supported by evidence? Limitations acknowledged?

### 2. Identification Strategy (most critical for this project)
- Is the ARP instrument (post95 × sulfur) credibly exogenous?
- Are the exclusion restriction and relevance condition explicitly stated?
- Threats: anticipatory responses, confounders correlated with high-sulfur coal regions,
  other 1995 policy changes?
- Robustness checks: pre-trends, placebo outcomes (non-mining violations), alternative samples?

### 3. Econometric Specification
- Correct standard errors (PWSID-clustered)?
- Appropriate FE structure (PWSID + year + state)?
- First-stage F-statistic reported? Above 10?
- Sample selection: balanced vs. unbalanced panel? Reasons for sample restrictions stated?
- Economically meaningful effect sizes (not just statistically significant)?

### 4. Literature Positioning
- Key papers cited (environmental pollution × health, drinking water quality, ARP)?
- Contribution clearly differentiated from existing work?
- Missing citations a referee would flag?

### 5. Writing Quality
- Clarity, concision, academic tone
- Consistent notation (variable names match between text and tables)
- Abstract effectively summarizes the paper
- Tables and figures self-contained (labels, notes, sources)

### 6. Presentation
- Tables: column headers correct? Sample sizes in footnotes?
- First-stage table present and F-stat prominently reported?
- Reduced-form and 2SLS shown side by side?

---

## Output Format

```markdown
# Manuscript Review: [Paper Title]
Date: YYYY-MM-DD

## Summary Assessment
**Overall:** [Strong Accept / Accept / R&R / Reject]

[2-3 paragraphs: main contribution, strengths, key concerns]

## Strengths
1. ...

## Major Concerns
### MC1: [Title]
- Dimension: [Identification / Econometrics / Argument / Literature / Writing]
- Issue: ...
- Suggestion: ...
- Location: ...

## Referee Objections
### RO1: [Question]
Why it matters: ...
How to address: ...

## Ratings
| Dimension | Score (1-5) |
|---|---|
| Argument | |
| Identification | |
| Econometrics | |
| Literature | |
| Writing | |
| Presentation | |
| **Overall** | |
```
