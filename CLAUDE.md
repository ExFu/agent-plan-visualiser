# agent-plan-tracker

Event-sourced planning methodology — packaged as a reusable Claude Code plugin. The plugin walks a project's git history, extracts structured events against a defined ontology, and provides projections (audits, diagrams, status reports) over the resulting event log.

The premise: git commit history is the only artefact in a planning-driven project that cannot lie about what happened. Plans, decision logs, and status reports are all secondary — useful as inputs, never authoritative on their own. By event-sourcing from commits directly, every projection (current state, completion audits, smell detection) derives from a single source of truth.

The plugin is project-agnostic. Any planning-driven project that uses git + writes plans can adopt it.

## Session-start orientation

Read `planning/T1-top-level.md` first. It captures the validated design so far, plus the open design questions queued.

**M1 is complete.** The hand-rolled end-to-end pipeline works and is dogfooded against this project: JSON-Schema validation, `cache-build.py` (events.jsonl → SQLite), `projection-emit.py`, `summary-emit.py`, the vanilla-JS HTML flow view, and the SQL audit catalogue all run green via `repack-validate.sh`. Two sub/sequence milestones also shipped on top of M1: **M6-analyser** (browser-direct "what's outstanding?" analyser, all five phases A–E — this drove the ontology's first evolution to schema `0.2.0` with the `analysis.*` events) and **M1.2-relationship-ssot** (milestone/theme membership is now event-sourced — `relationship.reattached` is the move primitive, frontmatter is only a creation-time seed).

**M2 is complete** (2026-06-09): event capture is now skill-driven. After each logical unit of work and **before committing**, the in-session agent follows `agent-plan-tracker/skills/apt-capture/SKILL.md` (`/apt-capture`) to append a sealed event block — schema `0.3.0`, draft gate (no `entity.progressed`/`entity.completed` against draft entities; acceptance is operator-only), `commit.recorded` seal matching the commit's first line. The **capture-guard pre-commit hook is installed and live** (`agent-plan-tracker/hooks/capture-guard.sh`, installer `agent-plan-tracker/scripts/install-hook.sh`): commits with staged files newer than `.agent-plan-tracker/.last-capture` are rejected; `git commit --no-verify` is the sanctioned escape hatch for capture-free trivia. The data dir is configurable via `APT_DATA_DIR`.

**M3 is complete** (2026-06-10): main is gated. `agent-plan-tracker/scripts/gate-check.sh` is the single boundary contract — the integrity composite (`gate-composite.py`: blocking = corruption of the record; warn = dashboard signal, merges freely) plus the seal↔commit correspondence check, policy lists in the committed `.apt-config.toml`. It fires through **three adapters**: `/apt-merge` skill-procedural (primary — `agent-plan-tracker/skills/apt-merge/SKILL.md`: branch-side reconciliation, main's log is the prefix, contradictions go to the operator, rulings become reconciliation events sealed by the merge commit), **pre-push** (gates pushes of main), and the **reference-transaction local gate** (operator ruling 2026-06-10: gates every local move of main including fast-forward merges; `APT_SKIP_GATE=1` is its hatch). All three hooks are installed live in this repo alongside the capture-guard. M3's acceptance test was self-referential: the branch delivering it landed on main via the skill, gate green. Blocking checks are epoch-gated (0.3.0 discipline judged from 0.3.0 onward) and append-only-repairable (a later `entity.reopened` heals an earlier resurrection violation).

The T1 plan remains in active authoring as the design source of truth. The next unbuilt frontier is **M4 (fresh-install packaging, where the deferred autonomous `claude -p` extractor for non-Claude-Code committers and the CI gate adapter template land)**; M5 (backfill) follows.

## Conventions

This project uses the planning methodology it captures (dogfooding).

- **`planning/`** holds plans. **Filename is load-bearing: must match the plan's `entity_id` (declared in YAML frontmatter), minus the `.md` extension.**
  - `T1-top-level.md` — main-spine Tier-1 intent + scope + themes + design.
  - `T2-<slug>.md` — main-spine Tier-2 thematic chunks (e.g., `T2-ontology.md`, `T2-storage.md`).
  - `T3-<slug>.md` — main-spine Tier-3 execution plans (e.g., `T3-events-jsonl-schema.md`).
  - `M<n>-<slug>.md` — milestone plans on the orthogonal sequence axis (e.g., `M1-bootstrap.md`, `M2-auto-extract.md`).
  - `XT<n>-<slug>.md` — crosscut workstream plans (X prefix).
  - `<L>T<n>-<slug>.md` — side-quest workstream plans (any capital letter L other than X — e.g., `PT2-client-editor.md`).
- **`.agent-plan-tracker/`** holds the event log (`events.jsonl`), cache, projection, snapshots — the tracking spine for this project itself (we dogfood).
- **`skills/`**, **`cheatsheet/`**, **`bin/`**, **`philosophies/`**, **`hooks/`**, **`view/`**, **`commands/`** (later) — packaged plugin content as the design crystallises into implementation.
- **No `product/`** until there's actual product code. Design + bootstrap first; implementation follows.
