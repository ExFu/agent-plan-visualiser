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
- `source` — `primary` (the entity was the focus of the call) or `derived` (the summary fell out as a side-effect of a primary call on another entity — see §3.13).
- `origin_summary_event_id` — for `derived` summaries: the `event_id` of the primary summary this fell out of. Null for `primary`.
- `structured` — object with the four canonical sections:
  - `outstanding` — string[]
  - `blocked` — string[] (each entry references blocker/HITL where applicable)
  - `recently_changed` — string[]
  - `next_move` — string (single most actionable next step)
- `freeform_path` — relative path to the per-summary markdown file (e.g. `.agent-plan-tracker/summaries/T2-projection-c2700009-....md`). For `derived` summaries this is typically a section pointer into the parent's md, not a standalone file (see §3.13).
- `supersedes_summary_event_id` — `event_id` of the prior live summary on this entity, if any. **A `primary` summary always supersedes any `derived` summary on the same entity; a `derived` summary never supersedes a `primary` one.**
- `context_event_id_range` — `{from, to}` capturing which events were folded into context. Enables cascade-invalidation logic to detect dependence.
- `estimated_input_tokens` / `estimated_output_tokens` / `actual_input_tokens` / `actual_output_tokens` — telemetry for cost transparency and future estimator calibration.
- `prompt_cache_hit_ratio` — fraction of input tokens served from prompt cache (global mode only).

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

### 3.8 Global update mode + prompt caching

"Analyse all live (global)" button generates summaries for every currently-live entity in one pass. This is the right path when the operator wants a fresh full-graph picture; running per-entity analysis on T1 would in principle pull in the whole graph but the focal-on-T1 framing would leave T2/T3 summaries shallow — global mode treats every live entity as a primary focus in its own right.

Implementation:

1. Browser fetches `projection.json`, identifies live entities (~20 currently for this project).
2. Builds **shared context** — global project state (T1 plan + recent events across entities + live-entities index + the live-relationship subgraph from §3.12) — placed at the top of the prompt and marked for Anthropic prompt caching (`cache_control: {type: "ephemeral"}`).
3. For each live entity, issues a fresh request that **reuses the cached shared context** and varies only the per-entity tail (plan body, entity-specific timeline, prior valid summary).
4. Each response is a `source: primary` structured summary saved through the same `/api/save-summary` flow (clean-tree check runs once at start; subsequent saves fail-fast if tree becomes dirty mid-run).
5. Opportunistic derived summaries on dependents (§3.13) are **suppressed** in global mode — every entity is getting a primary anyway, so derived would be wasted output tokens.

Cost model: ~80-90% of input tokens are shared context, billed at the cached-read rate after the first request. For ~20 entities that's a meaningful cost ratio shift — global mode is significantly cheaper per entity than running 20 individual calls.

Realistic? Yes, **conditional** on:
- Anthropic API supports the `cache_control` header (it does, as of Sonnet 4 / Opus 4).
- Shared context is large enough to benefit from caching (the 1024-token minimum is easily hit by T1 + recent events).
- The global run completes within the cache TTL (5 minutes by default, extendable). For ~20 entities at a few seconds each, well within.

A cost-warning dialog (§3.9.1) fires before the run with a hard confirmation gate.

### 3.9 Sidebar rendering

When the user clicks LIVE on an entity, the sidebar offers two paths:

- **Show timeline** (existing, cache-only, free, instant) — current behaviour.
- **Analyse outstanding** (new, calls Claude, costs tokens) — generates a summary on demand.

Summary view in the sidebar shows:
- The four structured sections (Outstanding / Blocked / Recently changed / Next move) as cleanly formatted cards.
- A toggle to flip to raw freeform markdown.
- The model used + timestamp + actual token cost (telemetry transparency).
- A small badge if the summary is `derived` (§3.13) — "Side-effect of T2-X analysis on YYYY-MM-DD; run primary analysis to refresh".
- "Save" button — gated by clean-tree check.
- If a saved summary already exists, it's shown by default with a "Regenerate" button. The chain (prior valid summaries) is browsable via collapsible history.

#### 3.9.1 Cost-warning dialog (gates every live call)

Before any Claude call fires — per-entity, global, or regenerate — the browser computes an estimate from the assembled context bundle (input tokens via tiktoken-equivalent or a heuristic char-count proxy; output tokens from a model-specific cap × expected summaries) and current Anthropic public pricing baked into the JS. Dialog shows:

