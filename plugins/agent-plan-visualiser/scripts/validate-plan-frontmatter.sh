#!/usr/bin/env bash
# Extract YAML frontmatter from each plan file + validate against schema.
# Also enforces filename-equals-id rule (not in JSON Schema).
#
# Scope: the configured planning root(s) only — `[storage] planning_dir`
# (default planning/) plus every `[projects.<name>] planning_dir`. Fail-closed
# inside them: every *.md is a plan and must validate, except the three
# carve-outs apvlib.plan_files applies (a `.apv-ignore` marker in a
# sub-folder; `[planning] non_plan_files`, default agent.md + readme.md;
# `apv: ignore` in a file's own frontmatter). See T3-synced-folder-runtime §2.1.
#
# Usage: validate-plan-frontmatter.sh [schema-path] [plans-dir]
#   plans-dir, when given, is validated as the single root (fixtures, ad hoc).
set -euo pipefail
# Schema = toolchain content, resolved beside this script (see validate-events.sh).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCHEMA="${1:-$SCRIPT_DIR/../schemas/0.2.0/plan-frontmatter.schema.json}"
PLANS_DIR="${2:-}"

python3 - "$SCRIPT_DIR" "$SCHEMA" "$PLANS_DIR" <<'PYEOF'
import sys, os, json, re
from pathlib import Path
script_dir, schema_path, plans_dir = sys.argv[1], sys.argv[2], sys.argv[3]
sys.path.insert(0, script_dir)
import apvlib

_MISSING = []
try:
    import yaml
except ImportError:
    _MISSING.append("pyyaml")
try:
    from jsonschema import validate, ValidationError
except ImportError:
    _MISSING.append("jsonschema")
if _MISSING:
    sys.stderr.write(
        f"Missing Python deps for {sys.executable}: {', '.join(_MISSING)}\n"
        f"Run: {sys.executable} -m pip install --user {' '.join(_MISSING)}\n"
        f"(Plain 'pip install ...' may install to a different Python — use the exact command above.)\n"
    )
    sys.exit(2)

with open(schema_path) as f:
    schema = json.load(f)

# Plans belong to the repo being validated (apvlib.repo_root: git toplevel ->
# nearest .apv-config.toml -> toolchain parent). Hardcoding "planning" once
# made a monorepo with a pinned planning_dir report "all 0 plan files valid".
repo_root = apvlib.repo_root()
try:
    non_plan = apvlib.apv_non_plan_files(repo_root)
    roots = [("main", Path(plans_dir))] if plans_dir else apvlib.apv_planning_roots(repo_root)
except ValueError as e:
    sys.stderr.write(f"validate-plan-frontmatter: {e}\n")
    sys.exit(2)

failures = 0
checked = 0
for root_name, root in roots:
    if len(roots) > 1:
        print(f"== {root_name}: {root}")
    if not root.is_dir():
        sys.stderr.write(f"planning root {root} does not exist\n")
        continue
    try:
        listing = apvlib.plan_files(root, non_plan)
    except ValueError as e:
        sys.stderr.write(f"validate-plan-frontmatter: {e}\n")
        sys.exit(2)
    for path, reason in listing["skipped"]:
        print(f"SKIP {path}: {reason}")
    for d in listing["unmarked_subdirs"]:
        print(f"NOTE {d}/: sub-folder not scanned; add {apvlib.IGNORE_MARKER} to record "
              "that it is intentionally non-plan content")
    for path, value in listing["bad_apv"]:
        print(f"FAIL {path}: unknown apv: value {value!r}; only 'ignore' is defined")
        failures += 1
        checked += 1
    for path in listing["plans"]:
        checked += 1
        with open(path) as f:
            content = f.read()
        m = re.match(r"^---\n(.*?)\n---\n", content, re.DOTALL)
        if not m:
            print(f"FAIL {path}: no YAML frontmatter")
            failures += 1
            continue
        try:
            fm = yaml.safe_load(m.group(1))
        except Exception as e:
            print(f"FAIL {path}: YAML parse error: {e}")
            failures += 1
            continue
        filename_stem = os.path.splitext(os.path.basename(path))[0]
        if not isinstance(fm, dict) or fm.get("id") != filename_stem:
            got = fm.get("id") if isinstance(fm, dict) else None
            print(f"FAIL {path}: filename '{filename_stem}.md' != frontmatter id '{got}'")
            failures += 1
            continue
        try:
            validate(instance=fm, schema=schema)
        except ValidationError as e:
            print(f"FAIL {path}: {e.message}")
            failures += 1
            continue
        print(f"OK   {path}")

if failures:
    sys.stderr.write(f"\n{failures}/{checked} plan files failed validation\n")
    sys.exit(1)
if not checked:
    # A green "all 0 plan files valid" is indistinguishable from a real pass
    # but proves nothing — it is what a mis-resolved plans dir looks like.
    where = ", ".join(str(r) for _, r in roots)
    sys.stderr.write(f"no plan files found under {where!r} — nothing validated\n")
    sys.exit(1)
print(f"\nall {checked} plan files valid")
PYEOF
