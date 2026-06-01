---
id: T3-milestone-parent-ontology
plan_kind: thematic
tier: 3
t2_parent: T2-ontology
milestone: M1-bootstrap
status: completed
---

# T3-milestone-parent-ontology — Milestones hang off Tier-1 (never T2/T3); reattached supersedes the prior spawn; M6 reparented to M1

> **For Claude:** This is the data/ontology half of the operator review whose view half is [[T3-flow-view-controls]]. It defines a missing ontology rule (what a milestone's spawn-parent may be), exercises the `relationship.reattached` primitive for the first time (designed in the T1 bootstrap events but never used), teaches `cache-build.py` to honour it, and corrects one live datum (`M6-analyser`'s parent). No view-layer code here; it touches `events.jsonl`, `scripts/cache-build.py`, and the methodology docs ([[T1-top-level]] §2.4, [[T2-ontology]] §3.6/§3.8). Shares no files with [[T3-flow-view-controls]].
>
> Read [[T2-ontology]] §3.6 (the 5 relationship types) and [[T1-top-level]] §2.4 (milestone plans + the two orthogonal axes) before implementing.

---

## 1. Why (the job)

Two coupled defects from the operator review:

- **(item 6) Milestones and themes are spawning each other.** `M6-analyser` is recorded as spawned by `T2-analyser` (event `c2a00004`). That crosses the two orthogonal axes the methodology insists on keeping separate ([[T1-top-level]] §2.4): a milestone (the *when*) should not hang off a theme (the *where*). The ontology never actually stated **what a milestone's own spawn-parent may be** — §2.4 defines how T3s attach to milestones but is silent on how milestones attach to anything. That gap let the bad edge through.
- **(item 3) Hiding `T2-analyser` wrongly hides `M6-analyser`.** A direct consequence of the bad edge: in the flow view's spawn graph, `M6` is a child of `T2-analyser`, so the cascade drags it under. (The view's cascade logic itself is correct and unchanged — the fix is the underlying data + the rule that prevents the edge.)

The operator's framing: *"M6 should really have been M1.1"* — i.e. M6 is conceptually a sub-milestone of M1 (the bootstrap capability), and the analyser shipped as part of getting the project working end-to-end. That yields the general rule below.

## 2. What (the rule, the data fix, the machinery, the docs)

### D1 — The milestone-parent rule (ontology, item 6)

State and document the rule:

