---
id: T3-analyser-phase-e-global-mode
plan_kind: thematic
tier: 3
t2_parent: T2-analyser
milestone: M6-analyser
status: draft
---

# T3-analyser-phase-e-global-mode — "Analyse all live" with Anthropic prompt caching

> **For Claude:** Read T2-analyser §3.8 (Global update mode + prompt caching) and §3.13 (Opportunistic derived caching — suppressed in global mode). This is the final phase of M6. Built on top of Phase A/B/C/D's surfaces — analyser pipeline, persistence, flow-view rendering, invalidation.

**Goal:** "Analyse all live (global)" button on the toolbar runs a single sweep over every currently-live entity, producing one `analysis.live-summary primary` event for each. Shared context (T1 + recent project events + live-entities index) is sent ONCE with an Anthropic `cache_control: {type: "ephemeral"}` block and reused on every per-entity follow-on call, so the effective per-entity cost is mostly output tokens + per-entity-tail input.

**Architecture:** Two new browser modules — `GlobalContextBuilder` (shared-context assembly) + `GlobalAnalyseClient` (per-entity follow-on call with cache_control) — plus a toolbar button + a multi-line progress UI in a new modal. Reuses `PersistenceClient.saveSummary` for every save. Derived-summary emission is suppressed in this mode (every entity gets a primary anyway).

**Tech stack:** Vanilla JS, fetch with `cache_control`. No backend changes; the server's `/api/save-summary` handles both single-entity and global-batch saves identically.

---

## 1. Why this T3

Without global mode, refreshing the project's analytical picture means clicking through every live entity (~23 right now) one by one. That's 23 sequential calls each paying full input-token cost on the shared context (T1 + cross-entity event stream + live-entities index). With prompt caching, the shared portion is billed at the cached-read rate after the first request → ~5× cheaper input on subsequent calls. For 23 entities that's a meaningful $-saving.

The mode is also operationally useful for "session-start orientation" — run global once when picking up a session, get a fresh sidebar-clickable summary for every live entity simultaneously.

## 2. Out of scope

- **Pre-Anthropic cache_control fallback.** If the cache header isn't respected (e.g. unsupported model), the requests still succeed; the cost is just higher. Don't bail.
- **Parallel per-entity calls.** Sequential is simpler and respects Anthropic's rate limits more politely. Parallelism is a Phase F optimisation.
- **Auto-trigger on commit.** Global mode is operator-initiated only.
- **Streaming responses.** Blocking calls only (each entity completes before the next fires).
- **Cross-session resumability.** If the user closes the tab mid-run, no resumption. The saved summaries up to that point persist.
- **Partial-failure rollback.** If summary 7 of 23 fails, the first 6 stay saved. Progress UI surfaces what completed.

## 3. Acceptance criteria

- "Analyse all live (global)" button in the toolbar (next to the API-key pill). Disabled when no API key.
- Click → cost-warning dialog showing:
  - Number of live entities to analyse.
  - Estimated total cost (input + output, with cache-hit projection on input).
  - Red accent (this is multi-dollar territory for a real project).
  - Hard confirm gate.
- On confirm, a modal opens with a progress list showing each live entity + status (queued / running / saved / failed) + running cost total.
- Each per-entity call uses Anthropic `cache_control: ephemeral` on the shared-context block.
- Each successful response saves via `/api/save-summary` (no derived emissions — `derived: []`).
- Telemetry per save: `prompt_cache_hit_ratio` in event attributes (computed from `usage.cache_read_input_tokens / usage.input_tokens` if available).
- On completion, modal shows summary: N saved, M failed (with reasons), total $ actual cost, average cache-hit ratio.
- Pre-flight clean-tree check at start. Clean-tree is also re-checked between every save; if tree goes dirty mid-run (e.g. user committed something concurrently), the run halts gracefully and reports.
- Browser DOES NOT have to be open continuously — but if user closes the tab the run aborts. Don't try to background it.

## 4. Files to create / modify

- **Modify** `agent-plan-tracker/view/index.html`:
  - Add "Analyse all live" button to toolbar.
  - Add `#global-modal` modal markup.
- **Modify** `agent-plan-tracker/view/app.js`:
  - New `GlobalContextBuilder` module — assembles the project-level shared context once per run.
  - New `GlobalAnalyseClient` module — per-entity call with `cache_control`.
  - New `GlobalAnalyser` UI controller — toolbar button → cost dialog → progress modal → save flow.
- **Modify** `agent-plan-tracker/view/style.css`:
  - `.global-progress-table`, `.global-row`, `.global-status-*` for the progress UI.

No backend / schema / cache changes.

## 5. Implementation steps

### Step 1 — GlobalContextBuilder (shared prefix)

Build a single shared-context block to send with every per-entity call:

```
You are doing a global pass over a planning-driven, event-sourced project.

## Project (T1 plan)
[T1-top-level.md body, ~5-8k tokens]

## Project-wide recent event stream (last ~50 events)
[chronological listing of last N events across all entities]

## Live entities index
- entity_id (kind/tier, derived_state): one-line summary
- ... ~23 entries
```

This block is identical for every per-entity call within a single global run. Send it as the first `content` block in `messages[0]`, marked `cache_control: {type: "ephemeral"}`. The minimum cacheable size is 1024 tokens — easily hit by T1 alone.

### Step 2 — Per-entity follow-on prompt

For each live entity, the per-entity tail says:

```
## Now focus on: <entity_id>
[entity's plan_md body]
[entity's full event timeline]
[1-hop related entities one-liners — same as Phase A]
[prior valid summary, if any]
```

