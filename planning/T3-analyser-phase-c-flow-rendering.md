---
id: T3-analyser-phase-c-flow-rendering
plan_kind: thematic
tier: 3
t2_parent: T2-analyser
milestone: M6-analyser
status: completed
---

# T3-analyser-phase-c-flow-rendering — Saved summaries appear as distinct nodes in the workstreams flow

> **For Claude:** Read T2-analyser §3.10 (Flow-view rendering) for the architectural spec. Phase A landed the analyser pipeline; Phase B persisted summaries as events. Phase C surfaces them in the flow view's swimlane diagram.

**Goal:** Each saved `analysis.live-summary` event renders as a distinct node on its entity's lifeline in the workstreams flow view, placed in the bracketing commit's column. Click → opens the saved summary in the sidebar (reusing Phase B's SavedSummary rendering by event-id, not just by latest-on-entity).

**Architecture:** Pure additive change to `computeFlowLayout` + `renderFlowSVG` in `view/app.js`. No new files. No schema change. No server change.

**Tech stack:** Vanilla JS, SVG. Reuses the existing node/edge rendering infrastructure.

---

## 1. Why this T3

Without it, saved summaries are invisible in the flow view — they only show up when an operator happens to click an entity's LIVE badge. That makes the analyser feel disconnected from project history. Phase C makes summaries first-class graph nodes: visible at a glance, clickable for detail, dimmed/struck through when invalidated (Phase D will make use of that, but the rendering logic should already handle the `valid=0` case).

It also lights up the analytical work itself as part of the project's timeline — you can see when summaries were produced, on what cadence, by which model. Useful for the dogfooding pass + future-self orientation.

## 2. Out of scope

- Cascade invalidation logic — Phase D.
- Visual treatment for *invalidated* summary nodes beyond the dimmed/strike-through rendering rule (Phase D will produce actual invalidation events).
- Editing summaries inline from the flow view.
- A separate timeline/log view of just summary events — flow-view nodes only.
- Bulk-mode "global update" rendering — Phase E.
- Saved-summary highlighting in the entity state board (board view) or plan hierarchy tree.

## 3. Acceptance criteria

- For each `analysis.live-summary` event in events.jsonl, a node renders on the entity's lifeline at the bracketing commit's x-coordinate.
- Summary nodes are visually distinct from event nodes:
  - Shape: square or diamond (not a circle).
  - Color: purple (`#6a1b9a`) for primary, light purple / outlined for derived.
  - Slightly smaller than event nodes (size ≈ 8px) so they don't dominate.
- Hover shows a tooltip: "Summary · primary · <model> · click to view".
- Click opens the summary in the sidebar via `SavedSummary.renderByEventId(panel, entity, event_id)` (a new helper that fetches that specific summary, not just the latest valid on the entity).
- Invalidated summaries (events where the projection marks `valid: 0`) render dimmed with a horizontal strike-through line through the node. Phase C doesn't *produce* invalidation events but must render correctly when one exists.
- Legend updated to show the new summary-node glyphs.
- No regression on existing nodes/edges/tooltips/spines.

## 4. Files to create / modify

- **Modify** `agent-plan-tracker/view/app.js`:
  - `computeFlowLayout` — extend node assembly to include `analysis.live-summary` events as a separate node kind on the entity's lifeline (not merged into composite nodes).
  - `renderFlowSVG` — render summary nodes as squares (primary) / outlined squares (derived) with the new fill colour.
  - `SavedSummary.renderByEventId` — new helper that takes a specific event_id and renders that summary (reuses 90% of `render()`'s code).
  - Legend update.
- **Modify** `agent-plan-tracker/view/style.css`:
  - `.summary-node-primary`, `.summary-node-derived`, `.summary-node-invalidated` rules.

No new files. Server, schema, cache-build all unchanged — the projection already carries the necessary info.

## 5. Implementation steps

### Step 1 — Projection shape audit

Verify that the projection's per-entity summary metadata is sufficient to render a node. Need at minimum: event_id, source (primary/derived), model, freeform_path, commit_recorded_event_id (for x-coordinate lookup), valid flag.

If `projection.json` doesn't carry the full list of summaries per entity (only `latest_summary_by_entity`), extend `projection-emit.py` to emit a `summary_events` array per entity, OR a top-level `summaries[]` keyed by `entity:event_id`. Decide which lookup shape is cheaper for the flow view's render loop.

**Verification:** `python3 -c "import json; print(list(json.load(open('.agent-plan-tracker/projection.json')).keys()))"` shows the summary index.

### Step 2 — Layout integration

In `computeFlowLayout`:
- Iterate `state.events` filtered to `type === "analysis.live-summary"`.
- For each, look up its bracketing commit (`commit_recorded_event_id`) and compute the same x-coordinate as event nodes.
- Compute y-coordinate from `entityRow[entityKey]` (same lifeline).
- Push to a separate `summaryNodes` array on the layout (don't merge with `nodes[]`, since they want a distinct render path).
- For derived summaries, also draw a thin connector line from the derived node back to the primary's node it descends from (use `origin_summary_event_id`).

**Verification:** `console.log(layout.summaryNodes)` after a render shows the expected count + positions.

### Step 3 — SVG render

In `renderFlowSVG`:
- New group `<g class="summary-nodes">` placed after the existing event nodes so summary nodes draw on top.
- Each summary renders as a `<rect>` (square, ~8px side) centred on its x/y.
- Classes: `summary-node summary-node-primary` or `summary-node summary-node-derived`. If `valid === 0`, add `summary-node-invalidated`.
- Hover + click handlers wired (mouseenter shows custom tooltip; click calls `SavedSummary.renderByEventId`).
- Add an SVG `<title>` child for native browser tooltip fallback.

**Verification:** screenshot via Claude_Preview shows a purple square node next to T2-projection's lifeline at the test-save commit column.

### Step 4 — SavedSummary.renderByEventId helper

Phase B's `SavedSummary.render(panel, entity)` reads the *latest* summary for the entity. For Phase C, summary nodes need to open *the specific* summary clicked, not just the latest.

Refactor or add a sibling helper:
- `SavedSummary.renderByEventId(panel, entity, eventId)` — finds the summary by event_id in `projection.summaries` (or scan events fallback), then renders the same panel structure.
- `SavedSummary.render` becomes a thin wrapper: looks up the latest event_id from `latest_summary_by_entity`, delegates to `renderByEventId`.

**Verification:** clicking two different summary nodes (e.g. an old superseded one and the current latest) opens each correctly. Both render the right structured cards + freeform.

### Step 5 — Legend + styles

- Add two legend entries: "primary summary" (filled purple square) and "derived summary" (outlined purple square).
- CSS: `.summary-node-primary { fill: #6a1b9a; stroke: #fff; }`, derived = filled white with purple stroke, invalidated = opacity 0.4 + an SVG `<line>` strike-through across the node.

**Verification:** screenshot shows updated legend.

### Step 6 — Regression check

- Flow view's existing event nodes still render at expected positions/colors.
- Tooltips still work on event nodes.
- Sidebar timeline + plan-md views still work.
- Saved summaries clicked from the analyser sidebar's "View saved summary" action (or from the now-button + Analyse flow) still open correctly.
- Entity-state-board view unaffected.

**Verification:** screenshot + click-through one of each: event node → showDetail panel; summary node → SavedSummary panel; LIVE badge → showLiveStatus.

## 6. Open questions surfaced during execution

(Add new ones during implementation. Resolve before merging.)

- Should summary nodes participate in the entity-spine line (visually connected to the lifeline)? Lean yes — they're temporal nodes on the entity's history, same as events. Implementation: include them when computing spine path points.
- Should derived-summary connectors back to primary be visible by default, or only on hover? Probably on hover to avoid visual noise — defer the connector to a v2 if it adds clutter.
- If a summary event's `commit_recorded_event_id` is null (the summary was saved between commits but somehow not closed by a commit.recorded — shouldn't happen because of the clean-tree guard, but defensive code should still handle it), where does the node go? Lean: render in the "now" column with a different visual treatment to signal "uncommitted summary".

## 7. Verification checklist (pre-commit)

- [ ] Summary nodes appear on lifelines in correct commit columns.
- [ ] Primary vs derived visually distinguishable.
- [ ] Click opens correct summary (not always the latest).
- [ ] Tooltip on hover.
- [ ] Legend includes both glyph types.
- [ ] Strike-through render path exists (won't fire until Phase D produces an invalidation, but the code path runs without error).
- [ ] No regression on event nodes / sidebar / other views.
- [ ] No console errors.
- [ ] repack-validate.sh passes 8/8.

## 8. Provenance

- T2-analyser §3.10 Flow-view rendering (architectural spec).
- M6-analyser §4 phase table.
- T3-analyser-phase-a-ephemeral (precedent for view-extension T3 structure).
- T3-analyser-phase-b-persistence (delivered the events Phase C now visualises).
