#!/usr/bin/env bash
# Validate every event in events.jsonl against the active schema.
# Usage: validate-events.sh [schema-path] [events-path]
set -uo pipefail
SCHEMA="${1:-agent-plan-tracker/schemas/0.1.0/events.schema.json}"
EVENTS="${2:-.agent-plan-tracker/events.jsonl}"

if ! command -v check-jsonschema >/dev/null 2>&1; then
  echo "check-jsonschema not installed; trying python3 fallback..." >&2
  python3 - "$SCHEMA" "$EVENTS" <<'PYEOF'
import sys, json
try:
    from jsonschema import validate, ValidationError
except ImportError:
    sys.stderr.write(
        f"jsonschema not installed for {sys.executable}.\n"
        f"Run: {sys.executable} -m pip install --user jsonschema\n"
        f"(Plain 'pip install ...' may install to a different Python — use the exact command above.)\n"
    )
    sys.exit(2)
schema_path, events_path = sys.argv[1], sys.argv[2]
with open(schema_path) as f:
    schema = json.load(f)
fail = 0
ok = 0
with open(events_path) as f:
    for i, raw in enumerate(f, start=1):
        try:
            ev = json.loads(raw)
        except json.JSONDecodeError as e:
            print(f"FAIL line {i}: JSON parse: {e}", file=sys.stderr)
            fail += 1
            continue
        try:
            validate(instance=ev, schema=schema)
            ok += 1
        except ValidationError as e:
            print(f"FAIL line {i} ({ev.get('event_id', '?')}): {e.message}", file=sys.stderr)
            fail += 1
if fail:
    print(f"{fail} events failed; {ok} valid", file=sys.stderr)
    sys.exit(1)
print(f"all {ok} events valid")
PYEOF
  exit $?
fi

# check-jsonschema route
FAIL=0
LINE=0
while IFS= read -r raw; do
  LINE=$((LINE + 1))
  if ! echo "$raw" | check-jsonschema --schemafile "$SCHEMA" - >/dev/null 2>&1; then
    echo "FAIL line $LINE" >&2
    FAIL=$((FAIL + 1))
  fi
done < "$EVENTS"
if [ "$FAIL" -gt 0 ]; then
  echo "$FAIL events failed validation" >&2
  exit 1
fi
echo "all $LINE events valid"
