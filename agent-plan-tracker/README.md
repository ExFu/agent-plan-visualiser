# agent-plan-tracker

Event-sourced planning methodology + tracking spine, packaged as a Claude Code plugin.

## Status

**Pre-M1.** Work in progress — not yet installable on other projects. Current focus is reaching M1: a hand-rollable end-to-end pipeline against this project itself, dogfooding the methodology.

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