Plus the same system prompt as Phase A asking for the structured JSON + freeform output. `derived_summaries` field is OMITTED from the schema (Phase E suppresses derived per §3.13 — every entity gets a primary in this mode).

### Step 3 — GlobalAnalyseClient

```js
async runOne({ apiKey, model, sharedPrompt, perEntityPrompt }) {
  const body = {
    model,
    max_tokens: 2048,
    system: GlobalContextBuilder.systemPrompt(),
    messages: [{
      role: "user",
      content: [
        { type: "text", text: sharedPrompt, cache_control: { type: "ephemeral" } },
        { type: "text", text: perEntityPrompt },
      ],
    }],
  };
  // ... same fetch + parsing as AnalyseClient, but reading usage.cache_read_input_tokens
  // for cache-hit-ratio telemetry.
}
```

### Step 4 — Toolbar button + cost dialog

In the toolbar, add `<button id="btn-global-analyse" class="btn-primary" disabled>✦ Analyse all live</button>`. Enable when `Settings.hasKey()`.

Click → builds shared prompt + estimates cost for N entities (assume 80% cache hit on input after first call) → opens cost-warning dialog with red accent. Confirm → opens progress modal.

### Step 5 — Progress modal

A table with one row per live entity:
- entity_id (clickable to open the saved summary once it's done)
- status pill: queued (grey) / running (blue spinner) / saved (green) / failed (red)
- per-entity cost (filled when complete)
- cache-hit-ratio for that call

Below: running totals — N/M complete, total cost so far, average cache-hit ratio.

Cancel button: stops the run (after the in-flight call completes); shows partial results.

### Step 6 — Execution loop

Pseudocode:
```js
for (const entity of liveEntities) {
  row.status = "running";
  try {
    const result = await GlobalAnalyseClient.runOne({...});
    // Build primary event from result (strip derived_summaries if present — defensive)
    const event = {entity_type, entity_id, attributes: {...}};
    const md = result.freeform || result.raw;
    const resp = await PersistenceClient.saveSummary({primary: {event, freeform_md: md}, derived: []});
    row.status = "saved";
    row.eventId = resp.primary_event_id;
    runningCost += actualCost;
  } catch (e) {
    row.status = "failed";
    row.error = e.userFacing?.() || e.message;
  }
  // Re-check clean tree between saves
  const cc = await PersistenceClient.cleanCheck();
  if (!cc.clean) { halt with banner; break; }
}
```

### Step 7 — Smoke test approach

Real Anthropic calls cost actual money on a real key. Two test paths:

(a) **End-to-end with throttled scope.** Set a tiny project (1-2 live entities) and run global mode against it with a real key. Validate the cache_control header is included, response usage shows cache_read_input_tokens > 0 on the second call, all events save correctly.

(b) **Server-side stub.** A test mode the operator can flip from the toolbar that mocks Anthropic responses with a fixed structured payload. Each "call" returns deterministically, no tokens burned. Lets us exercise the orchestration code without billing.

Lean (a) — but only if a real key is available + cost is acceptable for this project (~$0.50-1.50 estimated for 23 entities on Sonnet 4 with caching). If not, (b) is the fallback.

For Phase E's first smoke, the orchestrator may opt to exercise the code path via curl payloads to `/api/save-summary` directly, skipping the actual Anthropic call entirely. The code paths around the call are what matter for verification at this stage — the LLM call itself is tested in Phase A.

## 6. Open questions surfaced during execution

(Add new ones during implementation.)

- Does the chosen Sonnet 4 / Opus 4 model respect `cache_control` header? Confirmed yes per Anthropic docs; verify empirically on the first call by reading `usage.cache_creation_input_tokens` from the response.
- Should the progress modal allow drilling into a saved summary mid-run? Lean yes for completed rows — click → opens SavedSummary in the existing sidebar (closes the modal). Failed rows expose the error.
- If the user cancels mid-run, do we still need to commit before any future invalidate-summary call (since events.jsonl has the partial saves)? Yes — same clean-tree discipline. Surface this in the cancellation banner.

## 7. Verification checklist (pre-commit)

- [ ] Toolbar button visible, disabled without API key.
- [ ] Cost dialog appears with red accent + N entities + estimated cost.
- [ ] Progress modal renders with one row per live entity.
- [ ] Each per-entity call sends `cache_control: ephemeral` on the shared block (verify via DevTools network tab in browser).
- [ ] Each successful response saves via /api/save-summary; primary_event_id returned.
- [ ] Cache rebuild reflects the new summaries; projection's latest_summary_by_entity populated for each.
- [ ] Failed rows show error reason; saved rows show event_id.
- [ ] Running cost total + average cache-hit ratio displayed.
- [ ] Cancel button stops the run cleanly.
- [ ] Clean-tree halt between saves works when the tree is dirtied mid-run.
- [ ] No console errors.
- [ ] No regression on Phase A/B/C/D surfaces.
- [ ] repack-validate 8/8 pass.

## 8. Provenance

- T2-analyser §3.8 (Global update mode + prompt caching), §3.13 (derived suppressed in global), §3.9.1 (cost-warning dialog).
- M6-analyser §4 phase table.
- T3-analyser-phase-a/b/c/d — Phase A's AnalyseClient is the model; Phase B's PersistenceClient.saveSummary is reused as the save sink; Phase C's flow-view renders the saved summaries as new nodes; Phase D's invalidation is unaffected by global mode (an invalidated summary is still excluded from the prior-summary slot in Phase E's per-entity tail).
