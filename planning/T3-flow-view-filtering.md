---
id: T3-flow-view-filtering
plan_kind: thematic
tier: 3
t2_parent: T2-projection
milestone: M1-bootstrap
status: draft
---

# T3-flow-view-filtering — Isolate / hide / collapse / lifecycle-filter for the workstreams-flow view

> **For Claude:** Four interaction features bundled into one T3 because they share the same code surface (`view/app.js`, `view/style.css`, `view/index.html`) **and** a single new substrate: a `state.flowFilters` object + one filtering pre-pass that every feature mutates and the render path consults. Splitting into separate T3s would force them to coordinate on the same mutable state — the cross-plan coupling the methodology warns against. This mirrors the bundling rationale of [[T3-flow-view-density]]. No architectural change to the projection/event layers — pure client-side rendering/interaction over the layout established by [[T3-html-view]] and refined by [[T3-analyser-phase-c-flow-rendering]] and [[T3-flow-view-density]].
>
> Read [[T2-projection]] §3.2 (HTML view structure) for the established view contract. The view is dynamic-from-`projection.json`, vanilla JS, no build step — keep it that way.

---

## 1. Why (the job)

At a project's natural scale (this repo already has ~38 entities × dozens of commits) the flow view becomes a wall of lifelines. The operator's real questions are narrow: *"show me just this entity and what it's connected to"*, *"mute these swimlanes I don't care about right now"*, *"summarise that whole section to one node but keep its linkage visible"*, *"hide everything that's done so I only see live work."*

All four are **focus operations** — they reduce what's drawn without touching the data. They belong together because they answer the same underlying need (reduce noise to reason about a subset) and because they all reduce to *"which entities/sections render, and how."*

This delivers the interactivity reserved as `T3-html-view-interactivity` in [[T2-projection]] §5, scoped to the four focus operations the operator actually asked for (search/snapshot-selector remain out of scope — §6).

## 2. What (the four deliverables)

Each deliverable is independently verifiable. Build them in the order below; D1 lays the substrate the others reuse.

### D1 — Filter-state substrate + lifecycle filter (feature 4)

**Substrate.** Add one persistent object to the global `state` (already survives `switchView` re-renders):

```js
state.flowFilters = {
  hiddenEntities:    new Set(),  // entity keys (`type:id`) muted via the eye toggle — KEEP a greyed gutter row
  hiddenSwimlanes:   new Set(),  // swimlane keys muted via the section eye toggle (bulk-mutes members)
  collapsedSwimlanes:new Set(),  // swimlane keys collapsed to a placeholder (D3)
  isolateRoot:       null,       // { kind: "entity"|"swimlane", key } or null (D4... D2)
  lifecycle:         "all",      // "all" | "open" | "closed"
};
```

Introduce one pure pre-pass, called at the top of `computeFlowLayout`:

```js
// Returns { laidOut: Set<ekey>, suppressed: Set<ekey>, collapsed: Set<swimlaneKey> }
//   laidOut    — entities that get a row + y-coordinate
//   suppressed — subset of laidOut whose SVG marks (spine/nodes/continuation/badge)
//                are skipped but whose greyed gutter row stays (the eye-hide set)
//   collapsed  — swimlanes rendered as a single placeholder row (D3)
function computeFlowVisibility(projection, filters, mode) { ... }
```

Composition rules (order matters):
1. Start from all entities.
2. **lifecycle filter** removes entities entirely (no row): `open` keeps `derived_state !== "dead"`; `closed` keeps `derived_state === "dead"`; `all` keeps everything. (Rationale for "dead == closed": see Decision DEC-1.)
3. **isolation** (if `isolateRoot` set) intersects with the related set (D2) — removes entirely.
4. **eye-hide** (`hiddenEntities` ∪ members of `hiddenSwimlanes`) → stays laid out but marked `suppressed` (greyed row, no marks). This is deliberately *not* a layout removal so the toggle stays reachable in-place.
5. **collapse** (`collapsedSwimlanes`) → members removed from individual layout; one placeholder row added for the swimlane (D3).

