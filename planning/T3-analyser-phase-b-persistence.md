---
id: T3-analyser-phase-b-persistence
plan_kind: thematic
tier: 3
t2_parent: T2-analyser
milestone: M6-analyser
status: draft
---

# T3-analyser-phase-b-persistence — Persistence, new event types, server wrapper, opportunistic derived

> **For Claude:** Implement this plan task-by-task. See T2-analyser §3.2 (new event types), §3.3 (storage convention), §3.4 (server endpoints), §3.5 (clean-tree guard), §3.6 (summary chain), §3.13 (opportunistic derived). Phase A modules already exist in `agent-plan-tracker/view/app.js` (Settings, Estimator, ContextBuilder, AnalyseClient, SidebarAnalyser, AnalyseError) — extend, don't rewrite.

**Goal:** Saved analyser summaries persist as `analysis.live-summary` events in `events.jsonl`, with the freeform body in `.agent-plan-tracker/summaries/<entity_id>-<event_id>.md`. A new local-bind-only Python server wrapper exposes three endpoints (`/api/clean-check`, `/api/save-summary`, `/api/invalidate-summary` — the last is a stub deferred to Phase D). Primary analysis on a focal entity opportunistically emits derived summaries for the 1-hop dependents Claude touched; server-side enforces supersession rules (primary > derived). Reload preserves saved summaries — they're loaded back into the sidebar as the default view of the entity, with a "Regenerate" affordance.

**Architecture:** Phase A's pure-browser analyser stays. New layer is the server wrapper (Python `http.server` subclass) and the persistence flow. Schema version bumps to `0.2.0` to mark the catalogue grew; per-event `schema_version` policy documented below.

**Tech stack:** Python 3 stdlib only (no Flask), vanilla JS, fetch API. No new build step. No new dependencies.

---

## 1. Why this T3

Phase A proved the loop works: programmatic context bundles produce useful summaries at predictable cost. But without persistence, every analysis is a throwaway — the project gains nothing across sessions. Phase B closes that gap. Summaries become first-class events, the chain becomes durable project state, and the analyser starts behaving like the rest of the tracker (event-sourced, replayable, projection-derived).

Phase B is also the first time the project gets a server with any code in it. The clean-tree guard, save endpoint, and derived-summary supersession rules all have to live somewhere with filesystem + git access; the browser can't do that safely. Establishing the wrapper pattern here sets the precedent for any future server-side concerns (e.g. M3 cleanliness gates) without sneaking a heavier framework in.

Schema-version-wise: this is the first ontology evolution after the v0.1.0 bootstrap. T2-analyser §7 Q7 explicitly nominated `0.2.0` for clarity over additive-at-0.1.0 — picked here for that reason. Old events stay valid against the new schema (the new schema is strictly additive plus a version-string change in `const`).

## 2. Out of scope

- **Cascade invalidation logic.** The `/api/invalidate-summary` endpoint is reserved as a stub in Phase B (returns 501 with structured payload). Full cascade walking + `analysis.invalidated` emission lands in Phase D.
- **Flow-view rendering of saved summaries as distinct nodes.** Phase B persists and reloads them into the sidebar; the workstreams-flow lifeline rendering is Phase C.
- **Global / bulk mode + prompt caching.** Phase E.
- **Schema-version migration of existing events.** Existing v0.1.0 events stay v0.1.0; only newly-emitted events under the new ontology carry `0.2.0`. See §5.1 "schema-version policy".
- **Streaming responses.** Blocking calls only (T2-analyser §7 Q5).
- **Auth on the server.** The local-bind (127.0.0.1) is the moat — T2-analyser §3.4.

## 3. Acceptance criteria

1. **Schema additions land.** `agent-plan-tracker/schemas/0.2.0/events.schema.json` exists, mirrors v0.1.0 plus two new oneOf branches: `analysis_live_summary` and `analysis_invalidated`. The top-level `schema_version` const becomes `0.2.0`. The active schema pointer (`.agent-plan-tracker/schema-version.txt`) becomes `0.2.0`. `validate-events.sh` defaults updated to the new path. Old events at `schema_version: 0.1.0` continue to validate (the schema is still backward-compatible for the existing 23 event-type branches, because the v0.2.0 file *replaces* the v0.1.0 file as the authoritative schema and the `schema_version` const is loosened from `0.1.0` to an `enum: ["0.1.0", "0.2.0"]`).
2. **Cache-build recognises new event types.** `cache-build.py` accepts `analysis.live-summary` and `analysis.invalidated` events without erroring. Existing rebuild step passes. New `summaries` table populated (one row per `analysis.live-summary` event, with valid/invalid flag derived from later `analysis.invalidated` events).
3. **Projection surfaces latest-valid-summary per entity.** `projection.json` grows a `latest_summary_by_entity` map: `entity_key → {event_id, source, model, structured, freeform_path, ts}` for the most recent valid `analysis.live-summary` per entity (primary preferred over derived where both are current).
4. **Server wrapper exists and serves.** `agent-plan-tracker/scripts/serve.py` runs from the repo root, binds to `127.0.0.1:8765` by default, and serves the existing static tree (so `http://localhost:8765/agent-plan-tracker/view/index.html` works exactly as before). `python3 agent-plan-tracker/scripts/serve.py` is the new dev-serve command; `python3 -m http.server 8765` continues to work for clean-check-less browse mode.
5. **`GET /api/clean-check` returns clean state.** Empty `git status --porcelain` → `{"clean": true}`. Dirty → `{"clean": false, "dirty_files": ["M planning/...", "?? .agent-plan-tracker/..."]}`.
6. **`POST /api/save-summary` round-trips a primary save.** Browser POSTs `{event, freeform_md, derived: [{event, freeform_md}, ...]}`. Server: (i) re-runs clean-check; refuses with 409 if dirty. (ii) writes `.agent-plan-tracker/summaries/<entity_id>-<event_id>.md` for primary + each derived. (iii) appends events to `events.jsonl` (primary first, then derived). (iv) returns `{ok: true, primary_event_id, derived_event_ids: [...], line_positions: {...}}`. Validates each event against the v0.2.0 schema before append; refuses with 422 on validation failure.
7. **`POST /api/invalidate-summary` is a stub returning 501.** Body shape documented; server returns `{ok: false, code: 501, message: "Not implemented yet; Phase D"}` with HTTP 501. Browser must not call this in Phase B; route is reserved.
8. **Server-side supersession rules enforced on save.** When `POST /api/save-summary` arrives for entity E:
    - The primary's `supersedes_summary_event_id` is set to the previous live summary on E (primary or derived) if one exists; null otherwise. Browser sends a hint, but server is authoritative — it re-reads the events log to be sure.
    - Each derived summary's `supersedes_summary_event_id` is set to the previous `derived` summary on its entity if one exists. **A derived NEVER supersedes a primary.** Server zeroes out any client-supplied `supersedes_summary_event_id` that points at a `primary`.
