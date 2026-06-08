---
id: T3-capture-guard-hook
plan_kind: thematic
tier: 3
t2_parent: T2-extraction
milestone: M2-auto-extract
status: draft
---

# T3-capture-guard-hook — Pre-commit hook that enforces capture-before-commit

**Status**: Draft.
**Sits at**: T2-extraction theme, M2-auto-extract milestone. Depends on `T3-apt-capture-skill` (which writes `.last-capture`).

---

## 1. Why

The capture skill codifies the discipline; the hook **enforces** it. Without it, the agent (or the operator) can `git commit` without having run `/apt-capture`, and the event log silently falls behind. The hook makes that impossible — a commit with uncaptured changes is rejected.

The hook is deliberately **tiny** — a timestamp comparison, no LLM, no network call, no block. The *skill* does the thinking; the *hook* just refuses to let you forget.

## 2. What

A shell script (`.git/hooks/pre-commit` or installed via a wrapper) that:

1. Reads the timestamp from `.last-capture` (in the configured data dir, or `.agent-plan-tracker/.last-capture` by default).
2. If `.last-capture` doesn't exist → reject. ("No capture recorded. Run `/apt-capture` first.")
3. Checks whether any **staged files** have an mtime newer than the `.last-capture` timestamp.
4. If yes → reject. ("Staged changes are newer than the last capture. Run `/apt-capture` first.")
5. If no → exit 0. Commit proceeds.

## 3. Design details

### Timestamp file

- **Path:** `<APT_DATA_DIR>/.last-capture` (respects the configurable data dir from `T3-configurable-data-dir`; falls back to `.agent-plan-tracker/.last-capture`).
- **Content:** a Unix epoch timestamp (seconds), written by the capture skill as its last action.
- **Gitignored:** local machine state, not project state. Added to `.gitignore` by `T3-configurable-data-dir` (or by this T3 if the other hasn't landed yet).

### Staged-file mtime comparison

```bash
capture_ts=$(cat "$data_dir/.last-capture" 2>/dev/null)
if [ -z "$capture_ts" ]; then
    echo "apt: no capture recorded. Run /apt-capture first." >&2
    exit 1
fi

# Check each staged file's mtime against capture timestamp
for file in $(git diff --cached --name-only); do
    if [ -f "$file" ]; then
        file_ts=$(stat -f %m "$file" 2>/dev/null || stat -c %Y "$file" 2>/dev/null)
        if [ "$file_ts" -gt "$capture_ts" ]; then
            echo "apt: '$file' modified after last capture. Run /apt-capture first." >&2
            exit 1
        fi
    fi
done
```

(Exact stat flag varies by OS — `-f %m` on macOS, `-c %Y` on Linux. The hook handles both.)

### Bypass

`git commit --no-verify` skips the hook, as with any pre-commit hook. This is the escape hatch for commits that genuinely don't need event capture (e.g. a pure typo fix, or work on the plugin's own scripts that aren't tracked entities).

### Data dir resolution

The hook reads `APT_DATA_DIR` from the environment if set; otherwise defaults to `.agent-plan-tracker`. Same resolution as the Python scripts, but in shell.

## 4. Scope

### In scope
- The pre-commit hook script itself.
- Manual installation instructions ("copy to `.git/hooks/pre-commit`, chmod +x").
- A convenience one-liner install script (e.g. `scripts/install-hook.sh`) that copies it into place idempotently.
- `.last-capture` added to `.gitignore` if not already there.
- Test: stage a file, confirm hook rejects without `.last-capture`; write `.last-capture` with current timestamp, confirm hook passes; touch a staged file after `.last-capture`, confirm hook rejects again.

### Out of scope
- Automated hook installation as part of project-init (M4).
- The autonomous `claude -p` extraction hook (deferred, M4-adjacent).
- Cross-platform testing beyond macOS + Linux `stat` variants.

## 5. Verification

1. Hook rejects a commit when `.last-capture` is absent.
2. Hook rejects when a staged file is newer than `.last-capture`.
3. Hook passes when all staged files predate `.last-capture`.
4. `--no-verify` bypasses as expected.
5. Hook respects `APT_DATA_DIR` override.

## 6. Dependencies

- `T3-apt-capture-skill` — writes `.last-capture`.
- `T3-configurable-data-dir` — defines `APT_DATA_DIR` resolution (but the hook can ship with a simple fallback if this T3 lands first).

## 7. Open questions

1. **Timestamp precision.** Second-level should be sufficient — filesystem mtimes are typically second-granularity. Sub-second would add complexity for no practical gain.
2. **Derived files.** Should the hook exclude known derived files (cache.sqlite, projection.json, summary.md) from the mtime check? They're rebuilt by the pipeline and may be newer than `.last-capture` legitimately. Lean yes — maintain a small exclude list in the hook.
3. **events.jsonl itself.** The capture skill appends to events.jsonl *before* writing `.last-capture`. So events.jsonl's mtime should be ≤ `.last-capture`. But if the agent hand-edits events.jsonl after capture (correcting a typo), the hook would reject. Is that the right behaviour? Lean yes — re-run `/apt-capture` to update the timestamp, even if the edit was manual.
