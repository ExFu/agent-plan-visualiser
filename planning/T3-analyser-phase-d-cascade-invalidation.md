---
id: T3-analyser-phase-d-cascade-invalidation
plan_kind: thematic
tier: 3
t2_parent: T2-analyser
milestone: M1.1-analyser
status: completed
---

# T3-analyser-phase-d-cascade-invalidation — Saved summaries invalidatable with cascade detection

> **For Claude:** Read T2-analyser §3.7 (Cascade invalidation), §3.2 (analysis.invalidated event), §3.10 (Flow-view rendering of invalidated summaries — already in place from Phase C). Phase B left `/api/invalidate-summary` as a 501 stub; Phase D fleshes it out + adds the browser surface.

**Goal:** Operator can mark a saved summary invalid. Doing so marks every summary that depended on it (the cascade) invalid too. Invalidated summaries are excluded from chain lookups (no longer used as "prior summary" in new analyser calls) and visually dimmed + struck through in the flow view (rendering already in place from Phase C).

**Architecture:** Server enforces the cascade — browser sends `{target_event_id, reason}`, server walks dependents and emits one `analysis.invalidated` event with the cascade list. No new schema. No new event types (`analysis.invalidated` already in v0.2.0). Browser adds an Invalidate button + confirmation dialog showing the cascade scope before the call fires.

**Tech stack:** Vanilla JS (browser), stdlib Python (server).

---

## 1. Why this T3

Without it, saved summaries are permanent. A summary captured at one point may become stale as the underlying state evolves (new events, new related plans). The operator needs a way to say "this summary is no longer accurate" — and the system needs to be honest about which downstream summaries inherit that staleness.

Cascade matters because:
- Primary on E → derived summaries on 1-hop dependents got their context partly from E. If E's primary is invalidated, those derived summaries are likely stale.
- Later summaries on E itself are downstream of an earlier summary in E's chain. Invalidating the earlier one casts doubt on the later ones too (the chain says "treat established conclusions as fixed and build on them" — if a link breaks, the chain breaks).

Conservative-over-aggressive (per T2-analyser §3.7) — false positives (over-invalidation) cost a regeneration; false negatives leave stale summaries actively misleading the next analyser pass.

## 2. Out of scope

- **Auto-invalidation on event append.** No "when entity E gets a new event, invalidate E's summaries". Operator triggers explicitly.
- **Undo / un-invalidate.** Invalidation is one-way. To restore, regenerate (which supersedes the invalidated one with a fresh primary).
- **Edit / re-author of summaries.** Same as Phase B — immutable; revise = invalidate + regenerate.
- **Cascade visualisation as a graph diagram.** The confirmation dialog lists affected event_ids; doesn't draw a fancy dependency tree.
- **Bulk invalidation** (e.g. "invalidate all summaries older than X days"). Single-target only in Phase D.

## 3. Acceptance criteria

