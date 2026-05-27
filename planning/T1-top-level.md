---
id: T1-top-level
plan_kind: thematic
tier: 1
status: active-authoring
---

# T1-top-level — agent-plan-tracker — Top-level plan

**Status**: Draft. T1 in active authoring.
**Phase**: design exploration — pre-implementation. Currently bootstrapping plugin scaffold + M1 implementation plan.

---

## 1. Why this exists

Planning-driven projects accumulate divergent sources of truth. Tier-1, Tier-2, and Tier-3 planning documents describe intent and scope; a decisions log records architectural choices; an inbox captures uncrystallised ideas; commit messages and code comments each tell a different sliver. After enough velocity, every source partially lies.

The result is a class of failures that surface only on careful audit:

- **Verification claimed but never run** — a plan's verification section lists steps; the commit message claims completion; only some steps actually executed.
- **Decisions ratified but never landed** — a logged architectural choice; the code never picked it up; nobody noticed.
- **Supersession incomplete** — an older plan is superseded by a newer one; the older name still appears in several places.
- **Scope cut mid-execution** — items quietly drop out of scope during the work; no addendum records why.
- **Implicit work uncaptured** — a small feature ships without a corresponding plan; the absence of a planning trail makes it invisible in any later retrospective.
- **Sibling work orphaned** — the main task closes; a dependency it relied on is never picked up.

These compound silently. After months, *"what's actually complete?"* becomes a question nobody can answer with confidence.

There's a deeper reason this matters now. **Agents have no memory of the project across sessions.** A human carries context across weeks — remembering why Firebase was abandoned, why the auth approach changed, why a migration was rolled back. An agent cannot. An agent entering an unfamiliar project sees only what's currently in the files. Without a structured history it can consult cheaply, it will confidently propose work that was already tried and rejected, miss outstanding threads, and silently lose continuity.

The same problem bites the human at scale. Once a project gets large enough, scanning the entire planning corpus to answer "what's outstanding?" or "why is this in this state?" exceeds reasonable token budgets and human attention spans. The project needs a structured spine that both agents and humans can consult cheaply, with the rich markdown plans available behind it for deeper context.

**Git commit history is the one artefact that cannot lie about what happened.** Every other source is opinion or claim. The bet behind this project: derive every projection (state, status, audit, diagram) from a structured event log extracted directly from commits, and treat all other planning artefacts as inputs to that extraction — not as parallel sources of truth.

---

## 2. How — methodology and approach

### 2.1 Two halves, co-designed

The project delivers two related things that only work together:

1. **An opinionated planning methodology** — a tiered plan structure plus supporting concepts (decisions, blockers, inbox, HITL questions, implicit work) — that scales for sustained agent-driven development without the divergent-source-of-truth problem.
2. **A tracking spine** — walks git history, extracts structured events against an ontology derived from the methodology, maintains an append-only event log, provides projections (audits, diagrams, status reports) over it.

The methodology gives structure. The tracking spine enforces it and makes the project navigable. Neither half is complete without the other — the methodology drifts without tracking; the tracker has nothing to enforce without the methodology.

### 2.2 Planning tiers

Planning happens at altitudes. Each tier constrains the next; lower tiers cannot violate higher-tier commitments without an explicit pivot that the higher tier acknowledges.

**Tier 0 — Proposal (optional, commercial).** Pre-project. The proposal sent to a client or stakeholder: budget, timeframe, expectations, scope agreement. Not required, but where it exists it provides useful commercial background for agents picking up the project later.

**Tier 1 — Intent.** The grounding layer against bottom-up reasoning. Captures *why* the project exists, *what success looks like*, *who the audience is*, and *the themes and workstreams* the project will touch (e.g. data layer / UI layer / API layer for a dev project; phase A prototype → phase B milestones → phase C productionise for a sequenced project). Principle-led, no file paths, no specific component names.

A T1 plan exists so every subsequent agent (T2, T3, downstream) lands in the project with proper grounding — knowing why, for whom, and what counts as success — so that when something unforeseen arises, the agent can adapt with grounding instead of inventing direction from local code patterns.

Authored once at project start. Rarely edited; most evolution lands in lower tiers that reference T1 themes. Can occasionally be superseded if a fundamental pivot makes the original infeasible.

