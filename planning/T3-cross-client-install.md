---
id: T3-cross-client-install
plan_kind: thematic
tier: 3
t2_parent: T2-packaging
milestone: M4-fresh-install
status: draft
---

# T3-cross-client-install — one global install; a repo that declares its own dependency

**Status**: Draft.
**Sits at**: T2-packaging theme, M4-fresh-install milestone. Evolves the install channel ruled in [[T3-distribution]] (public git marketplace), extends the CLAUDE.md offer in [[T3-project-init-flow]] into a managed dependency assertion, and extends [[T3-session-orientation]]'s SessionStart hook with a version-currency check. Executable cold: carries every file path and command needed in this repo.

## 1. Why (condensed)

Plugin *enablement* is per-client machine state; it does not travel with the repo. Open the same repo in Claude Code vs Cowork/Desktop and the APV skills load in one and vanish in the other — M4 §1's "loads in Cowork" assumed a channel that guaranteed cross-client availability; the private-bundle channel didn't. The fix reframes the repo as the source of truth for *what it needs*, not *what is installed*: the repo declares its APV dependency portably, Claude Code auto-satisfies it, and every client verifies it and complains when unmet. Grounds in T1 §3.3 (the tracker substitutes for agent memory — the declaration is memory a cold agent in any client can read) and M4 §1 channel 3 (bootstrap + orientation, once per repo / once per session).

## 2. How (by reference)

- **Distribution is the public git marketplace** — [[T3-distribution]] §8 ruling (2026-07-23): marketplace `exfu` @ https://github.com/ExFu/claude-marketplace; plugin repo https://github.com/ExFu/agent-plan-visualiser; installed `agent-plan-visualiser@exfu`. The git channel is chosen because it is the only surface both Claude Code and Cowork honour.
- **Code/data split is absolute** (M4 §2.1): the declaration and the enablement pin are *data* committed to the attached repo; the toolchain stays in the plugin install (`${CLAUDE_PLUGIN_ROOT}`).
- **Grounding is asserted, never gated** (exfu-planning-methodology): the CLAUDE.md block *instructs* an agent to stop and complain on a missing plugin; nothing in core tooling hard-refuses.
- **Skills are the cross-client primitive; commands are Claude-Code-only aliases** (§3, command honesty).

## 3. What — the four layers

**Layer 0 — register the marketplace (per client, once per machine; documented, not automated).** `README.md` and the not-found hint in `scripts/apv-init.sh` point at `/plugin marketplace add https://github.com/ExFu/claude-marketplace` → `/plugin install agent-plan-visualiser@exfu` (landed pre-plan, operator-directed). No code owns this — it is the irreducible bootstrap, shared across all exfu plugins.

**Layer 1 — declare (portable, all clients).**
1. `.apv-config.toml` gains a `[requires]` table: `apv_min_version` (seeded from the plugin manifest version at attach time) and `skills = ["apv-capture", "apv-merge", "using-agent-plan-visualiser"]`. `scripts/apv-init.sh` writes it at attach.
2. `scripts/apv-init.sh`'s CLAUDE.md writer emits a **managed REQUIRES block**, superseding the thinner orientation paragraph, keyed on the marker guard that writer already uses (grep `apv:orientation` in `scripts/apv-init.sh` for the exact tokens; reuse them). Idempotent: create file → append block → replace-between-markers on re-init. Block content:
   - Names the plugin + `apv_min_version`.
   - Instructs the agent, before any work, to verify the **skill** `agent-plan-visualiser:apv-capture` is loaded; if absent, STOP and tell the operator to register the marketplace + install (Layer 0) — never fabricate captures by hand.
   - Signposts that git hooks live in `.git/` (uncommitted), so a fresh clone/worktree runs `/apv-init` once to install capture-guard + gate adapters.
   - Names the **skill** as the primitive; describes `/apv-capture` as its Claude-Code-only slash alias.

**Layer 2 — satisfy automatically (Claude Code).** A committed `.claude/settings.json` carrying an `enabledPlugins` entry for `agent-plan-visualiser@exfu` auto-enables APV when a Claude Code session opens the attached repo. Degrades gracefully: if the marketplace is unregistered on the machine, the pin cannot resolve and Layer 3 fires.

