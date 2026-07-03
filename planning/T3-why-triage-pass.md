---
id: T3-why-triage-pass
plan_kind: thematic
tier: 3
t2_parent: T2-ingest
milestone: M5-backfill
status: draft
---

# T3-why-triage-pass — recollection, harvested honestly

**Status**: Draft.
**Sits at**: T2-ingest theme, M5-backfill milestone. Wave 2 — depends on [[T3-origin-provenance-schema]] (event shapes) and [[T3-backfill-workflow]] (the hypotheses it consumes).

---

## 1. Why

The walk cannot recover Why; the human who was there often can — but only if asking them is cheap. Two hundred mid-run interruptions would make backfill unusable; one post-walk checklist session makes recollection a single sitting. This T3 is the machinery of tier 2 (recollected) and the honest disposal of tier 3 (inferred → open question), per T2-ontology §3.12.

## 2. What

1. **Input**: the run's hypotheses file ([[T3-backfill-workflow]] §2.4) — each entry: the fulcrum-ish moment (entity, event, anchored commit), the candidate rationales, the evidence pointers.
2. **The sitting**: present the checklist to the operator (skill-procedural, matching the house pattern — a `/apv-triage-why` flow): per moment, confirm a candidate / supply their own wording / mark unknown. Batch-first ergonomics: the analyser's bulk mode is the shape.
3. **Emission**: confirmations → `decision` events with the **operator as actor** (their say-so is the event), `origin: backfilled` + run id, `event_ids[]` pointing at the arcs they explain; unknowns → `hitl-question` entities carrying the candidates. All appended in the triage commit's block, sealed normally.
4. **Archive**: consumed hypotheses file archived with the run (repudiation cohort intact).

## 3. Scope

### In scope
- The triage skill/flow + emission script; hypothesis file contract; archive step.

### Out of scope
- Hypothesis *generation* (the walk's job); UI rendering of the resulting questions ([[T3-historical-projection-ui]]).

## 4. Verification

1. Sandbox run with three fulcrum-ish moments: operator confirms one (→ recollected decision, operator actor), rewords one (→ decision with their text), leaves one (→ hitl-question with candidates). Gate green; fulcrum pairing satisfied in all three shapes.
2. Re-running triage on a consumed file is a no-op (idempotent; nothing re-asked).
3. A later answer to a standing question converts tier 3 → tier 2 append-only (question closes, decision lands).

## 5. Dependencies

- T3-origin-provenance-schema; T3-backfill-workflow.
- /apv-capture discipline (the triage commit is an ordinary captured commit).

## 6. Open questions

1. Presentation surface: AskUserQuestion-driven in-session checklist vs a generated markdown checklist the operator annotates? Lean: in-session, one question per moment, resumable.
2. Should recollected decisions carry a `recollected: true` marker beyond `origin: backfilled`, or is origin + operator-actor sufficient to reconstruct the tier? Lean: sufficient — derive, don't duplicate.

## 7. Build notes (2026-07-03)

Both §6 leans ratified: the checklist is in-session (`commands/apv-triage-why.md` — one AskUserQuestion per moment, candidates as options plus "Other" and an explicit leave-open; resumable; never pressures toward a candidate), and no `recollected` marker — `origin: backfilled` + the operator as actor reconstructs the tier.

- **The deterministic half** is `scripts/backfill/triage-emit.py`: rulings JSON in; per confirmed/reworded moment a recollected `decision` (operator actor, the walk's candidates quoted inside the text for provenance, `event_ids` = the fulcrum's) plus `entity.completed` on the standing question; unknowns untouched — honestly open. All conversion events carry the run id (repudiating the run repudiates its triage).
- **Idempotency is structural**: the hypotheses file is archived on consumption (re-run = "Nothing to do") and already-closed questions are skipped at the event level.
- **Gate interaction verified**: the walk's tier-3 hitl stand-in keeps satisfying the fulcrum pairing after the question closes (pairing reads same-seal creation events, which are append-only), so triage never destabilises earlier blocks; the sandbox proves gate-green before and after triage, and the question derives `closed`.
- The triage commit is an ordinary captured commit sealed by the caller (`triage(<run>): N recollected, M left open` — the command's closing step).
