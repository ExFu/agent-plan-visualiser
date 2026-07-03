---
id: T2-ingest
plan_kind: thematic
tier: 2
status: draft
---

# T2-ingest — Backfill + retrospective mapping for existing projects

**Status**: Draft. T3s scheduled for M5.
**Theme**: One-shot import of existing project history into the event log, including the translation layer (retrospective mapping note) for projects that don't natively follow this methodology. **This T2 is the architectural source of truth for ingest**; T1 only summarises.

---

## 1. Why this T2 exists

For a project starting fresh with the plugin installed at commit 0, T2-extraction's pre-commit hook handles everything going forward. Easy case.

The harder case: an *existing* project with months or years of history, no event log, possibly no formal planning methodology at all. The plugin's value depends on being able to ingest such projects retroactively.

Two distinct sub-problems:

1. **Backfill of commits.** Walk git history from first commit to HEAD, extracting events per commit using the standard extractor (T2-extraction §3.9 primitive).
2. **Retrospective mapping.** If the project's planning artefacts don't match this methodology's vocabulary, produce a translation note that briefs the per-commit extractor on how to interpret the project's own conventions.

The mapping note is the load-bearing artefact. Without it, the extractor would misclassify project artefacts or refuse to extract confidently.

## 2. What lives in this theme

- **Backfill workflow** — sequential per-commit extraction over historical commits, opt-in and human-gated.
- **Retrospective mapping note format** — YAML/markdown artefact documenting the project's existing conventions and their mapping to this methodology.
- **Mapping-note generation** — agent-assisted authoring (agent inspects planning artefacts, proposes mappings, human reviews).
- **Resumability** — backfill of long histories needs to be pausable + resumable.
- **Ambiguity escalation during backfill** — same halt protocol as live extraction; surface + park, don't block subsequent commits.
- **Post-backfill cleanup** — mapping note is archived (not actively maintained) after backfill completes; extracted events become canonical.

## 3. Architecture

### 3.1 Ingest as a one-shot workflow

Backfill is **opt-in**. Surfaced as:

> "This repo has N commits with no extracted events. Recommend backfilling all N (~X min, ~Y API calls). Approve?"

Default without explicit approval: pre-commit hook only runs forward from install. Old history stays uncovered. Audits flag this; user opts to backfill at convenience.

### 3.2 Retrospective mapping note

For non-native projects, the per-commit extractor needs translation. The mapping note (`.agent-plan-tracker/retrospective-mapping.md`) covers:

- **Plan-equivalent artefacts** — does the project have something resembling T1/T2/T3? Where do they live? File naming convention? Map to thematic plans.
- **Decision-equivalent artefacts** — `decisions.md`, `ADRs/`, `RFCs/`, inline-in-commits, etc.
- **Blocker conventions** — `BLOCKERS.md`, GitHub issues with labels, etc.
- **HITL questions** — TODOs, `QUESTIONS.md`, `# HITL:` comments, etc.
- **Implicit work expected** — projects without strict planning convention will have many plan-less commits; expect lots of `implicit-work`.
- **Schema-version applied** — usually the current stable.
- **Known pivots** — when did the project switch from X to Y? Helps the extractor annotate fulcrum events.

Hand-authored by a user with project knowledge, with agent assistance available.

### 3.3 Mapping note structure (proposed)

```yaml
---
project_name: <slug>
backfill_started_at: <iso-datetime>
target_schema_version: 0.1.0
---

# Retrospective mapping for <project>

## Plan-equivalent artefacts

- Path: `docs/architecture/`
- Convention: file per major area, no tier discipline
- Mapping: each file → `T2` (synthesise a T1 from README + project goals)

## Decision artefacts

- Path: `docs/decisions/`
- Format: ADR-style numbered .md
- Mapping: each ADR → `decision` event, attached to relevant plan(s) inferred from cross-references

## Blocker artefacts

- Convention: GitHub issues with `blocker` label
- Mapping: label addition → `blocker.raised`; removal → `blocker.closed`; progress comments → `blocker.progressed`

## HITL questions

- Convention: `# HITL:` comments in code
- Mapping: each unique comment → `hitl-question` at first appearance; resolution by removal

## Implicit-work expectation

- High volume — many commits with no planning artefact change.

## Known pivots (for fulcrum annotation)

