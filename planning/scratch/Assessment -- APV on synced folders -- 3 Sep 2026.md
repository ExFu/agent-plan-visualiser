---
type: assessment
of: "Work Request -- APV on synced folders -- 3 Sep 2026.md"
for: Alastair
date: 2026-09-03
status: proposal, awaiting your acceptance before anything is built
---

# APV on synced folders: do it, and fix one more thing while we are there

**Yes to the request, and keep SQLite.** The problem is where the cache file sits, not what format it is. Moving the throwaway files out of the Dropbox folder and running the audits through Python removes both frictions the therapist-tool run hit, without touching the log, the plans or any git-based project.

**There is a third gap the request did not name, and it is the real cause of the awkward setup steps.** When there is no git, the tools decide where "the project" is by looking at their own install folder instead of the folder you are standing in. That is why every command in the therapist-tool notes has to start by exporting two environment variables, and it means the scope's own config file is silently ignored. A small fix (look for the config file when git is absent) removes those exports entirely. That should go first, alongside the validator fix.

**Answers to your three questions:** put the cache under `~/.cache/apv/`, named after the scope, with a temp-folder fallback that announces itself; move `projection.json` out too; no ignore list, the "is this a plan?" rule covers it.

**Shape:** one new milestone in the APV planning corpus with two plans under it. The first covers the validator, the root-finding fix, the audits and the cache move (about a day). The second gives `apv init` a no-git mode, since today it refuses to run outside git at all (half a day). Nothing changes on the Agent Library side for now.

**Caveat:** the shared summary and dashboard files stay in the folder by design, so Dropbox conflicted copies of those remain possible. This work reduces the noise, it does not remove it.

Full technical report: `Assessment -- APV on synced folders -- 3 Sep 2026.agent.md`.
