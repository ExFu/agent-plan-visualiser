#!/usr/bin/env bash
# run-provenance-sandbox.sh — T3-origin-provenance-schema §4: the 0.4.0
# bitemporal/provenance epoch behaves as ratified (T2-ontology §3.12).
#
#   1. A mixed log (captured blocks + a backfilled segment anchored to real
#      historical commits) passes the gate: backfilled seals carry
#      commit_ref and match reachable history; discipline checks skip
#      backfilled events; a tier-3 hitl-question stands in for a backfilled
#      fulcrum's decision.
#   2. The SAME shapes without origin: backfilled — implementation-on-draft
#      and fulcrum-without-decision BLOCK (origin is load-bearing, not
#      decorative).
#   3. The unfurl: derived state replays in EVENT time — a backfilled 2025
#      close followed (in event time) by a captured 2026 reopen+progress
#      derives `live`, even though the backfilled lines sit LAST in the log.
#   4. Repudiation: filtering a backfill_run cohort out reproduces the
#      pre-run record.
#
# Exits 0 when every case passes; 1 on the first failure.
set -uo pipefail
cd "$(dirname "$0")" || exit 2
WT_ROOT="$(cd ../../.. && pwd)"
PLUGIN="$WT_ROOT/agent-plan-visualiser"
FAIL=0

check() { # check <desc> <test-expr...>
  local desc="$1"; shift
  if "$@"; then
    echo "  ok: $desc"
  else
    echo "  FAIL: $desc"
    FAIL=1
  fi
}

run() { # run <cmd...> -> sets OUT, CODE
  OUT="$("$@" 2>&1)"
  CODE=$?
}

SANDBOX="$(mktemp -d /tmp/apv-provenance-sandbox.XXXXXX)" || exit 2
trap 'rm -rf "$SANDBOX"' EXIT
unset APV_DATA_DIR APV_GATE_CHECK APV_SKIP_GATE

uu() { python3 -c "import uuid; print(uuid.uuid4())"; }

# --- repo with real pre-adoption history -------------------------------------
git init -q -b main "$SANDBOX/work"
cd "$SANDBOX/work" || exit 2
git config user.email prov@example.invalid
git config user.name "Prov Sandbox"
echo one > a.txt && git add -A && git commit -qm "hist: first work"
SHA_A="$(git rev-parse HEAD)"
echo two > b.txt && git add -A && git commit -qm "hist: second work"
SHA_B="$(git rev-parse HEAD)"

# Adoption: captured block (0.3.0 era shapes) — includes the captured half
# of the unfurl proof: PROV-C is reopened+progressed in 2026, while its
# birth and closure arrive LATER in the record (backfilled, anchored 2025).
mkdir -p .apv
E_REOPEN="$(uu)"
cat >> .apv/events.jsonl <<JSON
{"event_id": "$(uu)", "type": "entity.created", "actor": "al", "confidence": "explicit", "schema_version": "0.3.0", "entity_type": "plan", "entity_id": "PROV-A", "attributes": {"summary": "adoption-era plan"}}
{"event_id": "$(uu)", "type": "entity.accepted", "actor": "al", "confidence": "explicit", "schema_version": "0.3.0", "entity_type": "plan", "entity_id": "PROV-A", "attributes": {"summary": "operator acceptance"}}
{"event_id": "$E_REOPEN", "type": "entity.reopened", "actor": "al", "confidence": "explicit", "schema_version": "0.3.0", "entity_type": "plan", "entity_id": "PROV-C", "attributes": {"summary": "pre-adoption plan deliberately revived"}}
{"event_id": "$(uu)", "type": "decision", "actor": "al", "confidence": "explicit", "schema_version": "0.3.0", "attributes": {"text": "PROV-C revived: the old approach applies after all.", "event_ids": ["$E_REOPEN"]}}
{"event_id": "$(uu)", "type": "entity.progressed", "actor": "al", "confidence": "explicit", "schema_version": "0.3.0", "entity_type": "plan", "entity_id": "PROV-C", "attributes": {"summary": "new work on the revived plan"}}
{"event_id": "$(uu)", "type": "commit.recorded", "actor": "al", "confidence": "explicit", "schema_version": "0.3.0", "attributes": {"author": "al", "date": "2026-07-03", "message_first_line": "adopt tracking"}}
JSON
printf '.apv/.last-capture\n' > .gitignore
git add -A && git commit -qm "adopt tracking" --no-verify

