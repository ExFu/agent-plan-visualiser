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

# The toolchain and the repo being validated are independent locations: on a
# plugin install this script runs from the plugin cache while the tracked repo
# is anywhere on disk. Resolve each from its own source — the same split
# gate-check.sh makes. (The old `cd "$(dirname "$0")/../.."` assumed the
# toolchain was vendored one level under a repo root, true only in dogfood.)
TOOLCHAIN="$(cd "$(dirname "$0")/.." && pwd)"

# Repo root and data dir via apvlib (root: git toplevel -> nearest
# .apv-config.toml -> toolchain parent; data: APV_DATA_DIR -> config ->
# .apv/), so this wrapper and the Python steps agree on where the project
# is — including a synced folder with no git (M7-git-less-scopes).
RESOLVED="$(python3 - "$TOOLCHAIN/scripts" <<'PYEOF'
import sys
sys.path.insert(0, sys.argv[1])
import apvlib
root = apvlib.repo_root()
data = apvlib.apv_data_dir(root)
print(root)
print(data)
print(apvlib.apv_cache_dir(data, root))
PYEOF
)" || { echo "repack-validate: could not resolve the repo root / data dir" >&2; exit 2; }
REPO_ROOT="$(printf '%s\n' "$RESOLVED" | sed -n 1p)"
DATA_DIR="$(printf '%s\n' "$RESOLVED" | sed -n 2p)"
CACHE_DIR="$(printf '%s\n' "$RESOLVED" | sed -n 3p)"
cd "$REPO_ROOT" || exit 2
# Derived files (cache.sqlite, projection.json) live here — beside the log in
# a git repo, outside the synced folder otherwise (apvlib.apv_cache_dir).
echo "cache dir: $CACHE_DIR"

# When derived files live outside the data dir, anything derived that is
# still beside events.jsonl is stale: a journal or .tmp from a build that
# failed mid-write into the synced folder (the failure M7 relocates away
# from), or a cache/projection from before relocation — which a scope-local
# dashboard builder could read by mistake. Report; never fail; the operator
# deletes them.
warn_leftovers() {
  [ "$CACHE_DIR" != "$DATA_DIR" ] || return 0
  for leftover in cache.sqlite-journal cache.sqlite.tmp; do
    [ -e "$DATA_DIR/$leftover" ] && echo "${YELLOW}WARN leftover $leftover beside events.jsonl — from a failed build; safe to delete${RESET}"
  done
  for leftover in cache.sqlite projection.json; do
    [ -e "$DATA_DIR/$leftover" ] && echo "${YELLOW}WARN stale $leftover beside events.jsonl — derived files now live in $CACHE_DIR; safe to delete${RESET}"
  done
  return 0
}

run_step "validate events.jsonl"          bash "$TOOLCHAIN/scripts/validate-events.sh"           || exit 1
run_step "validate plan frontmatter"      bash "$TOOLCHAIN/scripts/validate-plan-frontmatter.sh" || exit 1
run_step "rebuild SQLite cache"           python3 "$TOOLCHAIN/scripts/cache-build.py"            || exit 1
warn_leftovers
run_step "emit projection.json"           python3 "$TOOLCHAIN/scripts/projection-emit.py"        || exit 1
run_step "emit summary.md"                python3 "$TOOLCHAIN/scripts/summary-emit.py"           || exit 1
# Audits run through Python's sqlite3 module (audit-run.py) — the CLI is not
# a dependency; the cache path resolves the same way the build steps did.
run_step "audit-stalled"                  python3 "$TOOLCHAIN/scripts/audit-run.py" "$TOOLCHAIN/scripts/audit-stalled.sql"                  || exit 1
run_step "audit-fulcrum-without-decision" python3 "$TOOLCHAIN/scripts/audit-run.py" "$TOOLCHAIN/scripts/audit-fulcrum-without-decision.sql" || exit 1
run_step "audit-orphans"                  python3 "$TOOLCHAIN/scripts/audit-run.py" "$TOOLCHAIN/scripts/audit-orphans.sql"                  || exit 1

echo
echo "${GREEN}All ${#PASS[@]} steps passed.${RESET}"
