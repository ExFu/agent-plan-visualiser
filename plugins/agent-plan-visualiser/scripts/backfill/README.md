# Backfill — mining pre-adoption git history into the event log

History becomes record, honestly: backfilled events append at the record
tail, anchor to their historical commits, carry `origin: "backfilled"` + a
run id (repudiable as a cohort), and never fabricate a Why. Doctrine:
`planning/T2-ingest.md` §3.7; ontology: `planning/T2-ontology.md` §3.12.

## Files

- **`backfill.py`** — the orchestrator: walks commits before the adoption
  boundary oldest-first, one extraction per commit, write-side rules
  enforced in code, chunked guard-transiting commits, resumable.
- **`extract-commit-prompt.md`** — the extraction agent's brief (0.4.0,
  three-tier Why rules).
- **`triage-emit.py`** — the deterministic half of `/apv-triage-why`:
  converts operator rulings into recollected decisions and closes answered
  questions, append-only.
- **`retrospective-mapping-template.md`** / **`-example.md`** — the
  translation brief for non-native projects; the "known pivots" section
  feeds the triage pass pre-armed.

## The flow

```bash
# 0. The target must be attached (backfill appends to a live log):
#    /apv-init in the target repo.

# 1. Inspect what the extractor will see (free, writes nothing):
python3 <toolchain>/scripts/backfill/backfill.py \
  --project-path /path/to/repo --dry-run --limit 5

# 2. Non-native project? Author the mapping note first:
#    copy retrospective-mapping-template.md to <data-dir>/retrospective-mapping.md
#    and fill it in (see -example.md for a worked shape).

# 3. Rehearse on a small sample, then run for real:
python3 .../backfill.py --project-path /path/to/repo --limit 10
python3 .../backfill.py --project-path /path/to/repo            # full range

# 4. One triage sitting converts the queued Why hypotheses:
#    /apv-triage-why   (wraps triage-emit.py; seal the triage commit as usual)

# 5. Look at it:
python3 <toolchain>/scripts/serve.py      # ghosted history, provenance filter
```

The adoption boundary is auto-detected (commits strictly before the log's
first sealed commit); `--until <ref>` overrides. `--resume` continues past
halts once repaired. Chunk commits (`backfill(<run>): commits a..b, k
blocks`, every `--chunk-size` blocks) transit the capture guard normally.

## Guarantees (code, not prompt)

- Every event: `origin: "backfilled"`, `attributes.backfill_run`,
  `confidence: "derived"`, schema-validated at 0.4.0, fresh unique UUIDs.
- Every seal: the historical commit's real subject/author/date +
  `commit_ref` — the model's word is never trusted for ground truth.
- `entity.accepted`, `analysis.*` and `project.assigned` are rejected
  unconditionally.
- Attribution is mechanical (multi-project repos): plan creations under a
  named sub-project's planning root, and planless creations whose commit
  touches a named project's `dirs` carve-outs, are stamped
  `attributes.project` by the orchestrator from git ground truth — the
  model never asserts membership. Historical layouts that diverge from
  today's carve-outs are corrected at triage via the bulk
  `project.assigned` pattern
  (`cheatsheet/worked-examples/assign-entity-to-project.md`).
- Unrecoverable Whys become open `hitl-question`s with candidates (tier 3),
  collected to `<data-dir>/needs-review/hypotheses-<run>.jsonl` for triage —
  a decision is only ever recovered (cited source) or recollected (operator
  testimony at triage).
- Ambiguity halts the run to `needs-review/`, never auto-resolves.

## Cost notes

Sequential by design (each commit sees the prior log). One `claude -p`
call per commit, ~5–15k input tokens each; `APV_EXTRACT_MODEL` picks the
model, `APV_EXTRACT_TIMEOUT` bounds a call. Dry-run first; sample second;
full range deliberately.
