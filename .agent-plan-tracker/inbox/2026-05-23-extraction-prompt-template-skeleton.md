---
id: 2026-05-23.extraction-prompt-template-skeleton
entity_type: inbox-item
created_at: 2026-05-23
status: open
candidate_fate: t3
---

# M2 extraction prompt template — initial structure

When T2-extraction's `T3-extraction-prompt-template-v0` lands, the prompt will need to brief the per-commit extractor agent against the ontology and the commit context. Initial skeleton:

## Sections

1. **Role + purpose** — "You are the per-commit extraction agent for the agent-plan-tracker. You convert one commit into a list of structured events." (Why-grounded per `golden-circle-grounding.md`.)
2. **The ontology summary** — concise version of T2-ontology §3 (event types + entity types + derived states). Full schema available as attachment but inline summary for fast reference.
3. **Input contract** — exactly what the agent receives: commit diff, commit message, prior reconciled log (snapshot + delta), planning files touched by the commit, the active schema file. Per T2-extraction §3.2.
4. **Output contract** — events list in the order they should appear in events.jsonl. Each event valid against `events.schema.json`. Trailing `commit.recorded` carrying commit_meta.
5. **Examples per event type** — at least one worked example per event type. Especially important for fulcrum events (require paired decision).
6. **Ambiguity halt protocol** — when to halt instead of guessing. Per T2-extraction §3.6.
7. **Methodology grounding** — why this matters. Pointer to `tracker-as-agent-memory.md` for the deeper context.
8. **Token-cost discipline** — sub-agent recursion if diff is too large; per T2-extraction §3.5.

## Discipline

Per `empirical-prompt-architecture.md` — start static, iterate from real failures. Don't over-engineer. The v0 prompt is a single coherent document; only introduce dynamic composition after we've seen specific failures.

## Sketch-stage timing

Initial draft can be drafted once T2-ontology's JSON Schema lands (M1's `T3-events-schema-json`). The schema becomes the agent's validation contract and informs the examples.

**Resurrect when:** T3-events-schema-json is complete and the M2 extraction work begins.
