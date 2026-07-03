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