**Tier 2 — Implementation per chunk.** First partitioning of T1 into reasonably-independent thematic chunks — areas of the system that can be reasoned about somewhat independently (data layer, extraction pipeline, projection layer, etc.). T2 starts defining architecture, methodology, process — *how* the project's themes will be addressed — but still in the planning world, not execution.

The thematic decomposition answers *where in the system this work fits*. Sequencing — *when in the delivery this work ships* — is a separate axis captured by milestone plans (§2.4).

T2 is Claude co-work altitude. T2 plans can shift violently at architectural boundaries (GCP → AWS, Firebase → Postgres, React → something else); supersession is normal at this tier.

**Tier 3 — Execution per task.** The executable brief. File paths, interface signatures, per-file changes, verification steps, decisions to log, out-of-scope guards. Code-level enough that an agent can execute it cold.

T3 is Claude Code altitude. Once a T3 plan is built, a T2 agent should in theory be able to spin up a sub-agent swarm that just gets on with the work.

Principles do not belong in T3 — they live in T1/T2; T3 inherits them by reference. A T3 agent should see a summary of its T2 (and T1) to ground its judgement when execution surfaces unforeseen issues.

### 2.2.1 Why tiers at all?

Three reasons the tiered structure is load-bearing:

1. **Different agents read different tiers.** A planning-mode agent reads T1 to understand the project. An implementing agent reads T3 to do the work. A reviewer reads T2 to check fit. Mixing altitudes in one document means every audience gets too much or too little.
2. **Change frequency differs by tier.** T1 changes rarely; T3 churns. Separating them prevents stable content from being buried in low-stability churn.
3. **Decisions cascade downward, not upward.** A T1 theme constrains T2 implementation choices. A T2 decision constrains T3 task structure. Reverse couplings — a T3 finding forcing a T1 rethink — are signals of misalignment to surface, not normal flow.

### 2.3 Lettered workstreams

The main spine is `T1 / T2 / T3`. Workstreams that don't fit the main spine use a **letter prefix**:

- **`XT1 / XT2 / XT3`** — crosscut concerns. Work that touches multiple T2s or affects the system systemically. Examples: introducing analytics on every anchor link; restructuring componentisation across all UI plans; a new debugging methodology applied project-wide. Multiple X-workstreams (X-analytics, X-componentisation) can run in parallel; each gets its own 1/2/3 tree.
- **`PT1 / PT2 / PT3`, `AT1 / AT2 / AT3`, ...** — side quests. Any letter other than X. Each letter is one self-contained side quest that belongs to the project but isn't part of the main workstream. Example: a small editor tool a client team needs that lives alongside but outside the main delivery.

Lettered workstreams **always get their own 1/2/3 progression** — the why-how-what discipline applies at every workstream. Even a tiny side quest gets a one-paragraph T1 capturing its grounding.

Rule: a lettered workstream that genuinely belongs under a specific main T2 is not a crosscut or side quest — it's a spine T3 in disguise. The "doesn't fit under any single T2" property is what makes something lettered.

Diagrammatically: the project root has one main T1 plus zero or more lettered roots; each root has its own tier tree.

Lettered workstreams remain on the thematic axis (Tn). They're parallel thematic spines, not alternatives to milestones. A T3 inside an XT or PT tree still has a milestone target like any other T3 (§2.4).

### 2.4 Milestone plans (Mn)

Where Tn organises work by theme (*where in the system*), **Mn organises the same work by sequence** (*when in the delivery*). The two axes are orthogonal: every T3 has both a thematic parent (its T2, whether on the main spine or a lettered workstream) and a milestone target (its Mn).

**M1, M2, M3, ...** — sequential milestones. Each milestone defines a capability unlock: what gets shipped together. For this project, for example: M1 = "basic functionality works end-to-end hand-rolled"; M2 = "automated extraction takes over"; M3 = "cleanliness gate enforces methodology"; M4 = "installable on fresh projects"; M5 = "backfill works on existing projects".

Each Mn is a first-class plan with its own structure:

- **Why**: what does this milestone unlock? Why does it come at this point in the sequence? What does it prove that the previous milestone didn't?
- **How**: which T3s (from across themes and lettered workstreams) deliver into this milestone? What counts as "Mn complete"?
- **What**: the enumerated T3 references, plus milestone-level verification criteria.

