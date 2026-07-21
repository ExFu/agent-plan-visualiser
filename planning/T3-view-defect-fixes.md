---
id: T3-view-defect-fixes
plan_kind: thematic
tier: 3
t2_parent: T2-projection
milestone: M6-dashboard
status: draft
---

# T3-view-defect-fixes — two verified view defects

**Status**: Draft, awaiting operator acceptance. Verified firsthand during the 2026-07-21 assessment.

## Why

Both defects break promises the view already makes: the entity-name click affordance renders nothing, and saved summaries only work in this repo's dogfood layout.

## What

1. **`showPlanMarkdown` ReferenceError** — `view/app.js` (function at ~1740): declares `paths` but the success meta-line and the catch handler both reference an undefined `path`. The success template throws inside the `try`; the catch then throws on the same undefined variable — so clicking any entity name (gutter or "open full plan" link) leaves the panel stuck at "Loading…" with an uncaught error. Fix: meta-line shows the successful response's URL (`res.url`); catch shows `paths.join(", ")`. Mirror of the correct sibling `showLiveStatus` (~2233).
2. **Saved-summary dogfood hardcode** — `SavedSummary._renderInner` (~2576) fetches freeform markdown via `` `../../${summary.freeform_path}` `` only, bypassing `serve.py`'s `/data/` route — the defect class T3-historical-projection-ui eliminated elsewhere (and the standing inbox item `2026-06-10.view-hardcodes-dogfood-data-dir`). Fix: adopt the established dual-path convention (`DATA_PATHS` + `fetchFirst`): try `/data/summaries/<basename>` first, keep the `../../` relative path as the file:// fallback.

## Acceptance

- Served view: click an entity name in the flow gutter → plan markdown renders, meta-line shows the resolved path, zero console errors; same for an inbox item.
- Open a saved summary → freeform loads; network tab shows the `/data/summaries/…` request succeeding.
- Simulated failure (nonexistent entity file) → catch path renders the tried paths, no uncaught error.
- `repack-validate.sh` green.

## Out of scope

- Any other `app.js` refactoring; the fold-duplication liability; new features.
