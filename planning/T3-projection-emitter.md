---
id: T3-projection-emitter
plan_kind: thematic
tier: 3
t2_parent: T2-projection
milestone: M1-bootstrap
status: draft
---

# T3-projection-emitter — projection.json emitter from SQLite cache

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Land `agent-plan-tracker/scripts/projection-emit.py` that reads `cache.sqlite` and emits `.agent-plan-tracker/projection.json` per the shape in T2-storage §3.4.

**Architecture:** Python stdlib only. SQL queries pull entities + relationships + decisions + commits; assemble into the projection.json shape; write atomically (write to `.tmp` then rename).

**Tech Stack:** Python 3 stdlib (`sqlite3`, `json`, `datetime`).

---

## 1. Why this T3

The projection is the API consumed by the HTML view (`T3-html-view`), the markdown summary (`T3-markdown-summary`), and (eventually) the cleanliness gate. It's a single JSON snapshot of current project state, generated mechanically from the cache. Without it, every consumer would re-run its own SQL.

## 2. Out of scope

- Per-snapshot projection (`snapshots/<date>/projection.json`) — M2/M3.
- Incremental emission — M3+.
- Pretty-printing options (default: compact JSON).
- Schema for projection.json itself (we live without one for M1; if drift becomes a problem, add a `projection.schema.json` later).

## 3. Acceptance criteria

- `agent-plan-tracker/scripts/projection-emit.py` exists, executable.
- Running it produces a valid JSON file at `.agent-plan-tracker/projection.json`.
- Shape matches T2-storage §3.4: `generated_at`, `schema_version`, `ontology_version`, `entities`, `relationships`, `decisions`, `summary_stats`, `milestone_progress`.
- `summary_stats.total_events` matches events.jsonl line count.
- `milestone_progress` reflects accurate T3 counts per milestone.

## 4. Steps

### Step 1: Write the emitter

**File:** `agent-plan-tracker/scripts/projection-emit.py`

```python
#!/usr/bin/env python3
"""Emit .agent-plan-tracker/projection.json from cache.sqlite."""
import json, sqlite3, datetime
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
CACHE = REPO_ROOT / ".agent-plan-tracker/cache.sqlite"
OUT = REPO_ROOT / ".agent-plan-tracker/projection.json"

SCHEMA_VERSION = "0.1.0"
ONTOLOGY_VERSION = "0.1.0"


def main():
    conn = sqlite3.connect(CACHE)
    conn.row_factory = sqlite3.Row

    # Entities
    entities = {}
    for row in conn.execute("SELECT * FROM entities"):
        key = f"{row['entity_type']}:{row['entity_id']}"
        entities[key] = {
            "entity_type": row["entity_type"],
            "entity_id": row["entity_id"],
            "derived_state": row["derived_state"],
            "event_type_sequence": json.loads(row["event_type_sequence"]),
            "attributes": json.loads(row["attributes"] or "{}"),
        }

    # Relationships
    relationships = []
    for row in conn.execute("SELECT * FROM relationships"):
        relationships.append({
            "from": f"{row['from_entity_type']}:{row['from_entity_id']}",
            "to": f"{row['to_entity_type']}:{row['to_entity_id']}",
            "type": row["relationship_type"],
            "source_event_id": row["source_event_id"],
        })

    # Decisions
    decisions = []
    for row in conn.execute("SELECT * FROM decisions"):
        decisions.append({
            "event_id": row["decision_event_id"],
            "text": row["text"],
            "explains_arcs": json.loads(row["referenced_event_ids"]),
        })

    # Summary stats
    state_counts = {s: 0 for s in ("live", "dormant", "dead", "orphaned", "unknown")}
    for row in conn.execute("SELECT derived_state, count(*) c FROM entities GROUP BY derived_state"):
        state_counts[row["derived_state"]] = row["c"]
    total_events = conn.execute("SELECT count(*) FROM events").fetchone()[0]
    summary_stats = {
        "total_events": total_events,
        "live_count": state_counts["live"],
        "dormant_count": state_counts["dormant"],
        "dead_count": state_counts["dead"],
        "orphaned_count": state_counts["orphaned"],
        "unknown_count": state_counts["unknown"],
    }

    # Milestone progress — read T3 plan files to find which milestone they belong to + their state
    # For M1: read frontmatter via the validator's approach (or just scan files)
    milestone_progress = compute_milestone_progress(entities)

    projection = {
        "generated_at": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
        "schema_version": SCHEMA_VERSION,
        "ontology_version": ONTOLOGY_VERSION,
        "entities": entities,
        "relationships": relationships,
        "decisions": decisions,
        "summary_stats": summary_stats,
        "milestone_progress": milestone_progress,
    }

    # Atomic write
    tmp = OUT.with_suffix(".tmp")
    with open(tmp, "w") as f:
        json.dump(projection, f, separators=(",", ":"))
    tmp.replace(OUT)
    print(f"projection emitted: {len(entities)} entities, {len(relationships)} relationships, {len(decisions)} decisions, {summary_stats}")
    conn.close()


def compute_milestone_progress(entities):
    """Walk planning/ T3 plan files; read milestone frontmatter; aggregate."""
    import re, glob
    try:
        import yaml
    except ImportError:
        return {}
    progress = {}
    for path in glob.glob(str(REPO_ROOT / "planning/T3-*.md")):
        with open(path) as f:
            content = f.read()
        m = re.match(r"^---\n(.*?)\n---\n", content, re.DOTALL)
        if not m:
            continue
        fm = yaml.safe_load(m.group(1))
        milestone = fm.get("milestone")
        if not milestone:
            continue
        slot = progress.setdefault(milestone, {"scheduled_t3_count": 0, "completed_t3_count": 0, "live_t3_count": 0})
        slot["scheduled_t3_count"] += 1
        # Find the entity in the entities dict
        t3_id = fm.get("id")
        ent = entities.get(f"plan:{t3_id}")
        if ent:
            if ent["derived_state"] == "live":
                slot["live_t3_count"] += 1
            elif ent["derived_state"] == "dead":
                slot["completed_t3_count"] += 1
    return progress


if __name__ == "__main__":
    main()
```