Mn plans have their own lifecycle. They progress as their constituent T3s land. They complete when their definition-of-done is satisfied (not strictly when all originally-scheduled T3s are done — milestones promise capability outcomes, not specific T3 membership). T3s can be moved between milestones as a normal scope adjustment, no supersession needed; that's expected reshuffling, not destruction.

A T3 carries its milestone as frontmatter (`milestone: M1-bootstrap` or similar). Scheduling is metadata, not a graph relationship — it's the kind of thing that adjusts naturally as work shapes up. Persisting it as a relationship event would create noise without proportional value.

#### 2.4.1 The two axes in practice

```
                     Themes (Tn — where)
                       ↓
                       T2-ontology    T2-storage    T2-extraction    T2-projection    T2-ingest
   Sequence            │              │             │                │                │
   (Mn — when)         │              │             │                │                │
   ↓                   │              │             │                │                │
   M1-bootstrap        T3 ━━━━━━━━━━━ T3 ━━━━━━━━━ T3 ━━━━━━━━━━━━ T3 ━━━━━━━━━━━━
   M2-auto-extract                                  T3 ━━━━━━━━━━━━
   M3-clean-gate                      T3 ━━━━━━━━━ T3 ━━━━━━━━━━━━ T3 ━━━━━━━━━━━━
   M4-fresh-install   T3 ━━━━━━━━━━━ T3
   M5-backfill                       T3 ━━━━━━━━━ T3 ━━━━━━━━━━━━                   T3
```

A T3 sits at the intersection: one cell in this matrix. Its thematic parent says where it lives in the system; its milestone says when it ships.

Both axes have first-class projections:
- *"Show me all open work, grouped by theme"* → grouped by T2.
- *"Show me M2's status"* → all T3s tagged M2, plus their states across themes.

A project can lean more heavily on one axis than the other depending on context. A client-delivery project with hard release dates is milestone-primary; a long-running platform project may be theme-primary with rolling milestones. The methodology supports both leans without privileging either.

### 2.5 Plans are append-only

Plans, once committed, are not edited destructively. Three rules:

- **Small adjustments append.** A decision that affects an existing plan often lands as a line at the end of that plan's file. The plan stays alive.
- **Bigger shifts supersede.** When a plan can't survive the change, mark it superseded (or cancelled, abandoned, parked) and create a new plan. The old plan stays in the repo as historical evidence. **Never delete.**
- **Provenance is preserved.** Relationships between plans — including their abandoned ancestors — are part of the project's reasoning chain. An agent inspecting the project later needs to see what was tried and what was rejected so it doesn't re-propose abandoned work.

Plan supersession is normal, not exceptional. The whole point of the tracking spine is to make this navigable: any plan, however abandoned, has its full event history available, and agents can cheaply filter to live work without re-reading dead branches.

When a parent plan is superseded, its children become **orphans** until explicitly resolved: re-attached to the new parent, cancelled, or superseded under the new structure. Orphan resolution is human-gated (see §4.8).

### 2.6 Decisions, blockers, HITL questions, inbox

Four supporting concepts the methodology treats explicitly:

**Decisions.** A decision is the *explanation of a pivot* — why a plan was abandoned, why a supersession happened, why a parking was justified. Decisions are **not first-class entities**; they are **arc metadata** — text annotations attached to one or more events in the graph. A single decision can be referenced by many arcs when one rationale explains several related fulcrum events.

In the original methodology the decisions log was a separate artefact (`decisions.md`) because rationale cross-cut plans. With the tracking spine in place, that artefact is no longer load-bearing — decision rationale folds naturally into plan prose (the *why* of an addendum, or the *why* of the new plan replacing an old one), and the structured graph capture happens in the tracker. The separate log artefact disappears.

**Blockers.** External dependencies — owned by someone outside the working team — that gate progress. Credentials from a third party. Sign-off from legal. Approval from a budget owner. Blockers are entities with their own lifecycle: raised → progressed → closed. Tracked distinctly from plan progress because they're asynchronous and the team can't act on them directly. Partial movement is real signal.

**HITL questions.** Inside plans (commonly T2 or T3), some questions can't be answered by the authoring agent alone. They need human input — domain knowledge, taste call, commercial context. Marked explicitly in the plan with numbered queries (`Q1`, `Q2`, ...). The plan author commits to specific options where confident; defers to the human where not. HITL questions are tracked as entities so their answers can be queried independently of the plan they came from.

