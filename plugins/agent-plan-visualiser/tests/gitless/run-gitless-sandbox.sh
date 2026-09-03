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
# XDG_CACHE_HOME is pointed at a sibling of the sandbox so the per-machine
# cache default is inspectable and never touches the real ~/.cache.
in_t() { ( cd "$T" && env -u APV_DATA_DIR -u APV_PLANNING_DIR -u APV_CACHE_DIR XDG_CACHE_HOME="$T-xdg" "$@" ); }

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
run bash -c "cd '$T' && printf 'SELECT COUNT(*) AS n FROM events;' | env PATH='$NOSQL_PATH' XDG_CACHE_HOME='$T-xdg' python3 '$APV/scripts/audit-run.py' -"
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

# --- §2.4 derived files leave the synced folder ----------------------------
echo "== derived files relocate out of the data dir when there is no git"
run in_t env PATH="$NOSQL_PATH" bash "$APV/scripts/repack-validate.sh"
check "repack-validate exits 0" [ "$CODE" -eq 0 ]
check_present "cache dir is printed" "^cache dir: "
CACHE_DIR="$(sed -n 's/^cache dir: //p' <<<"$OUT" | head -n 1)"
check "data dir holds only the record and the human summary" \
  [ "$(ls -A "$T/.apv" | sort | tr '\n' ' ')" = "events.jsonl schema-version.txt summary.md " ]
check "cache.sqlite landed in the cache dir" [ -f "$CACHE_DIR/cache.sqlite" ]
check "projection.json landed in the cache dir" [ -f "$CACHE_DIR/projection.json" ]
case "$CACHE_DIR" in "$T"/*) echo "  FAIL: cache dir is inside the synced folder ($CACHE_DIR)"; FAIL=1 ;; *) echo "  ok: cache dir is outside the synced folder" ;; esac
case "$CACHE_DIR" in "$T-xdg/apv/"*) echo "  ok: default is <XDG_CACHE_HOME>/apv/<scope>-<hash>" ;; *) echo "  FAIL: unexpected default cache dir $CACHE_DIR"; FAIL=1 ;; esac
run in_t python3 "$APV/scripts/gate-composite.py"
check "gate-composite still passes (same cache dir)" [ "$CODE" -eq 0 ]

echo "== a leftover journal beside events.jsonl is warned about, not fatal"
: > "$T/.apv/cache.sqlite-journal"
run in_t env PATH="$NOSQL_PATH" bash "$APV/scripts/repack-validate.sh"
check "repack-validate exits 0" [ "$CODE" -eq 0 ]
check_present "journal warning printed" "WARN leftover cache.sqlite-journal"
rm -f "$T/.apv/cache.sqlite-journal"
: > "$T/.apv/cache.sqlite"; : > "$T/.apv/projection.json"
run in_t env PATH="$NOSQL_PATH" bash "$APV/scripts/repack-validate.sh"
check "repack-validate exits 0 with stale derived files present" [ "$CODE" -eq 0 ]
check_present "stale cache warned" "WARN stale cache.sqlite beside events.jsonl"
check_present "stale projection warned" "WARN stale projection.json beside events.jsonl"
rm -f "$T/.apv/cache.sqlite" "$T/.apv/projection.json"

echo "== unwritable cache home falls back to the temp dir and says so"
run in_t env PATH="$NOSQL_PATH" XDG_CACHE_HOME=/dev/null/apv bash "$APV/scripts/repack-validate.sh"
check "repack-validate exits 0" [ "$CODE" -eq 0 ]
check_present "fallback announced" "not writable; using"
TMP_BASE="$(python3 -c 'import tempfile; print(tempfile.gettempdir())')"
check_present "cache went under the temp dir" "^cache dir: $TMP_BASE/apv/"
check "data dir still clean" [ ! -e "$T/.apv/cache.sqlite" ]

echo "== APV_CACHE_DIR overrides the default"
run in_t env PATH="$NOSQL_PATH" APV_CACHE_DIR="$T-cache" bash "$APV/scripts/repack-validate.sh"
check "repack-validate exits 0" [ "$CODE" -eq 0 ]
check "override honoured" [ -f "$T-cache/cache.sqlite" ]
check_present "override printed" "^cache dir: $T-cache"
rm -rf "$T-cache"

echo "== a declared git-less folder inside someone's git checkout still keeps derived files out"
G="$(cd "$(mktemp -d)" && pwd -P)"; git -C "$G" init -q
mkdir -p "$G/.apv"; cp -R fixture/planning "$G/planning"; cp fixture/events.jsonl fixture/schema-version.txt "$G/.apv/"
printf '[storage]\ndata_dir = ".apv"\nplanning_dir = "planning"\nno_git = true\n' > "$G/.apv-config.toml"
run bash -c "cd '$G' && env -u APV_DATA_DIR -u APV_PLANNING_DIR -u APV_CACHE_DIR XDG_CACHE_HOME='$T-xdg' bash '$APV/scripts/repack-validate.sh'"
check "repack-validate exits 0 in the git checkout" [ "$CODE" -eq 0 ]
check "no_git = true keeps cache.sqlite out of the data dir" [ ! -e "$G/.apv/cache.sqlite" ]
rm -rf "$G"

echo "== a plan-named file without frontmatter still stops the pipeline"
printf '# not a plan yet\n' > "$T/planning/T3-broken.md"
run in_t env PATH="$NOSQL_PATH" bash "$APV/scripts/repack-validate.sh"
check "repack-validate exits 1" [ "$CODE" -eq 1 ]
check_present "fails at the validator step" "FAIL: validate plan frontmatter"
rm -f "$T/planning/T3-broken.md"

echo
if [ "$FAIL" -eq 0 ]; then
  rm -rf "$T" "$T-xdg"
  echo "ALL PASS"
else
  echo "FAILURES (sandbox kept at $T)"
  exit 1
fi
