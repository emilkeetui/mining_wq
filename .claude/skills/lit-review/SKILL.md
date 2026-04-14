---
name: lit-review
description: Structured literature search and synthesis with citation extraction and gap identification
argument-hint: "[topic, paper title, or research question]"
allowed-tools: ["Read", "Grep", "Glob", "Write", "WebSearch", "WebFetch"]
---

# Literature Review

Conduct a structured literature search and synthesis on the given topic.

**Input:** `$ARGUMENTS` — a topic, paper title, research question, or phenomenon.

---

## Steps

1. **Parse the topic** from `$ARGUMENTS`.

2. **Search for related work:**
   - Check `lit/` directory for uploaded PDFs
   - Use `WebSearch` to find recent publications (if available)
   - Check for any `.bib` files in the project

3. **Organize findings** into:
   - **Theoretical contributions** — mechanisms, frameworks
   - **Empirical findings** — key results, effect sizes, data sources
   - **Methodological innovations** — identification strategies, estimators
   - **Open debates** — unresolved disagreements

4. **Identify gaps and opportunities**

5. **Extract citations** in BibTeX format

6. **Save the report** to `.claude/logs/lit-review-[topic].md`

---

## Output Format

```markdown
# Literature Review: [Topic]
Date: YYYY-MM-DD

## Summary
[2-3 paragraph overview]

## Key Papers

### [Author (Year)] — [Short Title]
- **Contribution:** [1-2 sentences]
- **Method:** [Identification strategy / data]
- **Finding:** [Result with effect size]
- **Relevance:** [Why it matters for this project]

## Gaps and Opportunities
1. [Gap 1]
2. [Gap 2]

## BibTeX Entries
[bibtex entries]
```

## Important

- **Do NOT fabricate citations.** If you cannot verify a paper's details, flag it for verification.
- Note working papers vs. published papers — working papers may change.
- Prioritize work that uses similar identification strategies (IV/DiD with environmental policy).
