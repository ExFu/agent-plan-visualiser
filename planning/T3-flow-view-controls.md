---
id: T3-flow-view-controls
plan_kind: thematic
tier: 3
t2_parent: T2-projection
milestone: M1-bootstrap
status: completed
---

# T3-flow-view-controls — Button contrast, gutter-control affordances, isolated-root cues, and a cascade-exemption fix for the flow view

> **For Claude:** Four small view-layer fixes bundled into one T3 because they share the same code surface (`view/style.css`, `view/app.js`) and all concern the flow view's *controls and their legibility* — not its data. This continues the polish line of [[T3-flow-view-filtering]] (whose addendum §7 already locally patched one instance of the white-on-white bug fixed globally here) and [[T3-flow-view-density]]. No projection/schema/event-shape change — pure client-side rendering. Read [[T2-projection]] §3.2 for the view contract; keep it dynamic-from-`projection.json`, vanilla JS, no build step.
>
> Sibling plan [[T3-milestone-parent-ontology]] (under [[T2-ontology]]) carries the data/ontology half of the same operator review (items 6 + 3). This plan is view-only; that one is the event log + cache-build + methodology docs. They share no files.

---

## 1. Why (the job)

An operator review of the live flow view surfaced four defects, all about *controls* rather than the graph itself:

1. **White-on-white buttons.** Custom-coloured buttons (notably the purple "✦ Analyse all live" pill) render invisible — white text on a white background — in their normal enabled state. One instance (`.isolate-clear`) was already patched locally in [[T3-flow-view-filtering]] §7.3; the operator asked for a *global* fix because the same trap recurs anywhere a coloured button sits in a styled container.
2. **Cascade hides the wrong set.** Hiding `T1-top-level` fails to hide `T2-analyser` (which is spawned only from T1), even though it correctly hides T1's other children. Root cause: the eye-hide cascade exempts *any* superseding entity from being hidden at all (`computeFlowVisibility` superseder check), which is broader than the intent ("don't let a dead predecessor hide its live replacement").
3. **The unisolate control is unintuitive.** When isolation is active the only exit is a lone banner button at the top, and the isolated entity has no visual marker among the surviving rows.
4. **Gutter controls are cramped and monochrome.** The isolate / eye / caret glyphs are all near-identical grey, hard to tell apart, and have hit-areas too small for touch.

