---
id: T2-packaging
plan_kind: thematic
tier: 2
status: draft
---

# T2-packaging — Plugin scaffold and distribution

**Status**: Draft. Scaffold T3s scheduled into M1; distribution T3s into M4.
**Theme**: The plugin directory structure, build/test loop, and (later) the distribution artefact that delivers CLI + Claude plugin to users.

---

## 1. Why this T2 exists

Everything we build — schemas, scripts, views, philosophies, skills — has to land somewhere that constitutes a working Claude plugin. T2-packaging owns that landing pad.

Per the design rationale established in T1 conversation: packaging is not an end-of-project concern. It's continuous. Every milestone delivers content into the plugin tree, and the scaffold needs to be **repackable from day one** to catch format / manifest / skill-length bugs early rather than at distribution time.

## 2. What lives in this theme

- **Plugin root directory** — the canonical location everything ships from. Layout per T1 §4.11.
- **Plugin manifest** — the file Claude expects (format TBD by Claude plugin spec; investigate in M1).
- **Repack-and-test loop** — local script that validates plugin installability and basic correctness.
- **(M4) Distribution mechanic** — npm package config, CLI install script, hook-into-target-project flow.
- **(M4) Cowork compatibility verification** — confirm the plugin loads correctly in Claude Cowork.

## 3. Approach

### Plugin directory (M1)

```
agent-plan-tracker/                  # plugin root (working name)
  plugin.json                        # or whatever Claude expects
  README.md                          # user-facing
  skills/
    using-agent-plan-tracker.md      # formal spec
  cheatsheet/
    cheatsheet.md
    worked-examples/                 # populated as scenarios surface
  bin/
    <build, projection, audit scripts>
  view/
    index.html
    app.js
    style.css
  schemas/
    events.schema.json
    plan-frontmatter.schema.json
  philosophies/
    <markdown files capturing principles>
  hooks/
    pre-commit                       # placeholder for M2
    pre-push                         # placeholder for M3
  commands/
    <slash command definitions>
```

The `agent-plan-tracker/` directory IS the plugin. Everything M1 delivers goes inside it. The repo root contains:
- `agent-plan-tracker/` (the plugin)
- `planning/` (this project's plans — dogfood)
- `.agent-plan-tracker/` (this project's event log — dogfood)
- `CLAUDE.md` (this project's session-start orientation)
- Anything else stays minimal.

### Repack-and-test loop (M1)
- `bin/repack-validate.sh` (or similar) — checks plugin structure, validates schemas, parses any manifest, confirms no broken refs.
- Run after each substantive change to catch bugs early.
- M1 keeps this local-only; M4 makes it part of CI.

### Distribution (deferred to M4)
- `package.json` and `npm publish` flow.
- CLI install command that sets up target project's `.git/hooks/` plus deposits the plugin into Claude's plugin config dir.
- Cowork install path — likely identical to Claude Code if both use the same plugin config dir; verify.

## 4. T3 candidates

### M1-scheduled
- `T3-plugin-scaffold` — create the directory structure, write any required manifest, verify Claude can load it as a plugin.
- `T3-build-loop` — establish the repack-and-validate cycle.

### M4-scheduled
- `T3-npm-package-config` — package.json, npm publish setup, version conventions.
- `T3-cli-install-command` — user-facing install that writes git hooks into target repo.
- `T3-cowork-compat-verify` — confirm plugin loads in Cowork; document any differences.
- `T3-target-project-init-flow` — slash command + scripts for initialising a fresh project (`.agent-plan-tracker/` setup, hook installation, initial scaffold).

## 5. Dependencies

- M1 scaffold has no prior dependencies; it's foundational.
- M4 distribution depends on M2 (hooks exist), M3 (cleanliness gate exists), and a working pipeline against this project.

## 6. Open questions

1. **Final plugin name.** `agent-plan-tracker` is the working name. Punchier alternatives: `plan-spine`, `git-plan`, `apgt`, `aplan`, `apath`. Decide before M4 publish.
2. **Manifest format.** Look up Claude Code's plugin manifest spec in M1's `T3-plugin-scaffold`.
3. **Hook installation mechanism.** Git hooks land in target `.git/hooks/`. Via CLI command, npm postinstall, or both?
4. **Cowork install flow differences.** Probably none if Cowork uses the same plugin config dir; verify in M4.
5. **Versioning convention.** Semver from `0.1.0` once M1 lands; major version bump policy TBD.

## 7. Out of scope for this T2

- Versioned releases of the plugin itself until there's something worth releasing (post-M3 at earliest).
- Plugin marketplace listings.
- Telemetry / opt-in usage data.
- Auto-update mechanisms.
