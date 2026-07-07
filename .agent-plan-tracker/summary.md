# Project state — generated 2026-07-07T13:56:12Z

**Total events:** 480  ·  **Draft:** 13  ·  **Live:** 10  ·  **Dormant:** 0  ·  **Closed:** 52  ·  **Orphaned:** 0

## Live work

### By thematic parent

- **(T1 itself)**
  - `T1-top-level` (36 events): entity.accepted → entity.extended → entity.extended

- **(T2 itself)**
  - `T2-analyser` (9 events): entity.progressed → entity.progressed → entity.progressed
  - `T2-extraction` (7 events): entity.accepted → entity.progressed → entity.extended
  - `T2-ontology` (9 events): entity.extended → entity.extended → entity.extended
  - `T2-packaging` (7 events): entity.extended → entity.progressed → entity.extended
  - `T2-projection` (14 events): analysis.invalidated → entity.progressed → entity.extended
  - `T2-storage` (7 events): entity.progressed → entity.progressed → entity.progressed

- **(milestone)**
  - `M4-fresh-install` (7 events): entity.extended → entity.progressed → entity.progressed
  - `M5-backfill` (10 events): entity.progressed → verification.tested → verification.deferred

- **T2-packaging**
  - `T3-distribution` (12 events): entity.progressed → verification.tested → verification.deferred

### By milestone

- **(self: M4-fresh-install)**
  - `M4-fresh-install`

- **(self: M5-backfill)**
  - `M5-backfill`

- **M4-fresh-install**
  - `T3-distribution`

## Awaiting operator

**Acceptance ceremonies pending** (draft plans — the draft gate blocks implementation against them):
- `T2-ingest` (authored 2026-05-23, 73 commit(s) ago)

**Closure ceremonies pending** (all scheduled T3s closed; milestone still live):
- `M5-backfill`

**Deferred verifications** (operator legs to come back to):
- `T3-distribution` (deferred 2026-07-07): exfu.ai upload/placement walkthrough, Cowork verification, and the first real plugin-loader install all need the operator's environments — deferred pending an operator session. (The earlier verification.skipped records stand as written; this event carries the come-back intent forward.)
- `M5-backfill` (deferred 2026-07-07): The exfu rehearsal (~/Studio/projects/exfu_website-backfill-rehearsal/run-rehearsal.sh) must be operator-run from a normal terminal — claude -p cannot authenticate from inside a Claude Code session (M5 s9 amendment 3). M5's remaining definition-of-done proof rides on it.

## Draft

- **inbox-item**
  - `2026-05-23.autopilot-misuse-meta-observation` (45d untriaged)
  - `2026-05-23.cheatsheet-initial-content` (45d untriaged)
  - `2026-05-23.cowork-vs-code-altitude-guidance` (45d untriaged)
  - `2026-05-23.extraction-prompt-template-skeleton` (45d untriaged)
  - `2026-05-23.html-view-visual-style` (45d untriaged)
  - `2026-05-23.mapping-note-agent-design` (45d untriaged)
  - `2026-05-23.plugin-naming-alternatives` (45d untriaged)
  - `2026-05-23.side-quest-formalisation` (45d untriaged)
  - `2026-05-23.snapshot-trigger-config` (45d untriaged)
  - `2026-05-23.verification-overhaul-candidate-model` (45d untriaged)
  - `2026-06-10.view-hardcodes-dogfood-data-dir` (27d untriaged)
  - `2026-07-07.backfill-sandbox-triage-check-fails`
- **plan**
  - `T2-ingest`

## Blocked

_No open blockers._

## Orphaned

_No orphaned entities._

## Recently closed

- `2026-05-27.agents-emit-entity-created-for-plans` (inbox-item)
- `2026-05-27.outstanding-work-analyser-endpoint` (inbox-item)
- `2026-05-30.progressed-after-completed-state-flip` (inbox-item)
- `2026-06-09.commit-recorded-entity-subject-drift` (inbox-item)
- `2026-07-03.ceremony-prompting-gap` (inbox-item)
- `M1-bootstrap` (plan)
- `M1.1-analyser` (plan)
- `M1.2-relationship-ssot` (plan)
- `M2-auto-extract` (plan)
- `M3-clean-gate` (plan)

## Notable patterns

_No flapping closures._

## Milestone progress

- **M1-bootstrap**: 15/15 T3 complete (100%); 0 live
- **M1.1-analyser**: 6/6 T3 complete (100%); 0 live
- **M1.2-relationship-ssot**: 1/1 T3 complete (100%); 0 live
- **M2-auto-extract**: 5/5 T3 complete (100%); 0 live
- **M3-clean-gate**: 3/3 T3 complete (100%); 0 live
- **M4-fresh-install**: 4/5 T3 complete (80%); 1 live
- **M5-backfill**: 5/5 T3 complete (100%); 0 live
- **M5.1-operator-attention**: 2/2 T3 complete (100%); 0 live

---
_75 entities · 103 relationships · 25 decisions._