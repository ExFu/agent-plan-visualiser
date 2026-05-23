---
id: 2026-05-23.autopilot-misuse-meta-observation
entity_type: inbox-item
created_at: 2026-05-23
status: open
candidate_fate: tool
---

# Meta — autopilot invoked for documentation persistence (not its intended use)

The `oh-my-claudecode:autopilot` skill is designed for "Full autonomous execution from idea to working code". This session used the autopilot magic-keyword machinery to drive a *documentation / persistence* pass in a planning framework — not code generation.

## What worked anyway

- The "boulder never stops" principle scoped the persistence pass usefully — kept the agent moving through all the migration work without pausing for incremental check-ins.
- The parallel-batch discipline (encouraged by the hook reminders) accelerated the work.
- The phase-by-phase mental model (Expansion → Planning → Execution → QA → Validation) loosely mapped onto: Audit → Migrate-T2s → Materialise-philosophies → Inbox → Commit, even though no actual code was written.

## What was missing

- Autopilot's phases assume code artefacts at every stage. For documentation work, there's no QA phase (no tests to run) and no Validation phase (no security review of a plan file). The skill's "do all 5 phases" instruction had to be adapted.
- The skill's expected output (working verified code) didn't match the actual output (persisted plans + philosophies + inbox items). Final-checklist items were inapplicable.

## Tooling ideas this suggests

Several candidate tools / skills surfaced from this experience:

- **`/persist`** — comprehensive snapshot to disk of conversation state. Aimed at planning sessions where the value is in the captured decisions, not in any code. Could be a skill that walks the conversation and proposes which sections become plans / decisions / philosophies / inbox items.
- **`/migrate-plans`** — restructure plans without losing content. The kind of work this session did (move T1 §4 detail into T2s). Could be a skill that takes a "move content from X §Y to Z" instruction and does the migration safely with provenance.
- **`/dogfood-pass`** — periodically run on a dogfooding project to flag where the methodology is being violated (e.g. "T1 has architectural detail; consider migrating to T2-X"). Catches the kind of methodology drift this session was correcting.

## Connection to other work

- This experience itself is data for the empirical-prompt-architecture philosophy: autopilot's prompt is heavily code-oriented, and using it for documentation pulls it off its design centre. A dedicated `/persist` skill would have a cleaner mental model.
- The fact that the methodology drift went unnoticed until pointed out (Claude was putting architectural detail in T1 instead of T2) is itself a signal that automated methodology-conformance checking (a `/dogfood-pass` skill or a projection in T2-projection) has real value.

**Resurrect when:** Anyone (Alastair or other users) finds themselves invoking autopilot for non-code work, or when designing a new skill that fits the persistence / migration / dogfooding pattern.
