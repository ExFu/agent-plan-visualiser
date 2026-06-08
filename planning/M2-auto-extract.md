---
id: M2-auto-extract
plan_kind: milestone
milestone_index: 2
status: planned
---

# M2-auto-extract — Automated extraction takes over

**Status**: Planned. Design validated 2026-06-02 (brainstorming pass); T3s enumerated below, files authored as each becomes active scope.
**Sits at**: Second milestone in the sequence axis. Primary theme: T2-extraction. Touches T2-storage (configurable data dir), T2-ontology (prompt aligns to the `0.2.0` schema), T2-packaging (the skill ships in the plugin's `commands/`).

---

## 1. Why this milestone

M1 proved the pipeline **hand-rolled** — events authored by hand in interactive sessions, then committed. That is untenable past bootstrap. M2 is the capability T1's steady-state vision turns on: **events get extracted from commits automatically, with no hand-authoring of each JSON line.** Real projects will never hand-roll; the tool exists to remove that cost.

M2 is **not greenfield.** The `agent-plan-tracker/scripts/backfill/` prototype already implements the sequential per-commit extractor — `extract-commit-prompt.md` (the agent brief) plus `backfill.py` (bundle builder → `claude` invocation → schema validation → append), batch-mode, resumable, ambiguity-halting. It was pulled forward to dogfood against a client project. M2's job is to **lift that proven core into a reusable module, harden it to schema `0.2.0`, and surface it as the in-session extraction the project actually uses.**

## 2. What M2 unlocks — and the two decisions that shape it

Two operator decisions (brainstorming, 2026-06-02) define M2's shape:

### 2.1 Skill-only — no autonomous `claude -p` hook in M2

The original T2-extraction design centred on a **pre-commit hook** that fires a headless `claude -p` extractor on every commit. That has two costs: a **separate, metered API call** per commit (real money) and a **~10–20s block** on every `git commit`.

M2 instead ships extraction as a **slash-command, `/apt-extract`, run by the agent already in the Claude Code session.** No separate metered call (it's the session you're already running), no commit block, and it runs whatever model the session runs (often Opus — free-er *and* higher-quality than a Sonnet headless call). This is the natural path for any Claude-Code-driven project — including this one, which is built entirely in-session.

The autonomous `claude -p` pre-commit hook is **deferred** (not cancelled). It is the right tool for committers *outside* a session — a human committing directly, CI, a teammate without Claude Code — which is really an adoption/packaging concern. It lands in a later milestone (M4-adjacent), reusing the same core. See T2-extraction (reframed 2026-06-02).

### 2.2 Shadow-dev, then full cutover

The end state is **full cutover**: `/apt-extract` becomes the canonical producer of this project's events. But the canonical hand-rolled log (223 rich events) must not be corrupted while the extractor is still being tuned. So:

- **Shadow phase** — the extractor writes to a *configurable* data directory (`APT_DATA_DIR=.agent-plan-tracker-auto/`, gitignored, throwaway). Iterate the prompt against real apt commits; build cache/projection/summary/view from the shadow dir; the canonical `.agent-plan-tracker/` is never touched.
- **Cutover** — once trusted, drop the override so the default returns to `.agent-plan-tracker/`. From the cutover commit forward, `/apt-extract` writes the **canonical** log. The existing 223 hand-rolled events are **preserved** as history (append-only — we do **not** re-extract the past). Steady-state events become shallower-but-automatic; bootstrap richness was the exception, not the rule, and the in-session skill recovers much of it anyway (full context + enrich-before-seal).

The configurable data dir is also **permanent product capability** — M4 installs need it — not just a dev-safety hack.

## 3. What M2 explicitly does NOT include

- **Autonomous `claude -p` pre-commit hook + installer** — deferred (see §2.1); later/M4-adjacent.
- **Merge-to-main cleanliness gate, merge-conflict handler** — that's M3 (already scheduled in T2-extraction §3.7–3.8 / §4).
- **Fresh-project install / packaging** — M4.
- **Foreign-project backfill + retrospective mapping note** — M5 (though M2 hardens the core M5 reuses).
- **Sub-agent recursion for oversized diffs** — only if a real commit overflows the in-session context; the in-session agent has a large window and can spawn sub-agents itself. Out of M2 v1 unless friction surfaces.
- **`needs-review/*.md` ambiguity protocol** — *dropped* for the in-session path: when the agent is unsure it simply **asks the operator mid-session**. (The filesystem-note protocol was only needed because a headless hook had no human to ask; it remains relevant if/when the deferred hook lands, and for unattended catch-up runs — see §7 Q4.)

## 4. How M2 delivers — T3 tasks

Dependency order in brackets. Theme owner in italics.

1. **`T3-extraction-core`** [foundation] — *T2-extraction.* Lift `backfill.py`'s reusable functions (`build_bundle`, `invoke_extractor`, `parse_events_response`, `validate_events`) into a shared `core` module both the skill and `backfill.py` import. Update the extraction prompt **`0.1.0 → 0.2.0`**: it predates the `analysis.*` events, the `relationship.reattached` `from_parent`/`to_parent` shape, the `dead → closed` term, the "agents emit `entity.created` for plans" rule, and the milestone-parent rule. No logic fork between triggers.
2. **`T3-configurable-data-dir`** [parallel to #1] — *T2-storage.* A shared path resolver (`APT_DATA_DIR` env → optional committed default → `.agent-plan-tracker/`). Repoint `cache-build.py`, `projection-emit.py`, `summary-emit.py`, `serve.py`, `backfill.py` to use it instead of hardcoding. Gitignore `.agent-plan-tracker-auto/`.
3. **`T3-apt-extract-skill`** [depends #1, #2] — *T2-extraction.* The `/apt-extract` command in the plugin's `commands/`. **Pending mode** (default): extract events for the staged diff + intended message, show the agent the events already pending in the open block, emit only the **delta**, append to the configured dir, review-before-seal. **Catch-up mode** (`/apt-extract HEAD~N..HEAD`): the backfill primitive surfaced interactively, over already-sealed commits. Ambiguity → ask the operator in-session.
4. **`T3-extraction-idempotency`** [depends #3] — *T2-extraction.* Idempotency at the granularity of a **sealed commit's event block** (the run terminated by its `commit.recorded`). The **open (pending) block is deliberately accumulative** — repeated `/apt-extract` appends are legitimate (work → extract → more work → extract → one commit seals all); no guard fires there. The skip-guard applies **only** to re-extracting an *already-sealed* commit in catch-up mode (`--force` to override). Fixture tests cover both.
5. **`T3-cutover-to-auto`** [depends #3, #4] — *T2-extraction.* Validate `/apt-extract` in the shadow dir over a representative range of apt's own commits; judge quality (§7 Q1); flip the config to the canonical dir; record the cutover `decision`; produce ≥1 real commit's events via the skill into the canonical log; confirm `repack-validate` green.

## 5. Definition of done

M2 is complete when:

- A shared extractor **`core`** module exists; the extraction prompt is at schema **`0.2.0`**; both `/apt-extract` and `backfill.py` use the core (no logic fork).
- The data directory is **configurable** via `APT_DATA_DIR`; every script honours it; the shadow dir works end-to-end (cache/projection/summary/view all build from it).
- **`/apt-extract`** works in-session in both modes: pending (delta-aware, accumulative-safe, review-before-seal) and catch-up (sealed-commit skip-guard, `--force`). Ambiguity asks the operator.
- The extractor is **validated in shadow** against a range of apt's own commits — events are sensible (entities, types, relationships correct).
- **Cutover performed**: config points at the canonical `.agent-plan-tracker/`; the existing 223 hand-rolled events are preserved; ≥1 real commit's events are produced by `/apt-extract` into the canonical log; `repack-validate.sh` passes end-to-end; the cutover is recorded as a `decision`.

## 6. Dependencies

- **M1-bootstrap** (complete) — the pipeline M2 feeds (cache/projection/summary/view) already exists and is green.
- **T2-ontology** — the `0.2.0` schema the hardened prompt targets.
- **T2-storage** — owns `T3-configurable-data-dir`; M2's extractor appends in storage's format.
- **T2-packaging** — the skill ships in the plugin's `commands/`.
- The `scripts/backfill/` prototype — the proven core M2 refactors and hardens (not rebuilt from scratch).

## 7. Open questions (M2-specific)

1. **Cutover quality bar.** What is "good enough" to cut over? We chose *not* to build a formal precision/recall comparison harness against the hand-rolled log. Open: is an operator eyeball sufficient, or do we want a light spot-check diff (auto vs hand-rolled for a handful of overlapping commits)? Resolve in `T3-cutover-to-auto`.
2. **Open-block delta detection.** On a second `/apt-extract` of an open block, the staged diff is cumulative (A+B). Does the skill tree-diff since the last extract, or rely on the in-session agent reading the pending events and emitting only the new ones? Lean agent-judgment first; add tooling only if it proves unreliable. Resolve in `T3-apt-extract-skill`.
3. **Skill naming / location.** `/apt-extract` is the working name; lives in the plugin's `commands/`. Confirm naming against any future command-namespace convention (T2-packaging).
4. **Unattended catch-up ambiguity.** In-session ambiguity = ask the operator. But a long unattended catch-up run has no one watching — does catch-up mode retain a lightweight halt-and-record fallback (a slim version of the dropped `needs-review` note) so it doesn't silently guess? Lean yes for catch-up only. Resolve in `T3-apt-extract-skill`.
5. **Extraction model.** In-session uses whatever the session runs (often Opus). Acceptable and arguably better than forcing Sonnet. No action unless cost/consistency bites.

## 8. After M2

M3 adds the merge-to-main cleanliness gate over the projections M1 produces (orphans, fulcrum-without-decision, etc.). M4 packages for distribution and onboarding to fresh projects — and is where the deferred autonomous `claude -p` pre-commit hook naturally lands (for non-Claude-Code committers), reusing M2's `core`. M5 backfills existing/foreign projects, reusing the same core via `backfill.py`.
