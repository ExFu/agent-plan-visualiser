---
id: T3-multi-project
plan_kind: thematic
tier: 3
t2_parent: T2-storage
milestone: M4-fresh-install
status: draft
---

# T3-multi-project — sub-projects as a dimension of one record

**Status**: Accepted by the operator 2026-07-21 (conversation ruling; the four
design points below quoted back and confirmed verbatim). The projection/view
half touches T2-projection; the registry/roots core is T2-storage's.

## Why

Monorepos hold multiple real projects — exfu_website's website at the repo
root and its `plugin/` sub-folder are separate endeavours with separate
planning roots — but commits are repo-wide by definition. APV must therefore
support aggregating/flagging/filtering by sub-project without ever
partitioning the record.

## Design (operator-accepted frame)

1. **One log per repo, always.** The commit stream is one, so the append-only
   record is one. Sub-projects are a *dimension of the data*, not a partition
   of the record. No event-schema change (attributes are open).
2. **A project registry in committed config**: `[projects.<name>]` tables in
   `.apv-config.toml`, each with a `planning_dir`. Entity → project membership
   derives from which registered planning root owns `<root>/<entity_id>.md`,
   with explicit `attributes.project` as the escape hatch for planless
   entities (inbox items, blockers). Explicit attribute wins; latest-recorded
   wins among attributes (latest-knowledge doctrine).
3. **Filter/aggregate at projection time.** The cache folds a per-entity
   `project` column (mirroring the 0.4.0 `origin` fold); the projection
   carries it plus a top-level `projects` list (only when a registry exists —
   single-project output stays byte-identical); the view gets ONE shared
   view-independent project filter applying to board, tree, and flow
   (operator's choice: all three views), plus passive project badges;
   summary.md gains a `## By project` rollup.
4. **Guard and gate stay repo-level.** Capture discipline and the boundary
   gate protect the one record; the drift check iterates every registered
   planning root and WARNs on a plan id present in two roots.

Resolution details: `[storage] planning_dir` remains the primary root and
becomes the implicit project **`main`** (a named project registering the same
dir renames it); entities matching no root with no attribute derive
**`unassigned`** — deliberately visible triage, not a silent bucket. Reserved
name `unassigned` and duplicate `planning_dir`s are fail-loud config errors.
No `[projects]` tables → single-project mode, behaviour exactly as before
(zero migration for existing adopters).

## Migration (approval-gated)

`scripts/migrate-projects.py` — dry-run default; proposes the config block,
previews per-entity membership with resolution source, and renders
`entity.extended` annotation events for unassigned **non-closed** entities
under explicit `--assign` only (closed entities are listed but never
annotated: `entity.extended` on a closed entity trips the gate's
resurrection-without-reopen blocker; they remain honest archaeology).
`--apply` writes config only; `--emit-events` writes a side file the operator
appends via a normal captured commit — the tool never touches events.jsonl.
**The spec and sample output go to the operator before this script is
written.**

## Acceptance

- Registry parse (tomllib and minimal-parser parity), membership derivation
  (attr / root / main / unassigned), project filter in all three views,
  multi-root `/planning` serving, drift across roots, duplicate-id WARN —
  all exercised in the view + gate sandboxes.
- Single-project projections byte-identical, pinned by test.
- All seven suites green; gate green on the branch and the main move.
