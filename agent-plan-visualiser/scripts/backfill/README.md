# Backfill — extracting events from an existing project's git history

This directory contains the M5-lite (and M2-lite) machinery: an extraction prompt and an orchestrator that, given a target git project, walks its history commit-by-commit and produces a `.agent-plan-tracker/events.jsonl` for it.

**Status**: pre-production. Pulled forward from M2/M5 because Alastair wants to dogfood the tracker against a client project before the formal pre-commit hook lands. Expect to iterate on the prompt as real commits expose extraction quality gaps.

## Files

- **`extract-commit-prompt.md`** — the system prompt the extraction agent runs with. Briefs the ontology, input/output contract, classification rules, ambiguity-halt protocol.
- **`backfill.py`** — orchestrator. Walks git log, builds per-commit bundles, invokes `claude` CLI per commit, validates returned events against `schemas/0.1.0/events.schema.json`, appends to events.jsonl.
- **`README.md`** — this file.

## Prerequisites

- `claude` CLI on PATH (you have this if you're using Claude Code).
- Python 3, plus `jsonschema` installed *for the python3 your shell uses*:
  ```bash
  python3 -m pip install --user jsonschema
  ```
- Target project must be a git repo.

## Quickstart: dry-run against a project

```bash
# Dry-run: build bundles + print to stdout; do NOT call Claude. Useful for
# verifying the bundles look sensible before burning API tokens.
python3 agent-plan-visualiser/scripts/backfill/backfill.py \
  --project-path /path/to/client-project \
  --limit 5 \
  --dry-run \
  --verbose
```

You'll see 5 commit bundles printed. Each contains: commit metadata, diff, files touched, planning files (post-commit content), prior log (initially empty).

## Real run (against a sample)

```bash
# Real run on the last 20 commits, writing into the project's own .agent-plan-tracker/
python3 agent-plan-visualiser/scripts/backfill/backfill.py \
  --project-path /path/to/client-project \
  --limit 20 \
  --verbose
```

Output:
- `<project>/.agent-plan-tracker/events.jsonl` — extracted events (appended)
- `<project>/.agent-plan-tracker/backfill-state.json` — resume state
- `<project>/.agent-plan-tracker/needs-review/` — ambiguity halts, validation failures, parse errors (if any)

## Resumability

If the orchestrator fails on a specific commit (ambiguity halt, validation error, timeout), state is saved. You resolve the issue (manually edit events.jsonl, or update the prompt, or skip the commit), then re-run with `--resume`:

```bash
python3 .../backfill.py --project-path ... --resume
```

Already-processed commits are skipped.

## After backfill: run the pipeline

Once `events.jsonl` exists for the target project, use the standard pipeline against it:

```bash
cd /path/to/client-project
# Adjust paths so the agent-plan-visualiser scripts find the right files
# (until M4 packaging, you'll invoke them with explicit paths)
python3 /path/to/agent-plan-visualiser/agent-plan-visualiser/scripts/cache-build.py
python3 /path/to/agent-plan-visualiser/agent-plan-visualiser/scripts/projection-emit.py
python3 /path/to/agent-plan-visualiser/agent-plan-visualiser/scripts/summary-emit.py
cat .agent-plan-tracker/summary.md
```

The HTML view works the same way — open via `python3 -m http.server` from the client project root.

## Workflow

1. **Dry-run first.** Inspect a handful of bundles to see what the extractor will be given. Spot any obvious bugs (e.g. the project has a non-standard `planning/` directory, or commit messages reference plans by an alias).
2. **Run on a small sample** (`--limit 5` or `--limit 10`). Inspect the output events.jsonl. Are events sensible? Are entities being created correctly?
3. **Tune the prompt** if needed — add project-specific aliases or rules. Re-run.
4. **Run at scale.** Drop `--limit`, run on full history. Monitor progress; halt-and-resume as needed.
5. **Validate.** Run the cache build + projections. The summary.md should show a sensible project state.

## Known limitations (M5-lite)

- **Per-commit cost.** Each commit = one Claude call with the full bundle (commit diff + touched planning files + prior log delta + ontology prompt). At ~5-15K input tokens per call, a 100-commit project is ~1-2M tokens total. Be deliberate.
- **No parallel commits.** Sequential per design (each commit needs the prior log to resolve references). Could parallelise with care but adds complexity.
- **Prompt iteration is manual.** No A/B testing or formal eval harness. Read the output; if quality drops, revise the prompt.
- **No retrospective mapping note yet.** For projects that diverge meaningfully from T1/T2/T3, you'll get quality drop. Add aliases inline in the prompt for now; formal mapping note lands in proper M5.
- **Output isn't `entity.completed` aware for milestones.** If your project marks milestones differently, extract may miss completions. Manually inspect / patch.

## Troubleshooting

**`claude` CLI not found.** Install Claude Code (your shell needs the `claude` command). Or use `--dry-run` to skip extraction.

**`jsonschema not installed for /usr/bin/python3`.** Run the exact install command the script prints (uses `sys.executable -m pip install`). Don't trust `pip install`-alone — your shell's `pip` may install to a different python.

**Extraction agent emits prose instead of JSON.** Prompt isn't being followed. Inspect the response in `needs-review/*-parse-error.md`. Tighten the "output JSON only" rule in `extract-commit-prompt.md`. Re-run.

**Ambiguity halts on most commits.** The prompt's confidence threshold is too high, OR the project really is too ambiguous for this v0 extractor. Inspect halts, see if there's a common pattern, add explicit rules.

**Slow runs.** Sequential by design. Use `--limit` to test scope. Real-world: a 50-commit backfill at ~20s/commit is ~17 min. Plan accordingly.

## Forward path (proper M5)

This M5-lite version sidesteps:
- The mapping-note generator agent (`mapping-note-agent-design` inbox item)
- Snapshot integration (no snapshots yet, just full prior log up to recent N events)
- A formal extraction-input-contract spec
- The per-commit pre-commit hook flow (this is one-shot batch, not commit-time triggered)

Each of those is its own future T3 under T2-ingest / T2-extraction. The current scripts here are deliberately scrappy — meant to surface real-world friction before formalisation.
