---
id: M4-fresh-install
plan_kind: milestone
milestone_index: 4
status: planned
---

# M4-fresh-install — the plugin attaches to any project

**Status**: Planned (authored 2026-06-10 from the post-M3 design conversation: "when this gets installed into a user's Claude, how does that agent know how to install and use all this stuff?").
**Sits at**: Fourth milestone on the sequence axis. Primary theme: T2-packaging (which remains the architectural source of truth for packaging — this milestone schedules its M4 wave). Touches every theme's content surfaces (skills, hooks, scripts resolve portably).

---

## 1. Why this milestone

M1–M3 built the methodology and proved it on this repo — where the toolchain and the tracked project happen to be the same directory tree. M4 breaks that coincidence. The plugin must install into anyone's Claude Code (or Cowork), attach to a fresh **or existing** repo, and have the downstream agent — cold, no project context — follow the discipline unprompted.

The consumer question M4 answers: **how does a downstream agent know how to install and use this?** The design stance: knowledge is delivered just-in-time through three channels, never front-loaded —

1. **Skill descriptions** (when to act): `/apv-capture` and `/apv-merge` trigger off the repo fingerprint at the moments that matter. Ships free with the plugin spec — already built.
2. **Enforcement refusals** (when discipline slips): the guard and gate hooks name the missing skill and the repair path in their refusal messages. Already built.
3. **Bootstrap + orientation** (once per repo, once per session): nothing today initialises a repo, installs the hooks, or tells a session "this project is tracked". **This is M4's build.**

## 2. The shaping decisions

### 2.1 Code/data split is absolute

An attached repo carries **data**: the log, `.apv-config.toml`, and installed git-hook copies. It never carries toolchain. The toolchain home is the plugin install (`${CLAUDE_PLUGIN_ROOT}`); the dogfood repo's vendored copy remains a supported home (it is simply "the toolchain happens to live in the repo"). M3 already made this executable for schemas; M4 finishes it for every script, skill and hook reference. Installed hook copies bake the toolchain path at install time — the resolution chain (env → repo-vendored → plugin root → PATH) decides once, at init.

### 2.2 Init is a user-triggered, idempotent command

