# Smoke-test summary for T2-projection

This is a hand-crafted summary used to validate the Phase B save flow without burning real Anthropic API tokens.

If you can read this in the sidebar after reloading the view, the persistence round-trip works end-to-end:

1. POST /api/save-summary → server wrapper.
2. Server: clean-tree check, schema-validate, write summaries/*.md, append event to events.jsonl.
3. cache-build picks up the new analysis.live-summary event.
4. projection.json includes latest_summary_by_entity["plan:T2-projection"].
5. SavedSummary.forEntity returns the summary; showLiveStatus renders it.
