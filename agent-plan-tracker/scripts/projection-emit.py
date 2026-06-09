#!/usr/bin/env python3
"""Emit .agent-plan-tracker/projection.json from cache.sqlite."""
import datetime
import json
import re
import sqlite3
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
CACHE = REPO_ROOT / ".agent-plan-tracker/cache.sqlite"
OUT = REPO_ROOT / ".agent-plan-tracker/projection.json"

SCHEMA_VERSION = "0.3.0"
ONTOLOGY_VERSION = "0.3.0"


def compute_milestone_progress(entities, relationships):
    """Aggregate per-milestone Tier-3 counts from the cache relationship fold.

    Milestone membership is read from the cache `relationships` (milestone
    `spawns` Tier-3 edges), NOT from a live read of planning/*.md frontmatter.
    cache-build already materialises those edges as the event-sourced single
    source of truth: the `entity.created` frontmatter snapshot *seeds* the edge
    and each `relationship.reattached` event *rewrites* it last-write-wins
    (see T3-milestone-parent-ontology D3). Reading them here collapses the last
    independent membership source — so editing a plan's `milestone:` field alone
    no longer moves it in milestone_progress; a relationship.reattached event is
    required. Frontmatter-vs-event drift becomes possible-but-detectable and is
    flagged by the M3 drift audit. See T3-event-sourced-relationships (M1.2) D-C
    / T1 §5 Q9.

    Semantics preserved from the prior file-glob implementation: only main-spine
    Tier-3 plans (id `T3-*`) are counted; status is joined from the cache
    entities (event-derived `derived_state`).
    """
    progress = {}
    for rel in relationships:
        if rel["type"] != "spawns":
            continue
        # milestone (plan:M<digit>...) spawns a main-spine Tier-3 plan (plan:T3-...)
        mid = rel["from"].split(":", 1)[1]
        if not re.match(r"^M[0-9]", mid):  # excludes prefixed plans like MT2-*
            continue
        cid = rel["to"].split(":", 1)[1]
        if not cid.startswith("T3-"):
            continue
        slot = progress.setdefault(mid, {
            "scheduled_t3_count": 0,
            "completed_t3_count": 0,
            "live_t3_count": 0,
        })
        slot["scheduled_t3_count"] += 1
        ent = entities.get(rel["to"])
        if ent:
            if ent["derived_state"] == "live":
                slot["live_t3_count"] += 1
            elif ent["derived_state"] == "closed":
                slot["completed_t3_count"] += 1
    return progress


def main():
    conn = sqlite3.connect(CACHE)
    conn.row_factory = sqlite3.Row

    entities = {}
    for row in conn.execute("SELECT * FROM entities"):
        key = f"{row['entity_type']}:{row['entity_id']}"
        entities[key] = {
            "entity_type": row["entity_type"],
            "entity_id": row["entity_id"],
            "derived_state": row["derived_state"],
            "event_type_sequence": json.loads(row["event_type_sequence"]),
            "attributes": json.loads(row["attributes"] or "{}"),
        }

    relationships = []
    for row in conn.execute("SELECT * FROM relationships"):
        relationships.append({
            "from": f"{row['from_entity_type']}:{row['from_entity_id']}",
            "to": f"{row['to_entity_type']}:{row['to_entity_id']}",
            "type": row["relationship_type"],
            "source": row["source"],                    # 'event' | 'frontmatter'
            "source_event_id": row["source_event_id"],  # null for frontmatter-derived
        })

    decisions = []
    for row in conn.execute("SELECT * FROM decisions"):
        decisions.append({
            "event_id": row["decision_event_id"],
            "text": row["text"],
            "explains_arcs": json.loads(row["referenced_event_ids"]),
        })

    # Latest-valid-summary per entity (T2-analyser §3.6, Phase B).
    # Sort by rowid (insertion order = events.jsonl line order) so iteration is chronological.
    # Rules:
    #   - primary always beats derived (regardless of recency)
    #   - within same source, later wins
    latest_summary_by_entity = {}
    for row in conn.execute(
        "SELECT * FROM summaries WHERE valid = 1 ORDER BY line_no ASC"
    ):
        key = f"{row['entity_type']}:{row['entity_id']}"
        prev = latest_summary_by_entity.get(key)
        keep = True
        if prev is not None:
            if prev["source"] == "primary" and row["source"] == "derived":
                # derived never displaces primary
                keep = False
            elif prev["source"] == "derived" and row["source"] == "primary":
                # primary always displaces derived
                keep = True
            else:
                # same source: later wins (we're iterating ascending)
                keep = True
        if keep:
            latest_summary_by_entity[key] = {
                "event_id": row["event_id"],
                "source": row["source"],
                "model": row["model"],
                "freeform_path": row["freeform_path"],
                "structured": json.loads(row["structured"]),
                "supersedes_summary_event_id": row["supersedes_summary_event_id"],
                "origin_summary_event_id": row["origin_summary_event_id"],
            }

    # All summaries keyed by event_id (Phase C — flow-view rendering needs
    # per-event metadata to render each summary as a distinct node, plus
    # the `valid` flag to apply strike-through to invalidated summaries).
    # Includes both valid and invalid entries — the renderer decides.
    summaries = {}
    for row in conn.execute("SELECT * FROM summaries ORDER BY line_no ASC"):
        summaries[row["event_id"]] = {
            "event_id": row["event_id"],
            "entity_type": row["entity_type"],
            "entity_id": row["entity_id"],
            "source": row["source"],
            "model": row["model"],
            "freeform_path": row["freeform_path"],
            "structured": json.loads(row["structured"]),
            "supersedes_summary_event_id": row["supersedes_summary_event_id"],
            "origin_summary_event_id": row["origin_summary_event_id"],
            "valid": bool(row["valid"]),
            "invalidated_by_event_id": row["invalidated_by_event_id"],
            "created_commit_recorded_event_id": row["created_commit_recorded_event_id"],
        }

    state_counts = {s: 0 for s in ("draft", "live", "dormant", "closed", "orphaned", "unknown")}
    for row in conn.execute("SELECT derived_state, count(*) c FROM entities GROUP BY derived_state"):
        state_counts[row["derived_state"]] = row["c"]
    total_events = conn.execute("SELECT count(*) FROM events").fetchone()[0]
    summary_stats = {
        "total_events": total_events,
        "draft_count": state_counts["draft"],
        "live_count": state_counts["live"],
        "dormant_count": state_counts["dormant"],
        "closed_count": state_counts["closed"],
        "orphaned_count": state_counts["orphaned"],
        "unknown_count": state_counts["unknown"],
    }
    milestone_progress = compute_milestone_progress(entities, relationships)

    projection = {
        "generated_at": datetime.datetime.now(tz=datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "schema_version": SCHEMA_VERSION,
        "ontology_version": ONTOLOGY_VERSION,
        "entities": entities,
        "relationships": relationships,
        "decisions": decisions,
        "summary_stats": summary_stats,
        "milestone_progress": milestone_progress,
        "latest_summary_by_entity": latest_summary_by_entity,
        "summaries": summaries,
    }

    tmp = OUT.with_suffix(".tmp")
    with open(tmp, "w") as f:
        json.dump(projection, f, separators=(",", ":"))
    tmp.replace(OUT)
    print(
        f"projection emitted: {len(entities)} entities, "
        f"{len(relationships)} relationships, {len(decisions)} decisions, "
        f"{summary_stats}"
    )
    conn.close()


if __name__ == "__main__":
    main()