**Lifecycle filter UI.** A segmented selector in the flow `sub-toolbar` (next to the milestone/t2 toggle): `All · Open · Closed`. Clicking sets `state.flowFilters.lifecycle` and re-renders via `switchView("flow")`. Active segment styled with the existing `.sub-toolbar button.active` convention.

**Verification D1:**
- With `Open` selected, no `dead` entity has a lifeline/node in the SVG; meta line still reflects full counts (counts describe the project, not the filtered view — note in legend).
- `Closed` shows only `dead` entities.
- `All` restores the full view. Selection persists across a milestone↔t2 mode switch.

### D2 — Isolation + unisolate (feature 1)

**Related set.** For an entity root, the related set = `{root} ∪ ancestors(root) ∪ descendants(root)` walked transitively over `relationships` of `type === "spawns"` (both `source: "event"` and `"frontmatter"` edges — the unified set already used by `_related1Hop`). Ancestors = follow `to === root` edges upward; descendants = follow `from === root` edges downward. For a **swimlane root**, the related set = union of the related sets of all the swimlane's member entities (so isolating a section keeps the section plus everything it links to, in or out).

**Triggers (two paths, per the feature request):**
1. **Gutter icon.** Each gutter entity row and each swimlane header gets a small **isolate** icon (a target/crosshair glyph) *alongside* the eye icon. Click → `isolateRoot = {kind, key}`, re-render.
2. **Node click.** The existing node-click opens the detail panel (`showDetail`). Add an **"⌖ Isolate to this"** button at the top of that panel that sets `isolateRoot` to the clicked node's entity and re-renders.

**Unisolate.** When `isolateRoot` is set, show a prominent banner/button in the `sub-toolbar` area: `Isolated: <id> ✕ Clear`. Clicking clears `isolateRoot` and re-renders. Also expose the same clear on `Esc`.

**Interaction with other filters:** isolation composes by intersection (D1 step 3) — a lifecycle filter still applies inside an isolated set; eye-hidden entities inside the set still render greyed.

**Verification D2:**
- Isolating a mid-tree entity (e.g. `plan:T2-projection`) shows only it, its T1 ancestor, and its T3 descendants — everything else gone.
- Node-click "Isolate to this" produces the same set as the gutter icon for that entity.
- "Clear" / `Esc` restores the prior view (other filters preserved).
- Isolating a swimlane keeps the section's members + their link targets.

### D3 — Per-entity & per-section eye toggle (feature 2)

**Per-entity.** Each gutter row gets an eye icon. Toggling adds/removes the entity key in `hiddenEntities`. A hidden entity: gutter row stays but greyed + eye-closed glyph; SVG spine, nodes, continuation line, and now-badge are skipped (the entity is in `suppressed`, not removed — so the row and its toggle stay put). Reduces graph noise while staying reversible in-place.

