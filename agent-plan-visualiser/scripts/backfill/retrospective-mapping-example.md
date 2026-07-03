---
project_name: acme-storefront
authored_by: jane
authored_at: 2026-07-03
target_schema_version: 0.4.0
---

# Retrospective mapping for acme-storefront

Worked example of the template — a realistic non-native shape: ADRs +
`docs/architecture/` + GitHub-issue blockers, no tier discipline.

## Plan-equivalent artefacts

- Path(s): `docs/architecture/*.md` (one file per subsystem, no tiers)
- Convention: informal; each file mixes intent and implementation notes.
- Mapping: each file → one T2-equivalent plan entity, id `T2-<filename-slug>`
  (e.g. `docs/architecture/checkout.md` → `T2-checkout`). There is no
  T1-equivalent; do NOT synthesise one — treat the README's "Goals" section
  as background only.

## Decision artefacts

- Path(s): `docs/adr/NNN-*.md` (ADR-style, numbered).
- Mapping: each ADR → a recovered `decision` citing the ADR path; attach to
  the plan(s) its "Context" section names. ADR supersession lines ("ADR-012
  supersedes ADR-007") are fulcrum evidence for the affected plan.

## Blocker conventions

- Convention: GitHub issues labelled `blocked-external`; referenced in
  commits as "waiting on #NNN".
- Mapping: first "waiting on #NNN" mention → `blocker.raised` (slug from
  the issue title); "unblocked"/"#NNN resolved" wording → `blocker.closed`.

## HITL-question conventions

- Convention: `## Open questions` sections inside architecture files.

## Implicit-work expectation

- High: the `ops/` and `scripts/` trees never had planning artefacts —
  expect pure implicit-work there; don't force attribution.

## Known pivots (feeds the triage pass pre-armed)

| commit (sha or subject) | what pivoted | rationale (your words, citable) |
|---|---|---|
| "checkout: move to stripe elements" | hand-rolled card form → Stripe Elements | "PCI scope reduction — ruled at the 2025-01 security review" |
| "drop the recommendations service" | recommendations subsystem cancelled | "vendor cost tripled at renewal; conversion lift never materialised" |

## Anything else the extractor should know

- History before 2024-06 was squashed during a repo migration — expect
  large synthetic-looking commits there; classify as implicit-work.
- `vendor/` is third-party code; never attribute work to it.
