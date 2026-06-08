---
id: T2-extraction
plan_kind: thematic
tier: 2
status: draft
---

# T2-extraction — Per-commit event extraction + merge lifecycle

**Status**: Draft. M2 reframed 2026-06-08 (skill-as-instructions, capture-guard hook, no extraction core module); T3s enumerated in [[M2-auto-extract]].
**Theme**: The pipeline that turns commits into events automatically. In-session capture skill, capture-guard pre-commit hook, merge conflict handling, pre-merge-to-main cleanliness gate. **This T2 is the architectural source of truth for extraction**; T1 only summarises.

---

> **Reframe (2026-06-08, supersedes the 2026-06-02 note and the original hook-as-primary framing).** Two corrections:
>
> **(1) A skill is instructions, not a program.** The 2026-06-02 reframe correctly rejected the autonomous `claude -p` hook but then proposed a "shared extraction core module" lifted from `backfill.py` with input/output contracts, delta detection, catch-up mode, and idempotency guards. That over-engineered it. A Claude Code skill is **instructions the in-session agent follows** — the agent already has full session context, knows what it just did, and appends events directly. No separate program, no `invoke_extractor`, no bundle builder. The `backfill.py` prototype stays self-contained for M5 (retroactive extraction over historical commits); M2 does not touch it.
>
> **(2) The pre-commit hook is a timestamp guard, not an LLM call.** M2 ships a tiny shell-script hook that rejects commits when staged files are newer than an untracked `.last-capture` timestamp (written by the skill on completion). No LLM, no network, no block. The *skill* does the thinking; the *hook* enforces "you can't commit without capturing."
>
> Consequences: §3.1–3.3 (sequential extraction, agent contracts) describe the **retroactive/backfill** model (`backfill.py`, M5) — not M2's in-session capture. §3.4 (autonomous `claude -p` hook) remains deferred. §3.6 (`needs-review/*.md`) is dropped for in-session (agent asks the operator) but retained for the deferred hook. §4 T3 candidates rewritten. Full M2 shape: [[M2-auto-extract]].

## 1. Why this T2 exists

M1 hand-rolls events to prove the model. M2 turns the lights on: events get extracted automatically from commits, with no human in the inner loop.

Without this:
- Every commit needs manual event authoring (untenable past M1).
- Extraction quality varies per session (no canonical agent prompt).
- Sub-agents committing on branches can't participate cleanly.
- Merge conflicts in event logs cause silent drift.

T2-extraction owns the pipeline that makes the tracker self-maintaining.

## 2. What lives in this theme

- **Per-commit extraction agent** — its prompt, brief, input/output contract.
- **Pre-commit hook** — git hook that fires the extractor, appends events to events.jsonl, stages it.
- **Sub-agent recursion** — handling commits whose diff exceeds a single agent's context.
- **Ambiguity halting** — what counts as ambiguity, how the agent surfaces it, the resolution workflow.
- **Merge conflict handling** — detecting event-log contradictions, asking the human, re-attempting.
- **Pre-merge-to-main cleanliness gate** (M3) — projection-must-be-clean check before merge to main.
- **Backfill primitive** — opt-in catch-up extraction (full backfill workflow lives in T2-ingest, but reuses the same extractor).

## 3. Architecture

### 3.1 Sequential per-commit extraction

One agent per commit. Each agent reads the existing reconciled event log (via latest snapshot + delta since) before extracting events from its target commit's primary evidence (diff, message, file states via `git show`).

**Reference resolution happens at extraction time** because prior history is canonical when the agent runs. No best-guess IDs. No post-hoc reconciliation pass. Trades parallelism for correctness.

The very first extraction agent on a project has no prior log — its output is bootstrap state.

**Idempotency:** re-running extraction on the same commit produces the same events (within an ontology version).

### 3.2 Per-commit agent input contract (M2 v1)

Locked floor: agent receives commit diff + commit message + prior reconciled log via snapshot + planning files touched by the commit + the active `events.schema.json` (T2-ontology) for validation.

