---
id: T3-entity-accepted
plan_kind: thematic
tier: 3
t2_parent: T2-ontology
milestone: M2-auto-extract
status: draft
---

# T3-entity-accepted — Add draft→accepted lifecycle for all planning entities

**Status**: Draft.
**Sits at**: T2-ontology theme, M2-auto-extract milestone. Prerequisite for `T3-apt-capture-skill` (the skill needs draft/accepted semantics to enforce the "no implementation work on draft entities" rule).

---

## 1. Why

Today, every entity goes `entity.created` → `live`. An agent picking up a T3 can't tell if the plan is still being shaped or if it's ready to execute. Worse: nothing prevents implementation work against a plan that hasn't been reviewed.

The methodology needs a gate between "this entity exists and is being authored" and "this entity is confirmed as real and actionable." All planning entities — plans, inbox items, blockers, HITL questions, implicit work — should start as drafts until confirmed by a human (or, down the line, an overseer agent).

Rules this enables:
- **Draft entities cannot have implementation work done against them.** `entity.progressed` requires accepted state.
- **`entity.extended`** (refining the entity's own document) is always valid, in any state.
- **`entity.accepted`** is the explicit confirmation: "this entity is real, reviewed, and ready to act on."

The M2 capture skill is the first automated consumer of this distinction and needs it to teach the right discipline from day one.

## 2. What

### New event type: `entity.accepted`

- **Meaning**: Entity confirmed as real and actionable. Transitions draft → live.
- **Valid on**: All 5 entity types (plan, blocker, hitl-question, implicit-work, inbox-item).
- **Not a fulcrum event**: No paired `decision` required. Acceptance is a natural forward progression — confirming what's already there, not pivoting.
- **Valid only on draft entities**: Accepting an already-live entity is a no-op/error. Re-activating a closed or dormant entity is `entity.reopened` (which remains a fulcrum).

### New derived state: `draft`

Added to the existing 5 derived states (live, dormant, closed, orphaned, unknown), making 6 total.

| State | After event(s) |
|---|---|
| **`draft`** | **`entity.created`** (new — was `live`) |
| `live` | **`entity.accepted`** (new), `entity.extended` (except from draft — see below), `entity.progressed`, `entity.reopened` |
| `dormant` | `entity.parked` |
| `closed` | `entity.completed`, `entity.cancelled`, `entity.superseded` |
| `orphaned` | Derived: parent closed, child unresolved |
| `unknown` | Ambiguous event chain |

`entity.extended` is **draft-preserving**: extending a draft entity keeps it draft (still authoring, not bypassing acceptance). From any other state, `entity.extended` → `live` (reopens closed/dormant entities, same as `entity.progressed`).

### `entity.extended` — draft-preserving, otherwise reopens

`entity.extended` keeps its current behaviour of transitioning to `live` (which reopens closed/dormant entities — same as `entity.progressed`), with one exception: **extending a `draft` entity keeps it `draft`**. You're still authoring, not bypassing the acceptance gate.

This requires a small conditional in cache-build rather than a flat map entry: `entity.extended` is in `STATE_FROM_EVENT` mapping to `live`, but the state-machine loop skips the transition when current state is `draft`.

### Updated `STATE_FROM_EVENT`

```python
STATE_FROM_EVENT = {
    "entity.created": "draft",      # was "live"
    "entity.extended": "live",      # conditional: preserves "draft" (see loop)
    "entity.accepted": "live",      # NEW
    # entity.renamed: intentionally ABSENT (state-neutral)
    "entity.progressed": "live",
    "entity.completed": "closed",
    "entity.parked": "dormant",
    "entity.cancelled": "closed",
    "entity.superseded": "closed",
    "entity.reopened": "live",
}

# In the state-machine loop:
DRAFT_PRESERVING = {"entity.extended"}
```

### Schema version

This is a meaningful semantic change (new event type, new derived state, changed state mappings). Bump to **`0.3.0`**. New events carry `schema_version: "0.3.0"`; existing events keep their `0.1.0`/`0.2.0` version. The cache builder handles all versions.

## 3. Scope

### In scope
- Add `entity.accepted` to `schemas/0.3.0/events.schema.json` (copy + extend from `0.2.0`).
- Update `cache-build.py` `STATE_FROM_EVENT` as above.
- Update `projection-emit.py` to include `draft_count` in `summary_stats`.
- Update `summary-emit.py` to report draft entities in a dedicated section.
- Update T2-ontology prose (§3.2 event table, §3.10 derived states table, §3.1 total event count).
- Backward compatibility: closed entities stay closed. Entities that become `draft` under the new model (previously `live`) are correctly drafts — they were never explicitly accepted. The operator will manually indicate which to accept.
- Run `repack-validate.sh` green.

### Out of scope
- The capture skill's enforcement logic (`T3-apt-capture-skill` — consumes this).
- The capture-guard hook (`T3-capture-guard-hook`).
- Overseer-agent acceptance workflow (future work).
- Validation that `entity.progressed` only appears on accepted entities — that's a lint rule for the M3 cleanliness gate (and the capture skill's instructions for M2).