9. **Browser-side save flow.** A "Save" button appears below the Phase A result render. Disabled until a pre-flight `/api/clean-check` succeeds (re-run on Save click; show clear error if dirty). On success, the result panel transitions to "saved summary" mode showing `Saved · <event_id>` badge, the same structured cards, the freeform body, and a "Regenerate" button.
10. **Reload restores saved summary as the default sidebar view.** After save + page reload, clicking LIVE on the entity shows the saved summary by default (with `Regenerate` and `Show timeline` controls), not the timeline. Fetched from `projection.latest_summary_by_entity` plus a runtime fetch of the freeform markdown file.
11. **Opportunistic derived caching works end-to-end.** Primary analysis on T2 with N children → save flow produces N+1 events (1 primary + N derived); N+1 markdown files; reload shows all N+1 saved. Running primary on a child correctly supersedes its previous derived (its sidebar now shows a primary, with the older derived dropped from the latest-valid-summary projection).
12. **The system prompt instructs Claude to emit derived summaries.** Browser-side `ContextBuilder.buildSystemPrompt()` updated to ask Claude for a `derived_summaries` array in the JSON output, alongside the existing primary structured fields. AnalyseClient's `_parseStructured` extended to lift derived entries out. Each derived has `entity_id`, `entity_type`, and the same four structured fields.
13. **`repack-validate.sh` passes end-to-end on the branch.** All 8 steps green; cache + projection rebuild; no schema validation failures. Includes the new test events emitted by this plan's `entity.created` + completion arcs, plus any hand-rolled `analysis.live-summary` test events.
14. **No regressions on Phase A surfaces.** Settings modal, cost dialog, ephemeral run path still work when the user explicitly clicks "Regenerate" or runs analysis on an entity with no prior save.

## 4. Files to create / modify

### Create

- `agent-plan-tracker/schemas/0.2.0/events.schema.json` — copy of 0.1.0 with two new branches and schema_version policy loosened to enum.
- `agent-plan-tracker/schemas/0.2.0/cache.schema.sql` — copy of 0.1.0 + new `summaries` table.
- `agent-plan-tracker/schemas/0.2.0/plan-frontmatter.schema.json` — straight copy from 0.1.0 (no plan-frontmatter changes in Phase B).
- `agent-plan-tracker/scripts/serve.py` — server wrapper. ~200 lines, stdlib only.
- `.agent-plan-tracker/summaries/.keep` — directory marker (server creates dir on first save, but commit a marker so the directory is tracked).
- `planning/T3-analyser-phase-b-persistence.md` — this plan.

### Modify

- `.agent-plan-tracker/schema-version.txt` — `0.1.0` → `0.2.0`.
- `agent-plan-tracker/scripts/cache-build.py` — accept `analysis.live-summary` + `analysis.invalidated`; materialise into a new `summaries` table; compute valid/invalid flag. **Do not touch the relationship-derivation function** (the orchestrator is fixing frontmatter-implied edges separately — leave a TODO if your additions sit close to it).
- `agent-plan-tracker/scripts/projection-emit.py` — emit `latest_summary_by_entity` map; bump emitter's `SCHEMA_VERSION` + `ONTOLOGY_VERSION` to `0.2.0`.
- `agent-plan-tracker/scripts/validate-events.sh` — default schema path updated to 0.2.0.
- `agent-plan-tracker/scripts/validate-plan-frontmatter.sh` — default schema path updated to 0.2.0.
- `agent-plan-tracker/scripts/repack-validate.sh` — schema paths updated (if hard-coded anywhere).
- `agent-plan-tracker/view/app.js`:
  - `ContextBuilder.buildSystemPrompt()` — augment with derived-summaries instructions.
  - `ContextBuilder.buildPerEntityBundle()` — populate `prior_summary` from `projection.latest_summary_by_entity` if present.
  - `AnalyseClient._parseStructured()` — lift `derived_summaries` array out.
  - `SidebarAnalyser._renderResult()` — add Save button + status badge; wire to a new `PersistenceClient` module.
  - **New module `PersistenceClient`** — wraps fetch to `/api/clean-check` and `/api/save-summary`; surfaces errors via the existing AnalyseError taxonomy (or a sibling `PersistenceError`).
  - **New module `SavedSummary`** — given an entity, load latest-valid-summary from `projection.latest_summary_by_entity` and the freeform-markdown file; render as the default sidebar view (replacing the timeline) with `Regenerate` + `Show timeline` controls.
  - `showLiveStatus(entity)` — branch on saved-summary presence: if present, render saved-summary view; else current timeline + "Analyse outstanding".
- `agent-plan-tracker/view/index.html` — optional small additions: a status banner for the clean-check state (e.g. small "Working tree dirty — saves disabled" banner near the toolbar). Lower priority; skip if it complicates the basic flow.
- `agent-plan-tracker/view/style.css` — Save button + badge + saved-summary-view styles. Reuse Phase A colour palette.
- `.claude/launch.json` — `runtimeArgs` updated from `["-m", "http.server", "8765"]` to `["agent-plan-tracker/scripts/serve.py"]`. Port stays 8765.
- `planning/T2-analyser.md` — append an addendum to §3.4 noting Phase B chose the stub-then-flesh-out approach for `/api/invalidate-summary` (Phase D will implement).
- `planning/M6-analyser.md` — Phase B's T3 reference updated from `(tbw)` to `drafted` → `complete` as work progresses.

