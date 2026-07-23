---
id: T3-install-path-portability
plan_kind: thematic
tier: 3
t2_parent: T2-packaging
milestone: M4-fresh-install
status: draft
---

# T3-install-path-portability — the shipped surface resolves from an installed toolchain

**Status**: Draft. Bug-fix follow-on to the closed [[T3-toolchain-portability]] (append-only law: closed plans are archaeology; a defect found after closure spawns a sibling, it does not reopen the original).

## 1. Why

The first field report from a repo running APV purely as an installed plugin (`exfu_planner`, 2026-07-23) surfaced a defect class that dogfooding is structurally blind to. In this repo the toolchain and the tracked repo are **the same tree**; in every real install they are not. Every surface that addressed the toolchain as `agent-plan-visualiser/...` therefore worked here and resolved to nothing everywhere else.

The severity is not the broken paths. It is *which* path was broken: `/apv-capture` §6 step 1, the validation leg that gates every sealed commit. It has been unrunnable outside this repo since packaging, which means downstream logs were sealed without the check that makes a seal worth anything.

The reporting agent's own diagnosis was wrong in the other direction — it concluded the gate hooks were affected too. They were not: `gate-check.sh` and `bin/apv` were already portable and measured clean. The defect was narrower than reported and deeper than it looked.

## 2. What

Toolchain **content** (schemas, sibling scripts) resolves from each script's own location. The tracked **repo** resolves independently, via `git rev-parse` — the split `gate-check.sh` has always made and the rest of the pipeline never adopted. Data and planning dirs route through `apvlib`. Shipped instructions anchor on `$APV`, which is now *defined* rather than assumed.

## 3. Scope

### In scope

- `repack-validate.sh`, `validate-events.sh`, `validate-plan-frontmatter.sh` — location independence.
- `skills/apv-capture`, `skills/apv-merge`, `commands/*` — a runnable `$APV` resolver, and every invocation anchored on it.
- `apv-init.sh` toolchain-discovery glob (the 0.7.0 `exfu-` rename broke it) and `hooks/extract-capture.sh`'s missing cache rung.
- `tests/audit-toolchain-paths.sh` — the standing guard.

### Out of scope

- The analyser's live-summary save path (`serve.py:59` loads `schemas/0.2.0`; the `freeform_path` pattern at `0.2.0:335` rejects any data dir but `.agent-plan-tracker/`). Real, confirmed, and not on the capture path — carried separately.
- The 9 advisory comment banners the audit reports non-blocking.
- Re-running the gate over downstream repos captured during the broken window (operator call).

## 4. Verification

1. `repack-validate.sh` green from a synthetic installed repo with the toolchain in a plugin-cache-shaped path; artefacts land in the project's data dir and **not** beside the toolchain.
2. Dogfood layout unchanged: 8/8, and all ten existing suites ALL PASS.
3. `validate-plan-frontmatter.sh` exits non-zero on an empty planning dir (the pinned-`planning_dir` monorepo previously got a green `all 0 plan files valid`).
4. `audit-toolchain-paths.sh` demonstrates teeth: it must FAIL against the 0.7.0 tree and PASS against this one.

## 5. Dependencies

Follows [[T3-toolchain-portability]] (closed) and [[T3-distribution]] (§9 carries the 0.7.1 release note and the re-attach instruction).

## 6. Open questions

1. **Does the audit belong in the gate?** It is a static sweep over `git ls-files`, cheap enough to be a `gate-composite` check rather than a suite the operator remembers to run. Deferred — the gate's check list is policy in `.apv-config.toml` and adding to it is an operator ruling.
2. **How far does the re-attach obligation reach?** Every repo attached at ≤ 0.7.0 carries a committed shim with the broken glob. There is no inventory of attached repos, and no mechanism that would notice.
