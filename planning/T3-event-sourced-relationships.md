---
id: T3-event-sourced-relationships
plan_kind: thematic
tier: 3
t2_parent: T2-storage
milestone: M2-auto-extract
status: draft
---

# T3-event-sourced-relationships — make the event log the single source of truth for entity relationships

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Do NOT start until placement (§8 Q1) is confirmed.

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

## 3. The first reattach: analyser milestone re-tag (acceptance test, deferred in from M1 close-out)

The mis-tagged analyser T3s are the natural first exercise of the new machinery. Once the consumer is fixed, emit one `relationship.reattached` per mis-tagged entity:

- `T3-analyser-live-model-catalog`: axis `milestone`, `from_parent: M1-bootstrap` → `to_parent: M6-analyser` (and, if also thematically mis-parented, axis `t2_parent` `T2-projection`/whatever → `T2-analyser`).
- Repeat for the other analyser-phase T3s tagged `milestone: M1-bootstrap` that belong under `M6-analyser` (enumerate at implementation time from the cache, not from memory).

**Acceptance:** after rebuild, `milestone_progress` shows these T3s under M6-analyser (not M1-bootstrap); the flow-view graph draws the M6 edge and *visibly records* the move; M1-bootstrap's live count drops accordingly. The frontmatter `milestone:` field of each file is updated to match (so the file isn't misleading), but the **event** is what moved the state — proving frontmatter-edit-alone is no longer the mechanism.

