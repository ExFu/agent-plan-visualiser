---
id: T3-apt-merge-skill
plan_kind: thematic
tier: 3
t2_parent: T2-extraction
milestone: M3-clean-gate
status: draft
---

# T3-apt-merge-skill — branch-side reconciliation doctrine

**Status**: Draft.
**Sits at**: T2-extraction theme, M3-clean-gate milestone. Final T3 — consumes `gate-check`. Supersedes the `T3-merge-conflict-handler` candidate (T2-extraction §4): doctrine + agent + skill, not an arbitration program.

---

## 1. Why

Bringing a branch's event log to main is the one moment append-only discipline is genuinely at risk: a textual conflict on `events.jsonl` is the single most tempting moment for a human or agent to hand-edit the log. The doctrine: **the in-session agent reconciles on the branch, before main moves.** Main only ever receives gate-green logs. This is the same hygiene PR workflows already practise — update your branch, resolve there, then land clean.

## 2. What — `skills/apt-merge/SKILL.md`

1. **When**: a branch is ready for main.
2. **Pick the lightest sufficient integration.** Refresh main. Main unmoved → fast-forward, done. Main moved without touching `events.jsonl` → **rebase is acceptable and preferred** (seals match `message_first_line`, not commit hashes — the log is rebase-tolerant by design). Both logs grew → merge: there is actually something to merge.
3. **The `events.jsonl` conflict is the designed trigger, never suppressed.** No union merge driver, ever — auto-resolution would hide the one moment the agent must engage. The recipe: **main's log is the prefix; the branch's blocks append after; never reorder or edit within blocks.** (Append-only, generalised to the branch level: main's line positions never move.)
4. **Semantic pass.** Scan both tails for same-entity touches. Contradiction — closed on one side, progressed on the other; competing renames — → surface both stories to the operator with a recommendation. Their ruling becomes reconciliation events (`entity.reopened` + `decision`, or whatever they rule) in a fresh block **sealed by the merge commit**. The capture guard firing on a conflicted merge is correct behaviour — reconciliation is capturable work. A clean merge has nothing to capture and rightly bypasses the hooks.
5. **Run `gate-check`.** Only a green log lands on main.
6. **Degrades gracefully**: for non-agentic users the skill doubles as a documented manual procedure.

## 3. Scope

### In scope
- The skill file; the doctrine prose (which also corrects T2-extraction §3.8's program-shaped design — correction note added there).

### Out of scope
- Gate internals (T3-integrity-composite) and wiring (T3-gate-core).
- Any auto-arbitration program, `merge-conflicts/` filesystem protocol, or custom merge driver.
- CI adapters.

## 4. Verification

1. **Self-referential acceptance test**: this worktree branch (carrying all of M2+M3) is brought to main via the skill, `gate-check` green, operator-triggered — M3's delivery transits its own doctrine. (This is also M3-clean-gate §6's closing condition.)
2. Sandbox two-branch contradiction exercise: logs that close and progress the same entity on different branches → the skill surfaces the contradiction; the post-reconciliation log passes the gate. (Stretch if #1 already exercises a real conflict — M3-clean-gate §8 Q3.)

## 5. Dependencies

- T3-gate-core — `gate-check`.
- `/apt-capture` — sealing the reconciliation block; the capture-guard semantics it defines.

## 6. Open questions

1. **Does a clean merge commit need a seal?** Lean no — nothing happened to the log (M3-clean-gate §3.2); positional rollup tolerates sealess commits.
2. **Sandbox test required or stretch?** (M3-clean-gate §8 Q3 — resolve when the real merge's conflict surface is known.)

## 7. Build notes (2026-06-10)

Shipped: `skills/apt-merge/SKILL.md` (the doctrine — lightest-integration table, the prefix+append recipe, semantic pass, seal-by-merge-commit, gate-then-ff landing, manual degradation §6) and `tests/gate/run-aptmerge-sandbox.sh` (21 assertions, 3 cases). Settled during the build:

- **§6 Q1 resolved: no.** A clean merge bypasses the pre-commit hook by git's own design — nothing happened to the log, so no capture and no seal; sealless merge commits are tolerated (positional rollup skips them, seal↔commit checks log→git only). A *conflicted* merge is the designed opposite: the guard fires correctly, the minimum capture is a seal-only block, and contradictions add reconciliation events before the seal. Both halves sandbox-asserted.
- **§6 Q2 resolved: required, and built.** The real merge (this branch → main) is a pure fast-forward — main sits at the merge-base — so the self-referential acceptance test exercises no conflict. The sandbox carries the contradiction verification (closes M3-clean-gate §8 Q3 the same way).
- **`check_resurrection` learns the healed shape** (cross-T3 change, documented like gate-core's schema-home fix): a later `entity.reopened` resolves the violations before it for that entity. Every blocking check must be **append-only-repairable** — the recipe linearises a cross-branch contradiction as closed-then-progressed, and nothing can ever be inserted before the violation. What blocks at the boundary is the *unresolved* contradiction; the ruling's paired decision is guaranteed by the fulcrum check; a reopen heals only what precedes it.
- **Gate placement (skill §5)**: run `gate-check` *after* concluding the merge commit, from the branch — both parents reachable, every seal resolves (mid-merge, main's seals would look orphaned). "Before main moves" is the invariant, not "before the merge commit exists".
- **aptlib TOML fallback** (build-surfaced): stock macOS python3 is 3.9.6 — no `tomllib` — and `apt_config` silently returned `{}` with a config *present*: gate policy ignored, and a configured `[storage] data_dir` would silently misroute data. Added `_parse_toml_minimal` (strict subset: tables, strings, booleans, integers, single-line string arrays); anything outside the subset fails loud per M3 §3.3's own doctrine. The fixture suite's config-flip cases now exercise whichever parser path the host python provides.
