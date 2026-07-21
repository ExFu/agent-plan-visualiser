#!/usr/bin/env bash
# run-dist-sandbox.sh — T3-distribution §4.1/§4.3 + the M4 §6 cold-agent
# pass: from the bundle artefact ALONE (built, zipped, unzipped elsewhere —
# no repo checkout, no vendored toolchain), the plugin's structure is
# sound and the whole loop runs: init attaches a fresh repo, the guard
# rejects uncaptured commits, captured commits pass, the gate holds main
# (corrupt branch refused, clean branch lands, push gated), and the CI
# template's core step passes.
# Exits 0 when every case passes; 1 on the first failure.
set -uo pipefail
cd "$(dirname "$0")" || exit 2
WT_ROOT="$(cd ../../.. && pwd)"
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

check_absent_path() { # check_absent_path <desc> <path>
  local desc="$1" path="$2"
  if [ -e "$path" ]; then
    echo "  FAIL: $desc"
    FAIL=1
  else
    echo "  ok: $desc"
  fi
}

run() { # run <cmd...> -> sets OUT, CODE
  OUT="$("$@" 2>&1)"
  CODE=$?
}

SANDBOX="$(mktemp -d /tmp/apv-dist-sandbox.XXXXXX)" || exit 2
trap 'rm -rf "$SANDBOX"' EXIT
unset APV_DATA_DIR APV_GATE_CHECK APV_SKIP_GATE

# --- Case 1: the bundle builds ------------------------------------------------
echo "== build: bundle from the working tree"
run bash "$WT_ROOT/agent-plan-visualiser/scripts/build-bundle.sh" --out="$SANDBOX/dist"
check "build exits 0"                   [ "$CODE" -eq 0 ]
ZIP="$(ls "$SANDBOX"/dist/agent-plan-visualiser-*.zip 2>/dev/null | head -1)"
check "zip produced"                    [ -n "$ZIP" ] && [ -f "$ZIP" ]

# --- Case 2: unzip elsewhere = the downloaded artefact ------------------------
echo "== artefact: unzip is structurally a plugin"
mkdir -p "$SANDBOX/downloaded"
(cd "$SANDBOX/downloaded" && unzip -q "$ZIP")
MARKET="$SANDBOX/downloaded/apv-marketplace"
BUNDLE="$MARKET/agent-plan-visualiser"
check "marketplace manifest parses"     python3 -c "import json; json.load(open('$MARKET/.claude-plugin/marketplace.json'))"
check "marketplace source resolves"     python3 -c "
import json, os
m = json.load(open('$MARKET/.claude-plugin/marketplace.json'))
src = m['plugins'][0]['source']
assert os.path.isfile(os.path.join('$MARKET', src, '.claude-plugin/plugin.json')), src
"
check "plugin manifest parses"          python3 -c "import json; json.load(open('$BUNDLE/.claude-plugin/plugin.json'))"
check "capture skill shipped"           [ -f "$BUNDLE/skills/apv-capture/SKILL.md" ]
check "merge skill shipped"             [ -f "$BUNDLE/skills/apv-merge/SKILL.md" ]
check "orientation skill shipped"       [ -f "$BUNDLE/skills/using-agent-plan-visualiser/SKILL.md" ]
check "init command shipped"            [ -f "$BUNDLE/commands/apv-init.md" ]
check "hooks.json shipped"              [ -f "$BUNDLE/hooks/hooks.json" ]
check "session-orient shipped"          [ -f "$BUNDLE/hooks/session-orient.sh" ]
check "schemas shipped"                 [ -f "$BUNDLE/schemas/0.3.0/events.schema.json" ]
check "view shipped"                    [ -f "$BUNDLE/view/index.html" ]
check "cheatsheet shipped"              [ -f "$BUNDLE/cheatsheet/cheatsheet.md" ]
check "philosophies shipped"            [ -f "$BUNDLE/philosophies/tracker-as-agent-memory.md" ]
check_absent_path "tests excluded"      "$BUNDLE/tests"
check_absent_path "scripts/local excluded" "$BUNDLE/scripts/local"

