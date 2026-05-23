---
id: 2026-05-23.mapping-note-agent-design
entity_type: inbox-item
created_at: 2026-05-23
status: open
candidate_fate: t3
---

# Retrospective mapping note generator agent (M5)

T2-ingest's `T3-mapping-note-generator` — an agent that surveys a target repo's planning artefacts (READMEs, `docs/`, `decisions/`, ADR folders, etc.) and proposes a draft retrospective mapping note for human review.

## Behavioural requirements

- **Cautious by default.** Surface inferences with confidence levels; never silently map ambiguous content. Default to "needs human input" for low-confidence mappings.
- **Inspects, not assumes.** Looks at actual file contents, not just paths. A folder called `decisions/` might contain ADRs, might contain meeting notes, might contain something else entirely.
- **Proposes, doesn't commit.** Output is a draft mapping note file that the human reviews + edits + signs off before backfill begins.
- **Confidence-tagged.** Each mapping has a confidence flag (high / medium / low / needs-input).

## Where it lives

Likely a subagent shipped in `agent-plan-tracker/agents/mapping-note-generator.md` — auto-discovered by Claude Code's agent loading. Per `plugin-dev:agent-development` skill conventions.

## Integration with backfill flow

The mapping-note generator runs as a pre-flight step before backfill begins:

1. User initiates backfill on a non-native project.
2. Agent runs against the repo, produces draft `.agent-plan-tracker/retrospective-mapping.md`.
3. Human reviews + edits + signs off.
4. Backfill proceeds with the signed-off note in the per-commit extractor's brief.

## Edge cases worth thinking about

- Project has *some* native methodology but not all of it (partial T1, no T2s, freeform decisions). Mapping note covers the gaps.
- Project's "planning" lives in GitHub issues / tickets rather than markdown files. Different surface, same idea — map issue labels and templates to ontology terms.
- Project has multiple historical conventions (e.g. ADRs for 6 months, then a different format). The mapping note may need versioned sections.

**Resurrect when:** M5 work begins (T2-ingest `T3-mapping-note-generator`).
