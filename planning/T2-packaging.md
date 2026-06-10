---
id: T2-packaging
plan_kind: thematic
tier: 2
status: active
---

# T2-packaging — Plugin scaffold and distribution

**Status**: Active. M1 T3 (`T3-plugin-scaffold`) complete; M4 T3s queued.
**Theme**: The plugin directory structure, manifest, build/test loop, and (later) the distribution artefact that delivers the plugin to users. **This T2 is the architectural source of truth for packaging**; T1 only summarises.

---

## 1. Why this T2 exists

Everything else we build — schemas, scripts, views, philosophies, skills, hooks — has to land somewhere that constitutes a working Claude Code plugin. T2-packaging owns that landing pad.

Packaging is not an end-of-project concern. It's continuous. Every milestone delivers content into the plugin tree, and the scaffold needs to be **repackable from day one** to catch format / manifest / skill-length bugs early rather than at distribution time.

## 2. What lives in this theme

- **Plugin root directory** — `agent-plan-visualiser/` at the repo root. The canonical location everything ships from.
- **Plugin manifest** — `.claude-plugin/plugin.json`. Required by Claude Code's plugin spec.
- **Subdirectory layout** — both Claude-spec-conforming dirs (`commands/`, `agents/`, `skills/`, `hooks/`) and project-custom dirs (`scripts/`, `schemas/`, `view/`, `cheatsheet/`, `philosophies/`).
- **Repack-and-test loop** — local script that validates plugin installability.
- **(M4) Distribution mechanic** — npm package config, CLI install script, hook-into-target-project flow.
- **(M4) Cowork compatibility verification** — confirm the plugin loads correctly in Claude Cowork.

## 3. Architecture

### 3.1 Discovered Claude Code plugin spec

Investigated via `plugin-dev:plugin-structure` skill during M1's `T3-plugin-scaffold`. Key requirements:

- **Manifest location:** `.claude-plugin/plugin.json` (NOT bare `plugin.json` at plugin root).
- **Skills:** subdirectory per skill — `skills/<name>/SKILL.md` (NOT flat `.md` files).
- **Hooks:** declared in `hooks/hooks.json` (event-handler config), with hook scripts referenced via `${CLAUDE_PLUGIN_ROOT}`.
- **Auto-discovered component dirs:** `commands/`, `agents/`, `skills/`, `hooks/`.
- **Custom dirs:** supported but not auto-loaded — referenced from commands/hooks/skills via `${CLAUDE_PLUGIN_ROOT}`.
- **Portable paths:** `${CLAUDE_PLUGIN_ROOT}` is the canonical env var for intra-plugin references. Never use absolute paths or `~/`.
- **Naming:** kebab-case throughout.

### 3.2 Plugin directory layout

```
agent-plan-visualiser/                          # plugin root (at repo root)
  .claude-plugin/
    plugin.json                              # manifest — required location, kebab-case name
  README.md
  commands/
    <slash command .md files>                # auto-discovered (e.g. /apv-init, /apv-audit)
  agents/
    <subagent .md files>                     # auto-discovered (e.g. M2 extraction agent)
  skills/
    using-agent-plan-visualiser/
      SKILL.md                               # formal spec, full ontology
  hooks/
    hooks.json                               # event-handler configuration
    scripts/
      pre-commit                             # installed into target's .git/hooks/
      pre-push                               # installed into target's .git/hooks/
  scripts/
    <utility scripts the plugin invokes via Claude's Bash tool>
    local/                                   # per-user / per-session ad-hoc scripts
  schemas/
    <version>/
      events.schema.json
      plan-frontmatter.schema.json
  view/
    index.html                               # HTML view template
    app.js                                   # JS that loads projection.json
    style.css
  cheatsheet/
    cheatsheet.md                            # common operations, one-liners
    worked-examples/
      find-stalled-plans.md
      audit-verification-gaps.md
      trace-decision-history.md
      pre-merge-cleanliness-check.md
  philosophies/
    3-tier-rationale.md
    golden-circle-grounding.md
    top-down-from-job.md
    disposable-etl.md
    swap-out-surfaces.md
    empirical-prompt-architecture.md
    tracker-as-agent-memory.md
```

