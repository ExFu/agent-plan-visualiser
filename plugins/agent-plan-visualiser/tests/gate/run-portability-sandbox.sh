#!/usr/bin/env bash
# run-portability-sandbox.sh — T3-toolchain-portability §4.2: a repo with NO
# vendored toolchain, the toolchain at a simulated plugin root. Capture-guard,
# gate-check, pre-push and ref-update flows must all resolve and run — via
# the installer-baked APV_HOME, never via env overrides or repo-relative
# luck. Also exercises the `.apv/` default data dir (no config file at all),
# gate-check's git-toplevel repo-root default, and the installers' 0.5.12
# idempotency contract: same copy no-ops, an outdated apv hook (header
# fingerprint) refreshes in place, a foreign hook refuses untouched.
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

run() { # run <cmd...> -> sets OUT, CODE
  OUT="$("$@" 2>&1)"
  CODE=$?
}

# --- sandbox setup --------------------------------------------------------
SANDBOX="$(mktemp -d /tmp/apv-portability-sandbox.XXXXXX)" || exit 2
trap 'rm -rf "$SANDBOX"' EXIT
unset APV_DATA_DIR APV_GATE_CHECK APV_SKIP_GATE  # resolution must not lean on env

# The simulated plugin cache: the toolchain lives HERE, not in the repo.
PLUGIN_HOME="$SANDBOX/plugin-home"
cp -R "$WT_ROOT/plugins/agent-plan-visualiser" "$PLUGIN_HOME"

git init -q --bare "$SANDBOX/remote.git"
git init -q -b main "$SANDBOX/work"
cd "$SANDBOX/work" || exit 2
git config user.email sandbox@example.invalid
git config user.name "apv sandbox"
git remote add origin "$SANDBOX/remote.git"
mkdir -p .apv  # the M4-ruled default data dir; deliberately NO config file
# Local capture state is never tracked (the init flow writes this for
# adopters; the dogfood repo's .gitignore does the same for its data dir).
printf '.apv/.last-capture\n' > .gitignore

append_ev() { # append_ev <id4> <type> <entity_id> <summary>
  printf '{"event_id": "eeee%s-0000-4000-8000-00000000%s", "type": "%s", "actor": "al", "confidence": "explicit", "schema_version": "0.3.0", "entity_type": "plan", "entity_id": "%s", "attributes": {"summary": "%s"}}\n' \
    "$1" "$1" "$2" "$3" "$4" >> .apv/events.jsonl
}
append_seal() { # append_seal <id4> <message_first_line>
  printf '{"event_id": "eeee%s-0000-4000-8000-00000000%s", "type": "commit.recorded", "actor": "al", "confidence": "explicit", "schema_version": "0.3.0", "attributes": {"message_first_line": "%s", "author": "al", "date": "2026-06-10"}}\n' \
    "$1" "$1" "$2" >> .apv/events.jsonl
}
stamp() { date +%s > .apv/.last-capture; }

# --- Case 1: installers run from the plugin home, baking it in ------------
echo "== installers: plugin-home source, APV_HOME baked into gate hooks"
run bash "$PLUGIN_HOME/scripts/install-hook.sh"
check "capture-guard installed"         grep -q "installed" <<<"$OUT"
run bash "$PLUGIN_HOME/scripts/install-hook.sh"
check "capture-guard re-run is a no-op" grep -q "already installed" <<<"$OUT"
# 0.5.12 (aa1f109): an outdated apv capture-guard — header fingerprint, stale
# body — is OURS to refresh in place, same contract as the gate installer.
printf '%s\n' '#!/bin/sh' '# capture-guard.sh — agent-plan-visualiser pre-commit hook (obsolete vintage).' 'exit 0' > .git/hooks/pre-commit
run bash "$PLUGIN_HOME/scripts/install-hook.sh"
check "outdated capture-guard refreshes" [ "$CODE" -eq 0 ]
check "reports the capture-guard refresh" grep -q "refreshed" <<<"$OUT"
check "refreshed copy matches source"   cmp -s "$PLUGIN_HOME/hooks/capture-guard.sh" .git/hooks/pre-commit
# ...while a genuinely FOREIGN pre-commit (no apv fingerprint) still refuses.
mv .git/hooks/pre-commit "$SANDBOX/pre-commit.stash"
printf '%s\n' '#!/bin/sh' '# a foreign pre-commit, none of our business' 'exit 0' > .git/hooks/pre-commit
run bash "$PLUGIN_HOME/scripts/install-hook.sh"
check "foreign pre-commit refuses"      [ "$CODE" -eq 1 ]
check "capture-guard names the refusal" grep -q "refusing to overwrite" <<<"$OUT"
check "foreign pre-commit untouched"    grep -q "none of our business" .git/hooks/pre-commit
mv -f "$SANDBOX/pre-commit.stash" .git/hooks/pre-commit
run bash "$PLUGIN_HOME/scripts/install-gate.sh" --home="$PLUGIN_HOME"
check "pre-push installed"              [ "$CODE" -eq 0 ]
run bash "$PLUGIN_HOME/scripts/install-gate.sh" --at=ref-update --home="$PLUGIN_HOME"
check "ref-update installed"            [ "$CODE" -eq 0 ]
check "pre-push carries baked home"     grep -q "APV_HOME=\"$PLUGIN_HOME\"" .git/hooks/pre-push
check "ref-update carries baked home"   grep -q "APV_HOME=\"$PLUGIN_HOME\"" .git/hooks/reference-transaction
run bash "$PLUGIN_HOME/scripts/install-gate.sh" --home="$PLUGIN_HOME"
check "same-home re-run is a no-op"     grep -q "already installed" <<<"$OUT"
# 0.5.12 (aa1f109): an apv gate hook baking a stale home is OURS to refresh —
# a different-home re-run replaces the copy in place instead of refusing.
run bash "$PLUGIN_HOME/scripts/install-gate.sh" --home="$SANDBOX"
check "different-home re-run refreshes" [ "$CODE" -eq 0 ]
check "reports the gate refresh"        grep -q "refreshed" <<<"$OUT"
check "refresh bakes the NEW home"      grep -q "APV_HOME=\"$SANDBOX\"" .git/hooks/pre-push
run bash "$PLUGIN_HOME/scripts/install-gate.sh" --home="$PLUGIN_HOME"
check "re-bake restores the plugin home" grep -q "APV_HOME=\"$PLUGIN_HOME\"" .git/hooks/pre-push
# Never-clobber still protects FOREIGN hooks: no apv fingerprint -> refuse.
mv .git/hooks/pre-push "$SANDBOX/pre-push.stash"
printf '%s\n' '#!/bin/sh' '# a foreign pre-push, none of our business' 'exit 0' > .git/hooks/pre-push
run bash "$PLUGIN_HOME/scripts/install-gate.sh" --home="$PLUGIN_HOME"
check "foreign pre-push refuses"        [ "$CODE" -eq 1 ]
check "gate names the refusal"          grep -q "refusing to overwrite" <<<"$OUT"
check "foreign pre-push untouched"      grep -q "none of our business" .git/hooks/pre-push
mv -f "$SANDBOX/pre-push.stash" .git/hooks/pre-push

