---
id: M6-dashboard
plan_kind: milestone
milestone_index: 6
status: draft
---

# M6-dashboard — the dashboard surfaces what needs attention

**Status**: Draft, awaiting operator acceptance.
**Sits at**: Top-level milestone on the sequence axis, hung off T1 per the milestone-parent rule (§2.4.0). Its T3s all land in T2-projection.

---

## 1. Why this milestone

The record computes far more than the dashboard shows. M5.1-operator-attention built the *attention* capability — pending ceremonies, deferred verifications, untriaged ages — but surfaced it only in `summary.md` and the gate output. The browser view renders none of it, and none of the `decisions`/`milestone_progress` data the projection already emits. The result is two disjoint reporting surfaces: a reviewer must read a markdown file *and* open the view to get the full picture, and the richest "what needs the operator" signal the project computes is invisible in the surface people actually look at.

Alongside that gap, the 2026-07-21 assessment verified two live view defects (a `ReferenceError` breaking the plan-markdown panel; a dogfood path hardcode breaking saved summaries for `.apv/` adopters) and confirmed board/tree have no filtering or search at 77 entities.

**Capability unlock**: the dashboard becomes the operator's complete window — it prompts (attention queues), explains (decision text on fulcrum arcs), and narrows (search/filter everywhere) — without opening `summary.md` or the raw log.

## 2. How — T3 tasks

All under T2-projection, scheduled into this milestone:

1. **`T3-view-defect-fixes`** — the two verified defects: `showPlanMarkdown` undefined-variable crash; saved-summary freeform fetch bypassing the `/data/` route.
2. **`T3-view-attention-panel`** — render the `attention` block + `milestone_progress` in the view; wire `decisions` (`explains_arcs`) into the flow view so fulcrum nodes reveal their paired decision text.
3. **`T3-html-view-interactivity`** — text search + lifecycle filter on board and tree (the name T2-projection §5 reserved for this).

## 3. Definition of done

- Clicking any entity name renders its plan/inbox markdown with no console errors; saved-summary freeform loads through `/data/` in a non-dogfood layout.
- The view shows the same *Awaiting operator* content as `summary.md` (pending acceptance, pending closure, open deferrals) and per-milestone progress, from `projection.json` alone.
- Clicking a fulcrum node/arc in the flow view surfaces its paired decision text.
- Board and tree narrow by text search and lifecycle state; flow behaviour unregressed.
- All suites green (`repack-validate.sh`); gate green on the branch and the main move.

## 4. Out of scope

- Time-travel/snapshot selector, dark theme, incremental projection emit — real candidates, separately schedulable; this milestone is attention + interrogation + the verified defects.
- Any emitter/schema change — the data contract already exists; this is view-side work.
- The client-side fold duplication (view re-deriving rename/membership from raw events) — structural pay-down worth its own plan; not bundled here.
