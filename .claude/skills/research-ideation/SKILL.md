---
name: research-ideation
description: Generate structured research questions, testable hypotheses, and empirical strategies from a topic or dataset
argument-hint: "[topic, phenomenon, or dataset description]"
allowed-tools: ["Read", "Grep", "Glob", "Write"]
---

# Research Ideation

Generate structured research questions, testable hypotheses, and empirical strategies.

**Input:** `$ARGUMENTS` — a topic, phenomenon, or dataset description.

---

## Steps

1. **Understand the input.** Read `$ARGUMENTS`. Check `lit/` for related papers.
   Read `CLAUDE.md` for project context and existing empirical strategy.

2. **Generate 3-5 research questions** ordered descriptive → causal:
   - **Descriptive:** What are the patterns?
   - **Correlational:** What factors are associated?
   - **Causal:** What is the effect?
   - **Mechanism:** Through what channel?
   - **Policy:** What are the implications?

3. **For each question, develop:**
   - **Hypothesis:** Testable prediction with expected sign
   - **Identification strategy:** DiD, IV, RDD, synthetic control
   - **Data requirements:** What's needed and whether it exists in the project
   - **Key assumptions:** What must hold
   - **Potential pitfalls:** Common threats
   - **Related literature:** 2-3 papers

4. **Rank by feasibility and contribution.**

5. **Save to** `.claude/logs/research-ideation-[topic].md`

---

## Principles

- Think like a referee: immediately identify the identification challenge for causal questions
- Prioritize questions that can use the existing data (HUC12-matched PWSID × year panel)
- Consider the ARP instrument as a starting point for any causal question about mining intensity
