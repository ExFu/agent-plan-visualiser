#!/usr/bin/env bash
# run-gatecheck-sandbox.sh — sandbox verification for gate-check.sh,
# gate-prepush.sh and install-gate.sh (T3-gate-core §4, all three items).
# Mirrors the capture-guard sandbox pattern: throwaway repo under /tmp plus
# a bare remote, pushed through the installed hook. Exits 0 when every case
# passes; 1 on the first failure.
set -uo pipefail
cd "$(dirname "$0")" || exit 2
WT_ROOT="$(cd ../../.. && pwd)"
GATE_CHECK="$WT_ROOT/agent-plan-tracker/scripts/gate-check.sh"
INSTALL="$WT_ROOT/agent-plan-tracker/scripts/install-gate.sh"
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
SANDBOX="$(mktemp -d /tmp/apt-gate-sandbox.XXXXXX)" || exit 2
trap 'rm -rf "$SANDBOX"' EXIT
unset APT_DATA_DIR  # a leaked override would point the sandbox at real data
# The sandbox repo has no toolchain of its own — the hook resolves the
# check through the env override (its first resolution step).
export APT_GATE_CHECK="$GATE_CHECK"

git init -q --bare "$SANDBOX/remote.git"
git init -q -b main "$SANDBOX/work"
cd "$SANDBOX/work" || exit 2
git config user.email sandbox@example.invalid
git config user.name "apt sandbox"
git remote add origin "$SANDBOX/remote.git"
mkdir -p .agent-plan-tracker

append_ev() { # append_ev <id4> <type> <entity_id> <summary>
  printf '{"event_id": "cccc%s-0000-4000-8000-00000000%s", "type": "%s", "actor": "al", "confidence": "explicit", "schema_version": "0.3.0", "entity_type": "plan", "entity_id": "%s", "attributes": {"summary": "%s"}}\n' \
    "$1" "$1" "$2" "$3" "$4" >> .agent-plan-tracker/events.jsonl
}
append_seal() { # append_seal <id4> <message_first_line>
  printf '{"event_id": "cccc%s-0000-4000-8000-00000000%s", "type": "commit.recorded", "actor": "al", "confidence": "explicit", "schema_version": "0.3.0", "attributes": {"message_first_line": "%s", "author": "al", "date": "2026-06-10"}}\n' \
    "$1" "$1" "$2" >> .agent-plan-tracker/events.jsonl
}

# --- Case 1: installer contract (§4.3) ------------------------------------
echo "== installer: manual mode installs nothing"
run bash "$INSTALL" --at=manual
check "exit 0"                          [ "$CODE" -eq 0 ]
check "prints invocation guidance"      grep -q "run the gate with" <<<"$OUT"
check "no pre-push hook created"        [ ! -e .git/hooks/pre-push ]

echo "== installer: refuses to clobber a foreign pre-push"
echo '#!/bin/sh' > .git/hooks/pre-push
run bash "$INSTALL"
check "exit 1"                          [ "$CODE" -eq 1 ]
check "names the conflict"              grep -q "refusing to overwrite" <<<"$OUT"
rm .git/hooks/pre-push

echo "== installer: fresh install"
run bash "$INSTALL"
check "exit 0"                          [ "$CODE" -eq 0 ]
check "reports install"                 grep -q "installed gate-prepush" <<<"$OUT"
check "hook present and executable"     [ -x .git/hooks/pre-push ]

echo "== installer: identical re-run is a no-op"
run bash "$INSTALL"
check "exit 0"                          [ "$CODE" -eq 0 ]
check "reports already installed"       grep -q "already installed" <<<"$OUT"

# --- Case 2: pre-adoption history has nothing to gate ---------------------
echo "== ref mode: commit predating the log passes with a notice"
echo "hello" > README.md
git add README.md && git commit -qm "sandbox: init readme"
run bash "$GATE_CHECK" --repo-root "$PWD" --ref HEAD
check "exit 0"                          [ "$CODE" -eq 0 ]
check "notes pre-adoption history"      grep -q "nothing to gate (pre-adoption history)" <<<"$OUT"

# --- Case 3: clean adoption commit pushes through the hook (§4.2) ---------
echo "== clean log: push of main succeeds"
append_ev   0001 entity.created  SBX-A "sandbox plan A, born draft"
append_ev   0002 entity.accepted SBX-A "operator acceptance"
append_seal 0003 "sandbox: adopt tracker"
git add -A && git commit -qm "sandbox: adopt tracker"
run git push -q origin main
check "push exits 0"                    [ "$CODE" -eq 0 ]
check "remote main advanced"            [ "$(git -C "$SANDBOX/remote.git" rev-parse refs/heads/main 2>/dev/null)" = "$(git rev-parse HEAD)" ]

echo "== ref mode direct: clean state passes"
run bash "$GATE_CHECK" --repo-root "$PWD" --ref HEAD
check "exit 0"                          [ "$CODE" -eq 0 ]
check "PASS verdict"                    grep -q '^gate-check: PASS' <<<"$OUT"

