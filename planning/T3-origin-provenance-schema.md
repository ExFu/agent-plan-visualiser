---
id: T3-origin-provenance-schema
plan_kind: thematic
tier: 3
t2_parent: T2-ontology
milestone: M5-backfill
status: draft
---

# T3-origin-provenance-schema — the 0.3.0 → 0.4.0 evolution

**Status**: Draft.
**Sits at**: T2-ontology theme, M5-backfill milestone. Wave-1 contract T3, paired with [[T3-historical-projection-ui]] — neither builds until both are accepted. Executes T2-ontology §3.12 (ratified 2026-07-03).

---

## 1. Why

Everything M5 does keys on one contract: backfilled events are permanently distinguishable (`origin`), anchored (`commit_ref` on backfilled seals), and judged by the right regime (origin-aware enforcement, event-time state derivation). The schema is that contract made machine-checkable — it must exist before any backfilled event is emitted (M5 §7 Q4 lean: wave 1).

## 2. What

1. **`schemas/0.4.0/`** — new frozen epoch dir (0.3.0 stays byte-frozen, as ever):
   - `origin` optional top-level enum `captured | backfilled` on every event; absent = captured (zero migration of the existing log).
   - `origin: backfilled` events require `attributes.backfill_run` (run id).
   - Backfilled `commit.recorded` seals require `attributes.commit_ref` (the anchoring sha); captured seals still must not carry it (§3.1 rule, amended for the exception).
   - `cache.schema.sql` gains `origin` + `backfill_run` columns and the event-time anchor.
2. **`cache-build.py`** — derived state computed over **event-time order** (seal date / anchored commit topo order), record time as tiebreak; `origin` passed through to the entities/events tables.
3. **`gate-composite.py`** — discipline checks (`implementation-on-draft`, `fulcrum-without-decision`, `resurrection-without-reopen`, sealed-tail) skip `origin: backfilled` events; schema validity applies in full. For backfilled fulcrums, a paired *recovered/recollected* decision or a paired `hitl-question` (tier 3) both satisfy pairing.
4. **`validate-events.sh` / `projection-emit.py` / `summary-emit.py`** — accept 0.4.0; projection carries `origin` and event-time ordering (the UI contract).

## 3. Scope

### In scope
- The four surfaces above; gate fixtures for every new rule; the 0.4.0 ontology prose already in T2-ontology §3.12 kept in sync.

### Out of scope
- Any emission of backfilled events ([[T3-backfill-workflow]]).
- UI rendering ([[T3-historical-projection-ui]] — co-designed, separately built).
- Migration of existing events — there is none by design.

## 4. Verification

1. The dogfood log validates at 0.4.0 tooling **unmodified** (absence = captured; all suites green).
2. Fixture log with a backfilled segment (historical seals + `commit_ref` + `backfill_run`): gate green; states derive by event time; a backfilled implementation-on-draft does NOT block; the same shape with `origin` absent DOES block.
3. Fixture with a backfilled fulcrum paired only with a `hitl-question`: passes; same fulcrum with nothing: blocks.
4. Repudiation query: filtering a `backfill_run` cohort out reproduces the pre-run projection.

## 5. Dependencies

- T2-ontology §3.12 (the ratified spec).
- T3-historical-projection-ui (paired acceptance; its rendering needs drive the projection fields).

## 6. Open questions

1. Event-time ordering *within* one historical commit's block: log order is the only order available — confirm block-internal order is authoritative (lean: yes, same as live blocks).
2. Does `backfill_run` id embed the run date (`bf-2026-07-03-a`) or stay opaque? Lean: date-embedded — human-scannable in queries.