**Inbox.** A capture surface for ideas, observations, and partially-formed concerns that haven't yet earned a plan. Append-only; entries get short titles and bodies. Triaged periodically.

Capturing-without-committing is load-bearing for sustained work. Without it, ideas either interrupt the current focus (bad) or get lost (worse). With it, the friction of capture is low and the cost of triage is amortised. Each inbox item is an entity with a lifecycle: created → triaged → terminates as completed / cancelled / parked / converted to plan (via `relationship.spawns`).

### 2.7 Implicit work

Work that ships without a corresponding plan still needs to appear in the event log. Such commits are captured as `implicit-work` entities — auto-named from the short commit hash and message slug. This is the catch-all that prevents plan-less commits from disappearing from the project's reasoning chain.

### 2.8 What the tracker enforces

Given this methodology, the tracker's job is:

- Extract events aligned with the methodology's vocabulary (plans, decisions-as-arc-metadata, blockers, HITL questions, inbox items, implicit work).
- Catch when the methodology is being violated implicitly — a commit that claims to close a T3 but doesn't actually do the work; a fulcrum event without an attached decision; a blocker "closed" without evidence.
- Expose projections that let humans and agents reason about the project at any tier without re-reading every plan.

The methodology and the tracking are co-designed. Each methodology concept corresponds to one or more event types and node types in the ontology (§4).

---

## 3. Themes — the principles guiding this design

These are the load-bearing principles. Every concrete decision in §4 traces back to one of them.

### 3.1 Git history is the primary source of truth

Commits are immutable evidence of what happened. Plans, decision rationale, prose status reports are all secondary — useful as *inputs* to extraction, never authoritative on their own. Where they disagree with git, git wins.

### 3.2 State is a projection, not a parallel source

All views of "what's complete", "what's blocked", "what's outstanding" are derived projections from the event log. We never maintain parallel state stores that could diverge from the log.

### 3.3 The tracker substitutes for agent memory

Agents have no memory across sessions. The structured event log is the project's reconstructable reasoning chain — the thing a future agent (or a returning human) consults to answer "why is the project this shape, what's outstanding, what's settled, what's blocked" without re-reading the entire planning corpus. This isn't a "more accurate plan"; it's the project's structured memory.

### 3.4 Event-sourced architecture

The append-only event log is the canonical store. Materialized views (a SQLite cache, snapshot files, derived projections, HTML rendering) are derived and rebuildable. Corrupting a derived view is recoverable; corrupting the log is not — so the log gets all the integrity discipline.

### 3.5 Self-contained event records

Every event in the log carries enough metadata to be interpreted without external systems available. An agent reading the log from a tarball with no git checkout gets the same identifying information as one reading it from a live repo. Git availability is a *bonus* for fast hash-based lookup; not a prerequisite for ingestion.

### 3.6 Sequential extraction with full prior context

Each per-commit extraction agent reads the existing reconciled log before extracting events for its target commit. Reference resolution happens at extraction time because prior history is canonical when the agent runs. Sequential rather than parallel — slower for backfill, but correctness is built in; no reconciliation phase needed.

### 3.7 Human-gated ambiguity

When extraction or merge produces ambiguity, the system halts and asks. It never auto-resolves a case where the right answer requires context only the human has. Agent recommends; human decides. Default-to-halt is correct; default-to-auto invites silent drift.

### 3.8 Token-cost-conscious

The plugin ships cheatsheets, worked examples, and pre-baked scripts so downstream agents can perform common operations without regenerating SQL or logic from scratch. Snapshots cap session-start ingestion at a bounded delta rather than full history. A local scripts directory amortises learning across sessions.

### 3.9 Golden circle for downstream agents

The plugin's instruction set leads with Why, then How, then What. Downstream agents need motivation and principles to make compatible judgement calls when instructions don't anticipate something. Shipping What (commands, schemas) without the surrounding Why/How produces brittle outputs that break on edge cases.

### 3.10 Two planes deliberately separated

Markdown plan files = rich, context-heavy intent. The event log + projection layer = what actually happened, queryable cheaply. They don't have to agree, and the gap between them is exactly what's interesting — that's where open threads, unmarked-abandoned work, and ratified-but-unlanded decisions become visible.

