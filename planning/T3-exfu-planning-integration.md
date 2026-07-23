---
id: T3-exfu-planning-integration
plan_kind: thematic
tier: 3
t2_parent: T2-extraction
milestone: M6-exfu-integration
status: active
---

# T3-exfu-planning-integration — receive the ExFu capture-provider skill

**Status**: Accepted 2026-07-24 (operator, post-audit). Raised on the operator's direction: the ExFu delegation stack's capture integration belongs to APV, not to the ExFu marketplace. Parent theme: T2-extraction (owns capture/merge doctrine skills, per the T3-apt-capture-skill / T3-apt-merge-skill precedent). Executable cold: this brief carries every command needed in THIS repo.

## Why (condensed)

The exfu_planner project built a three-component delegation stack (core / grounding / capture) with one-way dependencies; its capture component — how delegated work enters an APV record: draft-gate checks pre-delegation, `actor: "codex"` attribution, verdicts as summary text, orchestrator-sealed commits — was always bound for this plugin. Ownership here keeps the ExFu marketplace APV-free and lets APV evolve its own integration surface.

## Roles & sovereignty

A cheap sub-agent may place/reframe the skill file. The **orchestrator alone** appends events to `.agent-plan-tracker/events.jsonl`, runs acceptance ceremonies, and runs every `git commit`/`git merge`. Data dir is `.agent-plan-tracker/` (this repo's `.apv-config.toml`), never `.apv/`. Pre-commit capture-guard, pre-push, and reference-transaction gates are live.

## What & sequence

1. **Skill placement** (sub-agent): create `agent-plan-visualiser/skills/exfu-planning-apv-integration/SKILL.md`. Source content = the former `exfu-capture-apv` skill, secured from exfu_planner. Retrieve it explicitly if needed:
   `git -C /Users/al/Studio/projects/exfu_planner show HEAD:skills/exfu-capture-apv/SKILL.md` (the last commit before its removal), or the orchestrator-staged reframed copy. Reframe as APV-owned: `name: exfu-planning-apv-integration` (must equal dir); description in house style ending "in any project tracked by agent-plan-visualiser (has a .agent-plan-tracker/events.jsonl or APV_DATA_DIR equivalent)"; sibling reference `${CLAUDE_PLUGIN_ROOT}/skills/apv-capture/SKILL.md`; registers `capture = "exfu-planning-apv-integration"`; reference-skill pattern (no `commands/` wrapper).
2. **Accept plans** (operator say-so): this plan and `M6-exfu-integration` are orchestrator-authored drafts; on operator confirmation, `entity.accepted` each (actor `al`).
3. **Feature capture + commit** (orchestrator, one sealed block): `entity.created` + `relationship.spawns` for this T3 and M6; the two `entity.accepted`; `entity.progressed` on this T3 (skill placed) — **not `entity.completed`** (see step 7). Validate `bash agent-plan-visualiser/scripts/repack-validate.sh`; `date +%s > .agent-plan-tracker/.last-capture`; `git add agent-plan-visualiser/skills/exfu-planning-apv-integration/ planning/T3-exfu-planning-integration.md planning/M6-exfu-integration.md .agent-plan-tracker/events.jsonl` + derived; commit (seal-matching first line).
4. **Release 0.6.3** (rides T3-distribution, house convention — separate commit touching ONLY `agent-plan-visualiser/.claude-plugin/plugin.json` + `.agent-plan-tracker/events.jsonl`): bump `version` "0.6.2"→"0.6.3"; `bash agent-plan-visualiser/tests/dist/run-dist-sandbox.sh` (ALL PASS — the only pre-release verification; no CI); capture `entity.progressed` T3-distribution + `verification.tested` (command = sandbox script, result pass) + seal `release(T3-distribution): cut 0.6.3 — exfu-planning-apv-integration skill`; commit those two files.
5. **Build + refresh cache**: `bash agent-plan-visualiser/scripts/build-bundle.sh`; `claude plugin marketplace update apv`; `claude plugin update agent-plan-visualiser@apv`. Confirm `~/.claude/plugins/cache/apv/agent-plan-visualiser/0.6.3/skills/exfu-planning-apv-integration/SKILL.md` exists.
6. **Chore commit** (house pattern): `bash agent-plan-visualiser/scripts/repack-validate.sh`; commit refreshed derived artefacts — "chore: refresh derived projections over the captured log".
7. **Post-release completion** (orchestrator): with cache 0.6.3 + skill present and `bash agent-plan-visualiser/scripts/gate-check.sh` green, capture `verification.tested` (that evidence), `entity.completed` on this T3, and — on operator confirmation (milestone closure is a human ceremony) — `entity.completed` on M6; seal + commit.
8. **Land on main** per `/apv-merge` §1 (ff/rebase/merge; events.jsonl conflicts never auto-resolved).

## Out of scope

Changes to apv-capture/apv-merge/using-agent-plan-visualiser; any ontology/schema change (`schema_version` stays "0.3.0"; no new event types — verdicts remain summary text); delegate-side capture; git tags (not used here); ExFu-side skill content.

## Verification

1. `agent-plan-visualiser/skills/exfu-planning-apv-integration/SKILL.md` exists; frontmatter `name` == dir name.
2. `bash agent-plan-visualiser/tests/dist/run-dist-sandbox.sh` — ALL PASS before the release commit.
3. `~/.claude/plugins/cache/apv/agent-plan-visualiser/0.6.3/skills/exfu-planning-apv-integration/SKILL.md` exists after build + refresh.
4. `bash agent-plan-visualiser/scripts/gate-check.sh` green (pre-existing warns tolerated).
