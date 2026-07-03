#!/usr/bin/env bash
# run-orientation-sandbox.sh — T3-session-orientation §4: the SessionStart
# detection script emits one line for tracked repos and silence for
# untracked ones, honouring the data-dir resolution chain; hooks.json
# parses and every script it references exists; skill frontmatter lints.
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

SANDBOX="$(mktemp -d /tmp/apv-orientation-sandbox.XXXXXX)" || exit 2
trap 'rm -rf "$SANDBOX"' EXIT
unset APV_DATA_DIR APV_GATE_CHECK APV_SKIP_GATE
ORIENT="$PLUGIN/hooks/session-orient.sh"

# --- Case 1: untracked repo -> silence, exit 0, fast ------------------------
echo "== untracked repo: silence"
mkdir -p "$SANDBOX/untracked"
run env CLAUDE_PROJECT_DIR="$SANDBOX/untracked" sh "$ORIENT"
check "exit 0"                          [ "$CODE" -eq 0 ]
check "no output"                       [ -z "$OUT" ]

# --- Case 2: tracked repo, default .apv/ ------------------------------------
echo "== tracked repo, default data dir"
mkdir -p "$SANDBOX/tracked-default/.apv"
: > "$SANDBOX/tracked-default/.apv/events.jsonl"
run env CLAUDE_PROJECT_DIR="$SANDBOX/tracked-default" sh "$ORIENT"
check "exit 0"                          [ "$CODE" -eq 0 ]
check "one line"                        [ "$(wc -l <<<"$OUT")" -eq 1 ]
check "names the log path"              grep -q ".apv/events.jsonl" <<<"$OUT"
check "points at capture"               grep -q "/apv-capture" <<<"$OUT"
check "points at merge"                 grep -q "/apv-merge" <<<"$OUT"

# --- Case 3: tracked repo, config-pinned data dir ----------------------------
echo "== tracked repo, config-pinned data dir"
mkdir -p "$SANDBOX/tracked-pinned/.custom-spine"
: > "$SANDBOX/tracked-pinned/.custom-spine/events.jsonl"
printf '[storage]\ndata_dir = ".custom-spine"\n' > "$SANDBOX/tracked-pinned/.apv-config.toml"
run env CLAUDE_PROJECT_DIR="$SANDBOX/tracked-pinned" sh "$ORIENT"
check "pinned dir detected"             grep -q ".custom-spine/events.jsonl" <<<"$OUT"

# --- Case 4: env var wins over config ----------------------------------------
echo "== tracked repo, APV_DATA_DIR override"
mkdir -p "$SANDBOX/tracked-pinned/.env-spine"
: > "$SANDBOX/tracked-pinned/.env-spine/events.jsonl"
run env CLAUDE_PROJECT_DIR="$SANDBOX/tracked-pinned" APV_DATA_DIR=".env-spine" sh "$ORIENT"
check "env override detected"           grep -q ".env-spine/events.jsonl" <<<"$OUT"

# --- Case 5: config present but no log -> still silence ----------------------
echo "== config without a log: silence (fingerprint is the log itself)"
mkdir -p "$SANDBOX/half-attached"
printf '[storage]\ndata_dir = ".apv"\n' > "$SANDBOX/half-attached/.apv-config.toml"
run env CLAUDE_PROJECT_DIR="$SANDBOX/half-attached" sh "$ORIENT"
check "exit 0"                          [ "$CODE" -eq 0 ]
check "no output"                       [ -z "$OUT" ]

# --- Case 6: plugin wiring smoke checks --------------------------------------
echo "== hooks.json + skill lint"
run python3 -c "
import json, sys
cfg = json.load(open('$PLUGIN/hooks/hooks.json'))
assert 'hooks' in cfg, 'plugin wrapper format requires a hooks key'
starts = cfg['hooks']['SessionStart']
cmds = [h['command'] for entry in starts for h in entry['hooks'] if h['type'] == 'command']
assert cmds, 'no SessionStart command hooks'
for c in cmds:
    assert 'CLAUDE_PLUGIN_ROOT' in c, 'hook command must resolve via CLAUDE_PLUGIN_ROOT: ' + c
    path = c.split('\"')[1].replace('\${CLAUDE_PLUGIN_ROOT}', '$PLUGIN')
    assert __import__('os').path.isfile(path), 'referenced script missing: ' + path
print('hooks.json ok')
"
check "hooks.json parses + scripts exist" [ "$CODE" -eq 0 ]
run python3 -c "
import sys
lines = open('$PLUGIN/skills/using-agent-plan-visualiser/SKILL.md').read().split('\n')
assert lines[0] == '---'
end = lines[1:].index('---') + 1
fm = '\n'.join(lines[1:end])
assert 'name: using-agent-plan-visualiser' in fm
assert 'description:' in fm
print('skill frontmatter ok')
"
check "skill frontmatter lints"          [ "$CODE" -eq 0 ]

echo
if [ "$FAIL" -eq 0 ]; then
  echo "orientation sandbox: ALL PASS"
else
  echo "orientation sandbox: FAILURES (see above)"
fi
exit "$FAIL"
