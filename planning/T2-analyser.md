---
id: T2-analyser
plan_kind: thematic
tier: 2
status: draft
---

# T2-analyser — On-demand "what's outstanding?" analysis over live entities

**Status**: Draft. T3s queued; phases A-E candidate-scheduled across later milestones.
**Theme**: Claude-backed analyser that answers, for any live entity, **"what specifically is outstanding here?"** by reasoning over the entity's plan markdown, its event timeline, related entities, and any prior analyser summaries. Summaries are first-class events. The summary chain is invalidatable and cascades through dependents. **This T2 is the architectural source of truth for the analyser**; T1 references it once added to §4.1.

This T2 supersedes the inbox item `2026-05-27.outstanding-work-analyser-endpoint`, which proposed a thin server-wrapper-around-the-`claude`-CLI architecture. The design here is meaningfully different — browser-direct to the Anthropic API with a much smaller server wrapper, summaries as tracked events, and cascade-invalidation as a first-class concern.

---

## 1. Why this T2 exists

The flow view's LIVE badge currently opens a cache-derived **timeline** for an entity — what *has* happened. Useful, but partial. The question an operator actually asks at that point is "**what's still outstanding here?**" — and that answer needs reasoning over multiple inputs the cache can't synthesise:

- The entity's plan body (what was intended).
- Its event history (what's actually happened).
- Related entities — children, blockers, HITL questions, inbox items referencing it.
- Any prior analyser summary on the same entity (don't retread).

That synthesis is an agent task, not a query. The tracker-as-agent-memory principle inverts here — the agent *can* reason; the cache supplies grounded context; the summary feeds back into the tracker as a new event, available to the next reasoning pass.

Concretely, this T2 lets the operator:

- Click LIVE → get an opinionated **"here's what's outstanding"** summary in the sidebar.
- Save the summary as a tracked event in events.jsonl (positioned, supersedable, invalidatable).
- Generate summaries in bulk across all live entities (one-pass with prompt caching).
- Invalidate stale summaries when underlying state shifts; cascade to dependents.
- Carry summaries forward across sessions — the chain is durable project state, not session ephemera.

## 2. What lives in this theme

- **New event types** in the ontology — `analysis.live-summary` and `analysis.invalidated`. (T2-ontology owns the schema; this T2 owns the semantics.)
- **Browser-side analyser client** — direct call to Anthropic API from the HTML view's JS using `anthropic-dangerous-direct-browser-access: true`. API key in `localStorage`.
- **Settings modal** — API key entry + model picker presented at call time (no silent default). Persistent across sessions, per-machine.
- **Per-entity context builder** — JS code that assembles plan markdown + relevant timeline + related entities + prior summary chain into a Claude prompt.
- **Server wrapper** — small Python service (~150 lines) that adds three local-only endpoints to the existing static file server: `/api/clean-check`, `/api/save-summary`, `/api/invalidate-summary`. Replaces `python3 -m http.server` as the dev serve command.
- **Clean-tree guard** — `git status --porcelain` must be empty before a summary can be saved. Prevents sequencing problems within a commit.
- **Per-summary markdown file** — `.agent-plan-tracker/summaries/<entity_id>-<event_id>.md` carries the full freeform response (the JSONL event stays lightweight, carrying only the structured fields + a pointer).
- **Summary chain semantics** — each new summary for an entity `entity.superseded`-style supersedes the previous via `attributes.supersedes_summary_event_id`. Analyser prompt includes the most recent live summary so it can skip what's already covered.
- **Cascade invalidation** — when summary S1 is invalidated, all downstream summaries whose context depended on S1 are marked invalid. Marked, not deleted — regenerations replace them.
- **Bulk mode** — "Analyse all live" pass that ingests shared context once (via Anthropic prompt caching) and produces one summary per live entity.
- **Flow-view rendering** — saved live summaries appear as dedicated nodes in the workstreams-flow swimlane, visually distinct from event nodes. Invalid summaries get a strike-through / dimmed treatment.
- **Sidebar rendering** — structured response (Outstanding / Blocked / Recently changed / Next move) **and** raw markdown, with a toggle.

## 3. Architecture

### 3.1 Two halves: browser does Claude, server does git

The hybrid split is deliberate:

- **Browser-direct to Anthropic** for the LLM call itself. API key never leaves the user's machine in a way that requires a server-side credential store. Avoids the "where do I keep the key?" ops problem entirely. `anthropic-dangerous-direct-browser-access: true` header acknowledges the opsec posture: this is a local dev tool, not a hosted service.
- **Tiny server wrapper** for everything the browser can't do safely: `git status` (filesystem access), appending to `events.jsonl` (write access), writing summary markdown files. Server has zero LLM credentials, makes zero API calls — it's a thin RPC over local filesystem + git.

Net effect: API cost lives with the user's account directly; the server is project-local and credential-free.

### 3.2 New event types (briefed to T2-ontology)

Two events added to the ontology under a new **Analysis** category:

**`analysis.live-summary`** — a generated outstanding-work summary for a live entity.

Attributes:
- `entity_id` — the focal entity (also the event's `entity_id` field).
- `model` — exact Anthropic model id used (e.g. `claude-sonnet-4-20250514`). No silent default.
- `structured` — object with the four canonical sections:
  - `outstanding` — string[]
  - `blocked` — string[] (each entry references blocker/HITL where applicable)
  - `recently_changed` — string[]
  - `next_move` — string (single most actionable next step)
- `freeform_path` — relative path to the per-summary markdown file (e.g. `.agent-plan-tracker/summaries/T2-projection-c2700009-....md`).
- `supersedes_summary_event_id` — `event_id` of the prior live summary on this entity, if any.
- `context_event_id_range` — `{from, to}` capturing which events were folded into context. Enables cascade-invalidation logic to detect dependence.
- `prompt_cache_hit` — boolean (telemetry; bulk mode only).

**`analysis.invalidated`** — marks one or more prior summaries invalid.

Attributes:
- `target_event_id` — the summary being directly invalidated.
- `cascades_to_event_ids[]` — derived list of dependent summaries also marked invalid in the same operation.
- `reason` — short note (`user-triggered`, `underlying-events-changed`, etc.). Free text.

Neither is a fulcrum event. Neither requires a paired decision. Invalidation cascades are derived, not user-authored; they're audit trail, not policy.

### 3.3 Storage convention (briefed to T2-storage)

The JSONL event stays lightweight — structured response + pointer. The full freeform response lives in `.agent-plan-tracker/summaries/<entity_id>-<event_id>.md`. Rationale:

- Keeps `events.jsonl` line lengths bounded — bulk-mode runs across 20 live entities don't bloat one line per entity to multi-KB.
- The markdown file is human-readable in isolation, diff-friendly, and reviewable.
- The event_id in the filename means the file is naturally append-only — invalidations don't rewrite files, they emit a new `analysis.invalidated` event referencing the file's event_id.
- Summary files committed alongside the JSONL on the same commit — they share provenance and replay together.

The summaries directory is created on first use. Cache-build reads summary metadata from the event (structured fields) but does not need to read the markdown — the markdown is for human / sidebar consumption.

### 3.4 Server wrapper endpoints

The wrapper subclasses `SimpleHTTPRequestHandler` so all existing static-file behaviour (serving `view/`, `.agent-plan-tracker/projection.json`, etc.) is preserved. Three new endpoints:

**`GET /api/clean-check`**

Returns `{clean: true}` if `git status --porcelain` is empty, else `{clean: false, dirty_files: [...]}`. Browser calls this before allowing a save-summary action.

**`POST /api/save-summary`**

Body: full `analysis.live-summary` event payload + the freeform markdown body.

Server-side:
1. Re-runs the clean-tree check; refuses on dirty tree.
2. Validates the event against the active `events.schema.json`.
3. Writes the markdown file to `.agent-plan-tracker/summaries/<entity_id>-<event_id>.md`.
4. Appends the event to `events.jsonl`.
5. Returns the appended event's line position for client confirmation.

**`POST /api/invalidate-summary`**

Body: `{target_event_id, reason}`.

Server-side:
1. Re-runs the clean-tree check.
2. Walks the summary chain to compute cascade set (all summaries whose `context_event_id_range` post-dates `target_event_id`).
3. Emits a single `analysis.invalidated` event listing `cascades_to_event_ids`.
4. Appends to `events.jsonl`.

Returns the cascade set so the browser can update its display.

The wrapper is local-only by default — binds to `127.0.0.1`, not `0.0.0.0`. No auth on endpoints (the moat is the bind address).

### 3.5 Clean-tree guard

Working tree must be clean (`git status --porcelain` empty) before any save or invalidate is allowed. Two reasons:

1. **Sequencing within a commit.** A summary saved mid-uncommitted-work has an undefined position in the event timeline. Forcing clean-tree means each summary is unambiguously *between* commits, and the next `commit.recorded` cleanly closes it.
2. **Reproducibility.** A summary references events up to a known point. If new events are mid-flight in the working tree, the summary's `context_event_id_range` becomes ambiguous.

The guard is enforced server-side (the browser can't read git state). Browser displays a clear refusal: "Working tree dirty — commit or stash before saving summary."

### 3.6 Summary chain + retreading avoidance

Each new live summary for entity E carries `supersedes_summary_event_id` pointing at the previous live summary on E (or null if first). Forms a chain.

When the analyser builds context for a new summary, it includes the most recent **valid** summary in the chain and instructs Claude:

> A prior summary exists at <timestamp>. Treat its conclusions as established; only describe what has changed *since* it, plus what remains outstanding.

This bounds context cost: long-lived entities don't re-summarise their entire history every time.

If the most recent summary is invalid, the analyser walks back the chain to find the most recent valid one. If none exist, full-context mode.

### 3.7 Cascade invalidation

User clicks "Invalidate" on a saved summary S1 in the sidebar. Confirmation dialog warns:

> This will also invalidate <N> later summaries on related entities that incorporated S1's context. They will be marked invalid (not deleted). Regenerate any you still need.

A summary S2 is considered to depend on S1 when:

- S2.entity_id matches S1.entity_id (later summary in same entity's chain), **or**
- S2 was generated in a bulk run that occurred after S1 was saved (its `context_event_id_range.from` ≤ S1.event_id ≤ S2.context_event_id_range.to), **or**
- S2's entity has a `relationship.spawns` / `depends-on` edge to S1's entity *and* S2 was generated after S1.

Conservative over aggressive — false positives (over-invalidating) just mean regenerating; false negatives (under-invalidating) leave stale summaries in the chain misinforming the next pass. Lean cascade-wide.

Invalidated summaries remain visible in the flow view but rendered dimmed / struck-through, and are excluded from the "most recent valid summary" lookup.

### 3.8 Bulk mode + prompt caching

"Analyse all live" button generates summaries for every currently-live entity in one pass. Implementation:

1. Browser fetches `projection.json`, identifies live entities (~20 currently for this project).
2. Builds **shared context** — global project state (T1 + recent events across entities + live-entities index) — placed at the top of the prompt and marked for Anthropic prompt caching (`cache_control: {type: "ephemeral"}`).
3. For each live entity, issues a fresh request that **reuses the cached shared context** and varies only the per-entity tail (plan body, entity-specific timeline, prior summary).
4. Each response is a structured summary saved through the same `/api/save-summary` flow (clean-tree check runs once at start; subsequent saves fail-fast if tree becomes dirty mid-run).

Cost model: ~80-90% of the input tokens are the shared context, which is billed at the cached-read rate after the first request. For ~20 entities that's a meaningful cost ratio shift — bulk mode is cheaper per entity than running 20 individual calls.

Realistic? Yes, **conditional** on:
- Anthropic API supports the `cache_control` header (it does, as of Sonnet 4 / Opus 4).
- Shared context is large enough to benefit from caching (the 1024-token minimum is easily hit by T1 + recent events).
- The bulk run completes within the cache TTL (5 minutes by default, extendable). For ~20 entities at a few seconds each, well within.

### 3.9 Sidebar rendering

When the user clicks LIVE on an entity, the sidebar offers two paths:

- **Show timeline** (existing, cache-only, free, instant) — current behaviour.
- **Analyse outstanding** (new, calls Claude, costs tokens) — generates a summary on demand.

Summary view in the sidebar shows:
- The four structured sections (Outstanding / Blocked / Recently changed / Next move) as cleanly formatted cards.
- A toggle to flip to raw freeform markdown.
- The model used + timestamp + token cost (telemetry transparency).
- "Save" button — gated by clean-tree check.
- If a saved summary already exists, it's shown by default with a "Regenerate" button. The chain (prior valid summaries) is browsable via collapsible history.

### 3.10 Flow-view rendering

Saved live summaries appear in the workstreams flow as a distinct node kind on the entity's lifeline — a small annotated marker between the events it summarises. Click → opens the summary in the sidebar.

Invalidated summaries are dimmed and crossed out but remain visible (audit trail). The flow view never deletes; it surfaces what happened, including what was later marked stale.

### 3.11 Settings modal

Triggered from a gear icon in the toolbar. Two fields:

- **Anthropic API key** — `sk-ant-...`. Stored in `localStorage` under a per-machine key. Cleared on demand.
- **Default model** — none. Selection is required at each call ("Analyse with: ..." dropdown in the sidebar before the call fires). This is deliberate: model choice is a per-task decision, and a global default invites silent staleness.

A status indicator in the toolbar shows whether a key is configured. Missing-key state disables Analyse buttons with an inline "Configure API key" link.

## 4. Phases — T3 candidates

Five phases, each is a candidate T3. Milestone scheduling deferred — the M-axis will assign these once the bootstrap M1 settles and the user decides priority versus M2 (auto-extract) work.

### Phase A — Ephemeral browser-only analyser (~2h)

- Settings modal + API key + model picker.
- Per-entity context builder (plan md + entity timeline + related entities — no summary chain yet).
- Direct Anthropic call with structured + freeform response.
- Sidebar render: structured sections + raw md toggle.
- **No persistence** — close the tab, summary is gone. Proves the value loop before investing in storage.

Acceptance: user clicks LIVE → Analyse → sees a useful summary within ~10 seconds. No new event types yet.

### Phase B — Persistence + new event types + server wrapper (~2h)

- T2-ontology gets `analysis.live-summary` schema branch.
- Server wrapper replaces `python3 -m http.server`. Three endpoints land.
- Clean-tree guard.
- Per-summary markdown file convention.
- Saved summaries persist across reloads, replay through cache-build.
- No cascade-invalidate logic yet — single-summary regenerate replaces.

Acceptance: save a summary, reload the view, summary is still there. `events.jsonl` carries a valid `analysis.live-summary` event; markdown file exists.

### Phase C — Flow-view rendering (~1h)

- Summary nodes appear in the workstreams flow on the entity's lifeline.
- Click a summary node → sidebar opens the summary.
- Visual distinction from event nodes (different shape / color).

Acceptance: a saved summary shows as a node in the flow view; clicking it routes to the right sidebar render.

### Phase D — Invalidation + cascade (~1.5h)

- T2-ontology gets `analysis.invalidated` schema branch.
- Invalidate button on summary sidebar, confirmation dialog showing cascade scope.
- Server-side cascade computation.
- Invalidated summaries dimmed / struck through in flow view and excluded from chain lookups.
- Regenerate-on-invalidated-base path tested.

Acceptance: invalidate summary S1, see S2 (on related entity, generated after) also marked invalid; events.jsonl carries an `analysis.invalidated` event listing both.

### Phase E — Bulk mode (~1h)

- "Analyse all live" toolbar button.
- Shared-context prompt construction with `cache_control` for the shared portion.
- Sequential per-entity follow-on calls reusing the cache.
- Progress UI showing per-entity completion.
- All saves go through the same single-save endpoint.

Acceptance: bulk run on the project's ~20 live entities completes in <5 min, saves 20 summaries, telemetry shows cache-hit rate >80% on subsequent requests.

**Total: ~7-8h spread across phases.** Each phase is independently shippable.

## 5. Dependencies

- **T2-ontology** — owns the schema for the two new event types. Phase B blocks on a schema update there.
- **T2-storage** — owns the file convention for `.agent-plan-tracker/summaries/`. Phase B briefs T2-storage with the new directory.
- **T2-projection** — owns the flow view + sidebar. Phases A, C, D, E all extend T2-projection's surfaces.
- **T2-extraction (M2 onward)** — once extraction is automated, the extractor learns to *not* re-extract `analysis.live-summary` events (they're authored by the analyser flow, not the commit extractor — but the events are real events in events.jsonl, so the extractor must skip them rather than treat them as undocumented).

## 6. Swap-out points

- **Browser-direct Anthropic API call.** Trigger to revisit: opsec posture changes (e.g. multi-user setup), Anthropic discontinues the dangerous-direct-browser-access header, or a need emerges for shared API budget across team members. Replacement: thin server-side proxy holding the key. The split in this design (browser does LLM, server does git+disk) makes that swap localised — only the LLM call moves.
- **Per-summary markdown file.** Trigger to revisit: summary count explodes (>10k); filesystem becomes unwieldy. Replacement: inline in event JSON (accept the bloat) or external store. Lean filesystem until friction is real.
- **Cascade invalidation conservatism.** Trigger to revisit: users complain about over-invalidation noise. Replacement: more precise dependency tracking (e.g. only invalidate downstream summaries whose Claude prompt actually quoted the invalidated one). Lean conservative-and-cheap until friction is real.
- **Settings stored in localStorage.** Trigger to revisit: users want sync across machines / browsers. Replacement: settings file in `.agent-plan-tracker/` (per-project) or a separate config. Lean localStorage for v1 since it's a dev tool used on one machine at a time.

## 7. Open questions

1. **Server wrapper deployment.** Does the wrapper replace `python3 -m http.server` outright, or is it offered as `python3 agent-plan-tracker/scripts/serve.py` alongside? Lean replacement to keep one path; document the override for hook-averse setups.
2. **What counts as "related entities" in per-entity context?** Direct children (T3s of a T2), open blockers/HITL referencing the entity, inbox items mentioning it by id. Anything else? Lean conservative; expand based on Phase A real-failure observations.
3. **Cost ceiling per call.** Should the analyser refuse to fire if estimated input tokens exceed a threshold? Or just warn and let the user proceed? Lean warn-and-proceed for v1; protective ceilings invite frustration.
4. **Summary regeneration without invalidation.** Is "regenerate" semantically equivalent to "invalidate current + create new"? Yes. The Regenerate button is sugar over Invalidate-then-Save; UI surfaces it as one action.
5. **Streaming vs blocking call.** Anthropic supports streaming responses. Worth implementing for the perceived-latency win, but adds complexity. Lean blocking for Phase A; revisit if 10-second waits feel painful.
6. **Caching beyond the bulk-mode hit.** Should single-entity calls also use prompt caching for the global-context portion across sessions? Possibly, but cache TTL (5min default) limits the win for sporadic single calls. Worth measuring before committing.
7. **Schema-version bump for new events.** Adding two event types — does this require bumping `schema_version` from `0.1.0` to `0.2.0`, or is it additive enough to stay at `0.1.0`? Lean `0.2.0` for clarity (matches T2-ontology §4 versioning intent). Decision logged when Phase B lands.
8. **Bulk-mode partial failure.** If summary 7 of 20 fails (API error, validation fail), do the first 6 stay saved? Lean yes — each save is atomic and independent; partial completion is acceptable, surface in progress UI.

## 8. Out of scope for this T2

- **Inter-summary cross-references.** Summaries don't link to each other beyond the chain. No graph-of-summaries.
- **Auto-trigger on event append.** No "every commit re-analyses live entities" mode — the cost would be wild. On-demand only.
- **Summary editing.** Generated summaries are immutable. To revise: invalidate + regenerate (or hand-author a new event externally, but that's outside the analyser's flow).
- **Multi-model ensembling.** One model per summary. No "ask Claude and Gemini, merge".
- **Non-live entity analysis.** The analyser fires on `live` state only. "What did this dead entity ever achieve?" is a different query — answer it via the cache-derived timeline.
- **Summary export.** Markdown files are exportable by virtue of being filesystem objects. No special export endpoint.
