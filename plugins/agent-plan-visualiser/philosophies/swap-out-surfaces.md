# Swap-out surfaces

Every framework / library / service choice gets annotated with the cost of swapping later. No silent lock-in.

## The principle

Architectural decisions accumulate. Each "we'll use X" choice creates a coupling that costs to undo later. Most decisions are fine — the coupling cost is low or the choice is genuinely permanent. But some are sleeper costs: a casual "we'll use Firebase" today becomes "we have 50,000 lines of code that assume Firebase" later, and switching is now a major project.

The discipline: when choosing a framework / library / service, **explicitly annotate**:

1. **What we chose** (the surface).
2. **Why** (the job it serves at the time of choosing).
3. **What we'd consider swapping to** (the alternatives we know about).
4. **The trigger** (the signal that says "now would be the time to reconsider").

This trades a small amount of upfront documentation for a large amount of future flexibility. Future agents (and humans) can see the assumptions baked into the design without spelunking through commit history.

## How to apply

In any T2 plan that locks an architectural surface, include a "Swap-out points" section. Format per surface:

> **<surface name>.** <brief description of why this surface was chosen and what job it serves.> Trigger to revisit: <concrete signal — e.g. "if >30% of projection queries require multi-hop traversal (depth ≥ 3)">. Alternatives: <known candidates, with their tradeoffs>.

The trigger is the load-bearing bit. Without a trigger, "we might swap this later" is wishful thinking. With a trigger, swap evaluation becomes a routine review activity.

## Examples in our own design

- **SQLite as cache backend.** Chosen because: universal, file-based, sufficient for projected scale. Trigger to revisit: >30% of projection queries require multi-hop traversal (depth ≥ 3). Alternatives: KuzuDB, Cozo (embedded graph engines with GQL/Cypher). GQL standardisation reduces historical graph-engine lock-in risk.
- **Pure HTML + vanilla JS for the view layer.** Chosen because: zero dependencies, debuggable, no build step. Trigger to revisit: views need significant interactive complexity that vanilla JS makes painful. Alternatives: lit-html, Preact — but avoid a build-step-required SPA.
- **JSONL events as primary storage.** Chosen because: append-only text, blame-friendly, git-trackable. Trigger to revisit: events become large or numerous enough that append-only text scanning becomes slow. Alternatives: SQLite as primary, or a real event store like EventStoreDB. Unlikely within this project's scale.

## Common failure mode

Choosing a framework because it's popular, without annotating *why* it serves the job better than the alternatives. Six months later, someone asks "why did we pick X?" and nobody remembers. The cost of swapping is now also the cost of re-deriving the original rationale.

## Connection to other philosophies

- `top-down-from-job.md`: the *why* of a swap-out surface is always the job it serves. Without naming the job, the swap-out annotation is incomplete.
- `disposable-etl.md`: the inverse view. Stable surfaces get swap-out annotations; the bridges between them are throwaway.
