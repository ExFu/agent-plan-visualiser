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
  substr(commit_message_first_line, 1, 50) AS commit_msg,
  substr(json_extract(attributes, '\$.summary'), 1, 80) AS summary_snippet
FROM events
WHERE entity_id = '${ENTITY_ID}'
ORDER BY line_no;
SQL
