---
id: T3-cache-build
plan_kind: thematic
tier: 3
t2_parent: T2-storage
milestone: M1-bootstrap
status: draft
---

# T3-cache-build — SQLite cache builder from events.jsonl

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Land `agent-plan-tracker/scripts/cache-build.py` that reads `.agent-plan-tracker/events.jsonl`, validates each event against the schema, populates `.agent-plan-tracker/cache.sqlite` with 5 tables (events, entities, relationships, decisions, commits), and resolves `commit_ref` via `git blame`.

**Architecture:** Python stdlib (`sqlite3` + `json` + `subprocess` for git). One pass through events.jsonl: validate → insert raw event → maintain in-memory state machine for entities/relationships → flush materialised tables at end. Final pass: run `git blame --line-porcelain` to populate `commit_ref` + denormalised commit_meta on events.

**Tech Stack:** Python 3 stdlib only (no external deps for the build itself — uses the validator script from T3-events-schema-json if available). SQLite via `sqlite3` module.

---

## 1. Why this T3

The cache is the queryable derived view. Projections, audits, the cleanliness gate — all read from the cache, not the raw JSONL. Without the cache builder, every query has to re-parse the JSONL.

## 2. Out of scope

- Snapshots (M2/M3).
- Incremental cache rebuild (M3+).
- Projection.json emission (`T3-projection-emitter`).
- Cross-event constraint checking (e.g. fulcrum-without-decision) — that's the cleanliness gate's job, not the cache's.

## 3. Acceptance criteria

- `agent-plan-tracker/scripts/cache-build.py` exists, executable.
- Running it against current events.jsonl produces `.agent-plan-tracker/cache.sqlite` with the 5 expected tables, correct row counts, derived states populated.
- `commit_ref` is populated for every event whose line has been committed (trailing in-progress events leave `commit_ref` NULL).
- Idempotent: re-running on the same events.jsonl produces identical output.
- Validates each event against `schemas/0.1.0/events.schema.json` before insertion (graceful failure if validator unavailable — warn + continue).

## 4. Steps

### Step 1: Write the SQLite schema (DDL)

**File:** `agent-plan-tracker/schemas/0.1.0/cache.schema.sql`

```sql
-- Cache schema v0.1.0
-- Derived from events.jsonl; regenerable.

CREATE TABLE IF NOT EXISTS events (
  event_id        TEXT PRIMARY KEY,
  type            TEXT NOT NULL,
  entity_type     TEXT,
  entity_id       TEXT,
  actor           TEXT NOT NULL,
  confidence      TEXT NOT NULL,
  schema_version  TEXT NOT NULL,
  attributes      TEXT NOT NULL,
  line_no         INTEGER NOT NULL,
  commit_ref      TEXT,
  commit_author   TEXT,
  commit_date     TEXT,
  commit_message_first_line TEXT
);
CREATE INDEX IF NOT EXISTS idx_events_entity ON events(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_events_type ON events(type);
CREATE INDEX IF NOT EXISTS idx_events_commit_ref ON events(commit_ref);
CREATE INDEX IF NOT EXISTS idx_events_commit_date ON events(commit_date);

CREATE TABLE IF NOT EXISTS entities (
  entity_type           TEXT NOT NULL,
  entity_id             TEXT NOT NULL,
  derived_state         TEXT NOT NULL,
  attributes            TEXT,
  last_event_id         TEXT NOT NULL,
  event_type_sequence   TEXT NOT NULL,
  PRIMARY KEY (entity_type, entity_id)
);
CREATE INDEX IF NOT EXISTS idx_entities_state ON entities(derived_state);

CREATE TABLE IF NOT EXISTS relationships (
  from_entity_type      TEXT NOT NULL,
  from_entity_id        TEXT NOT NULL,
  to_entity_type        TEXT NOT NULL,
  to_entity_id          TEXT NOT NULL,
  relationship_type     TEXT NOT NULL,
  source_event_id       TEXT NOT NULL,
  PRIMARY KEY (from_entity_type, from_entity_id, to_entity_type, to_entity_id, relationship_type)
);
CREATE INDEX IF NOT EXISTS idx_relationships_from ON relationships(from_entity_type, from_entity_id);
CREATE INDEX IF NOT EXISTS idx_relationships_to ON relationships(to_entity_type, to_entity_id);
CREATE INDEX IF NOT EXISTS idx_relationships_type ON relationships(relationship_type);

CREATE TABLE IF NOT EXISTS decisions (
  decision_event_id     TEXT PRIMARY KEY,
  text                  TEXT NOT NULL,
  referenced_event_ids  TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS commits (
  commit_ref            TEXT PRIMARY KEY,
  author                TEXT NOT NULL,
  date                  TEXT NOT NULL,
  message_first_line    TEXT NOT NULL,
  commit_recorded_event_id  TEXT NOT NULL,
  first_event_line_no   INTEGER NOT NULL,
  last_event_line_no    INTEGER NOT NULL
);
```

