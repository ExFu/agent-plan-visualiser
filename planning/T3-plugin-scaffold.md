---
id: T3-plugin-scaffold
plan_kind: thematic
tier: 3
t2_parent: T2-packaging
milestone: M1-bootstrap
status: draft
---

# T3-plugin-scaffold — Create plugin directory structure

**Status**: Draft. Ready for execution.
**T2 parent**: T2-packaging
**Milestone**: M1-bootstrap

---

## 1. Why this T3

M1 needs a plugin scaffold to land everything else into. Schemas, scripts, views, philosophies, skills — all need a defined home. This T3 creates that home and verifies it loads as a Claude Code plugin.

Without the scaffold, every other M1 T3 has nowhere to put its output.

It also resolves T2-packaging's first open question (manifest format) by forcing investigation rather than guessing.

## 2. Out of scope

- Plugin distribution / npm packaging — M4 (`T3-npm-package-config`).
- Hook installation scripts — M2.
- Actual *content* for skills, philosophies, commands, schemas, view — other T3s.
- Final plugin naming — working name `agent-plan-tracker` is fine for M1; revisit in M4.
- `.keep` vs `.gitkeep` vs README.md as directory placeholder — pick one and use it consistently; no strong reason to overthink.

## 3. Acceptance criteria

- A `agent-plan-tracker/` directory exists at the repo root containing the canonical subdirectory layout per T1 §4.11.
- A minimal plugin manifest is present and valid against whatever schema Claude Code expects (investigated in Step 1).
- The plugin is loadable in Claude Code (verified by Claude reading the manifest without error, or by `claude` CLI / equivalent reporting no validation issues).
- `README.md` at plugin root explaining purpose + status + pointers to T1 and current milestone.
- Every subdirectory contains a placeholder file (e.g. `.keep` or a README) so the directory survives in git despite being empty of real content.

## 4. Steps

### Step 1 — Discover Claude Code plugin manifest format ✓ (resolved)

**Investigation outcome** (via the `plugin-dev:plugin-structure` skill, May 23 2026):

Claude Code plugin structure is well-specified. Key requirements:
- Manifest at `.claude-plugin/plugin.json` (NOT bare `plugin.json` at plugin root).
- Skills must be `skills/<name>/SKILL.md` (subdirectory per skill, not flat `.md`).
- Hooks declared in `hooks/hooks.json` (event-handler config), with hook scripts referenced via `${CLAUDE_PLUGIN_ROOT}`.
- Auto-discovered component dirs: `commands/`, `agents/`, `skills/`, `hooks/`. Custom dirs (e.g. `view/`, `schemas/`) supported but not auto-loaded — referenced from commands/hooks/skills via `${CLAUDE_PLUGIN_ROOT}`.
- `${CLAUDE_PLUGIN_ROOT}` is the canonical portable-path env var.
- Naming: kebab-case throughout.

T1 §4.11 has been updated to reflect this. Deltas vs the original T1 §4.11: (a) added `.claude-plugin/plugin.json`, (b) skills became `skills/<name>/SKILL.md`, (c) hooks restructured to `hooks/hooks.json` + `hooks/scripts/`, (d) renamed `bin/` → `scripts/` for Claude-convention consistency, (e) added `agents/` slot.

### Step 2 — Create the directory structure

At repo root, mirroring T1 §4.11:

```
agent-plan-tracker/
  .claude-plugin/
    plugin.json
  README.md
  commands/.keep
  agents/.keep
  skills/.keep
  hooks/.keep
  scripts/.keep
  schemas/.keep
  view/.keep
  cheatsheet/.keep
  philosophies/.keep
```

`.keep` is a 0-byte placeholder convention. Subdirectory contents (e.g. `skills/using-agent-plan-tracker/SKILL.md`, `cheatsheet/worked-examples/`) land via later T3s.

### Step 3 — Write the plugin manifest at `.claude-plugin/plugin.json`

```json
{
  "name": "agent-plan-tracker",
  "version": "0.1.0-pre-m1",
  "description": "Event-sourced planning methodology with git-history extraction and projection.",
  "author": { "name": "Alastair Brayne" },
  "keywords": ["planning", "event-sourcing", "git", "audit", "methodology"]
}
```

Version `0.1.0-pre-m1` (semver pre-release; bumps to `0.1.0` when M1 is complete).

### Step 4 — Write README.md at plugin root

Short. Covers:
- One-line purpose.
- Status: pre-M1, work in progress, not installable on other projects yet.
- Pointers: `../planning/T1-top-level.md` for full design, `../planning/M1-bootstrap.md` for current milestone.
- License placeholder.

### Step 5 — Verify load

- `cat agent-plan-tracker/.claude-plugin/plugin.json | python3 -m json.tool` — JSON parses.
- `ls -la agent-plan-tracker/` confirms full structure.
- Open Claude Code in this repo (or restart current session) → no plugin-loading errors.
- Defer formal CLI validation to `T3-build-loop` (which will provide a `bin/repack-validate.sh`).

## 5. Files to create

- `agent-plan-tracker/.claude-plugin/plugin.json`
- `agent-plan-tracker/README.md`
- `agent-plan-tracker/commands/.keep`
- `agent-plan-tracker/agents/.keep`
- `agent-plan-tracker/skills/.keep`
- `agent-plan-tracker/hooks/.keep`
- `agent-plan-tracker/scripts/.keep`
- `agent-plan-tracker/schemas/.keep`
- `agent-plan-tracker/view/.keep`
- `agent-plan-tracker/cheatsheet/.keep`
- `agent-plan-tracker/philosophies/.keep`

## 6. Decisions to log

- Final plugin name (vs `agent-plan-tracker` working name) — keep as working name; defer to M4.
- Manifest schema adopted from Step 1 investigation — log the exact fields used and any deviations from the discovered spec, with rationale.

## 7. Verification

Once steps complete:
- `ls -la agent-plan-tracker/` shows the full structure with all subdirectories and placeholder files.
- `cat agent-plan-tracker/plugin.json` parses as JSON.
- `find agent-plan-tracker -type f -empty -name .keep | wc -l` returns the expected placeholder count.
- Open Claude Code in this repo → no plugin-loading errors.
- (Eventually, after `T3-build-loop`) `bin/repack-validate.sh` confirms structural integrity.

## 8. HITL questions

- **Q1** (resolved): Claude Code plugin format differs from the original T1 §4.11 in five ways (manifest path, skill nesting, hook config format, dir name convention, agents slot). Reconciliation: T1 §4.11 updated in this same change to match the discovered spec. Plugin layout corrected before any plugin content lands, so no migration cost.
- **Q2** (resolved): Manifest lives at `.claude-plugin/plugin.json` per the Claude Code spec.

## 9. Events this T3 will emit

When work begins (`entity.progressed` on T3-plugin-scaffold). On completion (`entity.completed`). If Step 1 surfaces a manifest format that demands T1 §4.11 revision, emit `entity.extended` on T1 (and a `decision` arc if the change is destructive of prior committed plan content — but at this stage T1 §4.11 has been committed exactly once and a revision would be ordinary plan extension, not destructive).

If `agent-plan-tracker/` location turns out to be wrong (e.g. it should be under `.claude/plugins/` for some reason), the supersession-with-decision pattern applies.
