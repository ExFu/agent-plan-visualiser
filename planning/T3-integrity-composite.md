---
id: T3-integrity-composite
plan_kind: thematic
tier: 3
t2_parent: T2-projection
milestone: M3-clean-gate
status: draft
---

# T3-integrity-composite — one question: is this log a trustworthy record?

**Status**: Draft.
**Sits at**: T2-projection theme, M3-clean-gate milestone. Foundation T3 — the other two consume it. Supersedes the `T3-cleanliness-gate-projection` candidate (T2-projection §5).

---

## 1. Why

The gate needs a single check that answers: **can a cold reader trust this log?** Blocking = corruption of the record. Warn = advisory signal, reported but never failing. Visible plan-state (orphans, stalls, open questions) is dashboard work, not gate work — see M3-clean-gate §2 for the framing ruling.

## 2. What

### 2.1 Blocking checks (integrity)

1. **Schema validation** — every event validates against its `schema_version` (reuse the existing validator).
2. **Referential integrity** — `decision.attributes.event_ids` resolve to existing events; `relationship.*` `from_entity_*` (and `from_parent`/`to_parent` for reattached) name entities that exist; lifecycle events name entities that have an `entity.created`.
3. **Sealed tail** — no trailing unsealed run. (Legitimate mid-session on a branch; illegitimate at the boundary, where it means events no commit owns.)
4. **Implementation-on-draft** — `entity.progressed`/`entity.completed` against an entity whose derived state is `draft`. Backstop for the skill's advisory draft gate; honours the implicit-work same-block carve-out.
5. **Resurrection-without-reopen** — lifecycle events on a `closed` entity with no intervening `entity.reopened`. Branch-agnostic, so it also catches cross-branch contradictions after a merge.
6. **Fulcrum-without-decision** — the existing audit, promoted into the composite.

### 2.2 Warn checks (advisory)

- **Frontmatter-vs-event drift** (the M1.2 IOU): live plan-file `t2_parent`/`milestone` vs event-derived parentage from the cache fold.
- **Orphans**, **stalled entities**, **long-running blockers** — existing audits, demoted to warn by the reframe.
- (`verification.claimed` without `.tested` stays deferred pending the verification-ontology overhaul, as in T2-projection §3.4.)

### 2.3 Config — `.apt-config.toml`

Repo root (the config names the data dir, so it cannot live inside it). Parsed with `tomllib` (stdlib, Python ≥3.11). Initial shape:

```toml
[gate]
blocking = ["schema", "referential", "sealed-tail", "implementation-on-draft", "resurrection-without-reopen", "fulcrum-without-decision"]
warn = ["drift", "orphans", "stalled", "long-blockers"]

[storage]
data_dir = ".agent-plan-tracker"
```

`data_dir` slots into M2's resolution order as the never-built middle layer: `APT_DATA_DIR` env var → this file → default. Unknown keys are tolerated (forward compatibility — this file accrues future config).

### 2.4 Implementation + output

`scripts/gate-composite.py`, stdlib-only, reads `events.jsonl` + `cache.sqlite` (rebuilding the cache if stale). Human-readable report: one line per instance with check id, entity/event ids, and a description. Exit 0 = clean (warnings permitted, printed), exit 1 = any blocking instance.

## 3. Scope

### In scope
- The checks (§2.1–2.2), the config file + parser, the report, fixture logs for verification.

### Out of scope
- Enforcement wiring (`gate-check`, hooks, installer) — T3-gate-core.
- The merge procedure — T3-apt-merge-skill.
- Staleness-as-blocking in any form — rejected by design (M3-clean-gate §4).
- Dashboard rendering of warn signals — analyser/flow-view backlog.

## 4. Verification

1. Exit 0 against this repo's current log.
2. Corrupted fixture log (dangling decision ref; unsealed tail; progressed-on-draft; lifecycle-after-close) → exit 1, each instance named correctly.
3. Synthetic drift fixture → warn reported, exit 0.
4. Moving a check between `blocking` and `warn` in `.apt-config.toml` changes behaviour accordingly.

## 5. Dependencies

- 0.3.0 schema + validator (check 1); `cache-build.py` derived states (checks 4–5); M1.2 event-sourced parentage (the drift comparison's event side).

## 6. Open questions

1. **Seal↔commit correspondence** (each seal's `message_first_line` matches a real commit) needs git access. In the composite, in `gate-check`, or deferred? Lean: `gate-check` — boundary context owns git; the composite stays log-only.
2. **Plumbing share with `repack-validate.sh`** — separate entry points, but may invoke the same validator module. Confirm during build.
