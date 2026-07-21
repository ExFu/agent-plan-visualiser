---
name: using-agent-plan-visualiser
description: Orientation and formal reference for agent-plan-visualiser (APV) tracking — the event-sourced planning methodology, its ontology, projections, and where every operation lives. Use when you need to understand how this project's tracking system works, what the event log or its states mean, how to query project state, or which APV skill, script or surface fits an operation.
---

# using-agent-plan-visualiser — how the tracking works

This is the formal floor: the reference you consult when the per-moment
skills (`/apv-capture`, `/apv-merge`) or the cheatsheet don't answer a
question. Everyday operations stay with those surfaces; come here for the
model behind them.

## 1. Why this exists

Planning-driven projects accumulate divergent sources of truth — plans,
decision logs, status prose — and after enough velocity every source
partially lies. **Git commit history is the one artefact that cannot lie
about what happened.** APV event-sources from commits: an append-only event
log is the canonical project state, and every view (status, audits,
diagrams) is a derived, rebuildable projection over it. Plans remain rich
intent; the log records what actually happened; the *gap* between the two
planes is signal, not error.

The log doubles as agent memory: a fresh session reads structured history
instead of re-reading the planning corpus, so it neither re-proposes
abandoned work nor misses open threads.

## 2. The moments and their skills

- **`/apv-init`** — once per repo: attach it (seed the data dir, write
  config, install the git hooks). Idempotent; re-run to audit and repair.
- **`/apv-capture`** — after each logical unit of work, immediately
  **before every commit**: append one sealed event block. The installed
  pre-commit guard rejects uncaptured commits; `git commit --no-verify` is
  the sanctioned hatch for capture-free trivia.
