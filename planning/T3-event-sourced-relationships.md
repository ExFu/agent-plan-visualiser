---
id: T3-event-sourced-relationships
plan_kind: thematic
tier: 3
t2_parent: T2-storage
milestone: M1.2-relationship-ssot
status: draft
---

# T3-event-sourced-relationships — make milestone *membership* a projection of the cache, not a live-file read

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Placement is confirmed (§8 Q1): this plan is the sole constituent of milestone **M1.2-relationship-ssot** (a focused M1 follow-up).
>
> **This is a DELTA plan on `main` (merge 3d2d443 / base 6c68f1b).** A large part of the original SSOT design *already shipped* on `main` via two completed T3s — read both before implementing: [[T3-milestone-parent-ontology]] (reattach machinery + milestone-parent rule) and [[T3-lifecycle-term-closed]] (`dead`→`closed`). This plan keeps **only the one piece that remains genuinely unbuilt** and records which original decisions `main` superseded. See §0.

---

## 0. What `main` already shipped vs. what this delta adds

The original draft of this T3 proposed five design decisions (D-A…D-F). `main`'s parallel close-out work shipped most of the machinery — under different, equally-valid choices — so this delta is now small and single-concern. Verified against `cache-build.py` / `projection-emit.py` on 2026-06-01 (post-merge):

| Original decision | Status on `main` | This delta |
|---|---|---|
| **D-B** edge fold: reattach rewrites the spawn graph, last-write-wins | ✅ **Shipped** ([[T3-milestone-parent-ontology]] D3). `cache-build.py:207-267` pre-scans reattachments into `reattach_new` + `suppressed_spawns`, drops the old spawn edge (event **and** frontmatter sources, lines 251/285/294), inserts the new one. Dead `from_entity_id` path no longer skips reattach. | **Adopt as-is.** No change. |
| **D-A** add required `axis` to reattach; bump schema 0.2.0→0.3.0 | ❌ **Not shipped, and now unnecessary.** `main` keys suppression on `(from_parent, child_id)`. A plan's `t2_parent` is a `T2-*` id and its `milestone` is an `M*` id — they never collide — so `from_parent` *alone* already disambiguates which axis moves. The fold is deterministic without an axis discriminator. | **DROPPED.** See §4 D-A (superseded). No schema bump; reattach stays 0.2.0. |
| **D-C** projection reads milestone *membership* from the cache, not live frontmatter | ❌ **Not shipped.** [[T3-milestone-parent-ontology]] §5 explicitly left this out ("milestone *membership* … unaffected; still frontmatter"). `projection-emit.compute_milestone_progress` (`:18-51`) still globs `planning/T3-*.md` and reads the live `milestone:` field. | **THE CORE OF THIS DELTA.** §4 D-C. Resolves T1 §5 Q9. |
| **D-D** frontmatter demoted to creation seed | ◑ **True in the cache already** — the frontmatter milestone edge reads frozen `entity.created` attrs (`cache-build.py:165,282,293`), not the live file (live read is only a fallback for entities with no `entity.created`, `:167-193`). But the *projection* still bypasses this. | Completed **for membership** once D-C lands. Behaviour to document. |
| **D-E** correct the methodology prose that asserts the opposite | ◑ **Partially shipped.** [[T3-milestone-parent-ontology]] D4 corrected T1 §2.4 + T2-ontology §3.6/§3.8. **T2-storage §3.8 (line 205/228) was *not* touched** — it still says the frontmatter "field IS the source of truth … no drift risk." | **Correct T2-storage §3.8.** §4 D-E. |
| **D-F** `entity.renamed` must migrate identity + state, not resurrect | ❌ **Not shipped** (`cache-build.py:22` still maps `entity.renamed→"live"`; no key migration). Only *needed* for the M6→M1.1 rename. | **DROPPED** with the rename. See §3 + §8 Q4. |

**Net delta:** one function repoint (D-C) + one prose fix (D-E) + one acceptance reattach (§3). No schema change, no `entity.renamed` work, no rename.

## 1. Why this T3 (after the merge)

The single-source-of-truth defect this milestone exists to kill is now reduced to **one** surviving divergence. `main` made the *cache* relationship graph event-sourced (reattach rewrites it; the frontmatter seed comes from frozen `entity.created` attrs). But the **milestone progress projection** still reads membership a second, independent way:

- `compute_milestone_progress()` globs `planning/T3-*.md` and reads each file's **live** `milestone:` field (`projection-emit.py:25,35`).

So a plan's milestone membership is still represented twice that can disagree:
- **Cache** (`relationships`, `milestone spawns T3`): frozen seed + reattach events — event-sourced, SSOT.
- **`milestone_progress`** (projection): whatever the live file says *now*.

