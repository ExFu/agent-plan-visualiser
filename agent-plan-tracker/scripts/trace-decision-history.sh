#!/usr/bin/env bash
# Given an entity_id, list all decision events touching it (via referenced_event_ids).
# Usage: trace-decision-history.sh <entity_id>
set -euo pipefail
ENTITY_ID="${1:?usage: $0 <entity_id>}"
CACHE="${CACHE:-${APT_DATA_DIR:-.agent-plan-tracker}/cache.sqlite}"

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
