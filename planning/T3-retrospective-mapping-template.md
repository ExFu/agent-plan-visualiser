---
id: T3-retrospective-mapping-template
plan_kind: thematic
tier: 3
t2_parent: T2-ingest
milestone: M5-backfill
status: draft
---

# T3-retrospective-mapping-template — the translation brief, canonical

**Status**: Draft.
**Sits at**: T2-ingest theme, M5-backfill milestone. Wave 2, parallel to the other machinery T3s (nothing depends on it for the native case; the non-native case depends on it).

---

## 1. Why

For non-native projects the mapping note is the load-bearing artefact (T2-ingest §1): without it the extractor misclassifies or refuses. T2-ingest §3.3 sketched the structure; this T3 makes it canonical — a template a project owner can fill in an hour, and a wired brief the extractor actually consumes.

## 2. What

1. **The template** — `scripts/backfill/retrospective-mapping-template.md`: YAML frontmatter for the structured parts (paths, conventions, target schema), free-form markdown for narrative (T2-ingest §6 Q1 lean), covering the §3.2 checklist: plan-equivalents, decision artefacts, blocker conventions, HITL conventions, implicit-work expectation, **known pivots** (the recollected-Why seed — these feed the triage pass pre-armed).
2. **One worked example** — filled in for a realistic non-native shape (ADRs + docs/architecture + GitHub-issue blockers).
3. **Brief wiring** — [[T3-backfill-workflow]]'s prompt includes the note verbatim when present; pre-flight warns (not blocks) when absent on a non-native-looking target.
4. **Placement** — authored at `<data_dir>/retrospective-mapping.md`; archived to `<data_dir>/archive/` post-backfill (T2-ingest §3.4 step 5).

## 3. Scope

### In scope
- Template + worked example + prompt wiring + the pre-flight warning.

### Out of scope
- Agent-assisted generation (`T3-mapping-note-generator`, later candidate).
- T1 synthesis for planless projects (later candidate).

## 4. Verification

1. Template parses (frontmatter valid; checklist sections present).
2. Dry-run bundle against a fixture non-native repo shows the note in the extractor brief.
3. Absent-note pre-flight warns on the fixture, proceeds on confirmation.

## 5. Dependencies

- T3-backfill-workflow (consumes the brief).
- T2-ingest §3.2/§3.3 (the ratified checklist and sketch).

## 6. Open questions

1. Should "known pivots" entries carry enough structure (commit ref + candidate rationale) to land directly as triage-pass input? Lean: yes — same entry shape as the hypotheses file, so the human's up-front knowledge and the walk's inferences meet in one checklist.
