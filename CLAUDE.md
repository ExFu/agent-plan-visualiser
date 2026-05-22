# agent-plan-tracker

Event-sourced planning methodology — packaged as a reusable Claude Code plugin. The plugin walks a project's git history, extracts structured events against a defined ontology, and provides projections (audits, diagrams, status reports) over the resulting event log.

The premise: git commit history is the only artefact in a planning-driven project that cannot lie about what happened. Plans, decision logs, and status reports are all secondary — useful as inputs, never authoritative on their own. By event-sourcing from commits directly, every projection (current state, completion audits, smell detection) derives from a single source of truth.

The plugin is project-agnostic. Any planning-driven project that uses git + writes plans can adopt it.

## Session-start orientation

Read `planning/T1-top-level.md` first. It captures the validated design so far, plus the open design questions queued.

We are in **design + M1 bootstrap phase**. The T1 plan is still in active authoring; M1 (the first milestone — hand-rollable end-to-end against this project) is queued. Don't start coding the automated extraction pipeline until the ontology + extraction-prompt template + storage format are all settled and the remaining open questions in §5 are closed (most are slated for resolution during M1 dogfooding).

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
