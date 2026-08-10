---
description: Attach the current repository to agent-plan-visualiser tracking — seed the data dir, write the config, install the git hooks. Idempotent; re-run to audit and repair.
---

Attach the current repository to agent-plan-visualiser tracking (or audit an
already-attached one). The flow is one idempotent script; your job is to run
it, relay its report, and handle the CLAUDE.md offer with the user.

1. Run the init script from the repo root:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/apv-init.sh" $ARGUMENTS
   ```

   Flags you may pass through if the user asked for them:
   - `--at=pre-push` / `--at=ref-update` — install only that gate adapter.
   - `--at=manual` — install no git hooks; the gate runs on demand only
     (for hook-averse teams; capture discipline is then unenforced).

2. Relay the per-component report to the user faithfully — created / ok /
   REFUSED lines included. A REFUSED hook means a foreign hook already
   occupies that slot: the installers never clobber. Show the refusal and
   let the user decide; re-running after they clear it repairs only the gap.

3. **The CLAUDE.md offer.** If the script printed an orientation-block offer,
   ask the user explicitly whether to add it (one question, yes/no — do not
   assume). Only on their explicit yes, re-run:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/apv-init.sh" --accept-claude-md
   ```

   Never write the block by hand, never write it unasked, and never re-offer
   outside an init run — init is this offer's only trigger.

4. Close by telling the user the attach-from-now contract: work proceeds
   normally; /apv-capture runs after each logical unit of work, immediately
   before each commit; branches land on main via /apv-merge; pre-init
   history is not mined (backfill is a separate opt-in step, not yet part
   of this flow).

5. Monorepo with sub-projects? The generated config carries a commented
   `[projects.<name>]` registry template (planning root + owned-dir
   `dirs` carve-outs) — point the user at it if they mention sub-projects.
   Uncommenting it turns on creation-time attribution (named sub-projects
   stamped by location; the default project is named by registering a
   project that claims the `[storage]` planning root). Single-project
   behaviour is unchanged while it stays commented.