# --- Case 3: the cold-agent loop, toolchain = the unzipped bundle -------------
echo "== cold agent: init -> guard -> capture -> gate -> merge -> push"
git init -q --bare "$SANDBOX/remote.git"
git init -q -b main "$SANDBOX/project"
cd "$SANDBOX/project" || exit 2
git config user.email cold@example.invalid
git config user.name "apv cold agent"
git remote add origin "$SANDBOX/remote.git"

run bash "$BUNDLE/scripts/apv-init.sh"
check "init from bundle exits 0"        [ "$CODE" -eq 0 ]
check "hooks carry the bundle home"     grep -q "APV_HOME=\"$BUNDLE\"" .git/hooks/pre-push

run env CLAUDE_PROJECT_DIR="$PWD" sh "$BUNDLE/hooks/session-orient.sh"
check "session orientation fires"       grep -q "tracked by agent-plan-visualiser" <<<"$OUT"

append_ev() { # append_ev <id4> <type> <entity_id> <summary>
  printf '{"event_id": "eeee%s-0000-4000-8000-00000000%s", "type": "%s", "actor": "al", "confidence": "explicit", "schema_version": "0.3.0", "entity_type": "plan", "entity_id": "%s", "attributes": {"summary": "%s"}}\n' \
    "$1" "$1" "$2" "$3" "$4" >> .apv/events.jsonl
}
append_seal() { # append_seal <id4> <message_first_line>
  printf '{"event_id": "eeee%s-0000-4000-8000-00000000%s", "type": "commit.recorded", "actor": "al", "confidence": "explicit", "schema_version": "0.3.0", "attributes": {"message_first_line": "%s", "author": "al", "date": "2026-07-03"}}\n' \
    "$1" "$1" "$2" >> .apv/events.jsonl
}
stamp() { date +%s > .apv/.last-capture; }

git add -A
run git commit -m "adopt tracking"
check "uncaptured commit refused"       [ "$CODE" -ne 0 ]
check "refusal points at skill source"  grep -q "skills/apv-capture/SKILL.md" <<<"$OUT"
append_ev   0001 entity.created  COLD-A "cold-agent plan, born draft"
append_ev   0002 entity.accepted COLD-A "operator acceptance"
append_seal 0003 "adopt tracking"
git add -A && stamp
run git commit -m "adopt tracking"
check "captured commit passes"          [ "$CODE" -eq 0 ]
run git push -q origin main
check "green main pushes"               [ "$CODE" -eq 0 ]
GREEN="$(git rev-parse refs/heads/main)"

git checkout -qb wip
append_ev   0004 entity.created    COLD-B "second plan, born draft"
append_ev   0005 entity.progressed COLD-B "implementation against a draft entity"
append_seal 0006 "cold: corrupt step"
git add -A && stamp && git commit -qm "cold: corrupt step"
git checkout -q main
run git merge wip
check "corrupt branch refused locally"  [ "$CODE" -ne 0 ]
check "main did not move"               [ "$(git rev-parse refs/heads/main)" = "$GREEN" ]
git reset -q --hard HEAD

git checkout -qb wip2 "$GREEN"
append_ev   0007 entity.progressed COLD-A "clean continuation on the accepted plan"
append_seal 0008 "cold: clean step"
git add -A && stamp && git commit -qm "cold: clean step"
git checkout -q main
run git merge wip2
check "clean branch lands"              [ "$CODE" -eq 0 ]
run git push -q origin main
check "clean push passes the gate"      [ "$CODE" -eq 0 ]

# --- Case 4: the CI template's core step --------------------------------------
echo "== CI template core step: gate-check --ref on the head sha"
run bash "$BUNDLE/scripts/gate-check.sh" --repo-root "$PWD" --ref "$(git rev-parse HEAD)"
check "green head passes (job green)"   [ "$CODE" -eq 0 ]
run bash "$BUNDLE/scripts/gate-check.sh" --repo-root "$PWD" --ref "$(git rev-parse wip)"
check "red ref fails (job red)"         [ "$CODE" -eq 1 ]

echo
if [ "$FAIL" -eq 0 ]; then
  echo "dist sandbox: ALL PASS"
else
  echo "dist sandbox: FAILURES (see above)"
fi
exit "$FAIL"
