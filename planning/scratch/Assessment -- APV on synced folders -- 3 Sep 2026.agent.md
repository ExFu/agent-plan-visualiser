---
type: assessment
of: "Work Request -- APV on synced folders -- 3 Sep 2026.md"
for: Alastair (accept/reject before any implementation), then the APV coding agent
from: claude (for al), Claude Code desktop session, worktree of ExFu/agent-library
date: 2026-09-03
status: proposal. Read-only analysis; nothing in the APV repo, the Agent Library repo or the therapist-tool scope was changed. Implementation waits on Alastair's acceptance and on a T3 in the APV planning corpus (proposed shape in §5).
---

# Assessment: make APV first-class on a synced, git-less folder

## 0. Where the work lives

The request is addressed to the APV plugin coding agent. The APV plugin source is the repo at `/Users/al/Studio/projects/agent-plan-tracker` (remote `ExFu/agent-plan-visualiser`, plugin `exfu-agent-plan-visualiser` 0.7.2, toolchain under `plugins/agent-plan-visualiser/`). This session's checkout is the **Agent Library** repo (`ExFu/agent-library`, worktree `project-improvement-priorities-06f179`), which is a consumer of APV, not its source. Everything below was verified against the APV repo's `main` working tree and the live therapist-tool scope at `/Users/al/Dropbox/ExFu Library/scopes/therapist-tool/`. Implementation belongs in a worktree of the APV repo under its own capture discipline.

## 1. Why (agreeing with the request, with one sharpening)

The request's framing is right: git-less synced folders will be the normal case for ExFu library scopes, so "works around it by hand" is not an acceptable steady state. The Agent Library's own ontology already rules the same way for the library as a whole: `src/shared/substrate/exfu/20260901-1907/ontology.md` (durable/ section) says no SQLite or `-wal`/`-shm` sidecars inside a synced root, because sidecars sync out of order, smart-sync dehydrates files mid-transaction, and conflicted copies have no merge; fast lookups are "built per-machine outside the synced root". The APV change proposed here brings the toolchain into line with a principle the ExFu side has already committed to.

The sharpening: the two frictions in the request are symptoms of **three** gaps, and the third is the one that makes deviation 3 in `ontology/apv-tracking.md` necessary at all.

## 2. Findings (verified)

### 2.1 Problem 1, validator: confirmed

`plugins/agent-plan-visualiser/scripts/validate-plan-frontmatter.sh` globs `*.md` and fails any file without frontmatter. Run read-only against the live scope:

```
OK   .../therapist-tool/planning/T2-platform.md
FAIL .../therapist-tool/planning/agent.md: no YAML frontmatter
```

`repack-validate.sh` chains steps with `|| exit 1`, so cache, projection, summary and audits never run. Matches the request exactly.

Adjacent consumers checked:

- `gate-composite.py` drift check (`check_drift`, ~line 514) globs `*.md` per planning root. `parse_frontmatter` returns `{}` for a frontmatter-less file and the state lookup `states.get("agent")` is None, so `agent.md` is skipped there **today**. One latent defect: the duplicate-plan-id check runs before that skip, so in a multi-project repo with two planning roots, `agent.md` present in both would be reported as `plan 'agent' present in planning roots ... duplicate plan id`. Every ExFu planning folder-type carries `agent.md`, so this will fire the first time two ExFu planning roots are registered. Apply the same is-plan filter there.
- `cache-build.py` and `projection-emit.py` do not glob the planning dir; they only test `(root / f"{eid}.md").exists()` for ids that already appear in the log. Safe.
- `serve.py` routes `/planning/<name>` by filename; safe. The scope's `build-static-dashboard.py` embeds every `planning/*.md` including `agent.md`; harmless (the view only fetches by plan id).

### 2.2 Problem 2, SQLite in the synced folder: confirmed, plus evidence

- The stale journal is present on Alastair's Mac right now: `.apv/cache.sqlite-journal`, 512 bytes, mtime 14:55, beside a `cache.sqlite` at 14:56. It is exactly the visible symptom the request wants warned about.
- Cache path assembly sites (grep `cache.sqlite|projection.json scripts/*`): `cache-build.py:23`, `projection-emit.py:16-17`, `gate-composite.py:215`, `timeline-for-entity.sh:6`, `trace-decision-history.sh:6`, `repack-validate.sh:51-53`, plus `projection.json` readers `summary-emit.py:16` and `serve.py:407` and the `/data/*` static route in `serve.py:216`. Eight files, not six. `apv-capture/SKILL.md` §4 and §6 also hardcode `"$DATA_DIR/cache.sqlite"` for the draft-gate query and sanity check.
- CLI dependency: `repack-validate.sh` shells out to `sqlite3` three times; `timeline-for-entity.sh` and `trace-decision-history.sh` too. The three audit `.sql` files each start with `.headers on` / `.mode column` dot-commands, which Python's `sqlite3` module cannot execute; everything after is plain SQL.
- In the dogfood repo `cache.sqlite` is **git-tracked** (`git ls-files .agent-plan-tracker` lists it), not gitignored as the request assumes. This strengthens, not weakens, "git repos: no behaviour change": leave the in-git location exactly as is.

