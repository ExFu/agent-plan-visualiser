#!/usr/bin/env bash
# run-view-sandbox.sh — T3-historical-projection-ui §4: the view serves and
# renders for a plain `.apv/` adopter (no vendored toolchain, no config, no
# env), with the 0.4.0 provenance contract wired through:
#
#   1. serve.py, run from the plugin home inside an adopter repo, serves the
#      view from the TOOLCHAIN, /data/* from the apvlib-resolved data dir,
#      /planning/* from the target repo — and blocks path traversal.
#   2. The projection served carries origin; app.js/style.css carry the
#      unfurl + ghosting + provenance-filter + open-question wiring (static
#      assertions; visual taste is the operator's pass).
#   3. Grep audit: no dogfood-data-dir literals remain in view/ except the
#      documented legacy fallbacks.
#
# Exits 0 when every case passes; 1 on the first failure.
set -uo pipefail
cd "$(dirname "$0")" || exit 2
WT_ROOT="$(cd ../../.. && pwd)"
FAIL=0
SERVER_PID=""

check() { # check <desc> <test-expr...>
  local desc="$1"; shift
  if "$@"; then
    echo "  ok: $desc"
  else
    echo "  FAIL: $desc"
    FAIL=1
  fi
}

SANDBOX="$(mktemp -d /tmp/apv-view-sandbox.XXXXXX)" || exit 2
cleanup() { [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null; rm -rf "$SANDBOX"; }
trap cleanup EXIT
unset APV_DATA_DIR APV_GATE_CHECK APV_SKIP_GATE

PLUGIN_HOME="$SANDBOX/plugin-home"
cp -R "$WT_ROOT/agent-plan-visualiser" "$PLUGIN_HOME"

uu() { python3 -c "import uuid; print(uuid.uuid4())"; }

# --- adopter repo: .apv default, mixed captured+backfilled log ---------------
git init -q -b main "$SANDBOX/project"
cd "$SANDBOX/project" || exit 2
git config user.email view@example.invalid
git config user.name "View Sandbox"
mkdir -p .apv planning
printf -- "---\nid: VIEW-A\nplan_kind: thematic\ntier: 3\nstatus: draft\n---\n\n# VIEW-A\n\nbody\n" > planning/VIEW-A.md
F_SUP="$(uu)"
cat >> .apv/events.jsonl <<JSON
{"event_id": "$(uu)", "type": "entity.created", "actor": "al", "confidence": "explicit", "schema_version": "0.3.0", "entity_type": "plan", "entity_id": "VIEW-A", "attributes": {"summary": "captured-era plan"}}
{"event_id": "$(uu)", "type": "entity.accepted", "actor": "al", "confidence": "explicit", "schema_version": "0.3.0", "entity_type": "plan", "entity_id": "VIEW-A", "attributes": {"summary": "operator acceptance"}}
{"event_id": "$(uu)", "type": "commit.recorded", "actor": "al", "confidence": "explicit", "schema_version": "0.3.0", "attributes": {"author": "al", "date": "2026-07-03", "message_first_line": "adopt tracking"}}
{"event_id": "$(uu)", "type": "entity.created", "origin": "backfilled", "actor": "backfill-agent", "confidence": "derived", "schema_version": "0.4.0", "entity_type": "plan", "entity_id": "VIEW-H", "attributes": {"backfill_run": "bf-view", "summary": "mined plan"}}
{"event_id": "$F_SUP", "type": "entity.superseded", "origin": "backfilled", "actor": "backfill-agent", "confidence": "derived", "schema_version": "0.4.0", "entity_type": "plan", "entity_id": "VIEW-H", "attributes": {"backfill_run": "bf-view", "entity_ids": ["VIEW-A"], "summary": "replaced"}}
{"event_id": "$(uu)", "type": "entity.created", "origin": "backfilled", "actor": "backfill-agent", "confidence": "derived", "schema_version": "0.4.0", "entity_type": "hitl-question", "entity_id": "VIEW-H.q1", "attributes": {"backfill_run": "bf-view", "event_ids": ["$F_SUP"], "summary": "Why superseded? Candidates: A / B."}}
{"event_id": "$(uu)", "type": "commit.recorded", "origin": "backfilled", "actor": "backfill-agent", "confidence": "derived", "schema_version": "0.4.0", "attributes": {"backfill_run": "bf-view", "commit_ref": "0123456789abcdef0123456789abcdef01234567", "author": "someone", "date": "2025-02-01", "message_first_line": "hist: old work"}}
JSON

run_py() { python3 "$PLUGIN_HOME/scripts/$1"; }
echo "== pipeline runs from the plugin home in a bare .apv adopter"
check "cache builds (no env, no config)"  run_py cache-build.py
check "projection emits"                  run_py projection-emit.py
check "summary emits"                     run_py summary-emit.py
check "data landed in .apv"               [ -f .apv/projection.json ]

# --- serve.py ------------------------------------------------------------------
echo "== serve.py: toolchain view + adopter data, traversal blocked"
PORT=8799
python3 "$PLUGIN_HOME/scripts/serve.py" --port "$PORT" >/dev/null 2>&1 &
SERVER_PID=$!
for i in $(seq 1 30); do curl -sf "http://127.0.0.1:$PORT/api/clean-check" >/dev/null 2>&1 && break; sleep 0.2; done

http_code() { curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$PORT$1"; }
check "view index served"               [ "$(http_code /view/index.html)" = "200" ]
check "app.js served"                   [ "$(http_code /view/app.js)" = "200" ]
check "root redirects to the view"      [ "$(http_code /)" = "302" ]
check "projection served from /data"    [ "$(http_code /data/projection.json)" = "200" ]
check "events served from /data"        [ "$(http_code /data/events.jsonl)" = "200" ]
check "plan served from /planning"      [ "$(http_code /planning/VIEW-A.md)" = "200" ]
check "traversal blocked"               sh -c "[ \"\$(curl --path-as-is -s -o /dev/null -w '%{http_code}' 'http://127.0.0.1:$PORT/data/../planning/VIEW-A.md')\" != '200' ]"
check "origin in served projection"     sh -c "curl -s http://127.0.0.1:$PORT/data/projection.json | grep -q '\"origin\":\"backfilled\"'"
check "mixed rollup in projection"      sh -c "curl -s http://127.0.0.1:$PORT/data/projection.json | python3 -c \"import json,sys; p=json.load(sys.stdin); assert p['entities']['plan:VIEW-H']['origin']=='backfilled'; assert p['entities']['plan:VIEW-A']['origin']=='captured'\""

# --- static wiring assertions -----------------------------------------------
echo "== view wiring: unfurl, provenance filter, ghosting, open questions"
APP="$PLUGIN_HOME/view/app.js"
CSS="$PLUGIN_HOME/view/style.css"
check "event-time unfurl present"       grep -q "Event-time unfurl" "$APP"
check "provenance filter present"       grep -q 'provenance-filter' "$APP"
check "provenance visibility step"      grep -q 'filters.provenance === "captured"' "$APP"
check "node ghost class wired"          grep -q 'allBackfilled ? " ghost"' "$APP"
check "spine ghost class wired"         grep -q 'spineGhost ? " ghost"' "$APP"
check "origin badge wired"              grep -q 'origin-badge' "$APP"
check "open-question badge wired"       grep -q 'question-badge' "$APP"
check "css ghost styles present"        grep -q '.node.ghost' "$CSS"
check "css origin badge present"        grep -q '.badge.origin-badge' "$CSS"
check "js syntax valid"                 node --check "$APP"

echo "== grep audit: no dogfood literals in view/ outside legacy fallbacks"
STRAYS=$(grep -rn "agent-plan-tracker" "$PLUGIN_HOME/view" | grep -v "legacy\|fallbacks for plain" | grep -v '\.\./\.\./\.agent-plan-tracker' || true)
if [ -n "$STRAYS" ]; then
  echo "  FAIL: stray dogfood literals:"; echo "$STRAYS" | sed 's/^/    | /'
  FAIL=1
else
  echo "  ok: only documented legacy fallbacks remain"
fi

echo
if [ "$FAIL" -eq 0 ]; then
  echo "view sandbox: ALL PASS"
else
  echo "view sandbox: FAILURES (see above)"
fi
exit "$FAIL"
