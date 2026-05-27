#!/usr/bin/env python3
"""Read .agent-plan-tracker/projection.json -> emit summary.md."""
import json
from collections import defaultdict
from pathlib import Path

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
    lines.append(
        f"**Total events:** {stats['total_events']}  ·  "
        f"**Live:** {stats['live_count']}  ·  "
        f"**Dormant:** {stats['dormant_count']}  ·  "
        f"**Dead:** {stats['dead_count']}  ·  "
        f"**Orphaned:** {stats['orphaned_count']}"
    )
    lines.append("")

    # Live work
    lines.append("## Live work")
    lines.append("")
    live = [e for e in entities.values() if e["derived_state"] == "live"]

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
                by_t2["(plan: other)"].append(e)
        else:
            by_t2[f"(non-plan: {e['entity_type']})"].append(e)

    lines.append("### By thematic parent")
    lines.append("")
    for t2 in sorted(by_t2.keys()):
        lines.append(f"- **{t2}**")
        for e in sorted(by_t2[t2], key=lambda x: x["entity_id"]):
            seq = e["event_type_sequence"]
            tail = " → ".join(seq[-3:])
            lines.append(f"  - `{e['entity_id']}` ({len(seq)} events): {tail}")
        lines.append("")

    by_milestone = defaultdict(list)
    for e in live:
        if e["entity_type"] == "plan":
            m = e["attributes"].get("milestone")
            if m:
                by_milestone[m].append(e)
            elif e["attributes"].get("plan_kind") == "milestone":
                by_milestone[f"(self: {e['entity_id']})"].append(e)

    if by_milestone:
        lines.append("### By milestone")
        lines.append("")
        for m in sorted(by_milestone.keys()):
            lines.append(f"- **{m}**")
            for e in sorted(by_milestone[m], key=lambda x: x["entity_id"]):
                lines.append(f"  - `{e['entity_id']}`")
            lines.append("")

    # Blocked
    blocked = [e for e in entities.values() if e["entity_type"] == "blocker" and e["derived_state"] == "live"]
    lines.append("## Blocked")
    lines.append("")
    if not blocked:
        lines.append("_No open blockers._")
    else:
        for e in blocked:
            lines.append(f"- `{e['entity_id']}`")
    lines.append("")

    # Orphaned
    lines.append("## Orphaned")
    lines.append("")
    orphans = [e for e in entities.values() if e["derived_state"] == "orphaned"]
    if not orphans:
        lines.append("_No orphaned entities._")
    else:
        for e in orphans:
            lines.append(f"- `{e['entity_id']}`")
    lines.append("")

    # Recently closed
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

    # Notable patterns
    lines.append("## Notable patterns")
    lines.append("")
    flaps = [
        e for e in entities.values()
        if "entity.reopened" in e["event_type_sequence"]
        and "entity.completed" in e["event_type_sequence"]
    ]
    if flaps:
        lines.append("**Flapping closures** (completed then reopened):")
        for e in flaps:
            lines.append(f"- `{e['entity_id']}`")
    else:
        lines.append("_No flapping closures._")
    lines.append("")

    # Milestone progress
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
    lines.append(
        f"_{len(entities)} entities · {len(relationships)} relationships · "
        f"{len(decisions)} decisions._"
    )

    OUT.write_text("\n".join(lines))
    print(f"summary emitted: {OUT}")


if __name__ == "__main__":
    main()
