---
id: T3-toolchain-portability
plan_kind: thematic
tier: 3
t2_parent: T2-packaging
milestone: M4-fresh-install
status: draft
---

# T3-toolchain-portability — every reference resolves via the toolchain home

**Status**: Draft.
**Sits at**: T2-packaging theme, M4-fresh-install milestone. Foundation T3 — everything else in M4 builds on portable paths. **The APV rename executes here** (operator ruling 2026-06-10; M4 §2.3).

---

## 1. Why

Every skill, hook and doc currently says `bash agent-plan-tracker/scripts/...` — repo-relative, true only in the dogfood repo where the toolchain is vendored. On a real install the toolchain lives in the plugin cache, addressed as `${CLAUDE_PLUGIN_ROOT}`. M3 made the principle executable for schemas ("a gated repo carries a log, not the schemas"); this T3 finishes the job — and renames the project while every reference is already in hand.

## 2. What

### 2.1 Resolution doctrine

One chain, used everywhere: explicit env (`APV_*`) → repo-vendored toolchain (dogfood) → `${CLAUDE_PLUGIN_ROOT}` (plugin install) → PATH. Skills reference scripts through it; **installers bake the resolved toolchain path into the hook copies they write** (installed hooks must not re-derive — the deciding happens once, at install).

### 2.2 Rename execution (APT → APV, agent-plan-tracker → agent-plan-visualiser)

Live surfaces only:

- Plugin dir `agent-plan-tracker/` → `agent-plan-visualiser/` (git mv); manifest name + version bump.
- Skills `apt-capture`/`apt-merge` → `apv-capture`/`apv-merge`; command/doc references follow.
- Env vars `APT_DATA_DIR`/`APT_GATE_CHECK`/`APT_SKIP_GATE` → `APV_*` (decide: legacy fallback reads with deprecation notice, or clean break — §6 Q2).
- `.apt-config.toml` → `.apv-config.toml`; `aptlib.py` → `apvlib.py`; script prose.
- Live plans, CLAUDE.md, README, cheatsheet/philosophies.

Never touched: **the event log** (append-only — historical names are true record), **closed plans** (archaeology), git history. Dogfood data dir stays `.agent-plan-tracker/`, pinned via `[storage] data_dir` (config middle layer absorbs the brand change). Hooks installed in this repo's `.git/hooks` are refreshed via uninstall + reinstall (the differs-refuse contract makes stale copies loud).

## 3. Scope

### In scope
- Resolution chain in skills/hooks/installers/scripts; rename of all live surfaces; grep audit proving zero stale live references; manifest bump.

### Out of scope
- The init command (T3-project-init-flow) — it *consumes* the baked paths.
- Distribution artefact (T3-distribution).
- Any log or closed-plan rewriting — forbidden, not deferred.

## 4. Verification

1. All existing suites (gate fixtures, both sandboxes, repack-validate, real-repo gate) pass after the rename — dogfood keeps working via the vendored home.
2. Portability sandbox: a repo with **no vendored toolchain**, toolchain at a simulated plugin root — capture-guard, gate-check, pre-push and ref-update flows all resolve and run.
3. Grep audit: no `agent-plan-tracker`/`APT_`/`apt-` references on live surfaces outside the log, closed plans and git history (allowlist documented).

## 5. Dependencies

- M3's installers and resolution chains (the seams were built anticipating this).
- T2-packaging §3.1 spec discoveries (`${CLAUDE_PLUGIN_ROOT}` semantics).

## 6. Open questions

1. Does the dogfood repo's *plugin dir* rename happen in the same commit as the skill/env renames, or staged? Lean: one commit — half-renamed states are worse than a big diff.
2. Legacy env-var fallback (`APT_*` read with notice) or clean break? Lean: clean break — the only install is this repo; migration cost is one reinstall.
3. Does the repo folder itself (`~/Studio/projects/agent-plan-tracker`) rename? Out of plugin scope (operator's filesystem); note `git worktree repair` if done.

## 7. Build notes (2026-06-10)

One commit, as ratified (§6 Q1): five `git mv`s (plugin dir, both skills, `apvlib`, the config file) + 245 mechanical replacements across the toolchain and the 14 non-closed plans + the structural changes below. Clean break on `APT_*` (§6 Q2) — no fallbacks anywhere; one hook reinstall was the whole migration cost. `tests/audit-rename.sh` enforces §4.3 with the allowlist explicit: the data dir, frozen schemas, closed plans, this mapping doc, and two deliberate phrases.

- **Baking is conditional on `--home=`** (the build's main design ruling): an unconditional bake would weld the shared dogfood hooks — one copy serving every worktree — to a single worktree's path. Plugin installs pass `${CLAUDE_PLUGIN_ROOT}`; vendored installs ship the source verbatim and the chain (env → baked → repo-relative → PATH) decides at run time. Installer idempotency compares the **rendered** copy, so same-home re-runs no-op and a different home refuses loudly. `install-hook.sh` needs no `--home` — the guard is toolchain-free.
- **capture-guard mirrors apvlib POSIX-ly**: `APV_DATA_DIR` → one-key `sed` of `.apv-config.toml` → `.apv` default. apvlib's default moved to `.apv` (M4 §7 Q3); the dogfood repo pins `.agent-plan-tracker` via config — the rename was a non-event for the record.
- **gate-check's repo-root default** → `git rev-parse --show-toplevel`: the toolchain may live in the plugin cache, far from any tracked repo; the old `SCRIPT_DIR/../..` default assumed the vendored layout.
- **Schemas stayed byte-frozen** — 0.3.0 even patterns the data dir's real name structurally; epoch artefacts validate historical events and must not move. Manifest bumped 0.2.0 → 0.4.0.
- Portability sandbox (`tests/gate/run-portability-sandbox.sh`, §4.2): no vendored toolchain, no env overrides, no config file — installer bake asserted in the copies, guard finds `.apv` by default, gate-check passes on both explicit and toplevel-default repo-root, ref-update and pre-push refuse a corrupt state via the baked home and pass clean work, `APV_SKIP_GATE` hatch + reset-to-green exercised.
- Live cutover: the three installed hooks refreshed by rm + reinstall (differs-refuse made the staleness loud); this T3's own landing transited the renamed gate end-to-end.
- Surfaced for later: the HTML view hardcodes `../../.agent-plan-tracker/` paths — fine for dogfood, wrong for `.apv` adopters (inbox item filed). The two legacy sandboxes' fixture repos moved to `.apv` with the new default.
