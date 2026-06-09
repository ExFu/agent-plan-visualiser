---
id: T2-ontology
plan_kind: thematic
tier: 2
status: active
---

# T2-ontology — Formal event + entity ontology

**Status**: Active. M1 T3s scheduled.
**Theme**: The canonical event types, entity types, derived states, attribute schemas, and ID conventions — captured as machine-readable JSON Schemas plus prose reference. **This T2 is the architectural source of truth for the ontology**; T1 only summarises.

---

## 1. Why this T2 exists

The ontology defines what *kinds of things* exist in the project's event log and how each is shaped. It needs to be:

- **Machine-validated** — extraction at M2 must validate every emitted event against a schema before appending to the log. Cache build at M1 already needs the same. Pre-merge-to-main gate at M3 uses it.
- **Lookup-friendly for downstream agents** — agents extracting or projecting need a precise reference, not narrative.
- **Versioned** — each event carries a `schema_version` field; the schema can evolve without rewriting history.
- **The canonical home for ontological detail** — T1 references this T2 for the actual schemas, derived states, ID conventions, etc.

## 2. What lives in this theme

- **Event types** — 23 events in 6 categories.
- **Entity types** — 5 entity kinds with real lifecycles.
- **Arc metadata** — decisions (text annotations on events, not nodes).
- **Field values** — persons (actor field, not graphed).
- **Derived entity states** — 5 states computed from event history.
- **ID scheme** — how entity IDs are derived per type; how plan files map to IDs.
- **Fulcrum events + decision pairing rule** — which events require a paired decision in the same commit.
- **Schemas** — `schemas/events.schema.json` and `schemas/plan-frontmatter.schema.json` (and later: blocker/hitl/inbox frontmatter schemas as those entities get their own files).
- **Schema versioning** — how `schema_version` binds events to a specific schema file version.

## 3. Architecture — the ontology as it currently stands

### 3.1 Event common fields

Every event carries:

- `event_id` — unique ID (UUID v4 conventional). Lets decisions reference arcs unambiguously; lets relationships point to specific events.
- `type` — the event type (e.g. `entity.completed`).
- `entity_type` — the kind of node the event acts on (e.g. `plan`). Required for all events except meta events (`commit.recorded`).
- `entity_id` — the canonical id within that type (e.g. `T2-ontology`). Required wherever `entity_type` is.
- `actor` — handle or canonical slug identifying the actor. Persons are field values only, not graph nodes.
- `confidence` — `explicit` (stated in commit message or plan) or `derived` (inferred from diff + context).
- `schema_version` — the ontology version this event was extracted against (binds to a specific schemas/<version>/ file).
- `attributes` — event-type-specific extras.

**Commit metadata is carried once per commit, not on every event.** A single `commit.recorded` event terminates each commit's event group, carrying `author`, `date`, `message_first_line` in its attributes. All events between the previous `commit.recorded` (or log start) and the next belong to the closing one (**positional rollup**). Eliminates per-event redundancy when commits emit many events.

No `commit_ref` field in the JSONL — see T2-storage for git-blame-based resolution.

### 3.2 Entity lifecycle events (9)

| Event | Meaning | Fulcrum? |
|---|---|---|
| `entity.created` | First appearance | No |
| `entity.extended` | Content added; includes non-additive plan edits (plan changes are inherently additive by methodology) | No |
| `entity.renamed` | Canonical id migrated old→new (identity migration: history preserved, no phantom, state-neutral). See §3.10, §3.11. | **Yes** — decision required |
| `entity.progressed` | Work was done but didn't reach closure | No |
| `entity.completed` | All per-file changes landed; verification claimed | No |
| `entity.parked` | Explicitly deferred | **Yes** — decision required |
| `entity.cancelled` | Won't be done | **Yes** — decision required |
| `entity.superseded` | Replaced by another entity (link required; `attributes.entity_ids[]` for one-to-many fork) | **Yes** — decision required |
| `entity.reopened` | Previously closed, active again | **Yes** — decision required |

### 3.3 Decision (1)

- `decision` — text annotation with `attributes.text` plus `attributes.event_ids[]` listing the arcs it explains. Required as a paired event for each of the 5 fulcrum events in the same commit. Optional on any non-fulcrum event when justification is worth capturing structurally. One decision can list multiple `event_ids` when a single rationale explains several related arcs (e.g. a T2 supersession spawning two replacement T2s — one decision, three arcs).

