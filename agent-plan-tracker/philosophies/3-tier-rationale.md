# Three-tier plan rationale

Planning happens at altitudes. Three tiers, each with a distinct purpose, separation enforced by discipline.

**Tier 1 — Intent.** The grounding layer against bottom-up reasoning. Captures *why* the project exists, *what success looks like*, *who the audience is*, *the themes and workstreams the project will touch*. Principle-led, no file paths, no specific component names. Authored once at project start, rarely edited; most evolution lands in lower tiers that reference T1 themes.

T1 exists so every subsequent agent (T2, T3, downstream) lands in the project with proper grounding — knowing why, for whom, and what counts as success — so that when something unforeseen arises, the agent can adapt with grounding instead of inventing direction from local code patterns.

**Tier 2 — Implementation per chunk.** First partitioning of T1 into reasonably-independent thematic chunks (data layer, extraction pipeline, projection layer, etc.). T2 starts defining architecture, methodology, process — *how* the project's themes will be addressed — but still in the planning world, not execution. T2 is Claude co-work altitude.

T2 plans can shift violently at architectural boundaries (GCP → AWS, Firebase → Postgres, React → something else); supersession is normal at this tier.

**Tier 3 — Execution per task.** The executable brief. File paths, interface signatures, per-file changes, verification steps, decisions to log, out-of-scope guards. Code-level enough that an agent can execute it cold. T3 is Claude Code altitude.

Principles do not belong in T3 — they live in T1/T2; T3 inherits them by reference.

## Why tiers at all?

Three reasons the tiered structure is load-bearing:

1. **Different agents read different tiers.** A planning agent reads T1 to understand the project. An implementing agent reads T3 to do the work. A reviewer reads T2 to check fit. Mixing altitudes in one document means every audience gets too much or too little.
2. **Change frequency differs by tier.** T1 changes rarely; T3 churns. Separating them prevents stable content from being buried in low-stability churn.
3. **Decisions cascade downward, not upward.** A T1 theme constrains T2 implementation choices. A T2 decision constrains T3 task structure. Reverse couplings — a T3 finding forcing a T1 rethink — are signals of misalignment to surface, not normal flow.

## Tier 0 (optional, commercial)

Pre-project. The proposal sent to a client or stakeholder: budget, timeframe, expectations, scope agreement. Commercial. Not required, but where it exists provides useful background for agents picking up the project later.

## Orthogonal axis: milestones (Mn)

Where Tn organises by theme (*where in the system*), Mn organises the same work by sequence (*when in the delivery*). The axes are orthogonal: every T3 has both a thematic parent (its T2) and a milestone target (its Mn). See `T2-packaging` or the methodology section for the dual-axis details.