## 5. Implementation steps

### Step 1 — Plan + events arc (this T3 + its `entity.created`)

- Write this plan to `planning/T3-analyser-phase-b-persistence.md` with the frontmatter above.
- Append events to `.agent-plan-tracker/events.jsonl` (in this commit):
  - `entity.created` for `T3-analyser-phase-b-persistence` (entity_type `plan`, attributes carrying full frontmatter — `id`, `plan_kind: thematic`, `tier: 3`, `t2_parent: T2-analyser`, `milestone: M6-analyser`, `status: draft`, `title`, `summary`).
  - `relationship.spawns` from `M6-analyser` to this T3 (Phase A's `entity.created` for M6 already exists per the latest events — confirm and skip if it's already attached differently).
  - `relationship.spawns` from `T2-analyser` to this T3 (T2-parent → T3-child arc).
  - `commit.recorded` closing the commit.
- All events use `schema_version: "0.2.0"` after the schema change below — sequencing within this T3 is: do the schema bump *before* emitting the new events, so the very first commit on this T3 already validates against v0.2.0. Decision: bundle the schema bump and the T3 authoring in commit #1.

**Verification:** `bash agent-plan-tracker/scripts/repack-validate.sh` passes 8/8. `entities` table has a row for `plan:T3-analyser-phase-b-persistence` with attrs including `t2_parent: T2-analyser`, `milestone: M6-analyser`.

### Step 2 — Schema v0.2.0 directory + branches

Author `agent-plan-tracker/schemas/0.2.0/events.schema.json` based on v0.1.0:

- Bump `$id` URL segment to `0.2.0`.
- Loosen the top-level `schema_version` property:
  ```json
  "schema_version": { "type": "string", "enum": ["0.1.0", "0.2.0"] }
  ```
  Rationale: old events on disk stay valid; new events emit at `0.2.0`. Documented in §5.1 below.
- Append to the `entity_type` enum: nothing — `analysis.*` events don't carry a new entity_type. They carry `entity_id` of the focal entity (already a `plan` or `inbox-item`), so the existing entity_type values cover it.
- Add to the top-level `oneOf` array: `{"$ref": "#/$defs/analysis_live_summary"}` and `{"$ref": "#/$defs/analysis_invalidated"}`.
- Add the two `$defs` branches:

```json
"analysis_live_summary": {
  "type": "object",
  "required": ["entity_type", "entity_id"],
  "properties": {
    "type": { "const": "analysis.live-summary" },
    "entity_type": { "enum": ["plan", "inbox-item"] },
    "attributes": {
      "type": "object",
      "required": ["model", "source", "structured", "freeform_path"],
      "properties": {
        "model": { "type": "string", "minLength": 1 },
        "source": { "type": "string", "enum": ["primary", "derived"] },
        "origin_summary_event_id": { "type": ["string", "null"] },
        "supersedes_summary_event_id": { "type": ["string", "null"] },
        "structured": {
          "type": "object",
          "required": ["outstanding", "blocked", "recently_changed", "next_move"],
          "properties": {
            "outstanding": { "type": "array", "items": { "type": "string" } },
            "blocked": { "type": "array", "items": { "type": "string" } },
            "recently_changed": { "type": "array", "items": { "type": "string" } },
            "next_move": { "type": "string" }
          }
        },
        "freeform_path": { "type": "string", "pattern": "^\\.agent-plan-tracker/summaries/.+\\.md$" },
        "context_event_id_range": {
          "type": "object",
          "properties": {
            "from": { "type": ["string", "null"] },
            "to": { "type": ["string", "null"] }
          }
        },
        "estimated_input_tokens":  { "type": ["integer", "null"] },
        "estimated_output_tokens": { "type": ["integer", "null"] },
        "actual_input_tokens":     { "type": ["integer", "null"] },
        "actual_output_tokens":    { "type": ["integer", "null"] },
        "prompt_cache_hit_ratio":  { "type": ["number", "null"] }
      }
    }
  }
},
"analysis_invalidated": {
  "type": "object",
  "required": ["entity_type", "entity_id"],
  "properties": {
    "type": { "const": "analysis.invalidated" },
    "entity_type": { "enum": ["plan", "inbox-item"] },
    "attributes": {
      "type": "object",
      "required": ["target_event_id", "reason"],
      "properties": {
        "target_event_id": { "type": "string" },
        "cascades_to_event_ids": {
          "type": "array",
          "items": { "type": "string" }
        },
        "reason": { "type": "string" }
      }
    }
  }
}
```

Notes:
- `analysis.live-summary`'s `entity_type` is restricted to `plan` and `inbox-item` per T2-analyser §3.10 + §8 (live entities only; the analyser fires against plan/inbox-item kinds, not blocker/hitl-question/implicit-work — those have their own lifecycle).
- `freeform_path` pattern enforces the `.agent-plan-tracker/summaries/<file>.md` convention (T2-analyser §3.3).
- Token / cost telemetry fields are nullable to allow partial captures (e.g. estimator missed, but actuals exist).
- `context_event_id_range` is included now (Phase D needs it for cascade computation) but marked all-nullable so Phase B can leave them null without invalidation.

Also copy/adapt:
- `agent-plan-tracker/schemas/0.2.0/cache.schema.sql` — add the `summaries` table DDL (see Step 3).
- `agent-plan-tracker/schemas/0.2.0/plan-frontmatter.schema.json` — straight copy from 0.1.0; bump `$id`.

Update `.agent-plan-tracker/schema-version.txt` to `0.2.0`. Update `validate-events.sh`, `validate-plan-frontmatter.sh`, `repack-validate.sh`, `cache-build.py`, `projection-emit.py` references to point at the new schema directory.

