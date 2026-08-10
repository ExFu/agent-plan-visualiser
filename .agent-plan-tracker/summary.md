# Project state — generated 2026-08-10T17:16:12Z

**Total events:** 736  ·  **Draft:** 20  ·  **Live:** 12  ·  **Dormant:** 0  ·  **Closed:** 65  ·  **Orphaned:** 0

## Live work

### By thematic parent

- **(T1 itself)**
  - `T1-top-level` (36 events): entity.accepted → entity.extended → entity.extended

- **(T2 itself)**
  - `T2-analyser` (9 events): entity.progressed → entity.progressed → entity.progressed
  - `T2-extraction` (8 events): entity.progressed → entity.extended → entity.progressed
  - `T2-ontology` (9 events): entity.extended → entity.extended → entity.extended
  - `T2-packaging` (7 events): entity.extended → entity.progressed → entity.extended
  - `T2-projection` (18 events): verification.tested → entity.progressed → verification.tested
  - `T2-storage` (9 events): entity.progressed → entity.progressed → verification.tested

- **(milestone)**
  - `M4-fresh-install` (8 events): entity.progressed → entity.progressed → verification.tested
  - `M5-backfill` (16 events): verification.tested → entity.progressed → verification.tested

- **T2-ontology**
  - `T3-retrospective-project-annotation` (6 events): entity.accepted → entity.progressed → verification.tested

- **T2-packaging**
  - `T3-distribution` (65 events): entity.progressed → verification.tested → verification.deferred

- **T2-storage**
  - `T3-multi-project` (6 events): entity.progressed → verification.tested → entity.extended

### By milestone

- **(self: M4-fresh-install)**
  - `M4-fresh-install`

- **(self: M5-backfill)**
  - `M5-backfill`

- **M4-fresh-install**
  - `T3-distribution`
  - `T3-retrospective-project-annotation`

## Awaiting operator

**Acceptance ceremonies pending** (draft plans — the draft gate blocks implementation against them):
- `KT0-knowledge-substrate` (authored 2026-07-21, 35 commit(s) ago)
- `T2-ingest` (authored 2026-05-23, 142 commit(s) ago)

**Closure ceremonies pending** (all scheduled T3s closed; milestone still live):
- `M5-backfill`

**Deferred verifications** (operator legs to come back to):
- `T3-claude-md-block-healing` (deferred 2026-08-10): The other two attached repos are separate repositories; healing their working trees is not this branch's to commit.
- `T3-distribution` (deferred 2026-08-10): The actual Cowork check is still out of this session's hands: both repos must be pushed and the exfu marketplace removed/re-added (or refreshed) in Cowork. Expected signal: fetchAccountScopedRemotePlugins reports 14 plugins from 3 marketplace(s), up from 13, and exfu-agent-plan-visualiser appears in the plugin list. If it still says 13 the path shape was not the cause either; next probe is a one-entry marketplace over this repo, whose all-fail sync surfaces the backend's per-plugin error verbatim.

## Draft

- **inbox-item**
  - `2026-05-23.autopilot-misuse-meta-observation` (79d untriaged)
  - `2026-05-23.cheatsheet-initial-content` (79d untriaged)
  - `2026-05-23.cowork-vs-code-altitude-guidance` (79d untriaged)
  - `2026-05-23.extraction-prompt-template-skeleton` (79d untriaged)
  - `2026-05-23.html-view-visual-style` (79d untriaged)
  - `2026-05-23.mapping-note-agent-design` (79d untriaged)
  - `2026-05-23.plugin-naming-alternatives` (79d untriaged)
  - `2026-05-23.side-quest-formalisation` (79d untriaged)
  - `2026-05-23.snapshot-trigger-config` (79d untriaged)
  - `2026-05-23.verification-overhaul-candidate-model` (79d untriaged)
  - `2026-06-10.view-hardcodes-dogfood-data-dir` (61d untriaged)
  - `2026-07-07.dist-sandbox-test-reference-stale` (34d untriaged)
  - `2026-07-21.methodology-name-pending` (20d untriaged)
  - `2026-07-23.exfu-plugin-project-scoped-elsewhere` (18d untriaged)
  - `2026-07-23.stale-hooks-after-plugin-upgrade` (18d untriaged)
  - `2026-08-10.exfu-marketplace-rename-residuals`
  - `2026-08-10.legacy-command-files-shadowed-by-skills`
  - `2026-08-10.session-orient-block-drift-nag`
- **plan**
  - `KT0-knowledge-substrate`
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
- `2026-07-07.backfill-sandbox-triage-check-fails` (inbox-item)
- `M1-bootstrap` (plan)
- `M1.1-analyser` (plan)
- `M1.2-relationship-ssot` (plan)
- `M2-auto-extract` (plan)

## Notable patterns

_No flapping closures._

## Milestone progress

- **M1-bootstrap**: 15/15 T3 complete (100%); 0 live
- **M1.1-analyser**: 6/6 T3 complete (100%); 0 live
- **M1.2-relationship-ssot**: 1/1 T3 complete (100%); 0 live
- **M2-auto-extract**: 5/5 T3 complete (100%); 0 live
- **M3-clean-gate**: 3/3 T3 complete (100%); 0 live
- **M4-fresh-install**: 8/10 T3 complete (80%); 2 live
- **M5-backfill**: 5/5 T3 complete (100%); 0 live
- **M5.1-operator-attention**: 2/2 T3 complete (100%); 0 live
- **M6-dashboard**: 3/3 T3 complete (100%); 0 live
- **M6-exfu-integration**: 1/1 T3 complete (100%); 0 live

---
_97 entities · 127 relationships · 44 decisions._