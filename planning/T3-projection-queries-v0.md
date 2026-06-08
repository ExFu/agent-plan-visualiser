---
id: T3-projection-queries-v0
plan_kind: thematic
tier: 3
t2_parent: T2-projection
milestone: M1-bootstrap
status: completed
---

# T3-projection-queries-v0 — Initial SQL catalogue

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Land the initial query catalogue in `agent-plan-tracker/scripts/`: `audit-stalled.sql`, `audit-fulcrum-without-decision.sql`, `audit-orphans.sql`, `trace-decision-history.sh`, `timeline-for-entity.sh`.

**Architecture:** Plain `.sql` files for queries (invoked via `sqlite3 cache.sqlite < script.sql` or wrapped in shell). Shell wrappers for queries that need parameterisation (entity_id arguments).

**Tech Stack:** SQLite SQL + bash.

---

## 1. Why this T3

The query catalogue is what makes the cache useful for everyday work. Per the cheatsheet inbox item, these are the recurring "show me X" patterns that future agents and humans hit constantly. Pre-baking them saves tokens (agents don't have to derive SQL each time) and provides a reference for SQL idioms specific to this ontology.

## 2. Out of scope

- The full cleanliness gate composite (M3-scheduled).
- Verification-gap audit (defer until verification overhaul resolves).
- HTML view's queries (those live in JS against projection.json).
- Performance optimisation.

## 3. Acceptance criteria

- 5 scripts exist in `agent-plan-tracker/scripts/`:
  - `audit-stalled.sql`
  - `audit-fulcrum-without-decision.sql`
  - `audit-orphans.sql`
  - `trace-decision-history.sh`
  - `timeline-for-entity.sh`
- Each runs cleanly against current cache.
- Output is human-readable (sqlite default columnar; bash wrappers format nicely).
- Each script has a top comment explaining what it answers.

## 4. Steps

### Step 1: `audit-stalled.sql`

**File:** `agent-plan-tracker/scripts/audit-stalled.sql`

```sql
-- audit-stalled.sql
-- Live entities with no event activity in the last commit.
-- Usage: sqlite3 .agent-plan-tracker/cache.sqlite < audit-stalled.sql
.headers on
.mode column

WITH last_commit AS (
  SELECT MAX(last_event_line_no) AS max_line FROM commits
),
last_per_entity AS (
  SELECT entity_type, entity_id, MAX(line_no) AS last_line
  FROM events
  WHERE entity_type IS NOT NULL
  GROUP BY entity_type, entity_id
)
SELECT
  e.entity_type,
  e.entity_id,
  e.derived_state,
  l.last_line AS last_event_line,
  (SELECT max_line FROM last_commit) AS current_max_line
FROM entities e
LEFT JOIN last_per_entity l USING (entity_type, entity_id)
WHERE e.derived_state = 'live'
  AND l.last_line < (SELECT max_line FROM last_commit)
ORDER BY l.last_line ASC;
```

### Step 2: `audit-fulcrum-without-decision.sql`

**File:** `agent-plan-tracker/scripts/audit-fulcrum-without-decision.sql`

```sql
-- audit-fulcrum-without-decision.sql
-- Fulcrum events (renamed/parked/cancelled/superseded/reopened) NOT paired with
-- a decision event in the same commit.
.headers on
.mode column

WITH fulcrum AS (
  SELECT * FROM events
  WHERE type IN ('entity.renamed','entity.parked','entity.cancelled',
                 'entity.superseded','entity.reopened')
),
decision_pairings AS (
  -- A decision event whose attributes.event_ids array contains the fulcrum's event_id.
  SELECT e.event_id AS fulcrum_event_id, d.event_id AS decision_event_id
  FROM fulcrum e
  JOIN events d ON d.type = 'decision'
  WHERE d.commit_ref = e.commit_ref
    AND d.attributes LIKE '%' || e.event_id || '%'
)
SELECT
  f.event_id AS fulcrum_event_id,
  f.type AS fulcrum_type,
  f.entity_type, f.entity_id,
  f.commit_ref,
  f.commit_message_first_line
FROM fulcrum f
LEFT JOIN decision_pairings p ON p.fulcrum_event_id = f.event_id
WHERE p.decision_event_id IS NULL
ORDER BY f.line_no;
```

### Step 3: `audit-orphans.sql`

**File:** `agent-plan-tracker/scripts/audit-orphans.sql`

```sql
-- audit-orphans.sql
-- Entities whose parent (via relationship.spawns) is dead AND the child has not
-- been reattached/cancelled/superseded since.
.headers on
.mode column

WITH dead_parents AS (
  SELECT entity_type, entity_id FROM entities WHERE derived_state = 'dead'
),
orphan_candidates AS (
  SELECT
    r.to_entity_type AS child_type,
    r.to_entity_id AS child_id,
    r.from_entity_type AS parent_type,
    r.from_entity_id AS parent_id
  FROM relationships r
  JOIN dead_parents p ON r.from_entity_type = p.entity_type AND r.from_entity_id = p.entity_id
  WHERE r.relationship_type = 'spawns'
)
SELECT
  oc.child_type, oc.child_id,
  oc.parent_type, oc.parent_id,
  e.derived_state AS child_derived_state
FROM orphan_candidates oc
JOIN entities e ON e.entity_type = oc.child_type AND e.entity_id = oc.child_id
WHERE e.derived_state IN ('live', 'dormant', 'unknown')
ORDER BY oc.child_id;
```

### Step 4: `trace-decision-history.sh`

**File:** `agent-plan-tracker/scripts/trace-decision-history.sh`

```bash
#!/usr/bin/env bash
# Given an entity_id, list all decision events touching it (via referenced_event_ids).
# Usage: trace-decision-history.sh <entity_id>
set -euo pipefail
ENTITY_ID="${1:?usage: $0 <entity_id>}"
CACHE="${CACHE:-.agent-plan-tracker/cache.sqlite}"

sqlite3 -header -column "$CACHE" <<SQL
WITH related_events AS (
  SELECT event_id FROM events WHERE entity_id = '${ENTITY_ID}'
)
SELECT
  d.decision_event_id,
  substr(d.text, 1, 80) AS text_snippet,
  d.referenced_event_ids
FROM decisions d
WHERE EXISTS (
  SELECT 1 FROM related_events re
  WHERE d.referenced_event_ids LIKE '%' || re.event_id || '%'
);
SQL
```

Make executable:
```bash
chmod +x agent-plan-tracker/scripts/trace-decision-history.sh
```

### Step 5: `timeline-for-entity.sh`

**File:** `agent-plan-tracker/scripts/timeline-for-entity.sh`

```bash
#!/usr/bin/env bash
# Chronological event timeline for a single entity.
# Usage: timeline-for-entity.sh <entity_id>
set -euo pipefail
ENTITY_ID="${1:?usage: $0 <entity_id>}"
CACHE="${CACHE:-.agent-plan-tracker/cache.sqlite}"

sqlite3 -header -column "$CACHE" <<SQL
SELECT
  line_no,
  type,
  substr(commit_message_first_line, 1, 50) AS commit,
  substr(json_extract(attributes, '$.summary'), 1, 80) AS summary_snippet
FROM events
WHERE entity_id = '${ENTITY_ID}'
ORDER BY line_no;
SQL
```

Make executable:
```bash
chmod +x agent-plan-tracker/scripts/timeline-for-entity.sh
```

### Step 6: Run each query

```bash
sqlite3 .agent-plan-tracker/cache.sqlite < agent-plan-tracker/scripts/audit-stalled.sql
sqlite3 .agent-plan-tracker/cache.sqlite < agent-plan-tracker/scripts/audit-fulcrum-without-decision.sql
sqlite3 .agent-plan-tracker/cache.sqlite < agent-plan-tracker/scripts/audit-orphans.sql
bash agent-plan-tracker/scripts/trace-decision-history.sh T1-top-level
bash agent-plan-tracker/scripts/timeline-for-entity.sh T1-top-level
```

Verify each runs without error and produces sensible output. (For audit-fulcrum-without-decision: should be empty if we've been disciplined; otherwise it flags the cases we need to fix.)

### Step 7: Commit

```bash
git add agent-plan-tracker/scripts/audit-*.sql agent-plan-tracker/scripts/trace-decision-history.sh agent-plan-tracker/scripts/timeline-for-entity.sh
```

Commit message: `[M1] T3-projection-queries-v0 complete — initial SQL catalogue`

## 5. Files to create / modify

- **Create:** `agent-plan-tracker/scripts/audit-stalled.sql`
- **Create:** `agent-plan-tracker/scripts/audit-fulcrum-without-decision.sql`
- **Create:** `agent-plan-tracker/scripts/audit-orphans.sql`
- **Create:** `agent-plan-tracker/scripts/trace-decision-history.sh`
- **Create:** `agent-plan-tracker/scripts/timeline-for-entity.sh`

## 6. Verification

- All 5 scripts exist and are executable (where applicable).
- Each runs against current cache without error.
- Output is sensible — actual project entities listed.

## 7. HITL questions

- **Q1**: `audit-fulcrum-without-decision.sql` uses `LIKE '%...%'` to search the JSON-string `referenced_event_ids`. Imperfect but adequate for M1 scale. Replace with `json_each()` / proper JSON traversal in M3 if it becomes slow.
- **Q2**: Bash shell wrappers vs SQL files: parameterised queries get bash wrappers (since SQLite CLI doesn't natively take args). Pure summary queries stay SQL-only.

## 8. Events this T3 will emit

- `entity.progressed` on T2-projection.
- `entity.completed` on T3-projection-queries-v0.
- `verification.tested` on T3-projection-queries-v0.
- `entity.progressed` on M1-bootstrap.
- `commit.recorded`.
