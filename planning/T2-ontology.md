---
id: T2-ontology
plan_kind: thematic
tier: 2
status: draft
---

# T2-ontology — Formal event + entity ontology

**Status**: Draft. First T3s scheduled into M1.
**Theme**: Capture the event types, entity types, derived states, and attribute schemas as both prose (in T1 §4) and machine-readable artefacts (JSON Schema in plugin tree).

---

## 1. Why this T2 exists

T1 §4 describes the ontology in prose. That's adequate for hand-rolling events but insufficient for:
- **Automated extraction** (M2) — the extractor needs machine validation, not narrative.
- **Downstream agents** — they need a precise reference, lookup-friendly.
- **Cache build validation** — to catch malformed events before they corrupt projections.
- **Versioning evolution** — schema_version on each event needs a versioned schema file to bind to.

T2-ontology bridges the gap. Formal artefacts that machines validate against, with prose as the human-facing supplement.

## 2. What lives in this theme

- **`schemas/events.schema.json`** — JSON Schema for all 23 event types. Discriminator: the `type` field.
- **`schemas/plan-frontmatter.schema.json`** — JSON Schema for plan-file YAML frontmatter. Discriminator: `plan_kind`.
- **`schemas/<other>-frontmatter.schema.json`** (later) — for hitl-question, blocker, inbox-item frontmatter once those entity types get their own files. Defer.
- **Schema-versioning conventions** — how `schema_version` on events binds to which schema file. Likely `schema_version: 0.1.0` → `schemas/0.1.0/events.schema.json`.

## 3. Approach

JSON Schema chosen per T1 §5 Q11 (resolved in this T2).

**Events schema shape.** One file with `oneOf` discriminated by `type`. Each branch validates required attributes specific to that type:
- `entity.superseded` requires `attributes.entity_ids[]` (one-to-many fork target).
- `decision` requires `attributes.text` + `attributes.event_ids[]`.
- `blocker.progressed` requires `attributes.note`.
- `relationship.*` events require `attributes.to_entity_id` (and `from_entity_id` is implied by the `entity_id` field).
- Fulcrum events validated together with their paired `decision` event at the projection layer, not at the JSON Schema layer (cross-event constraints aren't JSON Schema's strength).

**Plan frontmatter schema shape.** Single schema discriminated by `plan_kind`:
- `plan_kind: thematic` requires `tier`, allows optional `tier_prefix`.
- `plan_kind: milestone` requires `milestone_index`.
- Both require `id` (which must match the filename — enforced at validation step outside JSON Schema).

**Validation runs at three points** (M1 → onward):
1. Cache build time — every event re-validated as it's ingested from events.jsonl. Catches manual-edit drift.
2. Extraction time (M2 onward) — per-commit extractor validates each event before appending.
3. Pre-merge-to-main (M3) — part of the cleanliness gate.

## 4. T3 candidates

### M1-scheduled
- `T3-events-schema-json` — draft v0.1.0 schema for all 23 event types. Acceptance: validates the existing bootstrap events.jsonl after retro-migration of the prehistoric events.
- `T3-plan-frontmatter-schema` — draft v0.1.0 schema for plan frontmatter. Acceptance: validates T1, M1, and the four T2 plan files.

### Later milestones
- `T3-schema-versioning-discipline` — formal versioning + migration rules. M2 territory once schema evolution arrives.
- `T3-ontology-prose-sync` — script that diffs prose in T1 §4 against the JSON schema and flags divergence. Could land as M1 stretch or M3.
- `T3-blocker-hitl-frontmatter-schemas` — only when those entity types start carrying their own files.

## 5. Dependencies

- Reads from T1 §4 (the source prose).
- Feeds T2-storage (cache validates events against this schema).
- Feeds T2-projection (knows event-type catalogue for queries).
- Feeds T2-extraction (M2) — extractor is briefed against this schema.

## 6. Open questions

1. **JSON Schema draft version.** draft-07 (broadly supported, conservative) vs 2020-12 (`unevaluatedProperties`, better discriminators). Lean draft-07; revisit if needs justify.
2. **Single file vs many.** One `events.schema.json` with `$defs` is simpler; one-file-per-event-type is more navigable. Lean single file with internal definitions.
3. **Validation tooling.** `ajv` (Node), `jsonschema` / `check-jsonschema` (Python CLI), or both. Bash dev-loop needs at least one. Decide in `T3-events-schema-json`.
4. **Fulcrum-without-decision enforcement.** JSON Schema can't easily enforce "this event requires that event also exists in the log". Capture this at the cache build / projection layer (a derived check), not in schema. Document explicitly.

## 7. Out of scope for this T2

- Generated TypeScript types from JSON Schema (nice-to-have, not load-bearing for M1).
- Runtime performance of validation (validate naively first; profile if it bites).
- Schema-aware extraction prompts (M2 concern, briefed by this T2 but lives in T2-extraction).
