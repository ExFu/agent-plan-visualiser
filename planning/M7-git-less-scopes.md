---
id: M7-git-less-scopes
plan_kind: milestone
milestone_index: 7
status: active
---

# M7-git-less-scopes — APV is first-class on a synced folder with no git

**Status**: Accepted 2026-09-03 by the operator (authored 2026-09-03 from the therapist-tool work request, `planning/scratch/Work Request -- APV on synced folders -- 3 Sep 2026.md`, and the assessment filed beside it; revised twice pre-acceptance on the validator rule). Open questions carry stated leans, applied as working defaults until ruled otherwise.
**Sits at**: Seventh milestone on the sequence axis. Primary themes: T2-storage (where derived files live, how the project root is found) and T2-packaging (how a folder is attached). Follows M6-exfu-integration, which made APV the owner of its ExFu integration; this milestone makes the ExFu library's own storage shape a supported environment.

---

## 1. Why this milestone

APV was born for git repositories, and every T3 so far has assumed one: the project root is `git rev-parse --show-toplevel`, seals correspond to commits, and derived files sit beside the log because `.gitignore` or a commit absorbs them. T1-top-level §"Every event carries enough metadata to be interpreted without external systems" and T2-storage §1 ("bridges Git-aware and Git-less consumers") already promised the record would be readable without git. Running the *toolchain* without git was never promised, and the first real attempt showed the gap.

On 2026-09-02 the therapist-tool scope in the ExFu Library (a Dropbox-synced folder shared by two people and several agents, no git, no shared conversation) attached APV by hand and documented a "git-less mode" in its own `ontology/apv-tracking.md`: capture seals instead of commits, pinned dirs, manual conflicted-copy reconciliation. The first desktop run of the pipeline on 2026-09-03 stopped twice and had to be finished step by step by hand. The ExFu side has ruled that synced, git-less scopes will be the normal case for library scopes, not an exception; the Agent Library's own ontology (durable/ section) already forbids SQLite inside a synced root for the reasons this milestone addresses.

The consumer question M7 answers: **can two humans and their agents run APV on a shared folder without remembering a workaround?** Today the answer is no, for three reasons: the plan-frontmatter validator halts on the folder's descriptor file; SQLite is written into the synced tree, where some mounts cannot lock it and where two machines produce conflicted copies; and, unstated in the field report but the cause of its awkward setup, the toolchain resolves the project root to its own install directory when git is absent, so the folder's `.apv-config.toml` is never read.

## 2. The shaping decisions

### 2.1 Keep SQLite; move the derived files

The cache is derived, fully rebuilt on every run, and queried by SQL from four surfaces (audits, gate warn checks, the capture skill's draft-gate query, the ad-hoc trace scripts). Its location interacts with the mount and with sync; its format does not. Derived files leave the synced tree by default when the data dir is not inside a git work tree; git repos keep their current layout unchanged, including the dogfood repo's committed `cache.sqlite`. Replacing SQLite (JSON, DuckDB) was assessed and rejected: it rewrites every SQL surface and does nothing for concurrent writers.

### 2.2 The config file is the root marker when git is absent

`.apv-config.toml` lives at the project root by rule. When `git rev-parse` fails, the toolchain walks up from the working directory to the nearest `.apv-config.toml` and treats that directory as the root. The vendored-toolchain fallback stays last, for the dogfood layout. No environment exports are needed to run the pipeline from a git-less folder.

### 2.3 Git-less attach is explicit, never inferred (operator ruling 2026-09-03)

`apv init` outside a git work tree keeps refusing unless the operator passes `--no-git`. Auto-detection was considered and declined for now: attaching a folder to tracking is a deliberate act, and a folder that merely lacks `.git` (a fresh clone target, a scratch dir) must not be attached by accident. The refusal message names the flag.

### 2.4 Nothing about the record changes

`events.jsonl` handling, the schema, seal semantics, the gate's blocking checks and the manual conflicted-copy rule are untouched. `summary.md` stays in the synced folder so state is readable with nothing installed; `dashboard.html` stays where a scope's own builder puts it. Conflicted copies of those two remain possible and are accepted; this milestone reduces the noise, it does not remove it.

### 2.5 Report back to the scope, do not edit it

The therapist-tool scope's `ontology/apv-tracking.md` deviation 3 is rewritten by the scope's own agents from a dated addendum this milestone produces. APV never edits an adopting folder.

## 3. Definition of done

From a plain folder with no `.git`, holding `.apv-config.toml` (pinning `data_dir` and `planning_dir`), a planning dir that contains `agent.md` without frontmatter alongside valid plans, and an events log:

1. `apv init --no-git` attaches it idempotently; without the flag, init refuses and names the flag.
2. `bash "$APV/scripts/repack-validate.sh"` passes end to end from the folder root with **no** `APV_DATA_DIR`/`APV_PLANNING_DIR` exported and with **no** `sqlite3` CLI on `PATH`.
3. After the run the data dir holds nothing new except `summary.md`; `cache.sqlite`, its journal and `projection.json` are in a per-machine cache dir outside the folder, and the run prints where.
4. `python3 "$APV/scripts/gate-composite.py"` reads the folder's `[gate]` lists.
5. Every existing suite in the dogfood repo passes unchanged and `cache.sqlite` still lands in `.agent-plan-tracker/`.
6. The addendum for the scope's deviation 3 is written (in the runtime T3's build notes) and collapses the scope's step-3 commands to `cd <scope>; bash "$APV/scripts/repack-validate.sh"; python3 "$APV/scripts/gate-composite.py"`.

Closure is a human ceremony on that evidence.

## 4. Scheduled T3s (in sequence)

1. **T3-synced-folder-runtime** (T2-storage) — validator skip rule, config-file root finding, Python-run audits with the CLI dependency dropped, cache relocation with the journal warning, skill and README updates, the deviation-3 addendum. Delivers items 2 to 6.
2. **T3-git-less-init** (T2-packaging) — `apv init --no-git`, the git-less orientation block, and the Desktop toolchain-discovery rung. Delivers item 1. Depends on the resolver from the first T3.

## 5. Out of scope

- Auto-merging `events.jsonl` conflicted copies (human-visible by design; T2-storage §1 trust hierarchy).
- Any change to git-backed behaviour beyond reading the cache path through one function.
- ExFu Agent Library changes (a shipped `planning` folder-type descriptor, a `scope-setup` pointer): belong to the Agent Library repo once this milestone lands; noted in the assessment §7.
- Incremental cache rebuilds (T2-storage §5 "Later").

## 6. Open questions (HITL)

- **Q1 — the ExFu-side follow-ons.** Are the Agent Library follow-ons (planning folder-type template, scope-setup pointer) tracked as an inbox item here, or only in the Agent Library repo's own corpus? Lean: Agent Library only; this repo records the dependency direction in this section and nothing else.