### 3.11 Dogfooding

This project uses the methodology it captures. Plans live in `planning/`. Once we ship a working extraction, this project's own event log demonstrates the tool against itself.

---

## 4. What — concrete design

Detailed architectural design lives in the **T2 thematic plans**. T1 keeps a high-level overview only — sufficient for an agent or human to orient on the project's shape, with pointers to the T2 plan owning each theme. Migration of architectural detail from T1 §4 into the T2 plans was performed as a methodology-conformance pass; see the philosophies on tier separation (`3-tier-rationale.md`, `golden-circle-grounding.md`) for the underlying discipline.

### 4.1 Themes overview

| T2 plan | Theme | Key surfaces |
|---|---|---|
| [T2-ontology](T2-ontology.md) | Formal event + entity ontology | `events.schema.json`, `plan-frontmatter.schema.json`; 23 event types in 6 categories; 5 entity types + arc-metadata (decisions) + field values (persons); 5 derived states; fulcrum events; ID scheme; positional rollup |
| [T2-storage](T2-storage.md) | Event log + cache + projection storage | `.agent-plan-tracker/events.jsonl` (canonical), `cache.sqlite` (queryable), `projection.json` (view-friendly), snapshots (later); git-blame commit_ref resolution |
| [T2-projection](T2-projection.md) | Views and queries | projection.json emitter; markdown summary; HTML view (dynamic-from-data, vanilla JS); SQL query catalogue; cleanliness gate composite (M3) |
| [T2-packaging](T2-packaging.md) | Plugin scaffold + distribution | Plugin directory layout; `.claude-plugin/plugin.json` manifest; repack-and-validate loop; (M4) npm bundle + project-init install flow |
| [T2-extraction](T2-extraction.md) | Per-commit extraction + merge lifecycle | Pre-commit hook (M2); sequential per-commit extractor; sub-agent recursion; ambiguity halting; pre-merge-to-main cleanliness gate (M3); merge conflict handling |
| [T2-ingest](T2-ingest.md) | Backfill + retrospective mapping | One-shot opt-in backfill workflow (M5); retrospective mapping note for non-native projects; resumability; archived after completion |
| [T2-analyser](T2-analyser.md) | On-demand "what's outstanding?" analysis | Browser-direct Anthropic API call + thin server wrapper; new event types `analysis.live-summary` + `analysis.invalidated`; per-summary markdown files; clean-tree guard; cascade invalidation; bulk mode with prompt caching |

Each T2 owns the architectural detail for its theme. T1 evolves only when the overall project shape changes (intent, themes, audience, methodology). Architectural shifts within a theme update the relevant T2.

### 4.2 Cross-cutting principles

Captured as standalone documents in `agent-plan-tracker/philosophies/`:

- [3-tier-rationale.md](../agent-plan-tracker/philosophies/3-tier-rationale.md) — why T1/T2/T3 (and Mn) with strict separation.
- [golden-circle-grounding.md](../agent-plan-tracker/philosophies/golden-circle-grounding.md) — Why → How → What for downstream agents.
- [top-down-from-job.md](../agent-plan-tracker/philosophies/top-down-from-job.md) — architectural choices trace to concrete jobs.
- [disposable-etl.md](../agent-plan-tracker/philosophies/disposable-etl.md) — bridge code is throwaway by design.
- [swap-out-surfaces.md](../agent-plan-tracker/philosophies/swap-out-surfaces.md) — every framework choice annotated with swap-out triggers.
- [empirical-prompt-architecture.md](../agent-plan-tracker/philosophies/empirical-prompt-architecture.md) — start static, iterate from real failures.
- [tracker-as-agent-memory.md](../agent-plan-tracker/philosophies/tracker-as-agent-memory.md) — the event log substitutes for agent memory across sessions.

The plugin's skills surface these to downstream agents for judgement-call grounding.

### 4.3 Methodology surfaces (recap from §2)

The methodology produces these tracked artefacts:

