---
id: T3-plan-frontmatter-schema
plan_kind: thematic
tier: 3
t2_parent: T2-ontology
milestone: M1-bootstrap
status: draft
---

# T3-plan-frontmatter-schema — JSON Schema for plan YAML frontmatter

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Land `agent-plan-tracker/schemas/0.1.0/plan-frontmatter.schema.json` validating every plan file's YAML frontmatter in `planning/`.

**Architecture:** Single JSON Schema (draft-07) discriminated by `plan_kind`. Thematic plans require `tier`, allow optional `tier_prefix`, with T3 variants additionally requiring `t2_parent` + `milestone`. Milestone plans require `milestone_index`. Filename-equals-id rule enforced outside JSON Schema (by the validator script).

**Tech Stack:** JSON Schema draft-07. Python (`pyyaml` + `jsonschema` or `check-jsonschema`) for YAML extraction + validation.

---

## 1. Why this T3

Plan files need a validation contract. Without one, frontmatter drift (missing `id`, wrong `plan_kind`, inconsistent `tier_prefix`) goes silent until extraction/projection breaks downstream. M1's cleanliness floor includes structurally-valid plan files.

## 2. Out of scope

- Validating non-plan markdown files (inbox items, philosophies — different entity types or none).
- Validating plan body content (only frontmatter).
- Validating cross-plan references (e.g. `t2_parent: T2-foo` must exist).
- Lettered-workstream-specific extra fields (defer until first lettered workstream surfaces).

## 3. Acceptance criteria

- `agent-plan-tracker/schemas/0.1.0/plan-frontmatter.schema.json` exists, valid as draft-07.
- Schema validates every plan file currently in `planning/` (T1-top-level, M1-bootstrap, T2-ontology, T2-storage, T2-projection, T2-packaging, T2-extraction, T2-ingest, T3-plugin-scaffold, T3-events-schema-json, T3-plan-frontmatter-schema — once landed).
- Validation script `agent-plan-tracker/scripts/validate-plan-frontmatter.sh` runs against all plan files + reports passes/fails.
- Filename-equals-id check enforced by the script (not JSON Schema).

## 4. Steps

### Step 1: Write the schema

**File:** `agent-plan-tracker/schemas/0.1.0/plan-frontmatter.schema.json`

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "https://agent-plan-tracker/schemas/0.1.0/plan-frontmatter.schema.json",
  "title": "agent-plan-tracker plan frontmatter",
  "type": "object",
  "required": ["id", "plan_kind", "status"],
  "properties": {
    "id": {
      "type": "string",
      "pattern": "^([A-Z]?T[0-3]|M[0-9]+)-[a-z0-9][a-z0-9-]*$"
    },
    "plan_kind": { "type": "string", "enum": ["thematic", "milestone"] },
    "status": {
      "type": "string",
      "enum": ["draft", "active", "active-authoring", "planned", "in-progress", "parked", "cancelled", "superseded", "completed"]
    }
  },
  "oneOf": [
    {
      "properties": {
        "plan_kind": { "const": "thematic" },
        "tier": { "type": "integer", "enum": [0, 1, 2, 3] },
        "tier_prefix": { "type": "string", "pattern": "^[A-Z]$" },
        "t2_parent": { "type": "string", "pattern": "^([A-Z]?T2)-[a-z0-9][a-z0-9-]*$" },
        "milestone": { "type": "string", "pattern": "^M[0-9]+-[a-z0-9][a-z0-9-]*$" }
      },
      "required": ["tier"],
      "allOf": [
        {
          "if": { "properties": { "tier": { "const": 3 } } },
          "then": { "required": ["t2_parent", "milestone"] }
        }
      ]
    },
    {
      "properties": {
        "plan_kind": { "const": "milestone" },
        "milestone_index": { "type": "integer", "minimum": 1 }
      },
      "required": ["milestone_index"]
    }
  ]
}
```

### Step 2: Self-validate

```bash
check-jsonschema --check-metaschema agent-plan-tracker/schemas/0.1.0/plan-frontmatter.schema.json
```
Expected: PASS.

### Step 3: Write extractor + validator script

**File:** `agent-plan-tracker/scripts/validate-plan-frontmatter.sh`

```bash
#!/usr/bin/env bash
# Extract YAML frontmatter from each plan file + validate against schema.
# Also enforce filename-equals-id rule (not in JSON Schema).
set -euo pipefail
SCHEMA="${1:-agent-plan-tracker/schemas/0.1.0/plan-frontmatter.schema.json}"
PLANS_DIR="${2:-planning}"

python3 - "$SCHEMA" "$PLANS_DIR" <<'PYEOF'
import sys, os, json, re, glob
try:
    import yaml
except ImportError:
    sys.stderr.write("PyYAML not installed; run: pip install pyyaml\n")
    sys.exit(2)
try:
    from jsonschema import validate, ValidationError
except ImportError:
    sys.stderr.write("jsonschema not installed; run: pip install jsonschema\n")
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
    # Filename-equals-id check
    filename_stem = os.path.splitext(os.path.basename(path))[0]
    if fm.get("id") != filename_stem:
        print(f"FAIL {path}: filename '{filename_stem}.md' != frontmatter id '{fm.get('id')}'")
        failures += 1
        continue
    # JSON Schema validation
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
```

Make executable:
```bash
chmod +x agent-plan-tracker/scripts/validate-plan-frontmatter.sh
```

### Step 4: Install Python deps if missing

```bash
python3 -c "import yaml, jsonschema" || pip install --user pyyaml jsonschema
```

### Step 5: Run validation

```bash
bash agent-plan-tracker/scripts/validate-plan-frontmatter.sh
```
Expected: all plan files OK.

If any fail: inspect the frontmatter, fix or update schema, re-run.

### Step 6: Commit

```bash
git add agent-plan-tracker/schemas/0.1.0/plan-frontmatter.schema.json \
        agent-plan-tracker/scripts/validate-plan-frontmatter.sh
```

Commit message: `[M1] T3-plan-frontmatter-schema complete`

## 5. Files to create / modify

- **Create:** `agent-plan-tracker/schemas/0.1.0/plan-frontmatter.schema.json`
- **Create:** `agent-plan-tracker/scripts/validate-plan-frontmatter.sh`

## 6. Verification

- Schema is itself valid JSON Schema draft-07.
- Every plan file passes validation.
- Filename-equals-id rule catches mismatches.

## 7. HITL questions

- **Q1**: T3-plugin-scaffold currently has frontmatter that includes `t2_parent` and `milestone` — confirms the T3-required-fields enforcement works. Any other plans missing required fields? Likely no.
- **Q2**: The `status` enum captures the known states. If a plan ever needs a new status (e.g. `under-review`), update the schema explicitly — don't extend silently.

## 8. Events this T3 will emit

- `entity.progressed` on T2-ontology.
- `entity.completed` on T3-plan-frontmatter-schema.
- `verification.tested` on T3-plan-frontmatter-schema (test_type: `validate-all-plan-frontmatter`).
- `entity.progressed` on M1-bootstrap.
- `commit.recorded`.
