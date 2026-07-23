# agent-plan-visualiser (APV)

Event-sourced planning methodology + tracking spine, packaged as a Claude
Code plugin. Git commit history is the one artefact that cannot lie about
what happened: APV keeps an append-only event log extracted at commit time
and derives every view of project state (status, audits, decision traces,
an HTML flow view) from it. Plans stay rich intent; the log records what
actually happened; the gap between the two is signal.

## Quickstart

```text
# 1. Add the exfu marketplace (once per client — Claude Code and Cowork alike),
#    then install the plugin from it:
/plugin marketplace add https://github.com/ExFu/claude-marketplace
/plugin install agent-plan-visualiser@exfu
#    Offline/dev alternative — build a local single-plugin marketplace instead:
#    bash agent-plan-visualiser/scripts/build-bundle.sh   # -> dist/apv-marketplace/
#    /plugin marketplace add <path>/apv-marketplace && /plugin install agent-plan-visualiser@apv

# 2. Attach a project (fresh or existing repo — attaches from now):
/apv-init          # seeds .apv/, writes config, installs the git hooks

# 3. Commit the plugin enablement with your first tracked commit:
git add .claude/settings.json
# Without this, worktree checkouts and fresh clones run the git hooks but
# load none of the apv skills/commands. /apv-init checks and warns.

# 4. Work normally; before each commit:
/apv-capture       # appends the sealed event block; the guard enforces this
```

Land branches on main via `/apv-merge`; the pre-push and
reference-transaction hooks keep an untrustworthy log off main either way.
`git commit --no-verify` is the sanctioned hatch for capture-free trivia.

Skills install plugin-namespaced — in a session's skill list they appear as
`agent-plan-visualiser:apv-capture` etc. If neither that nor `/apv-capture`
is available, the session didn't load the plugin (usually a checkout without
`.claude/settings.json`); the skill sources remain readable at the newest
`~/.claude/plugins/cache/*/agent-plan-visualiser/*/skills/`.

## What's in the box

- **Skills** — `apv-capture` (the extractor: you, before every commit),
  `apv-merge` (landing doctrine), `using-agent-plan-visualiser` (the
  formal orientation/spec floor).
- **Command** — `/apv-init`: idempotent attach/audit/repair of any repo.
  `--with-extractor` opts in to autonomous capture: commits made outside a
  Claude session (editors, CI, collaborators) are extracted by `claude -p`
  at commit time — sealed like any capture, write-side rules enforced in
  code, ambiguity blocks the commit to `needs-review/`.
- **Hooks** — a SessionStart one-liner orients any session in a tracked
  repo (`hooks/hooks.json`); the git hooks (capture-guard, gate adapters,
  optional extractor pair) are installed per-repo by `/apv-init`.
- **Scripts** — the pipeline (`repack-validate.sh`), the boundary gate
  (`gate-check.sh`), audits, timelines, the view server, the bundle
  builder.
- **Multi-project monorepos** — register sub-project planning roots
  (`[projects.<name>] planning_dir = "..."` in `.apv-config.toml`): one
  shared event log, per-entity project membership derived at projection
  time, project filter + badges in the view, per-project summary rollup.
- **Schemas** — the versioned event + plan-frontmatter ontology.
- **Cheatsheet & worked examples** — the operations agents actually run,
  including a CI gate-adapter template.
- **Philosophies** — the grounding documents downstream agents use for
  judgement calls.

## Methodology, in one paragraph

Plans live in `planning/`, tiered by altitude — T1 intent, T2 per-theme
architecture, T3 executable briefs — with milestone plans (`Mn`) sequencing
the same work on an orthogonal axis, and lettered workstreams for crosscuts
and side quests. Plans are append-only: adjust by appending, replace by
superseding, never delete. Every commit is captured as events against a
defined ontology (entities, lifecycle, decisions-as-arc-metadata, blockers,
verification, relationships), sealed by the commit message. The full design
rationale ships in `philosophies/`.

## Requirements

`bash`, `git`, `python3` (stdlib only for the gate; `jsonschema` — or
`check-jsonschema` — for full pipeline validation), `sqlite3` for the cache
and audits.

## License

TBD.
