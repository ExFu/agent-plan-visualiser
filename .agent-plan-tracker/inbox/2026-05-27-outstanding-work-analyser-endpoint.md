---
id: 2026-05-27.outstanding-work-analyser-endpoint
entity_type: inbox-item
created_at: 2026-05-27
status: open
candidate_fate: t3
---

# On-demand "what's outstanding?" analysis via Claude — server endpoint

## The need

In the workstreams flow view, clicking the **LIVE** badge on the right tells you that an entity is still active, but doesn't tell you *what specifically remains to do*. To get that, you need to reason over:
- The entity's plan markdown (what was intended).
- The entity's event timeline (what's actually happened).
- Any open HITL questions / blockers / inbox items referencing it.
- Possibly child entities (T3s for a T2, etc).

This is a Claude task — not derivable from the cache alone. The methodology principle "the tracker substitutes for agent memory" applies in reverse here: an agent CAN reason, the cache CAN supply context, and the answer is genuinely useful for "where do I focus next on this entity?".

## What's in place (M1, this commit)

LIVE badge now opens a **timeline view** in the sidebar — full event history for that entity, derived purely from `events.jsonl`. No Claude call. Shows what's happened recently; doesn't tell you what's missing. Useful but partial.

## Proposed path forward

A small Python script that wraps `http.server` and adds an `/api/analyse?entity_id=X` endpoint:

```python
# Approximate shape
class Handler(SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith("/api/analyse"):
            entity_id = parse(self.path)["entity_id"]
            context = build_context(entity_id)  # plan md + timeline + related
            prompt = OUTSTANDING_WORK_PROMPT + context
            response = subprocess.check_output(["claude", "-p", prompt], text=True)
            self.send_json(response)
        else:
            super().do_GET()
```

Then in the view: click LIVE → `fetch("/api/analyse?entity_id=" + id)` → render the analysis in the sidebar.

**~80-120 lines of Python.** Replaces `python3 -m http.server` as the dev-serve command.

## Open design questions

1. **Context scope per entity.** T1's plan + all events = huge. Strategy: cap context to ~10K tokens, prefer recent events + immediate plan body (skip philosophies / out-of-scope). For T2/T3, narrower scope is natural.
2. **Caching.** Each analysis call costs API tokens. Should results be cached by (entity_id, last_event_id) so the same query within a session doesn't re-call?
3. **Streaming vs blocking.** Claude responses take seconds. Show a loading spinner in sidebar; render incrementally if possible.
4. **Authentication.** The endpoint shouldn't be exposed publicly — local-only by default.
5. **Failure modes.** What if `claude` CLI isn't on PATH? What if API is rate-limited? Surface useful errors in the sidebar.

## Alternative paths considered

- **Pre-compute via pipeline.** Run analysis for all live entities as part of `repack-validate.sh`, write to `live-status.json`. View reads from file. Pros: predictable cost, view is fully static. Cons: stale, won't reflect just-made changes.
- **Inline Claude via browser fetch directly to Anthropic API.** Requires user's API key in JS — major opsec issue. Don't.

## Resurrect when

- Project has more than ~5 live entities at any time AND the user is regularly hunting "what's outstanding".
- Or when running against external projects (M5) where the user is unfamiliar with the project's plans and needs help orienting.
- Or once M2's extraction pipeline lands, since infrastructure for invoking Claude via CLI would already exist and the analyser endpoint becomes a natural sibling.
