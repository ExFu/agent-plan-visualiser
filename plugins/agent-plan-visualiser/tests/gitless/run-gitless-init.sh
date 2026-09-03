#!/usr/bin/env bash
# run-gitless-init.sh — T3-git-less-init §4: `apv-init.sh --no-git` attaches a
# plain folder (no repository) idempotently; the flag is explicit, never
# inferred (M7 §2.3); nothing machine-specific and no git plumbing is written.
#
# Every case runs in a mktemp dir verified NOT to be inside a git work tree.
# Exits 0 when every case passes; 1 on the first failure.
set -uo pipefail
cd "$(dirname "$0")" || exit 2
APV="$(cd ../.. && pwd)"
INIT="$APV/scripts/apv-init.sh"
FAIL=0

check() { local desc="$1"; shift; if "$@"; then echo "  ok: $desc"; else echo "  FAIL: $desc"; FAIL=1; fi; }
check_present() { local desc="$1" pattern="$2"; if grep -q -- "$pattern" <<<"$OUT"; then echo "  ok: $desc"; else echo "  FAIL: $desc"; FAIL=1; fi; }
check_absent()  { local desc="$1" pattern="$2"; if grep -q -- "$pattern" <<<"$OUT"; then echo "  FAIL: $desc"; FAIL=1; else echo "  ok: $desc"; fi; }
new_dir() {
  T="$(cd "$(mktemp -d)" && pwd -P)"
  if git -C "$T" rev-parse --show-toplevel >/dev/null 2>&1; then echo "abort: $T is inside a git work tree" >&2; exit 2; fi
}
run_init() { OUT="$(cd "$T" && env -u APV_DATA_DIR -u APV_PLANNING_DIR -u APV_CACHE_DIR XDG_CACHE_HOME="$T-xdg" bash "$INIT" "$@" 2>&1)"; CODE=$?; }
hash_of() { python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"; }
finish() { [ "$FAIL" -eq 0 ] && rm -rf "$T" "$T-xdg"; }

echo "== 1. no flag, no git: refuses and names the flag"
new_dir; run_init
check "exit 2" [ "$CODE" -eq 2 ]
check_present "names --no-git" "pass --no-git"
finish

echo "== 2. --no-git inside a git repository: refuses"
new_dir; git -C "$T" init -q; run_init --no-git
check "exit 2" [ "$CODE" -eq 2 ]
check_present "says to drop the flag" "drop the flag"
finish

echo "== 3. --no-git in a plain folder: attaches with no git plumbing"
new_dir; run_init --no-git
check "exit 0" [ "$CODE" -eq 0 ]
check "empty events.jsonl" [ -f "$T/.apv/events.jsonl" ] && check "log is empty" [ ! -s "$T/.apv/events.jsonl" ]
check "schema-version.txt is 0.3.0" [ "$(cat "$T/.apv/schema-version.txt" 2>/dev/null)" = "0.3.0" ]
check "config declares no_git" grep -q '^no_git = true' "$T/.apv-config.toml"
check "config pins planning_dir" grep -q '^planning_dir = "planning"' "$T/.apv-config.toml"
check "config documents cache_dir" grep -q '^# cache_dir' "$T/.apv-config.toml"
check "config documents [planning]" grep -q 'non_plan_files' "$T/.apv-config.toml"
check "config carries [requires]" grep -q '^\[requires\]' "$T/.apv-config.toml"
check "no launcher shim" [ ! -e "$T/.apv/bin" ]
check "no ./apv symlink" [ ! -e "$T/apv" ]
check "no .gitignore" [ ! -e "$T/.gitignore" ]
check "no .toolchain-home pointer" [ ! -e "$T/.apv/.toolchain-home" ]
check "no .git created" [ ! -e "$T/.git" ]
check_present "launcher reported skipped" "skipped .*launcher"
check_present "hooks reported skipped" "skipped .*git hooks"
check_present "on-demand commands printed" "repack-validate.sh"
check "no machine path in the config" bash -c "! grep -qF '$HOME' '$T/.apv-config.toml'"
check "config has no absolute path" bash -c "! grep -q '^[a-z_]* = \"/' '$T/.apv-config.toml'"
finish

echo "== 4. re-run is audit mode: nothing changes"
new_dir; run_init --no-git; C1="$(hash_of "$T/.apv-config.toml")"; E1="$(hash_of "$T/.apv/events.jsonl")"; run_init --no-git
check "exit 0" [ "$CODE" -eq 0 ]
check "config byte-identical" [ "$(hash_of "$T/.apv-config.toml")" = "$C1" ]
check "log byte-identical" [ "$(hash_of "$T/.apv/events.jsonl")" = "$E1" ]
check_absent "nothing created on re-run" "^  created"
finish

echo "== 5. --accept-claude-md writes the git-less orientation block once"
new_dir; run_init --no-git --accept-claude-md
check "exit 0" [ "$CODE" -eq 0 ]
check "opening marker" grep -q '<!-- apv:orientation -->' "$T/CLAUDE.md"
check "closing marker" grep -q '<!-- /apv:orientation -->' "$T/CLAUDE.md"
check "names capture seals" grep -qi 'capture seal' "$T/CLAUDE.md"
check "names conflicted copies" grep -qi 'conflicted cop' "$T/CLAUDE.md"
check "does not name --no-verify" bash -c "! grep -q -- '--no-verify' '$T/CLAUDE.md'"
check "does not name apv-merge" bash -c "! grep -q 'apv-merge' '$T/CLAUDE.md'"
check "does not name .last-capture" bash -c "! grep -q 'last-capture' '$T/CLAUDE.md'"
H1="$(hash_of "$T/CLAUDE.md")"; run_init --no-git --accept-claude-md
check "second accept writes nothing" [ "$(hash_of "$T/CLAUDE.md")" = "$H1" ]
finish

echo "== 6. --no-git rejects hook-installing flags"
new_dir; run_init --no-git --at=pre-push
check "--at=pre-push exits 2" [ "$CODE" -eq 2 ]
run_init --no-git --with-extractor
check "--with-extractor exits 2" [ "$CODE" -eq 2 ]
finish

echo "== 7. an initialised folder runs the pipeline end to end"
new_dir; run_init --no-git
mkdir -p "$T/planning"; printf '> descriptor\n' > "$T/planning/agent.md"
cp "$APV/tests/gitless/fixture/planning/T1-top-level.md" "$T/planning/"
python3 - "$T/.apv/events.jsonl" <<'PY'
import json, sys
E=[{"event_id":"dddd0001-0000-4000-8000-000000000001","type":"entity.created","actor":"al","confidence":"explicit","schema_version":"0.3.0","entity_type":"plan","entity_id":"T1-top-level","attributes":{"plan_kind":"thematic","tier":1,"status":"active","summary":"first plan"}},
   {"event_id":"dddd0002-0000-4000-8000-000000000002","type":"commit.recorded","actor":"al","confidence":"explicit","schema_version":"0.3.0","attributes":{"author":"al","date":"2026-09-03","message_first_line":"plan: first block (capture seal)"}}]
open(sys.argv[1],"w").write("".join(json.dumps(e)+"\n" for e in E))
PY
OUT="$(cd "$T" && env -u APV_DATA_DIR -u APV_PLANNING_DIR -u APV_CACHE_DIR XDG_CACHE_HOME="$T-xdg" bash "$APV/scripts/repack-validate.sh" 2>&1)"; CODE=$?
check "repack-validate exits 0" [ "$CODE" -eq 0 ]
check "data dir gained only summary.md" [ "$(ls -A "$T/.apv" | sort | tr '\n' ' ')" = "events.jsonl schema-version.txt summary.md " ]
finish

echo
if [ "$FAIL" -eq 0 ]; then echo "gitless init: ALL PASS"; else echo "gitless init: FAILURES (last sandbox kept at $T)"; fi
exit "$FAIL"
