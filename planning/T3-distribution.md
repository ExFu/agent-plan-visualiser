---
id: T3-distribution
plan_kind: thematic
tier: 3
t2_parent: T2-packaging
milestone: M4-fresh-install
status: draft
---

# T3-distribution — the artefact that delivers the plugin

**Status**: Draft.
**Sits at**: T2-packaging theme, M4-fresh-install milestone. Final install-wave T3 — depends on the other three. Consolidates T2-packaging §5's `T3-npm-package-config` + `T3-cowork-compat-verify` candidates; hosts the CI adapter template M3 deferred.

---

## 1. Why

Everything before this T3 makes the plugin *work* anywhere; this T3 makes it *arrive* anywhere. For the test phase the mechanism is ruled (§2.1); the public-distribution stance (T2-packaging §4's npm sketch vs the matured plugin marketplaces) stays open deliberately until test-client feedback warrants deciding it.

## 2. What

1. **Mechanism — ruled for the test phase** (operator, 2026-06-10, resolves M4 §7 Q2 for now): **bundle the plugin**; deploy the bundle to exfu.ai as a private test channel (placement and upload flow: operator walkthrough pending) so test clients can install it and feed back. Public distribution is **deferred, not decided** — revisit on feedback. The exfu-solo plugin already distributes as a bundle via exfu.ai, so the channel pattern exists.
2. **The artefact**: package the plugin tree (manifest, skills, hooks + hooks.json, scripts, schemas, view, cheatsheet, philosophies) as an installable bundle; version from the manifest (semver — first test cut).
3. **Cowork verification** (T2-packaging §7 Q3): install + load in Cowork; document deltas (or confirm none).
4. **CI gate adapter template**: the thin caller M3 scoped out — a GitHub Actions example invoking `gate-check --ref` on PRs to main, shipped as documentation/template, no Actions dependency in the plugin itself.
5. **README quickstart**: install → init → first captured commit, in ten lines.

## 3. Scope

### In scope
- The four deliverables above + the mechanism decision.

### Out of scope
- Marketplace listing polish, telemetry, auto-update (T2-packaging §8).
- Backfill onboarding content (M5).

## 4. Verification

1. Clean-environment install simulation: from the artefact alone, plugin loads, skills surface, init attaches a sandbox repo, the loop runs (the M4 §6 "cold agent" pass rides on this).
2. Cowork: plugin loads; orientation + capture path exercised once; deltas documented.
3. CI template: run its steps locally against a sandbox repo (act-style or direct script invocation) — red log fails the job, green passes.

## 5. Dependencies

- T3-toolchain-portability, T3-project-init-flow, T3-session-orientation — the contents being shipped.
- T2-packaging §3.3 manifest.

## 6. Open questions

1. ~~Distribution mechanism~~ — ruled for the test phase (§2.1). Remaining: where on exfu.ai and the upload/update flow (operator walkthrough pending); and the public-distribution question, deferred until test feedback.
2. Does the dogfood repo consume the plugin from the artefact thereafter (eat the shipped build), or keep the vendored tree as the development home with the artefact derived? Lean: vendored stays the dev home; artefact is derived output.

## 7. Build notes (2026-07-03) — local-install path built; operator legs open

- **The artefact (§2.2)**: `scripts/build-bundle.sh` → `dist/apv-marketplace/` + `dist/agent-plan-visualiser-<version>.zip`. The bundle root is a **single-plugin marketplace wrapper** (`.claude-plugin/marketplace.json`, `source: "./agent-plan-visualiser"`) — the documented local-install shape, verified against code.claude.com/docs/en/plugin-marketplaces: plain non-git local dirs are supported marketplace sources; relative plugin sources resolve against the marketplace root. Install: `/plugin marketplace add <path>/apv-marketplace` → `/plugin install agent-plan-visualiser@apv`. Excluded from the bundle: `tests/`, `scripts/local/`, caches. Manifest bumped **0.4.1** — the first test cut. `dist/` is gitignored (§6 Q2 resolved as leaned: vendored tree stays the dev home; the artefact is derived output).
- **CI gate adapter (§2.4)**: `cheatsheet/worked-examples/ci-gate-adapter.md` — GitHub Actions template invoking `gate-check.sh --ref` on PR heads; no Actions dependency in the plugin. Runner needs bash/git/python3 only (gate path is stdlib-only). Its core step is exercised in the dist sandbox: green head → exit 0, red ref → exit 1.
- **README quickstart (§2.5)**: rewritten — install → init → first captured commit; the stale status section removed outright (docs carry no progress state; state lives in the log and its projections).
- **Verification**: `tests/dist/run-dist-sandbox.sh` is §4.1 and §4.3 plus the M4 §6 cold-agent core — build → unzip elsewhere → structural checks → from the bundle alone: init attaches a fresh repo, session orientation fires, guard rejects/passes, corrupt branch refused, clean branch lands, push gated, CI step green/red. ALL PASS.
- **Open — operator legs**: the **exfu.ai upload/placement walkthrough** (§6 Q1, unchanged) and the **Cowork verification (§2 item 3 / §4.2)** — both need the operator's environments; recorded as verification.skipped in the log, and this T3 stays live until they land. The first *real* Claude Code install of the bundle (plugin loads, skills surface, hooks fire in-session) is likewise the operator's local test — the sandbox proves everything up to the plugin-loader boundary.
