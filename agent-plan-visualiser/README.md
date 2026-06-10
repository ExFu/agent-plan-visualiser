# agent-plan-visualiser

Event-sourced planning methodology + tracking spine, packaged as a Claude Code plugin.

## Status

**M1 shipped; pre-distribution.** Not yet installable on other projects — that's M4. The hand-rolled end-to-end pipeline is complete and dogfooded against this repo: schema validation → SQLite cache → `projection.json` → `summary.md` → HTML flow view, all green via `scripts/repack-validate.sh`. Two further milestones landed on top: **M6-analyser** (browser-direct outstanding-work analyser; first ontology evolution to schema `0.2.0`) and **M1.2-relationship-ssot** (event-sourced relationship membership). Next frontier: **M2 — automated per-commit extraction** (events are still hand-rolled until then).

## What it will do

- Walk a project's git history and extract structured events against a defined ontology.
- Maintain an append-only event log (`.agent-plan-tracker/events.jsonl`) as canonical project state.
- Provide projections (audits, decision traces, status reports, HTML view) derived from the log.
- Enforce a tiered planning methodology (T1/T2/T3 + milestones + lettered workstreams).

## Authoritative references

- `../planning/T1-top-level.md` — full T1 design.
- `../planning/M1-bootstrap.md` — current milestone (M1).
- `../.agent-plan-tracker/events.jsonl` — this project's own event log (dogfood).
- `../CLAUDE.md` — session-start orientation.

## License

TBD.
