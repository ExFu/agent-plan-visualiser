#!/usr/bin/env python3
"""Build .agent-plan-tracker/cache.sqlite from .agent-plan-tracker/events.jsonl.

- Inserts raw events; applies state-machine to materialise entities/relationships/decisions/commits.
- Runs `git blame --line-porcelain` to populate commit_ref + denormalised commit_meta on events.
- Idempotent: wipes tables before rebuild.
"""
import datetime
import json
import sqlite3
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
EVENTS = REPO_ROOT / ".agent-plan-tracker/events.jsonl"
CACHE = REPO_ROOT / ".agent-plan-tracker/cache.sqlite"
SCHEMA_DDL = REPO_ROOT / "agent-plan-tracker/schemas/0.1.0/cache.schema.sql"

STATE_FROM_EVENT = {
    "entity.created": "live",
    "entity.extended": "live",
    "entity.renamed": "live",
    "entity.progressed": "live",
    "entity.completed": "dead",
    "entity.parked": "dormant",
    "entity.cancelled": "dead",
    "entity.superseded": "dead",
    "entity.reopened": "live",
}
RELATIONSHIP_TYPES = {
    "relationship.spawns": "spawns",
    "relationship.depends-on": "depends-on",
    "relationship.addendum-to": "addendum-to",
    "relationship.alongside": "alongside",
    "relationship.reattached": "reattached",
}


def load_events():
    events = []
    with open(EVENTS) as f:
        for line_no, raw in enumerate(f, start=1):
            ev = json.loads(raw)
            ev["_line_no"] = line_no
            events.append(ev)
    return events


def init_db(conn):
    # Drop any existing tables first so schema additions (new columns,
    # new indices) reliably take effect on rebuilds against a stale cache
    # file. `CREATE TABLE IF NOT EXISTS` would silently skip the schema
    # change and the index DDL would then reference a column that doesn't
    # exist on disk. Cache is fully derivable from events.jsonl, so the
    # nuke-and-rebuild cost is fine.
    for table in ("events", "entities", "relationships", "decisions", "commits"):
        conn.execute(f"DROP TABLE IF EXISTS {table}")
    with open(SCHEMA_DDL) as f:
        conn.executescript(f.read())


