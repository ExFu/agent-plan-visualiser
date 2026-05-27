---
id: T3-analyser-phase-a-ephemeral
plan_kind: thematic
tier: 3
t2_parent: T2-analyser
milestone: M6-analyser
status: draft
---

# T3-analyser-phase-a-ephemeral — Browser-only analyser proof of value (no persistence)

> **For Claude:** Implement this plan task-by-task. See T2-analyser §3, §3.12, §3.13, §3.9.1 for architectural context. No new event types in this phase — Phase A intentionally has zero persistence.

**Goal:** Ship a working "Analyse outstanding" button on the workstreams flow view's LIVE-badge sidebar. Click → cost dialog → confirm → Claude API call (browser-direct) → structured + freeform summary rendered in sidebar. No save, no events.jsonl write, no server wrapper. Close tab = summary gone.

**Architecture:** Pure vanilla JS extensions to `agent-plan-tracker/view/app.js` + a settings modal in `index.html`. Direct `fetch()` to `https://api.anthropic.com/v1/messages` with `anthropic-dangerous-direct-browser-access: true`. API key in `localStorage`.

**Tech stack:** Vanilla JS, fetch API, localStorage. No build step. No new dependencies.

---

## 1. Why this T3

T2-analyser §4 phases the rollout: A first because it's the cheapest proof-of-value. If clicking "Analyse outstanding" doesn't produce a useful summary, the rest of the design is moot. Phase A makes the loop visible end-to-end without committing to event-storage shape, summary file layout, or server-wrapper deployment.

Phase A also exercises §3.12 (programmatic context building) for the first time. If pre-assembled bundles work, the project saves 30-50% input tokens on every future call. If they don't (Claude gets confused by the pre-fetched bundle and needs to "see" things itself), Phase A surfaces it before we build storage around the wrong abstraction.

## 2. Out of scope

- **Persistence.** No save button. No `analysis.live-summary` event in events.jsonl. No server wrapper. (All Phase B.)
- **Flow-view summary nodes.** No saved summaries means nothing to render on the lifeline yet. (Phase C.)
- **Invalidation.** Nothing to invalidate yet. (Phase D.)
- **Global / bulk mode.** Single-entity calls only. (Phase E.)
- **Opportunistic derived caching.** Without persistence, derived summaries can't be saved either; the prompt-shape work is deferred to Phase B.
- **Streaming.** Blocking calls only (T2-analyser §7 Q5).
- **Schema-version bump.** No new event types in Phase A, so v0.1.0 stays.

## 3. Acceptance criteria

- Settings modal accessible from a gear icon in the toolbar. API key field saves to `localStorage`; model dropdown lists at least `claude-sonnet-4-20250514` and `claude-opus-4-20250514` (canonical IDs to verify against Anthropic docs).
- Toolbar shows a "key configured" indicator (green dot) when localStorage has a key; otherwise red dot + "Configure API key" link.
- Clicking the LIVE badge on a live entity opens the existing timeline sidebar (unchanged behaviour).
- Sidebar adds a new "Analyse outstanding" button next to the timeline. Disabled if no API key. Tooltip explains state.
- Clicking "Analyse outstanding" shows a model picker dropdown then a cost-warning dialog with:
  - Estimated input tokens (char-count proxy: `Math.ceil(prompt.length / 4)`).
  - Estimated output tokens (1500 cap × structured + freeform).
  - Estimated dollar cost (Sonnet 4 pricing baked in for v1: $3/MTok input, $15/MTok output).
  - "Cancel" / "Confirm and run" buttons.
- On confirm, browser POSTs to Anthropic with the programmatic context bundle (§3.12 spec: focal plan body + entity timeline + 1-hop graph + open blockers/HITL + inbox refs).
- Response renders in sidebar as:
  - Four structured cards (Outstanding / Blocked / Recently changed / Next move).
  - Toggle to flip to raw freeform markdown (using existing marked.js).
  - Header showing model used + actual token counts + actual dollar cost.
- Errors (no API key, invalid key, network failure, malformed response) surface as a clear in-sidebar error message — no silent failures.
- Sidebar state is ephemeral: navigating to another entity discards the summary. Refreshing the page discards the summary. Closing the tab discards the summary. **Explicit non-acceptance: no summary survives navigation.**

