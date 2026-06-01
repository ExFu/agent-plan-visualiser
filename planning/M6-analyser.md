---
id: M6-analyser
plan_kind: milestone
milestone_index: 6
status: completed
---

# M6-analyser — On-demand "what's outstanding?" analyser, rolled out across five phases

**Status**: Completed (2026-06-01). All five phases A–E landed (6/6 T3s); the analyser is operational against this project. Reparented to M1-bootstrap via `relationship.reattached`; label/index grandfathered for historical honesty.
**Sits at**: Sixth milestone in the sequence axis. Touches one theme: T2-analyser. Indirectly extends T2-ontology (new event types), T2-storage (summary files), T2-projection (flow-view rendering, sidebar surfaces).

**Position in M-axis ordering note:** Bootstrap delivered (M1). Auto-extract (M2), cleanliness gates (M3), packaging (M4), ingest (M5) are queued but no work has begun. M6 is being prioritised ahead of M2-M5 because the analyser is immediately useful against the project's own growing event log — operator demand is real and present, while M2-M5 deliver value only at scale.

---

## 1. Why this milestone

The project's flow view (delivered in M1) shows what's *happened*. The analyser closes the gap to **what's outstanding**, which is the question an operator actually asks. M6 ships that capability incrementally — five phases, each independently shippable, with the cheapest proof-of-value loop landing first.

M6 also exercises new surfaces that flow back into the methodology:

- **New event types** (analysis.live-summary, analysis.invalidated) extend T2-ontology's catalogue. This is the first ontology evolution after the v0.1.0 bootstrap.
- **Server wrapper** appears for the first time, taking over from `python3 -m http.server`. Establishes the pattern for any future server-side concerns.
- **Summary chain semantics** introduce the first non-event-driven supersession (primary-vs-derived). Tests whether the ontology can absorb this without strain.

By the end of M6, the analyser is fully operational on this project — ad-hoc per-entity calls, opportunistic dependent caching, cascade invalidation, global mode with prompt-caching cost amortisation. The capability proves out against ~20 live entities.

## 2. What M6 unlocks

After M6:

- The HTML view's LIVE badge has two paths: **Show timeline** (cache-only, free) and **Analyse outstanding** (Claude call, gated by cost dialog).
- Settings modal stores Anthropic API key + per-call model picker in `localStorage`.
- Saved live summaries persist as events in `events.jsonl` + markdown files in `.agent-plan-tracker/summaries/`. They replay through cache-build like any other event.
- Each primary analysis on E also produces derived summaries for E's 1-hop dependents — opportunistic caching to avoid wasting context.
- Cascade invalidation: invalidating one summary marks downstream dependents invalid (conservative-over-aggressive).
- Bulk/global mode: "Analyse all live" produces primary summaries for every live entity in one pass with Anthropic prompt caching amortising shared context.
- Flow view renders saved summaries as distinct nodes; invalidated summaries dimmed/struck-through.
- Server wrapper (~150 lines Python) replaces `python3 -m http.server` with three endpoints (`/api/clean-check`, `/api/save-summary`, `/api/invalidate-summary`) — local-bind-only, no LLM credentials.

**End-of-M6 acceptance test**: from a clean checkout, start the new server wrapper. In the flow view, click LIVE on T2-projection. Confirm the cost dialog. See a useful structured + freeform summary in the sidebar. Save it. Reload the view. Summary is still there (replayed via cache-build). Invalidate it. See the cascade marker. Click "Analyse all live (global)". See progress UI; complete in <5 min for ~20 entities; cache-hit ratio >80%.

## 3. What M6 explicitly does NOT include

- **Automatic re-analysis on event append.** No "every commit re-summarises live entities" mode. On-demand only. Auto-triggering is out of scope per T2-analyser §8.
- **Multi-model ensembling** (one model per summary).
- **Summary editing** — generated summaries are immutable; revise = invalidate + regenerate.
- **Streaming responses** — blocking Claude calls for v1. Streaming deferred until perceived latency is painful.
- **Cross-project summaries** — analyser fires against the current project's tracker only. Cross-project orientation is out of scope per T1 §7.
- **Hand-authored live summaries** — the analyser flow is the only producer of `analysis.live-summary` events. External authoring possible but unsupported.

Keeping these out keeps M6 phaseable. Each phase is independently valuable; if M6 stalls at any phase, the prior phases remain useful.

## 4. How M6 delivers — 5 phases / 5+ T3 tasks

