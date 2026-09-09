---
name: apv-check
description: Run APV validation and integrity checks with compact output and a detailed local report. Use after capture or before merge. Supports direct execution on clients without plugin subagents; never writes captures or commits.
---

# APV checking

Capture remains in the main conversation, where intent and decisions are known.
This skill checks the resulting files using scripts, with optional agent isolation.

## Resolve and run

Resolve `$APV` by the sibling `apv-capture/SKILL.md` section 0 (APV_HOME, plugin
root, vendored checkout or installed source path). Resolve the tracked project
separately and run from that directory. Never assume plugin root is project root.

```bash
bash "$APV/scripts/apv" check --json
```

Default mode validates events and plan frontmatter, rebuilds cache/projection/
summary, runs audits, then checks integrity and Git seal correspondence (integrity
only in a non-Git scope). It writes derived files and a temporary diagnostic report;
it never writes canonical events or a capture timestamp. Use `--gate-only` for
the merge boundary, or `--ref <commit>` to check a committed Git ref without refresh.
Gate-only skips the full refresh pipeline, but advisory gate checks may rebuild
a stale cache; it is not a guarantee of read-only execution.
Exit 0 = pass, 1 = failed check, 2 = environment/usage error or changed inputs.
The JSON response includes an input digest, steps, warning count and report path.
Reports live in the machine's temporary directory and may be cleaned by the OS.

## With an agent

If this client exposes `exfu-agent-plan-visualiser:apv-checker`, delegate the check
with the absolute project path, absolute toolchain path and requested mode. Tell
the user "APV is checking…". Wait for the result before timestamping or committing;
do not mutate inputs concurrently. Do not send the whole conversation: the checker
needs files and scope, not the narrative required to author a capture.

If native plugin agents are unavailable, run the same command directly and apply
the same reporting rules. No agent installation or subagent is required to check.

## Report and respond

- Pass: one short line with warning count, if any. Keep raw output in the report.
- Fail/error: read the report; surface the blocker and a recommended next action.
  Existing advisory backlog is summarized, not repeated in full.
- A result is valid only for the checked inputs. Any subsequent input change
  requires a fresh check. A pass does not authorize a commit, repair, or gate bypass.

The parent owns all captures, event repairs, acceptance, timestamps, commits and
merges. After a successful capture check it writes `.last-capture` as its last
file change, then commits per apv-capture. A failed check never stamps capture.
Use apv-merge for reconciliation and landing; this skill does not replace it.
