---
id: T3-html-view-interactivity
plan_kind: thematic
tier: 3
t2_parent: T2-projection
milestone: M6-dashboard
status: draft
---

# T3-html-view-interactivity — search + filters for board and tree

**Status**: Draft, awaiting operator acceptance. This is the T3 that T2-projection §5 reserved under "Later" (`T3-html-view-interactivity`, M3+).

## Why

The flow view got filters (lifecycle, provenance, project — T3-flow-view-filtering); board and tree got none. At 77 entities the board is scan-only — no way to narrow to one entity, one state, or a text match. The project filter (`state.projectFilter`) already proved the pattern for view-independent filter state applying across all three views.

## What

1. **Text search.** A toolbar search input, view-independent state (following the `projectFilter` pattern). Matches against entity id (substring, case-insensitive). Board: non-matching cards hidden, section counts update. Tree: matching nodes kept with their ancestor chain (ghosted ancestors, as the project filter already does); non-matching branches hidden. Flow: matching lanes kept (reusing the existing row-visibility machinery). Empty input = no-op.
2. **Lifecycle filter on board/tree.** Extend the flow view's existing lifecycle filter (All / Open / Closed) to board and tree, honouring the same state — one filter, three views, matching the operator-accepted multi-project filter precedent ("the view gets ONE shared view-independent filter", T3-multi-project design point 3).

## Acceptance

- Typing a fragment (e.g. `attention`) narrows board, tree and flow consistently; clearing restores all.
- Lifecycle filter set in flow persists when switching to board/tree and vice versa.
- Project filter + search + lifecycle compose (AND semantics).
- No behavioural change with empty search and All lifecycle; `repack-validate.sh` green.

## Out of scope

- Attribute/full-text search over plan contents; saved filter presets; URL-parameter filter state (nice-to-have, not this pass); flow-view filter redesign.
