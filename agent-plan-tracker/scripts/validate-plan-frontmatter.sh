#!/usr/bin/env bash
# Extract YAML frontmatter from each plan file + validate against schema.
# Also enforces filename-equals-id rule (not in JSON Schema).
# Usage: validate-plan-frontmatter.sh [schema-path] [plans-dir]
set -euo pipefail
SCHEMA="${1:-agent-plan-tracker/schemas/0.1.0/plan-frontmatter.schema.json}"
PLANS_DIR="${2:-planning}"

python3 - "$SCHEMA" "$PLANS_DIR" <<'PYEOF'
import sys, os, json, re, glob
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

schema_path, plans_dir = sys.argv[1], sys.argv[2]
with open(schema_path) as f:
    schema = json.load(f)

failures = 0
checked = 0
for path in sorted(glob.glob(os.path.join(plans_dir, "*.md"))):
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
    if fm.get("id") != filename_stem:
        print(f"FAIL {path}: filename '{filename_stem}.md' != frontmatter id '{fm.get('id')}'")
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
print(f"\nall {checked} plan files valid")
PYEOF