**Conformance vs custom dirs.** `.claude-plugin/`, `commands/`, `agents/`, `skills/`, `hooks/` follow Claude Code's plugin spec and use its auto-discovery conventions. The remaining directories (`scripts/`, `schemas/`, `view/`, `cheatsheet/`, `philosophies/`) are this project's own content surfaces, referenced from the plugin's commands/hooks/skills via `${CLAUDE_PLUGIN_ROOT}`.

### 3.3 Manifest contents (`.claude-plugin/plugin.json`)

Current (v0.4.0, post-rename 2026-06-10):

```json
{
  "name": "agent-plan-visualiser",
  "version": "0.4.0",
  "description": "Event-sourced planning methodology with git-history extraction and projection. Walks a project's git history, extracts structured events against a defined ontology, and provides projections (audits, diagrams, status reports) over the resulting event log.",
  "author": { "name": "Alastair Brayne" },
  "keywords": ["planning", "event-sourcing", "git", "audit", "methodology", "claude-code"]
}
```

Semver tracks the milestone era (0.&lt;milestone&gt;.x); the first test-channel cut is T3-distribution's call.

### 3.4 Plugin instruction shape (the skill tells downstream agents)

- Prefer existing `scripts/<script>` over generating SQL from scratch — major token saving.
- If you find yourself generating a useful query repeatedly, save it to `scripts/local/<descriptive-name>.sql` for future agents and humans. Lookup order: `scripts/` → `scripts/local/` → generate-from-scratch-and-save.
- For ontology/schema questions, go to `skills/using-agent-plan-visualiser/SKILL.md` (the formal spec). For common operations, `cheatsheet/cheatsheet.md`. For worked scenarios, `cheatsheet/worked-examples/`. The formal spec is the floor, not the everyday surface.
- The `philosophies/` content grounds judgement calls when instructions don't anticipate something.

### 3.5 Repack-and-test loop

- `scripts/repack-validate.sh` — orchestrates the full pipeline validation+build (events → frontmatter → cache → projection → summary → SQL audits). Runs after each substantive change to catch bugs early.
- M1 keeps this local-only; M4 makes it part of CI.

Plugin-structure smoke validations (M2-scoped — vacuously true until skills/hooks/commands are populated):
- `plugin.json` parses as JSON.
- Every skill has a `SKILL.md` (no orphan `skills/<name>/` dirs).
- Every hook script referenced in `hooks.json` exists.
- All schema files parse and reference each other consistently.

### 3.6 Repository layout (where the plugin sits relative to dogfood)

The `agent-plan-visualiser/` directory IS the plugin. The repo also contains:

- `agent-plan-visualiser/` — the plugin.
- `planning/` — this project's own plans (dogfood).
- `.agent-plan-tracker/` — this project's own event log (dogfood).
- `CLAUDE.md` — this project's session-start orientation.
- `.gitignore`, `README.md` (eventual) at repo root.

The dual presence (`agent-plan-visualiser/` AS plugin + `.agent-plan-tracker/` AS dogfood event log) is by design: the plugin lives at one path; the data it works against lives at another path with a similar but distinct name. Future agents reading the repo can distinguish *the tool* from *the tool used on itself*.

## 4. Artefact strategy

