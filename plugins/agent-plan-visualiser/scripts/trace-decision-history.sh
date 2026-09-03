#!/usr/bin/env bash
# Given an entity_id, list all decision events touching it (via referenced_event_ids).
# Usage: trace-decision-history.sh <entity_id>
# Reads the cache through audit-run.py (Python sqlite3 — no CLI needed); the
# cache path resolves via apvlib (APV_DATA_DIR -> .apv-config.toml -> .apv/,
# then the cache dir), or pass CACHE=<path> to override.
set -euo pipefail
ENTITY_ID="${1:?usage: $0 <entity_id>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CACHE_ARGS=()
[ -n "${CACHE:-}" ] && CACHE_ARGS=(--cache "$CACHE")

python3 "$SCRIPT_DIR/audit-run.py" - ${CACHE_ARGS[@]+"${CACHE_ARGS[@]}"} <<SQL
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
