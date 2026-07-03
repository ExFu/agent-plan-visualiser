---
id: M5-backfill
plan_kind: milestone
milestone_index: 5
status: planned
---

# M5-backfill — history becomes record

**Status**: Planned (authored 2026-07-03 from the ratified backfill-representation design — T2-ontology §3.12 + T2-ingest §3.7; operator ruling same day).
**Sits at**: Fifth milestone on the sequence axis. Primary theme: T2-ingest (the architectural source of truth for backfill). Contract work lands in T2-ontology (schema 0.4.0) and T2-projection (historical rendering); machinery inherits T2-extraction's per-commit extractor design.

---

## 1. Why this milestone

M1–M4 built a forward-only spine: a repo attaches via `/apv-init` and is tracked *from now*. Every adopting project with real history has an invisible past — projections start at adoption day, audits can't see prior pivots, and the log's promise ("the project's reconstructable reasoning chain") only holds for the future. M5 mines existing history into the log — **honestly**: appended, anchored, marked as inferred, and never pretending to a contemporaneous Why it cannot have.

The design ground is already ratified (2026-07-03):

- **Bitemporal anchoring** — backfilled blocks append at the record tail and anchor to historical event time via per-historical-commit seals carrying `commit_ref`; projections unfurl by event time. The append-only law is never bent.
- **Origin provenance** — `origin: captured | backfilled` distinguishes contemporaneous capture from retrospective inference, permanently; gate discipline is origin-aware; runs are repudiable as cohorts.
- **Three-tier Why** — recovered (cited source) / recollected (operator-confirmed at triage) / inferred (**no decision** — open `hitl-question` with candidates). A plausible lie is worse than an honest gap.

## 2. Shape of the wave

**Wave 1 — the contract pair (co-designed, everything else waits on it):**
`T3-origin-provenance-schema` (schema 0.4.0 + origin-aware enforcement) and `T3-historical-projection-ui` (event-time unfurling + provenance rendering). These co-constrain: the UI is what the origin field is *for*; the schema is what the UI keys on. Neither builds until both are accepted.

**Wave 2 — the machinery:**
`T3-backfill-workflow` (formalise the M5-lite `scripts/backfill/` orchestrator against 0.4.0 and the §3.7 doctrine), `T3-why-triage-pass` (the post-walk batch triage), `T3-retrospective-mapping-template` (the translation brief for non-native projects).

**Wave 3 — the proof (definition of done, §4).**

## 3. What M5 explicitly does NOT include

- **Auto-running backfill** — always opt-in (T2-ingest §7 stands).
- **Mapping-note generator agent + T1-synthesis-from-README** — later candidates (T2-ingest §4); the template + hand-authoring come first.
- **Incremental backfill** of partially-covered histories — rare; defer.
- **Multi-repo ingest** — out of scope per T1 §7.

## 4. Definition of done

- `schemas/0.4.0/` lands; the existing log validates **unmigrated** (absent `origin` = captured; 0.3.0 events untouched).
- The flow view renders a mixed log: event-time ordering, backfilled events visibly distinct, hypothesis questions rendered as open questions — and works in a `.apv/` repo (the view's dogfood-data-dir hardcode dies here).
- **The self-referential test**: this repo's own pre-adoption history (commits before the log existed) is backfilled — segment appended through the guard, gate green, projections unfurl it in place.
- The triage pass is exercised for real: at least one recovered, one recollected, and one inferred-question Why land in the record with correct tiers.
- A backfill run is demonstrably repudiable: filter a cohort by `backfill_run` and show the record without it.

## 5. How M5 delivers — T3 tasks

1. **`T3-origin-provenance-schema`** [wave 1, paired with #2] — under T2-ontology.
2. **`T3-historical-projection-ui`** [wave 1, paired with #1] — under T2-projection; absorbs the `2026-06-10.view-hardcodes-dogfood-data-dir` inbox item.
3. **`T3-backfill-workflow`** [wave 2, depends #1] — under T2-ingest.
4. **`T3-why-triage-pass`** [wave 2, depends #1, #3] — under T2-ingest.
5. **`T3-retrospective-mapping-template`** [wave 2, parallel] — under T2-ingest.

## 6. Dependencies

- The ratified representation design (T2-ontology §3.12, T2-ingest §3.7) — the ground.
- M4's toolchain-home portability — backfill tooling must run from the plugin install, like everything else.
- `T3-autonomous-extractor` (M4, still draft) — shares the `claude -p` extraction machinery with #3; see §7 Q3.

## 7. Open questions (for the acceptance ceremony)

1. **Self-referential native test** — confirm the dogfood repo's own pre-adoption history as the wave's first backfill target (lean: yes — M3 and M4 both proved themselves on themselves).
2. **Non-native reference project** — which real project is the canonical first non-native target (T2-ingest §4 suggested one of the operator's client projects)? Operator call; can land after the native test without blocking the milestone.
3. **Extractor consolidation** — `T3-autonomous-extractor` (M4, unaccepted draft) and `T3-backfill-workflow` share the per-commit `claude -p` machinery. Accept the extractor into this wave, keep it M4, or fold it into #3? Operator call at ceremony.
4. **0.4.0 timing** — bump at wave 1 (schema exists before any backfilled event) or lazily at first emission? Lean: wave 1 — the UI and gate work need the schema to test against.

## 8. After M5

The plugin is whole: adopt forward from today (M4), recover backward when wanted (M5). What remains beyond is distribution maturity (public channel, T2-packaging §8) and ontology reviews (verification overhaul, T2-ontology §7 Q1).