### 3.4 Blockers (3)

- `blocker.raised` — external dependency flagged.
- `blocker.progressed` — partial information received from external party (carries `attributes.note`).
- `blocker.closed` — external dependency resolved.

### 3.5 Verification (4) — flagged for ontology review

- `verification.claimed` — commit message or plan asserts completion.
- `verification.tested` — tests written/ran, or smoke validation recorded (attributes typically include `test_type`, `target_file`, `command`, `result`).
- `verification.skipped` — plan's verification step never executed; carries a `reason` attribute.
- `verification.failed` — audit found gap; entity status reverts toward partial.

**Review pending** (see Open questions §5): the 4-event category may be overwrought. A 2-event split (`probably-closed` + `actually-closed` with a different-actor requirement) is a candidate model. Decision after M1 dogfooding surfaces real friction.

### 3.6 Relationships (5)

- `relationship.spawns` — entity A's existence/completion led to entity B. Convention: `entity_id` on the event is the **spawned** (downstream) entity; `attributes.from_entity_type` + `attributes.from_entity_id` identify the spawner.
- `relationship.depends-on` — A blocks B's progress. Same convention: `entity_id` is the dependent; `attributes.from_*` is the dependency.
- `relationship.addendum-to` — A is an addendum within B.
- `relationship.alongside` — co-evolving without dependency (commutative; pick the "newer" side as `entity_id` deterministically — typically the later-created entity).
- `relationship.reattached` — child moved from old parent to new parent (the planning graph's *rebase primitive*). `entity_id` is the child; `attributes` carries `from_parent` and `to_parent` (**not** `from_entity_*` — it is the sole `relationship.*` exception, see §3.8). It does more than annotate: in derived projections it **supersedes the prior `spawns` edge** — the `from_parent spawns child` edge is suppressed and a `to_parent spawns child` edge replaces it, so the node actually moves in the spawn graph the view and tree read. `cache-build` applies this rewrite (pre-scan reattachments → suppress old spawn → insert new spawn → keep a `reattached` provenance row). Used both for supersession cascade resolution and for the milestone-parent rule ([[T1-top-level]] §2.4.0: a milestone that crossed the theme/milestone axes reattaches to its true Tier-1 parent).

### 3.7 Meta (1)

- `commit.recorded` — emitted once per commit as the terminal event of that commit's group. Carries `author`, `date`, `message_first_line` in attributes. All preceding events back to the previous `commit.recorded` (or log start) belong to this commit by positional rollup — no explicit event-id list required. Does not carry `entity_type`/`entity_id` (it has no subject entity; it's a boundary marker). An incomplete trailing run of events with no closing `commit.recorded` represents in-progress extraction not yet sealed.

### 3.8 Total: 23 event types

9 entity lifecycle + 1 decision + 3 blockers + 4 verification + 5 relationships + 1 meta = **23 events**.

### 3.9 Graph node taxonomy

The graph contains three categories:

**Entities (5)** — things with real lifecycles, subjects of work:

| Type | Discriminator | Identity |
|---|---|---|
| `plan` | `plan_kind: thematic` (with `tier`, optional `tier_prefix`) or `plan_kind: milestone` (with `milestone_index`). T3 thematic plans additionally carry `t2_parent` and `milestone` in frontmatter. | Frontmatter `id` field. Form for thematic: `<tier_prefix>T<tier>-<slug>`. Form for milestone: `M<n>-<slug>`. Filename load-bearing — must equal `<id>.md`. |
| `blocker` | (none — single kind) | Hand-authored slug from description |
| `hitl-question` | (none) | Parent plan id + `.q<n>` |
| `implicit-work` | (none) | `impl.<short-commit-hash>.<message-slug>` — auto-generated catch-all for plan-less commits |
| `inbox-item` | (none) | `<date>.<title-slug>` from the inbox heading |

**Arc metadata** — text annotations on events, not graph nodes:

- **decisions** — see §3.3. Each carries its own `event_id`, text content, and a list of `event_ids` it explains. Many arcs can reference the same decision.

**Field values** — not graphed:

- **persons** — handle or canonical slug in the `actor` field on every event. Searchable as values; not nodes with edges. A person is a fact in a register, not a thing being worked on.

### 3.10 Derived entity states (5)

Computed from event history; not directly emitted:

