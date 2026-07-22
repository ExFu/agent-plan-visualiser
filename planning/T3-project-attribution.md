---
id: T3-project-attribution
plan_kind: thematic
tier: 3
t2_parent: T2-storage
milestone: M4-fresh-install
status: draft
---

# T3-project-attribution — creation-time sub-project attribution; extraction and skills brought to the model

**Status**: Authored 2026-07-22 from an operator ruling correcting the
attribution model (conversation, 2026-07-21/22). Draft pending acceptance.
**Sits at**: T2-storage theme (membership semantics — registry schema + fold
contract), M4-fresh-install milestone. Addendum to
[T3-multi-project](T3-multi-project.md).

## 1. Why

An audit of the automated surfaces against the shipped multi-project model
(0.5.15 registry + fold, 0.6.0 `project.assigned`) found the extraction
authors blind to it: `backfill.py` hardcodes `planning/` in its bundle
builder (sub-project plans invisible), both extraction prompts carry no
project vocabulary, and `/apv-merge`'s semantic pass cannot see a
membership contradiction (latest-recorded-wins would settle a genuine
dispute by block order).

Reviewing the fix, the operator ruled the shipped model itself wrong for
open entities: attribution is **not** derivation-plus-retrospective-
correction. In registry repos, entities acquire project attribution **at
creation, by location**; `project.assigned` is the corrective for closed
entities and the sanctioned primitive for any deliberate re-home.

## 2. The rulings (operator, 2026-07-21/22 — recorded as decisions at acceptance)

1. **Creation-time attribution.** "For projects with sub-projects, new
   entities DO need to be attributed to a project. Typically, based on
   their location in the folder structure." Retrospective assertion "is
   only true when trying to change a closed element's attribution."
2. **Owned-directory carve-outs.** "The metadata for projects probably
   also needs to include a list of directories that the sub-project owns…
   the sub-projects can be assessed on the basis of explicit carve-outs."
   `[projects.<name>]` gains `dirs = ["site/", …]`; `planning_dir` is
   implicitly owned.
3. **Named sub-projects only are stamped.** "ONLY stamp named
   sub-projects. That allows greater flexibility down the line for
   additional sub-projects to spawn and get carve-outs. And, it's
   transparently compatible with the no named sub-projects condition.
   Otherwise, for named sub-projects, stamp at creation as you suggest."
   The default project is never stamped explicitly.
4. **`unassigned` stays.** "By default leave unassigned entities as they
   are. The project owner and the project's agent can and should be
   responsible for deciding how those entities are 'moved' into the
   projects by attribution. When doing capture going forwards, the
   assignment should trigger if the files/planning in question are within
   the project's carved out locations." No-carve-out planless work is
   likewise left `unassigned`. The fold floor is unchanged; `unassigned`
   is the visible triage bucket.
5. **Mixed-ownership commits split.** "The capture should either split
   the entities so that each project has its own entity OR we need to
   support multiple projects for a single entity. That might get
   complicated though. So I think safer to have multiple entities." One
   planless entity per named sub-project touched; no multi-project
   entities.
6. **Default-project naming stays flexible.** "Make it flexible so users
   can name if they want or be lazy and default too." Satisfied by the
   existing rename rule (a registered project claiming the `[storage]`
   planning dir renames implicit `main`) — no second mechanism.

## 3. What

1. **Config** (`scripts/apvlib.py`): `apv_projects` accepts optional
   `dirs` (repo-relative prefixes; fail-loud on non-strings and exact
   duplicates across projects; nesting allowed, longest prefix wins). New
   `apv_owned_prefixes` (named sub-projects' `dirs` + `planning_dir`; the
   default project contributes nothing) and `named_owners(repo_root,
   paths)` (distinct named owners of the touched paths, `[]` without a
   registry). The minimal TOML fallback already parses string arrays.
2. **Fold** (`scripts/cache-build.py`): unchanged in behaviour — the
   shipped precedence (explicit `attributes.project` → planning-root
   ownership → `main`/`unassigned`) already honours stamps first.
   Docstring notes stamping is now the creation-time norm for named
   sub-project work; derivation is the legacy/main-root path.
3. **Extraction — the model's word is never trusted.** Both orchestrators
   gain a deterministic ownership computation and enforce it in
   `enforce()`: plan `entity.created` under a named project's planning
   root ⇒ stamp `attributes.project`; main-root plans stripped of any
   stamp. Planless creations: 0 named owners ⇒ strip; exactly 1 ⇒ stamp;
   ≥2 ⇒ the bundle advertises the owner map, the prompt instructs one
   entity per named sub-project (split ids suffix `.<project>`), and
   enforcement validates each stamp against the advertised set. Both
   prompts add `project.assigned` to never-emit (`FORBIDDEN_TYPES` names
   the error; the pinned pre-0.6.0 schemas already reject it
   structurally) and reword plans-location text to "any registered
   planning root". No schema pins move — attributes bags are open at
   every epoch.
4. **Backfill bundle fix**: `backfill.py` matches planning files against
   all resolved planning roots (was hardcoded `planning/`), and
   `looks_non_native()` scans every root. Single-project bundles stay
   bit-identical.
5. **Gate**: new **warn**-class `attribution-drift` — a plan whose latest
   stamped project disagrees with the planning root that currently owns
   its file (registry repos only; vacuous otherwise). Added to the init
   template's warn list.
6. **Skills + docs**: `/apv-capture` §3 gains the creation-time
   attribution rules (stamp named sub-projects, split mixed work, never
   stamp default, re-homes are `project.assigned` only — a later event's
   bare `attributes.project` is forbidden as a move channel);
   `/apv-merge` §3/§7 gain the competing-membership contradiction;
   orientation skill, cheatsheet, worked examples, backfill README,
   mapping templates, `apv-init` command doc, init config template
   (`# dirs = [...]` lines) and its CLAUDE.md block all reworded to the
   corrected model.

## 4. Out of scope

- Auto-migrating existing `unassigned` entities — operator-driven via the
  bulk `project.assigned` pattern (ruling 4).
- Multi-project entities (ruling 5 rejects them).
- `migrate-projects.py` — stays deferred per T3-multi-project.
- Any behaviour change for registry-less repos: every change is a no-op
  there (this dogfood repo included).

## 5. Verification

1. Gate tests: `dirs` parsing (tomllib + minimal parser), duplicate-dir
   fail-loud, `named_owners` longest-prefix cases, `attribution-drift`
   fixture; existing `fixture-project-move*` untouched and green.
2. Extractor sandbox: registry+dirs repo, planless commit under a
   carve-out ⇒ stamped `entity.created`; bogus model stamp stripped;
   no-registry cases byte-identical.
3. Backfill sandbox: multi-root dry-run bundle lists plans from both
   roots; stamping case; split case validating stamps ∈ advertised set.
4. Dogfood no-op: full refresh, `SELECT DISTINCT project FROM entities`
   → `main` only; gate green.
