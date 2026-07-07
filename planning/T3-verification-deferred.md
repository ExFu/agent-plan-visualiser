---
id: T3-verification-deferred
plan_kind: thematic
tier: 3
t2_parent: T2-ontology
milestone: M5.1-operator-attention
status: completed
---

# T3-verification-deferred — the honest "not now, but we're coming back"

**Status**: Completed (authored, accepted and built 2026-07-07, operator-directed).
**Sits at**: T2-ontology theme, M5.1-operator-attention milestone.

---

## 1. Why

`verification.skipped` conflates two different truths: "we're not doing this" and "we can't do this *here/now*, but it must still happen". The M4/M5 operator legs (exfu.ai upload, Cowork check, rehearsal run) are the second kind — recorded as skips, their come-back-to-it intent lived only in the operator's head and in plan prose. Operator ruling (2026-07-07): the distinction becomes an event.

## 2. What

1. **Schema epoch `0.5.0`** (`agent-plan-visualiser/schemas/0.5.0/`): copy of 0.4.0 plus the `verification.deferred` event type — same shape as `verification.skipped`, `attributes.reason` required. `schema_version` enum grows to accept `0.5.0`; cache DDL unchanged.
2. **Semantics**: an entity's deferral is *open* while its latest `verification.*` event is a deferral; any later verification event on the entity (tested / claimed / failed, or a renewing deferred) supersedes it. No new derived entity state — deferral is verification-plane, not lifecycle-plane; `entity.parked` remains the whole-entity deferral.
3. **Emission**: `/apv-capture` emits `verification.deferred` at `schema_version: "0.5.0"`; all other capture events stay `0.3.0` (mirroring how only backfilled events carry 0.4.0). Skill §2 updated.
4. **Toolchain default bumps**: `validate-events.sh` default schema → 0.5.0 (superset enum, one pass covers the log); `cache-build.py` DDL path → 0.5.0; `projection-emit.py` schema/ontology stamps → 0.5.0. The gate's per-version routing picks up `schemas/0.5.0/` with no code change.
5. **Surfacing** is T3-pending-ceremony-surfacing's scope (the `deferred-verification` warn + summary queue).

## 3. Out of scope

- Rewriting existing `verification.skipped` events — append-only; old skips stand.
- Blocking semantics — a deferral is an honest recorded state, not corruption; it warns, never gates.
- `apv-init`'s `schema-version.txt` stamp (stays 0.3.0, the capture baseline — unchanged through the 0.4.0 epoch too).

## 4. Verification

1. Log validates unmigrated via `repack-validate.sh` with the 0.5.0 default.
2. A well-formed `verification.deferred` validates; a reason-less one is rejected (asserted at schema-cut time).
3. Fixture (`tests/gate/fixture-attention/`): open deferral warns with its reason; a deferral followed by `verification.tested` goes quiet. `run-gate-tests.sh` green.
