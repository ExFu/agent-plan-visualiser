---
id: T3-backfill-workflow
plan_kind: thematic
tier: 3
t2_parent: T2-ingest
milestone: M5-backfill
status: draft
---

# T3-backfill-workflow — the walk, formalised

**Status**: Draft.
**Sits at**: T2-ingest theme, M5-backfill milestone. Wave 2 — depends on [[T3-origin-provenance-schema]] (emits at 0.4.0). Formalises the M5-lite `scripts/backfill/` skeleton (backfill.py + extract-commit-prompt.md) against the ratified §3.7 doctrine.

---

## 1. Why

The M5-lite orchestrator was deliberately scrappy — pulled forward to surface friction, pre-rename, pre-doctrine, emitting at 0.1.0 with no provenance marking and no anchoring. The ratified representation (T2-ingest §3.7) turns backfill from "generate an events.jsonl" into "append an honest, anchored, marked segment to a possibly-live log". This T3 makes the orchestrator do that.

## 2. What

1. **Emission per §3.7 / §3.12**: every event `origin: "backfilled"` + `attributes.backfill_run`; one block per historical commit in historical order; seals quote the historical message/author/date and carry `attributes.commit_ref`; schema 0.4.0; each block validated before append.
2. **Append-to-live**: the walk targets the repo's real data dir (resolution chain as everywhere) and appends after existing live blocks — no more separate-file generation. Pre-flight confirms the range to mine = commits older than the log's first seal (T2-ingest §3.4 pre-flight updated from "confirm dir is empty").
3. **Chunked commits**: segment lands in chunks ("backfill(bf-<date>-<n>): commits <a>..<b>, <k> blocks"), each chunk captured + sealed normally, transiting the guard; resumable at chunk boundaries via `backfill-state.json`.
4. **Hypothesis emission, no stopping**: fulcrum-ish moments emit candidate-Why hypotheses to the run's output for [[T3-why-triage-pass]]; only genuine ambiguity halts (unchanged protocol, needs-review/).
5. **Extractor brief**: prompt updated to 0.4.0 + the three-tier Why rules (emit recovered decisions with cited sources; never fabricate; hypotheses to the side-channel) + mapping-note section ([[T3-retrospective-mapping-template]]).
6. **Toolchain-home portability**: runs from the plugin install like everything post-M4.

## 3. Scope

### In scope
- `scripts/backfill/backfill.py`, `extract-commit-prompt.md`, `README.md`; the pre-flight; chunking; state; sandbox.

### Out of scope
- The triage pass itself ([[T3-why-triage-pass]]).
- Mapping-note authoring/generation (template T3 / later candidates).
- Live per-commit extraction (T3-autonomous-extractor's ground — see M5 §7 Q3 on sharing the machinery).

## 4. Verification

1. Sandbox repo with synthetic pre-adoption history + a live log: backfill run → segment appended in chunks through the guard, gate green, `cache-build` unfurls states by event time, projection shows history in place.
2. Kill mid-run → `--resume` completes without duplicate blocks.
3. Ambiguity fixture → halts to needs-review, subsequent commits unaffected after skip.
4. Dry-run mode still works (bundle inspection without extraction).

## 5. Dependencies

- T3-origin-provenance-schema — the emission contract.
- T2-extraction §3.4/§3.6 (sequential walk, full prior context); `claude -p` availability.

## 6. Open questions

1. Chunk size: fixed N commits vs token-budget-driven? Lean: fixed N (predictable resumability), configurable.
2. Where do inline hypotheses live pending triage — `needs-review/hypotheses.jsonl` or the state file? Lean: separate hypotheses file, consumed and archived by the triage pass.

## 7. Build notes (2026-07-03)

Both §6 leans ratified: fixed-N chunks (`--chunk-size`, default 25, 0 = caller-managed) and a per-run hypotheses file (`needs-review/hypotheses-<run>.jsonl`, consumed-and-archived by triage).

- **Adoption boundary auto-detected**: mine strictly before the commit whose subject matches the log's *first seal* (`--until` overrides); an empty log or a seal matching no commit falls through to mine-all. Backfill refuses to run without an existing `events.jsonl` — it appends to a live log, it does not create one (init's monopoly stands).
- **Provenance is the orchestrator's word**: `origin`/`backfill_run`/`confidence: derived`/actor(=slugified historical author, `--actor-override` available) forced on every event; seals rebuilt from git ground truth (subject/author/date + `commit_ref`) — the sandbox's canned responses lie about all of it and are overridden. Write-side rules mirror the live extractor's stance in code: `entity.accepted`/`analysis.*` rejected, one-seal-last, fresh unique UUIDs, 0.4.0 schema validation failing closed.
- **`--limit N` takes the most recent N of the range** (unchanged M5-lite semantics — sample near the boundary first, where extraction quality matters most); resume state is per-commit, so mixed limit/full runs interleave safely without duplicates.
- **Chunk commits transit the guard** (stamp + commit `backfill(<run>): commits a..b, k blocks`) and the ref-update gate mid-run — historical seals resolve against reachable commits, so a mid-segment state is green by construction.
- The extraction prompt rewritten to 0.4.0 with the three-tier Why rules (recovered must cite; unrecoverable becomes a tier-3 hitl-question with candidates; "an unrecoverable Why is NOT ambiguity"); the mapping note rides the bundle verbatim when present. README rewritten as pure instruction (no progress state).
- Sandbox: `tests/backfill/run-backfill-sandbox.sh` — boundary detection, chunking, ground-truth override, resume-without-duplicates, gate + unfurl on the mined log, injection rejection, dry-run purity. ALL PASS with a stubbed model; the first live run is the M5 §4 rehearsal (operator-approved, sandbox copy).
