---
id: T3-button-system-dry
plan_kind: thematic
tier: 3
t2_parent: T2-projection
milestone: M1-bootstrap
status: completed
---

# T3-button-system-dry — One button component for the whole view; dial back gutter-control whitespace; inbox swimlanes always last

> **For Claude:** Operator-review round 2 of the flow view, all view-layer (`view/style.css`, with near-zero `view/app.js` change). The headline is a DRY button system that ends the recurring white-on-white regressions for good; two minor polish tweaks ride along because they share the same file surface. No projection/schema/event-shape change. The lifecycle-vocabulary half of this review round lives in [[T3-lifecycle-term-closed]]. Continues the polish line of [[T3-flow-view-controls]] and [[T3-flow-view-filtering]]; read [[T2-projection]] §3.2 for the view contract (dynamic-from-`projection.json`, vanilla JS, no build step).

## 1. Why

[[T3-flow-view-controls]] fixed one white-on-white button by adding `:not([class*="btn-"]):not(.api-key-pill)` to the `.toolbar button` base rule. That raised the base rule's specificity to **(0,3,1)** — which now *beats* `.toolbar button.active` at **(0,2,1)**. Result: the active "Workstreams flow" view-switcher button renders a white background (from the base) under near-white text (`color: var(--bg)` from `.active`, which still applies because the base sets no color). One specificity hack fixed one collision and created another.

The root cause is **location-based button styling**: `.toolbar button` / `.sub-toolbar button` descendant selectors colour buttons by where they sit, then single-class semantic buttons (`.btn-primary` etc. at (0,1,0)) lose to them, forcing `:not()` chains to claw specificity back. Every new button is a fresh chance to land outside the matched set (→ unstyled) or to invert specificity against `.active`/variant rules. The operator's instruction: *"get all buttons into a cohesive theme or DRY approach … we shouldn't be having these issues."* — eliminate the **class** of bug, not this instance.

## 2. The button system

A single, location-independent component built from layered single-purpose rules, each cleanly beating the one below:

| Layer | Selector | Specificity | Role |
|---|---|---|---|
| Base | `button` | (0,0,1) | Neutral pill every button starts from: `padding`, `border: 1px solid var(--border)`, `background: var(--card-bg)`, `color: var(--fg)`, `border-radius`, `cursor`, inherits font. |
| State | `button.active` | (0,1,1) | Selected toggle: `background: var(--fg); color: var(--bg)`. |
| Disabled | `button:disabled` | (0,1,1) | Uniform muted look + `cursor: not-allowed` for every disabled button. |
| Variant | `.btn-primary` / `.btn-danger` / `.btn-analyse` / `.btn-global-analyse` / `.btn-secondary` / `.btn-isolate` / `.isolate-clear` | (0,1,0)+ | Semantic colours from the palette tokens (already tokenised in round 1). |

**Key property:** because the base is the bare element selector (0,0,1), *every* single-class variant and *every* state pseudo-class outranks it automatically. No `:not()`, no `!important`, no location coupling. A button with no class is a legible neutral pill; add `.active`/`.btn-*`/`disabled` and it specialises predictably.

**`.toolbar` / `.sub-toolbar` keep layout only** — margins and flow. Their `… button { background/border/… }` colour declarations are deleted; the base rule supplies the look. Container rules that remain are layout-only (e.g. `margin-right`).

**app.js:** effectively unchanged. Buttons already carry the correct classes (`active`, `btn-*`); the view-switcher buttons built via `createElement("button")` toggle `className` between `"active"` and `""`, which the new `button` + `button.active` pair handles without edits. Confirm no button-creation site depends on a deleted location selector for its colour.

### 2.1 Acceptance for the button system
- The active "Workstreams flow" button: dark background, light text (legible).
- Every toolbar/sub-toolbar/sidebar button legible in default, `.active`, and `disabled` states.
- The unisolate affordances — the gutter `⊗` de-isolate control **and** the banner clear button — both legible (no white-on-white).
- Disabled "Analyse all live" pill reads as muted/disabled, not broken.
- Audit: no `:not([class*=…])` specificity hacks remain in the button rules; no hardcoded button hexes (palette tokens only).

## 3. Gutter-control whitespace (dial halfway back)

Round 1 (D4) grew the gutter controls from `width:13px` / `gctrls gap:2px` to `min-width/height:22px` / `gap:6px`. Operator: too wide now; *"about halfway between where it was and where it is now."*

| Property | Round-0 | Round-1 | This round (≈halfway) |
|---|---|---|---|
| `.gctrls` gap | 2px | 6px | **4px** |
| `.gctrl` box | 13px wide | 22px square | **18px square** (`min-width`+`height`) |
| `.gctrl` padding | none | `0 2px` | `0 1px` |
| `.gctrl` font-size | 11px | 13px | **12px** |
| swimlane `.gctrl` font | 12px | 14px | **13px** |

Keep the round-1 colour-coding and hover affordances; only the box/gap shrink. Targets stay comfortably tappable (~18px).

## 4. Inbox swimlanes always last

The flow view groups rows into swimlane sections. Inbox-item sections must **always sort to the very end**, after every plan/milestone section, regardless of the active swimlane mode (milestone vs T2-domain) or lifecycle filter. Locate the swimlane-ordering comparator in `app.js` and add a terminal sort key: any swimlane whose members are inbox-items (or the dedicated inbox lane) ranks after all others; preserve existing ordering among non-inbox lanes. Verify in both swimlane modes.

## 5. Out of scope
- No change to button *behaviour* or wiring — pure appearance/structure.
- No new button variants beyond those already present.
- Lifecycle term rename (`dead`→`closed`) is [[T3-lifecycle-term-closed]], not here (though both land in the same review round).

## 6. Verification (dogfood)
In-browser via the running `apt-view` server: screenshot the toolbar showing the active flow button legible; isolate an entity and confirm both unisolate affordances legible; confirm gutter spacing visibly tighter than round 1 but roomier than round 0; confirm inbox lanes render last in *both* swimlane modes; check console clean; confirm the round-1 controls (isolate/hide/collapse/lifecycle, swimlane switch) still work. Then `repack-validate.sh` green.
