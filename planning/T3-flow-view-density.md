---
id: T3-flow-view-density
plan_kind: thematic
tier: 3
t2_parent: T2-projection
milestone: M1-bootstrap
status: completed
---

# T3-flow-view-density — Compact, navigable flow view with sticky entity column + spawn-aware sidebar

> **For Claude:** Three independent improvements bundled into one T3 because they share the same code surface (`view/app.js`, `view/style.css`, `view/index.html`) and are all about making the existing workstreams-flow view usable at a project's natural scale (10+ commits, 20+ entities). No architectural change — pure rendering / interaction polish over the layout already established by T3-html-view and refined by T3-analyser-phase-c-flow-rendering.

**Goal:** The workstreams-flow view stays navigable as commit-count and entity-count grow:
1. (A) The entity-name column on the left stays in view when the SVG scrolls horizontally — and the column is itself user-resizable.
2. (B) Commit columns are radically denser (vertical labels, ~40px columns) so 3-4× more commits fit on screen; commit labels are now hover-tooltipped and click-to-detail.
3. (C) Clicking an event composite node surfaces the entity's **spawn relationships** (parents + children) in the sidebar, so the graph is navigable by click as well as by visual edge-following.

**Architecture:** Single-SVG approach for (A) with a sticky HTML overlay rendering the entity-name + swimlane-label "gutter" on top of `.flow-svg-wrap`. The SVG keeps swimlane backgrounds (which must span full width) and all data nodes; the overlay does only labels, sticks via `position: sticky; left: 0` inside the scrolling wrapper. (B) replaces the rotated `-28°` commit-label `<g transform>` with a vertical `-90°` rotation and shrinks `COMMIT_WIDTH` from 150 to 44; commit labels become clickable hit-targets with their own pointer-event group. (C) adds a `_spawnRelationshipsSection` helper called from both `showDetail` and `showLiveStatus` (the latter via `SavedSummary._renderInner`'s timeline pane or appended below the saved-summary cards).

**Tech stack:** Vanilla JS, SVG, CSS. No new dependencies. No build step. No backend changes.

---

## 1. Why this T3

The workstreams-flow view is the project's primary visual surface (T2-projection §3.2, refined as the default view in commit `21f6167`). It works for the current dogfooding scale (~10 commits, ~20 entities) but already strains:
- Horizontal scrolling loses the entity-to-lifeline mapping the further right you go — the leftmost label column scrolls out with the rest of the SVG.
- Each 150px-wide commit column accommodates a `-28°` rotated label, which makes the SVG much wider than the data demands. A normal-sized project (50+ commits) would scroll for screens.
- The sidebar's `showDetail` shows events at the (entity, commit) intersection but doesn't surface the entity's spawn relationships — the graph is currently navigable only by following visual edges, which is slow and easy to misread.

Each of these is a friction point for the agent-memory use case the tracker is meant to serve (T1 §3.3) — an agent re-orienting to a project should be able to scan its history fast, and a human reviewer should be able to pivot from "what happened in commit X" to "who spawned this plan" in one click. This T3 closes those three gaps without changing the data layer or the view architecture.

## 2. Out of scope

- **Time-travel snapshot selector.** Still M2/M3 (T2-projection §5).
- **Filter / search.** Still M3+ (T2-projection §5).
- **Vertical sticky for swimlane labels during vertical scroll.** Out of scope; the flow-svg-wrap currently uses height `80vh`, vertical scrolling is rare in practice and not part of this T3's brief.
- **Restructuring `showDetail` into a state machine.** Keep the additive pattern that Phase A/B/C used — small composable helpers inserted into the existing render function.
- **Spawn-relationship visual edges in the SVG itself.** Edges are already drawn (relEdges); this T3 only adds the click-to-list affordance in the sidebar.
- **Inline editing of entity names in the gutter.**
- **A separate per-commit detail view.** Click-on-commit-label reuses the same sidebar pattern as click-on-node.

## 3. Acceptance criteria

### Task A — Sticky + resizable entity gutter
- [ ] When the user scrolls the flow SVG horizontally, the leftmost gutter showing swimlane labels + per-entity labels remains visually pinned at left edge.
- [ ] The gutter is resizable via a thin drag handle on its right edge. Handle is subtler than the right-pane resizer (narrower default, fades in on hover).
- [ ] Minimum gutter width 80px, maximum 360px, default ~220px. Below ~140px entity-ids truncate with ellipsis; full id remains in `<title>` (already exists).
- [ ] Vertical alignment between the gutter rows and the SVG entity lifelines is exact (same y-coordinates used to compute both).
- [ ] Clicking an entity name in the gutter opens that entity's plan markdown in the sidebar (preserves the current `showPlanMarkdown` behaviour).
- [ ] No regression on swimlane background banding (the alternating even/odd swimlane bands still span the full SVG width).

### Task B — Compact commit labels + click affordance
- [ ] Commit labels render vertically (`rotate(-90)`), readable bottom-to-top, anchored just above the swimlane area.
- [ ] `COMMIT_WIDTH` shrinks from 150 to ~44px (verify visually; the project's events.jsonl has 12 commits so all should fit without scroll on a typical screen).
- [ ] Commit-label text truncates to ~32 chars + ellipsis. Full message available in `<title>` tooltip + sidebar click.
- [ ] Hovering a commit label shows the existing tooltip (re-use `showTooltip` / `flow-tooltip`) with the full commit message + date.
- [ ] Clicking a commit label opens a per-commit detail view in the sidebar: full commit message, date, author, and the full list of events that landed in that commit (across all entities), each as an event-pill + entity badge.
- [ ] Existing per-commit dashed guideline behaviour preserved.

### Task C — Spawn-relationship navigation in sidebar
- [ ] After clicking an event composite node (`showDetail`), the sidebar appends a "Spawn relationships" section listing:
  - **Parents** — entities where `r.to === ekey && r.type === "spawns"`. Each renders the parent entity_id with its derived_state badge.
  - **Children** — entities where `r.from === ekey && r.type === "spawns"`. Same render.
  - Click on a parent/child item calls `showLiveStatus(otherEntity)` to navigate to that entity (matches the LIVE-badge click affordance for consistency).
  - Each row visually distinguishes `source: "event"` vs `source: "frontmatter"` derivations (small marker — e.g. dotted underline or a tiny tag).
- [ ] The section is also surfaced from `showLiveStatus` (timeline branch — when no saved summary exists) — same helper, appended below the timeline.
- [ ] The section is also surfaced in the SavedSummary view, appended below the structured/freeform/timeline toggle group, so navigation works regardless of which sidebar variant is active.
- [ ] Empty case: if both parents and children arrays are empty, the section is not rendered.

### Bonus — Pink/created-event colour tweak
- [ ] `--pill-created` in style.css updated from `#c2185b` to `#e91e63` (Material vivid pink — distinct from fulcrum reds `#c62828`).
- [ ] Matching update in app.js `dominantEventColor` (created branch).
- [ ] Matching update in app.js flow-view legend SVG for "created".
- [ ] CSS comment on the pill variable tightened to "vivid pink — birth (distinct from fulcrum reds)".

## 4. Files to modify

- `agent-plan-tracker/view/app.js`
  - `renderFlow` — restructure split layout: add a sticky-gutter `<div>` overlay inside `.flow-svg-wrap` (or sibling — see step 1) + a small gutter-resize handle. Wire the gutter resize.
  - `computeFlowLayout` — shrink `COMMIT_WIDTH` to 44; rotate commit-label angle to `-90`; reserve `TOP_MARGIN` for vertical labels; expose computed entity rows (already in `entityRow`) for the overlay to consume.
  - `renderFlowSVG` — drop in-SVG `<text class="entity-label">` and `.swimlane-label` rendering (move those to the HTML overlay); keep swimlane bg rects; replace the rotated `-28°` commit-label `<g>` with `-90°` and add hover/click handlers (`showTooltip` on mouseenter, `showCommitDetail` on click); keep dashed column guideline.
  - New: `renderFlowGutter(layout, overlayEl)` — populates the HTML overlay with swimlane label divs + per-entity label rows. Uses the same y-coordinates as the SVG. Handles click to `showPlanMarkdown`.
  - New: `showCommitDetail(commit, events)` — sidebar view: full commit metadata + per-event list across all entities.
  - New: `_spawnRelationshipsSection(entity)` — returns HTML string with parent + child lists. Walks `state.projection.relationships` (already loaded). Distinguishes `source` field visually.
  - `showDetail` — append `_spawnRelationshipsSection(entity)` after the events list.
  - `showLiveStatus` — append `_spawnRelationshipsSection(entity)` after the timeline.
  - `SavedSummary._renderInner` — append `_spawnRelationshipsSection(entity)` after the toggle row's panes.
  - `dominantEventColor` — `#c2185b` → `#e91e63` (created branch).
  - Legend SVG `<circle ... fill="#c2185b"/>` → `#e91e63`.
  - `makeResizable` — generalise to accept min/max + a CSS-property mode (sidebar=flex-basis, gutter=width), OR add a sibling `makeGutterResizable` if generalising looks ugly.

- `agent-plan-tracker/view/style.css`
  - New `.flow-gutter`, `.flow-gutter-row`, `.flow-gutter-swimlane`, `.flow-gutter-drag-handle` rules — sticky positioning, truncation, hover affordance.
  - `--pill-created` colour update + tightened comment.
  - Possibly tweak the existing `.flow-svg-wrap` to be `position: relative` so absolute positioning works for the overlay.

- `agent-plan-tracker/view/index.html` — likely zero changes (overlay is created in JS).

## 5. Implementation steps

### Step 1 — Sticky entity gutter (Option-2 from the brief: HTML overlay)

Decision: HTML overlay sticky inside the scroll container. Rationale: simpler than two synchronised SVGs; reuses CSS `position: sticky; left: 0`; vertical alignment is straightforward because the overlay and the SVG share the same y-coordinates (computed in `computeFlowLayout`).

- In `renderFlow`, after creating `svgWrap`, create a `<div class="flow-gutter">` and append it to `svgWrap` BEFORE the SVG. The SVG continues to render swimlane background rects (which need to span the full SVG width). Move `<text class="entity-label">` and `<text class="swimlane-label">` rendering OUT of the SVG and into the gutter as DOM elements absolutely positioned by their swimlane / entity y-coord.
- The gutter is `position: sticky; left: 0` with a backing colour so commits scrolling under it are obscured; `z-index` above the SVG layer.
- The flow-gutter has width set via JS (CSS custom property `--gutter-width`, default 220px). The SVG keeps its viewBox + width unchanged; we just visually pin the gutter on top.
- The gutter's right edge has a thin drag handle (`.flow-gutter-drag-handle` — 4px wide, default border-only, on hover gets a slight bg highlight) that updates `--gutter-width` between 80 and 360.

Verification: open the view → scroll right → gutter remains pinned, entity names visible. Drag the handle → gutter widens/narrows. Below ~140px the labels truncate with ellipsis but tooltips still show full id.

### Step 2 — Compact commit labels + click-on-commit

- In `computeFlowLayout`: `COMMIT_WIDTH = 44`. Bump `TOP_MARGIN` to ~150 to give vertical labels room (32-char truncated label at -90° needs ~140px of vertical space at 10px font).
- In `renderFlowSVG`: replace the per-commit `<g transform="translate(x, top-12) rotate(-28)">` with `translate(x, top-8) rotate(-90)`. Add a `class="commit-label-hit"` rectangle (transparent, covering the label area + a bit of padding) on each commit, with mouseenter/mouseleave/click handlers.
- Hover handler: builds a fake `n`-like object with `entity` = a synthetic `{entity_id: "(commit)"}`, `events: [{type: "commit.recorded", attributes: {...}}]`, `commitMessage`, `commitDate` and calls `showTooltip` with a small adapted payload. (Alternative: write a dedicated `showCommitTooltip(e, c)` to avoid coupling to the node tooltip shape.) Go with the dedicated tooltip for clarity.
- Click handler: `showCommitDetail(commit, events)`. New sidebar render:
  - Title = commit short hash + first-line message (truncated reasonably).
  - Meta = full date, author.
  - For each event bracketed by this commit, list as event-pill + entity-id badge + summary. Walk `state.events` for events with `eventToCommit.get(ev.event_id) === commit.event_id`. (Need to expose `eventToCommit` and the full per-commit event list from `computeFlowLayout` or recompute lazily.)

Verification: the 12-commit dogfooding events.jsonl fits horizontally on a 1440px-wide laptop screen with no scroll, vs the current ~1900px width requiring scroll. Hover label → tooltip. Click label → sidebar shows commit detail.

### Step 3 — Spawn-relationship section

- Helper `_spawnRelationshipsSection(entity)` returns an HTML string:
  - `entityKey = "${entity.entity_type}:${entity.entity_id}"`.
  - Walk `state.projection.relationships`, partition into parents (where `r.to === entityKey && r.type === "spawns"`) and children (where `r.from === entityKey && r.type === "spawns"`).
  - If both arrays empty → return `""`.
  - For each row: render `entity_id` + `derived_state` badge + a tiny tag `event` (filled) vs `frontmatter` (outlined) based on `r.source`.
  - Each row has `data-target-key` for the click handler.
- After painting, attach `click` handlers on `.spawn-rel-row` elements: look up `state.projection.entities[targetKey]`, call `showLiveStatus(target)`.
- Call sites:
  - At the bottom of `showDetail`: append `_spawnRelationshipsSection(n.entity)` then attach click handlers.
  - At the bottom of `showLiveStatus`'s timeline branch: same.
  - At the bottom of `SavedSummary._renderInner`: same. (Insertion point: after the regenerate-actions row.)

Verification: click an event composite node on T2-projection (which spawns multiple T3s) → sidebar shows the 4 T3 children. Click one of them → sidebar pivots to that T3's saved summary / timeline. Click an entity with no spawn edges (e.g. an inbox-item) → section not rendered.

### Step 4 — Pink/created colour tweak

- `style.css`: `--pill-created: #c2185b;` → `#e91e63;` and tighten the comment.
- `app.js` `dominantEventColor`: `if (types.has("entity.created")) return "#c2185b";` → `"#e91e63"`.
- `app.js` legend SVG inline: `fill="#c2185b"` for the created circle → `#e91e63`.
- `grep -n c2185b` should return no matches in `view/`.

Verification: created-event composite nodes render with the new pink; legend matches.

### Step 5 — Smoke test via Claude_Preview

Load `http://localhost:8765/agent-plan-tracker/view/index.html`, flow view default. Verify each acceptance criterion. Take a screenshot.

### Step 6 — Repack + commit cadence

After each major chunk (A / B / C / bonus + smoke):
- `bash agent-plan-tracker/scripts/repack-validate.sh` → expect 8/8 pass.
- Commit with the appropriate per-task message.
- Emit events to `events.jsonl` capturing what just landed.

## 6. Files for events emission

Each commit lands its own event batch in `.agent-plan-tracker/events.jsonl`:

1. **T3 + planning commit** — `entity.created` on `T3-flow-view-density` (with full frontmatter in attributes), `relationship.spawns` from `T2-projection` to this T3, `commit.recorded`.
2. **Task A commit** — `entity.progressed` on this T3, `commit.recorded`.
3. **Task B commit** — `entity.progressed` on this T3, `commit.recorded`.
4. **Task C commit** — `entity.progressed` on this T3, `commit.recorded`.
5. **Smoke-test + pink-bonus commit** — `verification.tested` on this T3, `entity.completed` on this T3, `entity.progressed` on `T2-projection`, `commit.recorded`.

All events at `schema_version: "0.2.0"`. Per CLAUDE.md auto-memory: include `entity.created` for any new entity that first appears, with frontmatter as attributes.

## 7. Open questions surfaced during execution

(Add new ones during implementation. Resolve before merging.)

- **Q1:** Should the gutter resizer adjust the SVG's effective rendered width (i.e. the SVG visually shrinks to make space for the wider gutter) or just overlap further into the SVG (commits hidden under the gutter)? Lean: overlap further — simpler, the SVG's own left margin already gives the gutter ~230px of "free" space to start with, so the overlay can live within that without changing SVG geometry. If gutter widens beyond `LEFT_MARGIN` the swimlane-band starts to peek out from under it, which is acceptable visually.
- **Q2:** Should commit labels also rotate the other way (`rotate(90)` reading top-to-bottom) to match typical Gantt-chart conventions? Lean: `-90` (bottom-to-top), matching the "newer right" convention so the most recent commit's label reads up-and-to-the-right. Validate empirically with a screenshot.
- **Q3:** For commit detail in the sidebar, should we render the commit's full message body (not just first line) if `attributes.message_body` is present? Lean: render whatever's in `message_first_line` for now — projection.json currently only carries that. If full bodies become useful later, extend `cache-build.py` separately.

## 8. Verification checklist (pre-commit)

- [ ] `bash agent-plan-tracker/scripts/repack-validate.sh` → 8/8 pass.
- [ ] Flow view loads with zero console errors.
- [ ] Task A: scroll right → gutter sticks. Drag gutter handle → resize works. Click entity name → plan markdown opens.
- [ ] Task B: commit labels vertical. ~12 commits visible without horizontal scroll on a 1440px screen. Hover label → tooltip. Click label → commit detail in sidebar.
- [ ] Task C: click event node → spawn section shows parents+children. Click saved-summary node → spawn section also shows. Empty entity → section absent.
- [ ] Pink: `grep -n c2185b agent-plan-tracker/view/` returns nothing.
- [ ] Sidebar resize still works (Phase C's fix preserved: width + flex-basis).
- [ ] Analyse outstanding button still wires up; SavedSummary view still renders.
- [ ] Screenshot taken via Claude_Preview.

## 9. Provenance

- T2-projection §3.2 (HTML view structure) — architectural source of truth for what this T3 polishes.
- T3-html-view — landed the initial view.
- T3-analyser-phase-c-flow-rendering — established the summary-node rendering pattern; this T3 follows the same additive-helper approach.
- Orientation brief from coordinator agent (Task A/B/C) — explicit asks tied to user-observed friction during M5 dogfooding.
- Pink-colour tweak from coordinator follow-up — folded into bonus acceptance criterion.
