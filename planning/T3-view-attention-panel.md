---
id: T3-view-attention-panel
plan_kind: thematic
tier: 3
t2_parent: T2-projection
milestone: M6-dashboard
status: draft
---

# T3-view-attention-panel — operator attention + decision arcs in the dashboard

**Status**: Draft, awaiting operator acceptance.

## Why

`projection.json` already emits `attention` (pending acceptance ceremonies with staleness, pending closure ceremonies, deferred verifications — built by M5.1/`T3-pending-ceremony-surfacing`), `milestone_progress`, and `decisions` (with `explains_arcs`). The view renders none of them. The record prompts in `summary.md` but stays silent in the dashboard; and T2-projection §3.2's designed promise — fulcrum arcs "clickable for decision text" — was never built. This T3 closes the summary.md↔view gap using data that already exists: no emitter or schema changes.

## What

1. **Attention panel.** A collapsible panel available regardless of view mode (toolbar-level, default expanded when non-empty), mirroring summary.md's *Awaiting operator*: pending acceptance (with authored-N-commits-ago staleness), pending closure, open deferred verifications; plus untriaged inbox count. Entries link to the entity (same navigation as existing entity links).
2. **Milestone progress strip.** Per-milestone `scheduled/completed/live` counts from `milestone_progress`, rendered compactly (e.g. progress pills) within the panel.
3. **Decision-arc click-through.** In the flow view, fulcrum-coloured nodes gain an affordance; clicking surfaces the paired `decision` text (via `explains_arcs` → event ids) in the detail sidebar, alongside the existing event detail. Where a decision covers several arcs, show it on each.

## Acceptance

- With the dogfood data: the panel lists exactly what summary.md's *Awaiting operator* lists (same entities, same staleness numbers) — cross-checked in the same repack.
- Milestone strip matches summary.md's *Milestone progress* counts.
- Clicking a fulcrum node (e.g. the `entity.renamed` on the analyser, or any superseded plan) shows the decision text; a fulcrum-less node shows no decision affordance.
- No layout regression in board/tree/flow; `repack-validate.sh` green.

## Out of scope

- New attention categories or emitter changes; notification mechanisms; editing/acknowledging from the view (view-only remains the law, T2-projection §8).
