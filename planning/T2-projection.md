---
id: T2-projection
plan_kind: thematic
tier: 2
status: draft
---

# T2-projection — Views and queries over the event log

**Status**: Draft. First T3s scheduled into M1.
**Theme**: Derived views — markdown summaries, HTML visualisations, query patterns — over the event log via the SQLite cache and projection.json.

---

## 1. Why this T2 exists

The event log is canonical truth. But truth alone isn't navigable. Humans and agents need projections that surface the right information at the right altitude:
- **Agent at session start**: *what's outstanding, what's blocked, what just changed?*
- **Human reviewer**: *visual project state, decision-history traces, milestone progress.*
- **Merge-to-main gate (M3)**: *is the projection clean — any fulcrum-without-decision, orphans, unclosed verifications?*

T2-projection delivers the view layer. It's the consumed surface — the bit users actually look at.

## 2. What lives in this theme

- **projection.json emitter** — script that reads SQLite cache → emits projection.json. (Shape defined in T2-storage; emitter logic here.)
- **summary.md emitter** — script that reads projection.json → human-readable markdown summary.
- **HTML view** — `view/index.html` + `view/app.js` + `view/style.css`. Vanilla JS, no build step.
- **First-class projection queries** — pre-baked SQL in `bin/` for common audit/trace patterns.

## 3. Approach

### projection.json emitter (M1)

Pure SQL → JSON. No interpretation, no rules. Walks SQLite cache tables, joins entities + relationships + decisions, emits the shape in T2-storage §3.

### Markdown summary (M1)

Human-readable digest. Sections:

- **Live work** — entities in `live` state, grouped by thematic parent (T2) and milestone (Mn).
- **Blocked** — entities with open blockers attached.
- **Orphaned** — derived state = orphaned; requires resolution.
- **Recently closed** — entities transitioned to `dead` in last N events.
- **Notable patterns** — sequence signals (flapping closures, long-running blockers, fulcrum-without-paired-decision).
- **Milestone progress** — per Mn, scheduled vs completed T3 count.

### HTML view (M1)

Two priority views per T1 §4.9, both reading the same projection.json:

**Entity state board.** Entities grouped by derived state. Each entity = a card with:
- ID + tier badge (T1, T2, T3, XT2, M1, etc.)
- Derived-state badge (live / dormant / dead / orphaned / unknown)
- Event-type sequence as a visual timeline
- Click → expand: full event list, linked decisions, attached blockers

**Plan hierarchy tree.** Tree visualisation:
- Root: project
- Level 1: main T1 + lettered workstream roots (XT1, PT1, ...) + milestones (M1, M2, ...) on the orthogonal axis
- Level 2: T2s (and lettered T2s)
- Level 3: T3s, with milestone-membership shown as badges

Toggle between views via JS. No build step.

### First-class projection queries (M1 initial catalogue)

In `bin/`:
- `audit-stalled.sql` — entities in `live` state with no event activity in last N commits.
- `audit-fulcrum-without-decision.sql` — fulcrum events not paired with a `decision` event in the same commit. **Critical** for the M3 cleanliness gate.
- `audit-orphans.sql` — entities with `derived_state = 'orphaned'`.
- `trace-decision-history.sql` — given an entity_id, list all decision events touching it (directly or via arcs).
- `timeline-for-entity.sh` — chronological event list for a single entity, formatted readably.

Verification-gap audit (T1 §4.8) deferred until verification ontology overhaul resolves (T1 §5 Q2).

## 4. T3 candidates

### M1-scheduled
- `T3-projection-emitter` — SQL → JSON emitter.
- `T3-markdown-summary` — projection.json → summary.md.
- `T3-html-view-template` — HTML + JS + CSS.
- `T3-projection-queries-v0` — initial SQL catalogue.

### Later
- `T3-cleanliness-gate-projection` — M3-scheduled. Composite query the merge gate invokes.
- `T3-time-travel-snapshots` — M2/M3, once snapshots exist.
- `T3-html-view-interactivity` — filter, search, snapshot selector. Later.

## 5. Dependencies

- Depends on T2-storage (reads SQLite cache, produces projection.json shape defined there).
- Depends on T2-ontology (knows event-type and entity-type catalogue).
- Feeds the M3 pre-merge-to-main gate.

## 6. Open questions

1. **HTML view interactivity scope for M1.** Read-only views only? Or include basic filter/search? Lean read-only for M1; ship filter/search in M3+.
2. **Markdown summary verbosity.** Short (top 10 things to know) or long (full state dump)? Provide both via a flag? Default short.
3. **Projection refresh trigger.** Manual emit-script invocation for M1. Auto-refresh on events.jsonl change later? File watcher in M3+.
4. **Visual style for HTML view.** Bare-functional vs designed? M1: functional. Polish later (M3+).
5. **Per-axis grouping in markdown summary.** Group live work by theme (T2) or by milestone (Mn)? Probably both — two sub-sections.

## 7. Out of scope for this T2

- Real-time / streaming projections.
- Push notifications / RSS feeds of project state.
- Multi-project rollups.
- Performance metrics, dashboards, BI-style analytics.
