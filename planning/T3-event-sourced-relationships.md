---
id: T3-event-sourced-relationships
plan_kind: thematic
tier: 3
t2_parent: T2-storage
milestone: M1.2-relationship-ssot
status: draft
---

# T3-event-sourced-relationships — make the event log the single source of truth for entity relationships

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Placement is confirmed (§8 Q1, resolved 2026-06-01): this plan is the sole constituent of milestone **M1.2-relationship-ssot** (a focused M1 follow-up).

**Goal:** Make a plan's parentage (thematic `t2_parent`, milestone membership) a **derived projection of the event log**, not a value read independently from three places that can disagree. Wire up the currently-dead `relationship.reattached` event so that *moving* an entity between parents is a first-class, graph-visible operation — and so editing a frontmatter field alone can no longer silently change project state.

**Architecture:** Fold relationship edges from the event stream with last-write-wins per `(entity, axis)`: the `entity.created` frontmatter snapshot *seeds* an edge; each subsequent `relationship.reattached` event *rewrites* it. The cache becomes the only materialised relationship store; `projection-emit.py` reads parentage from the cache, never from live `planning/*.md` frontmatter. Frontmatter is demoted to a creation-time input (per T1 §3.1) with a future audit (M3) to flag frontmatter-vs-event drift.

**Tech stack:** Python 3 stdlib (`cache-build.py`, `projection-emit.py`); JSON Schema draft-07 (`events.schema.json`); no new dependencies.

---

## 1. Why this T3

This T3 exists because dogfooding surfaced a concrete violation of T1 §3.1 (git/event-log is primary; plans are inputs, never authoritative) and §3.2 (state is a projection; no parallel state stores that diverge).

**The symptom.** During M1 close-out we needed to move `T3-analyser-live-model-catalog` (and its sibling analyser T3s) out of `milestone: M1-bootstrap` and into `milestone: M6-analyser` — they had been mis-tagged, inflating M1's live count and keeping M1 from closing. There is no clean single edit that achieves this, because *milestone membership is represented in four different places that are read inconsistently.*

**The four representations** (current `main`):

| # | Where | How it's read | File / lines |
|---|-------|---------------|--------------|
| R1 | `entities.attributes` in the cache | Snapshot, materialised **only** from `entity.created`; later events never merge in | `cache-build.py` (entity pass — `if ev["type"] == "entity.created": e["attrs"] = ev.get("attributes", {})`) |
| R2 | `relationships` rows with `source="frontmatter"` | Synthesised from R1's frozen `attrs` (t2_parent + milestone edges), `INSERT OR IGNORE` | `cache-build.py` (frontmatter-edge synthesis) |
| R3 | `milestone_progress` in `projection.json` | Read **live** from `planning/*.md` frontmatter at projection time | `projection-emit.py` `compute_milestone_progress()` (≈ lines 18–43) |
| R4 | `relationship.reattached` events | **Nothing** — the edge-builder reads `from_entity_id`, but reattach carries `from_parent`/`to_parent`, so every reattach event is silently skipped (dead path) | `cache-build.py` (relationship pass — `from_id = attrs.get("from_entity_id"); if not from_id: continue`) |

**Why this enables the bug.** R1/R2 are frozen at creation; R3 reflects whatever the file says *now*. So if you edit a plan's `milestone:` field:
- R3 (`milestone_progress`) picks it up — live file read.
- R1/R2 (cache entity attrs + graph edge) do **not** — they're the creation snapshot.
- The flow-view graph keeps drawing the **old** edge.
- → The cache and the projection now disagree about the same fact. Exactly the divergent-source-of-truth failure T1 was built to kill, reproduced *inside the tracker itself.*

And R4 — the event designed to express a move — does nothing, so there is no append-only way to record "this entity was reparented" at all.

**The resolution (T1 §5 Q9, now closed; see T1 addendum 2026-06-01).** Frontmatter-only is insufficient. The event log is the single source of truth. `relationship.reattached` becomes the move primitive: it rewrites the edge in the cache *and* shows in the graph, leaving an auditable trail of the reshuffle. Frontmatter `t2_parent`/`milestone` is demoted to a creation-time declaration that seeds the first edge — an input, not a parallel store.

## 2. Out of scope