#### 5.1 Schema-version policy on emitted events

- **All events emitted on or after the v0.2.0 cutover use `schema_version: "0.2.0"`** — including events that aren't of the two new types (e.g. an `entity.completed` on an existing plan). Rationale: per-event schema_version means "validated against this schema", and after the cutover the active schema is 0.2.0.
- **Events already on disk at v0.1.0 are not retroactively rewritten.** They stay at `0.1.0`. The v0.2.0 schema accepts both via the loosened `schema_version` enum.
- **Mid-flight edge case:** Phase B's own commit #1 includes `entity.created` events for the new T3, which need to use `0.2.0` (because the schema cutover happens in this commit). Step 1's sequencing handles this: the schema lands first, then the new events validate cleanly.

### Step 3 — Cache-build extension

Modify `cache-build.py`:

1. **Recognise the new event types in the materialisation switch.** Add:
   - `analysis.live-summary` does NOT update entity `state` (the focal plan's lifecycle is unaffected by summary events). It IS appended to `event_type_sequence` and updates `last_event_id`.
   - `analysis.invalidated` similarly does not touch state; appended to sequence; updates last_event_id.
   - Do this in the existing entities-materialisation loop. The `STATE_FROM_EVENT` map needs no entries (analysis events are state-neutral).

2. **Create the `summaries` table.** DDL in `agent-plan-tracker/schemas/0.2.0/cache.schema.sql`:
   ```sql
   CREATE TABLE IF NOT EXISTS summaries (
     event_id                       TEXT PRIMARY KEY,
     entity_type                    TEXT NOT NULL,
     entity_id                      TEXT NOT NULL,
     source                         TEXT NOT NULL,           -- 'primary' | 'derived'
     model                          TEXT NOT NULL,
     origin_summary_event_id        TEXT,
     supersedes_summary_event_id    TEXT,
     freeform_path                  TEXT NOT NULL,
     structured                     TEXT NOT NULL,            -- JSON blob
     valid                          INTEGER NOT NULL DEFAULT 1,
     invalidated_by_event_id        TEXT,
     created_commit_recorded_event_id TEXT
   );
   CREATE INDEX IF NOT EXISTS idx_summaries_entity ON summaries(entity_type, entity_id);
   CREATE INDEX IF NOT EXISTS idx_summaries_valid ON summaries(valid);
   ```
   Rationale for picking a table over an entities-flag: summaries are first-class records with their own ids, supersession edges, and validity flag. They don't map cleanly onto entity state. A dedicated table also keeps the `entities` table semantics clean (it's about plan/inbox/blocker/HITL/implicit-work lifecycles, not analyser outputs).

3. **Insert one row per `analysis.live-summary` event.** Pull the attributes, set `valid = 1`. Decision: do NOT walk the chain inside cache-build to compute supersession-based invalidation. Supersession is "newer wins" — the projection layer (Step 4) sorts that out by event_id-on-line-position ordering. `valid` flips to 0 only when an `analysis.invalidated` event references this row in `target_event_id` or includes it in `cascades_to_event_ids[]`.

4. **Apply `analysis.invalidated` events to flip `valid → 0`.** Second pass after all summary rows inserted: walk all `analysis.invalidated` events; for each, set `valid = 0` and `invalidated_by_event_id = ev["event_id"]` on the target plus each id in `cascades_to_event_ids[]`.

5. **Leave the existing relationship-derivation logic untouched.** The orchestrator's parallel work on frontmatter-implied edges (t2_parent / milestone) is in a different function path. If a change to `analysis.*` event handling sits near it, add a `# TODO(phase-b): see orchestrator note about frontmatter-implied edges` comment and confine the diff to the additive switch.

**Verification:** Append a hand-rolled `analysis.live-summary` event to `events.jsonl`; rebuild cache; query `SELECT * FROM summaries`; row present with valid=1. Append an `analysis.invalidated` targeting that row; rebuild; row now has valid=0.

### Step 4 — Projection layer

Modify `projection-emit.py`:

1. Bump `SCHEMA_VERSION` and `ONTOLOGY_VERSION` constants to `"0.2.0"`.

2. Compute `latest_summary_by_entity`:
   ```python
   latest_summary_by_entity = {}
   for row in conn.execute(
       "SELECT * FROM summaries WHERE valid = 1 ORDER BY rowid ASC"
   ):
       key = f"{row['entity_type']}:{row['entity_id']}"
       prev = latest_summary_by_entity.get(key)
       # Primary beats derived; otherwise later-rowid wins.
       if (prev is None
           or (row["source"] == "primary" and prev["source"] == "derived")
           or (row["source"] == prev["source"])):  # later same-source wins
           latest_summary_by_entity[key] = {
               "event_id": row["event_id"],
               "source": row["source"],
               "model": row["model"],
               "freeform_path": row["freeform_path"],
               "structured": json.loads(row["structured"]),
               "supersedes_summary_event_id": row["supersedes_summary_event_id"],
               "origin_summary_event_id": row["origin_summary_event_id"],
           }
   ```
   The `(row["source"] == prev["source"])` branch handles the "later same-kind supersedes" case; the primary-beats-derived branch handles cross-kind ordering. A derived **never** dislodges a primary, regardless of recency.

3. Include in the projection dict alongside `entities` / `relationships` / `decisions`.

**Verification:** With test summary events in the log, `projection.json` carries `latest_summary_by_entity` with the expected keys. Primary-after-derived wins. Derived-after-primary does NOT win (test by hand-crafting events in that order; cache+projection rebuild; assert primary still in map).

### Step 5 — Server wrapper (`agent-plan-tracker/scripts/serve.py`)

Author the server. Approximate shape:

