---
id: T3-project-init-flow
plan_kind: thematic
tier: 3
t2_parent: T2-packaging
milestone: M4-fresh-install
status: draft
---

# T3-project-init-flow — one command attaches a repo

**Status**: Draft.
**Sits at**: T2-packaging theme, M4-fresh-install milestone. Depends on T3-toolchain-portability (baked paths). Consolidates T2-packaging §5's `T3-cli-install-command` + `T3-target-project-init-flow` candidates.

---

## 1. Why

Plugin install is per-user; tracking is per-repo. Nothing today bridges them — the capture skill rightly refuses to create `events.jsonl`, and git hooks must land in each repo's `.git/hooks`. The bridge is one user-triggered command (M4 §2.2: control + idempotency; no postinstall magic).

## 2. What — the init command

Single command (final name post-rename, e.g. `/apv-init`), runnable in any git repo:

1. **Preconditions**: a git repo; refuses bare repos; detects an already-attached repo and switches to report-and-repair mode.
2. **Seed**: create the data dir — **`.apv/`** (M4 §7 Q3, ruled 2026-06-10) — with an empty `events.jsonl` (created explicitly *here* — the one sanctioned creation site), and write `.apv-config.toml` with `[storage] data_dir = ".apv"` + default `[gate]` lists.
3. **Hooks**: run the three existing installers (capture-guard pre-commit; gate pre-push; gate ref-update) with the toolchain path baked (T3-toolchain-portability). Their fresh/identical/differs contract is the idempotency story — a foreign hook refuses loudly, never clobbers.
4. **Orient**: offer to write a CLAUDE.md block — one paragraph naming the discipline and the skills. Ruled (M4 §7 Q4, 2026-06-10): the offer makes clear **init is its only trigger** (no other code path writes or re-offers; re-run init to be offered again), and writing requires **explicit user acceptance** — never unasked.
5. **Hand off**: print next steps — "work normally; capture before commits; the guard will catch you if you forget".

Re-run = audit mode: report each component's state (present/missing/differs), fix the missing, touch nothing else.

## 3. Scope

### In scope
- The command + its script; existing-repo attachment (init-from-now); idempotent re-run; uninstall notes (manual, documented).

### Out of scope
- History mining — M5-backfill.
- Session-start awareness — T3-session-orientation.
- First capture content — the next real commit captures normally; init does not invent events.

## 4. Verification

1. Sandbox fresh repo: init → all three hooks live, config parses, first uncaptured commit is rejected by the guard, captured commit passes, gate green on empty + first-block log.
2. Sandbox existing repo (history, dirty hooks dir with a foreign pre-commit): init refuses that hook loudly, installs the others, reports clearly.
3. Re-run idempotency: second run reports "attached, nothing to do"; after deleting one hook, re-run restores only it.

## 5. Dependencies

- T3-toolchain-portability — baked paths, renamed surfaces.
- M2/M3 installers — the contract this command orchestrates.

## 6. Open questions

1. Command shape: plugin slash-command invoking a script, vs script-only with the skill documenting it? Lean: slash command (discoverable) wrapping one idempotent script (testable).
2. Should init offer `--at=manual` (no hooks, gate-on-demand) for hook-averse teams? Lean: yes, flag-through to the installers.

## 7. Build notes (2026-07-03)

Both §6 leans ratified in the build:

- **Q1 — slash command wrapping one idempotent script.** `scripts/apv-init.sh` owns every filesystem action; `commands/apv-init.md` owns the conversation (relay the per-component report; ask the CLAUDE.md question explicitly; re-run with `--accept-claude-md` only on the user's yes).
- **Q2 — `--at=manual` flags through**: no git hooks installed, the on-demand gate contract printed instead. `--at=pre-push`/`--at=ref-update` install a single gate adapter; the default installs all three hooks.
- **Vendored-vs-external detection**: the toolchain home is the script's own parent; when it sits inside the repo being attached the gate installers run bare (one shared hook copy must serve every worktree — the dogfood story), otherwise `--home=` bakes the plugin home (T3-toolchain-portability's contract, consumed as designed).
- **CLAUDE.md offer is marker-guarded** (`<!-- apv:orientation -->`): accepted runs are idempotent, the offer repeats only on re-init, nothing is ever written unasked (M4 §7 Q4 honoured).
- **Foreign-hook refusal aggregates**: init continues past a refused slot, surfaces the installer's own refusal text, exits 1 (§4.2's loud-but-partial shape).
- **Gate green on an empty log confirmed** — adopting repos start at zero events and pass; `schema-version.txt` seeded as a human-readable epoch marker (no toolchain consumer).
- Sandbox: `tests/init/run-init-sandbox.sh` covers §4.1–4.3 plus `--at=manual` and acceptance idempotency.
