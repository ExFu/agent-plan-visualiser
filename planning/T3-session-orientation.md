---
id: T3-session-orientation
plan_kind: thematic
tier: 3
t2_parent: T2-packaging
milestone: M4-fresh-install
status: draft
---

# T3-session-orientation — the session knows, without being told

**Status**: Draft.
**Sits at**: T2-packaging theme, M4-fresh-install milestone. Depends on T3-toolchain-portability. The third knowledge channel (M4 §1): skill descriptions cover *when to act*, refusals cover *when discipline slips* — this covers *ambient awareness*.

---

## 1. Why

Skills fire on recognised relevance; hooks fire on mistakes. Neither tells a fresh session "this repo is tracked" before it starts working. A downstream project shouldn't need a hand-written CLAUDE.md block for the basics — the plugin can orient the session itself.

## 2. What

### 2.1 SessionStart hook (`hooks/hooks.json`)

The plugin's Claude-side hook config (distinct from the git hooks sharing `hooks/`): on SessionStart, detect the repo fingerprint (data dir via the config resolution chain) and inject **one line** — tracked, log path, entity counts if cheap, "capture before commits (/apv-capture); land branches via /apv-merge". Untracked repo → inject nothing (silence is a feature; no nagging to adopt). Must be fast (no cache rebuild; read-only peek).

### 2.2 The formal orientation skill

`skills/using-agent-plan-visualiser/SKILL.md` — the spec floor T2-packaging §3.4 designed: full ontology reference, the instruction shape (prefer `scripts/` over regenerating SQL; save reusable queries to `scripts/local/`; cheatsheet for common ops; philosophies for judgement calls). Triggered by description for "how does this tracking system work" questions; everyday operations stay with the lean per-moment skills.

### 2.3 Cheatsheet wiring

`cheatsheet/cheatsheet.md` + worked examples get their first real content pass: the operations a downstream agent actually runs (status read, audit queries, gate-on-demand, flow view).

## 3. Scope

### In scope
- `hooks.json` SessionStart entry + detection script; the orientation skill; cheatsheet first pass.

### Out of scope
- Init (T3-project-init-flow); analyser/view features (their T2s); any always-on context heavier than one line.

## 4. Verification

1. Sandbox tracked repo: SessionStart hook emits the line (assert via hook-script direct invocation with a simulated session env).
2. Untracked repo: emits nothing, exits 0, fast.
3. Plugin-validator (or repack smoke checks) accept `hooks.json`; skill frontmatter lints.

## 5. Dependencies

- T3-toolchain-portability — `${CLAUDE_PLUGIN_ROOT}` references inside `hooks.json`.
- T2-packaging §3.1 (hooks.json spec shape).

## 6. Open questions

1. Does the one-liner include live entity counts (needs cache read — stale risk) or just the fingerprint facts? Lean: fingerprint facts only; counts are the analyser's job on demand.
2. SessionStart in Cowork — same event model? Verify alongside T3-distribution's Cowork pass.
