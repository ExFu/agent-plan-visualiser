---
id: 2026-05-30.progressed-after-completed-state-flip
entity_type: inbox-item
created_at: 2026-05-30
status: closed
candidate_fate: methodology-note
---

# Methodology rule: don't emit entity.progressed on a completed T3 — scope it to the T2 instead

## The smell

T3-cache-build was emitted as `entity.completed` + `verification.tested` during M1 bootstrap (commit `b3000001` / `b3000002`). Later, during the unified-edges fix (commit `87fe019` on 2026-05-27), the orchestrator emitted `entity.progressed` on T3-cache-build to document additions to `cache-build.py` (DROP TABLE in `init_db` + frontmatter-derivation pass).

That `entity.progressed` flipped the T3's derived_state from `dead` back to `live` per the cache-build state machine:

```python
STATE_FROM_EVENT = {
    "entity.created": "live",
    "entity.extended": "live",
    "entity.progressed": "live",      # ← any of these on a dead entity = reanimation
    "entity.completed": "dead",
    ...
}
```

Discovered 2026-05-30 by Al asking "T3 cache_build seems to still be live. Is that correct?" — verified with a single-row query against the cache:

```sql
SELECT entity_id, derived_state, event_type_sequence FROM entities
WHERE entity_id='T3-cache-build';
-- T3-cache-build | live | ["entity.completed","verification.tested","entity.progressed"]
```

## Why it's wrong

The work in question (frontmatter-derived edges + DROP TABLE in `init_db`) wasn't a continuation of T3-cache-build's deliverable. It was architectural extension to **T2-storage's** relationships convention, which happened to land in cache-build.py because that's where the code lives. T2-storage was emitted `entity.progressed` correctly in the same commit. T3-cache-build should not have been.

This is a recurring failure mode for agents: when emitting events for a commit that *touched* a file owned by a completed T3, the agent reaches for the T3 by name rather than tracing back to the live T2 (or T1) whose architecture the change actually advanced.

## Rule going forward

1. **A completed T3 is a closed history.** Don't emit any further events on it unless you're explicitly reopening it via `entity.reopened` (a fulcrum event that requires a paired `decision`).

2. **Post-completion work scoped to the T3's *theme* belongs on its T2 parent**, not back-onto the T3. `entity.progressed` / `entity.extended` events for that theme target the T2.

3. **Post-completion work that's genuinely a continuation of the T3** (rare — usually means the T3 was prematurely closed) → emit `entity.reopened` + paired `decision` explaining why we're reopening rather than spawning a fresh T3.

4. **Bug-fix follow-on to a completed T3's deliverable** → spawn a follow-on T3 (e.g. `T3-cache-build-followup-N`) with its own lifecycle. Don't reanimate.

## Workaround applied 2026-05-30

Emitted a second `entity.completed` event on T3-cache-build with a clarifying note. The state machine accepts double-completion (idempotent on `dead`). State flips back to `dead`. Captures the audit trail without rewriting history.

## Lint check (future)

```sql
SELECT entity_id, event_type_sequence
FROM entities
WHERE entity_type = 'plan'
  AND derived_state = 'live'
  AND event_type_sequence LIKE '%entity.completed%'
  AND event_type_sequence NOT LIKE '%entity.reopened%';
```

Should return zero rows. Any row indicates either: (a) a missing reopen+decision before the post-completion event, or (b) the post-completion event was scope-creep and belongs on the T2 instead.

## Resurrect when

Next time an agent emits events on a commit that touches files owned by a completed T3. Reference this inbox item in the relevant memory / methodology doc so the discipline carries forward.
