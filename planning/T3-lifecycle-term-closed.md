---
id: T3-lifecycle-term-closed
plan_kind: thematic
tier: 3
t2_parent: T2-ontology
milestone: M1-bootstrap
status: completed
---

# T3-lifecycle-term-closed — Rename the derived lifecycle state `dead` → `closed` everywhere

> **For Claude:** The ontology/vocabulary half of operator-review round 2 (view half: [[T3-button-system-dry]]). One change: rename the derived `derived_state` value `dead` to `closed` across code, projection, view, audits, and the ontology doc. This is a **projection-vocabulary** change, not an event change — see §2. Touches `scripts/cache-build.py`, `scripts/projection-emit.py`, `scripts/summary-emit.py`, `scripts/audit-orphans.sql`, `view/app.js`, `view/style.css`, and [[T2-ontology]]. Shares no files with [[T3-button-system-dry]].

## 1. Why

`dead` is harsh as a user-facing term, and it is already **inconsistent** with the rest of the UI: the Open/Closed lifecycle filter and the summary's "Recently closed" heading both say *closed*, while the header stat and badges say *dead*. Operator decision (2026-06-01): use **`closed`** everywhere, including the internal value — one vocabulary, no code/UI split.

## 2. Why this is safe (no event migration)

`dead` is **never written to the event log**. The log records lifecycle *transitions* — `entity.completed`, `entity.cancelled`, `entity.superseded` — and `cache-build.py` *derives* the terminal state, labelling it `dead`. So renaming the derived label to `closed` changes only derived artefacts (cache, projection, summary, view). `events.jsonl` is untouched; a plain cache rebuild re-derives every entity under the new label. The four state values become: `live` / `dormant` / `closed` / `orphaned` (+ `unknown`).

## 3. Change sites

All occurrences of the derived value `dead` (the string, the count key, the CSS hook), **not** the English word in prose where it still reads naturally:

- **`scripts/cache-build.py`** — `STATE_FOR_EVENT` (or equivalent) maps `entity.completed` / `entity.cancelled` / `entity.superseded` → `"closed"`. Any `entity.reopened` "previously-X" logic updated to read `closed`.
- **`scripts/projection-emit.py`** — the `derived_state == "dead"` branch; the `state_counts` tuple member `"dead"` → `"closed"`; the emitted summary-stat key `dead_count` → `closed_count`.
- **`scripts/summary-emit.py`** — header label `**Dead:**` → `**Closed:**`; the `derived_state == "dead"` filter → `"closed"`; "Recently closed (current dead state)" heading → "Recently closed".
- **`scripts/audit-orphans.sql`** — `WHERE derived_state = 'dead'` → `'closed'` (+ comment wording).
- **`view/app.js`** — header `summary_stats.dead_count` → `closed_count` with label "closed"; the `states` array member `"dead"` → `"closed"`; lifecycle-filter predicates (`derived_state !== "dead"` / `=== "dead"`) → `"closed"`; the filter tooltips "Hide closed (dead) entities" / "Show only closed (dead) entities" → drop the "(dead)" gloss; cascade-exemption comments that say "dead predecessor" may stay as prose or switch to "closed" for clarity; any CSS class hook `"dead"` → `"closed"`.
- **`view/style.css`** — `--color-dead` → `--color-closed`; `.badge.dead` → `.badge.closed`; `.now-badge.dead` → `.now-badge.closed`. Keep the grey hue.
- **`planning/T2-ontology.md`** — the derived-state table row `| dead | completed, cancelled, superseded |` → `| closed | … |`, with a one-line note that this value was renamed from `dead` on 2026-06-01 for operator-facing clarity (historical honesty; the transition events are unchanged).

## 4. Coupling watch
- `dead_count` → `closed_count` is a **projection.json shape change**: app.js must read the new key. Rename producer (projection-emit) and consumer (app.js) together or the header stat breaks.
- The CSS class string emitted by app.js for badges/now-badges must match the renamed `.badge.closed` / `.now-badge.closed` selectors — rename both sides together.
- After code changes, **rebuild** cache → projection → summary so the live artefacts carry `closed`. Grep the repo for any residual `dead` (excluding `deadline`, philosophy prose, and `entity.reopened`'s "previously-dead" doc wording if left as prose) to confirm full coverage.

## 5. Verification (dogfood)
`repack-validate.sh` green; projection `summary_stats` has `closed_count` and no `dead_count`; no entity has `derived_state == "dead"`. In-browser: header reads "… · N closed · …"; closed-entity badges render (grey); the Open/Closed filter still partitions correctly; "Recently closed" summary section populated. Grep shows no stray `dead` state-value references.
