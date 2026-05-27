# Project state — generated 2026-05-27T18:19:47Z

**Total events:** 128  ·  **Live:** 23  ·  **Dormant:** 0  ·  **Dead:** 10  ·  **Orphaned:** 0

## Live work

### By thematic parent

- **(T1 itself)**
  - `T1-top-level` (29 events): entity.extended → entity.extended → entity.extended

- **(T2 itself)**
  - `T2-analyser` (5 events): entity.extended → entity.progressed → entity.progressed
  - `T2-extraction` (2 events): entity.created → relationship.spawns
  - `T2-ingest` (2 events): entity.created → relationship.spawns
  - `T2-ontology` (4 events): relationship.spawns → entity.extended → entity.progressed
  - `T2-packaging` (6 events): entity.progressed → entity.extended → entity.progressed
  - `T2-projection` (8 events): entity.progressed → entity.progressed → entity.progressed
  - `T2-storage` (6 events): entity.progressed → entity.progressed → entity.progressed

- **(milestone)**
  - `M1-bootstrap` (4 events): relationship.spawns → entity.progressed → entity.progressed
  - `M6-analyser` (3 events): entity.created → relationship.spawns → entity.progressed

- **(non-plan: inbox-item)**
  - `2026-05-23.autopilot-misuse-meta-observation` (1 events): entity.created
  - `2026-05-23.cheatsheet-initial-content` (1 events): entity.created
  - `2026-05-23.cowork-vs-code-altitude-guidance` (1 events): entity.created
  - `2026-05-23.extraction-prompt-template-skeleton` (1 events): entity.created
  - `2026-05-23.html-view-visual-style` (1 events): entity.created
  - `2026-05-23.mapping-note-agent-design` (1 events): entity.created
  - `2026-05-23.plugin-naming-alternatives` (1 events): entity.created
  - `2026-05-23.side-quest-formalisation` (1 events): entity.created
  - `2026-05-23.snapshot-trigger-config` (1 events): entity.created
  - `2026-05-23.verification-overhaul-candidate-model` (1 events): entity.created
  - `2026-05-27.agents-emit-entity-created-for-plans` (1 events): entity.created

- **T2-analyser**
  - `T3-analyser-phase-b-persistence` (4 events): relationship.spawns → relationship.spawns → entity.progressed

- **T2-storage**
  - `T3-cache-build` (3 events): entity.completed → verification.tested → entity.progressed

### By milestone

- **(self: M1-bootstrap)**
  - `M1-bootstrap`

- **(self: M6-analyser)**
  - `M6-analyser`

- **M1-bootstrap**
  - `T3-cache-build`

- **M6-analyser**
  - `T3-analyser-phase-b-persistence`

## Blocked

_No open blockers._

## Orphaned

_No orphaned entities._

## Recently closed (current dead state)

- `2026-05-27.outstanding-work-analyser-endpoint` (inbox-item)
- `T3-analyser-phase-a-ephemeral` (plan)
- `T3-build-loop` (plan)
- `T3-events-schema-json` (plan)
- `T3-html-view` (plan)
- `T3-markdown-summary` (plan)
- `T3-plan-frontmatter-schema` (plan)
- `T3-plugin-scaffold` (plan)
- `T3-projection-emitter` (plan)
- `T3-projection-queries-v0` (plan)

## Notable patterns

_No flapping closures._

## Milestone progress

- **M1-bootstrap**: 8/9 T3 complete (88%); 1 live
- **M6-analyser**: 1/2 T3 complete (50%); 1 live

---
_33 entities · 31 relationships · 1 decisions._