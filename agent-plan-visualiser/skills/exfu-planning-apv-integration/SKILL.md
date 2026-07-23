---
name: exfu-planning-apv-integration
description: APV's optional integration with the ExFu planning approach - the capture provider that records multi-model delegated work into the event log (draft-gate checks before a delegate runs, actor-attributed capture of accepted work after). Loaded by an ExFu delegation core via its provider manifest (.exfu/providers.toml), or read directly. Use when delegating implementation/audit/review work in any project tracked by agent-plan-visualiser (has a .agent-plan-tracker/events.jsonl or APV_DATA_DIR equivalent).
---

# exfu-planning-apv-integration — APV's capture provider for ExFu delegation

This is APV's side of its pairing with the ExFu planning approach: how work handed to a foreign delegate (e.g. Codex via the `exfu-delegate` core) enters an APV-tracked record. It is an **optional** integration — APV works fully without it, and the ExFu delegation core works fully without APV; this skill is the seam between the two, wired only through the neutral provider manifest.

You define what to check before a delegate runs, and how accepted delegated work is captured after. You extend — never replace — this plugin's `/apv-capture` discipline: load the sibling skill `${CLAUDE_PLUGIN_ROOT}/skills/apv-capture/SKILL.md` for event mechanics (event types, block order, seal, validation, `.last-capture`); this skill adds only the delegation-specific rules on top.

## 1. Pre-delegation checks (the core calls this at preflight)

1. Resolve `DATA_DIR` by APV doctrine, in order: `APV_DATA_DIR` env var → the repo's committed `.apv-config.toml` `[storage] data_dir` (most repos set this; e.g. `.apv` or `.agent-plan-tracker`) → the historical default `.agent-plan-tracker/`. The resolved dir must contain `events.jsonl`; otherwise this repo isn't APV-tracked — tell the core to proceed without capture.
2. **Draft gate (implement mode only)**: the brief's subject plan must not be `draft` —
   `sqlite3 $DATA_DIR/cache.sqlite "SELECT derived_state FROM entities WHERE entity_id='<id>';"` (stale/no cache → scan the log tail for the entity's lifecycle events). `draft` → REFUSE the delegation; the operator must run the acceptance ceremony first. Never self-accept. Audit and review modes are exempt — judging a draft is legitimate; implementing against one is not.
3. **Protected paths**: declare `$DATA_DIR/events.jsonl` (and `$DATA_DIR/` generally) to the core's integrity snapshot via the manifest's `[integrity] protected_paths`. The delegate must never touch the record — the core enforces this by snapshot comparison; you supply the paths.

## 2. Post-return capture (after the orchestrator has independently accepted the work)

Only capture work the orchestrator verified — never on the delegate's say-so, and never for rejected rounds.

- **Attribution**: delegated implementation events (`entity.progressed`, `entity.completed`) carry `actor: "codex"` (or the delegate CLI's name). Verification events for checks the **orchestrator** ran carry the operator handle. Ceremonies (`entity.accepted`) are the operator's only — a delegate or orchestrator never self-issues them.
- **Verdicts** (audit/review mode): summary text, not new event types — an `entity.extended` on the audited plan (or the plan owning the reviewed work) whose summary states delegate, model, verdict, and finding counts. Keep the full verdict JSON in `.exfu/returns/` (disposable); the summary is the durable record.
- **Round trail**: the capture block's summaries should state rounds used and transport (e.g. "delegated via clink/codex, 2 rounds").
- **Seal and commit are the orchestrator's**: one sealed block per accepted unit, `commit.recorded` last, validate (repack pipeline), write `.last-capture`, then the orchestrator (never the delegate) commits with the seal's exact first line.

## 3. Registration

At install, ensure the target repo's `.exfu/providers.toml` carries:

```toml
[providers]
capture = "exfu-planning-apv-integration"

[integrity]
protected_paths = [".apv/events.jsonl", ".apv/"]
```

(Adjust the paths to the repo's resolved `DATA_DIR` — e.g. `.agent-plan-tracker/` in APV's own dogfood repo.)