> **As-built (2026-07-23): this layer already exists** — `scripts/apv-init.sh` §5b (field report 2026-07-21) already writes `enabledPlugins["agent-plan-visualiser@<marketplace>"] = true` (a JSON object keyed by plugin id, not an array), derives that id from the plugin-cache path (→ `@exfu` when installed from the exfu marketplace), merges it into any existing `.claude/settings.json` without clobbering sibling keys (Q2's ruling is already the behaviour), and reports `ACTION` when the file is untracked. This T3 therefore only *verifies* Layer 2 targets `@exfu` and preserves keys — it builds nothing new here.

**Layer 3 — verify + whinge (portable).** Two prongs for two failure modes:
- *loaded-but-stale* (drift): extend `hooks/session-orient.sh` to read `[requires].apv_min_version` and compare it against the running plugin's `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json` `version`; emit one loud line when the loaded version is behind. The hook firing at all proves the plugin is loaded, so this prong owns only the stale case.
- *not-loaded-at-all*: unreachable by a plugin hook (it cannot fire), owned entirely by the Layer-1 CLAUDE.md block the agent always reads.

**Command/skill honesty.** Retitle the bodies of `commands/apv-capture.md` and `commands/apv-merge.md` to state outright: "Slash alias for skill `agent-plan-visualiser:apv-capture` (resp. `:apv-merge`) — invoke that skill and follow it; do not improvise." Substance stays in the skill; the command is the deterministic operator trigger, explicitly Claude-Code-only. Every self-check (Layers 1 & 3) asserts on the skill, never the command — the command is exactly the surface that may legitimately be absent in a non-Code client.

## 4. Scope

### In scope
- `[requires]` in `.apv-config.toml` + init writing it.
- The managed REQUIRES block (evolving the orientation block) + its idempotent writer.
- The committed `.claude/settings.json` enablement pin + init writing/merging it.
- The session-orient version-currency check.
- The command-body reframe for the two alias commands.

### Out of scope
- The exfu marketplace itself listing APV (external — coordinated with the marketplace repo; see §6).
- Cowork/Desktop enablement *automation* — those clients get Layers 1 + 3 (declare + verify), not Layer 2; no per-repo auto-enable is claimed for them.
- A shared cross-plugin assertion convention — deliberately APV-local (few affected plugins; operator ruling).
- Any change to capture/merge/gate *procedure*, or to the ontology/schema (`schema_version` unchanged; no new event types).
- The dogfood repo's own enablement stance (see §7 Q1).

## 5. Verification
1. Sandbox fresh repo: `/apv-init` → `.apv-config.toml` has `[requires]`; CLAUDE.md carries the REQUIRES block between the markers; `.claude/settings.json` carries the `agent-plan-visualiser@exfu` pin. Re-run is idempotent — block replaced not duplicated, JSON sibling keys preserved.
2. session-orient: with `[requires].apv_min_version` set above the manifest version, the hook prints the loud stale line; at or below it, only the normal orientation line (or silence when untracked).
3. Command reframe: both command files name the skill as canonical; `bash agent-plan-visualiser/tests/dist/run-dist-sandbox.sh` still ALL PASS.
4. **Operator leg (Claude Code)**: open an attached sandbox repo in a fresh Code session — APV auto-enables from the committed pin (skills surface without a manual `/plugin install`).
5. **Operator leg (Cowork)**: open the same repo in Cowork — the REQUIRES block drives the agent to verify and announce the skill; when unmet, it whinges with the register + install steps.

## 6. Dependencies
- [[T3-distribution]] — the marketplace channel and its §8 public-distribution ruling.
- [[T3-project-init-flow]] — the init command whose CLAUDE.md offer + writer this extends.
- [[T3-session-orientation]] — the SessionStart hook this extends.
- **External**: APV published to `ExFu/agent-plan-visualiser` and listed in `ExFu/claude-marketplace` (built by a separate agent). Until that listing resolves, Layer-0 install cannot complete end-to-end — raise as a blocker if it lags the code work.

## 7. Open questions (HITL)
- **Q1 — dogfood repo enablement.** This repo keeps APV project-scoped and deliberately disabled (the deferred-verification note in `summary.md`). Does `/apv-init` write the `.claude/settings.json` pin *here* too (contradicting that stance), or is the pin consumer-only, with the dogfood repo's scope operator-controlled? Lean: consumer-only — the dogfood repo's enablement stays the operator's call.
- **Q2 — settings.json merge policy.** When a repo already has `.claude/settings.json` with other keys, init merges the `enabledPlugins` entry in. Confirm deep-merge (preserve `hooks`, `permissions`, etc.) vs refuse-and-report on an unexpected shape. Lean: merge the single key, report what changed, never clobber siblings.

## 8. Rulings (2026-07-23, operator acceptance ceremony)

- **Q1 (dogfood enablement)** — resolved: `/apv-init` writes the `.claude/settings.json` enablement pin **unconditionally** whenever it runs; there is no consumer-vs-dogfood branch. If this repo runs init and its deliberately project-scoped/disabled stance needs to override the pin, that override is expressed as dev-notes in this repo's own CLAUDE.md, not as a special case in `apv-init.sh`. §4's "dogfood repo's own enablement stance" out-of-scope item is **withdrawn** — init writes here too; the repo self-corrects at the CLAUDE.md layer.
- **Q2 (settings.json merge)** — resolved: **preserve every existing key.** Deep-merge only the `enabledPlugins` entry into any existing `.claude/settings.json` (append the plugin id if the array exists, create the array if not), never rewriting or dropping sibling keys (`hooks`, `permissions`, etc.). Report what changed. Never clobber another dev's or agent's settings because we don't recognise them.
