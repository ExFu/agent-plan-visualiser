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