- Commit a1b2c3d (2024-03-15): MongoDB → Postgres. Treat as `entity.superseded` on `data-layer` plan with paired decision (rationale in commit message).
```

### 3.4 Backfill execution flow

1. **Pre-flight.** Confirm `.agent-plan-tracker/` is empty (or only bootstrap events). Confirm mapping note exists (or warn it's optional for native-methodology projects).
2. **Synthesise T1** if missing. For projects with no T1-equivalent, agent generates a minimal T1 from README + project metadata + first commits. User reviews + commits before backfill proceeds.
3. **Walk commits from earliest to HEAD.** Per commit:
   a. Run standard per-commit extractor (T2-extraction §3.1) with mapping note in its brief.
   b. On ambiguity halt: park the backfill at that commit. Surface to user. Resume after resolution.
   c. On success: append events + commit.recorded. Move to next commit.
4. **Post-backfill verification.** Full cache rebuild + projection. Sanity-check for orphans, dangling references, schema failures.
5. **Archive mapping note.** Move to `.agent-plan-tracker/archive/retrospective-mapping-<date>.md`. No longer actively maintained.

### 3.5 Resumability

State file `.agent-plan-tracker/backfill-state.json` tracks last-processed commit_ref. Restart picks up where left off. Mid-process ambiguity-halt produces needs-review + saves state; user resolves; resume.

### 3.6 Native vs non-native vs greenfield

- **Greenfield** (project starts with plugin installed): no backfill needed. Pre-commit handles from commit 1.
- **Native** (project uses this methodology from start but plugin installed late): straightforward. Mapping note may not be needed.
- **Non-native** (project uses some other planning convention): mapping note essential. Backfill quality depends on note quality.

### 3.7 Representation: bitemporal anchoring + origin provenance (ratified 2026-07-03)

How backfilled events sit in a log that already has live blocks — the question §3.4's walk deliberately left open. The ontology mechanics are specified in [[T2-ontology]] §3.12 (schema `0.4.0`); this section is the ingest-side doctrine.

**Append at the record tail, anchor to event time.** Backfilled blocks are appended after all existing live blocks — the append-only law is never bent, and the log honestly records "in <now> we learned what happened in <then>." Each historical commit gets its own block, terminated by a seal quoting that commit's message/author/date plus `commit_ref` (the sha exists at extraction time — unlike live capture). Projections *unfurl* the segment by ordering on event time (the anchor), with record time as tiebreak; positional rollup works unchanged inside the segment. The gate's seal↔commit check passes as-is, since historical commits are reachable.

**Chunked backfill commits.** The real commits appending a segment are ordinary captured commits ("backfill: commits a1b2c3..d4e5f6, 40 blocks"), chunked to match §3.5's resumability — each chunk transits the capture guard normally.

**Everything backfilled is marked.** Every backfilled event carries `origin: "backfilled"` + `attributes.backfill_run`; absence of `origin` means contemporaneous capture (no migration of the existing log). The gate is origin-aware: discipline checks don't judge backfilled events (the methodology can't be demanded retroactively); schema validity applies in full. A bad run is auditable — and repudiable — as a cohort via its run id.

**The Why is emitted at exactly one of three strengths, never fabricated** (full spec: T2-ontology §3.12): *recovered* (rationale genuinely present in the historical record → real `decision` citing its source), *recollected* (the human who was there confirms at triage → `decision` with the operator as actor), or *inferred* (no source, no confirmation → **no decision**; candidate rationales become a `hitl-question` on the affected plan — open, non-authoritative, convertible to recollected append-only when the operator later answers). The Why-gap concentrates at fulcrums, which is precisely what the mapping note's "Known pivots" section harvests from the human up front; most historical commits are honestly `implicit-work` with What-only summaries, and that is fine — backfilled history serves navigation and memory, not steering.

**The post-walk triage pass.** The walk (§3.4 step 3) emits hypotheses inline but never stops for them (only genuine ambiguity halts). After the walk, one batch triage session presents every fulcrum-ish moment with its candidate rationales as a checklist; the operator confirms/edits/rejects in one sitting; confirmations land as recollected decisions in the triage commit's block. Same ergonomic shape as the analyser's bulk mode.

**UI co-design constraint.** `origin` + event-time ordering are the contract the historical-projection UI keys on (ghosted rendering, provenance toggle, event-time timeline). That UI design (T2-projection; includes the standing `2026-06-10.view-hardcodes-dogfood-data-dir` inbox item) must be settled alongside `T3-origin-provenance-schema` **before** M5's T3s build — the two co-constrain each other.

## 4. T3 candidates

### M5-scheduled
- `T3-backfill-workflow` — orchestration script + state file + resumability.
- `T3-why-triage-pass` — the §3.7 post-walk batch triage: hypothesis checklist presentation, recollected-decision capture, hitl-question emission for the unconfirmed.
- `T3-historical-projection-ui` — event-time unfurling + origin-aware rendering in the flow view (with [[T2-projection]]); paired with T2-ontology's `T3-origin-provenance-schema`; both precede the build of the T3s above.
- `T3-retrospective-mapping-template` — canonical YAML/markdown template + worked example.
- `T3-mapping-note-generator` — agent that surveys a repo and proposes a draft mapping note for review.
- `T3-t1-synthesis-from-readme` — for projects with no T1, agent generates minimal T1.
- `T3-backfill-against-reference-project` — apply backfill to Alastair's other project as the canonical first non-native target.

### Possibly later
- `T3-incremental-backfill` — for projects where partial backfill has happened and new gaps appear (rare; defer).

## 5. Dependencies

- Reuses T2-extraction's per-commit extractor primitive (T2-extraction §3.9).
- Depends on T2-ontology (extracted events validate against the schema).
- Depends on T2-storage (events append to events.jsonl).

## 6. Open questions

1. **Mapping-note schema rigour.** Free-form markdown vs strict YAML schema? Lean YAML for structured parts, free-form markdown for narrative context.
2. **Synthesised-T1 quality.** How confident can the agent be at generating a T1 from README + goals? Risk: synthesised T1 misses critical context. Mitigation: always human-review before backfill proceeds.
3. **Repos without git history** (squashed, rewritten). Out of scope or worth attempting? Probably out of scope for M5; revisit if it bites.
4. **Project-owner cross-checking.** For backfilling someone else's project, are mappings legitimate? Probably require owner to author the mapping note.
5. **Mono-repos.** Multiple projects in one git repo — does each get its own `.agent-plan-tracker/`? Probably yes; flag for design when actually encountered.

## 7. Out of scope

- Auto-running backfill on plugin install — always opt-in.
- Multi-repo ingest (out of scope per T1 §7).
- Mapping note maintenance after backfill — archive and forget.
- Forced re-extraction of already-extracted commits (idempotency-aware; only fills gaps).
