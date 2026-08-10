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

## 8. Ruling (2026-07-23) — public distribution decided

Resolves §6 Q1's remaining public-distribution leg (was "deferred, not decided"). **Public distribution is a git marketplace**: marketplace `exfu` @ https://github.com/ExFu/claude-marketplace, with the plugin published to its own repo https://github.com/ExFu/agent-plan-visualiser and installed `agent-plan-visualiser@exfu`. The exfu.ai private-bundle test channel (§2.1) is **superseded** for public delivery; `build-bundle.sh` and its local single-plugin marketplace survive as the offline/dev install path only.

Rationale: a git-hosted marketplace is the **only channel both Claude Code and Cowork honour**, so it is the mechanism that fixes cross-client enablement rather than papering over it. Publishing across the exfu plugin family is now git-push-to-publish, one marketplace for all of them.

The consumer-side model this unlocks — one global install, a repo that declares its own APV dependency portably, per-client verify-and-whinge — is carried by [[T3-cross-client-install]] (new sibling in the M4 wave). README + the `apv-init.sh` not-found hint already point at the public marketplace (operator-directed, pre-plan).

## 9. Release 0.7.1 (2026-07-23) — toolchain path portability. **Re-attach required.**

The first field report from a repo running APV purely as an installed plugin (`exfu_planner`, not a vendored checkout) surfaced a class of defect that dogfooding is structurally blind to: **the toolchain and the tracked repo are the same tree here, and only here.** Every surface that addressed the toolchain as `agent-plan-visualiser/...` worked perfectly in this repo and resolved to nothing for every real install.

**What was broken for installed users**

- **Capture discipline's validation leg — the whole chain.** `/apv-capture` §6 step 1 instructed `bash agent-plan-visualiser/scripts/repack-validate.sh`; from an installed project that is exit 127. `repack-validate.sh` itself then did `cd "$(dirname "$0")/../.."`, landing the cwd in the plugin cache's *parent*, so even a correctly-anchored invocation (as the cheatsheet already used) failed at step 1. `validate-events.sh` and `validate-plan-frontmatter.sh` defaulted their schema paths the same way. Net effect: **the validation step that gates every sealed commit has been unrunnable outside this repo since packaging.** Logs captured downstream in that window were sealed without it; a retrospective `gate-check --ref` over affected repos is the honest remedy.
- **`/apv-merge`'s gate invocation** (§0 precondition, §5, §6 manual step 5) — same shape, so the documented landing path was equally unrunnable.
- **The launcher, silently.** `apv-init.sh`'s discovery glob was `*/agent-plan-visualiser/*/`. The 0.7.0 package rename to `exfu-agent-plan-visualiser` means that glob matches **only pre-rename installs**: measured against a real cache it returned ten retired `0.5.x–0.6.3` dirs and missed `0.7.0` entirely. `hooks/gate-prepush.sh` already had the correct `*/*agent-plan-visualiser/*/` form — the rename updated one ladder and not the other.
- **The autonomous extractor, totally.** `hooks/extract-capture.sh` had no cache-discovery rung, and `install-extractor.sh` bakes `APV_HOME` only when given `--home`, which `apv-init` deliberately withholds for `*/plugins/cache/*` toolchains. No rung could resolve ⇒ **every commit blocked** for anyone installed `--with-extractor`.

**Fixes.** Toolchain content (schemas, sibling scripts) now resolves from each script's own location; the tracked repo resolves independently via `git rev-parse` — the split `gate-check.sh` has always made. Data and planning dirs route through `apvlib` (`APV_DATA_DIR` → `.apv-config.toml` → `.apv/`), so the pinned-`planning_dir` monorepo no longer gets a green `all 0 plan files valid` — zero files checked is now a failure, not a pass. Shipped instructions anchor on `$APV`, which `/apv-capture` §0 now **defines** as a runnable resolver rather than assuming (it was used 17× across the package and defined 0×).

**Guard.** `tests/audit-toolchain-paths.sh` — static sweep over `git ls-files` for unguarded toolchain-relative paths, the dogfood `cd`, and unanchored pipeline invocations, separating blocking (live surfaces) from advisory (comment banners). Verified to have teeth: **21 blocking hits against the 0.7.0 tree, 0 against 0.7.1.** It exists because the bug's real cause was not any one bad path but the absence of a check that could see the layout it assumed. Note the shape it guards against: three of the ten `repack-validate.sh` references were **bare names** carrying no `agent-plan-visualiser/` substring, so a fix campaign grepping the folder prefix alone would have left them behind — which is exactly the false negative that opened this investigation.