### 2.3 Gap 3, unstated: repo-root resolution is git-only and falls back to the toolchain's own tree

`apvlib.repo_root()` runs `git rev-parse --show-toplevel` from the cwd and, on failure, returns `Path(__file__).resolve().parents[2]`, i.e. the toolchain's parent. Verified from the scope root with `APV_DATA_DIR`/`APV_PLANNING_DIR` unset:

```
repo_root    : /Users/al/Studio/projects/agent-plan-tracker/plugins
data_dir     : /Users/al/Studio/projects/agent-plan-tracker/plugins/.apv
planning_dir : /Users/al/Studio/projects/agent-plan-tracker/plugins/planning
config read  : {}
```

Consequences:

1. Deviation 3's mandatory `export APV_DATA_DIR=... APV_PLANNING_DIR=...` exists only to paper over this. On a plugin-cache install the fallback points into the plugin cache itself.
2. The scope's `.apv-config.toml` is **never read** in git-less mode, so its `[gate]` lists (and any future `[storage] cache_dir`) are silently ignored; `gate-composite.py` runs on built-in defaults. Adding `cache_dir` to the config without fixing this would have no effect in exactly the environment it is for.
3. `repack-validate.sh` itself falls back to `pwd` for `REPO_ROOT`, so the shell wrapper and the Python steps disagree about where the project is.

Fix: in `repo_root()`, after git fails, walk up from the cwd to the first directory containing `.apv-config.toml` (the config "lives at the repo root" by rule, so it is the natural root marker), then fall back to the toolchain parent for the vendored dogfood case. `repack-validate.sh` should use the same resolution (ask apvlib for the root rather than `pwd`). This is roughly an hour, has no effect in any git repo, and removes deviation 3's environment exports entirely.

Related git-only rough edges, all cosmetic but all "improvisation training":

- `cache-build.py` `resolve_blame()` prints `fatal: not a git repository` to stderr on every git-less run. Detect not-in-git once and skip blame silently (commit_ref stays NULL as it already does).
- `apv-init.sh` exits 2 outside a git work tree, so a git-less scope cannot be attached by the tool at all; the therapist-tool attach was by hand. The request's deliverable 3 ("apv-init writes cache_dir on a git-less init") therefore presumes an init mode that does not exist yet. See §5 for scoping.

### 2.4 Toolchain discovery on Desktop/Cowork

`CLAUDE_PLUGIN_ROOT` is exposed to hooks, not to the session's shell: verified absent from this session's `env`. The `apv-capture` §0 ladder, the generated `bin/apv` shim and the scope's `build-static-dashboard.py` all glob only `~/.claude/plugins/cache/`. The Desktop app keeps plugins under `~/Library/Application Support/Claude/local-agent-mode-sessions/<session>/<session>/rpm/plugin_<id>/` (this session's own orientation hook printed that path). Two things follow:

- The path contains a space (`Application Support`), which is almost certainly the "shell quoting" the desktop agent tripped on. The skill's ladder uses `ls -d ... | sort -V | tail -1`, which is unsafe for such paths, and every downstream `$APV` use must be quoted.
- The `session-orient.sh` hook already prints `sources at $CLAUDE_PLUGIN_ROOT/skills/<name>/SKILL.md` when the plugin root is known. The cheapest reliable fix is doctrinal: the skill's §0 says "if the session-start orientation line printed a sources path, `APV_HOME` is its parent; export it quoted". Optionally add a Desktop rung to the discovery ladders (glob the `rpm/plugin_*/` dirs, filter by `.claude-plugin/plugin.json` name `exfu-agent-plan-visualiser`, newest mtime wins), written space-safe.

## 3. Alastair's direct question: replace SQLite?

**No.** Keep SQLite, relocate the derived files, drop the CLI dependency. Reasoning, tested against the code rather than assumed:

