---
id: T3-git-less-init
plan_kind: thematic
tier: 3
t2_parent: T2-packaging
milestone: M7-git-less-scopes
status: active
---

# T3-git-less-init — `apv init --no-git` attaches a folder that has no repository

**Status**: Accepted 2026-09-03 by the operator (authored 2026-09-03; revised twice pre-acceptance on the validator rule). Open questions carry stated leans, applied as working defaults until ruled otherwise.
**Sits at**: T2-packaging theme (init and orientation surfaces; T3-project-init-flow precedent, M4-fresh-install §2.2 "init is a user-triggered, idempotent command"), M7-git-less-scopes milestone. Second of the two M7 T3s; depends on `apvlib.apv_cache_dir` and the config-file root finding from T3-synced-folder-runtime.

Every path is relative to the repo root; `$APV` is the toolchain home.

---

## 1. Why (condensed; principles by reference)

`plugins/agent-plan-visualiser/scripts/apv-init.sh` lines 64-72 exit 2 outside a non-bare git work tree, so a synced folder cannot be attached by the tool at all; the therapist-tool scope was attached by hand on 2026-09-02 (data dir, `schema-version.txt`, `.apv-config.toml`, its own CLAUDE.md section). M7 §2.3 rules that git-less attach is explicit: the operator passes `--no-git`; nothing is inferred from a missing `.git`. M4 §2.2's contract (create-if-missing, never clobber, re-run is audit mode) applies unchanged.

## 2. What

### 2.1 The flag and its preconditions

File: `plugins/agent-plan-visualiser/scripts/apv-init.sh`.

- Argument parser (the `for arg in "$@"` case): add `--no-git` → `NO_GIT=1`. Usage line and the header comment gain it. Mutually exclusive with `--at=...` other than the default; `--no-git --at=pre-push` (or `ref-update`, `all` given explicitly) exits 2 with `apv-init: --no-git installs no git hooks; drop --at`. `--with-extractor` with `--no-git` exits 2 likewise (the extractor is a post-commit hook).
- Preconditions (replacing the block at lines 64-72):
  - `NO_GIT=0`, not in a work tree → the existing refusal, message extended: `apv-init: not inside a git repository — run from the repo to attach, or pass --no-git to attach this folder without one.`
  - `NO_GIT=1`, **inside** a work tree (`git rev-parse --is-inside-work-tree` prints `true`) → exit 2: `apv-init: --no-git given inside a git repository (<toplevel>) — drop the flag, or run from the folder you mean to attach.`
  - `NO_GIT=1`, not in a work tree → `REPO_ROOT="$PWD"` (physical path via `pwd -P`). `VENDORED` is always 0.

### 2.2 What a git-less attach writes

Same create-if-missing steps as today, with these differences:

1. **Data dir + `events.jsonl` + `schema-version.txt`**: unchanged.
2. **`.apv-config.toml`**: a git-less template. `[gate]` lists identical to the git template; `[storage]` carries `data_dir = "<DATA_DIR>"`, `planning_dir = "planning"` (explicit, since there is no repo convention to fall back on), `no_git = true` with the comment "Declared git-less: seals are capture seals, the gate is advisory, derived files live outside this folder (see cache_dir)", and a **commented** `# cache_dir = ...` line explaining the per-machine default and both overrides; a commented `[planning]` block showing the default `non_plan_files = ["agent.md", "readme.md"]` (T3-synced-folder-runtime §2.1) and naming the in-tree routes (`.apv-ignore` marker file in a sub-folder; `apv: ignore` in a file's frontmatter), so a scope agent sees every way to keep non-plan content under `planning/`. **Never write a machine-specific absolute path into the config**: the folder is shared across machines (M7 §2.4; the shim's "zero machine dependency in repo content" ruling, apv-init.sh header step 3). An existing config is respected exactly as today; if it lacks `no_git`, report `ACTION` suggesting the line rather than editing it.
3. **`[requires]` block**: unchanged.
4. **Launcher shim (`<data-dir>/bin/apv`, `./apv` symlink)**: skipped with `report skipped "launcher" "--no-git: run the toolchain via \$APV (see the orientation block)"`. Rationale: the shim's discovery ladder is git-aware (`git -C "$self_dir" rev-parse`), the `serve` default assumes git for its clean-check, and a shared folder should carry the minimum surface. (Q1 below asks whether to revisit.)
5. **`.toolchain-home` pointer**: skipped (machine-specific; nothing must be written into a synced folder that another machine would read as its own).
6. **`.gitignore`**: skipped.
7. **Hooks**: skipped with `report skipped "git hooks" "--no-git: no hooks; run the checks on demand:"` followed by the two on-demand commands: `bash "$APV/scripts/repack-validate.sh"` and `python3 "$APV/scripts/gate-composite.py"`.
8. **CLAUDE.md orientation block**: the same marker pair (`<!-- apv:orientation -->` … `<!-- /apv:orientation -->`) and the same offer/`--accept-claude-md`/heal semantics as the git block, with git-less body text. Required content: the log is the source of truth; **capture after each logical unit of work, sealed with a `commit.recorded` whose `message_first_line` is the block's one-line summary (no git commit to match)**; rebuild after capture (`repack-validate.sh`, `gate-composite.py`); no `/apv-merge`, no hooks; **one writer at a time, conflicted copies of `events.jsonl` are reconciled by hand** (append the copy's new lines in order, delete the copy, record a `decision` in the next block); the plugin requirement paragraph and the not-loaded fallback identical to the git block. The block must not name `git commit --no-verify`, `/apv-merge`, or `.last-capture`. The block text is generated from a second heredoc beside the existing one; the healing logic (T3-claude-md-block-healing) treats both variants as apv blocks by the markers alone, so a folder that later gains a repo heals to the git text and vice versa on re-init.
9. **Report**: the closing next-steps print the on-demand commands and `Then capture your first block: follow the apv-capture skill; in a git-less folder the seal's message_first_line is your block summary.`

