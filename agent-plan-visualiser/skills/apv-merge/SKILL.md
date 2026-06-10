---
name: apv-merge
description: Land a branch on main without corrupting the agent-plan-visualiser event log. Use when a branch is ready for main in any tracked project (has a .agent-plan-tracker/events.jsonl or APV_DATA_DIR equivalent), and especially when git reports a merge conflict on events.jsonl — that conflict is this skill's designed trigger, never a nuisance to auto-resolve.
---

# /apv-merge — bring a branch to main, record intact

You (the in-session agent) reconcile **on the branch, before main moves**. Main only ever receives gate-green logs. This is the hygiene PR workflows already practise — refresh your branch, resolve there, land clean — applied to the event log.

A textual conflict on `events.jsonl` is the single most tempting moment for anyone, human or agent, to hand-edit the log. This skill exists for that moment.

## 0. Preconditions

- Branch work is committed and captured (/apv-capture): the log ends in a seal, nothing staged.
- `bash agent-plan-visualiser/scripts/gate-check.sh` is green on the branch **as it stands** — repair first; never carry defects into a reconciliation.
- `DATA_DIR` resolves as /apv-capture §0; `DATA_REL` below is its repo-relative path (default `.agent-plan-tracker`). Snippets assume the repo root as cwd.

## 1. Pick the lightest sufficient integration

Refresh your view of main (`git fetch` when there is a remote), then compare:

| main since the branch point | integration |
|---|---|
| unmoved | **fast-forward**: `git checkout main && git merge --ff-only <branch>`. Skip to §5's gate. |
| moved, but `events.jsonl` untouched on main | **rebase — acceptable and preferred.** Seals match `message_first_line`, not commit hashes: the log is rebase-tolerant by design. Preserve subjects — never squash or reword a sealed commit (the orphaned seal blocks at the gate). |
| both logs grew | **merge main into the branch** — there is actually something to merge. §2–§4. |

## 2. The `events.jsonl` conflict — the recipe

Never suppress the conflict: no union merge driver, no `-X ours`/`-X theirs`, ever — auto-resolution would hide the one moment that needs you. The resolution is deterministic:

**Main's log is the prefix — its line positions never move. The branch's blocks append after, unedited, in their original order.** (Append-only, generalised to the branch level.)

```bash
BASE=$(git merge-base HEAD MERGE_HEAD)                        # merging main into
PREFIX=$(git show "$BASE:$DATA_REL/events.jsonl" | wc -l)     # the branch: MERGE_HEAD
{ git show "MERGE_HEAD:$DATA_REL/events.jsonl"                # is main, HEAD is you
  git show "HEAD:$DATA_REL/events.jsonl" | tail -n +"$((PREFIX + 1))"
} > "$DATA_REL/events.jsonl"
git add "$DATA_REL/events.jsonl"
```

(Under rebase the roles flip for each replayed commit: HEAD is upstream/main — keep it as the prefix and re-append the replayed commit's block.)

## 3. Semantic pass — contradictions go to the operator ⛔

The textual recipe cannot see meaning. Diff the two tails (each side's events since `$BASE`) for entities both sides touched:

- closed on one side, progressed/extended on the other;
- competing `entity.renamed` targets;
- duplicate `entity.created` of the same id;
- decisions that contradict each other.

Any of these → **stop. Surface both stories to the operator with a recommendation; never resolve silently.** Their ruling becomes **reconciliation events** in the block you are about to seal — typically `entity.reopened` + its paired `decision` carrying the ruling, or whatever they rule. The gate backstops this pass: a merged closed-then-progressed sequence blocks as `resurrection-without-reopen` until a reopen records the ruling. Repair is append-only by law — nothing can be inserted before the violation, so the check recognises the healed shape: a later reopen resolves what precedes it.

## 4. Conclude the merge commit

The capture guard firing on a conflicted merge is **correct behaviour** — reconciliation is capturable work. Append one block per /apv-capture, ending in a `commit.recorded` seal whose `message_first_line` exactly matches the merge commit message you are about to use:

- contradictions ruled on → the reconciliation events, then the seal;
- textual-only reconciliation → the seal alone (the log records that a reconciliation happened; there is nothing else to say).

Then as ever: validate, `date +%s > "$DATA_DIR/.last-capture"`, and `git commit` to conclude the merge.

A **clean** merge — no conflict — is the opposite case: git creates the merge commit without running the pre-commit hook, and that is right. Nothing happened to the log; no capture, no seal. Sealless merge commits are tolerated by design (positional rollup skips them; the seal↔commit check runs log→git only).

## 5. Gate, then land

```bash
bash agent-plan-visualiser/scripts/gate-check.sh
```

Run it **after** the merge commit, from the branch: both parents are now reachable, so every seal resolves (mid-merge, main's seals would look orphaned). Green only:

```bash
git checkout main && git merge --ff-only <branch>
```

The branch now contains main, so fast-forward always suffices — main receives exactly the reconciled, gated state, and never moves until the log is green. Pushing main transits the pre-push adapter where installed (belt-and-braces; same check).

Red → repair **on the branch** (integrity defects are repaired, never overridden) and re-gate. Main has not moved; there is nothing to unwind.

## 6. Manual procedure (no agent)

The same doctrine, condensed — for humans resolving by hand:

1. On the branch: `git merge main`. No conflict → done (no capture needed). Conflict on `events.jsonl` → continue.
2. Rebuild the file: main's version first, whole; then your branch's new lines (everything past the merge-base's line count in *your* version). Touch nothing else.
3. Read both tails. Same entity closed on one side and worked on the other → decide explicitly; record the ruling as `entity.reopened` + `decision` appended after (shapes: /apv-capture §2).
4. Append a `commit.recorded` seal matching your merge commit message exactly; `date +%s > .agent-plan-tracker/.last-capture`; conclude the commit.
5. `bash agent-plan-visualiser/scripts/gate-check.sh` — fix until green, then `git checkout main && git merge --ff-only <branch>`.

## 7. What NOT to do

- **No union merge driver** (`merge=union` in `.gitattributes`) on `events.jsonl`, and no `-X ours`/`-X theirs` — auto-resolution hides exactly what needs eyes.
- **Never edit or reorder within blocks**; never touch main's prefix; never dedupe "redundant-looking" events.
- **Never squash or reword sealed commits** while rebasing — the orphaned seal blocks at the gate.
- **Never self-rule a contradiction.** The operator rules; you recommend.
- **Never land red**, and never `--no-verify` a push of main to skip the gate — that hatch is for capture-free trivia commits, not the boundary.
