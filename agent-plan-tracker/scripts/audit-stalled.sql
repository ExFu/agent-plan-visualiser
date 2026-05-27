-- audit-stalled.sql
-- Live entities with no event activity in the most recent commit.
-- A live entity is "stalled" if its last event occurred BEFORE the start of
-- the latest commit's event range — i.e. it didn't fire during the most
-- recent commit. Uses first_event_line_no of the latest commit as threshold
-- (NOT last_event_line_no, which would flag entities that fired but not on
-- the very last line of the commit).
-- Usage: sqlite3 .agent-plan-tracker/cache.sqlite < audit-stalled.sql
.headers on
.mode column

WITH latest_commit AS (
  SELECT first_event_line_no, last_event_line_no
  FROM commits
  ORDER BY last_event_line_no DESC
  LIMIT 1
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
  (SELECT first_event_line_no FROM latest_commit) AS latest_commit_starts_at
FROM entities e
LEFT JOIN last_per_entity l USING (entity_type, entity_id)
WHERE e.derived_state = 'live'
  AND l.last_line < (SELECT first_event_line_no FROM latest_commit)
ORDER BY l.last_line ASC;
