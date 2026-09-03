#!/usr/bin/env bash
# run-validator-tests.sh — T3-synced-folder-runtime §2.1: the plan-frontmatter
# validator is fail-closed over the configured planning folders, with exactly
# three carve-outs — a `.apv-ignore` marker in a sub-folder, the
# `[planning] non_plan_files` list (default agent.md, readme.md), and
# `apv: ignore` in a file's own frontmatter. Everything else in a planning
# folder is a plan and must validate.
#
# Each case runs in a fresh mktemp dir holding .apv-config.toml (so the
# validator resolves the planning root through apvlib.repo_root rung 2 — no
# git, no env overrides). Exits 0 when every case passes; 1 on the first
# failure.
set -uo pipefail
cd "$(dirname "$0")" || exit 2
APV="$(cd ../.. && pwd)"
VALID_PLANS="$APV/tests/gitless/fixture/planning"
FAIL=0

check() { # check <desc> <test-expr...>
  local desc="$1"; shift
  if "$@"; then echo "  ok: $desc"; else echo "  FAIL: $desc"; FAIL=1; fi
}
check_present() { local desc="$1" pattern="$2"; if grep -q -- "$pattern" <<<"$OUT"; then echo "  ok: $desc"; else echo "  FAIL: $desc"; FAIL=1; fi; }
check_absent()  { local desc="$1" pattern="$2"; if grep -q -- "$pattern" <<<"$OUT"; then echo "  FAIL: $desc"; FAIL=1; else echo "  ok: $desc"; fi; }