Considered and deferred:
- Entire planning corpus at commit's state (probably overkill — token cost too high; if needed, agent can fetch specific files).
- File histories beyond the commit's own diff (only needed for rename detection; defer until M2 surfaces this as a real friction).

### 3.3 Per-commit agent output contract

Agent returns:
- A list of events to append (each validated against `events.schema.json`).
- An optional ambiguity report (if anything blocks confident extraction).
- A token-cost summary (for monitoring).

Events are appended in order; the final event is the terminal `commit.recorded` carrying commit_meta (author / date / message_first_line).

### 3.4 Pre-commit hook flow — **deferred out of M2** (see Reframe above)

> Retained as the design for the *autonomous* trigger that lands in a later/M4-adjacent milestone for non-session committers. M2 itself uses `/apt-extract` (in-session) instead; the hook below reuses the same extractor `core` when it does land.

Installed by the plugin's project-init slash command (T2-packaging M4). The hook:

1. Reads staged diff + commit message file (passed by git as args).
2. Invokes `claude` CLI with the extraction prompt and input bundle.
3. Receives events; validates each against schema (per T2-ontology).
4. If valid + no ambiguity: appends to `.agent-plan-tracker/events.jsonl`, stages the log, exits 0. Commit proceeds.
5. If ambiguity halt: writes recommendation to `.agent-plan-tracker/needs-review/<staged-summary>.md`, exits non-zero. Commit blocked.
6. If validation fails: same path as ambiguity halt — write failure detail, exit non-zero.

The hook deliberately does **not** enforce projection cleanliness (no orphan checks, no fulcrum-without-decision checks). Sub-agents commit freely on work branches; mess allowed locally.

**Alternative for hook-averse setups:** manual extract invocation before `git commit --no-verify`. Same code path, different trigger. Backfill catches up later.

### 3.5 Sub-agent recursion for large diffs

When a commit's diff exceeds a single agent's context budget:

1. Top-level extraction agent recognises overflow during initial inspection.
2. Spawns sub-agents handling specific file clusters.
3. Each sub-agent emits its events to the parent.
4. Parent composes + emits the consolidated event list.
5. Parent's working context is discarded after emission. Only structured events propagate forward — the master log never grows by the size of the diffs themselves.

Keeps master extraction always bounded in context.

### 3.6 Ambiguity halting

Agent halts when:
- A diff touches an entity it can't confidently identify.
- A fulcrum event lacks an obvious decision rationale.
- An existing entity_id conflicts with new content.
- Schema validation fails after best-effort fixup.

Default-to-halt is correct; default-to-auto invites silent drift.

Halt produces `.agent-plan-tracker/needs-review/<commit-slug>.md` with:
- The ambiguity description.
- Agent's recommended resolution (if any).
- Specific events that would be emitted under each candidate resolution.
- "Next steps" for the human.

### 3.7 Pre-merge-to-main cleanliness gate (M3)

Methodology cleanliness enforced at merge-to-main boundary, not every commit. Work trees can carry orphans, unclosed verification claims, in-progress mess. Main cannot.

Two layers:
- **Local hook (convenience)**: pre-push refuses pushes to main if projection isn't clean.
- **Server-side hook (enforcement)**: CI check on PRs targeting main runs T2-projection's cleanliness composite and fails on blocking smells.

**Override path:** human can override with explicit `decision` event recording why mess was acknowledged-and-deferred. Override is auditable.

This split — extraction at commit, cleanliness at merge — accommodates sub-agents committing freely while keeping main canonical.

### 3.8 Merge conflict handling

Merge commits run through extraction like any other. When two branches' event logs produce contradictions (one closed a plan, the other extended it; competing renames for one entity), the hook:

1. Refuses the merge commit; writes recommendation to `.agent-plan-tracker/merge-conflicts/<merge-id>.md` — what each branch did, agent's suggested resolution.
2. Asks the human. Human reviews, approves or supplies different resolution.
3. Re-attempts commit with resolved event log.

