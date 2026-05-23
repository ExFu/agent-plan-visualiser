---
id: 2026-05-23.snapshot-trigger-config
entity_type: inbox-item
created_at: 2026-05-23
status: open
candidate_fate: t3
---

# Snapshot auto-trigger configuration

Per T2-storage §3.6, snapshots trigger on:

- Major plan completions (Tier-1 / Tier-2 closure).
- Project milestones.
- On demand: `apt snapshot now [--label <slug>]` (or equivalent slash command).
- Auto-rolling: every N events (configurable, default off during early use).

The "every N events" auto-roll is currently off by default. Once M2/M3 land and the event log grows to a real size, decide:

- **What's N?** Probably ~500–1000 events. Need to feel out via dogfooding.
- **Per-project configurable?** Yes — different projects have different cadences.
- **Where does the config live?** `.agent-plan-tracker/config.yaml` is a sensible candidate. Or in the plugin's per-project local settings (per `plugin-dev:plugin-settings` skill — the `.claude/<plugin>.local.md` pattern).
- **Manual trigger as a slash command?** `/apt-snapshot` or similar.
- **Auto-trigger on major plan closure** — needs to detect "major" (T1/T2 supersession or completion). Derivable from event types.

**Resurrect when:** Snapshots become useful (probably M2 when the log has grown enough to make full-rebuild noticeable, or M3 when the cleanliness gate needs incremental cache rebuilds).