Each phase has at least one T3. Phase A's T3 (T3-analyser-phase-a-ephemeral) is drafted; later T3s author as each phase becomes the next active scope.

| Phase | T3 (initial) | Theme touched | Status |
|---|---|---|---|
| A — Ephemeral browser-only | `T3-analyser-phase-a-ephemeral` | T2-analyser | draft |
| B — Persistence + new event types + server wrapper + opportunistic derived | `T3-analyser-phase-b-persistence` (tbw) | T2-analyser, T2-ontology, T2-storage | pending |
| C — Flow-view rendering | `T3-analyser-phase-c-flow-rendering` (tbw) | T2-analyser, T2-projection | pending |
| D — Invalidation + cascade | `T3-analyser-phase-d-cascade-invalidation` (tbw) | T2-analyser | pending |
| E — Global update mode | `T3-analyser-phase-e-global-mode` (tbw) | T2-analyser | pending |

Total candidate effort per T2-analyser §4: ~9h spread across phases. Phase A is the first slice and the only one with a written T3 at the time of this milestone's creation.

## 5. Ordering rules within M6

- Phases execute in **A → B → C → D → E** order. Each builds on the prior.
- A may ship and the milestone pause indefinitely if Phase A surfaces design friction. Milestone status stays `live` until E lands.
- B's schema additions to T2-ontology require a `schema_version` bump consideration (T2-analyser §7 Q7) — decision logged during B authoring.
- Authoring Phases B-E's T3 plans is a per-phase activity, not a milestone-opening batch — defer until Phase A's empirical lessons are in.

## 6. Dependencies

- M1 delivered the flow view + LIVE badge + sidebar infrastructure that the analyser plugs into. **Met.**
- T2-analyser §3 captures the architectural design; this milestone executes against it. **Met.**
- T2-ontology will absorb new event types during Phase B. Authoring those schema branches is part of Phase B's T3.
- T2-storage will absorb the `.agent-plan-tracker/summaries/` convention during Phase B.

## 7. Risk register

- **Anthropic browser-direct policy change** — if `anthropic-dangerous-direct-browser-access` is deprecated mid-M6, the architecture flips to server-side proxy (the swap-out is localised; see T2-analyser §6). Mitigation: keep the LLM call thin and well-isolated in browser JS.
- **Cost dialog estimator drift** — char-count proxy can be ±15-25% off. Mitigation: calibration data captured on every save (T2-analyser §3.9.1); promote to tiktoken-equivalent JS if drift exceeds ±25% per T2-analyser §7 Q11.
- **Phase A surfaces fundamental design issue** — possible. Mitigation: Phase A is ephemeral, so backing out is free. Reauthor T2-analyser if needed before Phase B.
- **Server wrapper breaks dev-serve UX** — currently `python3 -m http.server` is one command. New wrapper must be no harder to start. Mitigation: ship as `agent-plan-tracker/scripts/serve.py` with a one-liner CLI signature; document override.

## 8. Provenance

- Sourced from T2-analyser §3 (architecture) and §4 (phase candidates).
- Inbox item `2026-05-27.outstanding-work-analyser-endpoint` was the kernel; superseded by T2-analyser on the same day as this milestone is created.
- Phase ordering matches T2-analyser §4 directly.

## 9. Addendum — reparented to M1-bootstrap (2026-06-01)

This milestone was originally recorded as spawned by `T2-analyser` (event `c2a00004`). That crossed the two orthogonal axes the methodology keeps separate ([[T1-top-level]] §2.4): a milestone (the *when*) must not hang off a theme (the *where*). Per the milestone-parent rule now codified in [[T1-top-level]] §2.4.0, a milestone hangs off a Tier-1 plan. Conceptually M6 is a sub-milestone of M1 — *"M6 should really have been M1.1"* — because the analyser shipped as part of getting this project working end-to-end.

**Resolution:** `M6-analyser` is **reattached** to `M1-bootstrap` via a `relationship.reattached` event (the first real use of that primitive — designed in the bootstrap, never previously exercised). The label `M6-analyser` and `milestone_index: 6` are **kept** for historical honesty (the id is load-bearing as a filename, and renaming would churn ~20 events); the dotted `Mn.p` notation is forward-looking methodology for future sub-milestones, not a retro-rename. In derived projections the prior `T2-analyser spawns M6` edge is now suppressed and replaced by `M1-bootstrap spawns M6` (see [[T2-ontology]] §3.6). This is a parent correction only — none of the architecture, phases, or provenance above changes.