def resolve_blame():
    """Returns dict {line_no: (commit_ref, author, iso_date, summary)} or empty on error."""
    try:
        out = subprocess.check_output(
            ["git", "blame", "--line-porcelain", str(EVENTS)],
            cwd=REPO_ROOT,
            text=True,
        )
    except subprocess.CalledProcessError:
        return {}

    blame = {}
    cur_commit = cur_author = cur_date_epoch = cur_summary = None
    line_no = 0
    for raw in out.splitlines():
        if raw.startswith("\t"):
            line_no += 1
            iso_date = None
            if cur_date_epoch is not None:
                try:
                    iso_date = datetime.datetime.fromtimestamp(int(cur_date_epoch), tz=datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
                except (ValueError, TypeError):
                    iso_date = None
            blame[line_no] = (cur_commit, cur_author, iso_date, cur_summary)
        elif raw.startswith("author "):
            cur_author = raw[len("author "):]
        elif raw.startswith("author-time "):
            cur_date_epoch = raw[len("author-time "):]
        elif raw.startswith("summary "):
            cur_summary = raw[len("summary "):]
        else:
            parts = raw.split(" ")
            if len(parts) >= 3 and len(parts[0]) == 40 and all(c in "0123456789abcdef" for c in parts[0]):
                # All-zeros hash is git's sentinel for working-tree modifications
                # not yet committed. Render as 'pending' for human-friendly displays.
                cur_commit = "pending" if parts[0] == "0" * 40 else parts[0]
                cur_author = cur_date_epoch = cur_summary = None
    return blame


def main():
    events = load_events()
    conn = sqlite3.connect(CACHE)
    init_db(conn)
    blame = resolve_blame()

    # Build commit-boundaries lookup for positional rollup.
    # Each entry: (line_no_of_commit_recorded, commit.recorded event_id, attributes dict)
    commit_boundaries = [
        (ev["_line_no"], ev["event_id"], ev.get("attributes", {}))
        for ev in events
        if ev["type"] == "commit.recorded"
    ]

    def find_commit_for(line_no):
        """Positional rollup: return (commit_recorded_event_id, author, date, msg_first_line)
        for the FIRST commit.recorded event with line_no >= the given line. Trailing
        events with no closing commit.recorded return all None."""
        for b_line, b_event_id, b_attrs in commit_boundaries:
            if b_line >= line_no:
                return (b_event_id,
                        b_attrs.get("author"),
                        b_attrs.get("date"),
                        b_attrs.get("message_first_line"))
        return (None, None, None, None)

    for ev in events:
        line_no = ev["_line_no"]
        cref = blame.get(line_no, (None,))[0]  # commit_ref only — blame is unreliable post-rewrite for commit_meta
        cre_id, cauthor, cdate, csum = find_commit_for(line_no)
        conn.execute(
            """INSERT INTO events (event_id, type, entity_type, entity_id, actor, confidence,
                schema_version, attributes, line_no, commit_ref, commit_author, commit_date,
                commit_message_first_line, commit_recorded_event_id)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            (
                ev["event_id"], ev["type"], ev.get("entity_type"), ev.get("entity_id"),
                ev["actor"], ev["confidence"], ev["schema_version"],
                json.dumps(ev.get("attributes", {}), separators=(",", ":")),
                line_no, cref, cauthor, cdate, csum, cre_id,
            ),
        )

    # Materialise entities
    entities = {}
    for ev in events:
        et = ev.get("entity_type")
        eid = ev.get("entity_id")
        if not et or not eid:
            continue
        key = (et, eid)
        e = entities.setdefault(key, {
            "state": "unknown",
            "attrs": {},
            "last_event_id": "",
            "sequence": [],
        })
        e["sequence"].append(ev["type"])
        e["last_event_id"] = ev["event_id"]
        new_state = STATE_FROM_EVENT.get(ev["type"])
        if new_state:
            e["state"] = new_state
        if ev["type"] == "entity.created":
            e["attrs"] = ev.get("attributes", {})

    # Fallback: for plan entities with empty attrs (no entity.created event
    # in the log), read frontmatter directly from the plan file. The
    # methodology going forward says agents must emit entity.created for every
    # plan when first touched, but this masks legacy gaps. See inbox item:
    # 2026-05-27.agents-emit-entity-created-for-plans.
    try:
        import re as _re
        import yaml as _yaml
        for (et, eid), e in entities.items():
            if et != "plan" or e["attrs"]:
                continue
            plan_path = REPO_ROOT / "planning" / f"{eid}.md"
            if not plan_path.exists():
                continue
            content = plan_path.read_text()
            m = _re.match(r"^---\n(.*?)\n---\n", content, _re.DOTALL)
            if not m:
                continue
            try:
                fm = _yaml.safe_load(m.group(1))
                if isinstance(fm, dict):
                    e["attrs"] = fm
            except _yaml.YAMLError:
                pass
    except ImportError:
        # pyyaml not available; skip fallback. Cache still builds; routing may be poorer.
        pass

    for (et, eid), e in entities.items():
        conn.execute(
            """INSERT INTO entities (entity_type, entity_id, derived_state, attributes,
                last_event_id, event_type_sequence) VALUES (?,?,?,?,?,?)""",
            (
                et, eid, e["state"],
                json.dumps(e["attrs"], separators=(",", ":")),
                e["last_event_id"],
                json.dumps(e["sequence"], separators=(",", ":")),
            ),
        )

    # Materialise relationships — event-sourced edges first (source='event').
    for ev in events:
        rtype = RELATIONSHIP_TYPES.get(ev["type"])
        if not rtype:
            continue
        attrs = ev.get("attributes", {})
        from_type = attrs.get("from_entity_type", "plan")
        from_id = attrs.get("from_entity_id")
        if not from_id:
            continue
        conn.execute(
            """INSERT OR IGNORE INTO relationships (from_entity_type, from_entity_id,
                to_entity_type, to_entity_id, relationship_type, source_event_id, source)
                VALUES (?,?,?,?,?,?,?)""",
            (from_type, from_id, ev["entity_type"], ev["entity_id"], rtype, ev["event_id"], "event"),
        )

    # Frontmatter-derived edges (source='frontmatter').
    # The planning methodology declares hierarchy via frontmatter fields
    # (T3.t2_parent → T2; T3.milestone → Mn). These are equally first-class
    # edges, but they're metadata on the entity rather than events. Consumers
    # (HTML view, analyser, summary) shouldn't have to do a dual walk —
    # cache-build unifies both kinds into `relationships`, with a `source`
    # column distinguishing them. Event-sourced rows always win on PK collision
    # (INSERT OR IGNORE below; the event-sourced pass above already inserted).
    # See T2-storage.md §3.5 and inbox 2026-05-27.outstanding-work-analyser-endpoint
    # (superseded) for context.
    for (et, eid), e in entities.items():
        if et != "plan":
            continue
        a = e["attrs"] or {}
        # T3 → T2 parent
        t2p = a.get("t2_parent")
        if t2p:
            conn.execute(
                """INSERT OR IGNORE INTO relationships (from_entity_type, from_entity_id,
                    to_entity_type, to_entity_id, relationship_type, source_event_id, source)
                    VALUES (?,?,?,?,?,?,?)""",
                ("plan", t2p, "plan", eid, "spawns", None, "frontmatter"),
            )
        # T3 → milestone (and any plan tagged with a milestone)
        m = a.get("milestone")
        if m:
            conn.execute(
                """INSERT OR IGNORE INTO relationships (from_entity_type, from_entity_id,
                    to_entity_type, to_entity_id, relationship_type, source_event_id, source)
                    VALUES (?,?,?,?,?,?,?)""",
                ("plan", m, "plan", eid, "spawns", None, "frontmatter"),
            )

    # Materialise decisions
    for ev in events:
        if ev["type"] != "decision":
            continue
        attrs = ev.get("attributes", {})
        conn.execute(
            """INSERT OR REPLACE INTO decisions (decision_event_id, text, referenced_event_ids)
                VALUES (?,?,?)""",
            (
                ev["event_id"],
                attrs.get("text", ""),
                json.dumps(attrs.get("event_ids", [])),
            ),
        )

    # Materialise commits from commit.recorded events.
    # Keyed by commit_recorded_event_id (unique per commit.recorded event),
    # not commit_ref (which may collide post-rewrite — e.g. after a schema
    # migration touches every line of events.jsonl).
    last_boundary = 0
    for ev in events:
        if ev["type"] == "commit.recorded":
            attrs = ev.get("attributes", {})
            cref = blame.get(ev["_line_no"], (None,))[0]
            conn.execute(
                """INSERT OR REPLACE INTO commits (commit_recorded_event_id, commit_ref,
                    author, date, message_first_line,
                    first_event_line_no, last_event_line_no)
                    VALUES (?,?,?,?,?,?,?)""",
                (
                    ev["event_id"], cref,
                    attrs.get("author", ""),
                    attrs.get("date", ""),
                    attrs.get("message_first_line", ""),
                    last_boundary + 1,
                    ev["_line_no"],
                ),
            )
            last_boundary = ev["_line_no"]

    conn.commit()
    counts = {
        t: conn.execute(f"SELECT count(*) FROM {t}").fetchone()[0]
        for t in ("events", "entities", "relationships", "decisions", "commits")
    }
    conn.close()
    print(f"cache built: {counts}")


if __name__ == "__main__":
    main()
