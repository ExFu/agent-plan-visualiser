---
id: T3-markdown-summary
plan_kind: thematic
tier: 3
t2_parent: T2-projection
milestone: M1-bootstrap
status: completed
---

# T3-markdown-summary — projection.json → summary.md

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Land `agent-plan-tracker/scripts/summary-emit.py` that reads `projection.json` and emits a human-readable `.agent-plan-tracker/summary.md` per T2-projection §3.3.

**Architecture:** Python stdlib. Reads projection.json; renders sections (Live work / Blocked / Orphaned / Recently closed / Notable patterns / Milestone progress) as markdown.

**Tech Stack:** Python 3 stdlib.

---

## 1. Why this T3

The HTML view (T3-html-view) is great for visual exploration; the markdown summary is great for session-start agent orientation. Agents read summary.md to answer "what's outstanding?" without re-parsing the entire event log or projection.

## 2. Out of scope

- Long-form mode (configurable verbosity) — defer to M3.
- Per-axis grouping options — default to both (theme + milestone).
- Customisable sections — fixed set for M1.

## 3. Acceptance criteria

- `agent-plan-tracker/scripts/summary-emit.py` exists, executable.
- Running it produces `.agent-plan-tracker/summary.md` with all expected sections.
- Live entities grouped by thematic parent (T2) AND by milestone (Mn) — two sub-sections under Live work.
- Sequence patterns flagged (any entity with `entity.completed` followed by `entity.reopened` is "flapping").
- Renders cleanly in any markdown viewer.

## 4. Steps

### Step 1: Write the emitter

**File:** `agent-plan-tracker/scripts/summary-emit.py`

