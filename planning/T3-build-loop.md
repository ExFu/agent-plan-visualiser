---
id: T3-build-loop
plan_kind: thematic
tier: 3
t2_parent: T2-packaging
milestone: M1-bootstrap
status: draft
---

# T3-build-loop — Repack-and-validate cycle

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Land `agent-plan-tracker/scripts/repack-validate.sh` that, in one invocation, runs every M1 validation + build step end-to-end. The single command an agent or human runs to confirm "everything still works".

**Architecture:** Bash orchestrator that calls each step in dependency order; aborts on first failure with a clear message; logs successes. Idempotent.

**Tech Stack:** Bash + the existing M1 scripts.

---

## 1. Why this T3

Without a single repack-validate command, agents have to remember the right order of validation + build operations. With it, the M1 acceptance test (T2-packaging §3.5) is a one-liner.

This is also the last M1 T3 — it depends on every other M1 T3 having landed.

## 2. Out of scope

- CI integration (deferred to M4 distribution).
- Performance optimisation (skip-unchanged-files, etc.) — M3+.
- Pre-commit hook automation — M2 territory.

## 3. Acceptance criteria

- `agent-plan-tracker/scripts/repack-validate.sh` exists, executable.
- Runs in order: validate events.jsonl schema → validate plan frontmatter → rebuild cache → emit projection.json → emit summary.md → run audit queries.
- Aborts on first failure with line-context message.
- Exits 0 on full success.
- Adds a colour-coded summary at the end (PASS/FAIL per step).
- Total runtime under 5 seconds against the current ~70-event log.

## 4. Steps

### Step 1: Write the orchestrator

**File:** `agent-plan-tracker/scripts/repack-validate.sh`

```bash
#!/usr/bin/env bash
# repack-validate.sh — end-to-end M1 validation + build.
# Aborts on first failure. Exits 0 on success.
set -uo pipefail

# Colours (skip if not a TTY)
if [ -t 1 ]; then
  RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RESET=$'\033[0m'
else
  RED=""; GREEN=""; YELLOW=""; RESET=""
fi

PASS=()
FAIL=""

run_step() {
  local label="$1"; shift
  echo "${YELLOW}==>${RESET} $label"
  if "$@"; then
    PASS+=("$label")
    echo "${GREEN}    OK${RESET}"
  else
    FAIL="$label"
    echo "${RED}    FAIL${RESET}"
    return 1
  fi
}

cd "$(dirname "$0")/../.." || exit 2

run_step "validate events.jsonl"        bash agent-plan-tracker/scripts/validate-events.sh           || exit 1
run_step "validate plan frontmatter"    bash agent-plan-tracker/scripts/validate-plan-frontmatter.sh || exit 1
run_step "rebuild SQLite cache"         python3 agent-plan-tracker/scripts/cache-build.py            || exit 1
run_step "emit projection.json"         python3 agent-plan-tracker/scripts/projection-emit.py        || exit 1
run_step "emit summary.md"              python3 agent-plan-tracker/scripts/summary-emit.py           || exit 1
run_step "audit-stalled"                bash -c "sqlite3 .agent-plan-tracker/cache.sqlite < agent-plan-tracker/scripts/audit-stalled.sql" || exit 1
run_step "audit-fulcrum-without-decision" bash -c "sqlite3 .agent-plan-tracker/cache.sqlite < agent-plan-tracker/scripts/audit-fulcrum-without-decision.sql" || exit 1
run_step "audit-orphans"                bash -c "sqlite3 .agent-plan-tracker/cache.sqlite < agent-plan-tracker/scripts/audit-orphans.sql" || exit 1

echo
echo "${GREEN}All ${#PASS[@]} steps passed.${RESET}"
```

Make executable:
```bash
chmod +x agent-plan-tracker/scripts/repack-validate.sh
```

### Step 2: Run

```bash
bash agent-plan-tracker/scripts/repack-validate.sh
```
Expected: each step printed with `OK`; final `All 8 steps passed.`

If any step fails, the script aborts immediately with the failing step's name visible.

### Step 3: Time it

```bash
time bash agent-plan-tracker/scripts/repack-validate.sh
```
Target: under 5 seconds total. If significantly over, investigate which step is slow.

### Step 4: Commit

```bash
git add agent-plan-tracker/scripts/repack-validate.sh
```

Commit message: `[M1] T3-build-loop complete — repack-validate end-to-end`

### Step 5: (Optional) Add to cheatsheet

If `agent-plan-tracker/cheatsheet/cheatsheet.md` exists, add a top-row entry:

```markdown
| Confirm everything still works | `bash agent-plan-tracker/scripts/repack-validate.sh` |
```

If cheatsheet doesn't exist yet (it's a later T3), skip this step.

## 5. Files to create / modify

- **Create:** `agent-plan-tracker/scripts/repack-validate.sh`
- **Modify (optional):** `agent-plan-tracker/cheatsheet/cheatsheet.md` if it exists

## 6. Verification

- Script runs end-to-end without error.
- Each individual step's exit status is checked.
- Total runtime is reasonable (<5s for M1 scale).
- Re-running produces identical output (idempotency at the build level).

## 7. HITL questions

- **Q1**: Order of steps assumes schemas validate first, then cache rebuild, then projections. If a step fails partway through, the remaining steps don't run — confirm this is the right failure semantics for M1. (Alternative: run all steps, collect all failures, report at end. More useful but more code. Defer.)
- **Q2**: The audit queries' output is currently dumped to stdout — that's noisy. Worth piping to a file or quieting unless `--verbose`? Default: verbose for M1 (humans want to see results).

## 8. Events this T3 will emit on completion

This is the **final M1 T3**. Its completion triggers M1 completion checks:

- `entity.progressed` on T2-packaging.
- `entity.completed` on T3-build-loop.
- `verification.tested` on T3-build-loop (test_type: `repack-validate-end-to-end`).
- Likely: `entity.completed` on M1-bootstrap if all 9 M1 T3s are dead and the milestone's definition-of-done is met (M1 §5).
- `commit.recorded`.

The M1-completion event is itself **destructive** (a fulcrum event would be `entity.cancelled` or `entity.superseded`; `entity.completed` is non-destructive natural progression). So no paired decision required — M1 just naturally completes.
