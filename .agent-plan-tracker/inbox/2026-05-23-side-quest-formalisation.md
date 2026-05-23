---
id: 2026-05-23.side-quest-formalisation
entity_type: inbox-item
created_at: 2026-05-23
status: open
candidate_fate: philosophy
---

# Side quest formalisation — when to spawn a lettered workstream

T1 §5 Q3 — lettered side quests (PT, AT, BT — any capital letter other than X for crosscut) work conceptually but the methodology around *when* to spawn one vs *extend the main spine* isn't crisp.

## Initial intuition (to be refined through dogfooding)

Spawn a lettered side quest when **both** are true:

1. **The work doesn't fit any single T2's scope.** A T3 that genuinely belongs under an existing T2 isn't a side quest — it's a regular T3 under that T2.
2. **The work has its own coherent why-how-what worth a T1-equivalent.** If you can't write a paragraph explaining why this side quest exists distinct from the main project's why, it's probably not a side quest — it's either crosscut work (XT) or just unrelated scope creep that shouldn't be in the project at all.

Otherwise: extend an existing T2 with a new T3 (or expand its scope explicitly).

## Why this matters

Without discipline, side quests proliferate and become a dumping ground for "stuff I want to do but isn't really part of the main project". The methodology has to make spawning a side quest *deliberate* — costly enough to deter but cheap enough to encourage when genuinely needed.

## Examples to think through

- Client team needs a small editor tool that sits alongside the main delivery → side quest (own outcome, own users, doesn't fit main spine).
- New debugging methodology applied project-wide → crosscut (XT) — touches everything but doesn't have its own outcome.
- New feature in the data layer → regular T3 under T2-data.
- A library upgrade that requires touching every component → crosscut (XT).
- Spike investigation that might inform future architecture → probably an inbox item until it earns plan-status.

## Likely outcome

Refined through dogfooding once this project encounters its first real side quest. Worth a philosophy doc once nailed down (provisional name: `philosophies/side-quest-discipline.md`).

**Resurrect when:** The first candidate side quest surfaces in this project or in any project where the plugin is in use.
