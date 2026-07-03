---
id: T3-autonomous-extractor
plan_kind: thematic
tier: 3
t2_parent: T2-extraction
milestone: M4-fresh-install
status: draft
---

# T3-autonomous-extractor — capture for commits no session agent saw

**Status**: Draft (authored 2026-06-10 post-ceremony, under the M4 §7 Q1 ruling: in-wave, sooner rather than later — the operator's discovery that `claude -p` runs within subscription allowances dissolved the cost concern behind the original deferral). Supersedes the `T3-autonomous-extraction-hook` candidate name (T2-extraction §4).
**Sits at**: T2-extraction theme, M4-fresh-install milestone. Depends on T3-toolchain-portability (invokes the toolchain by its post-rename, plugin-root-resolved paths). Builds the design retained in T2-extraction §3.4/§3.6.

---

## 1. Why

M2's capture discipline assumes the committer *is* a Claude session with full context. Humans committing from an editor, CI bots, and collaborators without Claude Code produce commits no agent saw — today those rely on `--no-verify` (sanctioned for trivia, wrong for real work) or block on the guard. The extractor closes the gap: the same capture contract, produced autonomously at commit time by `claude -p`.

## 2. What

### 2.1 The flow (T2-extraction §3.4, updated to the M2+ ontology)

One hook entry point for non-session commits:

1. If `.last-capture` is fresh (a session agent already captured) → pass through; the extractor never runs. Session capture remains primary.
2. Otherwise assemble the input bundle: staged diff, commit message, the log tail (last N blocks), the ontology summary, plan frontmatter for touched plans.
3. Invoke `claude -p` with the extraction prompt; receive the event list per the §3.3 output contract (events + optional ambiguity report + token summary).
4. Validate every event against the schema; enforce the write-side rules the capture skill enforces in-session — **the extractor may never emit `entity.accepted`** (operator-only), never resurrect closed entities, never edit prior lines.
5. Clean: append the block (terminal seal matching the commit's first line), stage the log, stamp, exit 0.
6. Ambiguous or invalid: **default-to-halt** (T2-extraction §3.6) — write `needs-review/<commit-slug>.md` (ambiguity, recommended resolution, candidate events, next steps) into the data dir, exit non-zero, commit blocked. The operator resolves in-session.

### 2.2 Installation

Opt-in, via the init command (`--with-extractor` or equivalent flag added to T3-project-init-flow's surface): installed setups chain it ahead of the capture-guard — extractor produces the capture, guard verifies it. Hook-averse setups keep the manual story (T2-extraction §3.4's alternative).

### 2.3 Out of the first cut

- Sub-agent recursion for overflow diffs (T2-extraction §3.5) — pulled forward only when a real commit overflows (§4 candidate `T3-sub-agent-recursion` stands).
- Backfill reuse — the machinery is shared with `backfill.py` by design, but catch-up over history is M5.

## 3. Scope

### In scope
- The hook script + extraction prompt; schema + write-rule validation; ambiguity halt path; init-flow flag; sandbox verification.

### Out of scope
- Session capture (M2, unchanged and primary).
- History mining (M5).
- Gate semantics (M3, unchanged — the extractor produces blocks; the gate judges them).

## 4. Verification

1. Sandbox: a non-session commit (no fresh stamp) triggers extraction; the appended block validates, seals to the commit subject, transits guard and gate green.
2. Ambiguity fixture: a diff engineered to be unattributable halts the commit and writes a well-formed `needs-review/` file; nothing is appended.
3. Acceptance-rule fixture: a prompt-injection-shaped diff cannot make the extractor emit `entity.accepted` (write-side rules enforced in code, not prompt).
4. Allowance check (operational, documented not asserted): invocation runs under `claude -p` within subscription allowances.

## 5. Dependencies

- T3-toolchain-portability — paths, naming, plugin-root resolution.
- T3-project-init-flow — carries the opt-in install flag.
- T2-ontology schema; M2 capture rules (the contract being reproduced autonomously).

## 6. Open questions

1. **Which hook?** pre-commit has no access to the commit message (needed for the seal); `commit-msg` receives the message file and can still block. Lean: commit-msg for the autonomous path (the guard stays pre-commit).
2. **Model + prompt budget** for `claude -p` — smallest model that extracts reliably? Resolve empirically in the sandbox.
3. **Confidence field** — autonomous events as `confidence: "derived"` rather than `"explicit"`? Lean: yes — the log should show which blocks no human/session vouched for at write time.

## 7. Build notes (2026-07-03)

Accepted at the M5 ceremony (operator ruling: build now; M4 identity kept) and built same day.

- **Q1 ratified with a discovered twist — the hook is a *pair*.** commit-msg (`hooks/extract-capture.sh`) extracts, because it alone receives the message the seal quotes; but git writes the commit's **tree before commit-msg runs**, so the appended block cannot ride its own commit from there. `hooks/extract-amend.sh` (post-commit) closes the gap: on the extractor's pending flag, it amends the just-created commit to include the log — recursion-safe (flag consumed first; the amend runs `--no-verify`). Verified: the block is IN the commit it seals; worktree clean after.
- **The guard defers, detected not configured**: capture-guard stands aside when a commit-msg hook carrying the `apv-extract` marker is installed — otherwise uncaptured non-session commits would be rejected at pre-commit before extraction could ever run. The extractor applies the identical staleness contract, so session capture stays primary (fresh stamp → extractor no-ops; asserted with a booby-trapped stub).
- **Q3 ratified in code**: the orchestrator (`scripts/extract-commit.py`) forces `confidence: "derived"`, sets `actor` from the committer, and substitutes ground-truth seal fields (`message_first_line`/author/date) regardless of model output. Write-side rules are code, not prompt (§4.3 proven with a prompt-injection-shaped canned response): `entity.accepted`/`analysis.*` rejected unconditionally, draft gate with the implicit-work same-block carve-out, resurrection-without-reopen rejected via state replay from the log, fulcrum-decision pairing required, UUID validity + uniqueness, JSON-Schema validation (fails closed if `jsonschema` is missing). Oversize diffs (>80k chars) halt rather than truncate — sub-agent recursion stays out of the first cut, as scoped.
- **Q2 open, machinery ready**: model selection rides `APV_EXTRACT_MODEL` (passed to `claude -p --model`); default is the CLI's default. Tests stub the model (`APV_CLAUDE_BIN`) so the pipeline is deterministic and free; §4.4's live-allowance check stays operational-documented (`APV_LIVE_EXTRACT=1` runs a real smoke).
- **Install**: `scripts/install-extractor.sh` installs both halves under the shared idempotency contract, `--home=` baked like the gate adapters; `/apv-init --with-extractor` flags through (§2.2 as designed). The pending flag and stamp are gitignored by init.
- **POSIX scar for the record**: `[ cond ] && exit 1` as a loop's final command reads a *fresh* capture as stale (false test → status 1 → pipeline fails); the if-form is load-bearing and now commented in both hooks. A `case` inside `$(...)` also broke parsing — patterns are `(...)`-parenthesised.
- Sandbox: `tests/extractor/run-extractor-sandbox.sh` covers §4.1–4.3 + the amend half + session-capture pass-through; full regression green (guard change is invisible to extractor-less repos); the dogfood repo's installed guard refreshed by rm + reinstall.
