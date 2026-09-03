---
id: T3-synced-folder-runtime
plan_kind: thematic
tier: 3
t2_parent: T2-storage
milestone: M7-git-less-scopes
status: active
---

# T3-synced-folder-runtime — the pipeline runs clean from a synced folder with no git

**Status**: Accepted 2026-09-03 by the operator (authored 2026-09-03; revised twice pre-acceptance on the validator rule). Open questions carry stated leans, applied as working defaults until ruled otherwise.
**Sits at**: T2-storage theme (the derived-file layer and where it lives, T2-storage §3.1 and §3.7), M7-git-less-scopes milestone. First of the two M7 T3s; T3-git-less-init depends on the resolver built here.

Source material: `planning/scratch/Work Request -- APV on synced folders -- 3 Sep 2026.md` and `planning/scratch/Assessment -- APV on synced folders -- 3 Sep 2026.agent.md` (the verified findings this brief is cut from). Every path below is relative to the repo root unless absolute; `$APV` is the toolchain home `plugins/agent-plan-visualiser` (in the dogfood repo) or the installed plugin root.

---

## 1. Why (condensed; principles by reference)

Three verified defects stop `repack-validate.sh` on a git-less synced folder (assessment §2): the plan-frontmatter validator fails on the ExFu folder descriptor `planning/agent.md`; SQLite and its journal are written into the synced tree, which some mounts cannot lock and which two machines turn into conflicted copies; and `apvlib.repo_root()` falls back to the toolchain's own parent when git is absent, so the folder's `.apv-config.toml` is never read (verified: from the therapist-tool scope root with no env exports, `repo_root` resolved to `/Users/al/Studio/projects/agent-plan-tracker/plugins`, config `{}`). M7 §2.1 and §2.2 rule the direction: keep SQLite, relocate derived files when not in git, use the config file as the root marker. T2-storage §3.1's trust hierarchy (log canonical, cache and projection rebuildable) is what makes relocation safe.

## 2. What

Four builds, in the order that gives the earliest value. Each is independently landable and independently captured.

### 2.1 Validator: every file in a planning folder is a plan, except a named list of non-plan files

File: `plugins/agent-plan-visualiser/scripts/validate-plan-frontmatter.sh` (Python heredoc, loop at `for path in sorted(glob.glob(...))`).

Scope is unchanged: the validator looks only inside the planning folder(s) resolved through the config (`[storage] planning_dir`, default `planning/`; registered `[projects.<name>] planning_dir` roots). It never scans the rest of the tree.