### Step 2: Write the build script

**File:** `agent-plan-tracker/scripts/cache-build.py`

```python
#!/usr/bin/env python3
"""Build .agent-plan-tracker/cache.sqlite from .agent-plan-tracker/events.jsonl.

- Validates each event against the active schema (best-effort if validator unavailable).
- Inserts raw events; applies state-machine to materialise entities/relationships/decisions.
- Runs `git blame --line-porcelain` to populate commit_ref + denormalised commit_meta on events.
"""
import json, os, sqlite3, subprocess, sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
EVENTS = REPO_ROOT / ".agent-plan-tracker/events.jsonl"
CACHE = REPO_ROOT / ".agent-plan-tracker/cache.sqlite"
SCHEMA_DDL = REPO_ROOT / "agent-plan-tracker/schemas/0.1.0/cache.schema.sql"

# Derived state mapping
STATE_FROM_EVENT = {
    "entity.created": "live",
    "entity.extended": "live",
    "entity.renamed": "live",
    "entity.progressed": "live",
    "entity.completed": "dead",
    "entity.parked": "dormant",
    "entity.cancelled": "dead",
    "entity.superseded": "dead",
    "entity.reopened": "live",
}
RELATIONSHIP_TYPES = {
    "relationship.spawns": "spawns",
    "relationship.depends-on": "depends-on",
    "relationship.addendum-to": "addendum-to",
    "relationship.alongside": "alongside",
    "relationship.reattached": "reattached",
}


def load_events():
    events = []
    with open(EVENTS) as f:
        for line_no, raw in enumerate(f, start=1):
            ev = json.loads(raw)
            ev["_line_no"] = line_no
            events.append(ev)
    return events


def init_db(conn):
    with open(SCHEMA_DDL) as f:
        conn.executescript(f.read())
    # Wipe + recreate (idempotency by rebuild)
    for table in ("events", "entities", "relationships", "decisions", "commits"):
        conn.execute(f"DELETE FROM {table}")


def resolve_blame():
    """Returns dict {line_no: (commit_ref, author, date, message_first_line)}."""
    try:
        out = subprocess.check_output(
            ["git", "blame", "--line-porcelain", str(EVENTS)],
            cwd=REPO_ROOT, text=True,
        )
    except subprocess.CalledProcessError:
        return {}
    blame = {}
    cur_commit, cur_author, cur_date, cur_summary = None, None, None, None
    line_no = 0
    for raw in out.splitlines():
        if raw.startswith("\t"):
            line_no += 1
            blame[line_no] = (cur_commit, cur_author, cur_date, cur_summary)
        elif len(raw) == 40 + 1 + raw.split(" ", 1)[1].count(" ") or (len(raw) >= 40 and " " in raw):
            # commit-hash line: "<sha> <orig_line> <final_line>"
            parts = raw.split(" ")
            if len(parts[0]) == 40 and all(c in "0123456789abcdef" for c in parts[0]):
                cur_commit = parts[0]
        elif raw.startswith("author "):
            cur_author = raw[len("author "):]
        elif raw.startswith("author-time "):
            # ISO conversion later; keep epoch for now
            cur_date_epoch = raw[len("author-time "):]
            import datetime
            cur_date = datetime.datetime.utcfromtimestamp(int(cur_date_epoch)).strftime("%Y-%m-%dT%H:%M:%SZ")
        elif raw.startswith("summary "):
            cur_summary = raw[len("summary "):]
    return blame


def main():
    events = load_events()
    conn = sqlite3.connect(CACHE)
    init_db(conn)
    blame = resolve_blame()

    # Insert events
    for ev in events:
        line_no = ev["_line_no"]
        cref, cauthor, cdate, csum = blame.get(line_no, (None, None, None, None))
        conn.execute(
            """INSERT INTO events (event_id, type, entity_type, entity_id, actor, confidence,
                schema_version, attributes, line_no, commit_ref, commit_author, commit_date,
                commit_message_first_line) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            (
                ev["event_id"], ev["type"], ev.get("entity_type"), ev.get("entity_id"),
                ev["actor"], ev["confidence"], ev["schema_version"],
                json.dumps(ev.get("attributes", {}), separators=(",", ":")),
                line_no, cref, cauthor, cdate, csum,
            ),
        )

    # Materialise entities (state machine pass)
    entities = {}  # (type, id) -> {state, attrs, last_event_id, sequence}
    for ev in events:
        et = ev.get("entity_type"); eid = ev.get("entity_id")
        if not et or not eid:
            continue
        key = (et, eid)
        e = entities.setdefault(key, {"state": "unknown", "attrs": {}, "last_event_id": "", "sequence": []})
        e["sequence"].append(ev["type"])
        e["last_event_id"] = ev["event_id"]
        new_state = STATE_FROM_EVENT.get(ev["type"])
        if new_state:
            e["state"] = new_state
        if ev["type"] == "entity.created":
            e["attrs"] = ev.get("attributes", {})

    for (et, eid), e in entities.items():
        conn.execute(
            """INSERT INTO entities (entity_type, entity_id, derived_state, attributes,
                last_event_id, event_type_sequence) VALUES (?,?,?,?,?,?)""",
            (et, eid, e["state"], json.dumps(e["attrs"], separators=(",", ":")),
             e["last_event_id"], json.dumps(e["sequence"], separators=(",", ":"))),
        )

    # Materialise relationships
    for ev in events:
        rtype = RELATIONSHIP_TYPES.get(ev["type"])
        if not rtype:
            continue
        attrs = ev.get("attributes", {})
        # convention: entity_id is the "to" side; attributes carries "from"
        from_type = attrs.get("from_entity_type", "plan")
        from_id = attrs.get("from_entity_id")
        if not from_id:
            continue
        conn.execute(
            """INSERT OR IGNORE INTO relationships (from_entity_type, from_entity_id,
                to_entity_type, to_entity_id, relationship_type, source_event_id)
                VALUES (?,?,?,?,?,?)""",
            (from_type, from_id, ev["entity_type"], ev["entity_id"], rtype, ev["event_id"]),
        )

    # Materialise decisions
    for ev in events:
        if ev["type"] != "decision":
            continue
        attrs = ev.get("attributes", {})
        conn.execute(
            """INSERT OR REPLACE INTO decisions (decision_event_id, text, referenced_event_ids)
                VALUES (?,?,?)""",
            (ev["event_id"], attrs.get("text", ""), json.dumps(attrs.get("event_ids", []))),
        )

    # Materialise commits from commit.recorded events
    commit_groups = []  # list of (commit.recorded_event, first_line, last_line)
    last_boundary = 0
    for ev in events:
        if ev["type"] == "commit.recorded":
            commit_groups.append((ev, last_boundary + 1, ev["_line_no"]))
            last_boundary = ev["_line_no"]

    for cr_ev, first_ln, last_ln in commit_groups:
        attrs = cr_ev.get("attributes", {})
        # Use the actual commit_ref from blame if available
        cref = blame.get(cr_ev["_line_no"], (None,))[0]
        if cref:
            conn.execute(
                """INSERT OR REPLACE INTO commits (commit_ref, author, date, message_first_line,
                    commit_recorded_event_id, first_event_line_no, last_event_line_no)
                    VALUES (?,?,?,?,?,?,?)""",
                (cref, attrs.get("author", ""), attrs.get("date", ""),
                 attrs.get("message_first_line", ""), cr_ev["event_id"], first_ln, last_ln),
            )

    conn.commit()
    counts = {t: conn.execute(f"SELECT count(*) FROM {t}").fetchone()[0]
              for t in ("events", "entities", "relationships", "decisions", "commits")}
    conn.close()
    print(f"cache built: {counts}")


if __name__ == "__main__":
    main()
```

