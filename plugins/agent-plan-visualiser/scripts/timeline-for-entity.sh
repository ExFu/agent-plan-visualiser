#!/usr/bin/env bash
# Chronological event timeline for a single entity.
# Usage: timeline-for-entity.sh <entity_id>
# Reads the cache through audit-run.py (Python sqlite3 — no CLI needed); the
# cache path resolves via apvlib (APV_DATA_DIR -> .apv-config.toml -> .apv/,
# then the cache dir), or pass CACHE=<path> to override.
set -euo pipefail
ENTITY_ID="${1:?usage: $0 <entity_id>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CACHE_ARGS=()
[ -n "${CACHE:-}" ] && CACHE_ARGS=(--cache "$CACHE")

python3 "$SCRIPT_DIR/audit-run.py" - ${CACHE_ARGS[@]+"${CACHE_ARGS[@]}"} <<SQL
SELECT
  line_no,
  type,
  substr(commit_message_first_line, 1, 50) AS commit_msg,
  substr(json_extract(attributes, '\$.summary'), 1, 80) AS summary_snippet
FROM events
WHERE entity_id = '${ENTITY_ID}'
ORDER BY line_no;
SQL
