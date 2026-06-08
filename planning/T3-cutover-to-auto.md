---
id: T3-cutover-to-auto
plan_kind: thematic
tier: 3
t2_parent: T2-extraction
milestone: M2-auto-extract
status: draft
---

# T3-cutover-to-auto — Validate in shadow, eyeball, flip to canonical

**Status**: Draft.
**Sits at**: T2-extraction theme, M2-auto-extract milestone. Final T3 — depends on the other three.

---

## 1. Why

The shadow-dev phase protects the canonical log while the capture skill is being tuned. This T3 is the gate between "the skill works in shadow" and "the skill is the canonical producer." It's not a code task — it's a **validation + config flip + decision record**.

## 2. What

### Step 1: Shadow validation

With `APT_DATA_DIR=.agent-plan-tracker-auto/`:

1. Do a stretch of real work on this project (at least 2–3 commits' worth).
2. Run `/apt-capture` after each unit of work.
3. Run the full pipeline (`cache-build`, `projection-emit`, `summary-emit`) against the shadow dir.
4. Open the HTML view pointed at the shadow projection.
5. **Operator eyeballs the output.** Are entities correctly identified? Are event types right? Are relationships present? Are `entity.created` events carrying frontmatter attributes? Are fulcrum events paired with decisions? Does `summary.md` look sensible?

No script, no precision/recall harness. The operator's judgment is the bar.

### Step 2: Cutover

Once satisfied:

1. Remove (or stop setting) the `APT_DATA_DIR` override. The default returns to `.agent-plan-tracker/`.
2. From this point forward, `/apt-capture` writes the **canonical** log.
3. The existing hand-rolled events (228+) are preserved — append-only. The first skill-captured events land on top.
4. Run `repack-validate.sh` — must pass end-to-end.

### Step 3: Record the decision

Emit a `decision` event recording:
- That the cutover happened.
- That the capture skill is now the canonical producer.
- That hand-rolled events are preserved as history.
- The date and the operator's judgment ("output reviewed, quality sufficient").

### Step 4: Clean up

- Delete `.agent-plan-tracker-auto/` (the shadow dir).
- Remove any shadow-specific entries from `.gitignore` if no longer needed (`.agent-plan-tracker-auto/` stays ignored as a convention for future shadow runs).

## 3. Scope

### In scope
- The validation + cutover procedure above.
- The decision event.
- Cleanup.

### Out of scope
- Improving the skill based on what the eyeball reveals — that's iterating on `T3-apt-capture-skill`, not this T3.
- Backfilling old commits (M5).
- Installing the capture-guard hook on other projects (M4).

## 4. Verification

1. ≥1 real commit's events captured via `/apt-capture` into the **canonical** `.agent-plan-tracker/events.jsonl`.
2. `repack-validate.sh` green.
3. The cutover `decision` event is present in the log.
4. Shadow dir cleaned up.

## 5. Dependencies

- `T3-configurable-data-dir` — the `APT_DATA_DIR` mechanism.
- `T3-apt-capture-skill` — the skill being validated.
- `T3-capture-guard-hook` — should be installed and working before cutover so the discipline is enforced from the start.

## 6. Open questions

None — this T3 is procedural. Any questions that surface during shadow validation feed back into the other T3s.
