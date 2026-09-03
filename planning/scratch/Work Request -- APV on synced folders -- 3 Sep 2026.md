---
type: work-request
for: the APV plugin coding agent (exfu-agent-plan-visualiser repo)
from: Alastair, via claude (for al), desktop session
date: 2026-09-03
origin: therapist-tool scope, first desktop run of the git-less pipeline
status: request. The receiving agent analyses, proposes a T3 (or equivalent) in the APV repo's own planning corpus, and implements only after Alastair accepts.
---

# Work request: make APV comfortable on a synced, git-less folder

## Why

APV was born for git repositories. It now also tracks the therapist-tool scope, a Dropbox-synced ExFu folder shared between two people and several agents with no git and no shared conversation. That mode is documented in that scope's `ontology/apv-tracking.md` (git-less mode: capture seals instead of commits, pinned dirs via `.apv-config.toml`, manual conflict reconciliation). It is going to be the normal case for ExFu library scopes, not an exception, so the toolchain should treat "synced folder, no git" as a first-class environment rather than something a session works around by hand.

The first real desktop run of the pipeline on 3 Sep 2026 (see the applied log at `context/icp-research/markbrayne_fold-in_pending_2026-09-03.md`, section 8) surfaced two frictions. Neither corrupted anything. Both forced the operating agent to abandon `repack-validate.sh` and run steps by hand, which is exactly the kind of improvisation the toolchain exists to prevent. Two humans and their agents cannot be expected to remember a workaround.

Binding constraints from the ExFu side, which this request does not reopen:

- ExFu materialises a folder-type by placing an `agent.md` descriptor inside it. A `planning/` folder-type therefore always contains `planning/agent.md`, which has no YAML frontmatter by design (descriptors are stateless reference+delta files).
- The synced folder is the source of truth for humans on any device. `events.jsonl`, `summary.md` and `dashboard.html` must stay in it so state is readable with nothing installed.
- Nothing in the log or the plans changes shape. This is a toolchain change only.

## How (the two problems, and the reasoning behind the preferred direction)

### Problem 1: the plan-frontmatter validator treats the folder descriptor as a broken plan

`scripts/validate-plan-frontmatter.sh` globs `*.md` in the planning dir and fails any file without frontmatter. `planning/agent.md` fails, and because `repack-validate.sh` chains steps with `|| exit 1`, the whole pipeline stops at step 2. Everything after (cache, projection, summary, audits) never runs.

Plain-words version: the checker expects every sheet in the planning drawer to carry a name tag. `agent.md` is the drawer's own label, not a sheet, and it has no tag. The checker sees one untagged sheet and halts.

Considerations for the analysis:

- The right test is "is this file a plan?", not "is this file in the planning dir?". The methodology already defines what a plan looks like: filename equals frontmatter `id`, and ids follow `T1-`, `T2-`, `T3-`, `Mn-` (plus whatever the schema at `schemas/0.2.0/plan-frontmatter.schema.json` allows). A file with no frontmatter and a name that is not a plan id is a non-plan and should be skipped with a one-line notice, not a failure.
- A file with no frontmatter whose name *does* look like a plan id should still fail. Silence there would hide real breakage.
- Prefer a rule in the validator over a per-repo ignore list. A config key (e.g. `[planning] ignore = ["agent.md"]` in `.apv-config.toml`) is acceptable as a secondary escape hatch, but the default should already be correct for an ExFu scope, because Kat's agent will never set config.
- `cache-build.py` and `projection-emit.py` may also glob the planning dir; check they do not choke on, or mis-register, a non-plan file.

### Problem 2: SQLite inside the synced folder

`cache.sqlite` (and its journal) is written into the data dir, which lives inside the synced folder. Three consequences:

1. Some mounts of a synced folder do not support SQLite's locking. The Cowork sandbox's mount of Dropbox returned `sqlite3.OperationalError: disk I/O error` on `cache-build.py`, and left a stale `cache.sqlite-journal` that the sandbox could not remove. On a Mac with the folder local, SQLite works; on a mobile-triggered or sandboxed run it does not.
2. Two machines rebuilding at once produce a Dropbox "conflicted copy" of a throwaway file. Harmless but noisy, and it trains people to ignore conflicted copies, which is dangerous for `events.jsonl` where a conflicted copy matters.
3. `sqlite3` the CLI is assumed by `repack-validate.sh` for the audits. The sandbox had the Python `sqlite3` module but no CLI. The README lists the CLI as standard on macOS and Linux; that is not true of every environment an agent runs in.

The scope's own convention already says `cache.sqlite` and `projection.json` "need not be synced" (apv-tracking.md, deviation 7). The toolchain should make that true by default rather than leaving it to Dropbox settings.

Alastair's question, which the analysis should answer directly: should SQLite be replaced with a filesystem-friendly store? The desktop agent's initial view, to be tested rather than assumed:

- The cache is derived and rebuilt from `events.jsonl` on every run. Its location is the problem, not its format. Moving it out of the synced folder removes consequences 1 and 2 without touching the audits' SQL.
- Replacing SQLite with JSON or a DuckDB file would still be a file that two machines can write concurrently, so it does not fix consequence 2 on its own, and it forces a rewrite of the audit queries and `gate-composite.py`'s warn checks. High cost, partial benefit.
- Consequence 3 (CLI dependency) is real regardless of location and has a cheap fix: run the audit `.sql` files through Python's `sqlite3` module (already required by `cache-build.py`) instead of shelling out. The `.sql` files contain sqlite3 dot-commands (`.mode`, `.headers` or similar) that the module cannot execute; strip or move those.