# The backfilled segment: one block per historical commit, appended at the
# record tail, anchored to 2025 via commit_ref. Includes:
#  - PROV-H created+progressed while draft (discipline skip proof);
#  - PROV-OLD superseded with a tier-3 hitl-question stand-in (no decision);
#  - PROV-C created+completed (event-time BEFORE the captured reopen above).
RUN="bf-2026-07-03-a"
F_SUP="$(uu)"
backfilled_segment() { # emits to stdout; $1 = "yes" to include origin field
  local O=""
  [ "$1" = "yes" ] && O='"origin": "backfilled", '
  local BR=""
  [ "$1" = "yes" ] && BR='"backfill_run": "'$RUN'", '
  cat <<JSON
{"event_id": "$(uu)", "type": "entity.created", ${O}"actor": "backfill-agent", "confidence": "derived", "schema_version": "0.4.0", "entity_type": "plan", "entity_id": "PROV-H", "attributes": {${BR}"summary": "historical plan, mined"}}
{"event_id": "$(uu)", "type": "entity.progressed", ${O}"actor": "backfill-agent", "confidence": "derived", "schema_version": "0.4.0", "entity_type": "plan", "entity_id": "PROV-H", "attributes": {${BR}"summary": "historical work — no acceptance ceremony existed then"}}
{"event_id": "$(uu)", "type": "entity.created", ${O}"actor": "backfill-agent", "confidence": "derived", "schema_version": "0.4.0", "entity_type": "plan", "entity_id": "PROV-C", "attributes": {${BR}"summary": "pre-adoption plan, mined"}}
{"event_id": "$(uu)", "type": "entity.completed", ${O}"actor": "backfill-agent", "confidence": "derived", "schema_version": "0.4.0", "entity_type": "plan", "entity_id": "PROV-C", "attributes": {${BR}"summary": "closed in 2025 (later revived in the captured era)"}}
{"event_id": "$(uu)", "type": "commit.recorded", ${O}"actor": "backfill-agent", "confidence": "derived", "schema_version": "0.4.0", "attributes": {${BR}"commit_ref": "$SHA_A", "author": "prov-sandbox", "date": "2025-03-10", "message_first_line": "hist: first work"}}
{"event_id": "$(uu)", "type": "entity.created", ${O}"actor": "backfill-agent", "confidence": "derived", "schema_version": "0.4.0", "entity_type": "plan", "entity_id": "PROV-OLD", "attributes": {${BR}"summary": "the approach later replaced"}}
{"event_id": "$F_SUP", "type": "entity.superseded", ${O}"actor": "backfill-agent", "confidence": "derived", "schema_version": "0.4.0", "entity_type": "plan", "entity_id": "PROV-OLD", "attributes": {${BR}"entity_ids": ["PROV-H"], "summary": "replaced by PROV-H — rationale unrecovered"}}
{"event_id": "$(uu)", "type": "entity.created", ${O}"actor": "backfill-agent", "confidence": "derived", "schema_version": "0.4.0", "entity_type": "hitl-question", "entity_id": "PROV-OLD.q1", "attributes": {${BR}"event_ids": ["$F_SUP"], "summary": "Why was PROV-OLD superseded? Candidates: (a) perf ceiling, (b) upstream API change, (c) scope pivot. Unconfirmed — tier-3 inferred."}}
{"event_id": "$(uu)", "type": "commit.recorded", ${O}"actor": "backfill-agent", "confidence": "derived", "schema_version": "0.4.0", "attributes": {${BR}"commit_ref": "$SHA_B", "author": "prov-sandbox", "date": "2025-04-22", "message_first_line": "hist: second work"}}
JSON
}

cp .apv/events.jsonl "$SANDBOX/pre-run-events.jsonl"
backfilled_segment yes >> .apv/events.jsonl
git add -A && git commit -qm "backfill($RUN): commits ${SHA_A:0:7}..${SHA_B:0:7}, 2 blocks" --no-verify

# --- Case 1: the mixed log is gate-green --------------------------------------
echo "== mixed log: gate green (origin-aware discipline, hitl stand-in, anchored seals)"
run bash "$PLUGIN/scripts/gate-check.sh" --repo-root "$PWD"
check "gate-check PASS"                 [ "$CODE" -eq 0 ]
if grep -q "^BLOCK" <<<"$OUT"; then
  echo "  FAIL: no blocking instances"; FAIL=1
else
  echo "  ok: no blocking instances"
