# APV on a synced folder with no git (git-less mode)

One page for an agent working in a Dropbox-synced ExFu scope (or any plain
folder) that is tracked by agent-plan-visualiser. Everything in the
`apv-capture` skill applies except where this page says otherwise.

## What is different

| Git repo | Git-less folder |
|---|---|
| Seal = the git commit's first line | Seal = the block's one-line summary (a **capture seal**); `author` is the actor, `date` the day |
| Pre-commit guard, pre-push and ref-update gates, `/apv-merge` | No hooks, no merge ceremony: run the two commands below after every capture |
| Derived files beside the log (`.gitignore`/commit absorbs them) | `cache.sqlite`, `projection.json` in a per-machine cache dir **outside** the folder (`~/.cache/apv/<folder>-<hash>/`); `summary.md` stays in the folder |
| Git merges concurrent work | **One writer at a time.** A conflicted copy of `events.jsonl` is reconciled by hand (below) |

## Attach (once, by the operator)

```bash
cd "<folder root>"
bash "$APV/scripts/apv-init.sh" --no-git            # explicit flag; refused inside a git repo
bash "$APV/scripts/apv-init.sh" --no-git --accept-claude-md   # optional: orientation block for cold agents
```

Writes `.apv/events.jsonl` (empty), `.apv/schema-version.txt` and a
`.apv-config.toml` with `no_git = true`, `planning_dir = "planning"` and the
`[requires]` floor. Nothing machine-specific is written into the folder.

## After every capture

```bash
cd "<folder root>"
bash "$APV/scripts/repack-validate.sh"      # validate log + plans, rebuild cache/projection/summary, audits
python3 "$APV/scripts/gate-composite.py"    # integrity composite (advisory here; pending-ceremony warnings are normal while plans are draft)
```

No environment exports: the toolchain finds the folder by its
`.apv-config.toml`. No `sqlite3` command needed. `repack-validate.sh` prints
`cache dir:`; a `WARN stale ...` line means old derived files are still in
`.apv/` — delete them.

`$APV` is the plugin's toolchain directory (`apv-capture` §0). On Desktop or
Cowork, `export APV_HOME="…/Application Support/Claude/…/plugin_…"` **quoted**
(the path has a space) and quote `"$APV"` everywhere.

## Non-plan content under `planning/`

The validator is fail-closed: every `.md` directly under `planning/` must be
a valid plan, except

- `agent.md` and `readme.md` (default `[planning] non_plan_files`),
- a sub-folder holding an empty `.apv-ignore` file (scratch, references),
- a file whose frontmatter says `apv: ignore`.

An unmarked sub-folder gets a one-line `NOTE`; anything else stops the run.

## Conflicted copy of `events.jsonl`

Whoever finds `events (conflicted copy …).jsonl`: append its lines that are
not already in the main file, in their original order; delete the copy; run
the two commands; record what happened in a `decision` event in your next
block. Never auto-merge; never edit existing lines.

## Draft gate, unchanged

`entity.accepted` is a human ruling. Agents never self-accept and never
record `entity.progressed`/`entity.completed` against a draft. Check state:

```bash
printf '%s' "SELECT entity_id, derived_state FROM entities;" | python3 "$APV/scripts/audit-run.py" -
```