```python
#!/usr/bin/env python3
"""serve.py — local dev server for the agent-plan-tracker view + analyser endpoints.

Subclass of http.server.SimpleHTTPRequestHandler that:
- Serves the existing static tree (view/, .agent-plan-tracker/) unchanged.
- Adds three local-only endpoints under /api/.
- Binds to 127.0.0.1 only (no external exposure).
- Holds zero credentials, makes zero outbound calls.

Usage: python3 agent-plan-tracker/scripts/serve.py [--port 8765]
"""
import argparse
import json
import os
import re
import subprocess
import sys
import uuid
from http.server import SimpleHTTPRequestHandler, HTTPServer
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
EVENTS = REPO_ROOT / ".agent-plan-tracker/events.jsonl"
SUMMARIES_DIR = REPO_ROOT / ".agent-plan-tracker/summaries"
SCHEMA_PATH = REPO_ROOT / "agent-plan-tracker/schemas/0.2.0/events.schema.json"


def git_clean_check():
    try:
        out = subprocess.check_output(
            ["git", "status", "--porcelain"], cwd=REPO_ROOT, text=True
        )
    except subprocess.CalledProcessError as e:
        return False, [f"git status failed: {e}"]
    if not out.strip():
        return True, []
    return False, [line.rstrip() for line in out.splitlines()]


def load_schema():
    with open(SCHEMA_PATH) as f:
        return json.load(f)


def validate_event(event, schema):
    """Returns (ok, error_message). Uses jsonschema if available; else basic shape checks."""
    try:
        from jsonschema import validate, ValidationError
    except ImportError:
        # Minimal shape checks if jsonschema isn't installed. Catches the obvious cases.
        required = {"event_id", "type", "actor", "confidence", "schema_version", "attributes"}
        missing = required - set(event.keys())
        if missing:
            return False, f"missing required keys: {missing}"
        return True, None
    try:
        validate(instance=event, schema=schema)
        return True, None
    except ValidationError as e:
        return False, e.message


def latest_summary_for(entity_type, entity_id):
    """Walk events.jsonl backwards; return the most recent analysis.live-summary event
    for this entity, OR None. Also returns its source so caller knows."""
    if not EVENTS.exists():
        return None
    last = None
    with open(EVENTS) as f:
        for raw in f:
            try:
                ev = json.loads(raw)
            except json.JSONDecodeError:
                continue
            if ev.get("type") != "analysis.live-summary":
                continue
            if ev.get("entity_type") != entity_type or ev.get("entity_id") != entity_id:
                continue
            last = ev
    return last


class APTHandler(SimpleHTTPRequestHandler):
    schema_cache = None

    def _send_json(self, code, body):
        payload = json.dumps(body).encode("utf-8")
        self.send_response(code)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def _read_json_body(self):
        length = int(self.headers.get("content-length", "0"))
        raw = self.rfile.read(length) if length else b""
        if not raw:
            return None, "empty body"
        try:
            return json.loads(raw.decode("utf-8")), None
        except json.JSONDecodeError as e:
            return None, f"json parse: {e}"

    def do_GET(self):
        if self.path == "/api/clean-check":
            clean, dirty = git_clean_check()
            self._send_json(200, {"clean": clean, "dirty_files": dirty})
            return
        # Fall back to static-file serving.
        return super().do_GET()

    def do_POST(self):
        if self.path == "/api/save-summary":
            return self._handle_save_summary()
        if self.path == "/api/invalidate-summary":
            # Phase D will implement. Reserve the route now.
            self._send_json(501, {
                "ok": False,
                "code": 501,
                "message": "Not implemented yet; Phase D",
            })
            return
        self._send_json(404, {"ok": False, "message": f"unknown endpoint {self.path}"})

    def _handle_save_summary(self):
        clean, dirty = git_clean_check()
        if not clean:
            self._send_json(409, {
                "ok": False,
                "code": 409,
                "message": "Working tree dirty — commit or stash first.",
                "dirty_files": dirty,
            })
            return
        body, err = self._read_json_body()
        if err or body is None:
            self._send_json(400, {"ok": False, "message": err or "no body"})
            return
        primary = body.get("event")
        primary_md = body.get("freeform_md", "")
        derived_list = body.get("derived", []) or []
        if not isinstance(primary, dict):
            self._send_json(400, {"ok": False, "message": "missing event"})
            return

        schema = APTHandler._schema()

        # Enforce supersession rules + freeform_path generation server-side.
        if not self._prepare_event(primary, source_required="primary", schema=schema, errors_out := []):
            self._send_json(422, {"ok": False, "message": "primary failed validation", "errors": errors_out})
            return
        prepared_derived = []
        for d in derived_list:
            errs = []
            ev = d.get("event")
            md = d.get("freeform_md", "")
            if not isinstance(ev, dict):
                self._send_json(400, {"ok": False, "message": "derived item missing event"})
                return
            if not self._prepare_event(ev, source_required="derived", schema=schema, errors_out=errs):
                self._send_json(422, {"ok": False, "message": f"derived failed validation: {ev.get('entity_id')}", "errors": errs})
                return
            prepared_derived.append((ev, md))

        # Write markdown files + append events. Atomicity is best-effort: if append
        # fails after files are written, the files become orphans (cleanup is manual).
        # Future work: stage to a tmp location and rename atomically.
        SUMMARIES_DIR.mkdir(parents=True, exist_ok=True)

        def write_md(event, md_text):
            path = REPO_ROOT / event["attributes"]["freeform_path"]
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(md_text or "(empty)")

        write_md(primary, primary_md)
        for ev, md in prepared_derived:
            write_md(ev, md)

        # Append all events.
        with open(EVENTS, "a") as f:
            f.write(json.dumps(primary, separators=(",", ":")) + "\n")
            for ev, _ in prepared_derived:
                f.write(json.dumps(ev, separators=(",", ":")) + "\n")

        self._send_json(200, {
            "ok": True,
            "primary_event_id": primary["event_id"],
            "derived_event_ids": [ev["event_id"] for ev, _ in prepared_derived],
        })

    @classmethod
    def _schema(cls):
        if cls.schema_cache is None:
            cls.schema_cache = load_schema()
        return cls.schema_cache

    def _prepare_event(self, ev, source_required, schema, errors_out):
        """Mutates ev in place. Validates after preparation. Returns True/False; appends to errors_out."""
        # Required scaffolding
        ev.setdefault("event_id", str(uuid.uuid4()))
        ev.setdefault("type", "analysis.live-summary")
        ev.setdefault("actor", "analyser")
        ev.setdefault("confidence", "explicit")
        ev.setdefault("schema_version", "0.2.0")
        attrs = ev.setdefault("attributes", {})
        attrs.setdefault("source", source_required)
        if attrs["source"] != source_required:
            errors_out.append(f"expected source={source_required}, got {attrs['source']}")
            return False

        entity_type = ev.get("entity_type")
        entity_id = ev.get("entity_id")
        if not entity_type or not entity_id:
            errors_out.append("missing entity_type/entity_id")
            return False

        # Compute freeform_path from event_id.
        attrs["freeform_path"] = f".agent-plan-tracker/summaries/{entity_id}-{ev['event_id']}.md"

        # Supersession: re-derive server-side.
        prev = latest_summary_for(entity_type, entity_id)
        if attrs["source"] == "primary":
            # Primary always supersedes the most recent summary on E (primary or derived).
            attrs["supersedes_summary_event_id"] = prev["event_id"] if prev else None
        else:
            # Derived: only supersedes prior DERIVED on E. Never primary.
            if prev and prev.get("attributes", {}).get("source") == "derived":
                attrs["supersedes_summary_event_id"] = prev["event_id"]
            else:
                attrs["supersedes_summary_event_id"] = None

        # Validate
        ok, msg = validate_event(ev, schema)
        if not ok:
            errors_out.append(msg)
            return False
        return True


def run(port=8765, host="127.0.0.1"):
    os.chdir(REPO_ROOT)
    server = HTTPServer((host, port), APTHandler)
    print(f"serve.py listening on http://{host}:{port}")
    print(f"  static: serving from {REPO_ROOT}")
    print(f"  endpoints: GET /api/clean-check, POST /api/save-summary, POST /api/invalidate-summary (stub)")
    server.serve_forever()


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--host", default="127.0.0.1")
    args = ap.parse_args()
    run(port=args.port, host=args.host)
```

