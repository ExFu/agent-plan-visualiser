-- audit-fulcrum-without-decision.sql
-- Fulcrum events (renamed/parked/cancelled/superseded/reopened) NOT paired
-- with a decision event in the same commit.
.headers on
.mode column

WITH fulcrum AS (
  SELECT * FROM events
  WHERE type IN ('entity.renamed', 'entity.parked', 'entity.cancelled',
                 'entity.superseded', 'entity.reopened')
),
decision_pairings AS (
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
