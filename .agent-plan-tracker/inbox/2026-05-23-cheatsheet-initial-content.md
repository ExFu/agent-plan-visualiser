---
id: 2026-05-23.cheatsheet-initial-content
entity_type: inbox-item
created_at: 2026-05-23
status: open
candidate_fate: t3
---

# Initial content for cheatsheet.md

T2-packaging plugin structure includes `cheatsheet/cheatsheet.md` for common operations (per T2-packaging §3.4). This is the everyday surface — agents should hit this before reading the formal spec.

## Likely entries (once tooling lands)

| Want to... | Run this |
|---|---|
| Show me what's outstanding | `scripts/audit-stalled.sql` (T2-projection §3.4) |
| Trace why this plan died | `scripts/trace-decision-history.sql <entity_id>` |
| Rebuild the cache from scratch | `scripts/cache-build.sh` |
| Validate plan frontmatter | `scripts/validate-frontmatter.sh <plan-file>` |
| List orphans needing resolution | `scripts/audit-orphans.sql` |
| Show the timeline for an entity | `scripts/timeline-for-entity.sh <entity_id>` |
| Find fulcrum events without paired decisions | `scripts/audit-fulcrum-without-decision.sql` |
| Generate a fresh projection | `scripts/projection-emit.sh` |
| Open the HTML view | `open agent-plan-tracker/view/index.html` (or equivalent) |
| Run the pre-merge cleanliness gate locally | `scripts/cleanliness-gate.sh` |

Each pair (or each small group) becomes a one-liner explanation. Cross-link to worked examples in `cheatsheet/worked-examples/` for deeper dives.

## Discipline

The cheatsheet is for the everyday surface. The formal spec (`skills/using-agent-plan-tracker/SKILL.md`) is the floor for "I need the canonical definition". The cheatsheet is the floor for "I just want to do the thing".

Pointer convention (per T2-packaging §3.4 — the lookup order): `scripts/` → `scripts/local/` → generate-from-scratch-and-save. Cheatsheet entries reference the canonical `scripts/` paths.

**Resurrect when:** First M1 tooling lands (`T3-projection-queries-v0` is the earliest catalyst). Once 3-4 scripts exist, the cheatsheet starts paying off.