- **Plans** — `T<n>-<slug>.md`, `M<n>-<slug>.md`, `XT<n>-<slug>.md` (crosscut), `<L>T<n>-<slug>.md` (lettered side quests). Filename load-bearing; equals `entity_id + .md`.
- **Decisions** — text annotations on events, not nodes. Required as paired events for the 5 fulcrum events. See T2-ontology §3.3.
- **Blockers** — external dependencies with raised / progressed / closed lifecycle. See T2-ontology §3.4.
- **HITL questions** — inline in plans; trackable entities. See T2-ontology §3.9.
- **Inbox** — append-only capture surface for ideas not yet earning a plan, at `.agent-plan-tracker/inbox/`. Prehistoric implementation; full lifecycle per T1 §2.6.
- **Implicit work** — catch-all for commits with no corresponding plan. See T2-ontology §3.9.

The tracker (T2-storage + T2-projection) enforces visibility on each.

---

## 5. Open design questions (in queue)

Some original questions are now closed; new ones have surfaced.

**Recently closed during T1 authoring:**
- ~~Plan-vs-tracker rebalance~~ — decisions are arc metadata, separate decisions log artefact dissolves.
- ~~Decision event triad (ratified / referenced / superseded)~~ — collapsed into a single `decision` event referencing `event_ids[]`.
- ~~Multiple T1 plans~~ — corrected to one T1 plus lettered workstreams (XT, PT, AT, etc.).
- ~~Discovery as entity type~~ — out of scope (see §7).
- ~~Pre-commit cleanliness gate~~ — moved to pre-merge-to-main; pre-commit only extracts.
- ~~HTML view: static vs dynamic~~ — dynamic from `projection.json`.
- ~~Entity types count~~ — reduced from 7 to 5 (decisions are arc metadata; persons are field values).
- ~~T2 partitioning: thematic vs milestone~~ — recognised as orthogonal axes, not alternatives. Tn (thematic) and Mn (milestone-sequence) are both first-class; every T3 has one parent on each axis.

**Still open:**

