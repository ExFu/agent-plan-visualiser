---
name: apt-capture
description: Capture the current session's work as structured events in the agent-plan-tracker event log. Use after completing a logical unit of work, immediately before git-committing, in any project tracked by agent-plan-tracker (has a .agent-plan-tracker/events.jsonl or APT_DATA_DIR equivalent).
---

# /apt-capture — record what just happened as events

You (the in-session agent) are the extractor. You have full session context: you know what you did, which plans you touched, and why. This skill tells you how to record that as events. The event log is the project's source of truth — plans and status reports are secondary.

**Append-only. One capture = one sealed block = the git commit you are about to make.**

## 0. Resolve the data dir and schema

- `DATA_DIR` = `$APT_DATA_DIR` if set (absolute, or relative to repo root), else `.agent-plan-tracker/`.
- Events file: `$DATA_DIR/events.jsonl`. Never create it implicitly — if it doesn't exist, stop and ask the operator (the project may not be initialised).
- Emit events at `schema_version: "0.3.0"`. Precise field shapes: `agent-plan-tracker/schemas/0.3.0/events.schema.json` (and `plan-frontmatter.schema.json` for plan attributes).

## 1. When to run

- After completing a logical unit of work, **immediately before `git commit`** — capture is the last act before committing.
- Each invocation appends one block ending in `commit.recorded` (the seal). Events between the previous seal and yours belong to your commit (**positional rollup**).
- If you realise events are missing *after* sealing: never edit prior lines. Fold the omission into your **next** capture, noting it in that event's summary. (If you haven't committed yet and the omission is serious, ask the operator.)

## 2. Ontology quick reference — schema 0.3.0, 26 event types

### Entity lifecycle (10)

| Event | Meaning | Fulcrum (paired `decision` required)? |
|---|---|---|
| `entity.created` | First appearance. **Must be the entity's first event**, carrying its identifying attributes (for plans: the frontmatter — `plan_kind`, `tier`, `t2_parent`, `milestone`, `status`, plus a `summary`). Lands the entity in `draft`. | No |
| `entity.extended` | Content added to the entity's own document (plan edits are inherently additive). Valid in any state; draft-preserving. | No |
| `entity.accepted` | Entity confirmed real and actionable; `draft` → `live`. **Operator (or overseer) confirmation only — never self-issued by the working agent.** | No |
| `entity.renamed` | Identity migration `attributes.from_name` → `attributes.to_name` (history follows, children follow, state-neutral). | **Yes** |
| `entity.progressed` | Implementation work done, not yet closed. **Subject to the draft gate (§4).** | No |
| `entity.completed` | Work landed; verification claimed. | No |
| `entity.parked` | Explicitly deferred. | **Yes** |
| `entity.cancelled` | Won't be done. | **Yes** |
| `entity.superseded` | Replaced by other entity/entities (`attributes.entity_ids[]` required). | **Yes** |
| `entity.reopened` | Previously closed, deliberately active again. | **Yes** |

### Decision (1)

`decision` — `attributes.text` + `attributes.event_ids[]` (the arcs it explains). **No `entity_type`/`entity_id`.** Required in the same block as each fulcrum event; optional wherever rationale is worth keeping. One decision may cover several related arcs.

### Blockers (3)

`blocker.raised`, `blocker.progressed` (requires `attributes.note`), `blocker.closed`.

### Verification (4)

`verification.claimed`, `verification.tested` (typically `test_type`, `command`, `result`), `verification.skipped` (requires `reason`), `verification.failed`.

### Relationships (5)

`entity_id` on the event is the **focal/downstream** entity; `attributes.from_entity_type` + `attributes.from_entity_id` identify the other end:

- `relationship.spawns` — `entity_id` is the spawned child; `from_*` the spawner. Emit alongside `entity.created` for every new plan with a parent.
- `relationship.depends-on` — `entity_id` is the dependent.
- `relationship.addendum-to`, `relationship.alongside` (commutative; pick the later-created entity as `entity_id`).
- `relationship.reattached` — **the sole exception**: `attributes.from_parent` + `attributes.to_parent` (not `from_entity_*`). This is the move primitive; it supersedes the prior spawns edge in projections.

