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
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT" || exit 2

# Data dir via apvlib (APV_DATA_DIR -> .apv-config.toml -> .apv/), matching
# what the Python steps resolve for themselves.
DATA_DIR="$(python3 - "$TOOLCHAIN/scripts" "$REPO_ROOT" <<'PYEOF'
import sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
import apvlib
print(apvlib.apv_data_dir(Path(sys.argv[2])))
PYEOF
)" || { echo "repack-validate: could not resolve the data dir" >&2; exit 2; }

run_step "validate events.jsonl"          bash "$TOOLCHAIN/scripts/validate-events.sh"           || exit 1
run_step "validate plan frontmatter"      bash "$TOOLCHAIN/scripts/validate-plan-frontmatter.sh" || exit 1
run_step "rebuild SQLite cache"           python3 "$TOOLCHAIN/scripts/cache-build.py"            || exit 1
run_step "emit projection.json"           python3 "$TOOLCHAIN/scripts/projection-emit.py"        || exit 1
run_step "emit summary.md"                python3 "$TOOLCHAIN/scripts/summary-emit.py"           || exit 1
run_step "audit-stalled"                  sh -c "sqlite3 '${DATA_DIR}/cache.sqlite' < '$TOOLCHAIN/scripts/audit-stalled.sql'" || exit 1
run_step "audit-fulcrum-without-decision" sh -c "sqlite3 '${DATA_DIR}/cache.sqlite' < '$TOOLCHAIN/scripts/audit-fulcrum-without-decision.sql'" || exit 1
run_step "audit-orphans"                  sh -c "sqlite3 '${DATA_DIR}/cache.sqlite' < '$TOOLCHAIN/scripts/audit-orphans.sql'" || exit 1

echo
echo "${GREEN}All ${#PASS[@]} steps passed.${RESET}"