**OPERATOR ACTION — every attached repo must re-run `/apv-init`.** `apv-init.sh` deliberately does not gitignore the generated `<data-dir>/bin/apv` shim (machine-independent, meant to be committed). The broken glob is therefore **committed into every repo attached at ≤ 0.7.0**, and will keep resolving to a retired `0.6.3` toolchain until each repo regenerates its shim. Updating the plugin alone does not fix those repos. This dogfood repo has never been init'd (no `./apv`, no `.agent-plan-tracker/bin/`) — which is precisely why the glob survived the rename unnoticed.

`[requires] apv_min_version` is left at `0.6.4` per its own doctrine (operator raises the floor deliberately; never auto-bumped). Raise it to `0.7.1` when a repo needs the fixed capture instructions to be guaranteed present.

**Known, still open after this cut:** the analyser's live-summary save remains dead for any data dir other than `.agent-plan-tracker/` — `serve.py:59` loads `schemas/0.2.0`, so the enforcing `freeform_path` pattern is `0.2.0:335`, not the 0.6.0 copy. Out of this release's scope (it is not on the capture path) and carried separately.

## 10. Release 0.7.2 (2026-08-10) — licence declared, marketplace repo renamed. **No re-attach required.**

Documentation, identity and licensing only: no behaviour on the capture, gate or extraction paths changes, so the 0.7.1 re-attach instruction (§9) is not repeated. `[requires] apv_min_version` stays `0.6.4` per its own doctrine.

**Provenance — this cut was authored from outside.** An agent working the `exfu` marketplace across the whole plugin family made these edits here without APV context: it did not know the repo is tracked, so the change set arrived uncommitted, uncaptured and half-staged in the working tree (three mode-only changes staged, the rest not). Reviewed retrospectively, corrected, and captured as this block. **The record was never at risk** — `events.jsonl` was untouched, and `gate-check.sh`, `audit-rename.sh` and `audit-toolchain-paths.sh` all pass against the incoming tree. The failure mode is worth naming, because it recurs whenever a cross-repo campaign meets a tracked repo: a fleet-wide sweep is exactly the kind of work that produces correct edits and no events.

**What the cut carries**

- **Licence declared.** Proprietary: `LICENSE` at the repo root, `"license": "Proprietary"` in the manifest, licence sections in both READMEs. The repo stays public for distribution convenience; publication grants nothing.
- **Marketplace repo renamed** `ExFu/claude-marketplace` → `ExFu/exfu-marketplace` on the live surfaces: `CLAUDE.md`, the plugin README quickstart, `apv-init.sh`'s not-found hint **and the CLAUDE.md orientation block it stamps into attached repos**. The old URL still resolves by GitHub redirect, so nothing was broken in the interim — the §8 ruling's mechanism is unchanged, only its address.
- **Root `README.md` added** — the repo's front door (install, what's in the tree, the source/consumer duality); the plugin README remains the full quickstart.
- **`jsonschema` documented as a real prerequisite.** The extractor fails closed without it, so a fresh installer previously met that as a halt at their first tracked commit rather than as a requirement up front.
- Executable bits set on `capture-guard.sh`, `extract-amend.sh`, `install-hook.sh` (cosmetic — `install-hook.sh` chmods on copy regardless).

**Defect found and fixed in review: `../LICENSE` was dangling in every install shape.** The marketplace installs APV as `git-subdir` at `path: agent-plan-visualiser`, and `build-bundle.sh` stages that subtree alone — so a root-only `LICENSE` ships to nobody, and the plugin README pointed at a file no installed copy contains, while the manifest had just begun asserting Proprietary. The licence text now lives at `agent-plan-visualiser/LICENSE` too (the root copy stays for the repo), and the README link is plugin-root-relative. **Shape worth remembering: the repo root is not part of the artefact.** Anything an installed user must be able to read belongs inside `agent-plan-visualiser/`, and the two install shapes — git-subdir and `build-bundle.sh` — are the only tests of that.

**Deliberately not changed:** the four pre-rename marketplace URLs in `planning/` (§8 above, and [[T3-cross-client-install]] §§1/2/5). Those record rulings as they were made; append-only law puts the new address in this section, not over the old prose. `audit-rename.sh` does not guard marketplace URLs — it guards the tracker→visualiser rename — so it flags neither, by design.

**Residual, outside this repo (operator legs):** the `exfu-marketplace` catalogue commit declaring Proprietary on every entry is **committed but unpushed**, so the licence this manifest asserts is not yet on the surface anyone installs from; and this machine's `known_marketplaces.json` still registers `exfu` under the old URL with `autoUpdate: true`, working only by GitHub's redirect. Carried as `2026-08-10.exfu-marketplace-rename-residuals`.
