---
id: T3-synced-folder-runtime
plan_kind: thematic
tier: 3
t2_parent: T2-storage
milestone: M7-git-less-scopes
status: draft
---

# T3-synced-folder-runtime — the pipeline runs clean from a synced folder with no git

**Status**: Draft (authored 2026-09-03). Awaiting operator acceptance.
**Sits at**: T2-storage theme (the derived-file layer and where it lives, T2-storage §3.1 and §3.7), M7-git-less-scopes milestone. First of the two M7 T3s; T3-git-less-init depends on the resolver built here.

Source material: `planning/scratch/Work Request -- APV on synced folders -- 3 Sep 2026.md` and `planning/scratch/Assessment -- APV on synced folders -- 3 Sep 2026.agent.md` (the verified findings this brief is cut from). Every path below is relative to the repo root unless absolute; `$APV` is the toolchain home `plugins/agent-plan-visualiser` (in the dogfood repo) or the installed plugin root.

---

## 1. Why (condensed; principles by reference)

Three verified defects stop `repack-validate.sh` on a git-less synced folder (assessment §2): the plan-frontmatter validator fails on the ExFu folder descriptor `planning/agent.md`; SQLite and its journal are written into the synced tree, which some mounts cannot lock and which two machines turn into conflicted copies; and `apvlib.repo_root()` falls back to the toolchain's own parent when git is absent, so the folder's `.apv-config.toml` is never read (verified: from the therapist-tool scope root with no env exports, `repo_root` resolved to `/Users/al/Studio/projects/agent-plan-tracker/plugins`, config `{}`). M7 §2.1 and §2.2 rule the direction: keep SQLite, relocate derived files when not in git, use the config file as the root marker. T2-storage §3.1's trust hierarchy (log canonical, cache and projection rebuildable) is what makes relocation safe.

## 2. What

Four builds, in the order that gives the earliest value. Each is independently landable and independently captured.

### 2.1 Validator: validate plans, skip non-plans, still fail broken plans

File: `plugins/agent-plan-visualiser/scripts/validate-plan-frontmatter.sh` (Python heredoc, loop at `for path in sorted(glob.glob(...))`).

Rule (assessment §4 Q3; the request's Q3 is answered "no ignore list"):

- Read the plan-id pattern from the schema already loaded: `schema["properties"]["id"]["pattern"]` (today `^([A-Z]?T[0-3]|M[0-9]+(\.[0-9]+)?)-[a-z0-9][a-z0-9-]*$`). Never hardcode it a second time.
- For each `*.md`: `is_plan_name = re.match(pattern, stem)`; `declares_id = frontmatter parsed and "id" in fm`.
- If neither holds: print `SKIP <path>: not a plan (name is not a plan id and no frontmatter id)` and `continue` **without** incrementing `checked`.
- Otherwise the existing checks run unchanged (no frontmatter → FAIL; YAML error → FAIL; filename ≠ id → FAIL; schema → FAIL).
- Final line stays `all N plan files valid` where N counts validated files only; the existing "nothing validated" guard therefore still trips on a dir holding only `agent.md`.

Companion fix, same rule: `plugins/agent-plan-visualiser/scripts/gate-composite.py`, `check_drift`, the loop `for md in sorted(root_dir.glob("*.md"))`. Before the duplicate-id check, skip a file whose stem does not match the pattern **and** whose `parse_frontmatter(md)` has no `id`. Reason: `agent.md` present in two registered planning roots is otherwise reported as `plan 'agent' present in planning roots ... duplicate plan id`. Read the pattern from `$APV/schemas/0.2.0/plan-frontmatter.schema.json` via the existing `SCRIPT_DIR.parent / "schemas"` convention.

Test: new `plugins/agent-plan-visualiser/tests/validator/run-validator-tests.sh` (same `check`/`FAIL` shape as `tests/gate/run-gate-tests.sh`). Cases, each in a fresh `mktemp -d`, run as `bash ../../scripts/validate-plan-frontmatter.sh ../../schemas/0.2.0/plan-frontmatter.schema.json "$DIR"`:

1. `agent.md` (no frontmatter) + `T1-top-level.md` + `T2-alpha.md` (valid) → exit 0; output contains `SKIP` for `agent.md` and `all 2 plan files valid`.
2. Case 1 plus `T3-broken.md` with no frontmatter → exit 1; output contains `FAIL .../T3-broken.md: no YAML frontmatter`.
3. `agent.md` only → exit 1; stderr contains `nothing validated`.
4. Case 1 plus `notes.md` whose frontmatter is `title: scratch` (no `id`) → exit 0, `SKIP` for `notes.md`.
5. Case 1 plus `t3-foo.md` whose frontmatter declares `id: t3-foo` → exit 1 (schema pattern fails; the file claimed to be a plan).

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
- **Q2 — `no_git` config key.** §2.4 reads an optional `[storage] no_git = true` so a declared git-less folder that happens to sit inside someone's git checkout still keeps derived files out of tree. Confirm the key name and that T3-git-less-init writes it. Lean: yes, `no_git`.
