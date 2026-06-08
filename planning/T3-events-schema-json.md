---
id: T3-events-schema-json
plan_kind: thematic
tier: 3
t2_parent: T2-ontology
milestone: M1-bootstrap
status: completed
---

# T3-events-schema-json — JSON Schema for 23 event types

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Land `agent-plan-tracker/schemas/0.1.0/events.schema.json` validating every event in `.agent-plan-tracker/events.jsonl` after retro-migration from `0.0.0-prehistoric` to `0.1.0`.

**Architecture:** Single JSON Schema (draft-07) with `oneOf` discriminated by the `type` field. Common fields validated at root; type-specific attributes validated per branch. Cross-event constraints (fulcrum-decision pairing) NOT enforced here — caught at cache build (T3-cache-build).

**Tech Stack:** JSON Schema draft-07. Python `check-jsonschema` for validation. `jq` + Python for migration.

---

## 1. Why this T3

M1 needs the validation contract. Every event must parse against this schema before being trusted by downstream T3s. Per T2-ontology §3 — this is the formal capture of the prose ontology.

## 2. Out of scope

- Cross-event constraints (fulcrum-decision pairing) — caught at cache build.
- TypeScript type generation from schema.
- Performance optimisation of validation.
- Schema versioning discipline beyond 0.1.0 (`T3-schema-versioning-discipline`, M2).
- Validating other schemas (frontmatter is `T3-plan-frontmatter-schema`).

## 3. Acceptance criteria

- `agent-plan-tracker/schemas/0.1.0/events.schema.json` exists and is itself valid JSON Schema draft-07.
- All 23 event types have explicit branches with attribute requirements.
- After migration, `check-jsonschema --schemafile <schema> --instancefile <line>` passes for every line in `.agent-plan-tracker/events.jsonl`.
- Migration from `0.0.0-prehistoric` to `0.1.0` is reversible-by-inspection (only `schema_version` field changes; no semantic data lost).
- A `agent-plan-tracker/scripts/validate-events.sh` script wraps validation for repeated use.

## 4. Steps

### Step 1: Verify tooling available

```bash
which python3 && python3 -m pip show check-jsonschema 2>/dev/null || pip install --user check-jsonschema
```
Expected: `check-jsonschema` available. If not, install it (one-off).

### Step 2: Create the schema scaffold

**File:** `agent-plan-tracker/schemas/0.1.0/events.schema.json`

