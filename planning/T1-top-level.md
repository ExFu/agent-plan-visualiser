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

### 4.1 Approach: sequential per-commit extraction

One agent per commit. Each agent reads the existing reconciled event log (via the latest snapshot + delta since) before extracting events from its target commit's primary evidence (diff, message, file states via `git show`).

Reference resolution happens at extraction time because prior history is canonical when the agent runs. No best-guess IDs, no post-hoc reconciliation pass.

For commits whose evidence is too large for one agent's context, the per-commit agent spawns sub-agents that handle parts of the diff. Each sub-agent returns its events to the parent; the parent composes and emits a consolidated report.

Once a per-commit agent's report is appended to the log, the agent's working context is discarded. Only the structured events propagate forward — the master log never grows by the size of the diffs themselves.

The very first extraction agent on a project has no prior log. Its output is the bootstrap state.

Extraction is idempotent within an ontology version: re-running on the same commit produces the same events.

### 4.2 Event ontology — 23 event types in 6 categories

Each event carries common fields:

- `event_id` — unique ID for this event (UUID or similar). Lets decisions reference arcs unambiguously; lets relationships point to specific events.
- `type` — the event type (e.g. `entity.completed`).
- `entity_type` — the kind of node it acts on (e.g. `plan`). Required for all events except meta events (`commit.recorded`).
- `entity_id` — the canonical id within that type (e.g. `T2-ontology`). Required wherever `entity_type` is.
- `actor` — value identifying the actor (github handle or canonical name slug). Persons are field values, not graph nodes.
- `confidence` — `explicit` (stated in commit message or plan) or `derived` (inferred from diff + context).
- `schema_version` — the ontology version this event was extracted against.
- `attributes` — event-type-specific extras.

**Commit metadata is carried once per commit, not on every event.** A single `commit.recorded` event terminates each commit's event group, carrying `author`, `date`, and `message_first_line` in its attributes. All events between the previous `commit.recorded` (or the start of the log) and the next `commit.recorded` belong to the closing one (**positional rollup**). This eliminates per-event redundancy when a commit emits many events.

Notably **no `commit_ref` field in the JSONL** — see §4.7 for why and how commit hash is derived.

**Entity lifecycle (9)**:
- `entity.created` — first appearance.
- `entity.extended` — content added (file grew with new section, addendum, line at end). Includes non-additive plan edits, since the methodology treats plan changes as inherently additive.
- `entity.renamed` — filename/canonical name moved; identity preserved. **Fulcrum event** — decision required.
- `entity.progressed` — work was done but didn't reach closure.
- `entity.completed` — all per-file changes landed; verification claimed.
- `entity.parked` — explicitly deferred. **Fulcrum event** — decision required.
- `entity.cancelled` — won't be done. **Fulcrum event** — decision required.
- `entity.superseded` — replaced by another entity (link required; takes `entity_ids[]` for one-to-many fork). **Fulcrum event** — decision required.
- `entity.reopened` — previously closed, active again. **Fulcrum event** — decision required.

**Decision (1)**:
- `decision` — text annotation with a list of `event_ids` it explains. Required as a paired event for each of the 5 fulcrum events in the same commit; optional on any other event when justification is worth capturing structurally.

**Blockers (3)**:
- `blocker.raised` — external dependency flagged.
- `blocker.progressed` — partial info received from external party.
- `blocker.closed` — external dep resolved.

**Verification (4) — flagged for ontology review (see §5)**:
- `verification.claimed` — commit message or plan asserts completion.
- `verification.tested` — tests written/ran, or a smoke recorded.
- `verification.skipped` — plan's verification step never executed. Carries a `reason` attribute.
- `verification.failed` — audit found gap; entity status reverts toward partial.

**Relationships (5)**:
- `relationship.spawns` — entity A's existence/completion led to entity B.
- `relationship.depends-on` — A blocks B's progress.
- `relationship.addendum-to` — A is an addendum within B.
- `relationship.alongside` — co-evolving without dependency.
- `relationship.reattached` — child moved from old parent to new parent (used in supersession cascade resolution).