| State | After event(s) |
|---|---|
| `live` | created, extended, progressed, reopened |
| `dormant` | parked (could revive via reopened) |
| `closed` | completed, cancelled, superseded |
| `orphaned` | Derived: parent superseded AND child has no subsequent `relationship.reattached` / `entity.cancelled` / `entity.superseded` |
| `unknown` | Ambiguous event chain — needs human review |

The terminal state was renamed `dead` → `closed` on 2026-06-01 for operator-facing clarity. This is a projection-vocabulary change only: the transition events (`entity.completed` / `entity.cancelled` / `entity.superseded`) are unchanged — `closed` is derived from them, never written to the log.

Orphan derivation is the only non-trivially-mapped state: it's a graph-state computation, not a per-event mapping. Resolved by emitting one of the clearing events.

`entity.renamed` is **state-neutral** — it is an identity migration, not a lifecycle transition, so it is absent from the event→state map (`cache-build` `STATE_FROM_EVENT`) and never changes `derived_state`. Renaming a `closed` entity keeps it `closed` (no resurrection); renaming a `live` one keeps it `live`. (Added 2026-06-08 with the canonical-id rename capability — see §3.11.)

### 3.11 ID scheme summary

| Type | Derivation | Example |
|---|---|---|
| `plan` (thematic) | Frontmatter `id`. Form `<tier_prefix>T<tier>-<slug>`. Filename load-bearing. | `T1-top-level`, `T2-ontology`, `XT2-analytics`, `PT3-client-editor` |
| `plan` (milestone) | `M<n>-<slug>` | `M1-bootstrap`, `M2-auto-extract` |
| `blocker` | Hand-authored slug | `legal-review` |
| `hitl-question` | `<parent-plan-id>.q<n>` | `T2-ontology.q3` |
| `implicit-work` | `impl.<short-hash>.<message-slug>` (auto) | `impl.a1b2c3d.silence-typecheck` |
| `inbox-item` | `<YYYY-MM-DD>.<title-slug>` | `2026-05-23.html-view-style-options` |

Decisions and persons don't follow per-entity ID schemes — decisions have their `event_id`, persons live in the `actor` field as values.

Renames (corrected 2026-06-08 — **supersedes** the prior "id never changes across rename" rule). `entity.renamed` is an **identity migration**: it MAY change an entity's canonical id, carried in `attributes.from_name` → `attributes.to_name`. `cache-build` folds the rename last-write-wins across (a) the renamed entity's own events, (b) every relationship endpoint (`from_entity_id`/`to_entity_id`, `from_parent`/`to_parent`), and (c) frozen frontmatter seeds (`t2_parent`/`milestone`). Consequences: the entity carries its full history forward under the new id; **children follow for free** (no per-child events — their seed pointing at the old id is remapped); and **no phantom row survives** under the old id. Any non-(`from_name`/`to_name`) attributes on the rename event patch the migrated entity's materialised attrs (e.g. a `milestone_index` change accompanying a renumber). Because the filename is load-bearing (filename = id), a canonical-id rename also moves the plan file. The withdrawn rule ("canonical ID established at entity.created persists across rename; the id itself does not change") made the primitive inert — a renamed entity split into a phantom under the old id. First exercised by the `M6-analyser` → `M1.1-analyser` renumber (2026-06-08). A rename that changes only a human-facing title while *intentionally pinning* the id is still expressible — just keep the id unchanged; pinned-id is now a special case of the general migration, not the universal rule.

Sequential task numbering (e.g. `task-1`, `task-2`) is avoided in favour of semantic slugs to prevent parallel-branch collisions.

## 4. Approach — schema authoring

JSON Schema is the chosen spec format (resolved this T2).

**Events schema shape.** One `events.schema.json` with `oneOf` discriminated by `type`. Each branch validates required attributes specific to that type:

- `entity.superseded` requires `attributes.entity_ids[]` (one-to-many fork target).
- `decision` requires `attributes.text` + `attributes.event_ids[]`.
- `blocker.progressed` requires `attributes.note`.
- `relationship.*` events require `attributes.from_entity_type` + `attributes.from_entity_id` (`entity_id` on the event is the focal/result entity) — **except `relationship.reattached`**, which instead requires `attributes.from_parent` + `attributes.to_parent` (it names a move between two parents, not a single spawner). The 0.2.0 schema encodes this exception in the `reattached` branch; the requirement above applies to the other four relationship types.
- Fulcrum-with-decision pairing **cannot** be validated by JSON Schema (cross-event constraint). Caught at the cache build / projection layer instead.