## 4. Files to create / modify

- **Modify** `agent-plan-tracker/view/index.html` — add settings modal markup, gear icon in toolbar, cost dialog markup. Hidden by default.
- **Modify** `agent-plan-tracker/view/app.js` — add:
  - `Settings` module (read/write localStorage; toolbar status pill).
  - `ContextBuilder` module — assembles per-entity bundle from projection.json + plan/inbox markdown fetches.
  - `Estimator` module — char-count proxy + dollar cost computation per model.
  - `AnalyseClient` module — wraps `fetch()` to Anthropic; handles structured JSON output via the model's structured-output / response-format mode if available, else regex/JSON-parse fallback.
  - `SidebarAnalyser` module — UI controller for the analyse button, model picker, cost dialog, result render.
- **Modify** `agent-plan-tracker/view/style.css` — settings modal, cost dialog, structured-summary cards, error banner styles. Reuse existing colour palette + sidebar layout.

No new files in Phase A. Each module is a `// === Module name ===` section in `app.js` for now — no module split until Phase B needs server-side glue.

## 5. Implementation steps

### Step 1 — Settings modal scaffold

- Add gear icon to toolbar (left of view-toggle buttons).
- Add hidden modal `<div id="settings-modal" hidden>` with API key input, model dropdown, status indicator, save/close buttons.
- `Settings.get()` / `Settings.set()` / `Settings.hasKey()` read/write `localStorage.apt_anthropic_api_key` and `localStorage.apt_default_model`.
- Toolbar status pill (`#api-key-status`) reflects `hasKey()`; clicking it opens the modal.

**Verification:** open page → modal closed; click gear → modal opens; enter `sk-ant-test` → save → close → reopen → field repopulated → toolbar pill is green.

### Step 2 — Context bundle builder

- `ContextBuilder.buildPerEntityBundle(entityId)` returns an object:
  ```
  {
    focal: { id, plan_kind, tier, derived_state, plan_md, events: [...] },
    related_1hop: [ { id, kind, derived_state, plan_kind, one_liner } ],
    open_blockers: [...],
    open_hitl: [...],
    inbox_refs: [ { id, body_md } ],
    prior_summary: null   // Phase A: always null since no persistence
  }
  ```
- Walks `projection.json` already loaded by the view (no extra fetch).
- For `focal.plan_md`: `fetch('../../../planning/' + entityId + '.md')` (or inbox path for inbox-items).
- For `related_1hop`: iterate `projection.json.relationships`, both directions, expand each related entity to its one-line summary.
- For `inbox_refs`: for v1, naive substring match — fetch each inbox markdown file and check for the entity id. **TODO comment**: replace with pre-computed index per T2-analyser §7 Q12 in Phase B.
- For `open_blockers` / `open_hitl`: filter projection entities by entity_type + derived_state.

**Verification:** open browser console; `await ContextBuilder.buildPerEntityBundle('T2-projection')` returns the expected shape; spot-check `related_1hop` includes T3-html-view, T3-projection-emitter, T3-markdown-summary, T3-projection-queries-v0.

### Step 3 — Prompt template + serialiser

- `ContextBuilder.bundleToPrompt(bundle)` returns a plain string formatted per T2-analyser §3.12 example, with:
  - System message: role briefing + structured output schema (the four sections).
  - User message: assembled bundle in the documented sections.
- Schema for structured output (passed to Anthropic if model supports it; otherwise asked-for-in-prose):
  ```json
  {
    "outstanding": ["string"],
    "blocked": ["string"],
    "recently_changed": ["string"],
    "next_move": "string"
  }
  ```

**Verification:** generated prompt for T2-projection is under 15k characters; visually inspect that each section header is present.

### Step 4 — Estimator + cost dialog

- `Estimator.estimateForBundle(bundle, model)` returns `{inputTokens, outputTokens, dollars}`.
- Model pricing table baked in v1: `claude-sonnet-4-20250514`: $3 in / $15 out per MTok; `claude-opus-4-20250514`: $15 in / $75 out per MTok.
- Cost dialog markup hidden by default; populated dynamically.
- "Confirm and run" wired to next step.

