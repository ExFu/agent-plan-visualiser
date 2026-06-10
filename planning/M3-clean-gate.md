---
id: M3-clean-gate
plan_kind: milestone
milestone_index: 3
status: planned
---

# M3-clean-gate — main's log stays a trustworthy record

**Status**: Planned (authored 2026-06-09 from the M3 design conversation; supersedes-in-part the gate prose in T2-extraction §3.7–3.8 and T2-projection §3.5 — correction notes added there).
**Sits at**: Third milestone on the sequence axis. Primary themes: T2-projection (the composite) and T2-extraction (enforcement + merge doctrine). Touches T2-storage (`.apt-config.toml` joins the data-dir resolution order).

---

## 1. Why this milestone

M2 made capture mandatory: every commit carries a sealed event block. M3 makes **main trustworthy**. The consumer of main's log is the next agent — cold, no session context — asking "where does this project stand?" M3 guarantees that read survives merges.

## 2. The reframe: protect the medium, not the content

Earlier prose framed this gate as *cleanliness*: "work trees can carry orphans … main cannot." That framing was wrong, and the correction (operator ruling, 2026-06-09) shapes everything in M3:

**Visible mess is the tracker succeeding.** An orphan, a stalled entity, an unresolved HITL question — these are *answers*: true state the system exists to surface. Loose ends that need a person are correct output, not defects. They belong on the dashboard (analyser, summary, flow view) and they merge to main freely.

**What the gate blocks is corruption of the record** — anything that breaks the cold read:

- Schema violations.
- Dangling references (a `decision` whose `event_ids` resolve to nothing; a relationship edge from an entity never created; lifecycle events against entities with no `entity.created`).
- An unsealed trailing run (events no commit owns — legitimate mid-session on a branch, illegitimate at the boundary).
- Implementation events against `draft` entities (the skill's draft gate is advisory in-session; the boundary is the enforcement backstop).
- Lifecycle events on a closed entity with no intervening `entity.reopened` — one log telling two incompatible stories (this also catches cross-branch contradictions after a merge, branch-agnostically).
- Fulcrum events without their paired `decision` — a consequential turn with no recorded *why*, cheap to fix at the boundary and unrecoverable later.

Integrity defects are never deliberately merged, so **there is no override machinery**. You don't override a dangling pointer; you fix it. (The override-decision design in T2-projection §3.5 is dropped.)

## 3. The three decisions that shape M3

### 3.1 Stance-neutral core, pluggable enforcement

One entry point (`gate-check`) runs the composite and exits non-zero with a report naming each instance. *Where* it fires is an adapter chosen at install time (`--at=pre-push|manual`). No GitHub Actions dependency — a future CI adapter is a thin caller of the same entry point (M4-adjacent). **Primary enforcement is procedural**: the `/apt-merge` skill runs `gate-check` before a branch lands on main. Hooks are belt-and-braces — local merges never push, so pre-push alone cannot see them.

> **Addendum (2026-06-10, operator ruling: local merges gate too).** A third adapter joins the family: `--at=ref-update` installs `hooks/gate-refupdate.sh` as the `reference-transaction` hook, refusing any local move of `refs/heads/main` whose incoming commit fails `gate-check` (strict `--ref` mode — the pre-push contract, applied locally). It is the only hook class that sees a **fast-forward** merge — no merge or commit hook runs on an ff, and ff is the standard `/apt-merge` landing — and it equally gates merge commits, direct commits on main, amends and resets: main never points at a red log. `reference-transaction` has no `--no-verify`, so the sanctioned hatch is explicit (`APT_SKIP_GATE=1` — tooling breakage, never red logs). Git updates the worktree before the ref transaction in an ff merge (verified empirically), so repo-relative `gate-check` resolution works even for the adoption merge that delivers the toolchain itself.

### 3.2 Branch-side reconciliation (merge doctrine, not merge program)

Conflicts are resolved **on the branch, by the in-session agent, before main moves** — the same hygiene PR workflows already practise. Rebase is acceptable (seals match `message_first_line`, not commit hashes — rebase-tolerant by design); merge only when there is actually something to merge. The `events.jsonl` conflict is the **designed trigger**, never suppressed (no union merge driver — auto-resolution would hide the one moment the agent must engage). The recipe: **main's log is the prefix; the branch's blocks append after; never reorder or edit within blocks** — append-only generalised to the branch level. Semantic contradictions surface to the operator (HITL is the system working); their ruling becomes reconciliation events in a fresh block **sealed by the merge commit** (the capture guard firing on conflicted merges is correct behaviour). Ships as skill instructions (`/apt-merge`), degrading to a documented manual procedure for non-agentic users.

### 3.3 Committed config over hardcode

`.apt-config.toml` at the **repo root** — root is forced by a chicken-and-egg: the config names the data dir, so it can't live inside it. TOML because `tomllib` is stdlib (Python ≥3.11): the zero-dependency stance holds. First keys: the gate's blocking/warn lists, and `data_dir` (the never-built middle layer of M2's resolution order: env var → committed config → default). Hardcoding policy inside scripts was rejected as the *riskier* option — invisible, unreviewable — not as YAGNI.

## 4. What M3 explicitly does NOT include

- **GitHub Actions / CI adapter** — future thin caller of `gate-check` (M4-adjacent).
- **Override machinery** — deleted by the reframe (§2).
- **Staleness smells** — a stale draft is a backlog item doing its job ("sitting there until someone does something with it" is its purpose). Never a smell.
- **Orphans / unresolved HITL / long blockers as blocking** — dashboard state; warn tier at most.
- **A merge-arbitration program** — doctrine + agent + skill instead. The `needs-review/` and `merge-conflicts/` filesystem protocols of the original design are not needed in-session.
- **Incremental cache/projection performance work** — still listed M3+ in T2-storage/T2-projection, but it's not gate work and not in this milestone.

## 5. How M3 delivers — T3 tasks

Three T3s. Dependency order in brackets.

1. **`T3-integrity-composite`** [foundation] — *T2-projection.* The integrity composite (blocking + warn catalogue, reworked under the cold-read framing), `.apt-config.toml`, and the frontmatter-vs-event drift audit (warn tier — the M1.2 IOU).
2. **`T3-gate-core`** [depends #1] — *T2-extraction.* The `gate-check` entry point, the enforcement topology, and the installer adapters (`--at=`).
3. **`T3-apt-merge-skill`** [depends #2] — *T2-extraction.* The branch-side reconciliation doctrine as a skill.

## 6. Definition of done

M3 is complete when:

- The **composite** runs against this repo's log: blocking = integrity defects (schema, referential, unsealed tail, implementation-on-draft, resurrection-without-reopen, fulcrum-without-decision); warn = drift, orphans, stalled, long blockers. Catalogue documented; lists read from `.apt-config.toml`.
- **`gate-check`** is installed on this repo via the installer (pre-push default) and runs green.
- The **`/apt-merge` skill** exists.
- **Self-referential acceptance test**: the branch carrying M2+M3 (this worktree) is brought to main via `/apt-merge` with `gate-check` green — M3's own delivery transits its own gate. The operator triggers the merge.
- The **drift audit** reports correctly against a synthetic drift fixture.

## 7. Resolved questions (M3-specific, from the 2026-06-09 design conversation)

1. **Enforcement location** → stance-neutral core + pluggable adapters; git hooks sane default; skill-procedural is primary.
2. **Override mechanics** → none. Integrity defects are repaired, not overridden.
3. **Staleness** → not a smell; drafts sit until triaged — that's their purpose.
4. **Strictness config home** → committed `.apt-config.toml` at repo root (resolves T2-extraction §7 Q2; hardcoding rejected).
5. **Supersession/orphan atomicity** (T2-extraction §7 Q1) → dissolved by the reframe: orphans don't block, so resolution may trail the supersession by any number of commits.
6. **Merge mechanics** → branch-side doctrine; rebase acceptable; merge only when there's something to merge; no custom merge driver.

## 8. Open questions

1. **Seal↔commit correspondence check** (each seal's `message_first_line` matches a real commit) needs git access — in the composite, in `gate-check`, or deferred? → T3-integrity-composite.
2. **Exact blocking-list membership at first ship** — start from §6's list, finalise in → T3-integrity-composite.
3. **Two-branch contradiction sandbox** for the skill's verification — required, or stretch if the real merge already exercises a conflict? → T3-apt-merge-skill.

## 9. Dependencies

- **M2-auto-extract** (complete) — the capture discipline + guard hook the gate builds on.
- **T2-projection §3.5** and **T2-extraction §3.7–3.8** — superseded-in-part; correction notes added 2026-06-09.
- **T2-ontology** — event-type catalogue the referential checks validate against.

## 10. After M3

**M4** packages for fresh installs — and naturally hosts the CI adapter template plus the deferred autonomous `claude -p` extractor. **M5** backfills. The warn tier keeps feeding the analyser/flow view as dashboard signal.