```
About to analyse: T2-projection (primary)
  Model:            claude-sonnet-4-20250514
  Input tokens:     ~14,200  (cache hit projected on 11,800 → 83%)
  Output tokens:    ~1,500   (one structured summary + freeform)
  Derived summaries: 3 dependents will also be summarised (§3.13)
  Estimated cost:   $0.043
  [ Cancel ]   [ Confirm and run ]
```

Global mode dialog is more dramatic (~20 entities, multi-dollar territory) and uses red accent. Confirm gate is always required — no silent dispatch even on per-entity calls. A "don't ask for calls under $0.10" toggle exists in settings (per-machine, default off).

Estimator calibration improves over time: every saved summary records `estimated_input_tokens` alongside `actual_input_tokens`. The settings modal surfaces accumulated error so the user knows whether estimates are trustworthy.

### 3.10 Flow-view rendering

Saved live summaries appear in the workstreams flow as a distinct node kind on the entity's lifeline — a small annotated marker between the events it summarises. Click → opens the summary in the sidebar.

Invalidated summaries are dimmed and crossed out but remain visible (audit trail). The flow view never deletes; it surfaces what happened, including what was later marked stale.

### 3.11 Settings modal

Triggered from a gear icon in the toolbar. Two fields:

- **Anthropic API key** — `sk-ant-...`. Stored in `localStorage` under a per-machine key. Cleared on demand.
- **Default model** — none. Selection is required at each call ("Analyse with: ..." dropdown in the sidebar before the call fires). This is deliberate: model choice is a per-task decision, and a global default invites silent staleness.

A status indicator in the toolbar shows whether a key is configured. Missing-key state disables Analyse buttons with an inline "Configure API key" link.

### 3.12 Programmatic context building (no agentic discovery)

The agent is never asked "go find related entities" or "figure out what depends on this". That would waste tokens on discovery the cache can answer for free. Instead the browser **pre-builds the context bundle** by walking the cache and projection, and hands the agent a fully assembled package.

**Inputs available client-side without an API call:**

- `projection.json` — full entities/relationships/decisions/events index.
- `cache.sqlite` — same data queryable; served as a binary blob or pre-exported as JSON slices (e.g. per-entity event arrays).
- Plan markdown files — fetched directly via the existing static file server.
- Inbox markdown files — same.

**Per-entity context bundle, assembled in browser JS:**

1. **Focal entity** — plan body (markdown), full event timeline, derived state.
2. **Direct children** — for a T2 focal, every T3 with `t2_parent` pointing to it; for a milestone focal, every plan with `milestone` pointing to it. Walked via the `entities.attributes` lookup, no LLM needed.
3. **Relationship graph (1-hop)** — follow `relationship.spawns`, `relationship.depends-on`, `relationship.alongside`, `relationship.addendum-to`, `relationship.reattached` from the focal in both directions. For each related entity, include its plan_kind + tier + current derived_state + one-line summary.
4. **Open blockers** — `blocker` entities with `derived_state = live` mentioned by id in the focal's plan body or appearing in any event with the focal as `entity_id`.
5. **Open HITL questions** — same lookup against `hitl-question` entities.
6. **Inbox items referencing the focal** — flat grep across `.agent-plan-tracker/inbox/*.md` for the focal `entity_id` string. Browser fetches an inbox-index file (generated by cache-build) listing entity references per file; no full-text scan needed at call time.
7. **Prior valid summary chain on the focal** — most recent `analysis.live-summary` where the chain is valid (no intervening `analysis.invalidated`), passed in full. Older valid summaries summarised by their `next_move` lines only (chain compression).

The agent receives this as a structured prompt section like:

```
## Focal entity: T2-projection
[plan markdown body]

## Recent events on T2-projection
[event timeline, most recent 30]

## Related entities (1-hop graph)
- T3-html-view (child, dead) — completed in commit abc123
- T3-projection-emitter (child, dead) — completed in commit def456
- T2-ontology (alongside, live) — last summary on 2026-05-26: "next: ..."

## Open blockers referencing T2-projection
(none)

## Open inbox items referencing T2-projection
- 2026-05-23.html-view-visual-style (open, t3 candidate) — body...

## Prior valid summary on T2-projection
[full markdown of most recent live-summary]
```

The agent's only job is **reason and structure**. It doesn't fetch, walk, or grep — those are pre-computed. This drives input token cost down by 30-50% vs an agentic-discovery approach (rough estimate; calibrate after Phase A).

**Token-cost ceiling per call**: if the assembled bundle exceeds a threshold (default 30k input tokens for per-entity calls, 80k for global), the cost-warning dialog (§3.9.1) flags it in red and recommends either trimming context (fewer historical events, no inbox items) or splitting the call.