Start with common fields + the `oneOf` skeleton. Use `$defs` for shared sub-schemas.

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "https://agent-plan-tracker/schemas/0.1.0/events.schema.json",
  "title": "agent-plan-tracker event",
  "type": "object",
  "required": ["event_id", "type", "actor", "confidence", "schema_version", "attributes"],
  "properties": {
    "event_id": {
      "type": "string",
      "pattern": "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
    },
    "type": { "type": "string" },
    "entity_type": {
      "type": "string",
      "enum": ["plan", "blocker", "hitl-question", "implicit-work", "inbox-item"]
    },
    "entity_id": { "type": "string", "minLength": 1 },
    "actor": { "type": "string", "minLength": 1 },
    "confidence": { "type": "string", "enum": ["explicit", "derived"] },
    "schema_version": { "type": "string", "const": "0.1.0" },
    "attributes": { "type": "object" }
  },
  "oneOf": [
    { "$ref": "#/$defs/entity_created" },
    { "$ref": "#/$defs/entity_extended" },
    { "$ref": "#/$defs/entity_renamed" },
    { "$ref": "#/$defs/entity_progressed" },
    { "$ref": "#/$defs/entity_completed" },
    { "$ref": "#/$defs/entity_parked" },
    { "$ref": "#/$defs/entity_cancelled" },
    { "$ref": "#/$defs/entity_superseded" },
    { "$ref": "#/$defs/entity_reopened" },
    { "$ref": "#/$defs/decision" },
    { "$ref": "#/$defs/blocker_raised" },
    { "$ref": "#/$defs/blocker_progressed" },
    { "$ref": "#/$defs/blocker_closed" },
    { "$ref": "#/$defs/verification_claimed" },
    { "$ref": "#/$defs/verification_tested" },
    { "$ref": "#/$defs/verification_skipped" },
    { "$ref": "#/$defs/verification_failed" },
    { "$ref": "#/$defs/relationship_spawns" },
    { "$ref": "#/$defs/relationship_depends_on" },
    { "$ref": "#/$defs/relationship_addendum_to" },
    { "$ref": "#/$defs/relationship_alongside" },
    { "$ref": "#/$defs/relationship_reattached" },
    { "$ref": "#/$defs/commit_recorded" }
  ],
  "$defs": {
    "entity_event_base": {
      "type": "object",
      "required": ["entity_type", "entity_id"],
      "properties": {
        "entity_type": { "type": "string" },
        "entity_id": { "type": "string" }
      }
    },
    "entity_created": {
      "allOf": [
        { "$ref": "#/$defs/entity_event_base" },
        { "properties": { "type": { "const": "entity.created" } } }
      ]
    },
    "entity_extended": {
      "allOf": [
        { "$ref": "#/$defs/entity_event_base" },
        { "properties": { "type": { "const": "entity.extended" } } }
      ]
    },
    "entity_renamed": {
      "allOf": [
        { "$ref": "#/$defs/entity_event_base" },
        {
          "properties": {
            "type": { "const": "entity.renamed" },
            "attributes": {
              "type": "object",
              "required": ["from_name", "to_name"],
              "properties": {
                "from_name": { "type": "string" },
                "to_name": { "type": "string" }
              }
            }
          }
        }
      ]
    },
    "entity_progressed": {
      "allOf": [
        { "$ref": "#/$defs/entity_event_base" },
        { "properties": { "type": { "const": "entity.progressed" } } }
      ]
    },
    "entity_completed": {
      "allOf": [
        { "$ref": "#/$defs/entity_event_base" },
        { "properties": { "type": { "const": "entity.completed" } } }
      ]
    },
    "entity_parked": {
      "allOf": [
        { "$ref": "#/$defs/entity_event_base" },
        { "properties": { "type": { "const": "entity.parked" } } }
      ]
    },
    "entity_cancelled": {
      "allOf": [
        { "$ref": "#/$defs/entity_event_base" },
        { "properties": { "type": { "const": "entity.cancelled" } } }
      ]
    },
    "entity_superseded": {
      "allOf": [
        { "$ref": "#/$defs/entity_event_base" },
        {
          "properties": {
            "type": { "const": "entity.superseded" },
            "attributes": {
              "type": "object",
              "required": ["entity_ids"],
              "properties": {
                "entity_ids": {
                  "type": "array",
                  "items": { "type": "string" },
                  "minItems": 1
                }
              }
            }
          }
        }
      ]
    },
    "entity_reopened": {
      "allOf": [
        { "$ref": "#/$defs/entity_event_base" },
        { "properties": { "type": { "const": "entity.reopened" } } }
      ]
    },
    "decision": {
      "type": "object",
      "properties": {
        "type": { "const": "decision" },
        "attributes": {
          "type": "object",
          "required": ["text", "event_ids"],
          "properties": {
            "text": { "type": "string", "minLength": 1 },
            "event_ids": {
              "type": "array",
              "items": { "type": "string" },
              "minItems": 1
            }
          }
        }
      },
      "required": ["type"]
    },
    "blocker_raised": {
      "allOf": [
        { "$ref": "#/$defs/entity_event_base" },
        { "properties": { "type": { "const": "blocker.raised" } } }
      ]
    },
    "blocker_progressed": {
      "allOf": [
        { "$ref": "#/$defs/entity_event_base" },
        {
          "properties": {
            "type": { "const": "blocker.progressed" },
            "attributes": {
              "type": "object",
              "required": ["note"],
              "properties": { "note": { "type": "string" } }
            }
          }
        }
      ]
    },
    "blocker_closed": {
      "allOf": [
        { "$ref": "#/$defs/entity_event_base" },
        { "properties": { "type": { "const": "blocker.closed" } } }
      ]
    },
    "verification_claimed": {
      "allOf": [
        { "$ref": "#/$defs/entity_event_base" },
        { "properties": { "type": { "const": "verification.claimed" } } }
      ]
    },
    "verification_tested": {
      "allOf": [
        { "$ref": "#/$defs/entity_event_base" },
        { "properties": { "type": { "const": "verification.tested" } } }
      ]
    },
    "verification_skipped": {
      "allOf": [
        { "$ref": "#/$defs/entity_event_base" },
        {
          "properties": {
            "type": { "const": "verification.skipped" },
            "attributes": {
              "type": "object",
              "required": ["reason"],
              "properties": { "reason": { "type": "string" } }
            }
          }
        }
      ]
    },
    "verification_failed": {
      "allOf": [
        { "$ref": "#/$defs/entity_event_base" },
        { "properties": { "type": { "const": "verification.failed" } } }
      ]
    },
    "relationship_spawns": {
      "allOf": [
        { "$ref": "#/$defs/entity_event_base" },
        {
          "properties": {
            "type": { "const": "relationship.spawns" },
            "attributes": {
              "type": "object",
              "required": ["from_entity_type", "from_entity_id"],
              "properties": {
                "from_entity_type": { "type": "string" },
                "from_entity_id": { "type": "string" }
              }
            }
          }
        }
      ]
    },
    "relationship_depends_on": {
      "allOf": [
        { "$ref": "#/$defs/entity_event_base" },
        {
          "properties": {
            "type": { "const": "relationship.depends-on" },
            "attributes": {
              "type": "object",
              "required": ["from_entity_type", "from_entity_id"]
            }
          }
        }
      ]
    },
    "relationship_addendum_to": {
      "allOf": [
        { "$ref": "#/$defs/entity_event_base" },
        {
          "properties": {
            "type": { "const": "relationship.addendum-to" },
            "attributes": {
              "type": "object",
              "required": ["from_entity_type", "from_entity_id"]
            }
          }
        }
      ]
    },
    "relationship_alongside": {
      "allOf": [
        { "$ref": "#/$defs/entity_event_base" },
        {
          "properties": {
            "type": { "const": "relationship.alongside" },
            "attributes": {
              "type": "object",
              "required": ["from_entity_type", "from_entity_id"]
            }
          }
        }
      ]
    },
    "relationship_reattached": {
      "allOf": [
        { "$ref": "#/$defs/entity_event_base" },
        {
          "properties": {
            "type": { "const": "relationship.reattached" },
            "attributes": {
              "type": "object",
              "required": ["from_parent", "to_parent"],
              "properties": {
                "from_parent": { "type": "string" },
                "to_parent": { "type": "string" }
              }
            }
          }
        }
      ]
    },
    "commit_recorded": {
      "type": "object",
      "properties": {
        "type": { "const": "commit.recorded" },
        "attributes": {
          "type": "object",
          "required": ["author", "date", "message_first_line"],
          "properties": {
            "author": { "type": "string" },
            "date": { "type": "string" },
            "message_first_line": { "type": "string" }
          }
        }
      },
      "required": ["type"]
    }
  }
}
```

### Step 3: Self-validate the schema

```bash
check-jsonschema --check-metaschema agent-plan-tracker/schemas/0.1.0/events.schema.json
```
Expected: PASS (schema is itself valid).

### Step 4: Migrate events.jsonl from prehistoric to 0.1.0

Write a one-shot migration script. **No semantic changes** — only the `schema_version` field bumps. Decision and commit.recorded events that previously omitted `entity_type`/`entity_id` continue to do so (allowed under their branches; absent on commit.recorded and decision since they're not entity-event-base).

**File:** `agent-plan-tracker/scripts/migrate-events-prehistoric-to-0.1.0.py`

```python
#!/usr/bin/env python3
"""One-shot migration: events.jsonl schema_version 0.0.0-prehistoric → 0.1.0.
Only schema_version field changes; all other fields preserved verbatim."""
import json, sys

