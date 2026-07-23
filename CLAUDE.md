# agent-plan-visualiser

Event-sourced planning methodology — packaged as a reusable Claude Code plugin. The plugin walks a project's git history, extracts structured events against a defined ontology, and provides projections (audits, diagrams, status reports) over the resulting event log.

(Renamed from **agent-plan-tracker** to **agent-plan-visualiser (APV)**, 2026-06-10, M4. The event log, closed plans and git history keep the old name as true record — append-only law. The dogfood data dir remains `.agent-plan-tracker/`, pinned via `.apv-config.toml` `[storage] data_dir`.)

(Plugin package identity set 2026-07-23: the installable plugin is **`exfu-agent-plan-visualiser`** — label *ExFu Agent Plan Visualiser* — distributed via the **exfu** marketplace (`/plugin install exfu-agent-plan-visualiser@exfu`), repo `https://github.com/ExFu/agent-plan-visualiser`. Only the plugin `name` gained the `exfu-` prefix; the folder `agent-plan-visualiser/`, the methodology name APV, the data dir, and the `apv-*` commands/config are unchanged, so plugin `name` ≠ folder by design. Historical `planning/` docs keep the pre-prefix install strings as append-only record.)

The premise: git commit history is the only artefact in a planning-driven project that cannot lie about what happened. Plans, decision logs, and status reports are all secondary — useful as inputs, never authoritative on their own. By event-sourcing from commits directly, every projection (current state, completion audits, smell detection) derives from a single source of truth.

The plugin is project-agnostic. Any planning-driven project that uses git + writes plans can adopt it.

**This file is time-independent by rule** (operator ruling 2026-07-21): static truths, conventions, instructions, and pointers to where stateful information lives — never transient planning state. If a statement here can become false as work advances, it doesn't belong here.

## Session-start orientation

Read `planning/T1-top-level.md` first — the design source of truth: the validated design plus the open design questions queued.

Current project state is never recorded in this file. Read it from the event-log projections:

- `.agent-plan-tracker/summary.md` — human digest: live work, awaiting-operator queues, draft/blocked/orphaned lists, milestone progress.
- `.agent-plan-tracker/projection.json` — machine-readable state, and the browser view over it: `agent-plan-visualiser/bin/apv serve`.
- Regenerate all derived views from the log with `agent-plan-visualiser/bin/apv` (cache → projection → summary).
- Milestone history lives in the event log and `planning/M*.md`.

## Standing discipline

Static operational law; mechanics live in the named skills and scripts.

- **Capture before commit.** After each logical unit of work and before committing, follow `/apv-capture` (`agent-plan-visualiser/skills/apv-capture/SKILL.md`) to append a sealed event block ending in a `commit.recorded` seal that matches the commit's first line. The capture-guard pre-commit hook rejects commits whose staged files are newer than the data dir's `.last-capture`; `git commit --no-verify` is the sanctioned escape hatch for capture-free trivia.
- **Draft gate.** No implementation work may be recorded against `draft` entities; acceptance (`entity.accepted`) is operator-only, never self-issued.
- **Main is gated.** `agent-plan-visualiser/scripts/gate-check.sh` — the integrity composite plus the seal↔commit correspondence check, policy lists in the committed `.apv-config.toml` — fires through three adapters: `/apv-merge` (primary, skill-procedural — `agent-plan-visualiser/skills/apv-merge/SKILL.md`), pre-push, and the reference-transaction local gate (`APV_SKIP_GATE=1` is its hatch).
- **Data dir resolution.** `APV_DATA_DIR` env var → `.apv-config.toml [storage] data_dir` → default `.apv/`. This repo pins `.agent-plan-tracker/`.

## Conventions

This project uses the planning methodology it captures (dogfooding).

- **`planning/`** holds plans. **Filename is load-bearing: must match the plan's `entity_id` (declared in YAML frontmatter), minus the `.md` extension.**
  - `T1-top-level.md` — main-spine Tier-1 intent + scope + themes + design.
  - `T2-<slug>.md` — main-spine Tier-2 thematic chunks (e.g., `T2-ontology.md`, `T2-storage.md`).
  - `T3-<slug>.md` — main-spine Tier-3 execution plans (e.g., `T3-events-jsonl-schema.md`).
  - `M<n>-<slug>.md` — milestone plans on the orthogonal sequence axis (e.g., `M1-bootstrap.md`); `M<n>.<m>-<slug>.md` — sub-milestones.
  - `XT<n>-<slug>.md` — crosscut workstream plans (X prefix).
  - `<L>T<n>-<slug>.md` — side-quest workstream plans (any capital letter L other than X — e.g., `PT2-client-editor.md`).
- **`.agent-plan-tracker/`** holds the event log (`events.jsonl`), cache, projection, snapshots — the tracking spine for this project itself (we dogfood). Pre-rename name kept deliberately, pinned via `.apv-config.toml`; fresh installs use `.apv/`.
- **`agent-plan-visualiser/`** is the packaged plugin: `skills/`, `commands/`, `hooks/`, `scripts/`, `bin/`, `schemas/`, `view/`, `cheatsheet/`, `philosophies/`, `tests/`. It installs as the plugin **`exfu-agent-plan-visualiser`** from the `exfu` marketplace; the folder name is kept as the dev/dogfood home (plugin `name` ≠ folder, by design).
- **No `product/`** until there's actual product code. Design + bootstrap first; implementation follows.
