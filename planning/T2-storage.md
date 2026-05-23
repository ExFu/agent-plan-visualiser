---
id: T2-storage
plan_kind: thematic
tier: 2
status: active
---

# T2-storage — Event log, cache, projection storage

**Status**: Active. M1 T3s scheduled.
**Theme**: The data layer — events.jsonl (canonical), SQLite cache (queryable derived view), projection.json (view-friendly derived snapshot), snapshots (later, M2/M3). **This T2 is the architectural source of truth for storage**; T1 only summarises.

---

## 1. Why this T2 exists

This is the hinge between events (raw evidence) and projections (consumed views). Get it wrong here and every downstream view inherits the pain.

Storage decisions also encode trust assumptions: what gets committed (canonical), what's regenerable (derived), what bridges Git-aware and Git-less consumers (event metadata), what amortises cost (snapshots).

## 2. What lives in this theme

- **`.agent-plan-tracker/events.jsonl`** — canonical, append-only event log. Format conventions, write discipline.
- **`.agent-plan-tracker/cache.sqlite`** — SQLite cache, rebuildable from events.jsonl. Schema, indexes, build script.
- **`.agent-plan-tracker/projection.json`** — current projection emitted from the cache. Shape defined here; emitter lives in T2-projection.
- **`.agent-plan-tracker/snapshots/<YYYY-MM-DD>-<label>/`** — materialised state checkpoints. Format, triggers, agent-orientation role. Later (M2/M3); not M1 scope.
- **`.agent-plan-tracker/schema-version.txt`** — marker file for the currently-active schema version.
- **Commit-ref resolution** — git-blame-based attribution of events.jsonl lines to commit hashes (since events don't carry hashes inline).

## 3. Architecture

### 3.1 Three-tier storage

```
.agent-plan-tracker/
  events.jsonl              # primary, append-only, source of truth
  cache.sqlite              # derived, regenerable, committed for read-performance
  projection.json           # derived, view-friendly
  snapshots/
    <YYYY-MM-DD>-<label>/
      snapshot.json
      projection.json
      summary.md
  schema-version.txt
```

**Trust hierarchy:** events.jsonl is canonical. SQLite and projection.json are rebuildable; their corruption is recoverable by re-running the build. The log itself gets all the integrity discipline (append-only, never manually edited, blame-attributable).

### 3.2 events.jsonl format

- One event per line, valid JSON.
- Fields per T2-ontology §3.1 (event_id, type, entity_type, entity_id, actor, confidence, schema_version, attributes; plus commit.recorded events terminating each commit's group with author/date/message_first_line in attributes).
- No trailing whitespace, UTF-8, LF line endings.
- **Append-only.** Manual edits break git-blame attribution. Discipline enforced by hook ownership in M2 onward; during M1 we hand-roll carefully.
- Schema versioning per event allows ontology evolution without history rewrites. During T1 active authoring, `0.0.0-prehistoric` permits retro-migration; subsequent versions are migration-aware.

### 3.3 SQLite cache schema (v0.1)

```sql
CREATE TABLE events (
  event_id        TEXT PRIMARY KEY,
  type            TEXT NOT NULL,
  entity_type     TEXT,                 -- nullable for meta events (commit.recorded)
  entity_id       TEXT,                 -- nullable for meta events
  actor           TEXT NOT NULL,
  confidence      TEXT NOT NULL,
  schema_version  TEXT NOT NULL,
  attributes      TEXT NOT NULL,        -- JSON
  line_no         INTEGER NOT NULL,     -- position in events.jsonl
  commit_ref      TEXT,                 -- resolved via git blame, NULL pre-resolve
  commit_author   TEXT,                 -- denormalised from terminal commit.recorded
  commit_date     TEXT,                 -- denormalised
  commit_message_first_line TEXT        -- denormalised
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

CREATE TABLE commits (
  commit_ref            TEXT PRIMARY KEY,
  author                TEXT NOT NULL,
  date                  TEXT NOT NULL,
  message_first_line    TEXT NOT NULL,
  commit_recorded_event_id  TEXT NOT NULL,
  first_event_line_no   INTEGER NOT NULL,
  last_event_line_no    INTEGER NOT NULL
);
```

The `commits` table denormalises commit groups for fast lookup and reverse navigation (commit_ref → events). The `events.commit_*` columns are denormalised for query convenience; canonical commit data lives in `commits`.

**Indexes:**
- `events`: `(entity_type, entity_id)`, `(type)`, `(commit_ref)`, `(commit_date)`.
- `entities`: `(derived_state)`.
- `relationships`: `(from_entity_type, from_entity_id)`, `(to_entity_type, to_entity_id)`, `(relationship_type)`.

### 3.4 projection.json shape

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
    { "from": "plan:T1-top-level", "to": "plan:T2-ontology", "type": "spawns", "source_event_id": "..." }
  ],
  "decisions": [
    { "event_id": "...", "text": "...", "explains_arcs": ["...", "..."] }
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

Shape may evolve in M1 as the HTML view drives concrete needs. Shape and view-needs co-design.

### 3.5 commit_ref derivation via git blame

The git commit hash is unknown pre-commit (computed from the tree which includes events.jsonl — chicken-and-egg). Resolution flow:

1. Events in `events.jsonl` do **not** carry `commit_ref` directly.
2. Cache builder runs `git blame --line-porcelain .agent-plan-tracker/events.jsonl` to attribute each line to its source commit.
3. SQLite `events.commit_ref` populated this way.
4. Git-less consumers identify events by `commit_meta` (carried on the terminal `commit.recorded` event of each commit's group) — always populated.
5. Rebase/amend handled naturally: blame always reports the current history's hash.

**Discipline:** `events.jsonl` is only appended to via the pre-commit hook (M2) or the manual extract path (M1 hand-roll). Manual edits break blame attribution.

### 3.6 Snapshots — materialised state + frozen events with commit_refs

(Out of scope for M1; designed here for forward compatibility.)

Three purposes:
1. **Agent orientation.** Session-start agents read the latest snapshot for current state rather than parsing the full event log. Bounded token cost.
2. **Cache rebuild acceleration.** Cache builder reads frozen events (commit_refs already resolved) from the snapshot and only blames the delta since.
3. **Team-readable status milestone.** Committed snapshots give humans a stable reference for "where things were at this point".

Triggers: major plan completions, project milestones, on demand, or auto-rolling every N events (off by default during early use).

Each snapshot directory contains:
- `snapshot.json` — full state at snapshot time, including each entity's event-type sequence and the frozen events with their `commit_refs`.
- `projection.json` — frozen projection for the HTML view to read when exploring history.
- `summary.md` — human-readable digest: open/in-progress, just-closed since last snapshot, blocked, active relationships, quick stats. Notable sequence patterns highlighted (flapping closure, long-running blockers).

### 3.7 Cache rebuild flow (M1)

1. Read `events.jsonl` linewise (preserve line_no).
2. For each line: parse JSON → validate against `schemas/<schema_version>/events.schema.json` from T2-ontology → insert into `events` table.
3. Walk events in order, applying state-machine logic per T2-ontology §3.10 to materialise `entities`, `relationships`, `decisions`, `commits` tables.
4. Run `git blame --line-porcelain events.jsonl` (if in a git repo) → populate `commit_ref` and denormalised commit columns.
5. Verify integrity: every `commit.recorded` event accounted for; every event has a commit_ref (unless tail-pending); no fulcrum events without paired decisions (warn but don't fail — that's the M3 gate's job).

In M3+ this becomes incremental (delta-from-snapshot).

## 4. Swap-out points

- **SQLite as cache backend.** Universal, file-based, sufficient for projected scale (thousands to low tens of thousands of events). Trigger to revisit: >30% of projection queries require multi-hop traversal (depth ≥ 3), or relationship-pattern matching becomes primary projection surface. Then evaluate embedded graph engines with GQL/Cypher support (KuzuDB, Cozo). GQL standardisation reduces historical lock-in risk.
- **JSONL events as primary storage.** Append-only text, blame-friendly. Trigger to revisit: events become large or numerous enough that append-only text scanning becomes slow. Unlikely within this project's scale.

## 5. T3 candidates

### M1-scheduled
- `T3-cache-sqlite-schema` — write `CREATE TABLE` statements + the cache-build script (reads events.jsonl, validates against T2-ontology schemas, populates all tables).
- `T3-projection-json-shape` — finalise structure of projection.json (emitter logic lives in T2-projection; shape spec lives here).
- `T3-git-blame-commit-ref` — implement git-blame-based commit_ref resolution as part of cache build.

### Later
- `T3-snapshots-format` (M2/M3) — snapshot JSON schema + generation script.
- `T3-cache-incremental-rebuild` (M3+) — performance optimisation.
- `T3-projection-incremental-emit` (M3+) — once full-rebuild becomes slow.

## 6. Dependencies

- Depends on T2-ontology (schemas validate events before cache insertion).
- Feeds T2-projection (cache is the projection source; projection.json shape defined here, emitter lives there).
- Feeds T2-extraction (M2) — extraction appends to events.jsonl using this format.

## 7. Open questions

1. **JSON storage in SQLite.** JSON1 (`json_extract`) for flexible ad-hoc queries vs pre-extract attributes into typed columns for indexing? Probably JSON1 with key fields promoted to typed columns if profiling demands.
2. **commit_ref resolution timing.** Naive `git blame` at every cache build (simple, slower) vs cache blame results (faster, more state)? M1 chooses naive; profile if it bites.
3. **Cache regeneration cost.** O(N) in event count. For M1 (<100 events) trivial. Revisit when snapshots arrive.
4. **Bootstrap event commit_meta correction.** Bootstrap events predicted a commit message that may not exactly match what actually landed. Either retroactively update commit_meta on the relevant `commit.recorded` events (allowed under 0.0.0-prehistoric) or rely on git-blame to authoritatively resolve commit_ref + denormalise actual commit data into the cache.
5. **Bootstrap line_no stability.** If the log is ever manually rewritten (e.g. retro-migration to 0.1.0 schema), line numbers shift. The `events.event_id` is stable; line_no is a cache implementation detail. Document this.

## 8. Out of scope for this T2

- Snapshot format and snapshot-aware cache rebuild — M2/M3.
- Concurrent-write safety (multiple agents appending simultaneously) — pre-commit hook serialises.
- Cache replication / multi-machine sync — out of scope; one repo, one log, one cache.
- Encryption / compression of the event log — not relevant at projected scale.
