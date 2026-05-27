#!/usr/bin/env bash
# repack-validate.sh — end-to-end M1 validation + build.
# Aborts on first failure. Exits 0 on success.
set -uo pipefail

if [ -t 1 ]; then
  RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RESET=$'\033[0m'
else
  RED=""; GREEN=""; YELLOW=""; RESET=""
fi

PASS=()

run_step() {
  local label="$1"; shift
  echo "${YELLOW}==>${RESET} $label"
  if "$@"; then
    PASS+=("$label")
    echo "${GREEN}    OK${RESET}"
  else
    echo "${RED}    FAIL: $label${RESET}"
    return 1
  fi
}

cd "$(dirname "$0")/../.." || exit 2

run_step "validate events.jsonl"          bash agent-plan-tracker/scripts/validate-events.sh           || exit 1
run_step "validate plan frontmatter"      bash agent-plan-tracker/scripts/validate-plan-frontmatter.sh || exit 1
run_step "rebuild SQLite cache"           python3 agent-plan-tracker/scripts/cache-build.py            || exit 1
run_step "emit projection.json"           python3 agent-plan-tracker/scripts/projection-emit.py        || exit 1
run_step "emit summary.md"                python3 agent-plan-tracker/scripts/summary-emit.py           || exit 1
run_step "audit-stalled"                  sh -c "sqlite3 .agent-plan-tracker/cache.sqlite < agent-plan-tracker/scripts/audit-stalled.sql" || exit 1
run_step "audit-fulcrum-without-decision" sh -c "sqlite3 .agent-plan-tracker/cache.sqlite < agent-plan-tracker/scripts/audit-fulcrum-without-decision.sql" || exit 1
run_step "audit-orphans"                  sh -c "sqlite3 .agent-plan-tracker/cache.sqlite < agent-plan-tracker/scripts/audit-orphans.sql" || exit 1

echo
echo "${GREEN}All ${#PASS[@]} steps passed.${RESET}"
