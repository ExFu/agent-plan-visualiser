-- audit-fulcrum-without-decision.sql
-- Fulcrum events (renamed/parked/cancelled/superseded/reopened, plus
-- project.assigned from 0.6.0) NOT paired with a decision event in the
-- same commit.
-- Pairs via commit_recorded_event_id (positional rollup) rather than
-- commit_ref, because commit_ref can collide across events after a bulk
-- rewrite (e.g. schema migration touches every line). commit_recorded_event_id
-- is the canonical commit-membership identifier.
.headers on
.mode column

WITH fulcrum AS (
  SELECT * FROM events
  WHERE type IN ('entity.renamed', 'entity.parked', 'entity.cancelled',
                 'entity.superseded', 'entity.reopened', 'project.assigned')
),
decision_pairings AS (
  SELECT e.event_id AS fulcrum_event_id, d.event_id AS decision_event_id
  FROM fulcrum e
  JOIN events d ON d.type = 'decision'
  WHERE d.commit_recorded_event_id = e.commit_recorded_event_id
    AND d.attributes LIKE '%' || e.event_id || '%'
)
SELECT
  f.event_id AS fulcrum_event_id,
  f.type AS fulcrum_type,
  f.entity_type, f.entity_id,
  f.commit_recorded_event_id,
  f.commit_message_first_line
FROM fulcrum f
LEFT JOIN decision_pairings p ON p.fulcrum_event_id = f.event_id
WHERE p.decision_event_id IS NULL
ORDER BY f.line_no;