Edit a plan's `milestone:` field and the projection's counts move while the cache graph does not (no reattach event); emit a reattach without editing the file and the cache graph moves while the projection's counts do not. That is the exact R1↔R3 divergence T1 §3.1/§3.2 forbid — now isolated to a single function. This delta collapses R3 into the cache source.

## 2. Out of scope

- **Everything `main` already shipped** (§0): reattach fold, milestone-parent rule, `dead`→`closed`, M6 reparent. Adopt, don't re-touch.
- **The M6→M1.1 rename / `entity.renamed` migration (D-F).** Adopting `main`'s grandfather decision; see §3 + §8 Q4.
- **The M3 drift audit** (`audit-frontmatter-event-drift.sql`) that flags a plan whose live `milestone:` disagrees with its event-derived parent. This delta makes that audit *meaningful* (the two sources can now provably differ) but does not build it — M3-clean-gate.
- **`t2_parent`-axis membership in the projection.** `compute_milestone_progress` is milestone-only; the thematic axis isn't surfaced as a progress projection today, so there's nothing to repoint. The cache `t2_parent` edge is already event-sourced. If a thematic progress projection is added later it reads the cache by construction.
- **Automated emission of reattach events** by the extractor — M2.
- **Broader historical backfill** of mis-parents beyond the single §3 re-tag — M5.

## 3. Acceptance test: re-tag the mis-filed analyser plan (real reattach drives the projection)

`main` reparented the **milestone node** `M6-analyser → M1-bootstrap` (its own parent on the when-axis) and **kept the label** (grandfathered — see [[T3-milestone-parent-ontology]] D2/DEC-2). This delta does **not** rename it. What `main` did *not* fix is a **membership** mis-tag surfaced during M1 close-out:

- `T3-analyser-live-model-catalog` is tagged `milestone: M1-bootstrap` (verified 2026-06-01) but is analyser work — it belongs under `M6-analyser` alongside its sibling phase T3s (`T3-analyser-phase-{a..e}-*`, already `milestone: M6-analyser`). In the cache this shows as the frontmatter edge `M1-bootstrap spawns T3-analyser-live-model-catalog`.

**The test.** Move it with a real `relationship.reattached` event (axis-less, per D-A-dropped):

```json
{"type":"relationship.reattached","entity_type":"plan","entity_id":"T3-analyser-live-model-catalog",
 "attributes":{"from_parent":"M1-bootstrap","to_parent":"M6-analyser",
   "summary":"Mis-filed under M1-bootstrap during early M1 work; it is analyser work and belongs under M6-analyser with the other analyser-phase T3s. First membership reattach exercising the D-C projection repoint."}}
```

Then update the file's `milestone:` frontmatter to `M6-analyser` so the file reads true — **but the event is the mechanism**, not the edit.