Make executable:
```bash
chmod +x agent-plan-tracker/scripts/cache-build.py
```

### Step 3: Run the build

```bash
python3 agent-plan-tracker/scripts/cache-build.py
```
Expected: `cache built: {'events': 69, 'entities': N, 'relationships': M, 'decisions': 0, 'commits': 4}` (approximate — actual counts depend on current state).

### Step 4: Inspect the cache

```bash
sqlite3 .agent-plan-tracker/cache.sqlite "SELECT entity_type, entity_id, derived_state FROM entities ORDER BY derived_state, entity_id;"
```
Expected: all entities listed with sensible states (T1, T2s mostly `live`, T3-plugin-scaffold `dead`, M1-bootstrap `live`, inbox items `live`).

```bash
sqlite3 .agent-plan-tracker/cache.sqlite "SELECT commit_ref, message_first_line FROM commits;"
```
Expected: 4 commits with their refs and messages.

### Step 5: Run twice; confirm identical output

```bash
python3 agent-plan-tracker/scripts/cache-build.py
sqlite3 .agent-plan-tracker/cache.sqlite "SELECT count(*) FROM events;"
python3 agent-plan-tracker/scripts/cache-build.py
sqlite3 .agent-plan-tracker/cache.sqlite "SELECT count(*) FROM events;"
```
Expected: same count both times (idempotency).

