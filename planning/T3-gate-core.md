---
id: T3-gate-core
plan_kind: thematic
tier: 3
t2_parent: T2-extraction
milestone: M3-clean-gate
status: draft
---

# T3-gate-core — the boundary check and where it fires

**Status**: Draft.
**Sits at**: T2-extraction theme, M3-clean-gate milestone. Depends on T3-integrity-composite. Supersedes the `T3-pre-merge-hook` + `T3-server-side-cleanliness-gate` candidates (T2-extraction §4) — the CI half is deferred to a future thin adapter (M4-adjacent).

---

## 1. Why

The composite answers "trustworthy?"; this T3 makes the answer **enforceable at the merge-to-main boundary** without binding to any CI platform or hosting stance. Core + adapters: the check is one contract; where it fires is installation choice.

## 2. What

### 2.1 `gate-check` entry point

`scripts/gate-check.sh`: resolve the data dir (env → `.apt-config.toml` → default), run `gate-composite.py`, surface the report and exit code. The single contract every adapter calls.

### 2.2 Enforcement topology (design statement)

1. **Skill-procedural (primary)** — `/apt-merge` runs `gate-check` before a branch lands on main. The agentic path, and the only one that sees *local* merges (a local merge never pushes, so hooks can't catch it).
2. **pre-push adapter (belt-and-braces)** — refuses a push that updates `refs/heads/main` when `gate-check` fails on the outgoing state.
3. **Manual / future CI** — `gate-check` on demand; a GitHub Actions (or any CI) template is a thin caller of the same entry point, M4-adjacent, out of M3 scope.

### 2.3 Installer

Extend the M2 installer pattern (`install-hook.sh` or sibling `install-gate.sh`) with `--at=pre-push` (default) | `--at=manual` (PATH-only, no hook). Same idempotency contract as capture-guard: fresh install / identical no-op / differs-refuse, symlink-aware. Must coexist safely with any existing pre-push hook (refuse-if-differs; never clobber).

## 3. Scope

### In scope
- `gate-check` entry point; pre-push adapter; installer extension; sandbox tests.

### Out of scope
- Composite internals — T3-integrity-composite.
- The merge doctrine — T3-apt-merge-skill.
- CI templates — M4-adjacent.

## 4. Verification

1. `gate-check` exits 0 on this repo.
2. Sandbox (`/tmp` repo + bare remote): a push of main carrying a corrupted log is refused; the clean log pushes. Mirrors the capture-guard 4-path sandbox pattern.
3. Installer idempotency: fresh / identical / differs paths behave per contract.

## 5. Dependencies

- T3-integrity-composite — the check itself.
- M2's `install-hook.sh` — the installer pattern (and possible shared home).

## 6. Open questions

1. **pre-push scoping** — the hook receives updated refs on stdin; gate only when `refs/heads/main` moves, or on every push? Lean: only main (branch pushes are work-in-flight by doctrine).

## 7. Build notes (2026-06-10)

Shipped: `scripts/gate-check.sh` (the contract, two modes), `hooks/gate-prepush.sh`, `scripts/install-gate.sh`, `tests/gate/run-gatecheck-sandbox.sh`. All three §4 items green (9 sandbox cases, 36 assertions); composite fixture suite + repack-validate stay green. Decisions settled during the build:

- **gate-check owns the seal↔commit half** (T3-integrity-composite §6 Q1, confirmed as leaned): every committed `commit.recorded` seal's `message_first_line` must match the subject of a commit reachable from the checked ref. Log→git direction only (unsealed commits are sanctioned `--no-verify` trivia); message-not-SHA matching keeps it rebase-tolerant; what it catches is squash/reword orphaning the record.
- **The epoch doctrine extends to the seal discipline**, keyed on the seal's own `schema_version` (offending-event keying, mirroring resurrection). The dogfood log made the case empirically: 7 pre-0.3.0 seals are loosely-worded summaries of commits that exist under slightly different subjects — hand-written seals predate the exact-match law (/apt-capture, 0.3.0). They NOTICE; a ≥0.3.0 mismatch blocks.
- **Mid-flow tolerance** (filesystem mode): seals on log lines beyond HEAD's committed extent name the commit *to come* — capture-before-commit means the seal precedes its commit by design. NOTICE, never block. `--ref` mode (what pre-push calls on the outgoing sha) is strict.
- **§6 Q1 resolved: only main.** The adapter gates `refs/heads/main` updates, skips deletions (nothing outgoing), and lets branch pushes through untouched — sandbox-asserted. Resolution order for finding the check: `APT_GATE_CHECK` env → `agent-plan-tracker/scripts/` relative to the repo root → PATH.
- **Schemas resolve against the toolchain home, never `--repo-root`** — gate-composite fix surfaced by the sandbox, the first non-dogfood repo the gate ran against. Plugin content is code, not data (aptlib's doctrine made executable); a gated repo carries a log, not a copy of the schemas.
- Pre-adoption history (no log blob at the ref) passes with a notice — the gate guards the log's integrity; no log, no integrity claim. Documented impurity: the drift check reads the *working* `planning/` even in `--ref` mode (warn-only blast radius).