# --- Case 4: mid-flow tolerance in filesystem mode ------------------------
# Capture-before-commit means the trailing block's seal names a commit that
# does not exist yet: NOTICE, never BLOCK. Once committed, silence.
echo "== filesystem mode: uncommitted capture tail is mid-flow, not a block"
append_ev   0004 entity.extended SBX-A "second step, captured before its commit"
append_seal 0005 "sandbox: second step"
run bash "$GATE_CHECK" --repo-root "$PWD"
check "exit 0"                          [ "$CODE" -eq 0 ]
check "mid-flow NOTICE emitted"         grep -q '^NOTICE \[seal-commit\].*sandbox: second step' <<<"$OUT"
check_absent "no seal BLOCK"            '^BLOCK \[seal-commit\]'

git add -A && git commit -qm "sandbox: second step"
run bash "$GATE_CHECK" --repo-root "$PWD"
check "exit 0 once committed"           [ "$CODE" -eq 0 ]
check_absent "notice gone"              '^NOTICE \[seal-commit\]'

# --- Case 5: corrupted log is refused at the boundary (§4.2) --------------
echo "== corrupt log: push of main refused"
append_ev   0006 entity.created    SBX-B "sandbox plan B, born draft"
append_ev   0007 entity.progressed SBX-B "implementation against a draft entity"
append_seal 0008 "sandbox: corrupt step"
git add -A && git commit -qm "sandbox: corrupt step"
BEFORE="$(git -C "$SANDBOX/remote.git" rev-parse refs/heads/main 2>/dev/null)"
run git push origin main
check "push exits nonzero"              [ "$CODE" -ne 0 ]
check "composite names the defect"      grep -q '^BLOCK \[implementation-on-draft\].*SBX-B' <<<"$OUT"
check "hook names the refusal"          grep -q 'push of refs/heads/main refused' <<<"$OUT"
check "remote main did not move"        [ "$(git -C "$SANDBOX/remote.git" rev-parse refs/heads/main 2>/dev/null)" = "$BEFORE" ]

# --- Case 6: branch pushes are work-in-flight, never gated (§6 Q1) --------
echo "== same corrupt state pushes freely to a branch"
run git push -q origin main:wip
check "branch push exits 0"             [ "$CODE" -eq 0 ]

# --- Case 7: --no-verify is the sanctioned escape hatch -------------------
echo "== --no-verify bypasses the gate"
run git push -q --no-verify origin main
check "bypass push exits 0"             [ "$CODE" -eq 0 ]

# --- Case 8: orphaned seal (squash/reword simulation) ---------------------
# The block is sealed for one message; the commit is made with another.
# The committed seal then matches no reachable commit subject.
echo "== seal-commit: reworded commit orphans its seal"
append_ev   0009 entity.extended SBX-A "step whose seal will be orphaned"
append_seal 000a "sandbox: never happened"
git add -A && git commit -qm "sandbox: reworded"
run bash "$GATE_CHECK" --repo-root "$PWD" --ref HEAD
check "exit 1"                          [ "$CODE" -eq 1 ]
check "orphaned seal named"             grep -q "^BLOCK \[seal-commit\].*sandbox: never happened" <<<"$OUT"
check "FAIL verdict"                    grep -q '^gate-check: FAIL' <<<"$OUT"

# --- Case 8b: pre-epoch seals are advisory, not blocking -------------------
# The exact-match discipline is 0.3.0 capture-skill law; a 0.2.0 seal with
# loose wording is judged by its own regime (offending-event epoch keying,
# mirroring the composite's resurrection check).
echo "== seal-commit: pre-0.3.0 loose seal notices, never blocks"
printf '{"event_id": "cccc000b-0000-4000-8000-00000000000b", "type": "commit.recorded", "actor": "al", "confidence": "explicit", "schema_version": "0.2.0", "attributes": {"message_first_line": "sandbox: legacy loose seal", "author": "al", "date": "2026-06-10"}}\n' \
  >> .agent-plan-tracker/events.jsonl
git add -A && git commit -qm "sandbox: epoch case"
run bash "$GATE_CHECK" --repo-root "$PWD" --ref HEAD
check "legacy seal notices"             grep -q '^NOTICE \[seal-commit\].*pre-0.3.0 seal.*legacy loose seal' <<<"$OUT"
check_absent "legacy seal never blocks" '^BLOCK \[seal-commit\].*legacy loose seal'
check "case-8 orphan still blocks"      grep -q '^BLOCK \[seal-commit\].*sandbox: never happened' <<<"$OUT"

# --- Case 9: the real repo passes the full contract (§4.1) ----------------
echo "== real repo / filesystem mode"
cd "$WT_ROOT" || exit 2
run bash "$GATE_CHECK"
check "exit 0 against this repo"        [ "$CODE" -eq 0 ]
check "PASS verdict"                    grep -q '^gate-check: PASS' <<<"$OUT"
check_absent "no BLOCK lines"           '^BLOCK'

echo
if [ "$FAIL" -eq 0 ]; then
  echo "gatecheck sandbox: ALL PASS"
else
  echo "gatecheck sandbox: FAILURES (see above)"
fi
exit "$FAIL"
