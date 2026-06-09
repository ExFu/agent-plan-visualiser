---
id: M2-auto-extract
plan_kind: milestone
milestone_index: 2
status: planned
---

# M2-auto-extract — Automated event capture takes over

**Status**: Planned. Design reframed 2026-06-08 (supersedes the 2026-06-02 draft which over-engineered the extraction as a separate program rather than agent instructions). T3s enumerated below; files authored as each becomes active scope.
**Sits at**: Second milestone in the sequence axis. Primary theme: T2-extraction. Touches T2-storage (configurable data dir), T2-packaging (the skill ships in the plugin).

---

## 1. Why this milestone

M1 proved the pipeline **hand-rolled** — events authored by hand in interactive sessions, each JSON line crafted manually, then committed. That is untenable past bootstrap. M2 is the capability T1's steady-state vision turns on: **the agent captures events as part of its normal workflow, guided by a skill, instead of the operator (or the agent) hand-authoring JSON.**

## 2. The key insight: a skill is just instructions

The previous M2 draft (2026-06-02) designed a "shared extraction core module" lifted from `backfill.py`, with an `invoke_extractor` function, an input/output contract, delta detection, and idempotency guards. That was wrong. **A Claude Code skill is instructions the agent follows, not a separate program.**

When the agent runs `/apt-capture`, it reads the skill's instructions and then **does the work itself** — it already has full session context, knows what it just did, knows the ontology, knows the schema. The skill codifies the hand-rolling discipline that's currently spread across CLAUDE.md memory entries, the ontology T2, and tribal knowledge from dogfooding:

- How to emit well-formed schema-`0.3.0` events.
- The entity-type identification rules (plan ID from frontmatter, inbox-item from date.slug, etc.).
- The `entity.created`-must-come-first rule (with frontmatter attributes).
- Fulcrum-decision pairing (which 5 events require a paired `decision`).
- `commit.recorded` as the seal — always last, carries author/date/message_first_line.
- Append-only — just keep appending; events accumulate until the commit seals them.

The `backfill.py` prototype (which *does* call `claude -p` headlessly over historical commits) stays as-is for M5 territory. M2 does not touch it.

## 3. The three decisions that shape M2

### 3.1 Skill-only — no autonomous LLM hook

The original T2-extraction design centred on a **pre-commit hook** that fires a headless `claude -p` extractor on every commit. That costs a **separate metered API call** per commit and **blocks `git commit` ~10–20s**. M2 instead ships a **skill** — instructions the in-session agent follows. No separate metered call, no commit block.

The autonomous `claude -p` pre-commit hook is **deferred** (not cancelled) to a later/M4-adjacent milestone for committers outside a Claude Code session (humans, CI, teammates). It would reuse the `backfill.py` machinery.

### 3.2 Shadow-dev, then full cutover

The canonical hand-rolled log (228 events as of M1 closure) must not be corrupted while the skill is being tuned. So:

- **Shadow phase** — a **configurable data directory** (`APT_DATA_DIR=.agent-plan-tracker-auto/`, gitignored) lets the agent run `/apt-capture` into a throwaway dir. Build cache/projection/summary/view from it; the canonical `.agent-plan-tracker/` is never touched.
- **Cutover** — once the operator eyeballs the shadow output and is satisfied, drop the override. From then on, `/apt-capture` writes the **canonical** log. Existing hand-rolled events are preserved (append-only). Cutover is recorded as a `decision` event.

The configurable data dir is also **permanent product capability** (M4 installs need it), not just a dev-safety hack.

### 3.3 Capture-guard pre-commit hook (tiny, no LLM)

A **pre-commit hook** enforces the discipline — but it's not an LLM-calling hook. It's a tiny shell script that checks a **timestamp**:

1. When the agent completes `/apt-capture`, it writes an untracked timestamp file (e.g. `.agent-plan-tracker/.last-capture`). This is written **last**, after all events are appended, so it genuinely means "events are current as of this instant."
2. The pre-commit hook checks: are any staged files newer than `.last-capture`? If yes → reject with "run `/apt-capture` first." If no → commit proceeds.
3. `.last-capture` is **gitignored** — it's local machine state, not project state.

This enforces "you can't commit without capturing events" at near-zero cost (a timestamp comparison, no LLM call, no network, no block). The *skill* does the thinking; the *hook* just refuses to let you forget.

## 4. What M2 explicitly does NOT include

- **Autonomous `claude -p` pre-commit hook** — deferred to later/M4-adjacent (see §3.1). The `backfill.py` prototype already exists for this path; M2 doesn't touch it.
- **Retroactive extraction / catch-up mode / backfill** — extracting events from *already-committed* history is M5. M2 is about capturing events for *current* work, before it's committed.
- **Merge-to-main cleanliness gate, merge-conflict handler** — M3.
- **Fresh-project install / packaging** — M4.
- **Sub-agent recursion** — the in-session agent has a large context window and can manage its own sub-agents if needed. Not an M2 concern.
- **`needs-review/*.md` ambiguity protocol** — the agent is in-session and simply asks the operator. No filesystem protocol needed.
- **Extraction "core module"** — the 2026-06-02 draft proposed lifting `backfill.py`'s functions into a shared module. That was based on a wrong model (skill-as-program). The skill is instructions; `backfill.py` stays self-contained for M5.
- **Delta detection / idempotency guards** — events are append-only. The agent keeps appending; there's no "re-extraction" to guard against. The `commit.recorded` seal is what closes a block, and the capture-guard hook is what prevents committing without capturing.