Preferred direction, subject to the agent's analysis: keep SQLite, relocate the derived files, drop the CLI dependency.

### Design wishes for the relocation

- A resolvable **cache dir** separate from the data dir. Precedence mirroring `apv_data_dir`: `APV_CACHE_DIR` env var, then `[storage] cache_dir` in `.apv-config.toml`, then a default. The default should be *outside* the synced tree when the data dir is not inside a git repo: something like `~/.cache/apv/<stable-id>/` where `<stable-id>` derives from the absolute data dir path (a short hash is fine). Inside a git repo the current behaviour (cache beside events) can stay, since `.gitignore` already handles it.
- `cache.sqlite`, its journal and `projection.json` go to the cache dir. `events.jsonl`, `schema-version.txt`, `summary.md` stay in the data dir. `dashboard.html` stays where the scope's builder puts it (`visualisations/apv/`).
- `summary-emit.py`, `projection-emit.py`, `gate-composite.py`, `serve.py`, `timeline-for-entity.sh`, `trace-decision-history.sh` and `repack-validate.sh` all read the cache path through one function in `apvlib.py`. Today the path is assembled in at least six places (see `grep -n cache.sqlite scripts/*`).
- The scope-local `visualisations/apv/build-static-dashboard.py` in therapist-tool reads `projection.json` from the data dir. It is deliberately tiny and lives outside the plugin; either accept a `--projection` argument or read the same `apvlib` resolver. Note that it also could not find the toolchain without `--apv=` because it searches `~/.claude/plugins/cache/...` and the Cowork sandbox keeps plugins under a different path; a documented `APV_HOME` check exists but the desktop agent tripped on shell quoting. Consider also searching `$CLAUDE_PLUGIN_ROOT` or similar if the harness exposes one.
- If the cache dir does not exist, create it. If it cannot be created, fall back to a temp dir and print where the cache went. Never fall back to the synced folder silently.
- A stale `*-journal` file next to `events.jsonl` should be reported by `repack-validate.sh` as a warning ("leftover journal from a failed build; safe to delete"), because it is the visible symptom of the failure this request fixes.

### Things that should stay as they are

- Git-backed repos: no behaviour change unless opted in.
- `events.jsonl` handling, the schema, the seal semantics, the gate's blocking checks.
- The manual conflicted-copy reconciliation rule in apv-tracking.md. Do not try to auto-merge `events.jsonl`; that is a human-visible event by design.

## What (deliverables, in the order that gives the earliest value)

1. **Validator fix** (problem 1). `validate-plan-frontmatter.sh` skips non-plan files with a notice and still fails plan-shaped files without frontmatter. Add a test case: a planning dir containing `agent.md` (no frontmatter) plus valid plans passes; the same dir plus `T3-broken.md` (no frontmatter) fails. Roughly an hour including the test.
2. **Audits without the sqlite3 CLI** (problem 2, consequence 3). Run the three audit `.sql` files via Python's `sqlite3` module from `repack-validate.sh` (a small `audit-run.py` that takes the SQL path). Keep the SQL files readable by the CLI for humans. Roughly an hour.
3. **Cache relocation** (problem 2, consequences 1 and 2). `apvlib.apv_cache_dir()` with the precedence above; all cache-path consumers use it; default outside the synced tree when not in git; journal-leftover warning. Update `README.md` and the `apv-init` scaffolding so a git-less init writes `cache_dir` into `.apv-config.toml` explicitly. Update the `apv-capture` skill's step-3 instructions. Half a day including tests on a git repo and on a plain folder.
4. **Report back.** A short completion note in the APV repo's own format, plus a dated addendum for `scopes/therapist-tool/ontology/apv-tracking.md` (section "Deviations", item 3) rewriting the step-3 commands once they are simpler. The therapist-tool side will apply that addendum; do not edit that scope from the APV repo.

Verification the receiving agent should run before calling any of this done:

- From a plain folder (no `.git`) with `.apv-config.toml` pinning `data_dir` and `planning_dir`, and with `planning/agent.md` present: `repack-validate.sh` passes end to end, no files other than `summary.md` appear in the data dir, and `gate-composite.py` reports the same warnings as before.
- The same run with `sqlite3` CLI absent from `PATH` still passes.
- From a git repo: existing tests pass unchanged.

## Open questions for Alastair (answer before step 3 starts)

- Q1: default cache location outside git: `~/.cache/apv/<hash>/` or the system temp dir? `~/.cache` survives reboots and keeps the incremental cache useful; temp is simpler and never accumulates.
- Q2: should `projection.json` also leave the synced folder, or stay so the dashboard can be rebuilt on a device with no cache? (Desktop agent's lean: move it; the dashboard already embeds it, and `summary.md` is the human-readable fallback.)
- Q3: is a per-repo ignore list in `.apv-config.toml` wanted at all, or is the plan-shaped-name rule enough?
