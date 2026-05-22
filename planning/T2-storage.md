---
id: T2-storage
plan_kind: thematic
tier: 2
status: draft
---

# T2-storage — Event log, cache, projection storage

**Status**: Draft. First T3s scheduled into M1.
**Theme**: The data layer — events.jsonl (canonical), SQLite cache (queryable), projection.json (view-friendly), snapshots (later).

---

## 1. Why this T2 exists

T1 §4.7 sketches the three-tier storage. T2-storage turns sketch into a working layer: schema decisions, build scripts, and the conventions downstream layers depend on.

This is the hinge between events (raw evidence) and projections (consumed views). Mistakes here propagate into every view.

## 2. What lives in this theme

- **`.agent-plan-tracker/events.jsonl`** — canonical, append-only. Schema and format conventions detailed here.
- **`.agent-plan-tracker/cache.sqlite`** — derived. Schema, indexes, regeneration script.
- **`.agent-plan-tracker/projection.json`** — derived. Structure + emitter logic (emitter itself lives in T2-projection).
- **`.agent-plan-tracker/snapshots/<date>/`** — later (M2/M3); not M1 scope.

## 3. Approach

### events.jsonl format
- One event per line, valid JSON.
- Fields per T1 §4.2 (event_id, type, entity_type, entity_id, commit_meta, actor, confidence, schema_version, attributes).
- No trailing whitespace, UTF-8, LF line endings.
- Append-only. Manual edits break git-blame attribution — discipline enforced by hook ownership (M2 onward); M1 we hand-roll carefully.

### SQLite cache schema (v0.1)

**Tables**:

```sql
CREATE TABLE events (
  event_id        TEXT PRIMARY KEY,
  type            TEXT NOT NULL,
  entity_type     TEXT NOT NULL,
  entity_id       TEXT NOT NULL,
  commit_meta     TEXT NOT NULL,        -- JSON
  actor           TEXT NOT NULL,
  confidence      TEXT NOT NULL,
  schema_version  TEXT NOT NULL,
  attributes      TEXT NOT NULL,        -- JSON
  line_no         INTEGER NOT NULL,     -- position in events.jsonl
  commit_ref      TEXT                  -- resolved via git blame, NULL pre-resolve
);

CREATE TABLE entities (
  entity_type           TEXT NOT NULL,
  entity_id             TEXT NOT NULL,
  derived_state         TEXT NOT NULL,   -- live | dormant | dead | orphaned | unknown
  attributes            TEXT,            -- JSON, current materialised attributes
  last_event_id         TEXT NOT NULL,
  event_type_sequence   TEXT NOT NULL,   -- JSON array of event-type names in order
  PRIMARY KEY (entity_type, entity_id)
);

CREATE TABLE relationships (
  from_entity_type      TEXT NOT NULL,
  from_entity_id        TEXT NOT NULL,
  to_entity_type        TEXT NOT NULL,
  to_entity_id          TEXT NOT NULL,
  relationship_type     TEXT NOT NULL,   -- spawns | depends-on | addendum-to | alongside | reattached
  source_event_id       TEXT NOT NULL,   -- event that created this edge
  PRIMARY KEY (from_entity_type, from_entity_id, to_entity_type, to_entity_id, relationship_type)
);

CREATE TABLE decisions (
  decision_event_id     TEXT PRIMARY KEY,
  text                  TEXT NOT NULL,
  referenced_event_ids  TEXT NOT NULL    -- JSON array
);
```

**Indexes**:
- `events`: `(entity_type, entity_id)`, `(type)`, `(commit_ref)`.
- `entities`: `(derived_state)`.
- `relationships`: `(from_entity_type, from_entity_id)`, `(to_entity_type, to_entity_id)`, `(relationship_type)`.

### projection.json shape

```json
{
  "generated_at": "<iso-datetime>",
  "schema_version": "0.1.0",
  "ontology_version": "0.1.0",
  "entities": {
    "plan:T1-top-level": {
      "entity_type": "plan",
      "entity_id": "T1-top-level",
      "derived_state": "live",
      "event_type_sequence": ["entity.created", "entity.extended", "entity.extended", "..."],
      "attributes": { "plan_kind": "thematic", "tier": 1 }
    }
  },
  "relationships": [
    {
      "from": "plan:T1-top-level",
      "to": "plan:T2-ontology",
      "type": "spawns",
      "source_event_id": "..."
    }
  ],
  "decisions": [
    {
      "event_id": "...",
      "text": "...",
      "explains_arcs": ["...", "..."]
    }
  ],
  "summary_stats": {
    "total_events": 0,
    "live_count": 0,
    "dormant_count": 0,
    "dead_count": 0,
    "orphaned_count": 0,
    "open_questions": 11
  },
  "milestone_progress": {
    "M1-bootstrap": {
      "scheduled_t3_count": 10,
      "completed_t3_count": 0,
      "live_t3_count": 0
    }
  }
}
```

Exact shape may evolve in M1 as the HTML view dictates what it actually wants to render — projection-shape and view-needs co-design.

### commit_ref derivation via git blame
- `git blame --line-porcelain .agent-plan-tracker/events.jsonl` → per-line commit hash.
- Populate `events.commit_ref` during cache build.
- Bootstrap events get a real `commit_ref` once the bootstrap commit lands.

## 4. T3 candidates

### M1-scheduled
- `T3-cache-sqlite-schema` — write `CREATE TABLE` statements + the cache-build script (reads events.jsonl, validates against schema from T2-ontology, inserts into tables, materialises `entities` and `relationships`).
- `T3-projection-json-shape` — finalise structure and write the emitter (SQL queries → JSON).
- `T3-git-blame-commit-ref` — implement git-blame-based commit_ref resolution as part of (or alongside) cache build.

### Later
- `T3-snapshots-format` — M2/M3.
- `T3-cache-incremental-rebuild` — performance optimisation, M3+.
- `T3-projection-incremental-emit` — M3+ once full-rebuild becomes slow.

## 5. Dependencies

- Depends on T2-ontology (schemas validate events before cache insertion).
- Feeds T2-projection (cache is the projection source; projection.json shape defined here, emitter lives there).

## 6. Open questions

1. **JSON storage in SQLite.** Use JSON1 (`json_extract`) for ad-hoc queries vs pre-extract attributes into typed columns for indexing? Probably JSON1 for flexibility, with a few key fields promoted to typed columns if profiling demands.
2. **commit_ref resolution timing.** Run git blame at every cache build (simple, slower) or cache blame results (faster, more state)? M1: naive every-build, profile if it bites.
3. **Cache regeneration cost.** O(N) in event count. For M1 (<100 events) trivial. Revisit when snapshots arrive.
4. **Bootstrap event commit_meta correction.** When the bootstrap commit lands, the predicted commit_meta.message_first_line may not match the actual commit message. Either retroactively update the bootstrap events (allowed under 0.0.0-prehistoric) or commit with the message we predicted.

## 7. Out of scope for this T2

- Snapshot format and snapshot-aware cache rebuild — M2/M3.
- Concurrent-write safety (multiple agents appending simultaneously) — not relevant; pre-commit hook serialises.
- Cache replication / multi-machine sync — out of scope; one repo, one log, one cache.