**Verification:** click "Analyse outstanding" on T2-projection with Sonnet selected → dialog appears showing input ~3500-5000 tokens, output ~1500 tokens, cost ~$0.03-0.04.

### Step 5 — Anthropic call + response parsing

- `AnalyseClient.run({apiKey, model, prompt, schema})` returns `{structured, freeform, usage}`.
- POST to `https://api.anthropic.com/v1/messages` with headers:
  - `x-api-key: <key>`
  - `anthropic-version: 2023-06-01`
  - `anthropic-dangerous-direct-browser-access: true`
  - `content-type: application/json`
- Body: `{model, max_tokens: 2048, messages: [{role: "user", content: prompt}]}`. (System prompt as separate top-level if Anthropic API supports it for the chosen model.)
- Parse structured output via the model's response; if Claude returns mixed prose + JSON, extract JSON via regex on a fenced code block.
- On error (HTTP non-2xx), throw with response body for sidebar display.

**Verification:** with a real key, a single end-to-end run on T2-projection completes in <15 seconds and returns a parsable structured response. Without a key, "Analyse outstanding" is disabled. With an invalid key, sidebar shows the API's error message verbatim.

### Step 6 — Sidebar render

- `SidebarAnalyser.render(result)` produces:
  - Header: `Analysed with claude-sonnet-4-20250514 · 4,231 in / 1,498 out tokens · $0.035`.
  - Four cards in fixed order: Outstanding / Blocked / Recently changed / Next move.
  - Toggle button: "Show freeform" / "Show structured".
  - Below cards: raw freeform markdown rendered via existing `marked.parse()`.
- On error: render in-sidebar error banner with the error text + a "Retry" button that reopens the cost dialog.
- Loading state: spinner + "Analysing T2-projection with claude-sonnet-4..." text while the Anthropic call is in flight.

**Verification:** full happy path produces nicely-formatted cards; toggling to freeform shows the markdown; clicking another entity in the swimlane discards the summary and shows that entity's timeline.

### Step 7 — Error path polish

- Test scenarios:
  - No API key configured → button disabled with hover-tooltip "Configure API key in settings".
  - Network failure (offline) → in-sidebar error: "Network error — check connection".
  - 401 from Anthropic → "API key invalid or revoked — check settings".
  - 429 / rate-limited → "Rate limited — retry in N seconds" (parse `retry-after` header).
  - Malformed response (model didn't return JSON) → "Couldn't parse model response. See freeform below." + fall back to freeform-only render.

**Verification:** flip airplane mode → run → see network error banner; restore connectivity → click retry → succeeds.

## 6. Open questions surfaced during execution

(Add new ones as they arise during implementation. Resolve before merging the T3.)

- Does the Anthropic API support a structured-output mode for the chosen models, or do we ask for JSON in the prompt and parse manually?
- Does `marked.js` need updating from the CDN-loaded version to handle nested lists in the freeform response?
- Does the existing flow-view sidebar need a state machine refactor (current state: timeline-only) or can we add the analyser surface alongside without disturbing it?

## 7. Verification checklist (pre-commit)

- [ ] Settings modal opens, persists, restores.
- [ ] Toolbar status pill green/red correctly.
- [ ] Cost dialog shows non-zero estimates for a real entity.
- [ ] Real Anthropic call succeeds with a valid key (live test required).
- [ ] Structured cards render correctly.
- [ ] Freeform toggle works.
- [ ] Error paths surface clearly.
- [ ] Existing flow view, sidebar timeline, plan-md view, entity-state-board, plan-hierarchy-tree all still work (regression check).
- [ ] No console errors during happy path.
- [ ] Phase A non-persistence confirmed: reload page → summary gone.

## 8. Provenance

- T2-analyser §4 Phase A schedule + §3.12 context-building spec + §3.9.1 cost dialog spec.
- M6-analyser §4 phase table.
- Inbox item `2026-05-27.outstanding-work-analyser-endpoint` — original (superseded) spec; useful only for historical context.