## 5. How M2 delivers — T3 tasks

Five T3s. Dependency order in brackets.

1. **`T3-entity-accepted`** [foundation, parallel to #2] — *T2-ontology.* Add the draft→accepted lifecycle for all planning entities: new `entity.accepted` standard event (draft→live, all 5 entity types, not a fulcrum), new `draft` derived state (`entity.created` now lands `draft`, was `live`), `entity.extended` becomes draft-preserving (otherwise unchanged — still reopens closed entities, same as `entity.progressed`). Schema bump `0.2.0`→`0.3.0`. The capture skill consumes this to enforce "no implementation work on draft entities."

2. **`T3-configurable-data-dir`** [foundation, parallel to #1] — *T2-storage.* A shared path resolver: `APT_DATA_DIR` env var → optional committed config default → `.agent-plan-tracker/`. Repoint `cache-build.py`, `projection-emit.py`, `summary-emit.py`, `serve.py` to use it instead of hardcoding. Gitignore `.agent-plan-tracker-auto/`. Permanent product capability (M4 installs need it too).

3. **`T3-apt-capture-skill`** [depends #1] — *T2-extraction.* The skill (or command) that codifies the event-capture discipline for the in-session agent. Contains: the ontology summary at schema `0.3.0`, entity identification rules, the `entity.created`-first rule, the **draft gate** (no `entity.progressed` against draft entities — implementation work requires acceptance; `entity.extended` is valid any time), fulcrum-decision pairing rules, `commit.recorded` semantics, the append-only accumulation model, and the instruction to write `.last-capture` on completion. **This is the M2 headline deliverable.** Name TBD — `/apt-capture` is the working candidate; `/apt-save` is an alternative.

4. **`T3-capture-guard-hook`** [depends #3] — *T2-extraction.* A pre-commit hook (tiny shell script, no LLM) that rejects commits when staged files are newer than `.last-capture`. Installation instructions in the skill; automated installer deferred to M4. `.last-capture` is gitignored and untracked.

5. **`T3-cutover-to-auto`** [depends #1–#4] — *T2-extraction.* Run `/apt-capture` in the shadow dir for a stretch of real work on this project; operator eyeballs the output; flip the config to canonical; record the cutover `decision`; produce ≥1 real commit's events via the skill into the canonical log; confirm `repack-validate.sh` green.

## 6. Definition of done

M2 is complete when:

- The **draft→accepted lifecycle** is live: `entity.accepted` exists at schema `0.3.0`, `entity.created` lands entities in `draft`, `entity.extended` is draft-preserving, and the pipeline (cache/projection/summary) reports draft state.
- The data directory is **configurable** via `APT_DATA_DIR`; every pipeline script honours it.
- The `/apt-capture` skill exists and the in-session agent can follow it to produce well-formed schema-`0.3.0` events — including `entity.created` with attributes (landing in `draft`), the draft gate (no `entity.progressed` on drafts), fulcrum-decision pairing, and `commit.recorded` as seal.
- The **capture-guard hook** rejects commits when staged changes postdate `.last-capture`.
- **Cutover performed**: the operator has eyeballed shadow output, config points at the canonical `.agent-plan-tracker/`, ≥1 real commit's events are captured via the skill, `repack-validate.sh` passes, and the cutover is recorded as a `decision`.

## 7. Open questions (M2-specific)

1. **Skill naming.** `/apt-capture`, `/apt-save`, or something else? The name should convey "record what just happened as events" rather than "extract from history." Resolve in `T3-apt-capture-skill`.
2. **Timestamp granularity.** Does `.last-capture` need sub-second precision, or is second-level sufficient for the guard hook? Lean second-level; filesystem timestamps are typically second-granularity anyway.
3. **Hook installation.** M2 documents how to install the capture-guard hook manually (copy into `.git/hooks/pre-commit`). Automated idempotent installation is M4 scope. Should M2 also ship a one-liner install script as a convenience? Lean yes.
4. **Skill location.** `skills/` or `commands/`? A skill is passive instructions the agent reads when invoked; a command can carry executable logic. `/apt-capture` is instructions — leans `skills/`. Resolve alongside T2-packaging conventions.

## 8. Dependencies

- **M1-bootstrap** (complete) — the pipeline M2 feeds (cache/projection/summary/view) already works.
- **T2-ontology** — the `0.3.0` schema the skill targets (bumped from `0.2.0` by `T3-entity-accepted`).
- **T2-storage** — owns `T3-configurable-data-dir`.
- **T2-packaging** — the skill ships in the plugin.

## 9. After M2

**M3** adds the merge-to-main cleanliness gate (orphans, fulcrum-without-decision, etc.). **M4** packages for distribution — and is where the deferred autonomous `claude -p` pre-commit hook naturally lands (for non-Claude-Code committers), reusing `backfill.py`. **M5** backfills existing/foreign projects via the same `backfill.py` orchestrator.

## 10. Provenance

The first M2 draft (2026-06-02, commit `caa3940`) over-engineered the design around a wrong model: treating the skill as a program that calls an "extraction core module" lifted from `backfill.py`, with input/output contracts, delta detection, catch-up mode over historical commits, and idempotency guards. A 2026-06-08 brainstorming correction surfaced the simpler truth: a skill is just instructions the agent follows; the agent already has full context; events are append-only; retroactive extraction is M5 not M2; and the capture-guard hook is a timestamp check, not an LLM call. This rewrite reflects that correction.