### 2.3 Desktop toolchain discovery (optional rung; see T3-synced-folder-runtime Q1)

If ruled in: add to `skills/apv-capture/SKILL.md` §0's ladder and to `gen_launcher` in `apv-init.sh` one rung that searches `"$HOME/Library/Application Support/Claude/local-agent-mode-sessions"/*/*/rpm/plugin_*/` for a `.claude-plugin/plugin.json` whose `"name"` is `exfu-agent-plan-visualiser`, newest mtime wins, written space-safe (a `python3 -c` one-liner using `glob` + `json`, printing one path; never `ls | sort | tail`). Documented as best-effort: session-scoped paths may vanish.

## 3. Scope

### In scope

`apv-init.sh` (flag, preconditions, git-less template, skipped components, orientation variant, report), `commands/apv-init.md` and `skills/apv-init` prose naming the flag, the `using-agent-plan-visualiser` skill's init paragraph, README quickstart (one line: "Folder without git? `apv init --no-git`"), the init sandbox.

### Out of scope

- Auto-detecting git-less folders (declined, M7 §2.3).
- The cache-dir resolver and `no_git` read side — T3-synced-folder-runtime §2.4.
- Backfill (`apv backfill` needs git history by definition).
- `serve.py` behaviour without git (works today; save-summary disabled by its own clean-check).
- Editing any adopting folder.

## 4. Verification (pass criteria)

Extend `plugins/agent-plan-visualiser/tests/init/run-init-sandbox.sh` (or add `tests/gitless/run-gitless-init.sh` in the same `check` shape), all in `mktemp -d` dirs verified not inside a git work tree:

1. No flag, no git → exit 2; stderr contains `pass --no-git`.
2. `--no-git` inside a fresh `git init` dir → exit 2; stderr contains `drop the flag`.
3. `--no-git` in a plain folder → exit 0; `.apv/events.jsonl` (empty), `.apv/schema-version.txt` (`0.3.0`), `.apv-config.toml` containing `no_git = true`, `planning_dir = "planning"`, and a line starting `# cache_dir`; **no** `.apv/bin`, `./apv`, `.gitignore`, `.apv/.toolchain-home`, and no `.git`; stdout contains `skipped` for launcher and git hooks.
4. Re-run → exit 0, every component `ok` or `skipped`, `.apv-config.toml` and `events.jsonl` byte-identical (hash before/after).
5. `--no-git --accept-claude-md` → `CLAUDE.md` has both markers; body contains `capture seal` (or the agreed phrase) and `conflicted cop`; does not contain `--no-verify` or `apv-merge`. Re-run writes nothing (hash).
6. `--no-git --at=pre-push` → exit 2; `--no-git --with-extractor` → exit 2.
7. End to end: after case 3, add `planning/agent.md` (no frontmatter) and `planning/T1-top-level.md` (valid), append a one-block log (entity.created + seal) → `bash "$APV/scripts/repack-validate.sh"` from the folder root with no env exports exits 0 and the data dir gains only `summary.md` (the T3-synced-folder-runtime behaviour, exercised through an initialised folder).