### 3.13 Opportunistic caching of derived summaries

When running a **primary** analysis on focal E, the assembled context bundle (§3.12) includes 1-hop related entities. Claude reasons over all of them to answer "what's outstanding on E?". The prompt instructs Claude to **also emit a structured summary for each direct dependent it touched**, in the same output:

```
## Primary summary
[focal entity: structured + freeform]

## Derived summaries (1-hop dependents touched)
### T3-html-view
- next_move: ...
- outstanding: ...
(or: "no useful summary — dead entity, no derived needed")

### 2026-05-23.html-view-visual-style
- next_move: ...
```

Each derived summary is saved as a separate `analysis.live-summary` event with:
- `source: derived`
- `origin_summary_event_id` → the primary's `event_id`
- `freeform_path` → may point into a section of the primary's markdown file (e.g. `summaries/T2-projection-c2800007-....md#derived-T3-html-view`), or to a standalone file — implementation choice deferred to Phase B.

**Supersession rules:**
- A new `primary` on entity X **always** supersedes any prior summary on X (primary or derived).
- A new `derived` on entity X supersedes a prior `derived` on X. It does **not** supersede a prior `primary` (because primary is higher-confidence — the focal call's attention was on it).
- A `primary` on X older than a `derived` on X gets superseded *only* by another `primary` on X. The derived is treated as a freshness signal but doesn't replace authoritative content.

**Why this matters:** when a global update runs, every entity gets a primary — no need for derived. But for ad-hoc per-entity calls, dependents get cheap drive-by refreshes. Over time the project accumulates summaries opportunistically without explicit cost.

**Confidence display:** the sidebar marks derived summaries with a "side-effect" badge (§3.9) so the operator knows the analysis wasn't focused on this entity. Encourages running a primary analysis when precision matters.

**Cost framing:** derived summaries cost only output tokens, not input — the input context was already paid for in the primary call. A primary call on a T2 with 4 children adds ~4 × 200 = 800 output tokens; well under 10% extra cost for 4 free side-effect updates.

**Suppressed in global mode** (§3.8): every entity is getting a primary anyway, no waste.

## 4. Phases — T3 candidates

Five phases, each is a candidate T3. Milestone scheduling deferred — the M-axis will assign these once the bootstrap M1 settles and the user decides priority versus M2 (auto-extract) work.

### Phase A — Ephemeral browser-only analyser (~2.5h)

- Settings modal + API key + model picker.
- **Programmatic context builder** (§3.12) — pre-assembles bundle from projection.json + cache exports + plan/inbox md fetches. Walks 1-hop relationship graph. No agentic discovery.
- **Cost-warning dialog** (§3.9.1) — input/output token estimate + dollar cost before every call. Hard confirm gate.
- Direct Anthropic call with structured + freeform response.
- Sidebar render: structured sections + raw md toggle.
- **No persistence** — close the tab, summary is gone. Proves the value loop + the programmatic-context approach before investing in storage.

Acceptance: user clicks LIVE → Analyse → confirms cost dialog → sees a useful summary within ~10 seconds. Context bundle assembled entirely client-side from cache+projection (no LLM call for discovery). No new event types yet.

### Phase B — Persistence + new event types + server wrapper + opportunistic derived (~3h)

- T2-ontology gets `analysis.live-summary` schema branch including `source` and `origin_summary_event_id` fields.
- Server wrapper replaces `python3 -m http.server`. Three endpoints land.
- Clean-tree guard.
- Per-summary markdown file convention.
- **Opportunistic derived caching** (§3.13) — primary calls also emit + save summaries for 1-hop dependents touched. Supersession rules (primary always beats derived) enforced server-side at save time.
- Saved summaries persist across reloads, replay through cache-build.
- No cascade-invalidate logic yet — single-summary regenerate replaces.

Acceptance: save a primary summary on a T2 with 3 children → 4 `analysis.live-summary` events appended (1 primary + 3 derived); markdown files exist. Reload the view, all 4 summaries are there. Running a primary on one of the children supersedes its derived correctly.

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

### Phase E — Global update mode (~1.5h)

- "Analyse all live (global)" toolbar button with red-accent cost-warning dialog (§3.9.1).
- Shared-context prompt construction with `cache_control` for the shared portion.
- Sequential per-entity follow-on calls reusing the cache, each producing a `primary` summary.
- Derived-summary emission suppressed in this mode (every entity gets a primary anyway).
- Progress UI showing per-entity completion + running cost total + cache-hit ratio.
- All saves go through the same single-save endpoint.

Acceptance: global run on the project's ~20 live entities completes in <5 min, saves 20 primary summaries, telemetry shows prompt-cache-hit ratio >80% on subsequent requests, total cost matches dialog estimate within ±15%.

**Total: ~9h spread across phases.** Each phase is independently shippable.

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
- **Opportunistic derived-summary emission.** Trigger to revisit: derived summaries prove low-signal (Claude consistently fills them with hedge phrases like "no useful summary"), or supersession rules generate user confusion. Replacement: drop derived entirely; per-entity calls focus only on the focal. Lean keep-derived until empirical friction shows otherwise — the output-token cost is small and the cached side-effect value is real.
- **Programmatic 1-hop traversal scope.** Trigger to revisit: 1-hop misses important transitive context (e.g. T1 analysis should reach T3s, not stop at T2s) or includes too much noise. Replacement: configurable hop depth, or hop-by-relationship-type rules. Lean 1-hop until friction surfaces.

## 7. Open questions

1. **Server wrapper deployment.** Does the wrapper replace `python3 -m http.server` outright, or is it offered as `python3 agent-plan-visualiser/scripts/serve.py` alongside? Lean replacement to keep one path; document the override for hook-averse setups.
2. **What counts as "related entities" in per-entity context?** Direct children (T3s of a T2), open blockers/HITL referencing the entity, inbox items mentioning it by id. Anything else? Lean conservative; expand based on Phase A real-failure observations.
3. **Cost ceiling per call.** Should the analyser refuse to fire if estimated input tokens exceed a threshold? Or just warn and let the user proceed? Lean warn-and-proceed for v1; protective ceilings invite frustration.
4. **Summary regeneration without invalidation.** Is "regenerate" semantically equivalent to "invalidate current + create new"? Yes. The Regenerate button is sugar over Invalidate-then-Save; UI surfaces it as one action.
5. **Streaming vs blocking call.** Anthropic supports streaming responses. Worth implementing for the perceived-latency win, but adds complexity. Lean blocking for Phase A; revisit if 10-second waits feel painful.
6. **Caching beyond the bulk-mode hit.** Should single-entity calls also use prompt caching for the global-context portion across sessions? Possibly, but cache TTL (5min default) limits the win for sporadic single calls. Worth measuring before committing.
7. **Schema-version bump for new events.** Adding two event types — does this require bumping `schema_version` from `0.1.0` to `0.2.0`, or is it additive enough to stay at `0.1.0`? Lean `0.2.0` for clarity (matches T2-ontology §4 versioning intent). Decision logged when Phase B lands.
8. **Bulk-mode partial failure.** If summary 7 of 20 fails (API error, validation fail), do the first 6 stay saved? Lean yes — each save is atomic and independent; partial completion is acceptable, surface in progress UI.
9. **Derived freeform storage layout.** Should derived summaries (§3.13) share a markdown file with their primary (anchor sections) or get their own files? Shared is leaner (1 file per primary call) but invalidating a derived independently of the primary is uglier. Own files is fatter but cleaner semantically. Decide in Phase B based on whether independent derived-only invalidation is needed (probably not — see Q10).
10. **Can a derived summary be invalidated independently of its origin primary?** Lean no — derived is a side-effect; invalidating it without invalidating the primary creates a weird half-state. Force "invalidate origin → cascades to all its derived" as the only path. Validate during Phase D design.
11. **Cost-estimator accuracy.** A char-count proxy for token count is rough (typically ±15%). Worth shipping tiktoken-equivalent JS for tighter estimates? Probably yes once estimator error in real use exceeds ±25%, but lean cheap-and-rough for Phase A.
12. **Inbox-index pre-computation.** §3.12 step 6 assumes cache-build emits an inbox-to-entity reference index. That's a small addition to T2-storage's cache builder. Confirm with T2-storage owner that this is in scope before Phase A relies on it; fallback is a runtime grep across inbox md files (browser-side fetch each one).

## 8. Out of scope for this T2

- **Inter-summary cross-references.** Summaries don't link to each other beyond the chain. No graph-of-summaries.
- **Auto-trigger on event append.** No "every commit re-analyses live entities" mode — the cost would be wild. On-demand only.
- **Summary editing.** Generated summaries are immutable. To revise: invalidate + regenerate (or hand-author a new event externally, but that's outside the analyser's flow).
- **Multi-model ensembling.** One model per summary. No "ask Claude and Gemini, merge".
- **Non-live entity analysis.** The analyser fires on `live` state only. "What did this dead entity ever achieve?" is a different query — answer it via the cache-derived timeline.
- **Summary export.** Markdown files are exportable by virtue of being filesystem objects. No special export endpoint.