> Note: this re-tag was originally going to be a quick frontmatter edit during M1 close-out. It was deferred into this T3 precisely because the quick edit would have *demonstrated* the bug (R3 moves, R1/R2/graph don't) rather than fixing it.

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

### D-C — `projection-emit.py` reads parentage from the cache, not the live file
`compute_milestone_progress()` stops reading `planning/*.md` frontmatter. It reads milestone membership from the cache `relationships` table (the §D-B fold). This collapses R3 into the single event-derived source and removes the live-file divergence entirely.

### D-D — Frontmatter demoted to creation-time input
After §D-B/§D-C, `t2_parent`/`milestone` in frontmatter is the *declaration at creation* that seeds the first edge (via `entity.created` attributes). Post-creation moves require a `relationship.reattached` event. The frontmatter field should still be updated to match (so the file reads true), but it is **no longer the mechanism** — and M3's drift audit will flag mismatches. This is the behaviour change to call out loudly in the methodology text (§5 below) and in the cheatsheet.

### D-E — Methodology text must be corrected, not just code
Two prose locations currently assert the *opposite* of this resolution and must be updated in the same change so the docs don't lie:
- **T2-storage §3.8 ("Unified relationships")** currently states the frontmatter "field IS the source of truth. No event-emission required, no drift risk because the frontmatter is the single declaration." → rewrite to: frontmatter seeds; event log is authoritative; reattach is the move primitive; drift is possible and audited (M3).
- **T1 §2.4** carries the aside that milestone membership "shouldn't be a relationship event (would create noise)." → annotate as superseded by the Q9 resolution (cross-reference the §5 addendum). Keep the original text (append-only spirit), add a dated correction.

## 5. Acceptance criteria

- `events.schema.json` 0.3.0 defines `relationship.reattached` with required `axis ∈ {t2-parent, milestone}` plus `from_parent`/`to_parent`; `validate-events.sh` passes on the whole log.
- `cache-build.py` folds reattach events: a hand-emitted reattach measurably changes the `relationships` table (old edge gone, new edge present, `source="reattached"`, correct `source_event_id`). The dead `from_entity_id` path is removed.
- `projection-emit.py` `compute_milestone_progress()` reads parentage from the cache; grepping the file shows **no** live `planning/*.md` frontmatter read for milestone membership.
- End-to-end on the analyser re-tag (§3): after `cache-build → projection-emit → summary-emit`, the analyser T3s appear under M6-analyser in `milestone_progress`, the flow-view graph shows the M6 edge, and M1-bootstrap's live count is correct.
- Editing a plan's `milestone:` frontmatter *without* a reattach event does **not** move it in `milestone_progress` (proves the cache/projection no longer reads live frontmatter) — and is the case M3's audit will later flag.
- Idempotent rebuild (re-running the pipeline yields identical cache + projection).

## 6. Steps (high-level — expand under executing-plans)

1. **Confirm preconditions** — zero pre-existing reattach events in the log; enumerate the analyser T3s actually mis-tagged (query the cache).
2. **Schema 0.3.0** — copy 0.2.0 → 0.3.0, add `axis` to `relationship_reattached`, point the validator's "active" version forward, keep older versions valid.
3. **cache-build edge fold (D-B)** — replace frontmatter-edge synthesis + dead reattach path with the ordered fold; record `source`/`source_event_id`.
4. **projection-emit (D-C)** — repoint `compute_milestone_progress()` at the cache.
5. **Methodology text (D-E)** — rewrite T2-storage §3.8; annotate T1 §2.4; update cheatsheet if it documents milestone tagging.
6. **First reattach (§3)** — emit `relationship.reattached` events for the analyser re-tag; update each file's frontmatter to match; rebuild; verify §5.
7. **Dogfood + commit** — append `commit.recorded`; run both validators; rebuild pipeline.

## 7. Verification

- **V1** — `grep -c reattached .agent-plan-tracker/events.jsonl` before implementation = 0 (or, if non-zero, each is handled by the migration).
- **V2** — emit a throwaway reattach in a scratch log; rebuild; assert the `relationships` row flips. Revert the scratch event (red→green discipline).
- **V3** — `grep` `projection-emit.py` for any `planning/` / `.md` / `frontmatter` read in the milestone path → must be absent after D-C.
- **V4** — analyser T3s show under M6-analyser in `projection.json` and `summary.md`; M1-bootstrap live count correct; diff `projection.json` before/after to show *only* the intended membership change.
- **V5** — open `view/index.html`, confirm the flow view draws the moved edges with no `view/` code change (confirms the view is purely projection-driven).
- **V6** — frontmatter-edit-without-event control: edit one plan's `milestone:`, rebuild, assert `milestone_progress` does **not** move; then revert.
- **V7** — both validators green; pipeline idempotent.

## 8. HITL questions

- **Q1 (placement — needs sign-off before implementation).** This plan is filed `milestone: M2-auto-extract` because (a) it must **not** sit under M1-bootstrap (an open M1 T3 is exactly what keeps M1 from closing — the problem we're clearing), and (b) M2's extractor will be the primary *producer* of reattach events, and projections must be trustworthy before automation leans on them. Caveat: `M2-auto-extract.md` does not yet exist (only `M1-bootstrap.md` and `M6-analyser.md` are authored), so this is a T3 authored ahead of its milestone plan. **Alternatives:** (i) promote to a standalone "architecture hardening" milestone (the user noted appetite for inserted milestones — "M6 should've been M1.1"); (ii) park under `T2-storage` with no milestone until M2 is authored (would require relaxing the schema's tier-3 `milestone` requirement — reject). Recommend M2-auto-extract; confirm or redirect.
- **Q2 (schema version).** Bump to 0.3.0 (adds required `axis`). Confirm we version-bump rather than retrofit 0.2.0 in place — consistent with the project's `schema_version`-per-event discipline.
- **Q3 (axis vocabulary).** `{t2-parent, milestone}` now; is `depends-on` / `alongside` reattachment foreseen soon enough to design the enum wider today? Lean: keep it to the two parentage axes; extend when needed.

## 9. Files to create / modify

- **Create:** `agent-plan-tracker/schemas/0.3.0/events.schema.json` (+ sibling schemas copied forward as needed).
- **Modify:** `agent-plan-tracker/scripts/cache-build.py` (edge fold; remove dead reattach path).
- **Modify:** `agent-plan-tracker/scripts/projection-emit.py` (`compute_milestone_progress` → cache).
- **Modify:** `planning/T2-storage.md` §3.8; `planning/T1-top-level.md` §2.4 (dated correction).
- **Append:** `.agent-plan-tracker/events.jsonl` — the analyser-retag reattach events + `commit.recorded`.
- **Modify:** each mis-tagged analyser `planning/T3-analyser-*.md` frontmatter `milestone:`.
- **Possibly:** `cheatsheet/` entry on "moving an entity between parents = emit reattach, don't just edit frontmatter".

## 10. Events this T3 will emit

- `entity.progressed` on T2-storage (edge-fold landed) and T2-projection (projection repointed).
- `relationship.reattached` ×N on the analyser T3s (axis `milestone`, and `t2-parent` where applicable) — the first real uses of the event.
- `verification.tested` on T3-event-sourced-relationships (test_type: `reattach-fold` + `frontmatter-edit-noop`).
- `entity.completed` on T3-event-sourced-relationships.
- `entity.progressed` on M2-auto-extract (once that milestone plan exists) or its confirmed host.
- `commit.recorded`.
