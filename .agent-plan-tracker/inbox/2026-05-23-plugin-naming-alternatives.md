---
id: 2026-05-23.plugin-naming-alternatives
entity_type: inbox-item
created_at: 2026-05-23
status: parked
candidate_fate: decision
---

# Final plugin name decision

Working name: **`agent-plan-tracker`**.

## Alternatives considered / proposed

- `plan-spine` — evocative of the "tracking spine" framing in T1.
- `git-plan` — emphasises the git-history-as-source-of-truth premise.
- `apgt` — initialism of agent-plan-tracker; cryptic but short.
- `aplan` — short, ambiguous.
- `apath` — short, hints at "agent path" but also collides with python `apath`.
- **Rejected:** `apt` — Debian/Ubuntu package manager namespace collision (recognised in T1).

## Naming criteria

- **Short enough to type** — for slash commands like `/apt-extract`, `/apt-audit`.
- **Distinctive enough to search** — Googling the name should find the plugin.
- **Evocative of the why** — picks up the planning + git + agent angle.
- **Cowork-friendly** — some users won't know what "event-sourced" means; the name shouldn't be more jargon than necessary.

## Status: parked

Defer until M4 packaging work begins. Working name is fine for M1–M3 internal use. Renaming pre-publish is cheap; renaming post-publish is expensive.

**Resurrect when:** M4 work begins. Decide name + lock the npm package identifier + lock the slash command prefix.