# new_case [config-body] -> sets $T with .apv-config.toml + planning/
new_case() {
  T="$(cd "$(mktemp -d)" && pwd -P)"
  mkdir -p "$T/planning"
  if [ $# -gt 0 ]; then printf '%s\n' "$1" > "$T/.apv-config.toml"
  else printf '[storage]\nplanning_dir = "planning"\n' > "$T/.apv-config.toml"; fi
}
add_valid() { cp "$VALID_PLANS/T1-top-level.md" "$VALID_PLANS/T2-alpha.md" "$T/planning/"; }
add_agent() { printf '> This folder follows ExFu conventions.\n\nFollows: ../ontology/planning.md\n' > "$T/planning/agent.md"; }
run_validator() { # run from $T with no APV_* env; sets OUT, CODE
  OUT="$(cd "$T" && env -u APV_DATA_DIR -u APV_PLANNING_DIR bash "$APV/scripts/validate-plan-frontmatter.sh" 2>&1)"
  CODE=$?
}
finish() { if [ "$FAIL" -eq 0 ]; then rm -rf "$T"; fi; }

echo "== 1. agent.md beside valid plans passes with a SKIP notice"
new_case; add_valid; add_agent; run_validator
check "exit 0" [ "$CODE" -eq 0 ]
check_present "agent.md skipped as a listed non-plan file" "SKIP .*agent.md: listed non-plan file"
check_present "two plans validated" "all 2 plan files valid"
finish

echo "== 2. a plan-named file without frontmatter still fails"
new_case; add_valid; add_agent; printf '# not a plan yet\n' > "$T/planning/T3-broken.md"; run_validator
check "exit 1" [ "$CODE" -eq 1 ]
check_present "T3-broken.md reported" "FAIL .*T3-broken.md: no YAML frontmatter"
finish

echo "== 3. a folder holding only agent.md validates nothing"
new_case; add_agent; run_validator
check "exit 1" [ "$CODE" -eq 1 ]
check_present "nothing-validated guard trips" "nothing validated"
finish

echo "== 4. an unlisted stray file fails (fail-closed)"
new_case; add_valid; add_agent; printf 'scratch notes\n' > "$T/planning/notes.md"; run_validator
check "exit 1" [ "$CODE" -eq 1 ]
check_present "notes.md reported" "FAIL .*notes.md"
finish

echo "== 5. the config list excludes a further file"
new_case "$(printf '[storage]\nplanning_dir = "planning"\n\n[planning]\nnon_plan_files = ["agent.md", "notes.md"]\n')"
add_valid; add_agent; printf 'scratch notes\n' > "$T/planning/notes.md"; run_validator
check "exit 0" [ "$CODE" -eq 0 ]
check_present "notes.md skipped" "SKIP .*notes.md: listed non-plan file"
check_present "agent.md skipped" "SKIP .*agent.md: listed non-plan file"
finish

echo "== 6. README.md is skipped by the default list, case-insensitively"
new_case; add_valid; printf '# plans\n' > "$T/planning/README.md"; run_validator
check "exit 0" [ "$CODE" -eq 0 ]
check_present "README.md skipped" "SKIP .*README.md: listed non-plan file"
finish

echo "== 7. a non-list non_plan_files value fails loud"
new_case "$(printf '[storage]\nplanning_dir = "planning"\n\n[planning]\nnon_plan_files = "agent.md"\n')"
add_valid; run_validator
check "exit 2" [ "$CODE" -eq 2 ]
check_present "names the key" "non_plan_files"
finish

echo "== 8. every registered planning root is validated"
new_case "$(printf '[storage]\nplanning_dir = "planning"\n\n[projects.sub]\nplanning_dir = "sub/planning"\n')"
mkdir -p "$T/sub/planning"; cp "$VALID_PLANS/T1-top-level.md" "$T/planning/"; cp "$VALID_PLANS/T2-alpha.md" "$T/sub/planning/"
add_agent; printf '> descriptor\n' > "$T/sub/planning/agent.md"; run_validator
check "exit 0" [ "$CODE" -eq 0 ]
check_present "two plans across two roots" "all 2 plan files valid"
check_present "sub root's plan validated" "OK .*sub/planning/T2-alpha.md"
check_present "main root's plan validated" "OK .*[^b]/planning/T1-top-level.md"
finish

echo "== 9. a file excludes itself with apv: ignore"
new_case; add_valid; printf -- '---\napv: ignore\ntitle: checklist\n---\n\n- [ ] thing\n' > "$T/planning/checklist.md"; run_validator
check "exit 0" [ "$CODE" -eq 0 ]
check_present "checklist.md skipped" "SKIP .*checklist.md: frontmatter apv: ignore"
finish

echo "== 10. a typo in the apv: key cannot hide a plan"
new_case; add_valid; printf -- '---\nid: T3-real\nplan_kind: thematic\ntier: 3\nt2_parent: T2-alpha\nmilestone: M1-first\nstatus: draft\napv: ignroe\n---\n\n# real\n' > "$T/planning/T3-real.md"; run_validator
check "exit 1" [ "$CODE" -eq 1 ]
check_present "unknown apv: value reported" "unknown apv: value"
finish

echo "== 11. a sub-folder with .apv-ignore is not planning content"
new_case; add_valid; mkdir -p "$T/planning/scratch"; printf 'loose\n' > "$T/planning/scratch/notes.md"; : > "$T/planning/scratch/.apv-ignore"; run_validator
check "exit 0" [ "$CODE" -eq 0 ]
check_present "scratch skipped by marker" "SKIP .*scratch: .apv-ignore"
check_absent "nothing under scratch is mentioned" "notes.md"
finish

echo "== 12. an unmarked sub-folder prints a notice and passes"
new_case; add_valid; mkdir -p "$T/planning/scratch"; printf 'loose\n' > "$T/planning/scratch/notes.md"; run_validator
check "exit 0" [ "$CODE" -eq 0 ]
check_present "notice names the folder and the marker" "NOTE .*scratch/: sub-folder not scanned; add .apv-ignore"
finish

echo "== 13. a marker on the planning root itself is a misconfiguration"
new_case; add_valid; : > "$T/planning/.apv-ignore"; run_validator
check "exit 2" [ "$CODE" -eq 2 ]
check_present "names the planning root" "planning root .* carries .apv-ignore"
finish

echo
if [ "$FAIL" -eq 0 ]; then echo "validator tests: ALL PASS"; else echo "validator tests: FAILURES (last sandbox kept at $T)"; fi
exit "$FAIL"
