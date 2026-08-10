# ExFu Agent Plan Visualiser (APV)

Event-sourced planning methodology and tracking spine, packaged as a Claude
Code plugin. Git commit history is the one artefact that cannot lie about what
happened: APV keeps an append-only event log extracted at commit time and
derives every view of project state — status, audits, decision traces, an HTML
flow view — from it. Plans stay rich intent; the log records what actually
happened; the gap between the two is signal.

## Install

```text
/plugin marketplace add ExFu/exfu-marketplace
/plugin install exfu-agent-plan-visualiser@exfu
```

Then attach a project with `/apv-init`.

**Before you install**, note APV needs `python3` (3.11+), `sqlite3`, and the
`jsonschema` Python package — the extractor fails closed without it:

```bash
python3 -m pip install --user jsonschema
```

Full quickstart, requirements, and command reference:
**[`plugins/agent-plan-visualiser/README.md`](plugins/agent-plan-visualiser/README.md)**.

## What's in this repo

| Path | What it is |
| --- | --- |
| [`plugins/agent-plan-visualiser/`](plugins/agent-plan-visualiser) | The plugin itself — skills, commands, hooks, scripts, schemas. This is what the marketplace installs. |
| [`WHITEPAPER.md`](WHITEPAPER.md) | The reasoning behind event-sourced planning — why commit history is the trustworthy substrate. |
| `planning/` | This project's own tiered plan corpus (T1–T3 + milestones). |
| `.agent-plan-tracker/` | This repo's own event log — APV tracks itself. |

The repo is both the **source** of the plugin and a **consumer** that dogfoods
it: every commit here is extracted into the log by APV's own hooks.

## License

Proprietary — see [LICENSE](LICENSE). This repository is public for
distribution convenience; publication does not grant an open-source licence.
Redistribution enquiries: al@exfu.ai