**Per-section.** Each swimlane header gets an eye icon. Toggling adds/removes the swimlane key in `hiddenSwimlanes`, which bulk-suppresses every member (each member's marks skipped; rows greyed). Toggling back restores all.

**Verification D3:**
- Hiding one entity removes its marks but leaves a greyed, clickable row that toggles it back.
- Hiding a section greys all its rows and removes all its marks in one click; un-hiding restores them.
- A spawn edge whose *other* end is still visible renders to the suppressed entity's reserved row position? No — suppressed entities draw no node, so edges into them are dropped (they reduce noise). Edges between two visible entities are unaffected.

### D4 — Section collapse with placeholder spawn-target node (feature 3)

**Collapse control.** Each swimlane header gets a caret (▸ collapsed / ▾ expanded) toggling the swimlane key in `collapsedSwimlanes`.

**Collapsed rendering.** A collapsed swimlane contributes **one** placeholder row instead of its member rows:
- The gutter shows the section header with a ▸ and a member count (e.g. `T2-ontology ▸ (4)`).
- The SVG draws a single **placeholder node** (distinct shape — a hollow rounded square with a count label) on that row, positioned at the x of the earliest commit column in which any member has an event (so it sits where the section's activity begins).
- **Spawn edges are re-routed:** any `spawns` edge with an endpoint that is a member of a collapsed swimlane has that endpoint replaced by the swimlane's placeholder node. Edges fully internal to the collapsed swimlane are dropped. This realises "something within that section is linked, but we don't bother expanding."

**Verification D4:**
- Collapsing a section that other entities spawn into shows dashed spawn edges terminating at the placeholder node, not disappearing.
- The placeholder shows the member count and a tooltip listing members; clicking it expands the section (removes from `collapsedSwimlanes`).
- An edge between two collapsed sections routes placeholder→placeholder.
- Expanding restores per-member lifelines and original edge endpoints.

## 3. Implementation notes / touch-points

- **`computeFlowLayout`** — call `computeFlowVisibility` first; iterate only `laidOut` entities for rows/`entityRow`/`entityNodes`; tag suppressed; build collapsed placeholder rows + a `swimlanePlaceholder[swimlaneKey] = {x, y, members}` map. When building `relEdges` and `continuations`, map any endpoint ekey that belongs to a collapsed swimlane to its placeholder node, and drop endpoints that are suppressed or fully-internal-to-collapsed.
- **`renderFlowSVG`** — skip spine/nodes/continuation/now-badge for suppressed entities; draw placeholder nodes for collapsed swimlanes; everything else unchanged.
- **`renderFlowGutter`** — each row/header gains a small control cluster (isolate + eye [+ caret for headers]). Use `event.stopPropagation()` so control clicks don't trigger the row's open-markdown handler. Greyed style for suppressed rows; collapsed header shows caret + count.
- **`renderFlow`** — render the lifecycle selector + isolation banner in/near the `sub-toolbar`; wire `Esc` to clear isolation.
- **Re-render** — all toggles call `switchView("flow")` (cheap full re-render; the view already re-renders wholesale on mode switch). No incremental-DOM needed at this scale.
- **Mode-switch caveat:** `hiddenSwimlanes`/`collapsedSwimlanes`/swimlane-`isolateRoot` are keyed by swimlane key, which differs between milestone and t2 modes. On mode switch, clear the swimlane-keyed sets (keep entity-keyed `hiddenEntities`, entity `isolateRoot`, and `lifecycle`, which are mode-independent). Document this in a code comment.
- **No projection/schema/event-shape changes.** This is view-only.

## 4. Decisions to log (paired with the implementing commit)

- **DEC-1 — "closed" ≙ `derived_state === "dead"`.** The lifecycle filter's Open/Closed split treats only `dead` as closed; `dormant`/`orphaned`/`unknown` count as Open ("still needs a human's eye"). Rationale: matches the operator's framing ("hide everything that is closed = show everything still live"), and `dead` is the single unambiguous terminal state in the state machine. If a finer split is wanted later, promote to a multi-select.
- **DEC-2 — eye-hide keeps a greyed row; lifecycle/isolation remove rows.** Rationale: a per-entity mute must stay reversible *in place* (you hid it, you can un-hide it where it was); a view-wide filter has its own always-visible toolbar control to undo it, so leaving ghost rows would just be noise.

## 5. Out of scope (this T3)

- Free-text search / fuzzy entity finder (separate future T3).
- Snapshot / time-travel selector (separate; needs snapshots to exist).
- Persisting filter state across reloads (localStorage) — could come later; v1 is session-only.
- Any change to the Entity-state-board or Plan-hierarchy-tree views — flow view only.
- Edge rendering for non-`spawns` relationship types (depends-on/addendum) — not yet drawn anywhere; unchanged here.

## 6. Verification (whole-T3)

Manual, in-browser (the view's only runtime). Serve repo root, open `agent-plan-tracker/view/index.html`, flow view:
1. D1: lifecycle All/Open/Closed behaves per D1 verification.
2. D2: isolate via gutter icon and via node-panel button; unisolate via banner and Esc.
3. D3: eye-hide an entity and a section; confirm greyed rows + restored toggles.
4. D4: collapse a spawned-into section; confirm placeholder + re-routed edges; expand restores.
5. Regression: milestone↔t2 mode switch still works; analyser summary nodes/now-badges still render; no console errors.
Screenshot each as evidence (no automated test harness exists for the view; [[T2-projection]] §7 keeps the view manually verified for now).