### Meta (1)

`commit.recorded` — the seal. Always **last** in the block. Attributes: `author`, `date` (YYYY-MM-DD), `message_first_line` — which must match the upcoming git commit's first line **exactly**. Carries **no** `entity_type`/`entity_id` (ruled 2026-06-09): a commit may affect many entities and none is privileged at write time — commit↔plan grouping is projection-time work over the positional rollup, not a write-time annotation. (16 seals from the 0.2.0–0.3.0 era do carry entity fields; that is historic drift, preserved append-only — do not imitate.)

### Analysis (2)

`analysis.live-summary`, `analysis.invalidated` — emitted by the analyser tooling (see T2-analyser), not by hand during capture.

### Entity types and ID derivation (5)

| Type | ID | Example |
|---|---|---|
| `plan` | Frontmatter `id` — **read it, never guess from filename** (though filename must equal `<id>.md`) | `T2-ontology`, `M2-auto-extract`, `XT2-analytics` |
| `blocker` | Hand-authored slug | `legal-review` |
| `hitl-question` | `<parent-plan-id>.q<n>` | `T2-ontology.q3` |
| `implicit-work` | `impl.<short-hash>.<message-slug>` — backfill catch-all; see §3 | `impl.a1b2c3d.fix-typo` |
| `inbox-item` | `<YYYY-MM-DD>.<title-slug>` | `2026-05-23.html-view-visual-style` |

### Derived states (6) — computed, never emitted

`draft` (after created) → `live` (accepted / progressed / reopened / extended-from-non-draft) → `dormant` (parked) / `closed` (completed / cancelled / superseded); plus derived `orphaned` and `unknown`. `entity.renamed` is state-neutral. `entity.extended` preserves `draft`; from any other state it maps to `live` (reopening closed entities, same as `progressed`).

## 3. Entity identification rules

1. **Plans**: open the file, read frontmatter `id`. New plan file ⇒ `entity.created` **first**, attributes = the frontmatter + a summary, then `relationship.spawns` from its parent (`t2_parent` for T3s; T1 for T2s; the spawning plan for milestones/side-quests).
2. **Existing entities**: check the log (`grep '"entity_id": "<id>"' $DATA_DIR/events.jsonl`) or the cache before emitting — never assume an entity exists, and never re-create one that does.
3. **Plan-less work**: `implicit-work` is primarily the backfill (M5) construct — its ID needs the commit hash, which doesn't exist pre-commit. In-session you almost always know better: attribute the work to the real plan/inbox item it serves, or raise an inbox item. A genuinely trivial plan-less commit (pure typo fix) may skip capture entirely via `git commit --no-verify` — that is the sanctioned escape hatch, not a failure.
4. **Inbox items**: things noticed but not actioned — capture as `entity.created` (entity_type `inbox-item`, ID `<today>.<slug>`) with a summary. They are born `draft`; that is correct (untriaged). No file needed.

## 4. The draft gate ⛔

**No implementation work may be recorded against a `draft` entity.** Before emitting `entity.progressed` **or `entity.completed`** (both record implementation work — a draft must not be progressed *or* sealed closed unreviewed), check the entity's current derived state:

```bash
sqlite3 "$DATA_DIR/cache.sqlite" "SELECT derived_state FROM entities WHERE entity_id='<id>';"
```

