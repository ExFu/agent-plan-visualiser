---
id: T3-historical-projection-ui
plan_kind: thematic
tier: 3
t2_parent: T2-projection
milestone: M5-backfill
status: draft
---

# T3-historical-projection-ui — the unfurl, rendered

**Status**: Draft.
**Sits at**: T2-projection theme, M5-backfill milestone. Wave-1 contract T3, paired with [[T3-origin-provenance-schema]] — neither builds until both are accepted. Absorbs the `2026-06-10.view-hardcodes-dogfood-data-dir` inbox item.

---

## 1. Why

`origin` is only real once it is *seeable*: the whole point of marking backfilled events is that a human looking at the project's history can tell contemporaneous record from retrospective inference at a glance. And the flow view currently cannot serve adopters at all — it hardcodes `../../.agent-plan-tracker/` paths, which is wrong for every `.apv/` repo M4 now creates. This T3 is where the view learns both lessons.

## 2. What

1. **Event-time unfurling** — the flow view and any timeline rendering order by event time (the anchor), not log position; a backfilled 2025 block renders *in* 2025. Record time stays available (tooltip/detail: "recorded 2026-07-03, backfill run bf-…").
2. **Provenance rendering** — `origin: backfilled` entities/events get a visibly distinct treatment (ghosted/dashed), with a provenance toggle (show all / captured only / backfilled only). Styling respects the button-system DRY rule — one component system, no location-specific overrides.
3. **Open-question rendering** — tier-3 Why hypotheses (`hitl-question`s from backfill) render as open questions attached to their plan, never as rationale/decision styling.
4. **Data-dir resolution** — `serve.py` resolves the data dir via apvlib (env → config → `.apv`) and serves `projection.json` from there; `app.js` loses the hardcoded paths (fetches via the served endpoint). The dogfood repo keeps working via its config pin.

## 3. Scope

### In scope
- `view/app.js`, `view/index.html`, `view/style.css`, `scripts/serve.py`; a mixed-log fixture projection for development.

### Out of scope
- Schema/gate/cache changes ([[T3-origin-provenance-schema]]).
- New analyser features (T2-analyser); snapshot time-travel (later).

## 4. Verification

1. Fixture projection with mixed captured+backfilled events: renders in event-time order; backfilled treatment visible; toggle filters correctly; open questions render as questions.
2. A `.apv/` sandbox repo: `serve.py` finds and serves its projection with zero config; the dogfood repo still works via its pin.
3. Grep audit: no `.agent-plan-tracker` literals left in `view/`.

## 5. Dependencies

- T3-origin-provenance-schema (paired; supplies `origin` + event-time fields in projection.json).
- M1's view + M1.1 analyser surfaces (the code being extended).

## 6. Open questions

1. Ghosting vs badge vs hue for backfilled treatment — operator taste call at build (present options against the fixture).
2. Does the provenance toggle belong in the existing filter controls or as a standalone control? Lean: existing filter system (DRY).

## 7. Build notes (2026-07-03)

- **Q1 built as ghosting + badge combined, default pending operator taste**: dashed translucent spines and nodes in the flow view, faded italic gutter rows, faded cards/tree nodes with a `◌` marker, plus a dashed `origin` badge (and hover title) on cards. All treatments key on one class hook (`origin-<value>` / `.ghost`), so re-tasting is a CSS-only change. Mixed entities keep full presence (they contain record) and carry the badge only.
- **Q2 as leaned**: the provenance toggle (All / Captured / Backfilled) reuses the lifecycle-filter component classes verbatim — zero new button CSS — and its visibility step slots into `computeFlowVisibility` beside lifecycle. "Captured" hides backfilled-only entities (mixed stays); "Backfilled" isolates mined history.
- **The unfurl is one load-time sort**: every event gets its block anchor (`_event_time`, backwards seal walk) and the raw event array is stable-sorted by `(anchor day, record order)` before any view consumes it — commit columns, positional rollup and lifelines all sequence historically for free. Identity for captured-only logs.
- **Open questions render as questions**: hitl-question entities get an `open question` badge (never decision styling) and dashed card borders.
- **The data-dir hardcode is dead** (inbox item absorbed): `serve.py` now serves the **toolchain's** `view/` at `/view/`, the apvlib-resolved data dir at `/data/` (traversal-guarded), and the target repo's `planning/` at `/planning/`; `app.js` fetches those routes with the dogfood-relative paths kept as documented legacy fallbacks for plain `http.server` browsing.
- **Surfaced and fixed in-scope**: the pipeline trio (`cache-build`, `projection-emit`, `summary-emit`) and `serve.py` all anchored `REPO_ROOT` at the *toolchain's* `parents[2]` — wrong for every plugin install (the same trap gate-check fixed in M4). New `apvlib.repo_root()` (cwd's enclosing repo → vendored fallback) fixes all four; toolchain content (schemas, view) now resolves script-relative. The view sandbox proves the whole pipeline + serve flow in a bare `.apv` adopter with no env and no config.
- **Verification**: `tests/view/run-view-sandbox.sh` (routes, traversal guard, origin in the served projection, static wiring audit, dogfood-literal grep audit) ALL PASS; live browser check on the dogfood repo — view loads via `/view/`, board + flow render (71 lanes, 201 nodes), provenance filter cycles Backfilled→0 lanes→All→71, zero console errors; screenshot taken. Full regression: all nine suites + repack + rename audit green.
