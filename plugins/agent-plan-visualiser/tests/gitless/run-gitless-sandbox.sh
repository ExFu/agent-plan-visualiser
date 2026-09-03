#!/usr/bin/env bash
# run-gitless-sandbox.sh — T3-synced-folder-runtime §4: the pipeline runs clean
# from a plain folder with NO git, NO env exports and NO sqlite3 CLI.
#
# Fixture: tests/gitless/fixture — four valid plans + planning/agent.md (the
# ExFu folder descriptor, no frontmatter) + a one-block log sealed with a
# capture seal. Copied into a mktemp dir that is verified NOT to be inside a
# git work tree; a .apv-config.toml pins data_dir/planning_dir and moves the
# `stalled` check from warn to blocking so we can prove the folder's [gate]
# is read.
#
# Cases grow with the T3's builds (§2.2 root resolution, §2.1 validator,
# §2.3 audits without the CLI, §2.4 cache relocation). Exits 0 when every
# case passes; 1 on the first failure.
set -uo pipefail
cd "$(dirname "$0")" || exit 2
APV="$(cd ../.. && pwd)"
TOOLCHAIN_PARENT="$(cd "$APV/.." && pwd)"
FAIL=0

check() { # check <desc> <test-expr...>
  local desc="$1"; shift
  if "$@"; then echo "  ok: $desc"; else echo "  FAIL: $desc"; FAIL=1; fi
}
check_absent() { # check_absent <desc> <grep-pattern> — must NOT match $OUT
  local desc="$1" pattern="$2"
  if grep -q -- "$pattern" <<<"$OUT"; then echo "  FAIL: $desc"; FAIL=1; else echo "  ok: $desc"; fi
}
check_present() { # check_present <desc> <grep-pattern> — must match $OUT
  local desc="$1" pattern="$2"
  if grep -q -- "$pattern" <<<"$OUT"; then echo "  ok: $desc"; else echo "  FAIL: $desc"; FAIL=1; fi
}
run() { OUT="$("$@" 2>&1)"; CODE=$?; }
# Run <cmd...> from $T with the git-less environment: no APV_* overrides.
in_t() { ( cd "$T" && env -u APV_DATA_DIR -u APV_PLANNING_DIR -u APV_CACHE_DIR "$@" ); }

T="$(cd "$(mktemp -d)" && pwd -P)"   # physical path: apvlib resolves symlinks (/var -> /private/var on macOS)
if git -C "$T" rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "abort: $T is inside a git work tree; this sandbox needs a plain folder" >&2
  exit 2
fi
mkdir -p "$T/.apv"
cp -R fixture/planning "$T/planning"
cp fixture/events.jsonl fixture/schema-version.txt "$T/.apv/"
cat > "$T/.apv-config.toml" <<'TOML'
[gate]
blocking = ["schema", "referential", "sealed-tail", "implementation-on-draft", "resurrection-without-reopen", "fulcrum-without-decision", "stalled"]
warn = ["drift", "orphans", "long-blockers", "pending-ceremony", "deferred-verification", "attribution-drift"]

[storage]
data_dir = ".apv"
planning_dir = "planning"
TOML
echo "sandbox: $T"

# --- §2.2 root resolution ---------------------------------------------------
echo "== root resolution without git"
run in_t python3 -c "import sys; sys.path.insert(0, '$APV/scripts'); import apvlib; print(apvlib.repo_root())"
check "repo_root() is the folder holding .apv-config.toml" [ "$OUT" = "$T" ]
run bash -c "cd '$T/planning' && env -u APV_DATA_DIR python3 -c \"import sys; sys.path.insert(0, '$APV/scripts'); import apvlib; print(apvlib.repo_root())\""
check "repo_root() walks up from a sub-folder" [ "$OUT" = "$T" ]
run in_t python3 -c "import sys; sys.path.insert(0, '$APV/scripts'); import apvlib; print(apvlib.apv_config(apvlib.repo_root()).get('storage', {}).get('data_dir'))"
check "the folder's .apv-config.toml is read" [ "$OUT" = ".apv" ]
U="$(mktemp -d)"
run bash -c "cd '$U' && python3 -c \"import sys; sys.path.insert(0, '$APV/scripts'); import apvlib; print(apvlib.repo_root())\""
check "no git, no config: falls back to the toolchain parent (unchanged)" [ "$OUT" = "$TOOLCHAIN_PARENT" ]
rmdir "$U"

echo "== cache-build without git"
run in_t python3 "$APV/scripts/cache-build.py"
check "cache-build exits 0" [ "$CODE" -eq 0 ]
check_absent "no 'fatal: not a git repository' on stderr" "fatal: not a git repository"

echo "== gate-composite without flags reads the folder's config"
run in_t python3 "$APV/scripts/gate-composite.py"
check "gate-composite exits 0" [ "$CODE" -eq 0 ]
check_absent "gate did not look for events beside the toolchain" "no events.jsonl"
check_present "gate reports the folder's blocking list (stalled moved to blocking)" "blocking=\[.*'stalled'"

# --- §2.3 audits without the sqlite3 CLI -----------------------------------
# Emulate a machine without the sqlite3 CLI: a shim that fails like a missing
# command sits first on PATH (stripping whole PATH dirs would also remove sed
# and friends, which is not the environment under test).
mkdir -p "$T/nosql"
printf '#!/bin/sh\necho "sqlite3: command not found" >&2\nexit 127\n' > "$T/nosql/sqlite3"; chmod +x "$T/nosql/sqlite3"
NOSQL_PATH="$T/nosql:$PATH"
echo "== audit-run.py runs the audit SQL through Python's sqlite3 module"
run in_t env PATH="$NOSQL_PATH" python3 "$APV/scripts/audit-run.py" "$APV/scripts/audit-stalled.sql"
check "audit file runs (exit 0)" [ "$CODE" -eq 0 ]
check_present "column header printed, dot-commands stripped" "entity_id"
check_absent "no .headers/.mode leakage" "^\.\(headers\|mode\)"
run bash -c "cd '$T' && printf 'SELECT COUNT(*) AS n FROM events;' | env PATH='$NOSQL_PATH' python3 '$APV/scripts/audit-run.py' -"
check "stdin SQL runs" [ "$CODE" -eq 0 ]
check_present "row value printed" "^10$"
run bash -c "cd '$T' && python3 '$APV/scripts/audit-run.py' --cache '$T/nowhere.sqlite' '$APV/scripts/audit-orphans.sql'"
check "missing cache exits 2" [ "$CODE" -eq 2 ]
check_present "missing cache names cache-build" "cache-build"

echo "== repack-validate end to end with no sqlite3 on PATH"
run in_t env PATH="$NOSQL_PATH" bash "$APV/scripts/repack-validate.sh"
check "repack-validate exits 0 without the CLI" [ "$CODE" -eq 0 ]
check_present "all eight steps passed" "All 8 steps passed"
check_present "agent.md skipped" "SKIP .*agent.md"
check_absent "no 'sqlite3: command not found'" "sqlite3: command not found"

echo
if [ "$FAIL" -eq 0 ]; then
  rm -rf "$T"
  echo "ALL PASS"
else
  echo "FAILURES (sandbox kept at $T)"
  exit 1
fi