- The cache is fully rebuilt on every run (`cache-build.py` wipes tables; there is no incremental path), so it carries no durability requirement. Its location is the only thing that interacts with the mount or with sync.
- Four surfaces speak SQL against it: the three audits, `gate-composite.py`'s warn checks, the `apv-capture` draft-gate query, and the two ad-hoc query scripts. Replacing the format rewrites all of them for no gain on consequence 2 (any file two machines write is a conflicted-copy candidate).
- Alternatives considered and rejected: a Dropbox-ignore xattr (`com.dropbox.ignored`) on the derived files would fix conflicted copies but not the sandbox mount's missing locking (consequence 1), so relocation is needed anyway; an in-memory build with `VACUUM INTO` would merge cache-build and projection-emit into one process, a larger refactor than the problem warrants; DuckDB adds a dependency and solves nothing SQLite lacks here.
- One cheap hardening worth adding in both modes: build into `cache.sqlite.tmp` in the cache dir and `os.replace()` into place. A failed build then leaves a `.tmp`, never a hot `-journal`, and readers never see a half-written cache.

## 4. Answers to the open questions

**Q1, default cache location outside git.** `${XDG_CACHE_HOME:-~/.cache}/apv/<scope-basename>-<12 hex of sha256(resolved absolute data dir)>/`, e.g. `~/.cache/apv/therapist-tool-3f9a1c2b4d5e/`. Create on demand; if creation fails, fall back to `tempfile.gettempdir()/apv-<same id>/` and print where the cache went; never fall back into the data dir. Reasons: a stable, human-findable path matters more than persistence (the incremental argument is moot today; `gate-composite.py` only uses persistence to skip a rebuild when event counts match), and the basename prefix makes debugging with the ad-hoc scripts possible without computing a hash. `repack-validate.sh` should print the resolved cache dir on every run so nobody has to guess it.

**Q2, does `projection.json` leave the synced folder too?** Yes, move it. It is machine-shaped, already embedded in `dashboard.html`, and `summary.md` is the human fallback. Keeping it buys nothing: a device with no cache can rebuild both from `events.jsonl` in one step. Caveat to state plainly: `summary.md` and `dashboard.html` stay in the folder by design and remain conflicted-copy candidates; moving `projection.json` reduces noise, it does not eliminate it. The two consumers (`summary-emit.py`, `serve.py`) and the scope's `build-static-dashboard.py` (add `--projection <path>` and default it through the resolver) are in the change list already.

**Q3, per-repo ignore list?** Not needed if the validator's rule is: a file is validated when its name is plan-shaped (stem matches the schema's `id` pattern `^([A-Z]?T[0-3]|M[0-9]+(\.[0-9]+)?)-[a-z0-9][a-z0-9-]*$`) **or** its frontmatter carries an `id` key; otherwise it is skipped with a one-line `SKIP <path>: not a plan` notice. This handles `agent.md` (skip), `T3-broken.md` without frontmatter (fail), a stray note with unrelated YAML frontmatter (skip), and a mis-cased `t3-foo.md` that declares an `id` (validate, fail on mismatch). Skipped files do not count toward `checked`, so a planning dir holding only `agent.md` still trips the existing "nothing validated" guard. A config key can be added later if a real case escapes the rule; adding it now creates a parse surface in three places (`apvlib`, the sed-based readers in `capture-guard.sh` and `session-orient.sh`) for a hypothetical.

## 5. Proposed shape in the APV planning corpus

`M6-exfu-integration` and `T3-exfu-planning-integration` are closed (cache `derived_state` = closed), so this does not extend them. `T2-storage` and `T2-packaging` are live. Proposal: one new milestone and two T3s, drafted by the APV agent, accepted by Alastair before any code.