1. **Decision text storage.** Decisions are arc metadata. Does the text live (a) inline in the decision event in `events.jsonl`, (b) in separate `decisions/<id>.md` files referenced by ID, or (c) somewhere else? Each has tradeoffs for searchability, diff-readability, and inline-edit-ability. Defer to M1.
2. **Verification overhaul.** Current 4-event verification category (`claimed / tested / skipped / failed`) is overwrought. A better model may be a 2-event split: `probably-closed` (any agent, after attempting tests if possible) and `actually-closed` (separate agent or human confirms — different actor). Review after M1 surfaces real friction. Until then, the current 4 stand.
3. **Side quest formalisation.** Lettered side quests work conceptually but the methodology around when to spawn one vs extending the main spine isn't crisp. Likely refined through dogfooding.
4. **Projection query catalogue.** What queries / views over the event log are first-class? Chronological-by-entity, completion-status-by-tier, blocker-timeline, decision-trace, smell-detection. The full set defines M3's scope.
5. **Pre-merge gate strictness.** Which smells block automatically vs warn vs ignore? Probably a configurable default-block list with project-level overrides.
6. **Atomicity of supersession + orphan resolution.** Must orphans be resolved in the same commit as the supersession event that created them, or can the supersession land and orphan resolution land in subsequent commits before the merge-to-main gate fires? Lean toward the latter, but worth confirming.
7. **Per-commit extraction agent input contract.** Exactly what's the agent fed? Commit diff + commit message + prior reconciled log via snapshot is the floor. Does it also get the planning files touched by the commit? The entire planning corpus at that commit's state? Affects extraction depth and token budget. Resolve in M2.
8. **Artefact mechanism details.** npm is the suggestion. Could be Node-only, could be a hybrid. Resolve in T2 (M4 packaging milestone).
9. **Milestone-membership representation.** Currently proposed as T3 frontmatter (`milestone: M1-bootstrap`), not a graph relationship event. Rationale: scheduling adjusts naturally as work shapes up, and capturing every reshuffle as an event would be noise. Confirm during M1 dogfooding that frontmatter-only is sufficient for the milestone-progress projection — if not, promote to a tracked relationship.
10. **Milestone supersession semantics.** Mn plans usually progress and complete rather than getting superseded. But what if a milestone genuinely needs to be replaced (e.g. M2's planned shape proves wrong)? Do we apply `entity.superseded` the same way, or does milestone supersession deserve its own treatment given the cross-axis implications?
11. **Ontology specification format.** The ontology is currently captured only as prose in §4 of this T1 doc. For automated extraction (M2 onward) it needs formal capture the extractor can validate against. Default candidate: JSON Schema (most standard, broadly tooled, language-agnostic). Alternatives considered: Zod (TS-first, programmatic), a custom DSL (over-engineering for this scale). Resolve in M1 by landing `schemas/events.schema.json` (and possibly entity / plan-frontmatter schemas) alongside the prose, with `schema_version` on each event tied to a versioned schema file.

---

## 6. Steady-state vision

A project that adopts this plugin gets:

- **One-time backfill**: extraction runs across full git history, produces complete event log. Human-gated where ambiguity arises. For non-native projects, a retrospective mapping note guides the backfill agent's interpretation.
- **Commit-time extraction**: every subsequent commit triggers the pre-commit hook that appends events to the log atomically. Cost amortises over time.
- **Merge-to-main cleanliness gate**: orphans, missing decisions on fulcrum events, and other smells are caught before main is contaminated.
- **Event log as project spine**: agents orienting at session start read the latest snapshot first; planning docs are secondary, fetched per-entity as needed. The log is the canonical project state.
- **Projections on demand**: smell-detection, decision-tracing, entity-timelines, and completion-status across both axes — thematic (per T2) and milestone-sequence (per Mn) — all derived without re-running extraction.
- **HTML view**: dynamic visualisation of current state, time-travellable across snapshots, decision-annotated arcs clickable for rationale.
- **Reasoning chain for agents**: when an agent picks up the project (any time, any session), it has the structured history needed to avoid re-proposing abandoned approaches or missing outstanding threads.

The log itself is a project artefact — small enough to commit, durable across team handovers, queryable without re-running anything.

---

## 7. Out of scope

- **Real-time tracking** of in-flight work. The plugin operates on commits, not on unstaged changes.
- **Cross-repo correlation.** One log per repo. Multi-repo project state is a future problem.
- **Time-cost estimation.** Events are recorded with their commit timestamp; the plugin doesn't try to estimate effort.
- **Performance reviews.** Provenance via `actor` lets you query "events by person X", but the plugin doesn't editorialise on performance.
- **Agent-memory discovery tracking.** Discoveries about libraries, agent behaviours, and methodology gotchas are useful but orthogonal to project history tracking. Decisions cover the structured part adequately for now. May be added later as a separate concern if friction emerges.

---

## 8. Provenance

This project's design surfaced from a conversation about how to reliably audit completion claims in a planning-driven codebase. The seed insight: don't reconcile claimed-vs-actual completion state from multiple divergent sources; instead, event-source from git directly and let every projection derive from the resulting event log.

The methodology in §2 was implicit in early drafts. It was made explicit during a dogfooding pass when the absence of a methodology section was flagged: the plugin's value is half in the methodology and half in the tracking, and the methodology cannot be left implicit if the plugin is to be used on projects whose authors are encountering it for the first time.

Brainstorming proceeded via iterative one-section-at-a-time exploration. Significant refinements during T1 authoring (still ongoing at the time of writing):

- Plan-vs-tracker rebalance: decisions don't need their own log artefact because the tracker captures the structured part; prose handles the human-readable part.
- Decisions are arc metadata, not nodes — text annotations on events, referenced by `event_id`.
- Persons aren't nodes; they're field values.
- Lettered workstreams (XT, PT, AT, etc.) replace "multiple T1 plans" — main spine numbered, exceptions lettered.
- Append-only / supersede-don't-delete discipline made explicit.
- Pre-merge-to-main gate replaces pre-commit cleanliness checking (sub-agent compatibility).
- HTML view is dynamic-from-projection.json, not static-rebuilt.
- Cowork compatibility built into the artefact strategy from T1.
- Event ontology reduced from 26 to 23 events; entity types reduced from 7 to 5; one unified `decision` event replaces the original triad.
- Themes (Tn) and milestones (Mn) recognised as orthogonal partitioning axes, not alternatives — both become first-class plan kinds, discriminated by a `plan_kind` attribute on the `plan` entity. A T3 has one parent on each axis (its thematic T2, its milestone Mn).

Brainstorming proceeded via the `superpowers:brainstorming` discipline (one question at a time, sectioned design presentation, validation per section).
