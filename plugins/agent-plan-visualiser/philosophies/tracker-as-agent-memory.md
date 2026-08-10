# The tracker substitutes for agent memory

Agents have no memory across sessions. The structured event log is the project's reconstructable reasoning chain — the thing a future agent (or a returning human) consults to answer *"why is the project this shape, what's outstanding, what's settled, what's blocked"* without re-reading the entire planning corpus.

## The principle

This isn't a "more accurate plan". It's the project's structured memory.

A human carries context across weeks — remembering why Firebase was abandoned, why the auth approach changed, why a migration was rolled back. An agent cannot. An agent entering an unfamiliar project sees only what's currently in the files. Without a structured history it can consult cheaply, it will confidently propose work that was already tried and rejected, miss outstanding threads, and silently lose continuity.

The event log captures *what actually happened*. Plans capture *what was intended*. The gap between them is where the interesting questions live — what got abandoned without being marked dead, what was decided but never implemented, what's still in flight months later.

## How to apply

When designing any agent surface that the plugin ships:

1. **Assume zero memory.** The agent has access to the event log, the current plan files, the cache, the projection. It has *no* memory of past sessions, conversations, or decisions outside what's been captured.
2. **Surface the structured history cheaply.** A new agent at session start should be able to answer "what's outstanding" with a single query, not by reading every plan file. The snapshot + projection layer exists for this.
3. **Make the why navigable, not just the what.** Decisions (as arc metadata) are the bridges between *what was planned* and *what actually happened differently*. Without them, agents have to guess at rationale.
4. **Resist proposing work that's already been tried.** Before suggesting an architectural pivot, check the event log for prior decisions on the same axis. Re-proposing rejected approaches is the most visible symptom of missing memory.

## Where this principle binds in our own design

- The event log is the substrate. Every projection, every view, every audit is derived from it.
- Snapshots cap session-start ingestion cost at a bounded delta rather than full history. Without snapshots, the memory substitution becomes impractical at scale.
- The `relationship.spawns` event chain lets agents trace lineage backwards (what spawned this entity, what spawned that, all the way back to T1).
- `decision` events provide the rationale spine — given any fulcrum event, the paired decision explains why.

## Why this is half the value of the plugin

The other half is the methodology. Together: structured planning + queryable structured memory = a project that scales beyond one person's working memory, with agents that contribute coherently rather than corrosively.

## Common failure mode

Trusting the markdown plan files as the only source of truth. They capture intent. Reality (what actually happened, what was tried and abandoned, what's still in motion) lives in the event log. An agent that only reads plans will reliably re-propose abandoned ideas and miss outstanding work.

## Connection to other philosophies

- `top-down-from-job.md`: the job this serves is *agent continuity across sessions*. Without that need, the tracker would be over-engineered for a single-session use case.
- `golden-circle-grounding.md`: the agent needs to know *why* the project is the shape it is. The event log + decisions provide the why.