**Plan frontmatter schema shape.** Single `plan-frontmatter.schema.json` discriminated by `plan_kind`:

- `plan_kind: thematic` requires `tier`, allows optional `tier_prefix`. T3 variants require `t2_parent` and `milestone`.
- `plan_kind: milestone` requires `milestone_index`.
- Both require `id`. Filename-equals-id validated outside JSON Schema.

**Validation runs at three points** (M1 → onward):

1. **Cache build time** (M1) — every event re-validated as it's ingested. Catches manual-edit drift.
2. **Extraction time** (M2 onward) — per-commit extractor validates each event before appending.
3. **Pre-merge-to-main** (M3) — part of the cleanliness gate.

**Schema versioning.** Layout `schemas/<version>/events.schema.json`. Events carry `schema_version: "0.1.0"` etc. Bootstrap events at `0.0.0-prehistoric` get migrated to the first stable version (`0.1.0`) once `T3-events-schema-json` lands. The prehistoric→0.1.0 migration is a straight retro-tagging — no information lost, just shape conformance.

## 5. T3 candidates

### M1-scheduled
- `T3-events-schema-json` — draft `schemas/0.1.0/events.schema.json` covering all 23 event types. Acceptance: validates `.agent-plan-tracker/events.jsonl` after retro-migration of prehistoric events.
- `T3-plan-frontmatter-schema` — draft `schemas/0.1.0/plan-frontmatter.schema.json`. Acceptance: validates frontmatter of every plan file currently in `planning/`.

### M2-scheduled
- `T3-entity-accepted` — first deliberate ontology evolution (`0.2.0`→`0.3.0`): new `entity.accepted` standard event (draft→live, all 5 entity types, not a fulcrum), new `draft` derived state (`entity.created` lands `draft`), `entity.extended` becomes draft-preserving (otherwise still reopens). Authored; see plan file.

### Later
- `T3-schema-versioning-discipline` (M2) — formal versioning + migration rules once first schema evolution arrives.
- `T3-ontology-prose-sync` — script diffs T2-ontology prose against schema, flags divergence (M1 stretch or M3).
- `T3-blocker-hitl-frontmatter-schemas` — when those entity types start carrying their own files.
- `T3-verification-overhaul` — depends on §5 Q1 resolution.

## 6. Dependencies

- T1 §3 (themes) — grounding principles.
- Feeds T2-storage (cache build validates events against this schema).
- Feeds T2-projection (event-type catalogue informs queries and views).
- Feeds T2-extraction (M2) — the extractor is briefed against this schema; its prompt embeds the ontology summary.
- Feeds T2-ingest (M5) — backfill agent uses the same schema.

## 7. Open questions

1. **Verification overhaul** (was T1 §5 Q2). Current 4-event category may be overwrought. Candidate replacement: 2-event split `probably-closed` (any agent, after attempting tests if possible) + `actually-closed` (separate agent or human confirms — different actor required). Review after M1 dogfooding.
2. **JSON Schema draft version.** draft-07 (broadly supported, conservative) vs 2020-12 (modern features). Lean draft-07 unless a feature is genuinely needed.
3. **Single file vs many.** One `events.schema.json` with `$defs` is simpler; one-file-per-event-type is more navigable. Lean single file.
4. **Validation tooling.** `ajv` (Node), `jsonschema` / `check-jsonschema` (Python CLI), or both. Decide in `T3-events-schema-json`.
5. **Decision text storage** (was T1 §5 Q1). Inline in the `decision` event vs separate `decisions/<id>.md` files. Each has tradeoffs for searchability, diff-readability, inline-edit-ability. Defer to M1's `T3-events-schema-json`.
6. **Fulcrum-without-decision enforcement.** JSON Schema can't enforce cross-event constraints. Capture at cache build / projection layer as a derived check; document explicitly.

## 8. Out of scope for this T2

- Generated TypeScript types from JSON Schema (nice-to-have, not load-bearing).
- Runtime performance optimisation of validation (profile if it bites; naive first).
- Schema-aware extraction prompts (M2 concern — briefed by this T2, but lives in T2-extraction).
- Discovery as an entity type — out of scope per T1 §7.
