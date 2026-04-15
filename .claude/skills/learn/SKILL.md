---
name: learn
description: |
  Extract reusable knowledge from the current session into a persistent skill.
  Use when you discover something non-obvious, create a workaround, or develop
  a multi-step workflow that future sessions would benefit from.
argument-hint: "[skill-name (kebab-case)]"
allowed-tools: ["Read", "Write", "Bash", "Glob", "Grep"]
---

# /learn — Skill Extraction Workflow

Extract non-obvious discoveries into reusable skills that persist across sessions.

## When to Use

Invoke `/learn` when you encounter:

- **Non-obvious debugging** — took significant effort, not in documentation
- **Misleading errors** — error message was wrong, found the real cause
- **Workarounds** — found a limitation with a creative solution
- **Cross-language schema issues** — parquet type mismatch between Python and R
- **Trial-and-error** — multiple attempts before success
- **Repeatable workflows** — multi-step task you'd do again

## Workflow

### Phase 1: Evaluate

Before creating a skill, answer:
1. "What did I just learn that wasn't obvious before starting?"
2. "Would future-me benefit from this being documented?"
3. "Is this specific to this project's data pipeline or general?"

Continue only if YES to at least one.

### Phase 2: Check for Duplicates

```bash
ls .claude/skills/
grep -r -i "KEYWORD" .claude/skills/ 2>/dev/null
```

If something related exists: update it (bump version). Otherwise: create new.

### Phase 3: Create Skill File

```
.claude/skills/[skill-name]/SKILL.md
```

```yaml
---
name: descriptive-kebab-case-name
description: |
  [What it does + specific trigger conditions]
version: 1.0.0
argument-hint: "[expected arguments]"
---

# Skill Name

## Problem
[What situation triggers this skill]

## Context / Trigger Conditions
[Exact error messages, symptoms, scenarios]

## Solution
[Step-by-step — include commands and code]

## Verification
[How to confirm it worked]

## Example
[Concrete example from the project]
```

### Phase 4: Quality Gates

- [ ] Trigger conditions are specific (not vague)
- [ ] Solution was verified to work
- [ ] No hardcoded paths or credentials
- [ ] Skill name is kebab-case

## Output

Report after creating:
```
Skill created: .claude/skills/[name]/SKILL.md
  Trigger: [when to use]
  Problem: [what it solves]
```
