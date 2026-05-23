---
id: 2026-05-23.verification-overhaul-candidate-model
entity_type: inbox-item
created_at: 2026-05-23
status: open
candidate_fate: decision
---

# Verification overhaul — probably-closed / actually-closed split

The current 4-event verification category (`claimed / tested / skipped / failed`) is flagged overwrought (T2-ontology §7 Q1).

## Candidate replacement: 2-event split

Replace the 4 with 2 events:

- **`probably-closed`** — any agent can emit. Should ideally have attempted tests where possible. Represents the executor's claim "I think this is done".
- **`actually-closed`** — separate agent or human confirms. **Schema-enforced different-actor requirement**: the `actor` of `actually-closed` must not equal the `actor` of the most recent `probably-closed` for the same entity.

## Why this is better

- **Trust-by-second-opinion built into the ontology.** Currently `entity.completed` is asserted unilaterally; the verification events are advisory. The two-event split makes the verification mandatory and structurally trustworthy.
- **Simpler discrimination.** Instead of figuring out which of 4 verification events applies, the question becomes "is there a paired actually-closed?"
- **Maps cleanly to existing workflows.** Code review = different actor confirms. Test execution by CI = different actor (the CI runner) confirms. Manual QA = different human.

## Implementation notes

- `entity.completed` likely becomes `probably-closed` (same lifecycle slot, renamed for the new semantics).
- `actually-closed` is the new gate event. Without it, the entity stays in a `probably-closed` derived state (a new state, between `live` and `dead`).
- Verification.skipped / verification.failed remain useful as exceptional cases — when verification was *attempted and didn't go cleanly*. Probably reduced to one event: `verification.exception` with attributes for reason + outcome.

## Final event count after overhaul

23 events → drop `entity.completed`, `verification.claimed/tested/skipped/failed` (5) → add `entity.probably-closed`, `entity.actually-closed`, `verification.exception` (3) → 21 events.

Or keep `entity.completed` as the umbrella derived state name (no event, just derived from actually-closed) → 22 events.

**Resurrect when:** M1 dogfooding has produced ~10–20 plan completions via the current 4-event model. Real friction will tell us if the overhaul earns its keep.
