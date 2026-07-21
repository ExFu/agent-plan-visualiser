---
id: T3-retrospective-project-annotation
plan_kind: thematic
tier: 3
t2_parent: T2-ontology
milestone: M4-fresh-install
status: draft
---

# T3-retrospective-project-annotation — assert sub-project membership, even on closed entities

**Status**: Authored and accepted 2026-07-21 (operator plan-approval ruling in
conversation; remit corrected there to annotation-only). Built same day.
**Sits at**: T2-ontology theme, M4-fresh-install milestone. Addendum to
[T3-multi-project](T3-multi-project.md).

## 1. Why

A downstream adopter — a repo that was previously one project and is now
separating into sub-projects — needs historical entities, many **closed**,
placed under the right `[projects.<name>]` without lying about lifecycle.
T3-multi-project shipped membership as a fold (explicit `attributes.project`
→ planning-root ownership → `main`/`unassigned`) but left closed entities
stranded: `entity.extended` on a closed entity trips the gate's
resurrection-without-reopen blocker, so its Migration spec carved them out
("listed but never annotated"). The operator's remit here: a mechanism for
the project's agent to **assert** an entity's membership retrospectively —
logical annotation only, no reopening; physical file organisation remains
the adopter's own business.

`relationship.reattached` was assessed and rejected for this job: it is the
*parent-move* primitive — its axis is inferred from parent-id shape (`M*` vs
`T2-*`), the gate requires its endpoints to be plan entities (projects are
registry names), and the membership fold never reads relationship edges.

## 2. What

1. **Schema epoch `0.6.0`** (`agent-plan-visualiser/schemas/0.6.0/`): copy of
   0.5.0 plus the `project.assigned` event type — `attributes.project`
   required; optional `from_project`, `summary`. `schema_version` enum grows
   to accept `0.6.0`; cache DDL unchanged (the event feeds the existing
   `entities.project` fold).
2. **Semantics**: a membership *assertion*, **state-neutral** — absent from
   `STATE_FROM_EVENT`, the `entity.renamed` precedent — so it is valid on
   open or closed entities and never resurrects. Feeds the existing
   `attributes.project` pre-scan with zero fold change; latest-recorded wins;
   once recorded, the attribute is authoritative over planning-root
   derivation. **Fulcrum**: paired same-block `decision` required; one
   decision covers a bulk assignment by listing every event_id.
3. **Gate**: resurrection check untouched (the exemption is absence from
   `STATE_FROM_EVENT`, pinned by fixture); `FULCRUM_TYPES` and the fulcrum
   audit SQL gain the type; the referential check gains an
   existence-in-record branch — NOT created-first (legacy pre-0.3.0 entities
   stay annotatable), and `project.assigned` events do not self-establish
   existence. Project *names* are not validated — the registry governs
   roots, not the namespace.
4. **Emission**: `/apv-capture` emits `project.assigned` at
   `schema_version: "0.6.0"` (each event stamps its introducing epoch);
   toolchain default pins bump (`validate-events.sh`, `cache-build.py` DDL,
   `projection-emit.py` stamps); plugin version 0.6.0. The gate's
   per-version schema routing needs no change — a mis-stamped
   `project.assigned` self-blocks against the older schema.
5. **Docs**: capture + orientation skills, cheatsheet, worked example
   `cheatsheet/worked-examples/assign-entity-to-project.md`; T3-multi-project
   gains an addendum superseding its closed-entity carve-out
   (`migrate-projects.py`, when built, emits `project.assigned` uniformly;
   the script itself stays deferred and approval-gated).

## 3. Out of scope

- `migrate-projects.py` — stays spec-first, approval-gated per
  T3-multi-project; the manual worked-example procedure serves the
  downstream need.
- Bitemporal membership history — membership stays a single current scalar
  (parity with the parent-move doctrine); past assertions remain queryable
  in the log.
- Prescribing physical file moves — the adopter's agent acts under its own
  aegis; the assertion event is the recorded fact either way.

## 4. Verification

1. Log validates unmigrated via `repack-validate.sh` with the 0.6.0 default.
2. Fixture `tests/gate/fixture-project-move`: a CLOSED entity annotated via
   `project.assigned` + paired decision — gate exit 0, no
   resurrection-without-reopen block, cache folds `project=rootb` with
   `derived_state` still `closed`.
3. Fixture `tests/gate/fixture-project-move-nodecision`: an unpaired
   assignment BLOCKs [fulcrum-without-decision]; an unknown-entity
   assignment BLOCKs [referential]; a 0.3.0-stamped assignment BLOCKs
   [schema] (epoch stamping self-polices).
4. All suites green; gate green on the repo and the main move.