Rule (revised 2026-09-03 on the operator's steer; supersedes the shape-based rule first drafted — see Q3):

- **Fail-closed.** Every `*.md` in a planning folder is a plan and must validate exactly as today (no frontmatter → FAIL; YAML error → FAIL; filename ≠ id → FAIL; schema → FAIL). The validator learns nothing about what a plan id looks like beyond what the schema already enforces.
- **Three explicit carve-outs, and only these**, checked in this order before any validation:
  1. **Folder marker.** A directory containing a file named `.apv-ignore` is not planning content: nothing under it is read by any toolchain walk of the planning tree. The file may be empty or hold a one-line reason. It is for sub-folders (`planning/scratch/`, `planning/reference/`); a planning **root** carrying the marker is a misconfiguration → exit 2 `planning root <dir> carries .apv-ignore — remove the marker or change planning_dir`.
  2. **Named non-plan files.** `.apv-config.toml` `[planning] non_plan_files = [...]`, matched on basename case-insensitively; default when absent `["agent.md", "readme.md"]` — the ExFu folder-type descriptor (a fixed ExFu convention, so the default is already correct for any ExFu scope and Kat's agent never sets config) and a folder readme. For files that cannot carry frontmatter.
  3. **Self-exclusion in frontmatter.** A file whose frontmatter contains `apv: ignore` excludes itself. For files that can carry frontmatter but are not plans (a note, a template, a checklist an agent parked beside the plans). The key is namespaced so it can never collide with plan fields; ignored files never reach the schema, so the schema does not learn the key. Any other value of `apv:` is a FAIL (`unknown apv: value '<v>'; only 'ignore' is defined`), so a typo cannot silently exclude a plan.
- Skipped files print one line each — `SKIP <path>: .apv-ignore in <dir>` / `listed non-plan file` / `frontmatter apv: ignore` — and are not counted in `checked`; the existing "nothing validated" guard therefore still trips on a dir holding only excluded files.
- Anything else that is not a plan fails loudly, as today. A stray note in `planning/` is a defect to fix or to exclude by one of the three routes, never something the validator guesses about.
- **Sub-folders without a marker.** The validator does not descend into sub-folders (unchanged: plan ids are flat and filename = id, so a plan can only be a direct child of a planning root). A sub-folder **without** `.apv-ignore` prints one notice, `NOTE <dir>/: sub-folder not scanned; add .apv-ignore to record that it is intentionally non-plan content`, and does not affect the exit code (Q4). The notice exists for agents: humans will rarely add these markers, so the tool has to say the option exists.

Helper in `plugins/agent-plan-visualiser/scripts/apvlib.py`: `apv_non_plan_files(repo_root, config_path=None) -> set[str]` (lower-cased basenames; fail-loud on a non-list value, matching `apv_projects`), `apv_dir_ignored(dir) -> bool` (`.apv-ignore` present), and `plan_files(root, non_plan_files) -> (plans, skipped, unmarked_subdirs)` which applies the three carve-outs in order and reads only the frontmatter head for rule 3. Both consumers below call `plan_files`; `.apv-config.toml`'s template in `apv-init.sh` gains a commented `[planning]` block showing the default list and naming the two in-tree routes. `skills/using-agent-plan-visualiser/SKILL.md` gains a short "Non-plan content under planning/" paragraph naming the three routes, since agents, not humans, will be the ones adding these markers.

Multi-root: the validator today reads only `apv_planning_dir` and ignores registered sub-project roots, while `gate-composite.py`'s drift check walks all of `apv_planning_roots`. Iterate `apv_planning_roots` in the validator too (each root labelled in the output), so "the configured planning folders" means the same set to both tools.

Companion fix, same helper: `plugins/agent-plan-visualiser/scripts/gate-composite.py`, `check_drift`, the loop `for md in sorted(root_dir.glob("*.md"))` becomes `for md in plan_files(root_dir, ...)[0]`, so all three carve-outs apply before the duplicate-id check. Reason: `agent.md` present in two registered planning roots is otherwise reported as `plan 'agent' present in planning roots ... duplicate plan id`.

Test: new `plugins/agent-plan-visualiser/tests/validator/run-validator-tests.sh` (same `check`/`FAIL` shape as `tests/gate/run-gate-tests.sh`). Cases, each in a fresh `mktemp -d` containing a `.apv-config.toml` with `[storage] planning_dir = "planning"` unless stated, run as `cd "$DIR" && bash "$APV/scripts/validate-plan-frontmatter.sh"`:

1. `agent.md` (no frontmatter) + `T1-top-level.md` + `T2-alpha.md` (valid) → exit 0; output contains `SKIP .../agent.md: listed non-plan file` and `all 2 plan files valid`.
2. Case 1 plus `T3-broken.md` with no frontmatter → exit 1; output contains `FAIL .../T3-broken.md: no YAML frontmatter`.
3. `agent.md` only → exit 1; stderr contains `nothing validated`.
4. Case 1 plus `notes.md` (any content) → exit 1; output contains `FAIL .../notes.md` (fail-closed: not listed, not a plan).
5. Case 4 with `[planning] non_plan_files = ["agent.md", "notes.md"]` in the config → exit 0; both skipped.
6. Case 1 plus `README.md` → exit 0; skipped by the default list (case-insensitive).
7. Config with `[planning] non_plan_files = "agent.md"` (a string, not a list) → exit 2 with the apvlib fail-loud message.
8. Two roots via `[projects.sub] planning_dir = "sub/planning"`, each holding `agent.md` and one valid plan → exit 0; `all 2 plan files valid`; both roots named in the output.

9. Case 1 plus `checklist.md` whose frontmatter is `apv: ignore` + `title: x` → exit 0; `SKIP .../checklist.md: frontmatter apv: ignore`.
10. Case 1 plus `T3-real.md` whose frontmatter is otherwise valid but carries `apv: ignroe` → exit 1; output contains `unknown apv: value`.
11. Case 1 plus `scratch/` holding `notes.md` (no frontmatter) and `.apv-ignore` → exit 0; `SKIP .../scratch: .apv-ignore`; `notes.md` never mentioned.
12. Case 11 without the marker → exit 0; stdout contains `NOTE .../scratch/: sub-folder not scanned`.
13. `.apv-ignore` placed in the planning root itself → exit 2; stderr contains `planning root`.

Gate side: add `agent.md` (no frontmatter) to `tests/gate/fixture-drift-planning/` and, in `tests/gate/run-gate-tests.sh`, `check_absent "agent.md is not a plan" "plan 'agent'"` after each `run_case` that inspects drift.

### 2.2 Root resolution without git

File: `plugins/agent-plan-visualiser/scripts/apvlib.py`, `repo_root()`.

After `git rev-parse --show-toplevel` fails: starting at `Path.cwd().resolve()`, walk `[cwd] + list(cwd.parents)`; return the first directory containing `.apv-config.toml`. Only then fall back to `Path(__file__).resolve().parents[2]` (unchanged dogfood behaviour). Update the docstring to state the three-rung chain. `APV_DATA_DIR` and `APV_PLANNING_DIR` keep their precedence; they become optional, not required, in git-less folders.

File: `plugins/agent-plan-visualiser/scripts/repack-validate.sh`. Replace `REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"` with the same apvlib resolution: extend the existing python heredoc that prints `DATA_DIR` to print `repo_root` first (two lines, read into two variables), so the shell wrapper and the Python steps agree.

File: `plugins/agent-plan-visualiser/scripts/cache-build.py`, `resolve_blame()`. Before invoking `git blame`, run `git -C <EVENTS.parent> rev-parse --is-inside-work-tree` with stderr suppressed; if it does not print `true`, return `{}` without calling blame. `commit_ref` stays NULL exactly as it does today on failure; the change removes the `fatal: not a git repository` line from stderr.

File: `plugins/agent-plan-visualiser/scripts/gate-composite.py`. Its `--repo-root` default is the module constant `DEFAULT_REPO_ROOT`, a script-relative path (the toolchain's parent), **not** `apvlib.repo_root()` — verified 2026-09-03: run with no flags from a worktree root it reported `error: no events.jsonl in .../plugins/.apv`. `gate-check.sh` masks this by always passing `--repo-root`; a git-less folder following its own docs calls `gate-composite.py` directly and hits it. Change the default to `apvlib.repo_root()` (evaluated inside `main()`, so the cwd at invocation decides). `gate-check.sh` keeps passing the flag explicitly.

No other script changes: `projection-emit.py`, `summary-emit.py`, `serve.py`, `validate-plan-frontmatter.sh` and `validate-events.sh` already resolve through `apvlib.repo_root()` and inherit the fix.

### 2.3 One cache path, audits through Python, CLI dependency dropped

File: `plugins/agent-plan-visualiser/scripts/apvlib.py`. Add:

- `apv_cache_dir(data_dir: Path, repo_root: Path = None, config_path=None) -> Path` — in this build returns `data_dir` (behaviour-preserving); §2.4 gives it the relocation logic. Define it now so every consumer is repointed once.
- `apv_cache_path(data_dir, ...) -> Path` = `apv_cache_dir(...) / "cache.sqlite"`.
- `apv_projection_path(data_dir, ...) -> Path` = `apv_cache_dir(...) / "projection.json"`.

Repoint every assembly site to these (assessment §2.2 list): `cache-build.py:23` (`CACHE`), `projection-emit.py:16-17` (`CACHE`, `OUT`), `summary-emit.py:16` (`PROJECTION`), `gate-composite.py:215` (`cache_path` in `Ctx.cache()`), `serve.py:407` (the `projection.json` read) and `serve.py:216` (route `/data/projection.json` to `apv_projection_path`; every other `/data/*` path stays served from the data dir), `timeline-for-entity.sh:6` and `trace-decision-history.sh:6` (`CACHE` default), `repack-validate.sh:51-53`.

New file: `plugins/agent-plan-visualiser/scripts/audit-run.py`.

```
usage: audit-run.py <file.sql | -> [--cache PATH]
```

Reads the SQL from the file or stdin; drops every line whose first non-blank character is `.` (sqlite3 dot-commands: `.headers`, `.mode`); executes the remainder as one statement with Python's `sqlite3` module against `--cache` or `apvlib.apv_cache_path(apvlib.apv_data_dir(apvlib.repo_root()))`; prints the column names, a separator, and the rows tab-aligned to the widest value per column (a readable stand-in for `.mode column`). Exit 0 when the statement ran, regardless of row count (the audits are advisory; matches today's `sqlite3` exit behaviour); exit 1 with the `sqlite3.Error` text on failure; exit 2 when the cache file is missing (message names `cache-build.py`).

Consumers: `repack-validate.sh` steps `audit-stalled`, `audit-fulcrum-without-decision`, `audit-orphans` become `python3 "$TOOLCHAIN/scripts/audit-run.py" "$TOOLCHAIN/scripts/<name>.sql"`. `timeline-for-entity.sh` and `trace-decision-history.sh` pipe their heredoc SQL into `python3 "$APV/scripts/audit-run.py" -` (resolve `$APV` from the script's own directory, `$(cd "$(dirname "$0")/.." && pwd)`). The three `.sql` files are **not** edited: they stay runnable by a human with the CLI.

Docs in the same build: `plugins/agent-plan-visualiser/README.md` lines 12 and 97 drop `sqlite3` from the dependency list (Python's `sqlite3` module is stdlib and already required by `cache-build.py`). `cheatsheet/cheatsheet.md:24,37-39` and `cheatsheet/worked-examples/find-stalled-plans.md:7` switch to `audit-run.py`. `skills/apv-capture/SKILL.md` §4 and §6.2 replace `sqlite3 "$DATA_DIR/cache.sqlite" "<query>"` with `printf '%s' "<query>" | python3 "$APV/scripts/audit-run.py" -`. `skills/exfu-planning-apv-integration/SKILL.md:16` likewise.

### 2.4 Relocate derived files when the data dir is not in git

File: `plugins/agent-plan-visualiser/scripts/apvlib.py`, `apv_cache_dir` (replacing the §2.3 stub). Precedence, mirroring `apv_data_dir`:

1. `APV_CACHE_DIR` env var (absolute, or relative to `repo_root`).
2. `.apv-config.toml` `[storage] cache_dir` (same).
3. If `[storage] no_git = true` is set (written by T3-git-less-init) **or** the data dir is not inside a git work tree → the per-machine default; else → `data_dir` (git repos unchanged, including the dogfood repo's committed `cache.sqlite`).

"Inside a git work tree" is decided from the **data dir**, not the cwd: take the nearest existing ancestor of `data_dir` and run `git -C <it> rev-parse --is-inside-work-tree`; `true` means in git. This keeps `gate-composite.py`'s `cache()` (which re-exports `APV_DATA_DIR` into a `cache-build.py` subprocess with a different cwd) and the subprocess agreeing on one cache dir.

Per-machine default (assessment §4 Q1): `<base>/apv/<data_dir.parent.name>-<sha256(str(data_dir.resolve())).hexdigest()[:12]>/` where `<base>` is `$XDG_CACHE_HOME` if set else `Path.home() / ".cache"`. Example: `~/.cache/apv/therapist-tool-3f9a1c2b4d5e/`. Create with `mkdir(parents=True, exist_ok=True)`. On `OSError`, fall back to `Path(tempfile.gettempdir()) / "apv" / <same leaf>` and print one stderr line `apv: cache dir <preferred> not writable; using <fallback>`. Never fall back into the data dir; if the temp fallback also fails, raise.

File: `plugins/agent-plan-visualiser/scripts/cache-build.py`. Build into `CACHE.with_name(CACHE.name + ".tmp")`, `conn.close()`, then `os.replace(tmp, CACHE)`. A failed build leaves `cache.sqlite.tmp`, never a hot `-journal`, and readers never see a half-written file. Applies in both modes.

File: `plugins/agent-plan-visualiser/scripts/repack-validate.sh`. After the data-dir resolution, resolve and print `cache dir: <path>` (same heredoc, third line). After the `rebuild SQLite cache` step, a non-failing check: if `"$DATA_DIR/cache.sqlite-journal"` or `"$DATA_DIR/cache.sqlite.tmp"` exists, print `WARN leftover <name> beside events.jsonl — from a failed build; safe to delete` (this is the visible symptom of the failure this T3 fixes; the live therapist-tool scope carries one as of 2026-09-03).

Docs: `README.md` gains a short "Where derived files live" paragraph (data dir in git; `~/.cache/apv/<scope>-<hash>/` otherwise; `APV_CACHE_DIR` and `[storage] cache_dir` overrides; the temp fallback is announced). `skills/apv-capture/SKILL.md` §0: add the sentence "When the session-start orientation line printed `sources at <path>/skills/...`, `APV_HOME` is that path's parent; export it **quoted** — Desktop and Cowork plugin roots contain spaces (`~/Library/Application Support/Claude/...`)", and make the `ls -d ... | sort -V | tail -1` rung space-safe (`find ... -maxdepth 3 -name plugin.json -print0`-style, or a `python3 -c` one-liner). `skills/using-agent-plan-visualiser/SKILL.md:92` names the cache dir as the home of `cache.sqlite` and `projection.json`. `scripts/apv-init.sh` config template (`cat > .apv-config.toml <<TOML`, around line 124): add a commented `# cache_dir = ".apv-cache"` line under `[storage]` with a one-line explanation of the default; T3-git-less-init owns the `no_git` key.

### 2.5 Report back (closing step)

Append `## 7. Build notes (<date>)` to this plan in the house pattern (see `T3-toolchain-portability.md` §7) recording what landed, evidence, and the dated addendum text for `scopes/therapist-tool/ontology/apv-tracking.md` deviation 3: step-3 commands collapse to

```bash
cd "<scope root>"
bash "$APV/scripts/repack-validate.sh"
python3 "$APV/scripts/gate-composite.py"
python3 visualisations/apv/build-static-dashboard.py --minify
```

with the `APV_DATA_DIR`/`APV_PLANNING_DIR` exports, the "fatal: not a git repository is expected" sentence, and the `sqlite3` CLI requirement all deleted, plus a sentence that `cache.sqlite` and `projection.json` now live under `~/.cache/apv/` (path printed by `repack-validate.sh`) and that a leftover `cache.sqlite-journal` in `.apv/` may be deleted. The scope's `build-static-dashboard.py` must gain `--projection <path>` (defaulting to `apvlib.apv_projection_path` when `$APV` is resolvable) — state this in the addendum; the therapist-tool side applies it. **Do not edit anything under `/Users/al/Dropbox/ExFu Library/` from this repo** (M7 §2.5).

## 3. Scope

### In scope

The files named in §2 and their tests. Version bump rides T3-distribution's release convention (a separate `release(T3-distribution)` commit touching `plugin.json` + the log), not this plan.

### Out of scope

- `apv init --no-git` and the git-less CLAUDE.md block — T3-git-less-init.
- Any change to `events.jsonl` handling, schemas, seal semantics, the gate's blocking checks, or conflicted-copy handling.
- Moving `summary.md` or `dashboard.html`.
- The analyser's summaries path (`serve.py`, `DATA_DIR/summaries`) — stays in the data dir.
- Incremental cache rebuilds.
- Editing the therapist-tool scope or any adopting folder.

## 4. Verification (pass criteria)

New `plugins/agent-plan-visualiser/tests/gitless/run-gitless-sandbox.sh`, plus a fixture `tests/gitless/fixture/` holding `planning/` (`T1-top-level.md`, `T2-alpha.md`, `T3-alpha-one.md` with `t2_parent: T2-alpha`, `milestone: M1-first`, `M1-first.md`, and `agent.md` with no frontmatter) and `events.jsonl` (`entity.created` for the four plans with their frontmatter as attributes, `relationship.spawns` T1→T2, T2→T3, T1→M1, `entity.accepted` on `T1-top-level`, one `commit.recorded` seal; all `schema_version: "0.3.0"`; must pass every blocking gate check). The sandbox copies the fixture into `mktemp -d` **verified not inside a git work tree** (`git -C "$T" rev-parse` must fail; abort the test otherwise), writes `.apv-config.toml` with `[storage] data_dir = ".apv"`, `planning_dir = "planning"` and a `[gate]` block that moves `stalled` from `warn` to `blocking`, then asserts:

1. `cd "$T" && bash "$APV/scripts/repack-validate.sh"` with **no** `APV_DATA_DIR`/`APV_PLANNING_DIR` in the environment and with `PATH` filtered to remove every directory containing `sqlite3` → exit 0; stdout contains `SKIP .../agent.md`, `cache dir: `, and `All 8 steps passed`; stderr does **not** contain `fatal: not a git repository`.
2. `ls -A "$T/.apv"` equals exactly `events.jsonl summary.md` (plus `schema-version.txt` if the fixture ships it); the printed cache dir contains `cache.sqlite` and `projection.json` and is not under `$T`.
3. `python3 "$APV/scripts/gate-composite.py"` from `$T` → output lists `stalled` among the blocking checks (proves the folder's `[gate]` is read).
4. Journal case: `touch "$T/.apv/cache.sqlite-journal"`; re-run `repack-validate.sh` → exit 0 and stdout contains `WARN leftover cache.sqlite-journal`.
5. Unwritable cache home: `XDG_CACHE_HOME=/dev/null/apv bash "$APV/scripts/repack-validate.sh"` → exit 0, stderr contains `not writable; using`, and the cache landed under `$(python3 -c 'import tempfile;print(tempfile.gettempdir())')/apv/`.
6. Override: `APV_CACHE_DIR="$T-cache" bash "$APV/scripts/repack-validate.sh"` → cache files appear in `$T-cache`.
7. Broken plan: add `T3-broken.md` (no frontmatter) → `repack-validate.sh` exits 1 at `validate plan frontmatter`.

Regression in the dogfood repo (all must stay ALL PASS / green): `tests/validator/run-validator-tests.sh` (new), `tests/gate/run-gate-tests.sh`, `tests/gate/run-portability-sandbox.sh`, `tests/gate/run-gatecheck-sandbox.sh`, `tests/gate/run-aptmerge-sandbox.sh`, `tests/init/run-init-sandbox.sh`, `tests/dist/run-dist-sandbox.sh`, `tests/audit-toolchain-paths.sh`, and `bash plugins/agent-plan-visualiser/scripts/repack-validate.sh` from the repo root with `git status --porcelain .agent-plan-tracker/cache.sqlite` showing the cache still rebuilt **in place** in `.agent-plan-tracker/`.

Live check (operator, after acceptance and build, before the addendum is sent): from `/Users/al/Dropbox/ExFu Library/scopes/therapist-tool/` with no env exports, `repack-validate.sh` passes and `gate-composite.py` reports the same 11 pending-ceremony warnings as the 2026-09-03 run. Read-only against the scope apart from `summary.md`.

## 5. Dependencies

- Schema `0.2.0/plan-frontmatter.schema.json` id pattern (read, not copied).
- `apvlib.apv_data_dir` / `apv_planning_dir` precedence (T3-configurable-data-dir, T3-integrity-composite §2.3) — extended, not changed.
- T3-install-path-portability's `$APV` resolver in the skills — extended with the Desktop note.

## 6. Open questions (HITL)

- **Q1 — Desktop discovery rung.** Should the `apv-capture` §0 ladder (and the generated shim) also glob `~/Library/Application Support/Claude/local-agent-mode-sessions/*/*/rpm/plugin_*/` filtered by `.claude-plugin/plugin.json` name, or is the quoted-`APV_HOME` guidance in §2.4 enough? Lean: guidance here; the glob rung, if wanted, lands in T3-git-less-init with the shim.
- **Q3 — validator rule (ruled 2026-09-03, recorded here because the first draft chose otherwise).** The first draft skipped files whose name did not match the plan-id pattern and whose frontmatter declared no `id` — fail-open, and it baked the current plan shape into the validator. The operator steered to the fail-closed form in §2.1: scope is the configured planning folders, everything inside is a plan, a named non-plan list (default `agent.md`, `readme.md`) is the only carve-out. The request's own Q3 (rule vs ignore list) is thereby answered "list, with a default that is right for ExFu scopes". Closed.
- **Q4 — the sub-folder notice.** §2.1 prints a one-line `NOTE` for any planning sub-folder lacking `.apv-ignore`. It never fails the run; it exists so agents discover the marker. The dogfood repo's own `planning/scratch/` will print it until a marker is added there. Confirm the notice is wanted, or rule silence for unmarked sub-folders. Lean: keep the notice.
- **Q2 — `no_git` config key.** §2.4 reads an optional `[storage] no_git = true` so a declared git-less folder that happens to sit inside someone's git checkout still keeps derived files out of tree. Confirm the key name and that T3-git-less-init writes it. Lean: yes, `no_git`.

## 7. Build notes (2026-09-03)

Built and landed on `claude/git-less-scopes` in five sealed commits, one per build plus the plan drafting, all TDD (each sandbox case observed red before the code that turned it green).

**Order.** §2.2 (root resolution) went first, before §2.1: the validator's config-driven tests run from a git-less temp folder and need the config-file root rung to find `[planning]`. Value order in the plan was a suggestion; dependency order won.

**What landed, by build.**

- §2.2 — `apvlib.repo_root()` rung 2 (nearest `.apv-config.toml`), `apvlib.in_git_work_tree(path)`, blame skipped outside git, `gate-composite.py --repo-root` default = `apvlib.repo_root()` (the script-relative constant is gone), `repack-validate.sh` resolves root and data dir through one apvlib call. Fixture `tests/gitless/fixture/`, sandbox `tests/gitless/run-gitless-sandbox.sh`.
- §2.1 — fail-closed validator over every registered planning root with the three carve-outs in `apvlib.plan_files()`; `check_drift` shares it; `tests/validator/run-validator-tests.sh` (13 cases); gate fixture gains `agent.md`.
- §2.3 — `apv_cache_dir/apv_cache_path/apv_projection_path`; `scripts/audit-run.py`; all eight assembly sites repointed; `serve.py` routes `/data/projection.json` to the resolved path; no `sqlite3` CLI anywhere on a live surface (README, cheatsheet, worked example, apv-capture §4/§6.2, exfu-planning-apv-integration).
- §2.4 — relocation rule with `no_git` and the temp fallback; `cache-build.py` writes `.tmp` then `os.replace`; `repack-validate.sh` prints `cache dir:`; warnings for a leftover journal/`.tmp` **and** for a stale `cache.sqlite`/`projection.json` still beside the log; README "Where derived files live"; apv-capture §0 space-safe glob + Desktop/Cowork quoted `APV_HOME` guidance (Q1 answered as the lean: guidance, no Desktop glob rung); `using-agent-plan-visualiser` documents the layout and the three non-plan routes; apv-init's config template documents `cache_dir` and `[planning]`.

**Unplanned, found by the tests.**

- `gate-check.sh` ref mode extracts the log into a temp dir and ran the composite with `--data-dir "$TMP"`; under the new rule every gate run would have left a `~/.cache/apv/T-<hash>/` behind (25 appeared during one suite run). Pinned with `APV_CACHE_DIR="$TMP"`; the gatecheck sandbox now asserts an empty isolated cache home.
- `tests/gate/run-gate-tests.sh` computed `REPO_ROOT` one directory short since the 2026-08-10 `plugins/` nesting, so its "real log" case failed on `main` too. Fixed.
- macOS bash 3.2 treats an empty array as unbound under `set -u`; the two ad-hoc scripts use the `${arr[@]+"${arr[@]}"}` idiom.
- Stale derived files: after relocation the scope's old `.apv/cache.sqlite` and `.apv/projection.json` stay behind and a scope-local dashboard builder would read the stale projection. Warned, not deleted (the scope's file to remove).

**Evidence.** Every suite ALL PASS: gitless (32 checks), validator (13 cases), gate fixtures, portability, gatecheck, apv-merge, init, dist, toolchain-paths audit; dogfood `repack-validate` 8/8 with `cache dir: .agent-plan-tracker` (in place). Live, from `/Users/al/Dropbox/ExFu Library/scopes/therapist-tool/` with no `APV_*` exports and no CLI shim: 8/8, `cache dir: ~/.cache/apv/therapist-tool-c6382aeac398`, `agent.md` skipped, leftover-journal warning fired, `gate-composite.py` PASS with the same 11 warnings as the field run. Only `summary.md` changed in the scope.

**Not done here.** The version bump rides T3-distribution's release convention (separate `release(...)` commit). This is a behaviour change on two axes (derived-file location, CLI dependency dropped): suggest **0.8.0**. The scope can adopt the addendum below only once that release is installed on both machines; until then `$APV` must point at a checkout of this branch.

**Q2 / Q4 as built.** `no_git = true` is read (Q2, lean confirmed by the sandbox case "declared git-less folder inside a git checkout"). The unmarked sub-folder NOTE is kept (Q4).

### 7.1 Addendum for `scopes/therapist-tool/ontology/apv-tracking.md` (the scope applies this; APV does not edit the scope)

> **Addendum (2026-09-03, APV ≥ 0.8.0).** Deviation 3 is simplified. The toolchain now finds this folder's root by its `.apv-config.toml` when there is no git, reads the config's `[gate]` and `[storage]` sections, and needs no `sqlite3` command. Step 3 becomes:
>
> ```bash
> cd "<scope root>"
> bash "$APV/scripts/repack-validate.sh"
> python3 "$APV/scripts/gate-composite.py"
> python3 visualisations/apv/build-static-dashboard.py --minify
> ```
>
> The `APV_DATA_DIR`/`APV_PLANNING_DIR` exports are no longer needed. The line "`fatal: not a git repository` is expected" is withdrawn; the run prints no such line. Python still needs `pyyaml` and `jsonschema`; the `sqlite3` command is not required. On Desktop or Cowork, set `APV_HOME` to the plugin path the session-start line reports, **quoted** (it contains a space).
>
> **Deviation 7 amendment.** `cache.sqlite`, its journal and `projection.json` no longer live in `.apv/`. They are written to a per-machine cache directory outside the synced folder (`~/.cache/apv/therapist-tool-<hash>/`; `repack-validate.sh` prints it as `cache dir:`). `events.jsonl`, `schema-version.txt` and `summary.md` stay in `.apv/`; `dashboard.html` stays in `visualisations/apv/`. The old `.apv/cache.sqlite`, `.apv/cache.sqlite-journal` and `.apv/projection.json` are stale: delete them once (the run warns until you do).
>
> **`build-static-dashboard.py`.** It read `.apv/projection.json`. Change `DATA / "projection.json"` to the resolver: `sys.path.insert(0, str(apv / "scripts")); import apvlib; projection = apvlib.apv_projection_path(apvlib.apv_data_dir(ROOT), ROOT)` (after `find_apv()`), and read the events file from `.apv/events.jsonl` as before. Optionally accept `--projection <path>` for a hand-supplied file. Run it after `repack-validate.sh`, as before.
>
> **Non-plan files under `planning/`.** `planning/agent.md` is skipped by default (`[planning] non_plan_files`, default `agent.md`, `readme.md`). A sub-folder is excluded by an empty `.apv-ignore` file inside it; a single note excludes itself with `apv: ignore` in its frontmatter. Anything else under `planning/` must be a valid plan or the run stops.
