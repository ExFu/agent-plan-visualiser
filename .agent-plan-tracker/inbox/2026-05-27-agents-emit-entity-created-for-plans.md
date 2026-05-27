---
id: 2026-05-27.agents-emit-entity-created-for-plans
entity_type: inbox-item
created_at: 2026-05-27
status: open
candidate_fate: t3
---

# Methodology rule: agents must emit entity.created for plans

When emitting events for a plan that doesn't already exist in `events.jsonl`, the agent should ALWAYS emit an `entity.created` event with the plan's frontmatter as attributes — **even if the entity comes into existence and completes within the same commit** (one-event lifecycle).

## Why

The cache builder materialises `entities.attributes` only from `entity.created` events. Without one, downstream projections lose key metadata (`plan_kind`, `tier`, `tier_prefix`, `t2_parent`, `milestone`, `title`). The workstreams flow view's swimlane routing depends on this metadata; without it, entities fall through to the "Other" swimlane regardless of their actual milestone or T2 parent.

## Surfaced by

The `[M1] all 8 T3s complete` commit emitted `entity.completed` + `verification.tested` for each of the 8 M1 T3s — but no `entity.created`. As a result, those 8 T3s had empty `attributes` in projection.json and were routed to "Other" in the Milestone-mode swimlane view (visible in the screenshot Alastair flagged on 2026-05-27).

## Fix landed

`cache-build.py` now has a frontmatter fallback: when a plan entity has no materialised `attrs` from events, read the plan file's YAML frontmatter directly and use it as `attrs`. This masks the gap so projections work, but events.jsonl history remains incomplete.

## Future work (candidate T3s)

- **Pre-commit lint check** — SQL query against the cache: *"any plan entity whose first event is not `entity.created`?"* — fail commit if yes. Catches the gap at commit time.
- **Document in T2-ontology §3.2** — add a discipline note to the entity-lifecycle events section explicitly stating the "always emit `entity.created` first" rule.
- **Possibly a `lint-events.sh` script** that runs this and other event-shape checks (e.g. fulcrum-without-decision is already separately handled).

## Resurrect when

- The frontmatter fallback in `cache-build.py` becomes a problem (e.g. we need genuine per-event provenance for milestone-tagging changes, or backfill against a project whose plan files diverge from the in-events metadata).
- We start running against external projects (M5 territory) where the events.jsonl history is the ONLY source of truth (no co-located plan files to fall back on).