- **Automated emission of reattach events** by the extraction agent — that's M2's extractor work; this T3 only makes the *consumer* (cache/projection) correct and makes manual/hand-rolled reattach work end-to-end.
- **The M3 drift audit** (`audit-frontmatter-event-drift.sql`) that flags a plan whose live frontmatter disagrees with its event-derived parent. Specified here as the safety net but built in M3. This T3 must not make the audit *impossible*, but does not implement it.
- **Retro-emitting reattach events for historical mis-parents** beyond the single analyser re-tag named in §3 (that one is the acceptance test). A broader backfill is M5.
- **Flow-view rendering changes.** The view already renders whatever edges the projection emits; once the cache folds reattach correctly, the view follows for free. No `view/` changes anticipated (confirm in §7 V5).
- **Dependency-edge moves.** `relationship.depends-on` reattachment is not in scope; this T3 covers parentage axes (thematic + milestone) only. The axis attribute (§4 D-A) is designed to extend to other axes later.

## 3. The first reattach: analyser milestone renumber + re-tag (acceptance test, deferred in from M1 close-out)

The mis-tagged analyser plans are the natural first exercise of the new machinery, now composed with a milestone **renumber** surfaced during M1.2 planning. Three moves, all via real events once the consumer is fixed. Tags below were verified against the live files on 2026-06-01:

1. **Renumber the milestone entity `M6-analyser` → `M1.1-analyser`.** It should always have been an M1 sub-milestone — analyser hardening *arising from* M1, not the 6th major milestone (see T1 §2.4 sub-milestones). `M6-analyser` is a **completed** milestone (full lifecycle ending in `entity.completed`), so the fold must carry the rename **without resurrecting it to live** — see D-F. Emit `entity.renamed` (`from_name: M6-analyser`, `to_name: M1.1-analyser`).
2. **Re-tag the 5 analyser-phase T3s** — `T3-analyser-phase-{a,b,c,d,e}-*`, currently `milestone: M6-analyser` → `M1.1-analyser`. One `relationship.reattached` each, axis `milestone`.
3. **Re-home `T3-analyser-live-model-catalog`** — currently mis-tagged `milestone: M1-bootstrap` → `M1.1-analyser` (axis `milestone`). This is the original M1-closeout mis-parent; the other `milestone: M1-bootstrap` plans (build-loop, cache-build, html-view, …) are legitimate bootstrap work and stay put.