Make executable:
```bash
chmod +x agent-plan-tracker/scripts/projection-emit.py
```

### Step 2: Run the emitter

```bash
python3 agent-plan-tracker/scripts/projection-emit.py
```
Expected: `projection emitted: N entities, M relationships, K decisions, {...stats...}`.

### Step 3: Validate JSON output

```bash
python3 -m json.tool .agent-plan-tracker/projection.json > /dev/null && echo "valid JSON"
```
Expected: `valid JSON`.

### Step 4: Spot-check the structure

```bash
python3 -c "
import json
p = json.load(open('.agent-plan-tracker/projection.json'))
for key in ('generated_at', 'schema_version', 'entities', 'relationships', 'decisions', 'summary_stats', 'milestone_progress'):
    assert key in p, f'missing key: {key}'
print('all expected keys present')
print(f'entity sample: {list(p[\"entities\"].keys())[:3]}')
print(f'milestone_progress: {p[\"milestone_progress\"]}')
"
```

### Step 5: Commit

```bash
git add agent-plan-tracker/scripts/projection-emit.py .agent-plan-tracker/projection.json
```

Commit message: `[M1] T3-projection-emitter complete — projection.json emitted from cache`

## 5. Files to create / modify

- **Create:** `agent-plan-tracker/scripts/projection-emit.py`
- **Create:** `.agent-plan-tracker/projection.json`

## 6. Verification

- Script exits 0 and reports counts.
- JSON file parses cleanly.
- All expected keys present.
- Milestone progress includes M1-bootstrap with a non-zero scheduled count.

## 7. HITL questions

- **Q1**: Should milestone-progress be computed from cache (via SQL) or from filesystem (reading frontmatter)? Plan above reads filesystem because frontmatter is the source-of-truth for milestone tagging, but cache could carry it if we promote `milestone` to a typed column on entities. Defer to feedback after first use.

## 8. Events this T3 will emit

- `entity.progressed` on T2-projection.
- `entity.completed` on T3-projection-emitter.
- `verification.tested` on T3-projection-emitter.
- `entity.progressed` on M1-bootstrap.
- `commit.recorded`.