EVENTS_FILE = ".agent-plan-tracker/events.jsonl"

with open(EVENTS_FILE) as f:
    lines = [json.loads(l) for l in f]

migrated = 0
for ev in lines:
    if ev.get("schema_version") == "0.0.0-prehistoric":
        ev["schema_version"] = "0.1.0"
        migrated += 1

with open(EVENTS_FILE, "w") as f:
    for ev in lines:
        f.write(json.dumps(ev, separators=(",", ":")) + "\n")

print(f"migrated {migrated} events to schema_version 0.1.0")
```

Run:
```bash
python3 agent-plan-tracker/scripts/migrate-events-prehistoric-to-0.1.0.py
```
Expected: `migrated 69 events to schema_version 0.1.0` (or whatever count is current).

### Step 5: Write the validation script

**File:** `agent-plan-tracker/scripts/validate-events.sh`

```bash
#!/usr/bin/env bash
# Validate every event in events.jsonl against the active schema.
set -euo pipefail
SCHEMA="${1:-agent-plan-tracker/schemas/0.1.0/events.schema.json}"
EVENTS="${2:-.agent-plan-tracker/events.jsonl}"
FAIL=0
LINE_NO=0
while IFS= read -r line; do
  LINE_NO=$((LINE_NO + 1))
  echo "$line" | check-jsonschema --schemafile "$SCHEMA" --stdin 2>/dev/null || {
    echo "FAIL line $LINE_NO: $line" >&2
    FAIL=$((FAIL + 1))
  }
