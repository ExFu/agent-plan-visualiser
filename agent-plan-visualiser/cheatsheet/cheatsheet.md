# APV cheatsheet — the operations you actually run

Conventions: `$APV` = the toolchain home (`${CLAUDE_PLUGIN_ROOT}` on a
plugin install; the vendored `agent-plan-visualiser/` dir in this repo's
dogfood case; from any checkout, the newest
`~/.claude/plugins/cache/*/agent-plan-visualiser/*/`). `$DATA` = the data
dir (`APV_DATA_DIR` → `.apv-config.toml` `[storage] data_dir` → `.apv/`).
Run everything from the repo root. Skills are plugin-namespaced
(`agent-plan-visualiser:apv-capture` etc.); when a session lacks them, the
sources are at `$APV/skills/<name>/SKILL.md`.

## Status read (what's the project state?)

```bash
cat "$DATA/summary.md"                 # human-readable rollup (derived)
sqlite3 "$DATA/cache.sqlite" \
  "SELECT entity_id, derived_state FROM entities ORDER BY entity_id;"
```

Stale or missing? Rebuild the whole derived chain:

```bash
bash "$APV/scripts/repack-validate.sh"   # validate → cache → projection → summary → audits
```

## Audit queries

```bash
sqlite3 "$DATA/cache.sqlite" < "$APV/scripts/audit-stalled.sql"                  # live but quiet
sqlite3 "$DATA/cache.sqlite" < "$APV/scripts/audit-orphans.sql"                  # parent closed, child live
sqlite3 "$DATA/cache.sqlite" < "$APV/scripts/audit-fulcrum-without-decision.sql" # missing rationale
```

One entity's full history, or a decision's trace:

```bash
bash "$APV/scripts/timeline-for-entity.sh" <entity-id>
bash "$APV/scripts/trace-decision-history.sh" <entity-id>
```

## Gate on demand (is this state trustworthy?)

```bash
bash "$APV/scripts/gate-check.sh"                    # working data dir vs HEAD
bash "$APV/scripts/gate-check.sh" --ref <committish> # a specific ref, strictly
```

Exit 0 = trustworthy; 1 = blocking defect (repair the log, never override);
2 = unverifiable. Policy lists: `.apv-config.toml` `[gate]`.

## Flow view (see the graph)

```bash
python3 "$APV/scripts/serve.py"    # serves the HTML view over projection.json
```

## Reusable queries

Found yourself regenerating a query? Save it for the next agent:
`$APV/scripts/local/<descriptive-name>.sql`. Lookup order: `scripts/` →
`scripts/local/` → generate-and-save.