No npm-postinstall magic, no implicit creation (the capture skill's refusal to create `events.jsonl` stands). One command initialises a repo: seeds the data dir, writes the config, installs the three git hooks via the existing installers (whose fresh/identical/differs contract is the idempotency story), offers a CLAUDE.md orientation block, prints next steps. Re-running reports state and fixes gaps; it never clobbers. (Resolves T2-packaging §7 Q2 as leaned: slash command, for control + idempotency.)

### 2.3 The rename executes here (operator ruling 2026-06-10)

The project becomes **agent-plan-visualiser (APV)** — resolves T2-packaging §7 Q1; `apt` was already rejected for the Debian collision, `apv` clears it. Execution lands in `T3-toolchain-portability` because that T3 touches every live reference anyway — renaming at the same moment costs near-zero extra; renaming now would touch everything twice. Hard constraints: **the event log is never rewritten** (append-only law — historical summaries, command strings and seals keep the old name as true record), **closed plans are archaeology** (their prose stays), and git history is immutable. The dogfood repo's data dir stays `.agent-plan-tracker/` pinned via `[storage] data_dir` — the config middle layer built in M3 makes grandfathering free. Only live surfaces rename: plugin dir + manifest, skills, env vars, config filename, live-plan prose, docs.

### 2.4 Existing projects attach from now

Attaching to an existing repo = init-from-now: empty log, hooks live, the next commit is the first captured one. Mining the project's git history into events is **M5-backfill**, deliberately out of M4 — adoption must not gate on archaeology.

## 3. What M4 explicitly does NOT include

- **Backfill** — M5.
- **Telemetry, auto-update, marketplace listing polish** — T2-packaging §8 stands.
- ~~The full autonomous `claude -p` extractor as a later wave~~ — **pulled into the wave** (operator ruling at acceptance, 2026-06-10: sooner rather than later; `claude -p` runs within subscription allowances, dissolving the cost concern behind the deferral). See §5 #5 and [[T3-autonomous-extractor]].

## 4. How a cold agent experiences the result (definition of the job)

Install plugin → open any repo → session orientation says nothing (untracked) or one line (tracked). Run the init command on a project → data dir, config, three hooks, orientation block. Work normally → the capture skill triggers before commits; the guard catches misses; the gate guards main; `/apv-merge` lands branches. At no point does the user read a manual; at no point does the agent need this repo's CLAUDE.md.

## 5. How M4 delivers — T3 tasks

#1–#4 under T2-packaging (consolidating that plan's §5 M4-scheduled candidates: `T3-npm-package-config` + `T3-cowork-compat-verify` → #4; `T3-cli-install-command` + `T3-target-project-init-flow` → #2); #5 under T2-extraction.

1. **`T3-toolchain-portability`** [foundation] — every reference resolves via the toolchain home (`${CLAUDE_PLUGIN_ROOT}` / vendored / env); installers bake paths into hook copies; **the APV rename executes**; manifest + version bump.
2. **`T3-project-init-flow`** [depends #1] — the init command: seed (`.apv/`), config, hooks, CLAUDE.md offer, idempotent re-run, existing-repo handling.
3. **`T3-session-orientation`** [depends #1] — `hooks/hooks.json` SessionStart fingerprint detection injecting one orientation line; the formal `using-agent-plan-visualiser` skill (spec floor, cheatsheet surface — T2-packaging §3.4's instruction shape).
4. **`T3-distribution`** [depends #1–3] — the bundle for the exfu.ai test channel (§7 Q2 ruling); Cowork compatibility verification; the CI gate-adapter template (M3's deferral lands); README quickstart.
5. **`T3-autonomous-extractor`** [depends #1; parallel to #2–#4] — the `claude -p` per-commit extractor for non-Claude-Code committers (T2-extraction §3.4/§3.6 design; pulled in-wave by the §7 Q1 ruling).

## 6. Definition of done

- The plugin installs into a clean Claude Code from the distribution artefact; loads in Cowork.
- A **fresh repo** and an **existing repo with history** both attach via the init command: data dir seeded, config written, three hooks live, first post-init commit transits capture-guard, gate green.
- A sandbox "cold agent" pass: in an attached non-dogfood repo, the capture → guard → gate → merge loop runs end-to-end using only plugin-delivered knowledge (no repo CLAUDE.md).
- Every live surface resolves via the toolchain home; the dogfood repo stays green with its vendored copy (all existing suites pass unmodified in behaviour).
- The rename is complete on live surfaces; log, closed plans and git history untouched; dogfood data dir grandfathered via config.

## 7. Open questions

1. **Extractor placement** — later-wave M4 (current lean) or its own milestone? Operator call at acceptance.
   **RESOLVED at acceptance (operator, 2026-06-10): in-wave, sooner rather than later.** `claude -p` runs within subscription allowances — the cost concern behind the original deferral (T2-extraction §3.4) is dissolved. `T3-autonomous-extractor` authored same day, depends only on #1.
2. **Distribution mechanism** — npm package vs Claude Code plugin marketplace vs both (T2-packaging §4 sketched npm-bundles-both before marketplaces matured). **Ruled for the test phase (operator, 2026-06-10): bundle the plugin and deploy to exfu.ai as a private test channel for test-client feedback; public distribution deferred, not decided.** T3-distribution carries the bundle; the public question reopens on test feedback.
3. **Fresh-install data dir name** — `.agent-plan-visualiser/` (consistent) vs `.apv/` (short). Decide in T3-project-init-flow; dogfood stays grandfathered either way.
   **RESOLVED at acceptance (operator, 2026-06-10): `.apv/`.**
4. **CLAUDE.md block** — does init write it by default or offer it? Lean: offer, never write unasked.
   **RESOLVED at acceptance (operator, 2026-06-10): offer to write; init is the only trigger for the offer (no other code path writes or re-offers — re-run init to be offered again); writing requires explicit user acceptance.**
5. **Cowork deltas** — unknown until T3-distribution verifies (T2-packaging §7 Q3).

## 8. Dependencies

- M2 (capture + guard) and M3 (gate + adapters + merge doctrine) — complete; M4 packages them.
- T2-packaging §3 (spec discoveries: manifest location, `${CLAUDE_PLUGIN_ROOT}`, auto-discovery dirs) — the architectural ground.

## 9. After M4

**M5-backfill** mines existing history into the log (and inherits the extractor's machinery if Q1 keeps it in M4). The plugin is then whole: adopt forward from today, recover backward when wanted.