## 4. Approach

### D1: Schema file
Copy `schemas/0.2.0/` → `schemas/0.3.0/`. Add `entity.accepted` branch to the `oneOf` discriminator in `events.schema.json`. Same common fields as other entity lifecycle events; no special attributes required.

### D2: cache-build.py
- Update `STATE_FROM_EVENT`: add `"entity.accepted": "live"`; change `"entity.created"` from `"live"` to `"draft"`. `entity.extended` stays mapped to `"live"`.
- Add `DRAFT_PRESERVING = {"entity.extended"}` set. In the state-machine loop, skip the transition when the event type is in `DRAFT_PRESERVING` and current state is `"draft"`.
- The rest of the `entities` materialisation loop (last-write-wins) is unchanged.

### D3: projection-emit.py
- Add `draft_count` to `summary_stats` (alongside `live_count`, `closed_count`, etc.).

### D4: summary-emit.py
- Add a "Draft" section listing entities in draft state, grouped by entity type.

### D5: T2-ontology prose
- §3.2: add `entity.accepted` row to the entity lifecycle events table (not a fulcrum). Note `entity.extended` is now draft-preserving.
- §3.8: update total event count (25 → 26 with analysis events).
- §3.10: add `draft` to the derived states table; update `entity.created` mapping; document the `DRAFT_PRESERVING` exception for `entity.extended`.

### D6: Backward compatibility verification
- Rebuild cache with the new state machine.
- Identify entities whose derived state changed from `live` to `draft` (those with only `created`/`extended` events). Closed entities are unaffected.
- Present the list to the operator. Operator indicates which to accept; emit `entity.accepted` events for those.

## 5. Verification

1. `schemas/0.3.0/events.schema.json` validates all existing events (backward-compatible — `entity.accepted` is additive).
2. `cache-build.py` produces correct `derived_state` for entities with the new state machine.
3. `repack-validate.sh` green end-to-end.
4. `projection.json` includes `draft_count` in stats.
5. `summary.md` shows draft entities in a dedicated section.
6. A test event (`entity.accepted` for a known draft entity) round-trips through the pipeline correctly.

## 6. Dependencies

- T2-ontology — this T3 extends the ontology.
- Feeds `T3-apt-capture-skill` — the skill needs draft/accepted semantics.
- Parallel to `T3-configurable-data-dir` (no dependency).

## 7. Resolved questions

1. ~~**`entity.extended` on closed entities.**~~ **RESOLVED**: `entity.extended` keeps its current reopening behaviour (→ `live`) for closed/dormant entities. Only exception: extending a `draft` entity preserves `draft` (you're still authoring, not bypassing acceptance). Implemented via `DRAFT_PRESERVING` set in the state-machine loop.
2. ~~**Batch acceptance of existing entities.**~~ **RESOLVED**: closed entities stay closed. Entities that become `draft` under the new model (currently `live` with only `created`/`extended` in their history) are correctly drafts — they were never explicitly accepted. The operator will manually indicate which to accept during M2 execution.
3. ~~**`entity.accepted` on `implicit-work`.**~~ **RESOLVED**: not an issue. Implicit-work entities are created and closed in the same commit block (`entity.created` + `entity.completed`), so they pass through `draft` transiently and land at `closed`. No friction, no special case needed.