fi
check "verdict line present"            grep -q "gate-check: PASS" <<<"$OUT"

# --- Case 2: origin is load-bearing --------------------------------------------
echo "== same shapes WITHOUT origin: discipline blocks"
mkdir -p "$SANDBOX/noorigin/.apv"
cp "$SANDBOX/pre-run-events.jsonl" "$SANDBOX/noorigin/.apv/events.jsonl"
backfilled_segment no >> "$SANDBOX/noorigin/.apv/events.jsonl"
run python3 "$PLUGIN/scripts/gate-composite.py" --repo-root "$SANDBOX/noorigin" --data-dir "$SANDBOX/noorigin/.apv" --planning-dir "$SANDBOX/noorigin"
check "composite FAILs"                 [ "$CODE" -eq 1 ]
check "draft-gate block named"          grep -q "implementation-on-draft.*PROV-H" <<<"$OUT"
check "fulcrum block named"             grep -q "fulcrum-without-decision.*PROV-OLD" <<<"$OUT"
check "schema block on commit_ref"      grep -q "BLOCK \[schema\]" <<<"$OUT"

# --- Case 3: the unfurl ---------------------------------------------------------
echo "== event-time derivation: backfilled 2025 close precedes captured 2026 revive"
run env APV_DATA_DIR="$PWD/.apv" python3 "$PLUGIN/scripts/cache-build.py"
check "cache builds"                    [ "$CODE" -eq 0 ]
state() { sqlite3 .apv/cache.sqlite "SELECT derived_state FROM entities WHERE entity_id='$1';"; }
origin_of() { sqlite3 .apv/cache.sqlite "SELECT origin FROM entities WHERE entity_id='$1';"; }
check "PROV-C is live (unfurled)"       [ "$(state PROV-C)" = "live" ]
check "PROV-C origin mixed"             [ "$(origin_of PROV-C)" = "mixed" ]
check "PROV-H origin backfilled"        [ "$(origin_of PROV-H)" = "backfilled" ]
check "PROV-A origin captured"          [ "$(origin_of PROV-A)" = "captured" ]
check "event_time anchored to 2025"     sh -c "sqlite3 .apv/cache.sqlite \"SELECT count(*) FROM events WHERE event_time='2025-03-10'\" | grep -q '^5$'"
check "anchor sha on the commit row"    sh -c "sqlite3 .apv/cache.sqlite \"SELECT anchor_commit_ref FROM commits WHERE event_time='2025-04-22'\" | grep -q '$SHA_B'"
run env APV_DATA_DIR="$PWD/.apv" python3 "$PLUGIN/scripts/projection-emit.py"
check "projection emits"                [ "$CODE" -eq 0 ]
check "projection carries origin"       sh -c "python3 -c \"import json; p=json.load(open('.apv/projection.json')); assert p['entities']['plan:PROV-H']['origin']=='backfilled'; assert p['entities']['plan:PROV-C']['origin']=='mixed'\""

# --- Case 4: repudiation ---------------------------------------------------------
echo "== repudiation: dropping the cohort reproduces the pre-run record"
mkdir -p "$SANDBOX/repudiated/.apv"
python3 - "$PWD/.apv/events.jsonl" "$SANDBOX/repudiated/.apv/events.jsonl" "$RUN" <<'PYEOF'
import json, sys
src, dst, run = sys.argv[1], sys.argv[2], sys.argv[3]
with open(src) as f, open(dst, "w") as out:
    for line in f:
        e = json.loads(line)
        if (e.get("attributes") or {}).get("backfill_run") == run:
            continue
        out.write(line)
PYEOF
check "cohort filter = pre-run log"     sh -c "cmp -s '$SANDBOX/repudiated/.apv/events.jsonl' '$SANDBOX/pre-run-events.jsonl'"
run env APV_DATA_DIR="$SANDBOX/repudiated/.apv" python3 "$PLUGIN/scripts/cache-build.py"
check "repudiated cache builds"         [ "$CODE" -eq 0 ]
check "PROV-H gone after repudiation"   sh -c "[ -z \"\$(sqlite3 '$SANDBOX/repudiated/.apv/cache.sqlite' \"SELECT entity_id FROM entities WHERE entity_id='PROV-H'\")\" ]"

echo
if [ "$FAIL" -eq 0 ]; then
  echo "provenance sandbox: ALL PASS"
else
  echo "provenance sandbox: FAILURES (see above)"
fi
exit "$FAIL"
