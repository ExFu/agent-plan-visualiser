# Worked example — find stalled plans

**Question**: "what's live but hasn't moved?" — plans that were accepted or
progressed and then went quiet.

```bash
sqlite3 "$DATA/cache.sqlite" < "$APV/scripts/audit-stalled.sql"
```

Reading the output: each row is a live entity with its last event date.
Staleness is *signal*, not verdict — a stalled T3 might be blocked (check
`blocker.*` events in its timeline), mid-flight on a branch that hasn't
landed, or genuinely dropped. Follow up per entity:

```bash
bash "$APV/scripts/timeline-for-entity.sh" <entity-id>
```

If the work was quietly abandoned, that's exactly the state the methodology
refuses to leave implicit: either it continues (capture `entity.progressed`
with the next real work), gets deferred honestly (`entity.parked` + a
`decision`), or dies honestly (`entity.cancelled` + a `decision`).