**Meta (1)**:
- `commit.recorded` — emitted once per commit as the terminal event of that commit's group. Carries `author`, `date`, and `message_first_line` in its attributes. All preceding events back to the previous `commit.recorded` (or the start of the log) belong to this commit by positional rollup — no explicit event-id list required. Does not carry `entity_type` / `entity_id` (it has no subject entity; it's a boundary marker, not an action on a node). An incomplete trailing run of events with no closing `commit.recorded` represents in-progress extraction not yet sealed into a commit.

Total: 9 + 1 + 3 + 4 + 5 + 1 = **23 events**.

### 4.3 Fulcrum events and decisions

Five events are **fulcrum events** — state-changes that deviate from natural progression and need explaining:

1. `entity.renamed`
2. `entity.parked`
3. `entity.cancelled`
4. `entity.superseded`
5. `entity.reopened`

Each fulcrum event requires a paired `decision` event in the same commit, listing the fulcrum event's `event_id` in its `event_ids` array. The decision carries the text annotation explaining the pivot.

Decisions can also be attached optionally to any non-fulcrum event when the justification is worth capturing structurally rather than only in prose. One decision can list multiple `event_ids` when a single rationale explains several related arcs (e.g. a T2 supersession that spawns two replacement T2s — one decision, three arcs).

Why this matters: every other event is **self-documenting** by nature.
- Decisions, blockers, verifications, and relationships carry their meaning intrinsically — their type and attributes describe what happened and why.
- Natural lifecycle progressions (created, extended, progressed, completed) describe themselves through the diff.
- Fulcrum events alone need external annotation to make sense — they are the bends in an entity's trajectory.

### 4.4 Graph node taxonomy — 5 entity types + arc metadata + actor field

The graph contains three different things:

**Entities (5)** — things with real lifecycles, subjects of work:

1. **`plan`** — a planning artefact (per §2.2–2.4). Discriminated by a `plan_kind` attribute:
   - `plan_kind: thematic` (per §2.2–2.3) — plans on the thematic axis. Carries `tier` (`0 | 1 | 2 | 3`) plus optional `tier_prefix` (single capital letter — omitted for the main spine, `"X"` for crosscut, any other letter for a side quest).
   - `plan_kind: milestone` (per §2.4) — plans on the sequence axis. No `tier` or `tier_prefix`; carries a sequential `milestone_index` (1, 2, 3, …) instead.

   Identity declared in plan frontmatter as a stable `id` field; filename is descriptive convention.
2. **`blocker`** — an external dependency (per §2.6). Slug-identified.
3. **`hitl-question`** — a human-in-the-loop question (per §2.6). Identifier: parent plan id + question number.
4. **`implicit-work`** — work that shipped without a plan (per §2.7). Identifier auto-generated from short commit hash + message-slug.
5. **`inbox-item`** — captured but not picked up (per §2.6). Identifier: date + slug from the inbox heading.

**Arc metadata** — text annotations on events, not graph nodes:

- **decisions** — see §4.3. Live in `events.jsonl` as `decision` events; each carries its own `event_id`, the text content, and a list of `event_ids` it explains. Many arcs can reference the same decision.

**Field values** — not graphed:

- **persons** — actors are referenced by handle or slug in the `actor` field on every event. Searchable as values; not nodes with edges, not entities. A person is just a fact stored in a register, not a thing being worked on.

### 4.5 Derived entity states

Five states an entity can be in, derived from its event history:

- **live** — actively in scope, work continues or is ready to continue (after: created, extended, progressed, reopened).
- **dormant** — explicitly deferred, may return (after: parked).
- **dead** — terminally closed (after: completed, cancelled, superseded).
- **orphaned** — parent died, awaiting resolution. Derived from graph state, not directly emitted.
- **unknown** — ambiguous event chain, needs human review.

**Orphan derivation**: when an entity's parent is superseded and the child has no subsequent `relationship.reattached`, `entity.cancelled`, or `entity.superseded` event, the child is derived as orphaned. Resolution comes via one of those events; the orphaned status then clears.

### 4.6 ID scheme

Events store `entity_type` and `entity_id` as separate fields. The composite `entity_type:entity_id` can be materialised for display.

Per-type id derivation:

