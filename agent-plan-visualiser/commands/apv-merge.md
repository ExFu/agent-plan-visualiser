---
description: Land a branch on main without corrupting the event log — branch-side reconciliation, main only ever receives gate-green logs. Use when a branch is ready for main, and especially when git reports a merge conflict on events.jsonl.
---

Slash alias (Claude Code) for the skill `exfu-agent-plan-visualiser:apv-merge`. The
**skill** is the canonical procedure and the cross-client primitive; this
command is only its slash-invocable surface in Claude Code, and may be absent
in Cowork/Desktop even when the skill is loaded. Invoke the skill and follow it
exactly — do not improvise from memory, and never auto-resolve an
`events.jsonl` conflict.

1. Read the skill in full and follow it exactly:

   ```
   ${CLAUDE_PLUGIN_ROOT}/skills/apv-merge/SKILL.md
   ```

2. In outline (the skill governs on every detail): reconcile ON THE BRANCH
   before main moves; on an `events.jsonl` conflict, main's log is the
   prefix (its lines never move) and the branch's blocks append after,
   unedited; semantic contradictions between the two tails go to the
   operator — never resolve them silently; seal the merge commit per
   capture discipline; gate-check green; only then fast-forward main.
