-- audit-stalled.sql
-- Live entities with no event activity in the most recent commit.
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