| Type | Derivation | Illustrative example |
|---|---|---|
| `plan` (`plan_kind: thematic`) | Frontmatter `id` field declared at plan creation. Form: `<tier_prefix>T<tier>-<slug>` where `tier_prefix` is optional (omitted for the main spine, `X` for crosscut, any other capital letter for a side quest). Slug is semantic; optional shortid suffix for collision resolution. Stable across renames. **Filename is load-bearing: must match `entity_id` + `.md`.** | `T1-top-level`, `T2-ontology`, `XT2-analytics`, `PT3-client-editor` |
| `plan` (`plan_kind: milestone`) | `M<n>-<slug>` — sequential milestone index plus descriptive slug. | `M1-bootstrap`, `M2-auto-extract` |
| `blocker` | Hand-authored slug from blocker description. | `legal-review`, `vendor-api-access` |
| `hitl-question` | Parent plan id + `.q<n>`. | `T2-ontology.q3`, `M1-bootstrap.q1` |
| `implicit-work` | `impl.<short-commit-hash>.<message-slug>` — auto-generated. | `impl.a1b2c3d.silence-typecheck` |
| `inbox-item` | `<date>.<title-slug>` — derived from the inbox heading. | `2026-04-15.handoff-form-textarea` |

Decisions and persons don't follow this scheme. Decisions have only their `event_id` like any event. Persons are handle/slug values in the `actor` field.

Renames: canonical ID is established at `entity.created` and persists across `entity.renamed` events. The rename event records the filename/name change as metadata, but the entity ID does not change. Enforced by frontmatter-declared `id` on plans — moving the file doesn't change the id inside.

Sequential task numbering (e.g. `task-1`, `task-2`) is avoided in favour of semantic slugs to prevent parallel-branch collisions.

### 4.7 Storage architecture

Three-tier storage. Text primary + binary derived cache + materialized snapshots + JSON projection.

**Repo layout** in any project using the plugin:

```
.agent-plan-tracker/
  events.jsonl              # primary, append-only, source of truth
  cache.sqlite              # derived from events.jsonl, regenerable
  projection.json           # current projection for HTML view
  snapshots/
    <YYYY-MM-DD>-<label>/
      snapshot.json
      projection.json
      summary.md
  schema-version.txt
```

**Primary: JSONL events log**

- Append-only, line-delimited JSON. One event per line.
- Per-commit extraction (the pre-commit hook) appends to `events.jsonl` and stages it for inclusion in the commit being made.
- Diff-friendly (text), merge-friendly (append-only), commit-able.
- Schema versioning per event so the ontology can evolve without rewriting history. During T1 active authoring, schema `0.0.0-prehistoric` is used; retroactive migration of these events into a stable schema is acceptable when one ships — it won't remove information, only adjust representation.

**Cache: SQLite**

- Rebuilt from `events.jsonl` on demand. Committed for read-performance but not source of truth.
- Tables: `events` (raw rows, with `commit_ref` populated via `git blame`), `entities` (materialized current state per entity), `decisions` (denormalised text + referenced `event_ids[]`), `relationships` (graph edges).
- Indexes on `entity_type`, `entity_id`, `event_type`, `commit_date`, `event_id`.

Why SQLite (vs alternatives): universal, embeddable, file-based, mature tooling. Sufficient for projected scale. Swap-out trigger documented in §4.10.

**Projection: projection.json**

A derived snapshot of current state in JSON form. The HTML view layer reads this. Generated on demand from the SQLite cache. Includes per-entity event-type sequence (just type names, no full payloads) — the sequence itself is a signal of how complex an entity's backstory is.

**Commit-ref derivation via git blame**

The git commit hash is unknown pre-commit (computed from the tree which includes the events file — chicken-and-egg). Resolution:

- JSONL events do *not* carry `commit_ref` directly.
- The cache builder runs `git blame --line-porcelain .agent-plan-tracker/events.jsonl` to attribute each event line to its source commit.
- Cache's `events` table includes `commit_ref` as a column populated this way.
- Git-less consumers identify events by `commit_meta` (author + date + message-first-line) which is always populated.
- Rebase/amend handled naturally: blame always reports the current history's hash.

Discipline: `events.jsonl` is only appended to via the pre-commit hook (or the manual extract path). Manual edits break blame attribution.

**Snapshots — materialized state + frozen events with commit_refs**

Snapshots serve three purposes:
1. **Agent orientation**: session-start agents read the latest snapshot for current state rather than parsing the full event log. Bounded token cost.
2. **Cache rebuild acceleration**: the cache builder reads frozen events (commit_refs already resolved) from the snapshot and only blames the delta since.
3. **Team-readable status milestone**: committed snapshots give humans a stable reference for "where things were at this point".

