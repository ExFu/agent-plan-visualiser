---
id: FIX-D3
plan_kind: thematic
tier: 3
t2_parent: FIX-T2-OLD
status: active
---

# FIX-D3 — drift fixture child

Frontmatter still names `FIX-T2-OLD`, but a `relationship.reattached` event
moved this plan to `FIX-T2-NEW`. The gate's drift check must WARN (exit 0):
frontmatter is a creation-time seed; events are SSOT.