done < "$EVENTS"
if [ "$FAIL" -gt 0 ]; then
  echo "$FAIL events failed validation" >&2
  exit 1
fi
echo "all $LINE_NO events valid"
```

Make executable:
```bash
chmod +x agent-plan-tracker/scripts/validate-events.sh
```

### Step 6: Run validation against migrated events

```bash
bash agent-plan-tracker/scripts/validate-events.sh
```
Expected: `all 69 events valid` (or current count).

If any fail, the failure output will name the line. Inspect → fix schema or fix event → re-run.

### Step 7: Update schema-version.txt

**File:** `.agent-plan-tracker/schema-version.txt`

Change content from `0.0.0-prehistoric` to `0.1.0`.

### Step 8: Commit

```bash
git add agent-plan-tracker/schemas/ agent-plan-tracker/scripts/validate-events.sh \
        agent-plan-tracker/scripts/migrate-events-prehistoric-to-0.1.0.py \
        .agent-plan-tracker/events.jsonl .agent-plan-tracker/schema-version.txt
```

Commit message: `[M1] T3-events-schema-json complete + migrate events to 0.1.0`

## 5. Files to create / modify

- **Create:** `agent-plan-tracker/schemas/0.1.0/events.schema.json`
- **Create:** `agent-plan-tracker/scripts/validate-events.sh`
- **Create:** `agent-plan-tracker/scripts/migrate-events-prehistoric-to-0.1.0.py`
- **Modify:** `.agent-plan-tracker/events.jsonl` (schema_version field on every line)
- **Modify:** `.agent-plan-tracker/schema-version.txt` (`0.0.0-prehistoric` → `0.1.0`)
- **Delete .keep:** `agent-plan-tracker/schemas/.keep`, `agent-plan-tracker/scripts/.keep`

## 6. Verification

After commit:
- `bash agent-plan-tracker/scripts/validate-events.sh` exits 0.
- `cat .agent-plan-tracker/schema-version.txt` shows `0.1.0`.
- `wc -l .agent-plan-tracker/events.jsonl` matches pre-migration count.

## 7. HITL questions

- **Q1**: If validation fails on any existing event, is that schema bug or event bug? Default: schema bug (events are canonical). Adjust schema; re-validate. If event is genuinely malformed (e.g. missing required attribute), that's a deeper issue — surface to user.

## 8. Events this T3 will emit on completion

- `entity.progressed` on T2-ontology (T3 work happened).
- `entity.completed` on T3-events-schema-json.
- `verification.tested` on T3-events-schema-json (test_type: `jsonschema-validate-all-events`).
- `entity.progressed` on M1-bootstrap.
- `commit.recorded` closing the commit.
