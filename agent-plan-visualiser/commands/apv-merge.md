---
description: Land a branch on main without corrupting the event log — branch-side reconciliation, main only ever receives gate-green logs. Use when a branch is ready for main, and especially when git reports a merge conflict on events.jsonl.
---

Bring the branch to main with the record intact. The canonical procedure is
the apv-merge skill; this command is its slash-invocable surface — do not
improvise from memory, and never auto-resolve an `events.jsonl` conflict.

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
