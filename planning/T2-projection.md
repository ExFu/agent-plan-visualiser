---
id: T2-projection
plan_kind: thematic
tier: 2
status: active
---

# T2-projection — Views and queries over the event log

**Status**: Active. M1 T3s scheduled.
**Theme**: Derived views — markdown summaries, HTML visualisations, query patterns — over the event log via the SQLite cache and projection.json. **This T2 is the architectural source of truth for the projection / view layer**; T1 only summarises.

---

## 1. Why this T2 exists

The event log is canonical truth. But truth alone isn't navigable. Humans and agents need projections that surface the right information at the right altitude:

- **Agent at session start**: *what's outstanding, what's blocked, what just changed?*
- **Human reviewer**: *visual project state, decision-history traces, milestone progress.*
- **Merge-to-main gate (M3)**: *is the projection clean — any fulcrum-without-decision, orphans, unclosed verifications?*
- **Other agents downstream**: *programmatic API for project state.*

T2-projection is the consumed surface — the part users actually look at and the part automation queries against.

## 2. What lives in this theme

- **projection.json emitter** — script that reads SQLite cache → emits projection.json. Shape defined in T2-storage §3.4; emitter logic here.
- **summary.md emitter** — script that reads projection.json → human-readable markdown digest.
- **HTML view** — `view/index.html` + `view/app.js` + `view/style.css`. Vanilla JS reading projection.json. No build step.
- **First-class projection queries** — pre-baked SQL in `scripts/` (originally proposed as `bin/`; aligned to Claude plugin convention) for common audit, trace, and smell-detection patterns.
- **Cleanliness gate composite query** (M3) — the projection the pre-merge-to-main hook invokes.

## 3. Architecture

### 3.1 Why dynamic-from-data, not static-rebuild

The HTML view reads `projection.json` at load time and renders the project's current state. Templated, debuggable, no hosting needed. Claude opens the HTML directly for the user (browser → file://).

Six reasons this design wins over static-rebuilt HTML:

1. **Data and presentation change at different cadences.** Events arrive continuously; rendering logic is stable. Coupling them via static rebuild forces the stable thing to churn at the unstable thing's rate.
2. **Interactivity falls out for free.** Filter, expand, snapshot-switch all need JS-against-data. Static rebuild means either regenerating HTML per interaction (heavy) or adding JS anyway (so why not start there).
3. **Time-travel is trivial.** Pointing the loader at `snapshots/<date>/projection.json` instead of the live `projection.json` is a one-line change. One template handles all of history.
4. **Debuggability.** Fix the template once, refresh, done. No regeneration cycle.
5. **Token cost.** Generating fresh JSON is mechanical SQL→JSON. Generating fresh HTML burns tokens.
6. **The data layer becomes a first-class API.** `projection.json` is consumable by other clients — a CLI display, an alternative renderer, a future Cowork-native UI, an exported report.

### 3.2 HTML view structure

Pure HTML + vanilla JS + JSON. No build step. Files live in plugin `view/`.

```
view/
  index.html      # shell with view-toggle UI
  app.js          # fetches projection.json, renders both views
  style.css       # styling
```

**Default behaviour:** loads `../.agent-plan-tracker/projection.json` (when opened from inside the plugin context). A query param or selector loads `snapshots/<date>/projection.json` instead for time-travel.

**Two priority views, toggleable:**

**Entity state board.** Entities grouped by derived state (live / dormant / dead / orphaned / unknown). Each entity = a card with:
- ID + tier badge (T1, T2, T3, XT2, M1, etc.)
- Derived-state badge with colour
- Event-type sequence as a visual timeline (one chip per event type in order)
- Click → expand: full event list, linked decisions (clickable for text), attached blockers, milestone membership

**Plan hierarchy tree.** Tree visualisation:
- Root: project node
- Level 1: main T1 + lettered workstream roots (XT1, PT1, ...) + milestones (M1, M2, ...) as orthogonal-axis siblings
- Level 2: T2s (and lettered T2s)
- Level 3: T3s, with milestone-membership shown as badges
- Edges: spawns relationships render as parent→child; depends-on / addendum-to / alongside render as labelled edges between siblings or peers
- Fulcrum-event arcs (rename / supersede / etc.) are visually distinct and clickable for decision text

### 3.3 Markdown summary structure

Human-readable digest. Default sections:

- **Live work** — entities in `live` state, grouped by thematic parent (T2) and milestone (Mn) (two sub-groupings).
- **Blocked** — entities with open blockers attached.
- **Orphaned** — entities with `derived_state = orphaned` requiring resolution.
- **Recently closed** — entities transitioned to `dead` in last N events (configurable, default last commit).
- **Notable patterns** — sequence signals (flapping closures, long-running blockers, fulcrum-without-paired-decision).
- **Milestone progress** — per Mn, scheduled vs completed T3 count plus a per-T3 status line.

Short vs long mode via flag. Default short (top 10 things to know); long is a full state dump.