All four are legibility/affordance work on the same two files. Bundling avoids the cross-plan coupling the methodology warns against. (Item 2 is a logic bug, the others are CSS/markup, but they all live in `app.js`+`style.css` and ship together as one review's worth of view polish.)

## 2. What (the four deliverables)

Build in order; D1 is independent CSS, D2 is the one logic change, D3/D4 are markup+CSS over the gutter.

### D1 — Global button-contrast fix (item 1)

**Root cause (confirmed live).** Container rules `.toolbar button` and `.sub-toolbar button` (`style.css:37`, `:114`) both set `background: var(--card-bg)` (white). Their selector specificity is `(0,1,1)`; a custom button class like `.btn-global-analyse` (`:1059`) is only `(0,1,0)`, so the container rule wins the `background` while the custom rule's `color: white` survives → **white text on white background**. Verified in-browser: with the global-analyse pill force-enabled, computed `background-color` and `color` are both `rgb(255,255,255)`. It only bites when *enabled* because `:disabled` rules carry an extra pseudo-class and out-specify the container.

**Fix (global, future-proof) — two parts:**

*(a) Stop the clobber.* Scope the container defaults so they don't reach buttons that carry their own semantic class:

```css
/* style.css:37 */
.toolbar button:not([class*="btn-"]):not(.api-key-pill) { … }   /* view-switchers only */
/* style.css:114 */
.sub-toolbar button:not([class*="btn-"]) { … }
```

The view-switch buttons (`#btn-board`/`#btn-tree`/`#btn-flow`) have no `btn-`-prefixed *class* (their `btn-` is an `id`, plus the `active` class), so they keep the default styling; `.btn-global-analyse`, `.btn-primary/secondary/danger/analyse`, and `.api-key-pill` opt out and render their own colours. This generalises the local `.isolate-clear` patch so the next coloured button added to a toolbar is safe by default. The `.active` rules (`:45`, `:123`) stay as-is (view switchers still need them).

*(b) Tokenise the button palette.* The button colours are currently hard-coded hexes scattered across the stylesheet (`#6a1b9a`/`#4a148c` purple, `#1976d2`/`#1565c0` blue, `#c62828`/`#b71c1c` red, plus the `#f3e5f5`/`#ce93d8` isolation tints). Promote them to named CSS custom properties in `:root` (alongside the existing `--color-*` tokens) — e.g. `--btn-analyse`, `--btn-analyse-hover`, `--btn-primary`, `--btn-primary-hover`, `--btn-danger`, `--btn-danger-hover`, `--isolate-accent`, `--isolate-tint` — and reference them from `.btn-analyse`, `.btn-global-analyse`, `.btn-primary`, `.btn-danger`, `.isolate-banner`, `.gctrl-caret`, `.placeholder-node`, etc. Single source of truth for the palette; makes the next colour change (or a future dark theme) a one-line edit and prevents the drift that hid this bug. (Confirmed in the live review — operator asked for the token refactor here rather than deferring it.)

**Verification D1:** enabled "✦ Analyse all live" shows purple bg + white text (contrast ≥ 4.5). Sweep all buttons in every render state (toolbar, sub-toolbar, detail panel, modals, unisolate banner) — none white-on-white. View-switcher active/inactive styling unchanged.

### D2 — Cascade exemption precise-scoping (item 2)

**Root cause (confirmed).** `computeFlowVisibility` (`app.js:400-413`) skips *all* superseders from the eye-hide cascade: `if (closure.has(k) || superseders.has(k)) continue;`. `T2-analyser` is named in the `entity_ids` of the inbox item's `entity.superseded` event, so it is flagged a superseder and never cascade-hidden — even though its *only* spawn-parent is `T1-top-level`. The exemption's real intent (addendum §7.2) is narrow: *hiding a dead predecessor must not drag its live replacement into hiding.* But supersession is not a spawn edge, so a superseder is only ever cascade-eligible via its actual spawn-parents — and excluding it wholesale breaks the legitimate "hide T1 → hide its exclusive child T2-analyser" case.

**Fix.** Replace the boolean `computeSuperseders` (returns `Set<superseder-key>`) with `computeSupersededPredecessors` (returns `Map<superseder-key, Set<predecessor-key>>`, inverting each `entity.superseded` event: each id in `entity_ids` ⇒ superseder, the event's own `entity_id` ⇒ predecessor). In the closure loop, don't exempt the node — instead drop from its parent set only the parents it supersedes, then hide it iff it still has parents and they're all hidden:

```js
const supPreds = computeSupersededPredecessors(projection); // ekey -> Set(predecessor ekeys)
…
for (const k of allKeys) {
  if (closure.has(k)) continue;
  const ps = adj.parents[k];
  if (!ps || ps.size === 0) continue;
  const sup = supPreds.get(k);
  const eff = sup ? [...ps].filter(p => !sup.has(p)) : [...ps];
  if (eff.length > 0 && eff.every(p => closure.has(p))) { closure.add(k); changed = true; }
}
```

This preserves the original intent exactly (a plan that both supersedes *and* is spawned by X won't hide when X hides) while fixing the present bug (T2-analyser's parent set `{T1}` contains no superseded predecessor, so hiding T1 hides it). `computeSuperseders` has only this one caller (`app.js:400`), so replacing it is clean.

**Verification D2:** eye-hide `T1-top-level` ⇒ `T2-analyser` AND `T2-ontology` (and T1's other exclusive children) all go suppressed/greyed; un-hiding T1 restores them. A synthetic "supersedes-and-spawned-by-same-parent" case still keeps the replacement visible. Add assertions to the existing headless logic suite alongside the §7 cascade tests.

### D3 — Isolated-root affordance: de-isolate icon + title cue (item 4)

When `isolateRoot` is set, the isolated entity *is* on screen, so its gutter control should offer the inverse action and its label should stand out.

- **De-isolate glyph.** In the gutter render (`app.js:1126-1127` entity rows; `:1079-1081` swimlane headers), when the row/header *is* the current `isolateRoot`, render a **de-isolate** control instead of the ⌖ isolate control — a distinct glyph (proposed: **⊗**, "exit focus") wired to clear `isolateRoot`. Other rows keep ⌖ (isolate-to-this). The top banner button keeps its explicit "✕ Unisolate" text (`app.js:239`) as the always-visible escape; this adds an in-place second exit at the focal row.
- **Isolated-title styling.** Give the isolated root's label a marker class (`.grow-label.is-isolated-root` / `.gsl-label.is-isolated-root`) styled bold + the isolation purple (`#6a1b9a`) so it's instantly findable among survivors.

**Verification D3:** isolate an entity ⇒ its row shows the ⊗ de-isolate glyph and a bold purple title; clicking ⊗ clears isolation (same as banner / Esc). Non-root rows still show ⌖. Same for an isolated swimlane header.

### D4 — Colour-coded, roomier gutter controls (item 5)

- **Colour-code** the three control kinds so they're scannable (`style.css:1217-1230`): isolate ⌖ a steady blue-teal; eye ◉ green-when-on / red ◌ when-off (the off-state red already exists — make the on-state a positive hue); caret ▾ stays purple. Keep low default opacity, full on hover (current pattern).
- **Breathing room / touch targets.** Bump `.gctrls` `gap` (2px → ~6px) and give `.gctrl` a larger hit-area (min ~22-24px square via padding, keep the glyph centered) so the controls are tappable on touch devices. No dedicated mobile layout yet (out of scope), but size the targets mobile-friendly now.

**Verification D4:** the three glyph kinds are visually distinguishable at a glance; tap targets measure ≥ ~22px; hover/active states intact; no layout shift in the gutter rows.

## 3. Implementation notes / touch-points

- **`style.css`** — D1: edit selectors at `:37` and `:114`. D4: edit `.gctrls`/`.gctrl` block `:1210-1230`. D3: add `.is-isolated-root` label rule near `.grow-label` `:1233`.
- **`app.js`** — D2: `computeSuperseders` → `computeSupersededPredecessors` (`:330-343`) + closure loop (`:400-413`). D3: gutter render swimlane header `:1079-1081` and entity row `:1126-1131` (branch on `F.isolateRoot` match); pass an `isIsolatedRoot` flag to the label element.
- **No projection/schema/event-shape changes.** View-only.
- All toggles already re-render via `rerenderFlow()`; no new plumbing.

## 4. Decisions to log (paired with the implementing commit)

- **DEC-1 — container button defaults exclude semantic button classes, and the button palette moves to CSS variables.** Rationale: a coloured `.btn-*`/pill placed in any toolbar must keep its own colours; opting out via `:not([class*="btn-"])` stops the white-on-white trap recurring (supersedes the per-button `.isolate-clear` patch). Tokenising the palette gives a single source of truth and kills the scattered-hex drift that hid the bug (operator chose the refactor over deferring it).
- **DEC-2 — superseder cascade-exemption scoped to superseded parents only.** Rationale: supersession is event-data, not a spawn edge; a superseder must still cascade-hide when its real spawn-parents are hidden. Only the specific predecessor-parent it replaces is excluded.

## 5. Out of scope (this T3)

- A dedicated mobile/responsive layout (size touch targets generously now; full responsive view is a later T3).
- Any change to the Entity-state-board or Plan-hierarchy-tree views.
- The data/ontology fixes (M6 reparent, reattached-supersedes, Mn-parent rule) — those are [[T3-milestone-parent-ontology]].
- A full dark-theme / second palette (the tokenisation in D1 makes it cheap later, but no second theme is built here).

## 6. Verification (whole-T3)

Manual, in-browser (the view's only runtime), plus the headless logic suite for D2:
1. D1: every button legible in every state; enabled global-analyse pill purple+white.
2. D2: hide T1 ⇒ T2-analyser + T2-ontology suppress; headless cascade assertions green.
3. D3: isolate an entity & a swimlane; de-isolate glyph + bold purple title appear; ⊗ clears.
4. D4: glyphs distinguishable + tappable.
5. Regression: isolate/hide/collapse/lifecycle from [[T3-flow-view-filtering]] still work; milestone↔t2 switch fine; no console errors.
Screenshot each as evidence ([[T2-projection]] §7 keeps the view manually verified).