9-in-10 case: human reads recommendation, says "looks good", merge proceeds. 1-in-10 case: human knows context the agent doesn't, redirects. No silent drift past commit boundary.

### 3.9 Backfill primitive

If an agent in an interactive session notices extraction is behind (commits exist with no events — project pre-dated plugin install, someone used `--no-verify`), it does **not** auto-backfill. Surfaces:

> "There are N commits without extracted events. Recommend backfilling all N (~X min estimated). Approve?"

…and waits. Agent recommends; human gates.

Core extractor here is identical to pre-commit's — just invoked sequentially over historical commits. T2-ingest builds on this primitive for non-native projects.

## 4. T3 candidates

### M2-scheduled (skill-as-instructions — see [[M2-auto-extract]] §5)
- `T3-configurable-data-dir` — *(T2-storage-owned)* `APT_DATA_DIR`-aware path resolver; repoint all pipeline scripts; gitignore `.agent-plan-tracker-auto/`. Permanent product capability (M4 installs need it too).
- `T3-apt-capture-skill` — the in-session skill codifying the event-capture discipline (ontology summary at `0.2.0`, entity ID rules, `entity.created`-first, fulcrum-decision pairing, `commit.recorded` as seal, append-only accumulation, `.last-capture` timestamp on completion). M2 headline deliverable.
- `T3-capture-guard-hook` — tiny pre-commit hook (shell script, no LLM) that rejects commits when staged files are newer than `.last-capture`. No network, no block.
- `T3-cutover-to-auto` — validate in shadow, operator eyeballs, flip config to canonical, record the cutover decision, dogfood forward.

### Deferred out of M2 (later / M4-adjacent — autonomous trigger for non-session committers)
- `T3-autonomous-extraction-hook` — the `claude -p` hook (§3.4) for humans/CI committing outside a Claude Code session. Reuses `backfill.py` machinery.
- `T3-hook-installer` — drops hooks into a target's `.git/hooks/`; idempotent against existing hooks.
- `T3-sub-agent-recursion` — large-diff overflow handling; pulled forward only if a real commit overflows.

### M3-scheduled
- `T3-pre-merge-hook` — local pre-push.
- `T3-server-side-cleanliness-gate` — CI integration (GitHub Actions template).
- `T3-merge-conflict-handler` — merge-time arbitration flow.

## 5. Dependencies

- T2-ontology — extractor validates against the schema; prompt embeds the ontology summary.
- T2-storage — extractor appends to events.jsonl in storage's format.
- T2-projection — pre-merge gate invokes T2-projection's cleanliness composite (T2-projection §3.5).
- T2-packaging — hook installation lives in the plugin's project-init flow.

## 6. Swap-out points

- **Single-agent-per-commit (sequential).** Trade parallelism for correctness. Trigger to revisit: extraction becomes a bottleneck. Probably never for a single repo.
- **Ambiguity halt via filesystem note.** Simple, durable, git-trackable. Alternative: in-process interactive prompt (poor for sub-agents). Stick with files.

## 7. Open questions

1. **Atomicity of supersession + orphan resolution.** Must orphans be resolved in same commit as the supersession that created them, or can supersession land and orphan resolution land in subsequent commits before the merge-to-main gate fires? Lean toward the latter; confirm in `T3-pre-merge-hook`.
2. **Pre-merge gate strictness defaults.** Which smells block automatically vs warn vs ignore? Configurable default-block list with project-level overrides.
3. **Extractor LLM choice.** Probably Sonnet for routine, escalate to Opus on ambiguity-halt re-runs.
4. **Hook installation idempotency.** Re-running project-init should not break existing hooks. Handle existing `pre-commit` files (chain via prefix? refuse? warn?).
5. **Token budget per commit.** What's the practical ceiling for a commit's input bundle? Defines when sub-agent recursion kicks in.

## 8. Out of scope

- Real-time / streaming extraction.
- Multi-repo correlation (out of scope per T1 §7).
- Synthetic event generation (only real commits emit events).
