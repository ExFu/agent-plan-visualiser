---
id: KT0-knowledge-substrate
plan_kind: thematic
tier: 0
tier_prefix: K
status: draft
---

# KT0-knowledge-substrate — tracking non-git knowledge work (proposal)

**Status**: Tier-0 **proposal**, draft, for later review. **Nothing in this document is decided.** It catalogues the problem space, the propositions explored in the 2026-07-21 assessment session, the pushbacks, and both parties' reasoning, so a fresh session can pick this up without re-deriving any of it. Where an opinion was expressed, it is attributed; where none was, that is stated. A future review either promotes this into a KT1 (side-quest intent) + KT2 candidates, or parks/supersedes it.

**Delivery logistics (operator instinct, 2026-07-21, not ratified)**: this work should be built on a branch, possibly in a **total project clone**, to avoid its metadata/tooling colliding with the main repo's own dogfood machinery (the build would be creating watchers, hidden repos, and hooks *about* tracking, inside a repo that is itself tracked). A fresh session should do the build; the assessment session was near context capacity.

---

## 1. The problem (Why)

Extend APV's value — the append-only record, the reconstructable why-chain, the projections — to **knowledge workers whose projects do not live in git**: work fragmented across Dropbox, Google Drive, email, and similar; users who are non-technical and will never run a VCS deliberately.

This is one of three assessment dimensions from 2026-07-21 and converges with the second (methodology profiles): a knowledge-worker planning profile must map at the **event level**, not the markdown-frontmatter level, precisely so it can ride a non-git substrate. The two designs constrain each other.

## 2. What the audit established (the constraint set)

A full git-dependency audit ran during the assessment (agent report, 2026-07-21). Its findings are the fixed ground this proposal stands on:

- **The event log has zero cryptographic self-protection.** No hashes, chains, or signatures. All tamper-evidence is donated by git (committed history, blame, the seal↔commit reachability check).
- **Git's roles decompose into four**: attestation that work happened (immutable commits), tamper-evidence over the log, the extraction substrate (diffs), and — operationally decisive, see §3 — **mechanical enforcement** (hooks).
- **Substrate-neutral and carrying over unchanged**: the ontology, the append-only log format, the derived-state machine, the entire gate-composite blocking set, the merge-reconciliation invariant (prefix-preserving linearisation), the write-side `enforce()` rules, projections, and all three views.
- **Rewrite-heavy**: capture (`/apv-capture` assumes a commit boundary), the hooks (git primitives), the extractor and backfill (built on `git diff`/`git show`).
- **Existing design seams that help**: T1 §3.5 self-contained records ("git availability is a bonus… not a prerequisite for ingestion"); bitemporality (T2-ontology §3.12) separating record time from event time; rebase-tolerant seals (bound by message, not hash — the git binding is deliberately loose already).

## 3. Design axioms that emerged (strongly held, treat as law unless overturned at review)

1. **The enforcement axiom (operator, decisive).** "Agents *often* forget or miss or ignore the instructions to use APV properly. The actual lock of the git commit hooks is triggered as often as not. Any approach that *requires* the agent to remember is going to be error-strewn." No design may depend on agent or human memory or voluntary ceremony. Mechanical enforcement only. This axiom killed several propositions below and is empirical (observed guard firings in this very repo).
2. **The publication insight (operator, generalised by Claude).** "Git works because the work doesn't really exist until it's been pushed." The enforceable boundary in any substrate is **publication** (send, share, deliver, mark done), not save. Saves cannot carry ceremony; publications can.
3. **Up-front planning primacy (operator, emphatic).** "M5's backfill doctrine is a best effort, but it's absolutely nowhere near as rich as doing the planning up front originally. Not even close." After-the-fact inference is a fallback, never the design centre. Claude conceded this fully; its counter-position (that *structural* attribution via plan scopes changes reconciliation from archaeology to bookkeeping — §4 P11) is a proposition, not an agreed resolution.
4. **Session boundaries are unreliable (operator, decisive).** People walk away from open sessions, especially at close time, and won't perform closing ceremony. Nothing may hang on a session ending cleanly.

## 4. Propositions catalogue

Everything contemplated, with pros, cons, and expressed opinions. **None of these is ratified.**

