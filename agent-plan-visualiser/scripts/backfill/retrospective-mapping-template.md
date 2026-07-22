---
project_name: <slug>
authored_by: <the project owner — mappings need someone who was there>
authored_at: <YYYY-MM-DD>
target_schema_version: 0.4.0
---

# Retrospective mapping for <project>

The translation brief the backfill extractor reads verbatim (T2-ingest
§3.2/§3.3). Fill what applies; delete what doesn't; free-form notes are
welcome anywhere — structure below is a checklist, not a cage. Place the
finished note at `<data-dir>/retrospective-mapping.md`; it is archived
automatically after the backfill completes.

## Plan-equivalent artefacts

- Path(s): <e.g. `docs/architecture/`, `SPEC.md`, a wiki export>
- Convention: <file per area? tiers? nothing?>
- Mapping: <e.g. each file → a T2-equivalent plan entity; synthesise ids as
  `T2-<slug>`; there is no T1 — treat README §1 as the T1-equivalent>

## Decision artefacts

- Path(s) / convention: <ADRs? decisions.md? "because ..." commit messages?>
- Mapping: <e.g. each ADR → a recovered `decision` citing the ADR file>

## Blocker conventions

- Convention: <BLOCKERS.md? issue labels? "waiting on X" in commits?>
- Mapping: <appearance → blocker.raised; resolution wording → blocker.closed>

## HITL-question conventions

- Convention: <`# TODO:`? `QUESTIONS.md`? `Q:` markers in docs?>

## Implicit-work expectation

- <High/low volume of plan-less commits; any subsystems that never had
  planning artefacts and should be expected as pure implicit-work.>

## Known pivots (feeds the triage pass pre-armed)

Entries here are RECOVERED rationale — the extractor may cite them as
decision sources, and anything you can only half-remember belongs in the
triage sitting instead. Same shape as the triage checklist:

| commit (sha or subject) | what pivoted | rationale (your words, citable) |
|---|---|---|
| <a1b2c3d / "switch to postgres"> | <MongoDB → Postgres on the data layer> | <"aggregate queries were unshardable; decided in the 2024-03 arch review"> |

## Sub-projects (only if the repo registers a `[projects]` carve-out map)

- <Which historical areas map to which `[projects.<name>]` — e.g. "the old
  `web/` tree is today's `site` sub-project". The walk stamps
  `attributes.project` mechanically from TODAY's carve-outs applied to each
  historical commit's paths; where history diverges from today's layout,
  note it here and correct at triage with the bulk `project.assigned`
  pattern (`cheatsheet/worked-examples/assign-entity-to-project.md`).>

## Anything else the extractor should know

<naming aliases, dead directories, vendored code to ignore, rewritten
history caveats, ...>