Notes:
- Server-side supersession resolution is the **authoritative** source. The browser may include hints in the request payload, but the server overwrites `supersedes_summary_event_id` and `freeform_path` based on a fresh read of `events.jsonl`. This eliminates race / consistency issues without requiring the browser to be trustworthy.
- The walrus operator in `_handle_save_summary` (`errors_out := []`) is a deliberate Python 3.8+ usage. Replace with explicit `errors_out = []; if not self._prepare_event(..., errors_out=errors_out):` if 3.7 compatibility is needed (the rest of the project assumes 3.8+ — confirmed by `cache-build.py` patterns).
- `SimpleHTTPRequestHandler` serves from `os.getcwd()` by default — the `os.chdir(REPO_ROOT)` at startup is essential so the static tree resolves to `view/` and `.agent-plan-tracker/`.

**Verification:**
- `python3 agent-plan-tracker/scripts/serve.py` starts on 127.0.0.1:8765.
- `curl http://127.0.0.1:8765/api/clean-check` returns `{"clean": true, "dirty_files": []}` on a clean tree.
- After `touch foo.tmp`, same curl returns `{"clean": false, "dirty_files": ["?? foo.tmp"]}`.
- `curl -X POST -d '{}' http://127.0.0.1:8765/api/invalidate-summary` returns HTTP 501 with the documented payload.
- `curl http://127.0.0.1:8765/agent-plan-tracker/view/index.html` returns the HTML (static serving still works).
- POST a fake save-summary body with a dirty tree → 409. With clean tree + valid event → 200 and the markdown file appears.

### Step 6 — Browser save flow

Add new module `PersistenceClient` to `app.js`:

```js
const PersistenceClient = {
  async cleanCheck() {
    const res = await fetch("/api/clean-check");
    if (!res.ok) throw new Error(`/api/clean-check HTTP ${res.status}`);
    return await res.json();
  },
  async saveSummary({ primary, derived }) {
    const res = await fetch("/api/save-summary", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        event: primary.event,
        freeform_md: primary.freeform_md,
        derived: derived.map(d => ({ event: d.event, freeform_md: d.freeform_md })),
      }),
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
      const e = new Error(data.message || `HTTP ${res.status}`);
      e.code = data.code || res.status;
      e.dirty_files = data.dirty_files;
      e.errors = data.errors;
      throw e;
    }
    return data;
  },
};
```

Extend `SidebarAnalyser._renderResult()` (the Phase A result render):

