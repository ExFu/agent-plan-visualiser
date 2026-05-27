-- audit-orphans.sql
-- Entities whose parent (via relationship.spawns) is dead, AND the child
-- has not been reattached/cancelled/superseded since.
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
  JOIN dead_parents p
    ON r.from_entity_type = p.entity_type
   AND r.from_entity_id = p.entity_id
  WHERE r.relationship_type = 'spawns'
)
SELECT
  oc.child_type,
  oc.child_id,
  oc.parent_type,
  oc.parent_id,
  e.derived_state AS child_derived_state
FROM orphan_candidates oc
JOIN entities e
  ON e.entity_type = oc.child_type
 AND e.entity_id = oc.child_id
WHERE e.derived_state IN ('live', 'dormant', 'unknown')
ORDER BY oc.child_id;