Triggers: major plan completions, project milestones, on demand, or auto-rolling every N events (off by default during early use).

Each snapshot directory contains:
- `snapshot.json` — full state at snapshot time, including each entity's event-type sequence and the frozen events with their `commit_refs`.
- `projection.json` — frozen projection for the HTML view to read when exploring history.
- `summary.md` — human-readable digest: open/in-progress entities, just-closed since last snapshot, blocked, active relationships, quick stats. Notable sequence patterns highlighted (flapping closure, long-running blockers, etc.).

### 4.8 Extraction and merge lifecycle

**Pre-commit hook — extract events, never gates on cleanliness**

- Runs the extraction agent before each commit is finalised. Installed via the plugin's project-init command.
- Reads staged diff + commit message file, extracts events, appends to `events.jsonl`, stages the updated log.
- **Happy path**: commit proceeds, capturing substantive changes + their events atomically in one commit.
- **Ambiguity halt**: hook exits non-zero, commit blocked, recommendation written to `.agent-plan-tracker/needs-review/<staged-summary>.md`, human resolves, retries.
- **Alternative for hook-averse setups**: manual extract invocation before manual commit.

The pre-commit hook deliberately does **not** enforce projection cleanliness (no orphan checks, no fulcrum-without-decision checks). Sub-agents commit freely on work branches; mess is allowed locally.

**Pre-merge-to-main gate — projection-must-be-clean**

Methodology cleanliness is enforced at the merge-to-main boundary, not at every commit. Work trees can carry orphans, unclosed verification claims, and other in-progress mess. Main cannot.

Implementation:
- **Local hook (convenience)**: pre-push hook on the developer's machine refuses pushes to main if the projection isn't clean.
- **Server-side hook (enforcement)**: CI check on PRs targeting main that runs the projection-clean check and fails the PR if any of: orphans exist, fulcrum events without paired decisions, configurable verification smells, or other defined smells.
- **Override path**: human can override with an explicit decision event recording why the mess was acknowledged-and-deferred.

This split — extraction at commit, cleanliness gate at merge — accommodates sub-agents committing freely on branches while keeping main canonical.

**Merge conflicts**

Merge commits run through extraction like any other. When two branches' event logs produce contradictions on merge (one branch closed a plan, the other extended it; competing renames for one entity), the hook:

1. Refuses the merge commit; recommendation written to `.agent-plan-tracker/merge-conflicts/<merge-id>.md`.
2. Asks the human. Human reviews, approves the recommendation or supplies a different resolution.
3. Re-attempts the commit with the resolved event log.

The 9-in-10 case: human reads the recommendation, says "looks good", merge proceeds. The 1-in-10 case: human knows context the agent doesn't, redirects. No silent drift past the commit boundary.

**Backfill is opt-in, never automatic**

If an agent in an interactive session notices that extraction is behind (commits exist with no events — project pre-dates the plugin, someone used `--no-verify`), it does **not** auto-backfill. It surfaces:

> "There are N commits without extracted events. Recommend backfilling all N (~X min estimated). Approve?"

…and waits. Agent recommends; human gates.

For projects with planning conventions that don't natively match this methodology, the backfill workflow produces a **retrospective mapping note** — a one-shot translation artefact that explains how the project's existing planning artefacts correspond to this methodology's vocabulary. The per-commit extraction agent uses it as a brief. After backfill, it's archived but not actively referenced; the extracted events are canonical from then on.

### 4.9 HTML view — dynamic from projection.json

The plugin ships an HTML template that reads `projection.json` at load time and renders the project's current state. Templated, debuggable, no hosting needed. Claude can open the HTML directly for the user.

**Why dynamic, not static-per-event:**

1. Data and presentation change at different cadences — events arrive continuously, rendering logic is stable.
2. Interactivity (filter, expand, snapshot-switch) falls out for free with JS-against-data; static rebuild forces JS anyway for any interaction.
3. Time-travel is trivial: pointing the loader at `snapshots/<date>/projection.json` instead of the live `projection.json` is a one-line change.
4. Debuggability: fix the template once, refresh, done. No regeneration cycle.
5. Token cost: generating fresh JSON is mechanical SQL→JSON. Generating fresh HTML burns tokens.
6. The data layer becomes a first-class API consumable by other clients too.