> **A top-level milestone `Mn` hangs off a Tier-1 plan** (the project's intent) **or off a top-level side-quest's Tier-1-equivalent** (e.g. `P1` heading a `PT*` workstream). **Never off a T2 or T3.** A milestone is a *when-axis* node; its parent is the *intent* it sequences toward, not a theme.
>
> **Sub-milestones nest on the milestone axis:** `Mn.p` hangs off `Mn`; `Mn.p.q` hangs off `Mn.p`; and so on. The dotted index expresses "this is a finer-grained delivery slice of its parent milestone."

So the only legal spawn-parents of a milestone are: a Tier-1 plan, a top-level side-quest head, or (for a sub-milestone) its parent milestone. `T2-analyser → M6` violates this; `T1-top-level → M1-bootstrap` (event `c1000001`) satisfies it (verified: M1 is the only other milestone with an explicit parent edge, and it conforms).

**Naming vs. parenting.** `M6` *should* have been authored as `M1.1`. We **keep the label `M6-analyser`** (and `milestone_index: 6`) for historical honesty — renaming would churn ~20 events and the id is load-bearing as a filename — and instead **reparent** it to `M1-bootstrap`, which expresses exactly the "hangs off M1" relationship the dotted notation would have. The dotted `Mn.p` scheme is introduced as methodology for *future* sub-milestones; existing flat indices are grandfathered.

### D2 — Reparent M6 (data correction, item 3)

Emit (append-only — never edit `c2a00004`):

```json
{"type":"relationship.reattached","entity_type":"plan","entity_id":"M6-analyser",
 "attributes":{"from_parent":"T2-analyser","to_parent":"M1-bootstrap",
   "summary":"M6 crossed the theme/milestone axes (spawned by T2-analyser). Per the milestone-parent rule, a milestone hangs off a Tier-1 plan; M6 is conceptually M1.1 (the analyser was part of getting this project working end-to-end), so it reattaches to M1-bootstrap. Label/index kept for historical honesty."}}
```

…paired with a `decision` event (referencing the reattached event id) that records the rule itself, since introducing a methodology rule is decision-worthy. This is the **first real `relationship.reattached` event** in the log — the primitive was designed in the bootstrap (`entity.extended` events on T1, lines 8-9) but never exercised, so this also dogfoods/validates it. Append an addendum to `M6-analyser.md` noting the reparent + rationale (don't rewrite its body).

### D3 — Teach cache-build to honour reattached (machinery, item 3)

**Today the event would be a no-op (two bugs).** In `cache-build.py` the relationship loop (`:208-222`) reads `attrs["from_entity_id"]` and does `if not from_id: continue` — a `reattached` event has no `from_entity_id` (it carries `from_parent`/`to_parent`), so it is **skipped entirely**, materialising nothing. And even if processed, inserting a `reattached` row would not remove the prior `T2-analyser spawns M6` edge, so the spawn graph (which the view's cascade and the tree read) would be unchanged.

**Fix — reattached rewrites the spawn graph:**
1. **Pre-scan** all events for `relationship.reattached`, building `reattach_to[(child_type,child_id)] = to_parent` (last write wins, honouring append-only re-reattachment) and a suppression set `suppressed_spawns = {(from_parent, child_id)}`.
2. When materialising **event-sourced** spawns (`:208-222`) **and frontmatter-derived** spawns (`:234-255`), skip inserting any `spawns` row whose `(from_id, to_id)` is in `suppressed_spawns`.
3. After the scan, insert the **new** edge `to_parent spawns child` (`source='event'`, `source_event_id` = the reattached event's id) for each reattachment.
4. Also insert a provenance `reattached` row (so the move itself is queryable), but it is the rewritten **spawns** edge that drives projections.

This is general — any future reparent (the methodology's "rebase primitive for the planning graph") works the same way, not just M6.

### D4 — Methodology doc corrections

- **[[T1-top-level]] §2.4** — add the milestone-parent rule + sub-milestone (`Mn.p`) hierarchy + dotted-index notation. Note that milestone *membership* of a T3 stays frontmatter (`milestone:`), unchanged; this rule is about the milestone's *own* parent, which **is** a graph edge.
- **[[T2-ontology]] §3.6** — clarify `relationship.reattached`: it doesn't just record a move, it **supersedes the prior `spawns` edge** in derived projections (per D3). Cross-reference the new milestone-parent rule.
- **[[T2-ontology]] §3.8** — fix the blanket claim *"relationship.* events require `from_entity_type` + `from_entity_id`"*: `reattached` is the exception (requires `from_parent` + `to_parent`), matching the 0.2.0 schema. This is a latent doc/schema inconsistency this plan resolves.

## 3. Implementation notes / touch-points

- **`.agent-plan-tracker/events.jsonl`** — append the `relationship.reattached` + `decision` events (schema_version `0.2.0`). Validate against `schemas/0.2.0/events.schema.json` (`relationship_reattached` requires `from_parent`/`to_parent` — confirmed).
- **`scripts/cache-build.py`** — `:208-222` (event spawns) + `:234-255` (frontmatter spawns): add the pre-scan + suppression + new-edge insertion described in D3.
- **`planning/M6-analyser.md`** — append addendum (don't edit §8 provenance prose; add a dated note).
- **`planning/T1-top-level.md`**, **`planning/T2-ontology.md`** — doc edits per D4; each paired with an `entity.extended` event on that plan.
- **Rebuild chain**: `cache-build.py` → `projection-emit` → `summary-emit`. Confirm `repack-validate` (or the project's validate step) passes end-to-end.

## 4. Decisions to log

- **DEC-1 — milestone-parent rule.** A milestone hangs off T1 or a top-level side-quest; sub-milestones nest `Mn.p → Mn`. Never T2/T3. (Paired with the reattached event.)
- **DEC-2 — keep label M6, reparent not rename.** Historical honesty + load-bearing filename id; dotted notation is forward-looking only.
- **DEC-3 — reattached supersedes the prior spawn in derived projections.** Makes the primitive actually move the node in the graph, not merely annotate it.

## 5. Out of scope (this T3)

- Renaming M6 → M1.1 or renumbering any existing milestone (grandfathered).
- Auditing/!reparenting M2–M5 (they don't have offending edges; M1 conforms).
- Milestone *supersession* semantics ([[T1-top-level]] §5 open-Q10) — distinct from reattachment; not opened here.
- Any view-layer change — the cascade is correct once the data is; view polish is [[T3-flow-view-controls]].
- Promoting milestone *membership* from frontmatter to a relationship event ([[T1-top-level]] §5 open-Q9) — unaffected; still frontmatter.

## 6. Verification (whole-T3)

1. **Data**: after rebuild, `projection.json` shows `M6-analyser`'s only `spawns` parent is `M1-bootstrap`; no `T2-analyser → M6` spawns edge remains; a `reattached` provenance row exists.
2. **Item 3 in view**: eye-hiding `T2-analyser` no longer suppresses `M6-analyser`; eye-hiding `M1-bootstrap` *does* cascade to `M6` (it's now M1's child).
3. **Tree view**: `M6-analyser` renders under `M1-bootstrap` on the milestone axis.
4. **Schema/validate**: the new events pass `events.schema.json` 0.2.0; full validate chain green.
5. **Generality smoke**: a throwaway second reattachment of a test child rewrites correctly (last-wins), then removed — confirms the logic isn't M6-special.