The plugin is aimed at **developers**, with the caveat that it also needs to be usable in **Claude Cowork** (Cowork is filesystem-accessing, not browser-only — it's Claude Code with reduced jargon for less-technical users). Cowork is particularly useful when a user wants to work at T1/T2 (project-management) altitude rather than T3 (execution) altitude.

The distribution strategy (T2 lock-in deferred to M4):

- A **developer-installed package** — likely npm — that bundles:
  - CLI scripts (or Claude-invokable scripts) installed to the user's PATH or referenced via `${CLAUDE_PLUGIN_ROOT}`.
  - Claude plugin files (skills, commands, hooks, view template, philosophies, schemas) installed to the user's Claude config directory.
- One install command sets up both.
- The Claude plugin works in both Claude Code and Claude Cowork automatically.
- The plugin's project-init slash command writes git hooks into the target project's `.git/hooks/`.

Naming TBD — `apt` was rejected due to namespace collision with Debian/Ubuntu's package manager. Alternatives in play: `agent-plan-visualiser` (current working name, verbose), `plan-spine`, `git-plan`, `apgt`, `aplan`, `apath`. Decide before M4 publish.

## 5. T3 candidates

### M1-scheduled
- ~~`T3-plugin-scaffold`~~ — **complete** (`5068405`). Created directory structure, manifest, README, placeholder .keep files.
- `T3-build-loop` — establish the repack-and-validate cycle (`scripts/repack-validate.sh`).

### M4-scheduled
- `T3-npm-package-config` — package.json, npm publish setup, version conventions.
- `T3-cli-install-command` — user-facing install that writes git hooks into target repo.
- `T3-cowork-compat-verify` — confirm plugin loads in Cowork; document any differences.
- `T3-target-project-init-flow` — slash command + scripts for initialising a fresh project (`.agent-plan-tracker/` setup, hook installation, initial scaffold).

> **Superseded 2026-06-10 by [[M4-fresh-install]] §5.** The candidates consolidate into four authored T3s: `T3-toolchain-portability` (paths via the toolchain home + the APV rename), `T3-project-init-flow` (absorbs cli-install-command + target-project-init-flow), `T3-session-orientation` (the third knowledge channel — hooks.json + the formal orientation skill of §3.4), `T3-distribution` (absorbs npm-package-config + cowork-compat-verify; hosts M3's deferred CI adapter template).

## 6. Dependencies

- M1 scaffold has no prior dependencies; it's foundational.
- T3-build-loop depends on schema work landing (validates schemas).
- M4 distribution depends on M2 (hooks exist), M3 (cleanliness gate exists), and a working pipeline against this project.

## 7. Open questions

1. **Final plugin name.** Working name `agent-plan-tracker` works; decide before M4 publish whether to keep or shorten.
   **RESOLVED 2026-06-10 (operator ruling): `agent-plan-visualiser` (APV).** The `apt` collision (§4) is cleared by `apv`. Execution deferred to [[T3-toolchain-portability]] — every live reference is touched there anyway, so the rename rides at near-zero cost; renaming earlier would touch everything twice. Hard constraints: the event log is never rewritten (append-only — historical names stay as true record), closed plans are archaeology, git history is immutable; the dogfood data dir stays `.agent-plan-tracker/` pinned via `[storage] data_dir`.
2. **Hook installation mechanism.** Git hooks land in target `.git/hooks/`. Via CLI command (run after install), npm postinstall (automated), or slash command in Claude Code (user-triggered)? Probably the slash command for control + idempotency.
3. **Cowork install flow differences.** Probably none if Cowork uses the same plugin config dir as Claude Code; verify in M4.
4. **Versioning convention.** Semver from `0.1.0` once M1 lands. Major version bump policy: when ontology breaks backward compatibility? Defer until first such break is contemplated.
5. **Schema directory versioning.** Currently `schemas/<version>/` is proposed; sole alternative is flat `schemas/events.schema.json` with version embedded. Versioned-dirs are clearer for migration but require schema-version-aware loaders. Decide in `T3-events-schema-json`.

## 8. Out of scope for this T2

- Versioned releases of the plugin itself until there's something worth releasing (post-M3 at earliest).
- Plugin marketplace listings.
- Telemetry / opt-in usage data.
- Auto-update mechanisms.
- Multi-tenant install per-user-per-project hosting — single-tenant per repo.