```python
#!/usr/bin/env python3
"""Read .agent-plan-tracker/projection.json → emit summary.md."""
import json
from pathlib import Path
from collections import defaultdict

REPO_ROOT = Path(__file__).resolve().parents[2]
PROJECTION = REPO_ROOT / ".agent-plan-tracker/projection.json"
OUT = REPO_ROOT / ".agent-plan-tracker/summary.md"


def main():
    with open(PROJECTION) as f:
        p = json.load(f)

    entities = p["entities"]
    relationships = p["relationships"]
    decisions = p["decisions"]
    stats = p["summary_stats"]
    milestones = p["milestone_progress"]

    lines = []
    lines.append(f"# Project state — generated {p['generated_at']}")
    lines.append("")
    lines.append(f"**Total events:** {stats['total_events']}  ·  "
                 f"**Live:** {stats['live_count']}  ·  "
                 f"**Dormant:** {stats['dormant_count']}  ·  "
                 f"**Dead:** {stats['dead_count']}  ·  "
                 f"**Orphaned:** {stats['orphaned_count']}")
    lines.append("")

    # === Live work ===
    lines.append("## Live work")
    lines.append("")
    live = [e for e in entities.values() if e["derived_state"] == "live"]

    # Group by thematic parent (read t2_parent from attributes if present)
    by_t2 = defaultdict(list)
    for e in live:
        if e["entity_type"] == "plan":
            t2 = e["attributes"].get("t2_parent")
            tier = e["attributes"].get("tier")
            if t2:
                by_t2[t2].append(e)
            elif tier == 2:
                by_t2["(T2 itself)"].append(e)
            elif tier == 1:
                by_t2["(T1 itself)"].append(e)
            elif e["attributes"].get("plan_kind") == "milestone":
                by_t2["(milestone)"].append(e)
        else:
            by_t2[f"(non-plan: {e['entity_type']})"].append(e)

    lines.append("### By thematic parent")
    lines.append("")
    for t2 in sorted(by_t2.keys()):
        lines.append(f"- **{t2}**")
        for e in sorted(by_t2[t2], key=lambda x: x["entity_id"]):
            seq = e["event_type_sequence"]
            lines.append(f"  - `{e['entity_id']}` ({len(seq)} events): {' → '.join(seq[-3:])}")
        lines.append("")

    # Group by milestone
    by_milestone = defaultdict(list)
    for e in live:
        if e["entity_type"] == "plan":
            m = e["attributes"].get("milestone")
            if m:
                by_milestone[m].append(e)
            elif e["attributes"].get("plan_kind") == "milestone":
                # Milestone itself
                by_milestone[f"(self: {e['entity_id']})"].append(e)

    if by_milestone:
        lines.append("### By milestone")
        lines.append("")
        for m in sorted(by_milestone.keys()):
            lines.append(f"- **{m}**")
            for e in sorted(by_milestone[m], key=lambda x: x["entity_id"]):
                lines.append(f"  - `{e['entity_id']}`")
            lines.append("")

    # === Blocked ===
    blocked = [e for e in entities.values() if e["entity_type"] == "blocker" and e["derived_state"] == "live"]
    lines.append("## Blocked")
    lines.append("")
    if not blocked:
        lines.append("_No open blockers._")
    else:
        for e in blocked:
            lines.append(f"- `{e['entity_id']}`")
    lines.append("")

    # === Orphaned ===
    lines.append("## Orphaned")
    lines.append("")
    orphans = [e for e in entities.values() if e["derived_state"] == "orphaned"]
    if not orphans:
        lines.append("_No orphaned entities._")
    else:
        for e in orphans:
            lines.append(f"- `{e['entity_id']}`")
    lines.append("")

    # === Recently closed ===
    lines.append("## Recently closed (current dead state)")
    lines.append("")
    dead = sorted(
        [e for e in entities.values() if e["derived_state"] == "dead"],
        key=lambda x: x["entity_id"],
    )
    if not dead:
        lines.append("_None._")
    else:
        for e in dead[:10]:
            lines.append(f"- `{e['entity_id']}` ({e['entity_type']})")
    lines.append("")

    # === Notable patterns ===
    lines.append("## Notable patterns")
    lines.append("")
    flaps = [e for e in entities.values()
             if "entity.reopened" in e["event_type_sequence"]
             and "entity.completed" in e["event_type_sequence"]]
    if flaps:
        lines.append("**Flapping closures** (completed then reopened):")
        for e in flaps:
            lines.append(f"- `{e['entity_id']}`")
    else:
        lines.append("_No flapping closures._")
    lines.append("")

    # === Milestone progress ===
    lines.append("## Milestone progress")
    lines.append("")
    if not milestones:
        lines.append("_No milestone progress tracked._")
    else:
        for m, prog in sorted(milestones.items()):
            sched = prog["scheduled_t3_count"]
            done = prog["completed_t3_count"]
            live_c = prog["live_t3_count"]
            pct = (100 * done // sched) if sched else 0
            lines.append(f"- **{m}**: {done}/{sched} T3 complete ({pct}%); {live_c} live")
    lines.append("")

    lines.append("---")
    lines.append(f"_{len(entities)} entities · {len(relationships)} relationships · {len(decisions)} decisions._")

    OUT.write_text("\n".join(lines))
    print(f"summary emitted: {OUT}")


if __name__ == "__main__":
    main()
```

Make executable:
```bash
chmod +x agent-plan-tracker/scripts/summary-emit.py
```

### Step 2: Run

```bash
python3 agent-plan-tracker/scripts/summary-emit.py
```
Expected: `summary emitted: .agent-plan-tracker/summary.md`.

### Step 3: Inspect output

```bash
head -50 .agent-plan-tracker/summary.md
```
Expected: well-formed markdown with all expected sections + non-empty live work.

### Step 4: Commit

```bash
git add agent-plan-tracker/scripts/summary-emit.py .agent-plan-tracker/summary.md
```

Commit message: `[M1] T3-markdown-summary complete — summary.md generated from projection.json`

## 5. Files to create / modify

- **Create:** `agent-plan-tracker/scripts/summary-emit.py`
- **Create:** `.agent-plan-tracker/summary.md`

## 6. Verification

- Script exits 0.
- summary.md exists and is non-empty.
- All six sections present (Live work / Blocked / Orphaned / Recently closed / Notable patterns / Milestone progress).
- Live entities grouped by both axes (theme + milestone).

## 7. HITL questions

- **Q1**: Default verbosity — short for M1. Long mode (full state dump) added later if useful.
- **Q2**: Sequence rendering — currently shows last-3 events; useful for compactness. Tweak if it obscures meaningful patterns.

## 8. Events this T3 will emit

- `entity.progressed` on T2-projection.
- `entity.completed` on T3-markdown-summary.
- `verification.tested` on T3-markdown-summary.
- `entity.progressed` on M1-bootstrap.
- `commit.recorded`.