**Acceptance:** after rebuild, `milestone_progress` shows all six analyser plans under **M1.1-analyser** (not M6-analyser, not M1-bootstrap); the milestone entity appears as **M1.1-analyser** in `completed` state, and **M6-analyser no longer materialises as a separate live/phantom entity** (no resurrection); the flow-view graph draws the M1.1 edges and *visibly records* the moves; M1-bootstrap's live count drops by one (live-model-catalog leaves). Each file's `milestone:`/`id` frontmatter is updated to match (so files aren't misleading), but the **events** are what moved the state — proving frontmatter-edit-alone is no longer the mechanism.

> Note: this renumber + re-tag was originally going to be quick frontmatter edits during M1 close-out. It was deferred into this T3 precisely because the quick edit would have *demonstrated* the bugs (R3 moves; R1/R2/graph don't; and `entity.renamed` would resurrect a dead milestone) rather than fixing them. The M6→M1.1 renumber is the canonical example and the reason D-F exists.

## 4. Design decisions

### D-A — Reattach must name the axis it moves
`relationship.reattached` currently carries only `from_parent`/`to_parent` (both strings). An entity has parents on **multiple axes** (thematic `t2_parent` *and* `milestone`), so `from_parent`/`to_parent` alone is ambiguous about which edge moves.

**Decision:** add a required `axis` attribute to the reattach event, enum `["t2-parent", "milestone"]` (extensible to `"depends-on"` etc. later). This makes the event self-describing and the fold deterministic.

**Schema impact:** this changes the required attributes of an existing event type → **bump `events.schema.json` 0.2.0 → 0.3.0**. New 0.3.0 directory; the prehistoric/0.2.0 events keep validating under their own `schema_version`. Existing reattach events in the log: there are currently **none** in `events.jsonl` (R4 has never fired), so no migration of historical reattach events is required — the first ones written will be 0.3.0 with `axis`. Confirm zero pre-existing reattach events at implementation time (§7 V1).

### D-B — Edge derivation = fold the event stream, last-write-wins per (entity, axis)
Replace the frozen-snapshot edge synthesis. For each axis, the current parent of an entity is:
1. the `to_parent` of the **most recent** `relationship.reattached` for that `(entity, axis)`, else
2. the seed from `entity.created` frontmatter (`t2_parent` / `milestone` attribute), else
3. no edge.

Process events in log order; reattach overwrites the seed. The `relationships` row records `source` (`"frontmatter-seed"` vs `"reattached"`) and `source_event_id` so provenance is queryable. Old edge is removed/replaced, not left dangling.

**Vocabulary note — why reattach reads differently from spawns (resolved 2026-06-01).** The new parent is **not missing** from a reattach event; the two event types simply use different vocabularies for the same edge:
- `relationship.spawns` uses *edge-endpoint* vocabulary — `from_entity_id` literally names the **parent endpoint**, and cache-build writes the row `(from = parent, to = child)`. So for spawns, `from_entity_id` *is* the parent.
- `relationship.reattached` uses *transition* vocabulary — it names a **move** for the event's own `entity_id` (the child): `from_parent` (old) → `to_parent` (new). The new parent is `to_parent`.

The dead-code bug is *only* that the edge loop looks exclusively for the key `from_entity_id` and skips any event lacking it (`if not from_id: continue`). This fold teaches cache-build the second dialect: for a reattach the edge is `(parent = to_parent, child = entity_id)`, ordered after the seed so the latest move wins. `from_parent` is retained purely for **audit** — the log answers "what moved, from where, to where" without replaying prior state.

### D-C — `projection-emit.py` reads parentage from the cache, not the live file
`compute_milestone_progress()` stops reading `planning/*.md` frontmatter. It reads milestone membership from the cache `relationships` table (the §D-B fold). This collapses R3 into the single event-derived source and removes the live-file divergence entirely.

### D-D — Frontmatter demoted to creation-time input
After §D-B/§D-C, `t2_parent`/`milestone` in frontmatter is the *declaration at creation* that seeds the first edge (via `entity.created` attributes). Post-creation moves require a `relationship.reattached` event. The frontmatter field should still be updated to match (so the file reads true), but it is **no longer the mechanism** — and M3's drift audit will flag mismatches. This is the behaviour change to call out loudly in the methodology text (§5 below) and in the cheatsheet.

### D-E — Methodology text must be corrected, not just code
Two prose locations currently assert the *opposite* of this resolution and must be updated in the same change so the docs don't lie:
- **T2-storage §3.8 ("Unified relationships")** currently states the frontmatter "field IS the source of truth. No event-emission required, no drift risk because the frontmatter is the single declaration." → rewrite to: frontmatter seeds; event log is authoritative; reattach is the move primitive; drift is possible and audited (M3).
- **T1 §2.4** carries the aside that milestone membership "shouldn't be a relationship event (would create noise)." → annotate as superseded by the Q9 resolution (cross-reference the §5 addendum). Keep the original text (append-only spirit), add a dated correction.

### D-F — `entity.renamed` must migrate the entity, not resurrect it
Discovered 2026-06-01 while scoping the M6→M1.1 renumber: `entity.renamed` is broken in today's `cache-build.py`, the same root-cause family as the dead reattach path (cache-build was never taught to consume the event correctly):
1. **No key migration.** The entity loop keys by `(entity_type, event entity_id)` and never rewrites an entity's id on rename. A rename therefore produces *two* cache entities — the old id (carrying the full frozen history) and a separate new id — instead of one migrated entity.
2. **Resurrection.** `STATE_FROM_EVENT["entity.renamed"] = "live"`, so consuming a rename on a **completed** entity (exactly the M6-analyser case) flips it back to live.

**Decision:** the fold treats `entity.renamed` as an **identity migration**. The renamed entity's full event history, frozen `entity.created` attributes, **and derived state** move onto `to_name`; the old id leaves **no** live/phantom entity behind; the derived state is whatever the migrated history dictates (M6-analyser stays `completed`). `entity.renamed` is **not** a state-transition event — drop it from `STATE_FROM_EVENT` (or make it explicitly state-preserving). Frontmatter `id` + filename are updated to the new name so the file reads true, but the **event** is what migrates the entity. Verified directly by the §3 M6→M1.1 renumber (`V8`).

## 5. Acceptance criteria

- `events.schema.json` 0.3.0 defines `relationship.reattached` with required `axis ∈ {t2-parent, milestone}` plus `from_parent`/`to_parent`; `validate-events.sh` passes on the whole log.
- `cache-build.py` folds reattach events: a hand-emitted reattach measurably changes the `relationships` table (old edge gone, new edge present, `source="reattached"`, correct `source_event_id`). The dead `from_entity_id` path is removed.
- `projection-emit.py` `compute_milestone_progress()` reads parentage from the cache; grepping the file shows **no** live `planning/*.md` frontmatter read for milestone membership.
- End-to-end on the analyser renumber + re-tag (§3): after `cache-build → projection-emit → summary-emit`, all six analyser plans appear under **M1.1-analyser** in `milestone_progress`, the flow-view graph shows the M1.1 edges, and M1-bootstrap's live count drops by one (live-model-catalog leaves).
- The renumbered milestone materialises as **M1.1-analyser** in `completed` state; **M6-analyser does not appear as a separate entity** (no resurrection, no phantom) — proves `entity.renamed` migrates rather than duplicates (D-F).
- Editing a plan's `milestone:` frontmatter *without* a reattach event does **not** move it in `milestone_progress` (proves the cache/projection no longer reads live frontmatter) — and is the case M3's audit will later flag.
- Idempotent rebuild (re-running the pipeline yields identical cache + projection).

## 6. Steps (high-level — expand under executing-plans)

1. **Confirm preconditions** — zero pre-existing reattach events in the log; enumerate the analyser T3s actually mis-tagged (query the cache).
2. **Schema 0.3.0** — copy 0.2.0 → 0.3.0, add `axis` to `relationship_reattached`, point the validator's "active" version forward, keep older versions valid.
3. **cache-build edge fold (D-B)** — replace frontmatter-edge synthesis + dead reattach path with the ordered fold; record `source`/`source_event_id`.
4. **projection-emit (D-C)** — repoint `compute_milestone_progress()` at the cache.
5. **Methodology text (D-E)** — rewrite T2-storage §3.8; annotate T1 §2.4; update cheatsheet if it documents milestone tagging.
6. **First reattach + renumber (§3)** — emit `entity.renamed` (M6-analyser→M1.1-analyser) + `relationship.reattached` ×6 (5 phase T3s + live-model-catalog, axis `milestone`); rename `planning/M6-analyser.md`→`M1.1-analyser.md` and update its `id`/`milestone_index`; update each re-tagged file's `milestone:` frontmatter; rebuild; verify §5.
7. **Dogfood + commit** — append `commit.recorded`; run both validators; rebuild pipeline.

## 7. Verification

- **V1** — `grep -c reattached .agent-plan-tracker/events.jsonl` before implementation = 0 (or, if non-zero, each is handled by the migration).
- **V2** — emit a throwaway reattach in a scratch log; rebuild; assert the `relationships` row flips. Revert the scratch event (red→green discipline).
- **V3** — `grep` `projection-emit.py` for any `planning/` / `.md` / `frontmatter` read in the milestone path → must be absent after D-C.
- **V4** — analyser T3s show under M6-analyser in `projection.json` and `summary.md`; M1-bootstrap live count correct; diff `projection.json` before/after to show *only* the intended membership change.
- **V5** — open `view/index.html`, confirm the flow view draws the moved edges with no `view/` code change (confirms the view is purely projection-driven).
- **V6** — frontmatter-edit-without-event control: edit one plan's `milestone:`, rebuild, assert `milestone_progress` does **not** move; then revert.
- **V7** — both validators green; pipeline idempotent.
- **V8** — rename migration (D-F): after the M6→M1.1 `entity.renamed` is folded, the cache has exactly one entity for the milestone (`M1.1-analyser`, state `completed`) and **zero** rows for `M6-analyser`; assert M6-analyser is absent from `entities` and absent as an edge endpoint in `relationships`.

## 8. HITL questions

- **Q1 (placement). RESOLVED 2026-06-01.** ~~This plan is filed `milestone: M2-auto-extract`...~~ Originally filed under the phantom `M2-auto-extract` (which has no plan file). Resolved by the operator: this plan is the sole constituent of a new focused **sub-milestone `M1.2-relationship-ssot`**, attached to M1-bootstrap. Rationale: this is *follow-up work arising from M1* (a correctness defect surfaced by M1 dogfooding), not new auto-extract capability — so it belongs as a small M1.x hardening milestone, not folded into M2. Filing it under M1.2 (not M1-bootstrap directly) keeps it from blocking M1's close. This required a backward-compatible loosening of `plan-frontmatter.schema.json` to permit decimal milestone ids (`M[0-9]+(\.[0-9]+)?`) and a numeric `milestone_index`. The earlier alternatives (standalone hardening milestone / no-milestone-park) are subsumed: M1.2 *is* the focused hardening milestone, and the schema still requires a milestone for tier-3 thematic plans (no relaxation of that rule). Note: the move from `M2-auto-extract`→`M1.2` is itself recorded as the first real `relationship.reattached` event (see §7/events), inert until this plan lands.
- **Q2 (schema version).** Bump to 0.3.0 (adds required `axis`). Confirm we version-bump rather than retrofit 0.2.0 in place — consistent with the project's `schema_version`-per-event discipline.
- **Q3 (axis vocabulary).** `{t2-parent, milestone}` now; is `depends-on` / `alongside` reattachment foreseen soon enough to design the enum wider today? Lean: keep it to the two parentage axes; extend when needed.
- **Q4 (M6→M1.1 renumber). RESOLVED 2026-06-01 (operator-directed).** "Rename M6 to M1.1 now" was the trigger; scoping it revealed `entity.renamed` is inert + resurrects-to-live (D-F), and that the rename is just another representation-divergence on a *completed* milestone. Resolution: the renumber is **not** a separate housekeeping edit — it is folded into this T3 as the headline of the §3 acceptance test (the move that needs working rename+reattach folding to be expressible at all). Doing it by hand before T3 lands would either dirty the cache (resurrection/phantom) or pre-empt the acceptance test, so it is deliberately deferred to here. (This supersedes M1.2 §4's earlier "separate housekeeping change" note.)

## 9. Files to create / modify

- **Create:** `agent-plan-tracker/schemas/0.3.0/events.schema.json` (+ sibling schemas copied forward as needed).
- **Modify:** `agent-plan-tracker/scripts/cache-build.py` (edge fold; remove dead reattach path; `entity.renamed` identity-migration per D-F + drop from `STATE_FROM_EVENT`).
- **Modify:** `agent-plan-tracker/scripts/projection-emit.py` (`compute_milestone_progress` → cache).
- **Modify:** `planning/T2-storage.md` §3.8; `planning/T1-top-level.md` §2.4 (dated correction).
- **Append:** `.agent-plan-tracker/events.jsonl` — `entity.renamed` (M6→M1.1) + the analyser-retag reattach events ×6 + `commit.recorded`.
- **Rename:** `planning/M6-analyser.md` → `planning/M1.1-analyser.md`; update its `id` (M6-analyser→M1.1-analyser) and `milestone_index` (6→1.1).
- **Modify:** each re-tagged analyser plan's `milestone:` frontmatter — `T3-analyser-phase-{a..e}-*.md` (M6-analyser→M1.1-analyser) and `T3-analyser-live-model-catalog.md` (M1-bootstrap→M1.1-analyser).
- **Possibly:** `cheatsheet/` entry on "moving an entity between parents = emit reattach, don't just edit frontmatter".

## 10. Events this T3 will emit

- `entity.progressed` on T2-storage (edge-fold landed) and T2-projection (projection repointed).
- `entity.renamed` on the analyser milestone (M6-analyser→M1.1-analyser) — the first real use of the event; exercises the D-F identity migration.
- `relationship.reattached` ×6 on the analyser plans (5 phase T3s + live-model-catalog, axis `milestone`) — the first real uses of the event.
- `verification.tested` on T3-event-sourced-relationships (test_type: `reattach-fold` + `frontmatter-edit-noop`).
- `entity.completed` on T3-event-sourced-relationships.
- `entity.progressed` on M1.2-relationship-ssot (its host milestone) as constituent work lands.
- `commit.recorded`.
