#!/usr/bin/env bash
# run-gate-tests.sh — fixture verification for gate-composite.py
# (T3-integrity-composite §4 items 2–4, plus a real-log re-run of item 1).
# Exits 0 when every case passes; 1 on the first failure.
set -uo pipefail
cd "$(dirname "$0")" || exit 2
GATE="../../scripts/gate-composite.py"
REPO_ROOT="$(cd ../../.. && pwd)"
FAIL=0

# Fixture caches are derived — rebuild from scratch every run so a stale
# cache (same event count, different content) can't mask a regression.
rm -f fixture-corrupt/cache.sqlite fixture-drift/cache.sqlite fixture-attention/cache.sqlite

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

run_case() { # run_case <name> <data-dir> <config> -> sets OUT, CODE
  local name="$1" data="$2" cfg="$3"
  echo "== $name"
  OUT="$(python3 "$GATE" --data-dir "$data" --config "$cfg" --planning-dir fixture-drift-planning 2>&1)"
  CODE=$?
}

# --- Case 1: corrupted log, default config (§4.2) -----------------------
# Four distinct corruptions, each named; schema + fulcrum stay clean.
run_case "corrupt fixture / default config" fixture-corrupt config-default.toml
check "exit 1"                                  [ "$CODE" -eq 1 ]
check "4 BLOCK lines"                           [ "$(grep -c '^BLOCK' <<<"$OUT")" -eq 4 ]
check "referential: dangling decision ref"      grep -q '^BLOCK \[referential\].*deadbeef' <<<"$OUT"
check "implementation-on-draft names FIX-A"     grep -q "^BLOCK \[implementation-on-draft\].*'FIX-A'" <<<"$OUT"
check "resurrection-without-reopen names FIX-B" grep -q "^BLOCK \[resurrection-without-reopen\].*'FIX-B'" <<<"$OUT"
check "sealed-tail: trailing run"               grep -q '^BLOCK \[sealed-tail\].*unsealed trailing' <<<"$OUT"
check_absent "schema check stays clean"         '^BLOCK \[schema\]'
check_absent "fulcrum check stays clean"        '^BLOCK \[fulcrum-without-decision\]'

# --- Case 2: drift fixture, default config (§4.3) ------------------------
# Stale frontmatter is advisory: warn reported, exit 0.
run_case "drift fixture / default config" fixture-drift config-default.toml
check "exit 0"                                  [ "$CODE" -eq 0 ]
check_absent "no BLOCK lines"                   '^BLOCK'
check "WARN [drift] names the stale seed"       grep -q "^WARN \[drift\].*'FIX-T2-OLD'.*FIX-T2-NEW" <<<"$OUT"

# --- Case 2b: multi-project roots — registry-resolved drift + duplicate ---
# No --planning-dir: the composite resolves roots from config-projects.toml
# ([projects.rootb] + [storage] as implicit main). Root B carries a copy of
# FIX-D3.md: the drift WARN must still fire (found via the registry) and the
# duplicate plan id must WARN, not block.
echo "== drift across registered roots (config-resolved, no --planning-dir)"
mkdir -p fixture-drift-planning-b
cp fixture-drift-planning/FIX-D3.md fixture-drift-planning-b/FIX-D3.md
OUT="$(python3 "$GATE" --repo-root . --data-dir fixture-drift --config config-projects.toml 2>&1)"
CODE=$?
rm -rf fixture-drift-planning-b
check "exit 0 (warn-only)"                      [ "$CODE" -eq 0 ]
check_absent "no BLOCK lines"                   '^BLOCK'
check "drift found via registry root"           grep -q "^WARN \[drift\].*'FIX-T2-OLD'.*FIX-T2-NEW" <<<"$OUT"
check "duplicate plan id warned"                grep -q "^WARN \[drift\].*duplicate plan id" <<<"$OUT"
check "duplicate names both roots"              grep -q "'rootb' and 'main'" <<<"$OUT"

# --- Case 3: config flip, blocking -> warn (§4.4) ------------------------
# sealed-tail demoted: same corrupt log now reports it as WARN; still exit 1
# on the three remaining blockers.
run_case "corrupt fixture / sealed-tail demoted to warn" fixture-corrupt config-flip-sealed-tail-warn.toml
check "exit 1 (three blockers remain)"          [ "$CODE" -eq 1 ]
check "3 BLOCK lines"                           [ "$(grep -c '^BLOCK' <<<"$OUT")" -eq 3 ]
check_absent "sealed-tail no longer blocks"     '^BLOCK \[sealed-tail\]'
check "sealed-tail surfaces as WARN"            grep -q '^WARN \[sealed-tail\]' <<<"$OUT"

# --- Case 4: config flip, warn -> blocking (§4.4) ------------------------
# drift promoted: the drift fixture now fails the gate.
run_case "drift fixture / drift promoted to blocking" fixture-drift config-flip-drift-blocking.toml
check "exit 1"                                  [ "$CODE" -eq 1 ]
check "BLOCK [drift] present"                   grep -q '^BLOCK \[drift\]' <<<"$OUT"

# --- Case 5: attention surfaces, default config ---------------------------
# T3-pending-ceremony-surfacing + T3-verification-deferred (M5.1): a draft
# plan and an all-T3s-closed-but-live milestone warn as pending ceremonies;
# an open verification.deferred warns until a later verification.* resolves
# it. All advisory — exit 0, no BLOCK lines.
run_case "attention fixture / default config" fixture-attention config-default.toml
check "exit 0 (all advisory)"                   [ "$CODE" -eq 0 ]
check_absent "no BLOCK lines"                   '^BLOCK'
check "acceptance ceremony pending"             grep -q "^WARN \[pending-ceremony\].*'FIX-ATT-DRAFT' is draft" <<<"$OUT"
check "closure ceremony pending"                grep -q "^WARN \[pending-ceremony\].*'M9-fix-att' has all 1 scheduled T3(s) closed" <<<"$OUT"
check "open deferral warns with reason"         grep -q "^WARN \[deferred-verification\].*'T3-fix-att-open'.*operator leg pending" <<<"$OUT"
check_absent "resolved deferral stays quiet"    "T3-fix-att-healed"

# --- Case 6: the real log, repo defaults (§4.1) --------------------------
echo "== real log / repo defaults"
OUT="$(cd "$REPO_ROOT" && python3 agent-plan-visualiser/scripts/gate-composite.py 2>&1)"
CODE=$?
check "exit 0 against this repo's log"          [ "$CODE" -eq 0 ]
check_absent "no BLOCK lines"                   '^BLOCK'

echo
if [ "$FAIL" -eq 0 ]; then
  echo "gate tests: ALL PASS"
else
  echo "gate tests: FAILURES (see above)"
fi
exit "$FAIL"
