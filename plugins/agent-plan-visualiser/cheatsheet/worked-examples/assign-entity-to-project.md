# Assign an entity to a sub-project — retrospectively, incl. closed entities

Scenario: a repo registers sub-projects (`[projects.<name>]` in
`.apv-config.toml`) — perhaps it was one project and is now separating —
and historical entities need to be placed under the right project. The
entities may be **closed**; they do not need reopening, and their plan
files do not need to move.

The primitive is **`project.assigned`** (schema 0.6.0): a state-neutral
membership *assertion*. It is a **fulcrum** event — pair it with a
`decision` in the same sealed block.

(Creation-time attribution is automatic in registry repos —
T3-project-attribution: new entities are stamped by location as they are
captured/extracted. This example is the MOVE/retro-history path: re-homing
existing entities, legacy `unassigned` triage, and closed-entity
annotation.)

## Single entity (open or closed)

Append to the capture block (see `/apv-capture` for mechanics), then seal
and commit as usual:

```json
{"event_id": "<uuid4>", "type": "project.assigned", "actor": "al", "confidence": "explicit", "schema_version": "0.6.0", "entity_type": "plan", "entity_id": "T3-old-thing", "attributes": {"project": "website", "from_project": "main", "summary": "Belongs to the website sub-project — predates the registry."}}
{"event_id": "<uuid4>", "type": "decision", "actor": "al", "confidence": "explicit", "schema_version": "0.3.0", "attributes": {"text": "Repo split into website/plugin sub-projects; historical entities re-homed by operator ruling.", "event_ids": ["<the project.assigned event_id>"]}}
```

- `attributes.project` — the registry name (or `main`); required.
- `from_project` — optional; record it when the entity had a prior home.
- The entity must already exist in the log (any event) — the gate's
  referential check rejects assignments naming unknown entities.

## Bulk (separating a repo into sub-projects)

Emit N `project.assigned` events + ONE `decision` whose `event_ids` lists
all N event ids + one seal. One rationale, many arcs — that is the normal
decision shape.

## What the fold does with it

- Latest-recorded assertion wins (latest-knowledge doctrine, same as
  rename/reattach pre-scans).
- Once asserted, the attribute is **authoritative over planning-root
  derivation**: moving the plan file between planning dirs alone will no
  longer change membership. Whether files move at all is your project's
  own choice — the event is the recorded fact either way.
- State-neutral: a closed entity stays `closed` — no resurrection, no
  `entity.reopened` needed, the gate stays green.

## What NOT to do

- **Not `relationship.reattached`** — that is the parent-move primitive
  (milestone/theme axes); the membership fold never reads it, and the gate
  requires its endpoints to be plan entities.
- **Not `entity.extended` carrying `attributes.project` on a closed
  entity** — that trips the resurrection-without-reopen blocker.
- **Not reopen → retag → re-close** — fabricating lifecycle facts to move
  an attribute inverts the gate's philosophy.
