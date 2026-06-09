---
id: T3-apt-capture-skill
plan_kind: thematic
tier: 3
t2_parent: T2-extraction
milestone: M2-auto-extract
status: draft
---

# T3-apt-capture-skill — Codify the event-capture discipline as a skill

**Status**: Draft.
**Sits at**: T2-extraction theme, M2-auto-extract milestone. M2 headline deliverable — depends on `T3-entity-accepted` (draft/accepted semantics); parallel to `T3-configurable-data-dir`.

---

## 1. Why

Today the event-capture discipline is spread across CLAUDE.md memory entries, the T2-ontology prose, the schema files, and tribal knowledge from dogfooding sessions. Every new agent (or returning human) has to rediscover the rules: emit `entity.created` with frontmatter attributes first, pair decisions with fulcrum events, seal with `commit.recorded`, use the right `schema_version`, etc. Mistakes are caught only when `repack-validate.sh` fails — after the damage is done.

A skill packages these rules as **instructions the in-session agent reads and follows**, replacing hand-rolled JSON with guided, structured event capture. The agent already has full session context and knows what it did — the skill tells it *how to record that as events*.

## 2. What

A skill file (in the plugin's `skills/` directory) that the agent invokes via `/apt-capture` (working name; `/apt-save` is an alternative — see §7 Q1). The skill contains:

### Content outline

1. **When to run.** After completing a logical unit of work, before committing. Can be run multiple times — events are append-only; each invocation adds to the pending block.

2. **Ontology summary at schema `0.3.0`.** A concise reference the agent consults during capture:
   - The 26 event types (10 entity lifecycle + 1 decision + 3 blocker + 4 verification + 5 relationship + 1 meta + 2 analysis) with one-line descriptions and required attributes.
   - The 5 entity types with ID derivation rules (plan from frontmatter `id`, inbox-item from `date.slug`, etc.).
   - The 5 fulcrum events requiring paired `decision` events (renamed, parked, cancelled, superseded, reopened).
   - The 6 derived states, including `draft` (`entity.created` lands there) and the `entity.accepted` transition to `live`.

3. **Entity identification rules.**
   - Plans: read frontmatter `id` field — never guess from filename alone.
   - `entity.created` **must** come first for any entity not yet in the log, carrying frontmatter attributes (`plan_kind`, `tier`, `t2_parent`, `milestone`, etc.). Without it, downstream projections lose routing info.
   - `implicit-work` for commits that touch code but no plans.

4. **The draft gate.** All entities start as `draft` (`entity.created`). **No implementation work may be recorded against a draft entity** — `entity.progressed` requires the entity to have been accepted (`entity.accepted`, typically by the human operator). Plan extensions (`entity.extended`) are valid in any state and preserve `draft`. If the agent finds itself with code changes against a draft plan, it must stop and ask the operator to accept the plan first — not silently emit `entity.progressed`.

5. **Event-emission rules.**
   - Every event needs: `event_id` (UUID v4), `type`, `entity_type`, `entity_id`, `actor`, `confidence` (`explicit` | `derived`), `schema_version` (`"0.3.0"`), `attributes`.
   - `commit.recorded` is always the **last** event in a block. Carries `author`, `date`, `message_first_line` in attributes. Does not carry `entity_type`/`entity_id`.
   - `decision` events don't carry `entity_type`/`entity_id`; they reference arcs via `attributes.event_ids[]`.
   - `relationship.reattached` uses `from_parent`/`to_parent` (not `from_entity_id`).
   - Append-only. Never edit prior events. Just keep appending.

6. **The `.last-capture` timestamp.** After appending all events, write the current timestamp to `.agent-plan-tracker/.last-capture` (or the configured `APT_DATA_DIR` equivalent). This file is gitignored and untracked — it's local state consumed by the capture-guard hook.

7. **What NOT to do.**
   - Don't emit lifecycle events on already-closed entities just because their files were touched (the `2026-05-30.progressed-after-completed-state-flip` lesson).
   - Don't emit events for derived artefacts (cache.sqlite, projection.json, summary.md — those are rebuilt, not tracked).
   - Don't guess entity IDs — read frontmatter or the existing log.
   - Don't emit `entity.progressed` against a draft entity — see the draft gate (§2.4).

## 3. Scope

### In scope
- Author the skill file with the content above.
- Place it in `agent-plan-tracker/skills/` with appropriate frontmatter for Claude Code plugin discovery.
- Test: invoke the skill in-session, capture events for a real piece of work on this project, run `repack-validate.sh`, confirm events are well-formed and the pipeline is green.

### Out of scope
- The capture-guard hook (`T3-capture-guard-hook`).
- The configurable data dir (`T3-configurable-data-dir`).
- Retroactive extraction / backfill (M5).
- Automated validation of events at capture time (the skill instructs; `repack-validate.sh` catches errors; inline validation tooling is future work).

## 4. Approach

The skill is a markdown file with YAML frontmatter (standard Claude Code plugin skill format). The agent reads it when `/apt-capture` is invoked and follows the instructions to:

1. Review what work was done in the current session.
2. Identify which entities were affected and what events to emit.
3. Append well-formed JSON events to `events.jsonl` in the configured data dir.
4. Seal with `commit.recorded` if this is the final capture before committing (or leave unsealed if more work is expected).
5. Write `.last-capture` timestamp.

The skill references the schema files (`schemas/0.3.0/events.schema.json`, `schemas/0.3.0/plan-frontmatter.schema.json`) for the agent to consult if it needs precise field validation.

## 5. Verification

1. Invoke `/apt-capture` in a real session after doing real work on this project.
2. Appended events pass `validate-events.sh`.
3. `repack-validate.sh` green end-to-end.
4. Projection/summary correctly reflect the captured work.

## 6. Dependencies

- T2-ontology — the `0.3.0` schema the skill references.
- `T3-entity-accepted` — defines the draft/accepted semantics the draft gate enforces. Must land first.
- Parallel to `T3-configurable-data-dir` (the skill should write to the configured dir, but can hardcode `.agent-plan-tracker/` initially and adopt the resolver once both T3s land).

## 7. Open questions

1. **Naming.** `/apt-capture`, `/apt-save`, or something else? "Capture" conveys "record what happened"; "save" is more casual. The name sets expectations for every future user of the plugin.
2. **Seal-or-not UX.** Should the skill always emit `commit.recorded` (sealing the block), or should it ask "are you about to commit, or will you do more work first?" and only seal when the agent is about to commit? Lean: always seal — the agent can run `/apt-capture` again and a new block starts. Simpler than managing open blocks.
3. **Skill vs command.** `skills/` (passive instructions) vs `commands/` (can carry executable logic). This is purely instructional — leans `skills/`. Resolve alongside T2-packaging conventions.
