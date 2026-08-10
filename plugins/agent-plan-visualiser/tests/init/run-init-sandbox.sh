#!/usr/bin/env bash
# run-init-sandbox.sh — T3-project-init-flow §4: the init command attaches
# fresh and existing repos, idempotently, from a simulated plugin home.
#
#   1. Fresh repo: init -> data dir + empty log + config + three hooks live
#      (gate hooks carry the baked home); first uncaptured commit rejected
#      by the guard; captured commit passes; gate green on the empty and
#      first-block log.
#   2. Existing repo with a foreign pre-commit: init refuses that hook
#      loudly (exit 1), installs the others, seeds data/config.
#   3. Re-run idempotency: second run all-ok, exit 0, log untouched;
#      after deleting one hook, re-run restores only it.
#   4. --at=manual: no git hooks installed, exit 0.
#   5. CLAUDE.md offer + heal: never written unasked; --accept-claude-md
#      appends once with BOTH markers; a re-run on a current block writes
#      nothing (asserted by content hash); a stale body between intact
#      markers is refreshed with no flag; a legacy opening-marker-only block
#      is migrated only under --accept-claude-md, preserving an adjacent
#      sibling plugin's block and the user's prose; ambiguity is refused
#      with nothing written.
#
# Exits 0 when every case passes; 1 on the first failure.
set -uo pipefail
cd "$(dirname "$0")" || exit 2
WT_ROOT="$(cd ../../../.. && pwd)"
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

check_absent() { # check_absent <desc> <grep-pattern> — pattern must NOT match $OUT
  local desc="$1" pattern="$2"
  if grep -q "$pattern" <<<"$OUT"; then
    echo "  FAIL: $desc"
    FAIL=1
  else
    echo "  ok: $desc"
  fi
}