### P1 — Cloud version history as the commit-analogue
*Proposed by Claude (early in discussion).* Box/Dropbox/Drive revisions are immutable, timestamped receipts; if `events.jsonl` itself lives in the cloud store, the store's version history over the log plays both of git's trust roles (attestation + tamper-evidence) with zero cryptography.
**Pros**: exists today, zero build; honest v1 trust story. **Cons**: no hooks → fails the enforcement axiom (operator's point); revisions are too noisy to be semantic boundaries (Claude conceded); store could theoretically rewrite history, no content-addressing.
**Standing**: not rejected as an *evidence anchor*; rejected as the *enforcement* mechanism. Survives inside later propositions as the corroboration layer.

### P2 — Session-as-commit (harness SessionEnd/Stop hooks trigger the seal)
*Proposed by Claude.* The in-session agent seals a block at session end; harness hooks make the trigger mechanical; git pre-commit guard enforces capture-before-commit beneath.
**Operator ruling: rejected.** Axiom 4 — sessions get abandoned open; the closing ritual never happens. (In-session capture stays the *gold path* when a session is live and healthy; it just cannot be the load-bearing trigger.)

### P3 — Event-sourcing database as the store
*Raised and self-rejected by the operator in the same breath.* Swapping JSONL for an ES database changes storage, not the trigger problem. No pros claimed. Dead.

### P4 — Nightly librarian (the ExFu plugin concept)
*Raised by the operator, self-critiqued immediately*: (a) doesn't respect project boundaries; (b) by the time it runs, sessions have closed and "the Why's and all the rich, juicy, in-session knowledge is lost already."
*Claude's counter*: (a) is solved if a hidden per-project repo defines the boundary (the librarian walks repos, not the disk); (b) is partially answered by M5's three-tier Why doctrine (recovered / recollected / inferred, never fabricated) — What-only events overnight, candidate Whys queued for human triage.
*Operator's rebuttal*: axiom 3 — backfill inference is nowhere near up-front planning richness. **Standing**: librarian survives only as a *sweeper* for what escapes richer layers, never as the primary capture path. Not ruled on in that reduced role.

### P5 — Hidden git under the hood ("projects need git; non-techies just don't see it")
*Proposed by the operator; endorsed and extended by Claude.* The spine-repo shape (Claude): the hidden repo holds **only** `planning/` + the event log — the record, not the work. Work products stay where the person works (Drive, Dropbox, email); events carry **evidence anchors** into those substrates (Drive revision id, Dropbox `rev`, email message-id — the generalisation of `commit_ref`). This inverts the trust story: for developers git history is primary and the log derives; for knowledge workers **the log is primary** (protected by the hidden repo's real git machinery) and the substrates corroborate.
**Pros**: nearly all existing machinery runs unchanged (hooks, gate, merge doctrine, cache, projections, views); invisible to the user. **Cons / open** (operator): knowledge work is fragmented "all over the shop" and doesn't arrive repo-shaped; and hidden git alone doesn't answer *who triggers the commit* (see P10/P11).
**Standing**: the most-favoured structural substrate; no formal ruling.

### P6 — Shadow working directory ("work doesn't exist until reconciled")
*Proposed by the operator.* Agent works on copies in a shadow location; reconciliation back is the boundary event. Operator's own critiques: requires building "a load of under-the-hood mechanisms and scripts… effectively reinventing git for knowledge workers"; and workers would be confused that they can't see changes in their real folders. Operator also noted, tentatively (🤔), that reinventing git for knowledge workers "may not be an entirely stupid move… could be a market position with great opportunity."
**Standing**: superseded in discussion by P8's inversion, which keeps the visible folder live. The market musing is recorded in §7.

### P7 — Git repo hosted *in* the sync substrate (clone from Dropbox to local shadow)
*Proposed and self-rejected by the operator.* Avoids worktree metadata in Dropbox, but "the git view of origin would constantly fuck up while people worked on it from different locations and Dropbox keeps reconciling." Correct — sync engines corrupt live git metadata. **Dead.**

### P8 — The witness-repo inversion
*Proposed by Claude in response to P6/P7's failure modes; no operator ruling yet.* Invert P6: **the Dropbox/Drive folder stays the visible working copy** (humans see everything live — P6's confusion objection gone); **the hidden local repo is the shadow**, living *outside* the sync tree (P7's corruption gone), fed by a file watcher observing the project folder. The repo is a **witness, not a master**: nobody clones it, nobody pushes to it, no "origin" to corrupt. Multi-device/multi-person: each machine's witness records what it observes; reconciliation happens in the **event log** by the existing prefix-preserving merge doctrine, not by git-merging working trees; sync-conflict moments ("conflicted copy") become recorded events.
**Residual weakness (Claude, acknowledged)**: simultaneous multi-writer editing remains the hard tail.

### P9 — Alternative version-control systems (operator asked directly; Claude surveyed)
- **Jujutsu (jj)** — the one credible candidate. The working copy *is* a commit; every operation auto-snapshots; no staging area; the "forgot to commit" failure class does not exist structurally. Conflicts are stored in commits (never block); operation log with universal undo; **git-compatible backing store**, so APV's git-reading machinery survives underneath. Weaknesses: developer CLI; continuous snapshotting needs a file watcher; hook/enforcement story immature (the gate would move to the bookmark-move/push boundary).
- **Fossil** — single-file SQLite repo, robust, batteries included; nothing structural for the trigger problem.
- **Auto-commit daemons over plain git** (gitwatch, Dura) — a watcher commits every save; removes the trigger by removing meaning (commits become noise); tolerable if commits are the *witness layer*, not the record.
- **Local-first / CRDT** (Automerge, Yjs) — per-document op logs are native event sourcing; right theory, wrong packaging (app-level, not files-on-disk).
- **Verdict (Claude)**: nothing off the shelf is "git for knowledge workers"; jj is the closest structural fit and cheats by being git underneath. **No operator ruling.**

### P10 — OS-level save gates + the three file classes
*Proposed by the operator (latest and preferred direction of travel at session end).* Classify every file in project scope as: **metadata/non-project** (untracked), **planning files**, or **project files**. The latter two get *real* save gates — "you just literally can't save if it's write-blocked", so **every edit accrues against a plan**. At a quiet interval ("okay, all of those edits that just happened in the last seven minutes get locked in") a reconciliation locks the burst; at the relevant moment a projection surfaces in conversation ("okay, we're done on that plan") and the edits project against it. Operator's own caveat: "that feels like a really OS-level type thing" (i.e. heavy).
*Claude's feasibility notes*: true OS-level write-veto exists on macOS via **FSKit/FUSE project mounts** (a filesystem you control; writes return EACCES unless conditions hold) or the **Endpoint Security framework** (AUTH events can deny writes; needs an Apple-granted entitlement). Both real; both heavy. Claude's UX objection: hard-blocking a *human's* save risks confusion/lost work — the same class of objection the operator raised against P6.

### P11 — The layered architecture (Claude's synthesis of P5+P8+P10; **no operator ruling yet**)
The save gate decomposes into two different problems, one already solvable:

- **New ontology piece**: plans declare a **file scope** (paths/globs in frontmatter). The three P10 classes fall out of this: metadata (unscoped, ignored), planning files (lifecycle events), project files (covered by some plan's scope). Attribution becomes *structural and prior* — which is the specific answer to axiom 3: reconciliation over scoped edits is bookkeeping, not archaeology, because the plan mapping existed before the edit.
- **Layer 0 — agent edit gate** (buildable in days, zero OS work): a harness **PreToolUse hook denies any Edit/Write** in project scope unless the session has declared an active-plan pointer (e.g. `.apv/active-plan`). The operator's save gate, for agents, today — the draft gate moved from commit time to edit time. Fires mechanically; satisfies axiom 1.
- **Layer 1 — witness watcher** (weeks): hidden witness repo (P8) + FSEvents watcher + quiet-period burst chunking + scope attribution. Guarantees *what happened* is never lost, regardless of sessions or ceremony. Humans are never blocked — writes are born attributed instead (Claude's "attribution beats prohibition").
- **Layer 2 — reconciliation surface**: the in-conversation projection at completion moments ("fourteen edits locked against T3-foo; three unattributed — assign or spawn?"); Why captured in or near context, not overnight.
- **Layer 3 — lifecycle locking** (the one place hard-blocking is clearly right, Claude's view): when a plan closes/parks, its scope goes **read-only** (plain ACLs). Editing a closed area forces the reopen ceremony — resurrection discipline enforced *before* the fact rather than detected after.
- **Layer 4 — true OS gating** (FSKit mount / Endpoint Security), built **only if the pilot proves civilians need more than layers 0–3**.

## 5. T2 candidates (if/when a KT1 is authored)

Sketches only; scoping belongs to the future workstream, not this proposal.

| Candidate | Owns | Notes |
|---|---|---|
| `KT2-substrate-interface` | The formal generalisation of (commit, sha, git-history) → (boundary event, evidence anchor, integrity anchor); trust model incl. the parked hash-chain option | The design keystone; everything else implements it |
| `KT2-plan-scopes` | The new ontology piece: scope declarations on plans, scope→entity attribution rules, overlap/conflict semantics | Needed by every layer; likely lands partly in the main spine's T2-ontology |
| `KT2-agent-edit-gate` | Layer 0: PreToolUse deny, active-plan pointer, draft-gate-at-edit-time | Prototypable against this repo first — dogfood before any civilian build |
| `KT2-witness-layer` | Layer 1: hidden repo, watcher, burst chunking, born-attributed witness blocks | P8 architecture |
| `KT2-reconciliation-ux` | Layer 2: the conversation surface, Why capture at completion, unattributed-edit triage; the librarian in its reduced sweeper role | Where axiom 3 is honoured or violated — design with care |
| `KT2-lifecycle-locking` | Layer 3: ACL read-only on closed/parked scopes, reopen flow | Small, high leverage |
| `KT2-ingest-connectors` | Backfill analogue: walking Drive/Dropbox/email histories with evidence anchors | Hardest, latest; M5 doctrine applies |
| `KT2-pilot` | The first real deployment | Claude suggested the operator's own Brain-for-Claude vault (file-based, real knowledge work, operator is the user); **operator has not ruled** |

## 6. Open questions (unresolved, in rough priority order)

1. **The project boundary.** The hidden repo defines a project — but who draws that boundary for a civilian whose work is fragmented everywhere? Possibly the pilot's first research question. (Claude raised; unanswered.)
2. **Multi-writer.** Simultaneous edits from multiple people/devices on the same substrate folder — witness reconciliation handles sequential divergence; true concurrency is unsolved here.
3. **jj vs plain git as the witness plumbing.** jj removes the forgot-to-commit class structurally but has an immature hook story; plain git + watcher is boring and proven. (Surveyed, unruled.)
4. **The hash-chain.** Parked by explicit operator choice (2026-07-21: "keep discussing non-git first") so this design could shape it. This proposal is that design; the review should re-open the question.
5. **Blocking humans, ever?** Layer 4's existence acknowledges the operator's instinct that real gates matter; Claude's position is layers 0–3 make it unnecessary for humans. Unresolved — a pilot question.
6. **Where the reconciliation conversation lives** for a non-Claude-session user (Cowork? A daily digest? The dashboard?).
7. **Naming/positioning tie-in.** The whitepaper thesis ("agents need a record that cannot lie") and this product are the same claim for two audiences; the methodology name (pending, see inbox `2026-07-21.methodology-name-pending`) should probably work for both.

## 7. The market note (recorded, not a commitment)

Operator, tentatively: reinventing git for knowledge workers "may not be an entirely stupid move… could be a market position with great opportunity." Claude's framing: that turf belongs to the local-first movement and remains unwon because civilians don't want *version control* — twenty years of Track Changes and Drive history go unused. What nobody sells them is what versions enable: **memory, accountability, and answers to "how did we get here and why."** The differentiated play is the record and the methodology riding proven hidden plumbing, not a VCS war. No decision taken.

## 8. Provenance

Produced at the end of the 2026-07-21 assessment-and-M6 session (the session that also delivered the CLAUDE.md de-state ruling, M6-dashboard, and the whitepaper draft). Participants: Alastair (operator) and the in-session agent. The methodology-profiles thread (assessment dimension 2) ran alongside and converges here via the knowledge-worker profile; its own record lives in the session plan file and the whitepaper's mapping section. This document deliberately records *contemplation*, not commitment — review it fresh before building anything.