Implementation shape:
- Pure HTML + vanilla JS + JSON data file. No build step.
- JS fetches `projection.json`, renders entity state, event sequences, relationships, and fulcrum-with-decision arcs as clickable nodes/edges.
- Clicking a fulcrum arc reveals the attached decision text.

Two views to prioritise:
1. **Entity state board** — entities grouped by derived state (live / dormant / dead / orphaned / unknown), each entity's event-type sequence visible.
2. **Plan hierarchy tree** — T1 at root, T2s under it, T3s under those, lettered workstreams as siblings of the main T1. Each node shows derived state.

### 4.10 Swap-out points

Annotated places where the design intentionally accepts a specific tradeoff that we may revisit:

- **SQLite as cache backend.** Universal, file-based, sufficient for projected scale. Trigger to revisit: more than ~30% of projection queries require multi-hop traversal (depth ≥ 3), or relationship-pattern matching becomes a primary projection surface. Then evaluate embedded graph engines with GQL/Cypher support (KuzuDB, Cozo). GQL stabilising as a standard reduces the historical lock-in risk of graph engines.
- **Pure HTML + vanilla JS for the view layer.** Zero dependencies. Trigger to revisit: views need significant interactive complexity that vanilla JS makes painful. Then consider a minimal framework (lit-html, Preact) — but avoid a build-step-required SPA.
- **JSONL events as primary storage.** Append-only text, blame-friendly. Trigger to revisit: events become large or numerous enough that append-only text scanning becomes slow. Unlikely within this project's scale.

### 4.11 Plugin structure

```
agent-plan-tracker/                 # the plugin itself
  skills/
    using-agent-plan-tracker.md     # formal spec, full ontology, full schema
  cheatsheet/
    cheatsheet.md                   # common operations, one-liners
    worked-examples/
      find-stalled-plans.md
      audit-verification-gaps.md
      trace-decision-history.md
      pre-merge-cleanliness-check.md
  commands/
    <slash commands — install-into-project, extract, audit, snapshot, etc.>
  bin/
    <scripts the plugin invokes via Claude's Bash tool>
  view/
    index.html                      # HTML view template
    app.js                          # JS that loads projection.json
    style.css
  philosophies/
    3-tier-rationale.md
    golden-circle-grounding.md
    top-down-from-job.md
    disposable-etl.md
    swap-out-surfaces.md
    empirical-prompt-architecture.md
    tracker-as-agent-memory.md
  hooks/
    pre-commit                      # installed by install-into-project
    pre-push                        # installed by install-into-project
```

**Plugin instruction shape**

The skill tells downstream agents:

- Prefer `bin/<script>` over generating SQL from scratch — major token saving.
- If you find yourself generating a useful query repeatedly, save it to `bin/local/<descriptive-name>.sql` for future agents and humans. Lookup order: `bin/` → `bin/local/` → generate-from-scratch-and-save.
- For ontology/schema questions, go to `skills/using-agent-plan-tracker.md`. For common operations, `cheatsheet/cheatsheet.md`. For worked scenarios, `cheatsheet/worked-examples/`. The formal spec is the floor, not the everyday surface.
- The plugin's `philosophies/` content grounds judgement calls when instructions don't anticipate something.

### 4.12 Artefact strategy

The plugin is aimed at **developers**, with the caveat that it also needs to be usable in **Claude Cowork** (Cowork is filesystem-accessing, not browser-only — it's Claude Code with reduced jargon for less-technical users). Cowork is particularly useful when a user wants to work at the T1/T2 (project-management) altitude rather than the T3 (execution) altitude.

The artefact strategy (suggestion — T2 to confirm details):

- A **developer-installed package** (likely npm) that bundles:
  - CLI scripts installed to the user's PATH.
  - Claude plugin files (skills, commands, hooks, view template, philosophies) installed to the user's Claude config directory.
- One install command sets up both.
- The Claude plugin works in both Claude Code and Claude Cowork automatically.
- The plugin's project-init command writes git hooks into the target project's `.git/hooks/`.

Naming TBD — `apt` was rejected due to namespace collision with Debian/Ubuntu's package manager.

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