check_file_absent() { # check_file_absent <desc> <grep-pattern> <file>
  local desc="$1" pattern="$2" file="$3"
  if grep -q "$pattern" "$file" 2>/dev/null; then
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

SANDBOX="$(mktemp -d /tmp/apv-init-sandbox.XXXXXX)" || exit 2
trap 'rm -rf "$SANDBOX"' EXIT
unset APV_DATA_DIR APV_GATE_CHECK APV_SKIP_GATE

# The simulated plugin cache: the toolchain lives HERE, not in any repo.
PLUGIN_HOME="$SANDBOX/plugin-home"
cp -R "$WT_ROOT/plugins/agent-plan-visualiser" "$PLUGIN_HOME"
INIT="$PLUGIN_HOME/scripts/apv-init.sh"

new_repo() { # new_repo <name> -> cds into it
  git init -q -b main "$SANDBOX/$1"
  cd "$SANDBOX/$1" || exit 2
  git config user.email sandbox@example.invalid
  git config user.name "apv sandbox"
}

append_ev() { # append_ev <id4> <type> <entity_id> <summary>
  printf '{"event_id": "eeee%s-0000-4000-8000-00000000%s", "type": "%s", "actor": "al", "confidence": "explicit", "schema_version": "0.3.0", "entity_type": "plan", "entity_id": "%s", "attributes": {"summary": "%s"}}\n' \
    "$1" "$1" "$2" "$3" "$4" >> .apv/events.jsonl
}
append_seal() { # append_seal <id4> <message_first_line>
  printf '{"event_id": "eeee%s-0000-4000-8000-00000000%s", "type": "commit.recorded", "actor": "al", "confidence": "explicit", "schema_version": "0.3.0", "attributes": {"message_first_line": "%s", "author": "al", "date": "2026-06-10"}}\n' \
    "$1" "$1" "$2" >> .apv/events.jsonl
}
stamp() { date +%s > .apv/.last-capture; }

# --- Case 1: fresh repo attaches end-to-end --------------------------------
echo "== fresh repo: init seeds, hooks live, guard + gate function"
new_repo fresh
run bash "$INIT"
check "init exits 0"                    [ "$CODE" -eq 0 ]
check "data dir seeded"                 [ -f .apv/events.jsonl ]
check "log starts empty"                [ ! -s .apv/events.jsonl ]
check "schema marker written"           grep -q "0.3.0" .apv/schema-version.txt
check "config written"                  grep -q 'data_dir = ".apv"' .apv-config.toml
check "stamp gitignored"                grep -qxF ".apv/.last-capture" .gitignore
check "capture-guard installed"         [ -x .git/hooks/pre-commit ]
check "pre-push gate installed"         [ -x .git/hooks/pre-push ]
check "ref-update gate installed"       [ -x .git/hooks/reference-transaction ]
check "pre-push carries baked home"     grep -q "APV_HOME=\"$PLUGIN_HOME\"" .git/hooks/pre-push
check "ref-update carries baked home"   grep -q "APV_HOME=\"$PLUGIN_HOME\"" .git/hooks/reference-transaction
check "offer printed, not written"      grep -q "offer: a CLAUDE.md" <<<"$OUT"
check "CLAUDE.md not created unasked"   [ ! -f CLAUDE.md ]

run bash "$PLUGIN_HOME/scripts/gate-check.sh" --repo-root "$PWD"
check "gate green on empty log"         [ "$CODE" -eq 0 ]

git add -A
run git commit -m "adopt tracking"
check "uncaptured commit refused"       [ "$CODE" -ne 0 ]
check "guard names the missing capture" grep -qi "capture" <<<"$OUT"
check "refusal points at skill source"  grep -q "skills/apv-capture/SKILL.md" <<<"$OUT"
append_ev   0001 entity.created  INIT-A "fresh-repo plan, born draft"
append_seal 0002 "adopt tracking"
git add -A && stamp
run git commit -m "adopt tracking"
check "captured commit passes"          [ "$CODE" -eq 0 ]
run bash "$PLUGIN_HOME/scripts/gate-check.sh" --repo-root "$PWD"
check "gate green on first-block log"   [ "$CODE" -eq 0 ]

# --- Case 2: existing repo with a foreign pre-commit ------------------------
echo "== existing repo: foreign pre-commit refused loudly, rest installs"
new_repo existing
printf 'hello\n' > file.txt
git add -A && git commit -qm "pre-adoption history"
printf '#!/bin/sh\nexit 0\n' > .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
run bash "$INIT"
check "init exits 1 on the refusal"     [ "$CODE" -eq 1 ]
check "refusal is loud and named"       grep -q "REFUSED.*pre-commit" <<<"$OUT"
check "installer voice shown"           grep -q "refusing to overwrite" <<<"$OUT"
check "gates still installed"           [ -x .git/hooks/pre-push ]
check "data dir still seeded"           [ -f .apv/events.jsonl ]
check "foreign hook untouched"          grep -q "exit 0" .git/hooks/pre-commit

# --- Case 3: re-run idempotency ---------------------------------------------
echo "== re-run: audit mode reports ok, repairs only the gap"
cd "$SANDBOX/fresh" || exit 2
LOG_BEFORE="$(cat .apv/events.jsonl)"
run bash "$INIT"
check "re-run exits 0"                  [ "$CODE" -eq 0 ]
check_absent "no component re-created"  "^  created"
check "log untouched by re-run"         [ "$(cat .apv/events.jsonl)" = "$LOG_BEFORE" ]
GUARD_SUM="$(cksum .git/hooks/pre-commit)"
rm .git/hooks/pre-push
run bash "$INIT"
check "repair run exits 0"              [ "$CODE" -eq 0 ]
check "deleted hook restored"           [ -x .git/hooks/pre-push ]
check "other hooks untouched"           [ "$(cksum .git/hooks/pre-commit)" = "$GUARD_SUM" ]

# --- Case 4: --at=manual ------------------------------------------------------
echo "== --at=manual: no git hooks, on-demand contract printed"
new_repo manual
run bash "$INIT" --at=manual
check "manual init exits 0"             [ "$CODE" -eq 0 ]
check "no pre-commit hook"              [ ! -e .git/hooks/pre-commit ]
check "no pre-push hook"                [ ! -e .git/hooks/pre-push ]
check "no ref-update hook"              [ ! -e .git/hooks/reference-transaction ]
check "on-demand contract printed"      grep -q "gate-check.sh" <<<"$OUT"

# --- Case 5: CLAUDE.md offer + heal -------------------------------------------
# T3-claude-md-block-healing §5. The block is the ONLY live surface APV writes
# that it could not subsequently correct: init treated "marker present" as
# success, so every attached repo carried a frozen snapshot of whatever the
# toolchain said the day it attached. These cases assert on CONTENT, not on
# marker count — the old `grep -c == 1` assertion passed happily while the
# block rotted, and naming the defect ("second accept is a no-op") as the
# expected result is what carried it through an acceptance ceremony.
echo "== CLAUDE.md: appended only on acceptance, then kept current"
cd "$SANDBOX/fresh" || exit 2
run bash "$INIT" --accept-claude-md
check "accepted run exits 0"            [ "$CODE" -eq 0 ]
check "block appended"                  grep -qF "<!-- apv:orientation -->" CLAUDE.md
check "closing marker emitted"          grep -qF "<!-- /apv:orientation -->" CLAUDE.md
check "glob survives a rename (Q5)"     grep -qF 'cache/*/*agent-plan-visualiser/*/' CLAUDE.md
check_file_absent "no pre-rename glob"  'cache/\*/agent-plan-visualiser/\*/' CLAUDE.md

# §5.2 — a re-run on a current block must perform ZERO writes. Assert on the
# file's content hash, not on marker count.
BEFORE="$(shasum CLAUDE.md | cut -d' ' -f1)"
run bash "$INIT" --accept-claude-md
check "re-run exits 0"                  [ "$CODE" -eq 0 ]
check "re-run reports current"          grep -q "orientation block current" <<<"$OUT"
check "re-run wrote nothing"            [ "$(shasum CLAUDE.md | cut -d' ' -f1)" = "$BEFORE" ]
check "markers still single"            [ "$(grep -cF '<!-- apv:orientation -->' CLAUDE.md)" -eq 1 ]

# §5.5 — stale body between intact markers is refreshed, WITHOUT the flag (Q1).
perl -0pi -e 's/^## agent-plan-visualiser \(APV\) tracking$/## STALE HEADING/m' CLAUDE.md
run bash "$INIT"
check "stale refresh needs no flag"     grep -q "orientation block refreshed" <<<"$OUT"
check "canonical heading restored"      grep -qF '## agent-plan-visualiser (APV) tracking' CLAUDE.md
check_file_absent "stale text gone"     'STALE HEADING' CLAUDE.md
check "still exactly one open marker"   [ "$(grep -cF '<!-- apv:orientation -->' CLAUDE.md)" -eq 1 ]
check "still exactly one end marker"    [ "$(grep -cF '<!-- /apv:orientation -->' CLAUDE.md)" -eq 1 ]

# §5.3/§5.4/§5.6 — the real-world legacy layout: an opening-marker-only block
# carrying the dead pre-rename glob, immediately followed by a FULLY DELIMITED
# sibling plugin's block, with user prose on both sides. This is the exact
# shape of all three attached repos found in the field (this repo, the
# exfu-agent-planning-and-delegating consumer, and agent-library) — so
# end-detection must stop at the sibling opening comment, not swallow it.
new_repo legacy
cat > CLAUDE.md <<'LEGACY'
# My project

Prose above the block, which must survive byte-for-byte.

<!-- apv:orientation -->
## agent-plan-visualiser (APV) tracking

This repository is tracked by agent-plan-visualiser. Stale 0.6-era text.
Read the newest `~/.claude/plugins/cache/*/agent-plan-visualiser/*/skills/apv-capture/SKILL.md`.

<!-- exfu-agent-planning-and-delegating:orientation -->
## sibling plugin block

Owned by another plugin. Must not be touched.
<!-- /exfu-agent-planning-and-delegating:orientation -->

## User's own heading

Prose below, also byte-for-byte.
LEGACY
SIBLING_BEFORE="$(sed -n '/exfu-agent-planning-and-delegating:orientation/,/\/exfu-agent-planning-and-delegating:orientation/p' CLAUDE.md | shasum)"

# §5.7-adjacent — the migration is gated: it deletes lines whose extent was
# inferred, so a flagless run must report and write NOTHING (Q1 exception).
LEGACY_BEFORE="$(shasum CLAUDE.md | cut -d' ' -f1)"
run bash "$INIT"
check "legacy exits 0 without flag"     [ "$CODE" -eq 0 ]
check "legacy migration is offered"     grep -q "legacy block found" <<<"$OUT"
check "flagless legacy wrote nothing"   [ "$(shasum CLAUDE.md | cut -d' ' -f1)" = "$LEGACY_BEFORE" ]
check "offer shows the region"          grep -q "would be replaced" <<<"$OUT"

run bash "$INIT" --accept-claude-md
check "migration exits 0"               [ "$CODE" -eq 0 ]
check "migration reported"              grep -q "migrated to delimited form" <<<"$OUT"
check "one open marker"                 [ "$(grep -cF '<!-- apv:orientation -->' CLAUDE.md)" -eq 1 ]
check "one end marker"                  [ "$(grep -cF '<!-- /apv:orientation -->' CLAUDE.md)" -eq 1 ]
check_file_absent "pre-rename glob gone" 'cache/\*/agent-plan-visualiser/\*/' CLAUDE.md
check "survivable glob stamped"         grep -qF 'cache/*/*agent-plan-visualiser/*/' CLAUDE.md
check_file_absent "stale 0.6 text gone" '0.6-era' CLAUDE.md
check "sibling block untouched"         [ "$(sed -n '/exfu-agent-planning-and-delegating:orientation/,/\/exfu-agent-planning-and-delegating:orientation/p' CLAUDE.md | shasum)" = "$SIBLING_BEFORE" ]
check "prose above preserved"           grep -qF "Prose above the block, which must survive byte-for-byte." CLAUDE.md
check "prose below preserved"           grep -qF "Prose below, also byte-for-byte." CLAUDE.md
check "user heading preserved"          grep -qF "## User's own heading" CLAUDE.md

# Second migration run is now an ordinary current-block no-op.
MIGRATED="$(shasum CLAUDE.md | cut -d' ' -f1)"
run bash "$INIT"
check "post-migration run is current"   grep -q "orientation block current" <<<"$OUT"
check "post-migration wrote nothing"    [ "$(shasum CLAUDE.md | cut -d' ' -f1)" = "$MIGRATED" ]

# §5.7 — ambiguity is refused, loudly, with nothing written.
new_repo ambiguous
cat > CLAUDE.md <<'AMBIG'
<!-- apv:orientation -->
## agent-plan-visualiser (APV) tracking
first block
<!-- apv:orientation -->
## agent-plan-visualiser (APV) tracking
second block
AMBIG
AMBIG_BEFORE="$(shasum CLAUDE.md | cut -d' ' -f1)"
run bash "$INIT" --accept-claude-md
check "duplicate markers refused"       [ "$CODE" -ne 0 ]
check "refusal names the cause"         grep -q "cannot determine the block's extent" <<<"$OUT"
check "refusal wrote nothing"           [ "$(shasum CLAUDE.md | cut -d' ' -f1)" = "$AMBIG_BEFORE" ]

# An opening marker followed by text we do not recognise is also refused —
# we will not infer an extent for a block that is not ours.
new_repo unrecognised
printf '<!-- apv:orientation -->\n## Something else entirely\nwho knows\n' > CLAUDE.md
UNREC_BEFORE="$(shasum CLAUDE.md | cut -d' ' -f1)"
run bash "$INIT" --accept-claude-md
check "foreign block refused"           [ "$CODE" -ne 0 ]
check "foreign refusal wrote nothing"   [ "$(shasum CLAUDE.md | cut -d' ' -f1)" = "$UNREC_BEFORE" ]

# --- Case 6: plugin-cache install -> enablement persistence -------------------
echo "== cache install: enablement written to .claude/settings.json, tracked-ness checked"
CACHE_HOME="$SANDBOX/cc/plugins/cache/exfu/exfu-agent-plan-visualiser/9.9.9"
mkdir -p "$(dirname "$CACHE_HOME")"
cp -R "$WT_ROOT/plugins/agent-plan-visualiser" "$CACHE_HOME"
new_repo cachey
run env CLAUDE_CONFIG_DIR="$SANDBOX/cc" bash "$CACHE_HOME/scripts/apv-init.sh"
check "cache init exits 0"              [ "$CODE" -eq 0 ]
check "enablement key written"          grep -q '"exfu-agent-plan-visualiser@exfu": true' .claude/settings.json
check "untracked warned loudly"         grep -q "UNTRACKED" <<<"$OUT"
check "next-steps says commit it"       grep -q "COMMIT .claude/settings.json" <<<"$OUT"
check "gate hooks NOT baked to cache"   grep -q 'APV_HOME=""' .git/hooks/pre-push
git add .claude/settings.json
run env CLAUDE_CONFIG_DIR="$SANDBOX/cc" bash "$CACHE_HOME/scripts/apv-init.sh"
check "re-run exits 0"                  [ "$CODE" -eq 0 ]
check "tracked reported once staged"    grep -q "worktree checkouts and clones will load" <<<"$OUT"
check_absent "no UNTRACKED once staged" "UNTRACKED"

# End-to-end: a commit on main moves the ref, the reference-transaction
# gate fires, and — with no baked home — resolves gate-check by newest-cache
# discovery under CLAUDE_CONFIG_DIR. Green log, so the commit must land.
append_ev   00c1 entity.created  CACHE-A "cache-install plan, born draft"
append_ev   00c2 entity.accepted CACHE-A "operator acceptance"
append_seal 00c3 "cache: adopt tracking"
git add -A && stamp
run env CLAUDE_CONFIG_DIR="$SANDBOX/cc" git commit -m "cache: adopt tracking"
check "commit lands via cache-discovered gate" [ "$CODE" -eq 0 ]

echo "== cache install, user scope: nothing to persist"
CC2="$SANDBOX/cc2"
mkdir -p "$CC2/plugins"
printf '{"version":2,"plugins":{"exfu-agent-plan-visualiser@exfu":[{"scope":"user"}]}}\n' > "$CC2/plugins/installed_plugins.json"
new_repo userscoped
run env CLAUDE_CONFIG_DIR="$CC2" bash "$CACHE_HOME/scripts/apv-init.sh"
check "user-scope init exits 0"         [ "$CODE" -eq 0 ]
check "user-scope reported"             grep -q "user-scope" <<<"$OUT"
check "no settings file written"        [ ! -e .claude/settings.json ]

echo "== non-cache home: enablement component silent"
cd "$SANDBOX/fresh" || exit 2
run bash "$INIT"
check_absent "no enablement chatter"    "enabledPlugins"

# --- Case 7: outdated apv hooks refresh, foreign hooks still refuse -----------
echo "== hook refresh: our own outdated hooks are replaced, not refused"
cd "$SANDBOX/fresh" || exit 2
printf '# vintage-marker: simulated older apv release\n' >> .git/hooks/pre-commit
printf '# vintage-marker: simulated older apv release\n' >> .git/hooks/pre-push
run bash "$INIT"
check "refresh run exits 0"             [ "$CODE" -eq 0 ]
check "hooks reported updated"          grep -q "updated.*outdated apv hook refreshed" <<<"$OUT"
check_absent "no refusal on our hooks"  "REFUSED"
check "pre-commit vintage replaced"     bash -c '! grep -q "vintage-marker" .git/hooks/pre-commit'
check "pre-push vintage replaced"       bash -c '! grep -q "vintage-marker" .git/hooks/pre-push'
check "pre-push home re-baked"          grep -q "APV_HOME=\"$PLUGIN_HOME\"" .git/hooks/pre-push

echo
if [ "$FAIL" -eq 0 ]; then
  echo "init sandbox: ALL PASS"
else
  echo "init sandbox: FAILURES (see above)"
fi
exit "$FAIL"
