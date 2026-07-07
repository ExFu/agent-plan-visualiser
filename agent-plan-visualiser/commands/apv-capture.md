---
description: Capture the current session's work as sealed events in the event log. Run after each logical unit of work, immediately before committing — capture is the last act before a commit.
---

Capture what just happened as events. The canonical procedure is the
apv-capture skill; this command is its slash-invocable surface — do not
improvise from memory.

1. Read the skill in full and follow it exactly:

   ```
   ${CLAUDE_PLUGIN_ROOT}/skills/apv-capture/SKILL.md
   ```

2. In outline (the skill governs on every detail): resolve the data dir
   (`APV_DATA_DIR` → `.apv-config.toml` → default), append ONE block of
   events for the work just completed, ending in a `commit.recorded` seal
   whose `message_first_line` exactly matches the git commit you are about
   to make; validate (`repack-validate.sh`); stamp `.last-capture`; then
   commit. Append-only, always.