Dogfood regression: `tests/init/run-init-sandbox.sh` existing cases unchanged and green; `tests/gate/run-portability-sandbox.sh` green; `tests/audit-toolchain-paths.sh` green.

## 5. Dependencies

- T3-synced-folder-runtime §2.2 (config-file root finding) and §2.4 (`apv_cache_dir`, `no_git` read side). Sequence after it.
- T3-claude-md-block-healing's marker-pair healing (closed) — reused, not changed.

## 6. Open questions (HITL)

- **Q1 — launcher in git-less folders.** The shim is machine-independent and would give agents `apv refresh` without resolving `$APV`. Skipped here to keep the shared folder's surface minimal and because its ladder and `serve` default assume git. Revisit after the first git-less scope has run for a month? Lean: revisit then, not now.
- **Q2 — orientation for foreign agents.** The therapist-tool scope wrote its own self-contained CLAUDE.md for agents without the plugin. Should the git-less orientation block point at a shipped one-page "git-less mode" doc (a new `philosophies/` or `cheatsheet/` page) so scopes stop hand-writing it? Lean: yes, a `cheatsheet/git-less-mode.md`, one screen, added in this T3 if accepted.

## 7. Build notes (2026-09-03)

Built TDD on `claude/git-less-scopes` after T3-synced-folder-runtime closed: `tests/gitless/run-gitless-init.sh` (7 cases, 31 checks) was written first and observed red on every case that exercises the new behaviour.

**What landed.**

- `scripts/apv-init.sh`: `--no-git` flag (explicit; refused inside a work tree with the toplevel named; the flag-less refusal outside a work tree now names the flag); `--at=…` or `--with-extractor` with `--no-git` exit 2. Root = `pwd -P`. Git-less `.apv-config.toml` template: `[gate]` lists, `[storage]` with `data_dir`, explicit `planning_dir = "planning"`, `no_git = true`, a commented `cache_dir`, a commented `[planning] non_plan_files` block — no machine path, ever (an existing config lacking `no_git` gets an `ACTION` line, not an edit). Launcher shim, `.toolchain-home`, `./apv` symlink and `.gitignore` are reported `skipped`; hooks are `skipped` with the two on-demand commands printed; `[requires]` and the plugin-enablement step are unchanged (the tracked-file warning becomes "travels with the folder"). CLAUDE.md: `claude_md_block()` dispatches to a git-less body behind the same marker pair — capture seals, rebuild after capture, one writer at a time, conflicted-copy reconciliation, the draft gate, the plugin-requirement paragraph; it names no `--no-verify`, `/apv-merge` or `.last-capture`. The healing logic is untouched and keys on the markers, so a folder that later gains a repository heals to the git text on re-init. Next-steps text has a git-less variant.
- Docs: `commands/apv-init.md` (flag, exclusions, the git-less contract in step 4), `skills/using-agent-plan-visualiser/SKILL.md` (init bullet), `README.md` quickstart line, and **`cheatsheet/git-less-mode.md`** — the one-page git-less doc Q2 leaned towards, so scopes stop hand-writing it.
- Not built: §2.3's Desktop discovery rung. T3-synced-folder-runtime Q1 was ruled as its lean (quoted-`APV_HOME` guidance in `apv-capture` §0 and in the git-less block); the glob rung stays unbuilt until a field report asks for it. Q1 here (launcher in git-less folders) stays as the lean: skipped now, revisit after the first git-less scope has run for a month.

**Evidence.** `tests/gitless/run-gitless-init.sh` ALL PASS (including case 7: an initialised folder plus `agent.md` and one plan runs `repack-validate.sh` end to end and the data dir gains only `summary.md`); `tests/init/run-init-sandbox.sh` ALL PASS unchanged (git behaviour untouched); gitless sandbox, validator, gate fixtures, portability, gatecheck, apv-merge, dist, toolchain-paths audit ALL PASS; dogfood `repack-validate` 8/8.

**For the therapist-tool scope.** It was attached by hand on 2026-09-02 and needs no re-attach: add `no_git = true` under `[storage]` in its `.apv-config.toml` (the run works without it because the folder is not in git; the line makes the declaration explicit and survives a future checkout). Running `apv-init.sh --no-git` there would report the config as respected and print that `ACTION` line; nothing else would change. Its hand-written CLAUDE.md section stays; the shipped block is for new scopes.
