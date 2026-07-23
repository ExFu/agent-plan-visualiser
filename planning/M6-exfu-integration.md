---
id: M6-exfu-integration
plan_kind: milestone
milestone_index: 6
status: active
---

# M6-exfu-integration — APV owns its ExFu-planning integration

**Status**: Accepted 2026-07-24. Raised 2026-07-24 on the operator's direction: the capture-side integration with the ExFu planning approach is APV's to own, as an optional add-on to the ExFu delegation stack.

## Definition of done

The `exfu-planning-apv-integration` skill (formerly `exfu-capture-apv`, born in the exfu_planner repo) ships inside the `agent-plan-visualiser` plugin: present in plugin source, released (0.6.3), visible in the installed plugin cache, and registered as the `capture` provider by name in consuming repos' `.exfu/providers.toml`. ExFu's own marketplace distributes no capture integration.

Completion is evidence-gated and ordered: `T3-exfu-planning-integration` completes only after the 0.6.3 release, cache presence, and green gate (its step 7); this milestone closes on operator confirmation once that evidence is recorded (milestone closure is a human ceremony, never self-issued).