- **Server:** `POST /api/invalidate-summary` accepts `{target_event_id, reason}` and returns `{ok: true, invalidated_event_id, cascades_to_event_ids[]}`. 404 if target_event_id not found in current summaries. 409 on dirty tree (clean-tree guard, same as save-summary).
- **Cascade detection (server):** walks the existing summaries to compute the cascade set per the rules below (§5 Step 2). Conservative — when in doubt, include.
- **Browser:** Invalidate button appears on the SavedSummary panel (next to Regenerate). Click → confirmation dialog showing target + cascade scope (which event_ids on which entities will be marked invalid). Confirm → POST.
- **Confirmation dialog:** shows total cascade count, lists affected entities, warns "This is one-way; regenerate to replace any you still need."
- **Post-invalidation:** flow view repaints with affected summary nodes dimmed + struck through (Phase C's render path; just needs the projection rebuilt). Sidebar shows the invalidated summary with an "invalidated" badge + the reason + which event invalidated it.
- **Chain lookup exclusion:** `latest_summary_by_entity` in projection.json already filters `valid = 1` (Phase B). Phase D produces the events that flip `valid = 0` via cache-build. New analyser calls will not surface invalidated summaries as "prior summary" in their context.

## 4. Files to create / modify

- **Modify** `agent-plan-tracker/scripts/serve.py`:
  - Replace `/api/invalidate-summary` stub with real handler.
  - Add `_compute_cascade(target_event_id, summaries_db)` helper.
- **Modify** `agent-plan-tracker/view/app.js`:
  - `SavedSummary._renderInner` adds Invalidate button (next to Regenerate).
  - New `PersistenceClient.invalidateSummary({target_event_id, reason})` method.
  - New `SidebarAnalyser._showInvalidateDialog(panel, entity, summary, cascadePreview)` confirmation dialog. Optionally hits server first to compute preview, OR uses client-side cascade preview (cheaper).
  - SavedSummary view shows "invalidated" badge + reason + invalidated_by_event_id when `summary.valid === false`.
- **Modify** `agent-plan-tracker/view/style.css`:
  - `.invalidated-tag`, `.invalidation-warning-banner` styles.

No schema change. No cache-build change (already handles `analysis.invalidated` events from Phase B's work).

## 5. Implementation steps

### Step 1 — Server: cascade-computation helper

In `serve.py`, add `_compute_cascade(target_event_id)`:

1. Read all summaries from events.jsonl (filter `type == "analysis.live-summary"`).
2. Locate the target summary in that list. If not found, return None (caller returns 404).
3. Walk every other summary and decide if it depends on the target:
   - **Same-entity chain:** if `S.entity_id == target.entity_id` AND `S.line_no > target.line_no`, include.
   - **Cross-entity via spawn graph:** if there's a `relationship.spawns` edge in either direction between `S.entity_id` and `target.entity_id`, AND `S.line_no > target.line_no`, include. (Conservative: any 1-hop relationship qualifies. Frontmatter-derived edges from cache-build are NOT in events.jsonl — for cascade purposes only event-sourced edges count, since they have a clear "before this event" point in time. Frontmatter is timeless. This is a deliberate constraint to avoid over-cascading.)
   - **Origin chain:** if `S.origin_summary_event_id == target.event_id` (S is a derived summary whose primary IS the target). Always include regardless of line_no since this is a definitional dependency.
4. Also include any summary whose `target` field in a previous `analysis.invalidated` event references the target — but only the target itself, not those cascades' cascades (cascading-on-already-invalidated is a noop; the existing invalidation already covers them).
5. Return the cascade set as a sorted list of event_ids.

**Verification:** unit-test-style — start with a known events.jsonl, invoke `_compute_cascade(<test-event-id>)` from a small script, eyeball the output.

### Step 2 — Server: real /api/invalidate-summary handler

Replace the 501 stub:

1. Parse JSON body for `target_event_id` + `reason`.
2. Run clean-tree check (same as save-summary). Refuse on dirty.
3. Look up `target_event_id` in events.jsonl. If not found, 404.
4. Compute cascade via `_compute_cascade`.
5. Generate event_id for the invalidation event (uuid).
6. Build `analysis.invalidated` event payload:
   ```json
   {
     "event_id": "<uuid>",
     "type": "analysis.invalidated",
     "entity_type": "plan",
     "entity_id": "<target's entity_id>",
     "actor": "al",
     "confidence": "explicit",
     "schema_version": "0.2.0",
     "attributes": {
       "target_event_id": "<target>",
       "cascades_to_event_ids": [...],
       "reason": "<reason>"
     }
   }
   ```
7. Validate against schema.
8. Append to events.jsonl.
9. Return `{ok: true, invalidation_event_id, cascades_to_event_ids}`.

### Step 3 — Browser: PersistenceClient.invalidateSummary

```js
async invalidateSummary({ target_event_id, reason }) {
  const res = await fetch("/api/invalidate-summary", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ target_event_id, reason }),
  });
  // ... same error taxonomy as save: dirty-tree (409), bad-request (400), server (5xx)
}
```

### Step 4 — Browser: Invalidate button + confirmation dialog

In `SavedSummary._renderInner`, add an Invalidate button between Regenerate and View-event-id. Disabled if `summary.valid === false`.

Click → opens a confirmation dialog. Two-stage rendering:
1. **Initial:** show target + asking "reason?" — pre-fill with a short default like "user-triggered (stale)". User can edit or pick from `["user-triggered (stale)", "underlying-events-changed", "regenerating-replacement", "other"]`.
2. **After confirm:** server-side action only happens on confirm. No client-side cascade preview — let the server compute and return the cascade list; show the result in a final success banner. (Simpler for Phase D; if UX wants pre-flight scope visibility, add `/api/invalidate-summary-preview` in Phase D.5.)

Alternative for richer UX: client-side cascade preview using the existing projection.json data (we have all summary metadata; walk dependents the same way the server will). Lean implement client-side preview — it's cheap and lets the user cancel before triggering.

### Step 5 — Browser: invalidated-summary indicator

In SavedSummary._renderInner, when `summary.valid === false`:
- Add a red banner at the top: "⚠ This summary has been invalidated." + reason + invalidated_by_event_id.
- Strike-through the structured cards (CSS).
- Disable the Regenerate button — or change its label to "Regenerate to replace".

### Step 6 — Smoke test

1. Click an existing saved summary (T2-projection's test summary).
2. Click Invalidate.
3. Confirm dialog with reason "smoke test".
4. Server returns OK + (probably empty) cascade list.
5. Reload — flow view shows the summary node dimmed + struck through.
6. Clicking that node still opens the panel — shows the invalidation banner.
7. Run a NEW analyse on T2-projection — the prompt's "Prior summary" section should now say "(none)" because the invalidated one is filtered out of `latest_summary_by_entity`.

## 6. Open questions surfaced during execution

(Add new ones during implementation. Resolve before merging.)

- Should the invalidation event itself be considered an event needing positional bracketing by a `commit.recorded`? Per the methodology: yes, it's an event in events.jsonl. The save-summary endpoint already appends events without immediately committing — the user runs the next `git commit` themselves. Same model here. The invalidation event will be in a working-tree state of events.jsonl until the user commits.
  
  Implication: the clean-tree guard semantics. Save-summary requires clean tree because the new event needs a commit to bracket it. Invalidate-summary same? Yes — keep consistent. Cleanest semantically.

- If the operator invalidates an already-invalidated summary, behaviour? Reject (400 "already invalidated") to avoid emitting redundant events.

- What if the cascade contains a summary that was already invalidated by a previous event? Skip it (it's already valid=0). Cascade list returned only includes newly-invalidated event_ids.

## 7. Verification checklist (pre-commit)

- [ ] Server `_compute_cascade` returns expected cascade for known input.
- [ ] `/api/invalidate-summary` real (no longer 501); returns cascade list.
- [ ] Clean-tree guard fires when tree is dirty.
- [ ] 404 on unknown target_event_id.
- [ ] Browser Invalidate button visible on SavedSummary view.
- [ ] Confirmation dialog renders + accepts reason.
- [ ] Post-invalidation, cache rebuild flips `valid = 0`.
- [ ] Projection's `summaries[event_id].valid = false` for the invalidated one.
- [ ] Flow view repaint shows dimmed + struck-through summary node (Phase C's path).
- [ ] `latest_summary_by_entity` excludes invalidated entries.
- [ ] New analyser call's prompt shows "(none)" for prior summary.
- [ ] No console errors.
- [ ] repack-validate 8/8 pass.

## 8. Provenance

- T2-analyser §3.7 (Cascade invalidation), §3.2 (analysis.invalidated event), §3.10 (rendering invalidated).
- M6-analyser §4 phase table.
- T3-analyser-phase-b-persistence — stubbed the endpoint at 501 with the documented payload shape; Phase D fleshes out.
- T3-analyser-phase-c-flow-rendering — already renders invalidated summaries correctly; no view-layer work duplicated here.