(If the cache is stale, rebuild via `python3 agent-plan-tracker/scripts/cache-build.py`, or scan the entity's event history in the log tail.)

- State `draft` → **stop**. Ask the operator to accept the entity. On their confirmation, emit `entity.accepted` (their say-so is the event), *then* the lifecycle event. Never silently progress or complete a draft, and never self-accept. **One carve-out**: `implicit-work` created-and-completed in the same block (the planless-commit pattern) passes through draft transiently by design — no acceptance needed.
- `entity.extended` (refining the entity's own document) is valid in any state, including draft — authoring is not implementation.
- Code changes serving a draft plan with no operator available ⇒ the work waits, or the operator's standing instructions govern. The gate exists so plans are reviewed before they steer implementation.

## 5. Event-emission rules

Every event:

- `event_id` — fresh UUID v4. Never reuse.
- `type` — from §2.
- `entity_type` / `entity_id` — required for all events **except** `decision` and `commit.recorded` (both subject-less).
- `actor` — who did/decided the work (handle, e.g. `"al"`). Acceptance events carry the accepting operator.
- `confidence` — `explicit` (stated in plan/commit/conversation) or `derived` (inferred).
- `schema_version` — `"0.3.0"`.
- `attributes` — per-type extras (§2). Always include a human-useful `summary` on lifecycle events.

**Mechanics**: append with python3 + `json.dumps` (default separators, default ensure_ascii), one object per line, key order `event_id, type, actor, confidence, schema_version, entity_type, entity_id, attributes`:

```python
import json, uuid
events = [...]  # dicts in block order
with open(EVENTS_PATH, "a") as f:
    for e in events:
        f.write(json.dumps(e) + "\n")
```

**Block order**: `entity.created` events first (each immediately followed by its `relationship.spawns`), then the rest in narrative order, each fulcrum adjacent to its paired `decision`, and `commit.recorded` last.

## 6. Validate, then timestamp

1. `bash agent-plan-tracker/scripts/repack-validate.sh` — must pass end-to-end (honours `APT_DATA_DIR`). A failure means your block is malformed: fix by appending nothing further until you understand it; ask the operator if unclear. (Pre-seal you may correct an uncommitted block only by consulting the operator — the default remains append-only.)
2. Sanity-check derived states for the entities your block touched — closures show `closed`, new untriaged items show `draft`:

```bash
sqlite3 "$DATA_DIR/cache.sqlite" "SELECT entity_id, derived_state FROM entities WHERE entity_id IN ('<id1>','<id2>');"
```

3. Write the capture timestamp — **the very last action**, consumed by the capture-guard pre-commit hook (gitignored local state):

```bash
date +%s > "$DATA_DIR/.last-capture"
```

Then commit. The git commit's first line must match your seal's `message_first_line`. **Touch nothing after writing `.last-capture`** — the guard hook rejects staged files newer than it. If something must change anyway: substantive change → append events, re-validate, re-timestamp; mechanical fix-up → re-validate, re-timestamp.

## 7. What NOT to do

- **Don't emit lifecycle events on closed entities just because their files were touched** (the `2026-05-30.progressed-after-completed-state-flip` lesson — `progressed` would resurrect them). Post-completion theme work targets the live T2 parent; genuine continuation needs `entity.reopened` + decision; bug-fix follow-on spawns a new T3.
- **Don't emit events for derived artefacts** — `cache.sqlite`, `projection.json`, `summary.md` are rebuilt, not tracked.
- **Don't guess entity IDs** — read frontmatter or the log.
- **Don't progress or complete a draft** (§4) and **don't self-accept**.
- **Don't edit or reorder prior lines, ever.** Append-only.
- **Don't seal with a message you don't then use** — seal and commit message must match.

## 8. Worked example

Work done: extended plan `T3-foo` (accepted, live) and completed it after a green test run. Block:

```json
{"event_id": "<uuid4>", "type": "entity.extended", "actor": "al", "confidence": "explicit", "schema_version": "0.3.0", "entity_type": "plan", "entity_id": "T3-foo", "attributes": {"summary": "Resolved open question 2 (chose X over Y) while implementing."}}
{"event_id": "<uuid4>", "type": "verification.tested", "actor": "al", "confidence": "explicit", "schema_version": "0.3.0", "entity_type": "plan", "entity_id": "T3-foo", "attributes": {"test_type": "smoke", "command": "bash scripts/run-checks.sh", "result": "pass", "summary": "All checks green after the change."}}
{"event_id": "<uuid4>", "type": "entity.completed", "actor": "al", "confidence": "explicit", "schema_version": "0.3.0", "entity_type": "plan", "entity_id": "T3-foo", "attributes": {"summary": "T3-foo delivered: X implemented, checks green."}}
{"event_id": "<uuid4>", "type": "commit.recorded", "actor": "al", "confidence": "explicit", "schema_version": "0.3.0", "attributes": {"author": "al", "date": "2026-06-09", "message_first_line": "feat(T3-foo): implement X; checks green"}}
```

Then: repack-validate green → write `.last-capture` → `git commit`.
