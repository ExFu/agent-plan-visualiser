# Worked example — trace why an entity is the shape it is

**Question**: "why was this plan superseded / parked / renamed?" — recover
the reasoning chain without re-reading the planning corpus.

```bash
bash "$APV/scripts/trace-decision-history.sh" <entity-id>
```

This walks the entity's fulcrum events (`renamed`, `parked`, `cancelled`,
`superseded`, `reopened`) and prints each with its paired `decision` text —
the arc metadata that explains the pivot. Every fulcrum is required to have
one; a gap here is itself a finding (and the `fulcrum-without-decision`
audit will be flagging it).

For the full picture around the pivots — what happened between them:

```bash
bash "$APV/scripts/timeline-for-entity.sh" <entity-id>
```

Use this before proposing to revive or re-attempt anything: if an approach
was cancelled with a decision naming why, the next attempt must answer that
why, not rediscover it.