### 3.4 First-class projection queries (M1 initial catalogue)

Live in `scripts/` (Claude plugin convention) as `.sql` files invoked by Claude via Bash:

- `audit-stalled.sql` — entities in `live` state with no event activity in last N commits.
- `audit-fulcrum-without-decision.sql` — fulcrum events not paired with a `decision` event in the same commit. **Critical** for M3 cleanliness gate.
- `audit-orphans.sql` — entities with `derived_state = 'orphaned'`.
- `trace-decision-history.sql` — given an entity_id, list all decision events touching it (directly or via arcs).
- `timeline-for-entity.sh` — chronological event list for a single entity, formatted readably (shell wraps SQL + formats).

Verification-gap audit (`verification.claimed` without `verification.tested`) deferred until verification ontology overhaul resolves (see T2-ontology §7 Q1).

**Lookup convention** (per T1 §4.11): `scripts/` → `scripts/local/` → generate-from-scratch-and-save. Future agents preferentially use existing scripts to save tokens.

### 3.5 Cleanliness gate composite (M3-scheduled)

The pre-merge-to-main hook (T2-extraction) invokes a composite query that runs multiple audit projections and aggregates pass/fail per smell. Returns non-zero if any blocking smell is present. Default-blocking set is configurable per project.

Initial blocking smells:
- Orphans (any).
- Fulcrum events without paired decisions.
- Unresolved HITL questions referenced by completed plans.
- Reopened entities without follow-up activity within N commits.

Default-warn smells (visible but not blocking):
- Long-running blockers (raised > N commits ago, no progressed/closed).
- Verification.claimed without verification.tested (until overhaul).

Override path: explicit `decision` event listing the smell's offending event_ids with a `reason` attribute explaining the deferral.

> **Correction (2026-06-09, M3 design — supersedes the lists above).** Reframed from tidiness to **record integrity** (protect the cold read): blocking = schema violations, dangling references, unsealed trailing runs, implementation-on-draft, resurrection-without-reopen, fulcrum-without-decision. Orphans, unresolved-HITL-on-completed, and reopened-without-follow-up demote to **warn/dashboard** — visible true state merges freely; surfacing it is the tracker succeeding. The override path is dropped (integrity defects are repaired, not overridden). Blocking/warn lists live in committed `.apv-config.toml`. Spec: [[M3-clean-gate]] §2; build: [[T3-integrity-composite]].

## 4. Swap-out points

- **Pure HTML + vanilla JS for the view layer.** Zero dependencies. Trigger to revisit: views need significant interactive complexity that vanilla JS makes painful. Then consider a minimal framework (lit-html, Preact) — but avoid a build-step-required SPA.

## 5. T3 candidates

### M1-scheduled
- `T3-projection-emitter` — SQL → JSON emitter script.
- `T3-markdown-summary` — projection.json → summary.md.
- `T3-html-view-template` — HTML + JS + CSS (entity state board + plan hierarchy tree).
- `T3-projection-queries-v0` — initial SQL catalogue in `scripts/`.

### Later
- `T3-integrity-composite` (M3 — authored 2026-06-09, supersedes the `T3-cleanliness-gate-projection` candidate) — integrity composite the merge gate invokes.
- `T3-time-travel-snapshots` (M2/M3) — snapshot selector in HTML view, once snapshots exist.
- `T3-html-view-interactivity` (M3+) — filter, search, snapshot selector polish.
- `T3-projection-incremental-emit` (M3+) — performance optimisation.

## 6. Dependencies

- Depends on T2-storage (reads SQLite cache, produces projection.json — shape defined there).
- Depends on T2-ontology (knows event-type and entity-type catalogue for queries and rendering).
- Feeds M3 pre-merge-to-main gate (cleanliness composite is invoked by T2-extraction's hook).

## 7. Open questions

1. **HTML view interactivity scope for M1.** Read-only views only, or include basic filter/search? Lean read-only for M1; ship filter/search in M3+.
2. **Markdown summary verbosity.** Short top-10 by default, long full-dump via flag — both worth shipping.
3. **Projection refresh trigger.** Manual emit-script invocation for M1. Auto-refresh on events.jsonl change later (file watcher in M3+).
4. **Visual style for HTML view.** Bare-functional vs designed? M1 functional; polish later (M3+).
5. **Per-axis grouping in markdown summary.** Group live work by theme (T2) or by milestone (Mn) or both? Both — two sub-sections in Live Work.
6. **Decision arc rendering.** How to visually distinguish fulcrum arcs from natural progression edges in the hierarchy view? Colour, line style, or both?

## 8. Out of scope for this T2

- Real-time / streaming projections.
- Push notifications / RSS feeds of project state.
- Multi-project rollups (cross-repo correlation is T1 §7 out-of-scope).
- Performance metrics, dashboards, BI-style analytics — keep focus on *what's outstanding / what needs attention*, not vanity metrics.
- Interactive editing of plans from within the HTML view — view-only; edits happen in the plan files.
