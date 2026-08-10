#!/usr/bin/env python3
"""Read .agent-plan-tracker/projection.json -> emit summary.md.

Data dir defaults to .agent-plan-tracker/; override with APV_DATA_DIR (apvlib.apv_data_dir).
"""
import datetime
import json
import re
from collections import defaultdict
from pathlib import Path

import apvlib

REPO_ROOT = apvlib.repo_root()
DATA_DIR = apvlib.apv_data_dir(REPO_ROOT)
PROJECTION = DATA_DIR / "projection.json"
OUT = DATA_DIR / "summary.md"


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
        f"**Draft:** {stats['draft_count']}  ·  "
        f"**Live:** {stats['live_count']}  ·  "
        f"**Dormant:** {stats['dormant_count']}  ·  "
        f"**Closed:** {stats['closed_count']}  ·  "
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

    # Multi-project rollup (T3-multi-project): only when a registry is
    # configured (the projection carries top-level `projects` then) — a
    # single-project summary stays byte-identical. Tolerates older
    # projections without per-entity `project` (reads as main).
    if p.get("projects"):
        by_project = defaultdict(list)
        for e in live:
            by_project[e.get("project", "main")].append(e)
        lines.append("### By project")
        lines.append("")
        for name in p["projects"]:
            members = by_project.get(name, [])
            lines.append(f"- **{name}** ({len(members)} live)")
            for e in sorted(members, key=lambda x: x["entity_id"]):
                lines.append(f"  - `{e['entity_id']}`")
            lines.append("")

    # Awaiting operator — the attention queues (ceremonies + deferrals).
    # Tolerate an older projection.json without the block.
    attention = p.get("attention") or {}
    acc = attention.get("pending_acceptance") or []
    clo = attention.get("pending_closure") or []
    dfr = attention.get("deferred_verifications") or []
    lines.append("## Awaiting operator")
    lines.append("")
    if not (acc or clo or dfr):
        lines.append("_Nothing waiting on the operator._")
        lines.append("")
    else:
        if acc:
            lines.append("**Acceptance ceremonies pending** (draft plans — the draft gate blocks implementation against them):")
            for a in acc:
                since = f", {a['commits_since']} commit(s) ago" if a.get("commits_since") is not None else ""
                created = f"authored {a['created_date'][:10]}" if a.get("created_date") else "authoring date unknown"
                lines.append(f"- `{a['entity_id']}` ({created}{since})")
            lines.append("")
        if clo:
            lines.append("**Closure ceremonies pending** (all scheduled T3s closed; milestone still live):")
            for mid in clo:
                lines.append(f"- `{mid}`")
            lines.append("")
        if dfr:
            lines.append("**Deferred verifications** (operator legs to come back to):")
            for d in dfr:
                when = f" (deferred {d['deferred_date'][:10]})" if d.get("deferred_date") else ""
                reason = f": {d['reason']}" if d.get("reason") else ""
                lines.append(f"- `{d['entity_id']}`{when}{reason}")
            lines.append("")

    # Draft
    lines.append("## Draft")
    lines.append("")
    drafts = [e for e in entities.values() if e["derived_state"] == "draft"]
    if not drafts:
        lines.append("_No draft entities._")
    else:
        by_type = defaultdict(list)
        for e in drafts:
            by_type[e["entity_type"]].append(e)
        # Inbox ids embed their capture date (<YYYY-MM-DD>.<slug>) — surface
        # triage debt as age so "append-only capture surface" stays honest.
        gen_date = datetime.date.fromisoformat(p["generated_at"][:10])

        def age_note(eid):
            m = re.match(r"^(\d{4}-\d{2}-\d{2})\.", eid)
            if not m:
                return ""
            days = (gen_date - datetime.date.fromisoformat(m.group(1))).days
            return f" ({days}d untriaged)" if days > 0 else ""

        for et in sorted(by_type.keys()):
            lines.append(f"- **{et}**")
            for e in sorted(by_type[et], key=lambda x: x["entity_id"]):
                note = age_note(e["entity_id"]) if et == "inbox-item" else ""
                lines.append(f"  - `{e['entity_id']}`{note}")
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
    lines.append("## Recently closed")
    lines.append("")
    closed = sorted(
        [e for e in entities.values() if e["derived_state"] == "closed"],
        key=lambda x: x["entity_id"],
    )
    if not closed:
        lines.append("_None._")
    else:
        for e in closed[:10]:
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