**Acceptance:**
1. `cache-build` (main's fold) suppresses the `M1-bootstrap spawns live-model-catalog` frontmatter edge and inserts `M6-analyser spawns live-model-catalog` (`source=event`). *(Already works on main — this is the fold, not the new code.)*
2. After **D-C**, `milestone_progress` shows `T3-analyser-live-model-catalog` under **M6-analyser**, not M1-bootstrap — **derived from the cache edge, which moved because of the event.**
3. **Frontmatter-edit-alone control (the real proof):** in a scratch check, revert *only* the file's `milestone:` field (leave the event) → rebuild → `milestone_progress` is **unchanged** (still M6-analyser, because membership now comes from the cache fold, not the file). Restore. This is the assertion that frontmatter-edit-alone is no longer the mechanism.
4. `M6-analyser` keeps its label and `completed` state (grandfathered; no resurrection, because no `entity.renamed`).

This is a strictly smaller acceptance test than the original draft's (which renumbered M6 and re-tagged six plans). It exercises exactly the one new behaviour (D-C) against exactly the one real mis-tag.

> **Note on `live-model-catalog`'s state.** It is `completed`/`closed`, so re-tagging it does **not** change M1-bootstrap's *live* count — M1's close is not gated on this. It's a correctness re-home and the cleanest available D-C fixture.

## 4. Design decisions (delta)

### D-A — ~~Reattach must name the axis it moves~~ **DROPPED (superseded by main)**
The original draft argued `from_parent`/`to_parent` was ambiguous across the `t2_parent` and `milestone` axes and added a required `axis` enum + a 0.2.0→0.3.0 schema bump. **`main` disproved the premise:** its fold keys suppression on `(from_parent, child_id)` (`cache-build.py:225,251,285,294`). Because a plan's `t2_parent` is always a `T2-*` id and its `milestone` always an `M*` id, `from_parent` alone names the axis unambiguously. The axis attribute buys nothing for determinism. **Decision: do not add `axis`; do not bump the schema.** Reattach stays `0.2.0`. (If a future axis is added whose parent-id space *could* collide — e.g. two milestone-like parents — revisit then.)

### D-C — `projection-emit.compute_milestone_progress` reads membership from the cache *(THE CORE)*
Replace the live-file glob with a read of the cache `relationships` table.

- **Current** (`projection-emit.py:18-51`): globs `planning/T3-*.md`, reads `fm["milestone"]`, aggregates per-milestone scheduled/live/completed counts (status joined from the `entities` dict).
- **After:** membership comes from `relationships` rows where `relationship_type='spawns'`, `from_entity_id` is a milestone (`^M[0-9]`), `to_entity_id` is a T3 plan (preserve the current T3-only semantics — filter children to `to_entity_id LIKE 'T3%'` / `plan_kind thematic, tier 3`). The status join keeps using the cache `entities` dict (already event-derived). No `glob`, no `yaml`, no `planning/*.md` read in this function.
- The function needs the relationships; either pass them in from `main()` (which already loads them, `:69`) or query the open connection. Implementation detail for executing-plans.

This collapses R3 into the same event-sourced source as the cache graph. Membership becomes: frozen `entity.created` seed, rewritten by `relationship.reattached` — identical to how `main`'s cache graph already works. Editing `milestone:` alone stops moving the projection.

### D-D — Frontmatter is a creation-time seed (for membership: now true end-to-end)
With D-C, the only authoritative read of milestone membership is the cache fold. The live `milestone:` field is the **seed** (via `entity.created` attrs) and should still be kept truthful in the file, but post-creation moves require a `relationship.reattached` event. Drift between the live field and the event-derived parent becomes **possible-but-detectable** (M3 audit), not silently authoritative. Call this out in the methodology text (D-E) and the cheatsheet.

### D-E — Correct T2-storage §3.8 (the one prose location main left contradicting)
`main` corrected T1 §2.4 and T2-ontology §3.6/§3.8. **T2-storage §3.8 still asserts the opposite** and must be fixed in this change so the docs don't lie:
- **Line 205** — "the field IS the source of truth. No event-emission required, no drift risk because the frontmatter is the single declaration." → rewrite: for *membership as projected*, the **cache fold (seed + reattach) is authoritative**; the frontmatter field is the creation seed; moves are events; drift is possible and audited (M3).
- **Line 228** — frames event-sourced membership as a hypothetical "could collapse if we later wanted single-source-of-truth event semantics." → annotate as **realised** by this T3 (dated correction; keep the original text in append-only spirit, add the correction beneath it).
- Cross-reference [[T3-milestone-parent-ontology]] (the cache-side fold) so the two halves read as one design.

### D-F — ~~`entity.renamed` must migrate, not resurrect~~ **DROPPED (rename not done)**
Only needed if M6 is renamed to M1.1. `main` grandfathered the label and reparented the node instead (DEC-2: load-bearing filename + ~20-event churn + historical honesty), which already expresses "M6 is really M1.1" as a graph edge. **Decision: adopt the grandfather; do not rename; leave `entity.renamed` as-is for now.** The `entity.renamed` resurrection/no-migration bug is real but is now **dormant dead code** (no rename event will be emitted by this milestone). If a rename is ever wanted, D-F's analysis is preserved here and becomes its own scope. (See §8 Q4.)

## 5. Acceptance criteria

- `projection-emit.compute_milestone_progress()` reads milestone membership from the cache `relationships` table; grepping the function shows **no** `glob`, **no** `planning/*.md` read, **no** `yaml` import for membership.
- The §3 reattach moves `T3-analyser-live-model-catalog` to `M6-analyser` in `milestone_progress`, **and** the frontmatter-edit-alone control (§3.3) is a **no-op** in `milestone_progress` — proving membership is event-derived.
- `M6-analyser` retains its label and `completed` state; **no** `entity.renamed` emitted; no resurrection/phantom.
- No schema change: reattach events remain `0.2.0` and validate; `validate-events.sh` green on the whole log.
- T2-storage §3.8 no longer claims frontmatter is the sole source of truth for membership; the correction cross-references the cache fold.
- `repack-validate.sh` green end-to-end; rebuild is idempotent (re-running yields identical cache + projection).

## 6. Steps (high-level — expand under executing-plans)

1. **Confirm preconditions** — re-verify `compute_milestone_progress` still globs files; enumerate cache `milestone spawns T3` edges; confirm `live-model-catalog` is the only mis-tagged membership (others conform).
2. **D-C — repoint `compute_milestone_progress`** at the cache `relationships` table; preserve T3-only counting semantics and the status join from the `entities` dict; remove the file glob.
3. **D-E — correct T2-storage §3.8** (lines 205/228) with a dated correction; cross-reference [[T3-milestone-parent-ontology]]; update cheatsheet if it documents milestone tagging ("move = reattach event, not just a frontmatter edit").
4. **§3 acceptance reattach** — append the `relationship.reattached` for `live-model-catalog` (M1-bootstrap→M6-analyser); update the file's `milestone:` to `M6-analyser`; rebuild; verify §5 including the frontmatter-edit-alone control.
5. **Dogfood + commit** — append `entity.progressed` (T2-storage doc; T2-projection code), `verification.tested` + `entity.completed` on this T3, `entity.progressed` on M1.2; `commit.recorded` LAST; run validators; rebuild pipeline.

## 7. Verification

- **V1** — `grep -nE "glob|planning/|\.md|yaml" projection-emit.py` shows none of these inside `compute_milestone_progress` after D-C.
- **V2** — diff `projection.json` `milestone_progress` before/after the §3 reattach: the *only* change is `live-model-catalog` moving M1-bootstrap→M6-analyser (and the corresponding count deltas).
- **V3 (the SSOT proof)** — frontmatter-edit-alone control: revert only `live-model-catalog`'s `milestone:` field (keep the event), rebuild, assert `milestone_progress` is unchanged; restore. *(red→green discipline; the assertion that fails on `main` and passes after D-C.)*
- **V4** — `M6-analyser` present once, `completed`, label intact; no `M1.1-analyser` entity exists; no `entity.renamed` in the log for this milestone.
- **V5** — open the flow view; the moved membership edge renders with **no** `view/` change (view is purely projection/cache-driven).
- **V6** — both validators green; `repack-validate.sh` 8/8; pipeline idempotent.

## 8. HITL questions

- **Q1 (placement). RESOLVED 2026-06-01.** Sole constituent of sub-milestone **M1.2-relationship-ssot** (a focused M1 follow-up), attached to M1-bootstrap. Required the backward-compatible `plan-frontmatter.schema.json` loosening for decimal milestone ids — already merged. Unchanged by the delta.
- **Q2 (schema version). RESOLVED — no bump.** D-A dropped; reattach stays `0.2.0` (§0, §4 D-A). The original 0.3.0 proposal is withdrawn.
- **Q3 (axis vocabulary). RESOLVED — not added.** `main`'s `(from_parent, child_id)` suppression is unambiguous across the two parentage axes (§4 D-A). Revisit only if a future axis introduces a colliding parent-id space.
- **Q4 (M6→M1.1 renumber). RESOLVED 2026-06-01 (operator-directed) — DROPPED.** The original draft folded the rename into this T3 as its headline acceptance test. After the merge revealed `main` had already **reparented M6→M1-bootstrap and grandfathered the label** (DEC-2), the operator chose to **adopt the grandfather and drop the rename** (the reparent edge already expresses "M6 is really M1.1"; renaming would churn the load-bearing filename + ~20 events and require building the `entity.renamed` migration D-F for no functional gain). The acceptance test is re-scoped to the `live-model-catalog` membership re-tag (§3), which exercises the actual new behaviour (D-C). This supersedes the earlier "renumber is in scope" note in M1.2 §4 and §3/§4 D-F of this plan's prior draft.

## 9. Files to create / modify

- **Modify:** `agent-plan-tracker/scripts/projection-emit.py` — `compute_milestone_progress` reads the cache `relationships` table (D-C); drop the `planning/*.md` glob.
- **Modify:** `planning/T2-storage.md` §3.8 (lines 205/228) — dated correction (D-E).
- **Modify:** `planning/T3-analyser-live-model-catalog.md` — `milestone:` `M1-bootstrap` → `M6-analyser` (file follows the event).
- **Append:** `.agent-plan-tracker/events.jsonl` — the §3 `relationship.reattached` (0.2.0) + dogfooding events (§10) + `commit.recorded` LAST.
- **Possibly:** `cheatsheet/` — "moving an entity between milestones = emit `relationship.reattached`, don't just edit `milestone:`".
- **NOT touched:** `cache-build.py` (main's fold adopted as-is), `schemas/` (no bump), `planning/M6-analyser.md` (grandfathered), T1 §2.4 / T2-ontology (already corrected on main).

## 10. Events this T3 will emit

- `relationship.reattached` ×1 — `T3-analyser-live-model-catalog` (`from_parent: M1-bootstrap`, `to_parent: M6-analyser`); the first real **membership** reattach (0.2.0, axis-less).
- `entity.progressed` on T2-projection (D-C landed) and T2-storage (§3.8 doc correction).
- `verification.tested` on T3-event-sourced-relationships (`test_type: membership-from-cache` + `frontmatter-edit-noop`).
- `entity.completed` on T3-event-sourced-relationships.
- `entity.progressed` on M1.2-relationship-ssot (host milestone) as this lands.
- `commit.recorded` (LAST).