# --- Case 2: the guard finds .apv/ by default (no config, no env) ---------
echo "== capture-guard: default .apv data dir, no config anywhere"
append_ev   0001 entity.created  PBX-A "portability plan A, born draft"
append_ev   0002 entity.accepted PBX-A "operator acceptance"
append_seal 0003 "pbx: adopt tracking"
git add -A
run git commit -m "pbx: adopt tracking"
check "uncaptured commit refused"       [ "$CODE" -ne 0 ]
check "guard names the missing capture" grep -qi "capture" <<<"$OUT"
stamp
run git commit -m "pbx: adopt tracking"
check "captured commit passes"          [ "$CODE" -eq 0 ]

# --- Case 3: gate-check runs from the plugin home -------------------------
echo "== gate-check: plugin-home invocation, .apv default, toplevel default"
run bash "$PLUGIN_HOME/scripts/gate-check.sh" --repo-root "$PWD"
check "explicit repo-root passes"       [ "$CODE" -eq 0 ]
check "PASS verdict"                    grep -q '^gate-check: PASS' <<<"$OUT"
run bash "$PLUGIN_HOME/scripts/gate-check.sh"
check "git-toplevel default passes"     [ "$CODE" -eq 0 ]

# --- Case 4: ref-update resolves via the baked home -----------------------
echo "== ref-update: corrupt branch refused with no vendored toolchain"
git checkout -qb wip
append_ev   0004 entity.created    PBX-B "portability plan B, born draft"
append_ev   0005 entity.progressed PBX-B "implementation against a draft entity"
append_seal 0006 "pbx: corrupt step"
git add -A && stamp && git commit -qm "pbx: corrupt step"
run git checkout main
check "checkout main succeeds"          [ "$CODE" -eq 0 ]
GREEN="$(git rev-parse refs/heads/main)"
run git merge wip
check "local ff merge refused"          [ "$CODE" -ne 0 ]
check "composite names the defect"      grep -q '^BLOCK \[implementation-on-draft\].*PBX-B' <<<"$OUT"
check "main did not move"               [ "$(git rev-parse refs/heads/main)" = "$GREEN" ]
git reset -q --hard HEAD   # a refused ff may leave the worktree updated

# --- Case 5: pre-push resolves via the baked home --------------------------
echo "== pre-push: red main refused at the remote boundary"
run git push -q origin main
check "green main pushes"               [ "$CODE" -eq 0 ]
run env APV_SKIP_GATE=1 git merge wip
check "hatch lets the red merge by"     [ "$CODE" -eq 0 ]
run git push origin main
check "red push refused"                [ "$CODE" -ne 0 ]
check "hook names the refusal"          grep -q 'push of refs/heads/main refused' <<<"$OUT"
check "remote main still green"         [ "$(git -C "$SANDBOX/remote.git" rev-parse refs/heads/main)" = "$GREEN" ]
run git reset --hard "$GREEN"
check "reset back to green allowed"     [ "$CODE" -eq 0 ]

# --- Case 6: clean work lands through the baked gates ---------------------
echo "== clean branch ff-merges and pushes through baked-home gates"
git checkout -qb wip2 "$GREEN"
append_ev   0007 entity.extended PBX-A "clean continuation"
append_seal 0008 "pbx: clean step"
git add -A && stamp && git commit -qm "pbx: clean step"
git checkout -q main
run git merge wip2
check "clean ff merge exits 0"          [ "$CODE" -eq 0 ]
run git push -q origin main
check "clean push exits 0"              [ "$CODE" -eq 0 ]

echo
if [ "$FAIL" -eq 0 ]; then
  echo "portability sandbox: ALL PASS"
else
  echo "portability sandbox: FAILURES (see above)"
fi
exit "$FAIL"
