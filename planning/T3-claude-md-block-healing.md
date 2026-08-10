---
id: T3-claude-md-block-healing
plan_kind: thematic
tier: 3
t2_parent: T2-packaging
milestone: M4-fresh-install
status: active
---

# T3-claude-md-block-healing — the orientation block must heal itself on re-init

**Status**: Accepted 2026-08-10 (operator ceremony, §8 Rulings); implementation authorised. Capture contract in §9.
**Sits at**: T2-packaging theme, M4-fresh-install milestone. Completes an unbuilt clause of [[T3-cross-client-install]] §2 Layer 1.2, extends the writer owned by [[T3-project-init-flow]] §2.4, and optionally adds a detection prong to [[T3-session-orientation]]'s SessionStart hook. Exposed by the rename in [[T3-distribution]] §. Executable cold: carries every file path, line number and command needed in this repo.
**Authored**: 2026-08-10, from a consumer-side field report in the `exfu-agent-planning-and-delegating` repo (external; see §7).
**Reviewed**: 2026-08-10, in-repo. Every load-bearing claim re-verified against source (`apv-init.sh:539/:576`, `run-init-sandbox.sh:148-155`, the four hook globs, the event log's `entity.completed` for [[T3-cross-client-install]]) — all hold. Three defects corrected: the §3.2 repo table was short by one attached repo; §6 wrongly reported the consumer-side repair as landed on `main`; and the emitted glob is less rename-robust than the hooks', now raised as Q5.

## 1. Why

APV stamps a `<!-- apv:orientation -->` block into every attached repo's `CLAUDE.md`. That block is **Layer 1** of the cross-client install model — and per [[T3-cross-client-install]] §3 it is the *sole* owner of the `not-loaded-at-all` failure mode:

> *not-loaded-at-all*: unreachable by a plugin hook (it cannot fire), owned entirely by the Layer-1 CLAUDE.md block the agent always reads.

So the block is the only thing standing between a cold agent and a repo whose plugin never loaded. It is also the **only live surface APV writes that APV can never subsequently correct.** `scripts/apv-init.sh` appends it once and thereafter treats its mere presence as success:

```
scripts/apv-init.sh:576
  if [ -f CLAUDE.md ] && grep -qF "$APV_MD_MARKER" CLAUDE.md; then
    report ok "CLAUDE.md" "orientation block present"
```

Present, not *correct*. Every attached repo therefore carries a frozen snapshot of whatever the toolchain said on the day it attached, and re-running init — the one action a user would reasonably expect to fix it — is a no-op.

### 1.1 This is not hypothetical; it has already fired twice

**Rename 1 — the plugin (`agent-plan-visualiser` → `exfu-agent-plan-visualiser`).** Blocks stamped before it instruct a stranded agent to read:

```
~/.claude/plugins/cache/*/agent-plan-visualiser/*/skills/apv-capture/SKILL.md
```

That glob matches **nothing** post-rename — it needs a leading `*` on the package segment. Verified on a live install:

```console
$ ls -d ~/.claude/plugins/cache/*/agent-plan-visualiser/*/
zsh: no matches found
$ ls -d ~/.claude/plugins/cache/*/*agent-plan-visualiser/*/
/Users/al/.claude/plugins/cache/exfu/exfu-agent-plan-visualiser/0.7.1/
```

The launcher (`.apv/bin/apv`) and both git hooks already carry explicit comments warning about this exact glob trap. The CLAUDE.md block — the highest-stakes copy, because it is the recovery path of last resort — never got the fix. **The failure mode is precisely inverted: the block is most wrong exactly when it is most needed.**

**Rename 2 — the marketplace (`ExFu/claude-marketplace` → `ExFu/exfu-marketplace`).** Already diverging inside this repo, between the released cache and unreleased `main`:

```console
$ grep -o 'github.com/ExFu/[a-z-]*' agent-plan-visualiser/scripts/apv-init.sh | sort -u
github.com/ExFu/exfu-marketplace          # repo, 0.7.2 (unreleased)
$ grep -o 'github.com/ExFu/[a-z-]*' ~/.claude/plugins/cache/exfu/exfu-agent-plan-visualiser/0.7.1/scripts/apv-init.sh | sort -u
github.com/ExFu/claude-marketplace        # cache, 0.7.1 (released)
```

Survives only on a GitHub redirect ([[T3-distribution]] notes this explicitly). But it means **every block stamped by 0.7.1 is stale-on-arrival the moment 0.7.2 ships, and none of them will ever heal.** Two renames in roughly three weeks; the drift is monotonic and the install base only grows.

### 1.2 It contradicts a doctrine this project already holds

`agent-plan-visualiser/tests/audit-rename.sh` exists to enforce, in its own words, that *no pre-rename references survive on live surfaces* — with a deliberate, documented allowlist that **is** the doctrine (append-only data dir, epoch-frozen schemas, closed plans as archaeology).

That audit scans tracked files **in this repo only**. The orientation blocks APV stamps into consumer repos are live surfaces of exactly the kind the audit was written to protect, sitting where it cannot see them — and the sole mechanism that could reach them is the no-op above. **The doctrine has a hole the size of the install base.** This T3 closes it.

### 1.3 It was specified, accepted, and shipped unbuilt

[[T3-cross-client-install]] §2 Layer 1.2 is unambiguous:

> Idempotent: create file → append block → **replace-between-markers on re-init**.

Its §5.1 verification bar: *"Re-run is idempotent — **block replaced not duplicated**, JSON sibling keys preserved."*

Per the event log that entity is `closed` — `entity.accepted` (2026-07-23) → `entity.progressed` → `verification.tested` → `entity.completed`. (Its file frontmatter still reads `status: draft`; the log is the source of truth and the frontmatter is stale prose.) So this clause was **accepted and signed off as delivered**. It was never built. Two mechanical reasons:

1. **There is no closing marker.** `apv-init.sh:539` defines only `APV_MD_MARKER="<!-- apv:orientation -->"`; the writer emits it at the top of the block and nothing at the bottom. "Replace between markers" was never implementable as written — there is no *between*.
2. **The test asserts the wrong half.** `tests/init/run-init-sandbox.sh:148-155`:

   ```bash
   # --- Case 5: CLAUDE.md acceptance ---
   run bash "$INIT" --accept-claude-md
   check "block appended"            grep -qF "<!-- apv:orientation -->" CLAUDE.md
   run bash "$INIT" --accept-claude-md
   check "second accept is a no-op"  [ "$(grep -cF 'apv:orientation' CLAUDE.md)" -eq 1 ]
   ```

   It checks *not duplicated* (count == 1) and never *replaced* (content). It then names the defect — "second accept is a no-op" — as the expected result. A gap enshrined as a passing assertion is the hardest kind to notice, which is why it survived an acceptance ceremony.

### 1.4 The consent ruling does not cover this

`M4 §7 Q4` (2026-06-10, cited at `apv-init.sh:537`) ruled: offer only; init is the offer's only trigger; writing requires explicit acceptance. That ruling is **sound and stays**. But it governs the **first write** — do not scribble in a user's `CLAUDE.md` unasked. It says nothing about *refreshing a block the user already accepted*.

Treating "already present" as "hands off forever" is not respect for consent; it is the preservation of a stale artefact under cover of a ruling about a different moment. The user consented to *this block*, meaning the orientation APV vouches for — not to the specific sentence APV happened to emit in June.

## 2. How (by reference)

- **Prior art exists in the sibling plugin — copy it.** `exfu-agent-planning-and-delegating`'s `skills/exfu-planning-init/references/apply-project-config.py` already implements the target contract for that plugin's config: deep-merge only owned keys, preserve everything unrecognised, **compare-before-write** (`if raw == desired: return 0`) so a re-run performs zero writes, atomic `tempfile` + `os.replace`, mode preservation, and fail-closed (exit 2, nothing written) on unparseable input. That plugin's own CLAUDE.md block also carries **both** an opening and a closing marker (`<!-- exfu-…:orientation -->` / `<!-- /exfu-…:orientation -->`). Same operator, same fortnight, correct pattern. APV should not invent a second one.
- **Code/data split is absolute** ([[T3-cross-client-install]] §2, M4 §2.1): the block is *data* in the attached repo; the canonical text stays in the toolchain. Healing is the toolchain reasserting its own text over its own managed region — never touching a byte outside the markers.
- **Grounding is asserted, never gated** (`exfu-planning-methodology`): healing corrects the assertion. It does not add enforcement, and nothing in core tooling starts hard-refusing on a stale block.
- **Never clobber what we do not recognise** ([[T3-cross-client-install]] §8 Q2 ruling). The managed region is bounded by markers; prose outside them is the user's and is preserved byte-for-byte — including a **sibling plugin's block sitting immediately adjacent** (§3.2 hazard).
- **Detect separately from write** ([[T3-cross-client-install]] §3 Layer 3 "verify + whinge"): drift detection can live in the SessionStart hook, which fires every session; writing stays with init, which fires on operator command. Same split already used for version currency.

## 3. What

### 3.1 Emit a closing marker

`scripts/apv-init.sh:539` gains a companion, and `claude_md_block()` (`:540-575`) emits it as the block's final line:

```sh
APV_MD_MARKER="<!-- apv:orientation -->"
APV_MD_END_MARKER="<!-- /apv:orientation -->"
```

From then on the managed region is well defined and every subsequent write is a bounded replace.

### 3.2 Heal legacy (markerless) blocks — the load-bearing sub-problem

**Every block in existence today is markerless.** A naive replace-between-markers implementation finds no end delimiter and silently keeps no-opping on exactly the repos that need healing — i.e. all of them. Confirmed on every attached repo known on this machine (verified 2026-08-10):

| Repo | Block | Markers | Pre-rename glob |
|---|---|---|---|
| `agent-plan-tracker` (this repo, dogfood) | `CLAUDE.md:49` | opening only | no — hand-corrected |
| `exfu-agent-planning-and-delegating` (consumer, `main`) | `CLAUDE.md:1` | opening only | **yes**, `:16` |
| `ExFu/agent-library` (consumer) | `CLAUDE.md:51` | opening only | **yes**, `:65` |

The third repo was missed by the original field report: the install base is larger than the two repos the reporting session could see, which is the §1.2 argument in miniature — nothing in this toolchain can enumerate attached repos, so any count here is a floor, not a total.

So the writer needs a one-time legacy path: **opening marker present, closing marker absent ⇒ treat as legacy; determine the end by scan, replace the whole region, and emit both markers so it never happens again.**

End-detection rule (must be conservative — it is deleting lines):

1. Scan forward from the opening marker.
2. Stop at the **first** of: another HTML comment marker line (`<!--`), a `## ` heading that is not the block's own `## agent-plan-visualiser (APV) tracking`, or EOF.
3. Trim trailing blank lines from the captured region; they belong to the document, not the block.

**Hazard, from a real file.** In the `exfu-agent-planning-and-delegating` repo the APV block is immediately followed by a sibling plugin's block:

```
  1  <!-- apv:orientation -->
 ...  (APV block, no closing marker)
 34  <!-- exfu-agent-planning-and-delegating:orientation -->
 ...
 56  <!-- /exfu-agent-planning-and-delegating:orientation -->
```

Rule 2's "stop at the next `<!--`" is what prevents swallowing lines 34-56. This case is not theoretical and **must** be a test fixture (§5.3).

If end-detection cannot resolve unambiguously, **refuse and report** — print the region it would have replaced and tell the operator to resolve by hand. Never guess destructively. (Consistent with the installers' foreign-hook contract: refuse loudly, continue with other components, exit non-zero.)

### 3.3 Replace on re-init, compare-before-write

Rewrite `apv-init.sh:576-590` from presence-check to content-check:

| State | Action | Report |
|---|---|---|
| No `CLAUDE.md`, or no marker | offer; write only under `--accept-claude-md` (**M4 §7 Q4 unchanged**) | `offered` / `created` |
| Both markers, content **identical** to canonical | nothing — zero writes | `ok … block current` |
| Both markers, content **differs** | replace between markers (**Q1: no flag needed**) | `updated … block refreshed` |
| Opening marker, **no** closing marker (legacy), `--accept-claude-md` given | §3.2 end-detection, replace, emit both markers | `updated … block migrated to delimited form` |
| Opening marker, **no** closing marker (legacy), flag **absent** | print the region that would be replaced; write nothing (**Q1 exception**) | `offered … legacy block, migration needs --accept-claude-md` |
| End-detection ambiguous | refuse, print region, `FAIL=1` | `REFUSED` |

Writes are atomic (temp + `os.replace` semantics) and preserve file mode, per §2's prior art.

### 3.4 Report drift every session — WITHDRAWN (Q3, split to a follow-on T3)

*Retained for the follow-on plan's benefit; not built here.*

`hooks/session-orient.sh` already reads `.apv-config.toml` `[requires].apv_min_version` and compares it to the running plugin's manifest. Extend it to compare the in-repo block against the running toolchain's canonical text and emit one line when they differ:

```
apv: CLAUDE.md orientation block is stale (stamped by an older toolchain) — run /apv-init to refresh.
```

Detection only; the hook never writes. This turns a silent multi-week drift into a visible one-line nag from the first session after an upgrade.

## 4. Scope

### In scope
- Closing marker + both markers emitted by `claude_md_block()`.
- Legacy end-detection and one-time migration, with a refuse-on-ambiguity path.
- Content-compare + bounded replace in `apv-init.sh` §6; atomic write; mode preservation.
- New/extended cases in `tests/init/run-init-sandbox.sh`.
- The fallback glob correction inside the block, per **Q5** — `cache/*/*agent-plan-visualiser/*/`.

### Out of scope
- **Changing the block's content**, with the single Q5 exception above. This plan is about the *mechanism*; whatever else `claude_md_block()` says on the day it lands is what gets stamped. (The pending `claude-marketplace` → `exfu-marketplace` correction rides along for free once healing works.)
- **The `session-orient.sh` drift line (§3.4)** — withdrawn per Q3; follow-on T3.
- The `M4 §7 Q4` consent ruling for **first** write — unchanged, still `--accept-claude-md`.
- Any change to capture/merge/gate procedure, the ontology, or `schema_version`.
- Healing any file other than `CLAUDE.md`, or any region outside the markers.
- Retrofitting attached repos automatically. Healing happens when an operator runs `/apv-init`; APV does not go hunting for repos.
- Extending `audit-rename.sh` to consumer repos (it cannot see them; §1.2 is motivation, not scope).

## 5. Verification

Harness: `bash agent-plan-visualiser/tests/init/run-init-sandbox.sh` — must be ALL PASS throughout.

1. **Fresh repo, first write** — no `CLAUDE.md`; `/apv-init` reports `offered` and writes nothing; with `--accept-claude-md` the block appears with **both** markers. (Extends Case 5.)
2. **Idempotent re-run** — second `--accept-claude-md` on an already-current block performs **zero writes**. Assert on file mtime or content hash, not just `grep -c` — the existing count==1 assertion is precisely what let the defect through (§1.3), so replace it, do not merely add to it.
3. **Adjacent sibling block preserved** — fixture reproducing the real layout in §3.2 (legacy APV block immediately followed by a fully delimited foreign block). After healing: APV block refreshed, foreign block byte-identical, ordering unchanged.
4. **Legacy migration** — fixture with an opening-marker-only block containing the pre-rename glob `cache/*/agent-plan-visualiser/*/`. After `/apv-init`: exactly one opening and one closing marker, the pre-rename glob is **gone**, and the emitted glob is present *as a literal string named in the assertion* — not "the canonical glob", which is what Q5 is about. Whichever literal Q5 rules for, the assertion pins it, so the next identity change fails this test loudly instead of silently restamping a dead path.
5. **Stale-content refresh** — fixture with delimited markers but altered body; healed to canonical; `grep -c` of each marker == 1.
6. **User prose preserved** — text above and below the block (including another `## ` heading) survives byte-for-byte.
7. **Ambiguity refused** — fixture where end-detection cannot resolve; init exits non-zero, prints the candidate region, and **modifies nothing**.
8. **Real-repo leg** — run against all three repos in the §3.2 table: this repo (`CLAUDE.md:49`), `exfu-agent-planning-and-delegating` (`main`, `CLAUDE.md:1`), and `ExFu/agent-library` (`CLAUDE.md:51`). All three migrate to delimited form; each diff contains only the block; the two adjacent sibling-plugin blocks survive byte-identical.
9. **Rename audit still green** — `bash agent-plan-visualiser/tests/audit-rename.sh` passes; the new canonical text introduces no pre-rename references.
10. **Full battery** — `bash agent-plan-visualiser/scripts/repack-validate.sh` and `bash agent-plan-visualiser/tests/dist/run-dist-sandbox.sh` still ALL PASS.

## 6. Dependencies

- [[T3-cross-client-install]] — *closed*; this completes its §2 Layer 1.2 clause. Its §5.1 bar is the acceptance criterion this plan finally satisfies. **Do not reopen it** — closed-entity doctrine says a follow-on defect spawns a new T3 (this one).
- [[T3-project-init-flow]] — *closed*; owns `apv-init.sh` §6 and the `M4 §7 Q4` offer semantics this preserves.
- [[T3-session-orientation]] — *closed*; owns `hooks/session-orient.sh`, extended only if §3.4 is kept in scope.
- [[T3-distribution]] — *live*; owns the marketplace rename that exposed the gap and the pending `exfu-marketplace` URL correction.
- **External (informational, not blocking)**: the consumer-side repair that produced this report is `575cac7` in `exfu-agent-planning-and-delegating` — `fix(apv-wiring): repair APV wiring left stale by the marketplace rename` — hand-editing what healing should have done. **Correction to the original report: it has *not* landed on that repo's `main`.** It sits on `claude/exfu-marketplace-refactor-impact-7c8b17`; `main`'s `CLAUDE.md:16` still carries the pre-rename glob, which is why the §3.2 table now records that repo as unhealed. That repo needs nothing from this plan; it is the field evidence, and it is still bleeding.

## 7. Open questions (HITL)

- **Q1 — consent on refresh.** Does refreshing an already-accepted block require `--accept-claude-md` again, or is init's own invocation sufficient consent? *Lean: sufficient.* The user accepted the managed region; refresh reasserts the toolchain's text inside a boundary they already granted, and requiring a flag reproduces today's failure (nobody passes it, drift persists). Report the change loudly and show a diff. **The legacy migration in §3.2 is the exception** — it deletes lines whose extent was inferred, so it should require explicit acceptance on first encounter.
- **Q2 — version stamping in the marker.** Stamp the emitting version (`<!-- apv:orientation v0.7.2 -->`) for cheap staleness detection? *Lean: no.* The marker must stay grep-stable for legacy detection, and a content compare is exact where a version compare is a proxy. Revisit only if §3.4's per-session compare proves too slow.
- **Q3 — §3.4 in or out.** Ship the session-orient drift line with this T3, or split it? *Lean: split* if it needs new sandbox scaffolding; the writer fix is the load-bearing half and should not wait.
- **Q4 — blocks a user has deliberately edited.** If someone hand-tuned the text inside the markers, healing silently reverts it. Detect and refuse, or overwrite as policy? *Lean: overwrite*, documented — the managed region is APV's by construction, and §6's real case is a repo where the hand-edit was itself an emergency repair of APV's staleness. Q1's diff output makes it visible.
- **Q5 — the emitted glob is itself less rename-robust than the hooks (added on review, 2026-08-10).** §1.1 diagnoses the pre-rename failure as a missing leading `*` on the package segment, and the four toolchain surfaces that resolve the plugin from cache all use the survivable form:

  ```
  hooks/capture-guard.sh:59, gate-prepush.sh:48, gate-refupdate.sh:52, extract-capture.sh:79
    plugins/cache/*/*agent-plan-visualiser/*/
  ```

  But the text healing would stamp (`apv-init.sh:568`) is `cache/*/exfu-agent-plan-visualiser/*/` — hard-coded prefix, no leading `*`. Correct today; dead on the next identity change, which is the exact drift class this plan exists to end. As written, §4 freezes block content, so healing would faithfully propagate the *less* robust of the two forms to the whole install base. *Lean: align the block with the hooks* (`cache/*/*agent-plan-visualiser/*/`) as a one-line carve-out from §4, on the grounds that the recovery path of last resort should be at least as durable as the machinery it recovers. Counter-argument worth hearing: a leading `*` also matches any third-party package whose name merely ends in `agent-plan-visualiser`, and `sort -V | tail -1` would then pick it — the hooks already accept that risk, so this is a question of whether to accept it uniformly or tighten all five surfaces instead. **Resolve before implementation; it changes what the migration writes.**

## 8. Rulings (2026-08-10, operator acceptance ceremony)

Entity accepted; implementation authorised. §7's five questions resolved:

- **Q1 (consent on refresh)** — resolved: **init's own invocation is sufficient consent to refresh a delimited block.** Plain `/apv-init` replaces a stale managed region and reports the change; `--accept-claude-md` is no longer required once the user has accepted the block once. **The legacy migration is the exception** — an opening-marker-only block has no declared extent, so healing it deletes lines the toolchain *inferred*. That path requires `--accept-claude-md` on first encounter, and until it is given, init reports the region it would replace and writes nothing. M4 §7 Q4 stands unchanged for the **first** write into a repo with no block at all.
- **Q2 (version stamping)** — resolved as the lean: **no version in the marker.** The marker stays grep-stable; staleness is decided by exact content compare, not a proxy.
- **Q3 (§3.4 session-orient drift line)** — resolved as the lean: **split.** The writer fix lands alone. §3.4 is withdrawn from this plan's scope and becomes a follow-on T3 if the drift nag is still wanted once healing exists.
- **Q4 (deliberately hand-edited blocks)** — resolved as the lean: **overwrite, documented.** The managed region is APV's by construction. Q1's reporting makes the change visible, and the real-world case that prompted the question was itself an emergency repair of APV's own staleness — exactly what healing removes the need for.
- **Q5 (which glob to stamp)** — resolved: **align the block with the hooks — `plugins/cache/*/*agent-plan-visualiser/*/`.** The recovery path of last resort must be at least as rename-durable as the machinery it recovers, and a single wildcard is the difference between healing the install base once and re-healing it after every identity change. The third-party-suffix collision this admits is one the four hook surfaces already accept; accepting it uniformly is better than a fifth surface that diverges. §4's content freeze is amended accordingly — this one string is in scope.

## 9. Handoff / capture contract

This document was authored from the consumer side and is **deliberately uncaptured** — no event for `T3-claude-md-block-healing` exists in `.agent-plan-tracker/events.jsonl`. Capture belongs to the session that does the work here, whose seal must match its own commit. For the picking-up agent:

1. Read `exfu-agent-plan-visualiser:apv-capture` and follow it; do not improvise from this list.
2. First block: `entity.created` (`entity_type: plan`, `entity_id: T3-claude-md-block-healing`, attributes = this frontmatter + a summary) **immediately followed by** `relationship.spawns` with `from_entity_id: T2-packaging` (both parents verified `live` at authoring time: `T2-packaging`, `M4-fresh-install`).
3. The entity lands in `draft`. **The draft gate applies** — no `entity.progressed` or `entity.completed` until the operator accepts (`entity.accepted`, actor = the operator). Do not self-accept. Resolve §7's five questions in that ceremony and record them as a `## Rulings` section, per the house pattern in [[T3-cross-client-install]] §8. **Q5 is load-bearing** — it decides the literal string the migration stamps into every attached repo, so it cannot be deferred past acceptance.
4. `entity.extended` is valid on a draft — refining this document before acceptance is authoring, not implementation.
