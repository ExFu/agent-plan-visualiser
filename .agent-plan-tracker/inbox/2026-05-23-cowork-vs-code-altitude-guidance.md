---
id: 2026-05-23.cowork-vs-code-altitude-guidance
entity_type: inbox-item
created_at: 2026-05-23
status: open
candidate_fate: philosophy
---

# Cowork vs Code — altitude-specific guidance

Cowork is positioned as the project-management altitude (T1/T2 planning); Claude Code is the execution altitude (T3 implementation). Worth capturing concrete guidance for users on *when to use which surface*.

## Initial intuition

**Use Claude Cowork when:**

- Authoring or editing T1 / T2 plans.
- Brainstorming methodology, ontology, architecture.
- Reviewing project state at a high level (current status, what's blocked, what's outstanding).
- Discussing pivots, decisions, tradeoffs.
- Reading the HTML view to understand project shape.
- Triaging the inbox.

**Use Claude Code when:**

- Implementing T3 plans (writing code, modifying files).
- Running scripts (cache build, projection emit, etc.).
- Debugging, refactoring, testing.
- Anything that requires direct filesystem manipulation or Bash invocation at speed.

## Why this matters

Both surfaces can do both kinds of work — Cowork can edit files, Code can plan. But each is *optimised* for its altitude, and using the wrong one creates friction:

- T1 planning in Code feels heavy — too much focus on file ops, not enough on conceptual thinking.
- T3 execution in Cowork feels slow — too much abstraction, not enough direct control.

## Possible plugin UX

The plugin's slash commands could surface altitude-detection hints:

- "You're editing T1-top-level.md — Cowork might be a better surface for this kind of work."
- "You're running scripts — Code is the right altitude."

Or it could just document the convention and let users self-route.

## Status

Speculative — depends on Cowork's actual UX evolving in known directions. Probably becomes a philosophy doc (`philosophies/cowork-vs-code-altitudes.md`) or a skill (`skills/altitude-routing/SKILL.md`) once the convention has been validated in practice.

**Resurrect when:** Cowork is used in earnest on this project for T1/T2 work, and we have enough data to confirm or contradict the intuition above.
