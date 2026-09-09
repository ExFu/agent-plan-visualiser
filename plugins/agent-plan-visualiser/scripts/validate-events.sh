#!/usr/bin/env bash
# Validate JSONL in one process; arguments remain [schema-path] [events-path].
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# The Python entry point resolves dependencies before reading project data.
exec python3 "$SCRIPT_DIR/validate_events.py" "$@"
