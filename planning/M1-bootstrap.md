---
id: M1-bootstrap
plan_kind: milestone
milestone_index: 1
status: planned
---

# M1-bootstrap — Hand-rollable end-to-end

**Status**: Planned. Not yet started.
**Sits at**: First milestone in the sequence axis. Touches themes T2-ontology, T2-storage, T2-projection, T2-packaging.

---

## 1. Why this milestone

M1 proves the model. After M1, the agent-plan-tracker has a complete end-to-end pipeline working **against this project itself**, hand-rolled (no automated extraction yet) — events captured manually, cache buildable, projections renderable, HTML view openable.

This milestone exists for one reason: **demonstrate that the methodology + storage + projection design holds water before investing in automation.** If the end-to-end works hand-rolled, M2's automated extractor has a clear target. If it doesn't, surface the friction now while changes are still cheap.

It also delivers immediate value to the project itself — we're already in dogfooding mode (T1 §3.11), and M1 makes that dogfooding navigable rather than just an events.jsonl in a directory.

## 2. What M1 unlocks

After M1:

- The plugin's directory scaffold exists and is repackable. Everything below lands inside it.
- The event ontology v0.1 is formally specified (`schemas/events.schema.json`) and the T1 §4 prose references it.
- `events.jsonl` continues to grow by hand, conforming to the schema.
- A cache builder script reads events.jsonl → SQLite, validating against schema en route.
- A projection emitter produces `projection.json` from the cache.
- A markdown summary script reads projection.json → human-readable state report.
- An HTML view (vanilla JS) renders projection.json into entity-state-board + plan-hierarchy-tree views.

**End-of-M1 acceptance test**: from a clean checkout, run the build script and open the view. The cache rebuilds, projection emits, HTML renders the current state of this project (including this milestone's own progression) faithfully.

## 3. What M1 explicitly does NOT include

- **Automated extraction.** Events continue to be hand-rolled by Claude in interactive sessions. The pre-commit hook doesn't exist yet — that's M2.
- **Cleanliness gate / pre-merge-to-main hook.** That's M3.
- **Install into a different project.** Plugin only runs against this repo. That's M4.
- **Backfill of an existing project's history.** That's M5.
- **Snapshots.** Not needed yet — the event log is small enough to scan in full. Snapshots become valuable when the log gets long; add in M2 or M3.

Keeping these out keeps M1 small enough to land in 1–2 working sessions and prove the model.

## 4. How M1 delivers — T3 work across four themes

### From T2-ontology
- `T3-events-schema-json` — write `schemas/events.schema.json` defining all 23 event types, attribute requirements, shared fields.
- `T3-plan-frontmatter-schema` — write `schemas/plan-frontmatter.schema.json` for plan YAML frontmatter validation.

### From T2-storage
- `T3-cache-sqlite-schema` — define SQLite tables (`events`, `entities`, `relationships`, `decisions`) and the build-from-jsonl script.
- `T3-projection-json-shape` — define the projection.json structure (current entity state, event-type sequences per entity, decision arc metadata, milestone rollups).
- `T3-git-blame-commit-ref` — git-blame-based commit_ref resolution within the cache build.

### From T2-projection
- `T3-projection-emitter` — SQL → JSON script that reads SQLite cache and emits `projection.json`.
- `T3-markdown-summary` — projection.json → `summary.md` highlighting open work, blocked items, recently-closed, notable sequence patterns.
- `T3-html-view-template` — `view/index.html` + `view/app.js` + `view/style.css` rendering entity-state-board + plan-hierarchy-tree views.
- `T3-projection-queries-v0` — initial SQL catalogue in `bin/`.

### From T2-packaging
- `T3-plugin-scaffold` — create the plugin directory structure (`skills/`, `bin/`, `view/`, `philosophies/`, `hooks/`, `schemas/`, `commands/`) plus any required manifest.
- `T3-build-loop` — repack-and-validate cycle to catch plugin format bugs continuously.

That's ~10 T3 tasks. Each gets its own `T3-<slug>.md` plan when work begins on it (per the methodology — T3 plans are authored just before agents pick up the work).

## 5. Definition of done

M1 is complete when:

- `schemas/events.schema.json` validates every event in `.agent-plan-tracker/events.jsonl` (including bootstrap events under schema 0.0.0-prehistoric, after retro-migration to the first stable schema version).
- `schemas/plan-frontmatter.schema.json` validates every plan file's frontmatter in `planning/`.
- A build script produces `.agent-plan-tracker/cache.sqlite` from events.jsonl, with no validation errors and commit_ref populated via blame.
- A projection script produces `.agent-plan-tracker/projection.json` from the cache.
- A summary script produces a readable `summary.md` from projection.json.
- Opening `view/index.html` in a browser renders the current project state — entity-state-board shows all plans grouped by derived state; plan-hierarchy-tree shows T1 / lettered roots / milestones / T2-T3 nesting.
- All the above are inside the plugin scaffold (`agent-plan-tracker/<…>` at the repo root, or wherever we settle).

## 6. Dependencies

No prior-milestone dependencies (M1 is first).

T3-internal dependency order:
1. `T3-plugin-scaffold` lands first — everything else needs somewhere to live.
2. `T3-events-schema-json` + `T3-plan-frontmatter-schema` next — define the validation contract.
3. `T3-cache-sqlite-schema` + `T3-git-blame-commit-ref` — depends on schemas existing for validation during build.
4. `T3-projection-json-shape` — depends on cache schema.
5. `T3-projection-emitter` + `T3-markdown-summary` + `T3-html-view-template` + `T3-projection-queries-v0` — parallelisable, depend on projection shape.
6. `T3-build-loop` — last, validates the whole chain.

## 7. Open questions (M1-specific)

1. **Plugin naming.** `agent-plan-tracker` is the working name; locked enough for M1 scaffolding. Final name decision can stay in M4.
2. **Script invocation language.** Pure bash, node, or python for the build/projection scripts? Bash sufficient for M1 (hand-rolled, dev-only); node likely needed by M4 packaging. Resolve in `T3-build-loop`.
3. **HTML view: single file or split?** Lean single HTML file with view-toggle JS; details in `T3-html-view-template`.
4. **First stable schema version.** Bootstrap events are `0.0.0-prehistoric`. When does M1 land its first stable version — `0.1.0`? Probably once `events.schema.json` is drafted and prehistoric events are migrated to conform.
5. **JSON Schema draft version.** draft-07 (broadly supported, conservative) vs 2020-12 (modern features). Lean draft-07 unless a feature is genuinely needed.

## 8. After M1

M2 picks up automated extraction: the pre-commit hook fires an extraction agent that produces events the same shape as M1's hand-rolled ones. Schema and projection layer don't change — only the producer.

M3 adds the cleanliness gate at merge-to-main (using projections M1 already produces).

M4 packages for distribution and onboarding to fresh projects.

M5 backfills existing projects with retrospective mapping.