- **`/apv-merge`** — landing a branch on main: branch-side reconciliation
  (main's log must be a prefix), gate-check green, contradictions to the
  operator, rulings recorded as reconciliation events sealed by the merge
  commit. The pre-push and reference-transaction git hooks backstop it.

On a plugin install these skills are namespaced
`agent-plan-visualiser:<name>` in the session's skill list. If neither the
plain nor the namespaced form is available, the session did not load the
plugin (typical in a worktree checkout without a committed
`.claude/settings.json`) — the sources stay readable at
`${CLAUDE_PLUGIN_ROOT}/skills/<name>/SKILL.md`, or from any checkout at the
newest `~/.claude/plugins/cache/*/agent-plan-visualiser/*/skills/`; read
the file and follow it. `/apv-init` checks the enablement is committed.

## 3. Where things live

Data dir resolution, everywhere in the toolchain: `APV_DATA_DIR` env var →
committed `.apv-config.toml` `[storage] data_dir` → default `.apv/`. The
plans directory resolves the same way (`APV_PLANNING_DIR` → `[storage]
planning_dir` → default `planning/`) — a monorepo whose tracked project
lives in a sub-folder pins e.g. `planning_dir = "plugin/planning"` while
the data dir stays at the repo root (captures are commit-anchored, and
commits are repo-level).

**Multiple sub-projects, one repo** (T3-multi-project): register each
project's planning root as `[projects.<name>] planning_dir = "..."`. The
log stays ONE per repo — sub-projects are a dimension of the data, never a
partition of the record. Entity → project membership derives at projection
time: explicit `attributes.project` on any of the entity's events
(latest-recorded wins; the escape hatch for planless entities — inbox
items, blockers) → else whichever registered root owns
`<root>/<entity_id>.md` → else the `[storage]` root as the implicit
project `main` → else `unassigned` (a deliberately visible triage bucket).
The view gains a project filter (all three views) and badges; summary.md a
`## By project` rollup; the gate's drift check walks every root and WARNs
on a plan id present in two roots (entity ids are repo-global). No
`[projects]` tables → single-project behaviour, unchanged. Retrospective
membership (re)assignment — including on **closed** entities — is
`project.assigned` (0.6.0): a state-neutral membership assertion (the
`entity.renamed` precedent — no resurrection, no reopening needed), fulcrum
(paired decision required; one decision covers a bulk assignment).
Latest-recorded wins; once asserted, the attribute is authoritative over
planning-root derivation. Procedure:
`cheatsheet/worked-examples/assign-entity-to-project.md`.

Inside it: `events.jsonl` (canonical, append-only — all integrity
discipline applies here) plus derived, rebuildable artefacts
(`cache.sqlite`, `projection.json`, `summary.md`) — never emit events about
those. The toolchain itself (scripts, schemas, view) lives at the plugin
install (`${CLAUDE_PLUGIN_ROOT}`), or vendored in-repo; it is code, not
data, and never lives in the data dir.

## 4. Ontology — schema 0.3.0

The authority is `schemas/0.3.0/events.schema.json` (+
`plan-frontmatter.schema.json`); this is the orientation summary.

**26 event types**: entity lifecycle ×10 (`created`, `extended`,
`accepted`, `renamed`, `progressed`, `completed`, `parked`, `cancelled`,
`superseded`, `reopened`); `decision` ×1 (subject-less arc metadata —
`attributes.text` + `event_ids[]`); blockers ×3; verification ×4
(`claimed`/`tested`/`skipped`/`failed`); relationships ×5 (`spawns`,
`depends-on`, `addendum-to`, `alongside`, `reattached` — the parent-move
primitive on the milestone/theme axes; sub-project membership moves via
`project.assigned` instead); `commit.recorded` ×1 (the seal: last event of
every block, its `message_first_line` matches the commit's first line
exactly); analysis ×2 (tool-emitted). Later epochs add
`verification.deferred` (0.5.0) and `project.assigned` (0.6.0 — the
state-neutral, fulcrum membership assertion, §3); the newest epoch's
schema is the superset authority for validating a whole log.

**5 entity types**: `plan` (ID = frontmatter `id`; filename must equal
`<id>.md`), `blocker`, `hitl-question`, `implicit-work`, `inbox-item`.
Persons are field values (`actor`), never entities; decisions are arc
metadata, never entities.

**Derived states** (computed, never emitted): `draft` → `live` → `dormant`
/ `closed`, plus `orphaned`/`unknown`. **The draft gate**: no
`entity.progressed`/`entity.completed` against a `draft` entity;
`entity.accepted` is operator-only — never self-issued. **Fulcrum events**
(`renamed`, `parked`, `cancelled`, `superseded`, `reopened`) require a
paired `decision` in the same block.

**Positional rollup**: events between one seal and the next belong to the
later seal's commit — commit↔entity grouping is projection-time work.

## 5. The methodology being tracked

Plans live in `planning/`, tiered by altitude: **T1** intent (why/success/
themes), **T2** per-theme architecture, **T3** executable briefs. **Mn**
milestone plans sequence the same work on an orthogonal axis (every T3 has
a thematic parent and a milestone). Lettered workstreams (`XT*` crosscuts,
`PT*`-style side quests) get their own tier trees. Plans are append-only:
small adjustments append, bigger shifts supersede (never delete), and a
superseded parent's children are orphans until explicitly resolved.

## 6. Operating rules (the instruction shape)

1. **Prefer shipped scripts over regenerating logic**:
   `${CLAUDE_PLUGIN_ROOT}/scripts/` has the pipeline
   (`repack-validate.sh`, `cache-build.py`, `projection-emit.py`,
   `summary-emit.py`), the audits (`audit-*.sql`), timelines and traces
   (`timeline-for-entity.sh`, `trace-decision-history.sh`), the gate
   (`gate-check.sh`), and the view server (`serve.py`).
2. **Save reusable queries you find yourself regenerating** to
   `scripts/local/<descriptive-name>.sql` — future agents and humans
   inherit them. Lookup order: `scripts/` → `scripts/local/` → generate
   and save.
3. **Common operations**: `cheatsheet/cheatsheet.md`; worked scenarios:
   `cheatsheet/worked-examples/`.
4. **Judgement calls** the instructions don't anticipate: ground them in
   `philosophies/` (tier rationale, golden-circle grounding, tracker-as-
   agent-memory, disposable ETL, swap-out surfaces, empirical prompts).

## 7. The gate, in one paragraph

`gate-check.sh` is the single boundary contract for main: the integrity
composite (blocking = corruption of the record — schema, referential,
sealed-tail, implementation-on-draft, resurrection-without-reopen,
fulcrum-without-decision; warn = dashboard signal — drift, orphans,
stalled, long-blockers) plus the seal↔commit correspondence check. Policy
lives in `.apv-config.toml` `[gate]`. It fires procedurally in
`/apv-merge` and through the pre-push and reference-transaction hooks.
Blocking defects are **repaired, not overridden** (append-only repairs —
e.g. a later `entity.reopened` heals a resurrection); `APV_SKIP_GATE=1`
and `--no-verify` are emergency hatches, not disagreement mechanisms.