- Add a "Save" button below the existing rerun/back buttons.
- On click:
  1. `await PersistenceClient.cleanCheck()`. If `!clean`, render error: "Working tree dirty — commit or stash <list> before saving."
  2. Construct the primary event object (entity_type, entity_id, attributes with model/source=primary/structured/...), the freeform markdown body (the model's freeform output), and the derived array (one entry per `result.structured.derived_summaries[]` if present).
  3. `await PersistenceClient.saveSummary({primary, derived})`.
  4. On success: replace result panel with the "saved summary" view (see Step 7). Show a transient `Saved · <event_id>` badge.
  5. On failure: render the error inline with details (esp. `dirty_files` on 409, `errors` on 422).

Extend `ContextBuilder.buildSystemPrompt()` to instruct Claude to emit derived summaries when 1-hop dependents are present:

```
Output JSON schema:
{
  "outstanding": [...],
  "blocked": [...],
  "recently_changed": [...],
  "next_move": "...",
  "derived_summaries": [
    {
      "entity_type": "plan" | "inbox-item",
      "entity_id": "<id>",
      "outstanding": [...],
      "blocked": [...],
      "recently_changed": [...],
      "next_move": "..."
    }
  ]
}

For each 1-hop dependent listed above, you MAY emit a derived summary. Skip dependents
where you have nothing useful to say (e.g. dead entities, or entities you couldn't form
any opinion on from the available context). Empty derived_summaries: [] is fine.
```

Extend `AnalyseClient._parseStructured()` to surface `derived_summaries` from the parsed JSON unchanged into `result.structured`.

**Verification:**
- Run Phase A analyse on T2-projection. Confirm cost dialog. Get a structured response. Click Save.
- See clean-check confirmation, then a 200 from `/api/save-summary`, then a "Saved · <event_id>" badge.
- New events appear at the end of `events.jsonl`. New markdown file at `.agent-plan-tracker/summaries/T2-projection-<event_id>.md`.
- Repeat for an entity with multiple children. Verify N+1 events appear (1 primary + N derived) if Claude emitted derived for each.

### Step 7 — Saved-summary sidebar view

Add new module `SavedSummary` to `app.js`:

```js
const SavedSummary = {
  // Returns null if no saved summary for entity. Otherwise renders the sidebar.
  async render(panel, entity) {
    const proj = state.projection || {};
    const map = proj.latest_summary_by_entity || {};
    const key = `${entity.entity_type}:${entity.entity_id}`;
    const summary = map[key];
    if (!summary) return false;

    let freeform = "";
    try {
      const res = await fetch(`../../${summary.freeform_path}`);
      if (res.ok) freeform = await res.text();
    } catch {}

    const parts = [];
    parts.push(`<h3 class="md-title">${escapeHtml(entity.entity_id)}</h3>`);
    parts.push(`<p class="meta-line">
      <span class="badge ${entity.derived_state}">${entity.derived_state}</span> ·
      <span class="tag saved">saved summary</span>
      <code>${escapeHtml(summary.model)}</code>
      ${summary.source === "derived" ? '<span class="tag derived">derived</span>' : ""}
    </p>`);
    parts.push(`<div class="analyser-toggle-row">
      <button class="active" data-show="structured">Structured</button>
      <button data-show="freeform">Freeform</button>
      <button data-show="timeline">Timeline</button>
    </div>`);
    parts.push(`<div id="analyser-pane-structured">`);
    parts.push(SidebarAnalyser._renderSection("Outstanding", "outstanding", summary.structured.outstanding || []));
    parts.push(SidebarAnalyser._renderSection("Blocked", "blocked", summary.structured.blocked || []));
    parts.push(SidebarAnalyser._renderSection("Recently changed", "recently_changed", summary.structured.recently_changed || []));
    parts.push(SidebarAnalyser._renderNextMove(summary.structured.next_move || ""));
    parts.push(`</div>`);
    parts.push(`<div id="analyser-pane-freeform" hidden><div class="analyser-freeform">${
      window.marked && window.marked.parse ? window.marked.parse(stripFrontmatter(freeform)) : `<pre>${escapeHtml(freeform)}</pre>`
    }</div></div>`);
    parts.push(`<div id="analyser-pane-timeline" hidden></div>`);
    parts.push(`<div class="analyser-toggle-row">
      <button class="btn-secondary" id="btn-saved-regenerate" style="font-size:0.78rem">↻ Regenerate</button>
    </div>`);

    panel.innerHTML = parts.join("");
    // Wire toggle (including lazy-render timeline into its pane)
    // Wire regenerate → SidebarAnalyser.startAnalysis(entity)
    return true;
  },
};
```

Modify `showLiveStatus(entity)`: at the top, try `SavedSummary.render(panel, entity)`; if it returns true, stop. Else fall through to existing timeline + Analyse-outstanding flow.

**Verification:** After Step 6 save, reload the page. Click LIVE on the saved entity → SavedSummary view appears. Click Regenerate → goes back through cost dialog → new save replaces (supersedes_summary_event_id chain extends).

### Step 8 — Smoke test + integration via Claude_Preview

- `python3 agent-plan-tracker/scripts/serve.py` in background.
- `mcp__Claude_Preview__preview_start` against `http://localhost:8765/agent-plan-tracker/view/index.html`.
- preview_eval to walk through:
  1. Open settings, paste API key. (Use a real key for end-to-end; or stub the AnalyseClient response and exercise only the save path.)
  2. Click flow → click LIVE on T2-projection → Analyse outstanding → Confirm cost dialog.
  3. After result renders, click Save → assert clean-check passes → assert /api/save-summary returns 200.
  4. Reload page.
  5. Click LIVE on T2-projection again → assert SavedSummary view appears (not timeline).
  6. Click Regenerate → confirms cost dialog again → save again → reload → still works.
- Verify file system: `ls .agent-plan-tracker/summaries/` shows the expected files.
- Verify events.jsonl tail: new `analysis.live-summary` events present.

### Step 9 — Final commit cadence + completion arc

Suggested commits (matches the orchestrator's expectation):

1. **Commit 1** — `plan(T3,M6,B): T3-phase-b draft + schema 0.2.0 + cache+projection accept analysis events`
   - This plan + schema dir + schema-version bump + cache-build extension + projection emitter changes.
   - Events: `entity.created` for this T3, `relationship.spawns` from T2-analyser → T3, `relationship.spawns` from M6-analyser → T3, `commit.recorded`.

2. **Commit 2** — `feat(serve): server wrapper with clean-check + save-summary + invalidate stub`
   - `agent-plan-tracker/scripts/serve.py` lands.
   - `.claude/launch.json` updated to point at it.
   - `.agent-plan-tracker/summaries/.keep` added.
   - Events: `entity.progressed` on T3-phase-b summarising the server wrapper landing.

3. **Commit 3** — `feat(view): persistence flow — save button, clean-check, regenerate`
   - PersistenceClient + SidebarAnalyser changes + SavedSummary + showLiveStatus branch.
   - Browser-side smoke test against the running server with a fake-event payload (or real if key present).

4. **Commit 4** — `feat(analyser): derived summaries — system-prompt change + supersession enforcement`
   - System prompt asks for derived array.
   - Parser surfaces derived.
   - Save flow sends derived array.
   - Server enforces primary-beats-derived supersession.

5. **Commit 5** — `[M6,B] T3-phase-b complete + verification.tested + M6 progressed`
   - Events: `entity.completed` on T3-phase-b + `verification.tested` + `entity.progressed` on M6-analyser + `entity.progressed` on T2-analyser + `commit.recorded`.

Each commit must end with `bash agent-plan-tracker/scripts/repack-validate.sh` reporting all 8 steps pass.

## 6. Open questions surfaced during execution

Add to this list as work uncovers them. Resolve before merging the T3 to main.

- **Q1 — Atomicity of save.** Server writes markdown files then appends events. If the event append fails after a md write succeeds, the md file becomes an orphan. Acceptable for v1? Lean yes (lossy on the optimistic side; the orphan is detectable by a cache-build audit). Could be hardened later with tmp+rename + lock-then-append.
- **Q2 — `entity.created` for analyser-emitted summary events.** Should each `analysis.live-summary` event also emit an `entity.created` for its event_id? T2-ontology says yes for plans/inbox-items/blockers/hitl/implicit-work, but summaries aren't an `entity_type`. Lean: no — summaries are tracked in their own `summaries` cache table, not as entities. Confirm in T2-ontology when Phase B lands.
- **Q3 — JSON parse robustness when Claude emits derived inside the same fenced block.** Current `AnalyseClient._parseStructured()` uses a single regex on `\`\`\`json`. If Claude emits the derived array inside the same JSON object (most likely shape), the existing parser handles it. If Claude emits a SECOND fenced block for derived summaries (less likely but possible), we'd need to lift each block. Implementation: enforce in the system prompt that derived MUST live inside the same JSON object. Bail out cleanly if Claude doesn't comply.
- **Q4 — Derived summary `freeform_path` strategy.** T2-analyser §3.13 left this open ("section pointer or standalone file"). Phase B picks standalone files: `.agent-plan-tracker/summaries/<entity_id>-<event_id>.md` for each derived too. Rationale: cleaner semantics, simpler cache-build, simpler Phase D invalidation. Trade-off: more files (~3-5x per primary call). Lean accept the file count for v1.
- **Q5 — Where derived markdown content comes from.** Claude emits structured fields for each derived in the JSON, but no per-derived freeform text. Phase B writes a minimal stub `.md` per derived (just the structured fields rendered as headings + bullets). Could be richer later if Claude is asked to emit a freeform paragraph per derived. Lean keep minimal for v1.
- **Q6 — What happens if user clicks Save twice rapidly.** Server-side: the second save sees the first's events already in the log and computes supersession correctly. Browser-side: disable Save button after click. Lean: disable + show spinner; re-enable on response.
- **Q7 — Schema version of `commit.recorded` events going forward.** Per §5.1 all newly-emitted events are `0.2.0` after the cutover. `commit.recorded` is not a new event type but its emitted version bumps. The schema's loosened enum handles this. Confirmed.
- **Q8 — Where does the system prompt change happen vs the parser change.** They land in the same commit (Step 6 / Commit 3 area) so a mid-deploy state can't see prompt-asking-for-derived without parser-handling-derived. Yes — confirmed.

## 7. Verification checklist (pre-commit)

- [ ] `agent-plan-tracker/schemas/0.2.0/events.schema.json` exists; old 0.1.0 events still validate.
- [ ] `.agent-plan-tracker/schema-version.txt` = `0.2.0`.
- [ ] `bash agent-plan-tracker/scripts/validate-events.sh` passes against `events.jsonl` (with at least one `analysis.live-summary` test event present).
- [ ] `bash agent-plan-tracker/scripts/validate-plan-frontmatter.sh` passes.
- [ ] `python3 agent-plan-tracker/scripts/cache-build.py` populates the `summaries` table; row count matches the count of `analysis.live-summary` events in `events.jsonl`.
- [ ] `python3 agent-plan-tracker/scripts/projection-emit.py` produces `latest_summary_by_entity` with at least one entry after a save.
- [ ] All 3 audits (`audit-stalled.sql`, `audit-fulcrum-without-decision.sql`, `audit-orphans.sql`) return empty result sets.
- [ ] `bash agent-plan-tracker/scripts/repack-validate.sh` reports all 8 steps pass.
- [ ] `python3 agent-plan-tracker/scripts/serve.py` starts cleanly; binds only to 127.0.0.1.
- [ ] `GET /api/clean-check` returns expected JSON on clean + dirty trees.
- [ ] `POST /api/save-summary` round-trips a single primary save.
- [ ] `POST /api/save-summary` round-trips a primary + N derived save.
- [ ] `POST /api/invalidate-summary` returns HTTP 501 with the documented stub body.
- [ ] Browser save button gated on clean-check; surfaces the dirty-tree refusal clearly.
- [ ] Reload preserves saved summaries; SavedSummary view is the default when one exists.
- [ ] Regenerate replaces correctly; the chain extends via `supersedes_summary_event_id`.
- [ ] Primary on a child correctly supersedes the child's earlier derived (verified by `latest_summary_by_entity` updating).
- [ ] No console errors during the full flow.
- [ ] No regressions on Phase A — explicit re-analysis without saving still works.

## 8. Provenance

- T2-analyser §3.2 (event types), §3.3 (storage), §3.4 (endpoints), §3.5 (clean-tree), §3.6 (chain semantics), §3.13 (opportunistic derived).
- T2-analyser §4 Phase B scope.
- T2-analyser §7 Q7 (schema version bump → 0.2.0 chosen).
- T2-analyser §7 Q9 (derived markdown layout → standalone files chosen).
- T2-analyser §7 Q10 (derived can't be invalidated independently of primary — implication: Phase D's cascade design carries forward primary-as-invalidation-anchor; not yet exercised in Phase B).
- M6-analyser §4 phase table (Phase B placeholder filled).
- Inbox item `2026-05-27.agents-emit-entity-created-for-plans` — `entity.created` discipline applied throughout.
- Phase A's T3 (`T3-analyser-phase-a-ephemeral`) — structural model for this T3.
