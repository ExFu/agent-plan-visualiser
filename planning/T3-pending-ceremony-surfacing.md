---
id: T3-pending-ceremony-surfacing
plan_kind: thematic
tier: 3
t2_parent: T2-projection
milestone: M5.1-operator-attention
status: completed
---

# T3-pending-ceremony-surfacing — pending ceremonies become projections

**Status**: Completed (authored, accepted and built 2026-07-07, operator-directed).
**Sits at**: T2-projection theme, M5.1-operator-attention milestone. Delivers inbox `2026-07-03.ceremony-prompting-gap`.

---

## 1. Why

Ceremonies are operator-only and enforced lazily: the draft gate *blocks* implementation against unaccepted plans, but nothing *prompts* the acceptance itself, and nothing flags a milestone whose T3s have all closed while it sits live. The inbox item records the cost: `T3-autonomous-extractor` sat 23 days believed-built. The projections — not the operator's memory — should carry the queue.

## 2. What

1. **`attention` block in `projection.json`** (projection-emit): three queues —
   - `pending_acceptance`: plans in `draft` (inbox items excluded — draft is their correct untriaged state), with authoring date and commits-since;
   - `pending_closure`: live milestones whose scheduled T3s are all closed;
   - `deferred_verifications`: entities whose latest `verification.*` event is `verification.deferred` (reason + date).
2. **`## Awaiting operator` section in `summary.md`** (summary-emit), rendering the three queues right after Live work; tolerant of an older projection without the block.
3. **Two warn-tier gate checks** (gate-composite, cache-backed, ids in `.apv-config.toml [gate] warn` + built-in defaults): `pending-ceremony` (both ceremony flavours) and `deferred-verification` (open deferrals). Advisory by design — an unheld ceremony is a visible true state, not corruption (M3's reframe stands).
4. **Inbox age annotations** in the summary's Draft section — ids embed their capture date (`<YYYY-MM-DD>.<slug>`), so `(Nd untriaged)` costs nothing and makes triage debt visible.
5. **Not** session-orientation: `session-orient.sh`'s contract is fingerprint-only (no cache reads, no python). The summary and gate are the prompting surfaces; both fire routinely.

## 3. Out of scope

- Performing ceremonies (acceptance stays operator-only; the surfaces prompt, never act).
- Milestone definition-of-done evaluation — "all T3s closed but live" deliberately reads as "ceremony *or* remaining DoD legs pending"; the projection cannot judge DoD prose.
- Inbox-item acceptance nudging beyond age display.

## 4. Verification

1. Fixture (`tests/gate/fixture-attention/`): draft plan and all-closed-but-live milestone each warn under `pending-ceremony`; exit stays 0; no BLOCK lines. `run-gate-tests.sh` green.
2. Dogfood: the delivering commit's own summary/gate output surfaces `T2-ingest` (draft, 69 commits) and `M5-backfill` (closure pending) — the two real instances that motivated the work.
3. `repack-validate.sh` green end-to-end.