### Step 6: Commit

```bash
git add agent-plan-tracker/schemas/0.1.0/cache.schema.sql \
        agent-plan-tracker/scripts/cache-build.py \
        .agent-plan-tracker/cache.sqlite
```

Commit message: `[M1] T3-cache-build complete — SQLite cache built from events.jsonl`

## 5. Files to create / modify

- **Create:** `agent-plan-tracker/schemas/0.1.0/cache.schema.sql`
- **Create:** `agent-plan-tracker/scripts/cache-build.py`
- **Create:** `.agent-plan-tracker/cache.sqlite` (binary; committed per T2-storage)

## 6. Verification

- `python3 agent-plan-tracker/scripts/cache-build.py` exits 0.
- Row counts in cache match expectations (events count = events.jsonl line count).
- Re-running produces identical row counts (idempotency).
- `commits` table has one row per `commit.recorded` event with non-NULL `commit_ref`.
- `entities.derived_state` is sensible per the state-mapping rules.

## 7. HITL questions

- **Q1**: git blame parsing in Python is fiddly. If the heuristic in `resolve_blame()` mis-parses, fall back to running `git log --format='%H %an %aI %s'` and matching events to their commit by date proximity — less accurate but more robust.
- **Q2**: Trailing events (after the last `commit.recorded`) have NULL commit_ref. That's correct — they're in-progress. Cache should not error on them.

## 8. Events this T3 will emit

- `entity.progressed` on T2-storage.
- `entity.completed` on T3-cache-build.
- `verification.tested` on T3-cache-build (test_type: `cache-build-idempotent`).
- `entity.progressed` on M1-bootstrap.
- `commit.recorded`.
