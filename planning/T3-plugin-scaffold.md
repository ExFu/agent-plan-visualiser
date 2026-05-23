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

### Step 1 — Discover Claude Code plugin manifest format

Investigate the canonical plugin spec:
- Check Anthropic docs (`docs.anthropic.com/claude/docs/claude-code`).
- Look for example plugins in the wild — official Anthropic plugins, or `oh-my-claudecode` style projects, which have visible structure.
- Note required vs optional fields. Document findings as a brief note inside the plugin's `README.md` or in a Step-1 commit message.

If the spec genuinely doesn't exist publicly, derive from observable patterns: examine the `.claude/` directory of an installed plugin, or fall back to a minimal sensible JSON manifest and let Claude Code surface errors.

**HITL gate**: if the investigation surfaces a significantly different structure than T1 §4.11 anticipates, pause and reconcile before proceeding.

### Step 2 — Create the directory structure

At repo root:

```
agent-plan-tracker/
  plugin.json                       # or whatever Claude expects (resolved in Step 1)
  README.md
  skills/
    .keep
  cheatsheet/
    .keep
    worked-examples/
      .keep
  bin/
    .keep
  view/
    .keep
  schemas/
    .keep
  philosophies/
    .keep
  hooks/
    .keep
  commands/
    .keep
```

`.keep` is a 0-byte placeholder convention. Alternative: README.md in each subdirectory with a one-liner about what content will land there. Lean `.keep` for now; promote to README.md per-subdir as content lands.

### Step 3 — Write the plugin manifest

Minimal manifest (exact field names TBD by Step 1). Likely fields:

- `name`: `agent-plan-tracker`
- `version`: `0.1.0-pre-m1` (semver pre-release; bumps to `0.1.0` when M1 is complete)
- `description`: "Event-sourced planning methodology with git-history extraction and projection."
- (whatever else Claude expects)

### Step 4 — Write README.md at plugin root

Short. Covers:
- One-line purpose (1–2 sentences).
- Status: pre-M1, work in progress, not installable on other projects yet.
- Pointer: see `../planning/T1-top-level.md` for the full design, `../planning/M1-bootstrap.md` for the current milestone.
- License / authorship placeholders if needed.

### Step 5 — Verify load

- Run any available `claude` CLI plugin-validation command in this directory.
- If no validation tooling exists, smoke test: open Claude Code in this repo and confirm no plugin-loading errors surface.
- If validation fails, fix and re-test; if it can't be made to validate, raise as HITL Q1 below and pause.

## 5. Files to create

- `agent-plan-tracker/plugin.json` (or equivalent manifest)
- `agent-plan-tracker/README.md`
- `agent-plan-tracker/skills/.keep`
- `agent-plan-tracker/cheatsheet/.keep`
- `agent-plan-tracker/cheatsheet/worked-examples/.keep`
- `agent-plan-tracker/bin/.keep`
- `agent-plan-tracker/view/.keep`
- `agent-plan-tracker/schemas/.keep`
- `agent-plan-tracker/philosophies/.keep`
- `agent-plan-tracker/hooks/.keep`
- `agent-plan-tracker/commands/.keep`

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

- **Q1**: Does the Claude Code plugin format match T1 §4.11's anticipated layout? If not, what reconciliation is needed before proceeding with the M1 plan as written?
- **Q2**: Should the plugin manifest live at `plugin.json` (most common) or somewhere else (e.g. `claude-plugin.json`, `.claude/plugin.json`)? Resolved by Step 1 investigation; no a-priori answer.

## 9. Events this T3 will emit

When work begins (`entity.progressed` on T3-plugin-scaffold). On completion (`entity.completed`). If Step 1 surfaces a manifest format that demands T1 §4.11 revision, emit `entity.extended` on T1 (and a `decision` arc if the change is destructive of prior committed plan content — but at this stage T1 §4.11 has been committed exactly once and a revision would be ordinary plan extension, not destructive).

If `agent-plan-tracker/` location turns out to be wrong (e.g. it should be under `.claude/plugins/` for some reason), the supersession-with-decision pattern applies.