- **`M7-git-less-scopes`** (milestone axis). Definition of done: from a plain synced folder holding `.apv-config.toml`, `planning/agent.md` and an events log, with no git and no `sqlite3` CLI on PATH, `apv init --no-git`, `repack-validate.sh` and `gate-composite.py` run end to end with no environment exports, the data dir gains no files beyond `summary.md`, and the therapist-tool scope's deviation 3 collapses to `cd <scope>; bash "$APV/scripts/repack-validate.sh"`.
- **`T3-synced-folder-runtime`** (t2_parent `T2-storage`, milestone `M7-git-less-scopes`). The request's deliverables 1 to 3 plus gap 3, in value order:
  1. Validator rule from Q3, with the fixture test the request specifies (`agent.md` + valid plans passes; add `T3-broken.md` fails) and the same is-plan filter in `check_drift`'s duplicate-id pass. About an hour.
  2. `repo_root()` walk-up to `.apv-config.toml`; `repack-validate.sh` resolves the root through apvlib; `cache-build.py` skips blame silently when not in git. About an hour. Removes the env exports from deviation 3.
  3. `scripts/audit-run.py <sql> [<cache>]`: strips leading dot-commands, runs the file through Python `sqlite3`, prints a column table. `repack-validate.sh`, `timeline-for-entity.sh` and `trace-decision-history.sh` call it; the `.sql` files stay CLI-readable. About an hour.
  4. `apvlib.apv_cache_dir(data_dir)` with precedence `APV_CACHE_DIR` env → `[storage] cache_dir` → in-git: `data_dir` (unchanged) / not-in-git: Q1 default with temp fallback. In-git detection uses `git -C <data_dir's nearest existing ancestor> rev-parse --show-toplevel`, not the cwd, so subprocesses (`gate-composite.py`'s cache-build call re-exports `APV_DATA_DIR`) agree. All eight files in §2.2 read through it; `cache-build.py` writes via `.tmp` + `os.replace`; `repack-validate.sh` prints the cache dir and warns on a `cache.sqlite-journal` or `cache.sqlite.tmp` beside `events.jsonl` ("leftover from a failed build; safe to delete"). `apv-capture/SKILL.md` §0/§4/§6 read the cache path through `apv_cache_dir` and add the Desktop `APV_HOME` guidance from §2.4. README dependency line drops `sqlite3`. Half a day with a plain-folder test and the existing suites.
- **`T3-git-less-init`** (t2_parent `T2-packaging`, milestone `M7-git-less-scopes`). `apv-init.sh --no-git` (or auto-detected when not in a work tree): writes `.apv-config.toml` with `data_dir`, `planning_dir`, an explicit `cache_dir` comment/value and an advisory `[gate]` note; seeds `events.jsonl`, `schema-version.txt`; installs no hooks and no shim; writes a git-less variant of the CLAUDE.md orientation block (capture seals, rebuild after capture, no `/apv-merge`). Optionally adds the Desktop rung to the shim's and skill's discovery ladders, space-safe. Half a day. Sequenced after `T3-synced-folder-runtime` because it depends on the resolver.

Report-back deliverable 4 (completion note in APV format, dated addendum for `scopes/therapist-tool/ontology/apv-tracking.md` deviation 3) is the closing step of `T3-synced-folder-runtime`; the therapist-tool side applies the addendum, as the request rules.

## 6. Verification the T3 should carry (extending the request's list)

- Plain folder, no `.git`, `.apv-config.toml` pinning `data_dir` and `planning_dir`, `planning/agent.md` present, **no** `APV_DATA_DIR`/`APV_PLANNING_DIR` exported: `repack-validate.sh` passes; only `summary.md` is new in the data dir; `gate-composite.py` reads the folder's `[gate]` lists (prove it by flipping one id to `warn` in the fixture config and observing the change); stderr contains no `fatal: not a git repository`.
- Same run with `sqlite3` removed from PATH: passes.
- Same run with `HOME` pointed at a read-only dir: cache lands in the temp fallback and the path is printed.
- Journal fixture: a zero-byte `cache.sqlite-journal` beside `events.jsonl` produces the warning and the run still passes.
- Multi-project fixture with `agent.md` in two planning roots: no duplicate-plan-id drift finding.
- APV dogfood repo: `tests/gate/run-gate-tests.sh`, `tests/audit-toolchain-paths.sh`, the portability, init and dist sandboxes all pass unchanged; `cache.sqlite` still lands in `.agent-plan-tracker/`.

## 7. Agent Library side (this session's repo)

Nothing is required here for this request; the binding constraints it names (descriptor without frontmatter, synced folder is the source of truth for humans) are already the Agent Library's rules. Two optional follow-ons once M7 lands, both belonging to the planning plugin or the Agent Library rather than APV:

- A shipped `planning` folder-type descriptor template (today `planning/` is scope-custom, defined in `scopes/therapist-tool/ontology/planning.md`) so every APV-tracked scope carries the same `agent.md`.
- A one-line pointer in the `scope-setup` skill: "tracked scopes run `apv init --no-git`; derived files live outside the synced root", echoing the ontology's durable/ ruling.

## 8. Things deliberately left alone

As the request rules: `events.jsonl` handling, seal semantics, schema, blocking gate checks, the manual conflicted-copy rule, and all git-backed behaviour. Also left alone here: the stale journal in the live scope (it is the operator's file to delete; the T3's warning will name it).
