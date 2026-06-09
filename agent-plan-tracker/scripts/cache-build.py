#!/usr/bin/env python3
"""Build .agent-plan-tracker/cache.sqlite from .agent-plan-tracker/events.jsonl.

- Inserts raw events; applies state-machine to materialise entities/relationships/decisions/commits.
- Runs `git blame --line-porcelain` to populate commit_ref + denormalised commit_meta on events.
- Idempotent: wipes tables before rebuild.
- Data dir defaults to .agent-plan-tracker/; override with APT_DATA_DIR (aptlib.apt_data_dir).
"""
import datetime
import json
import sqlite3
import subprocess
from pathlib import Path

import aptlib

REPO_ROOT = Path(__file__).resolve().parents[2]
DATA_DIR = aptlib.apt_data_dir(REPO_ROOT)
EVENTS = DATA_DIR / "events.jsonl"
CACHE = DATA_DIR / "cache.sqlite"
SCHEMA_DDL = REPO_ROOT / "agent-plan-tracker/schemas/0.3.0/cache.schema.sql"

STATE_FROM_EVENT = {
    "entity.created": "draft",
    "entity.extended": "live",
    "entity.accepted": "live",
    # entity.renamed is intentionally ABSENT: it is state-neutral (an identity
    # migration, not a lifecycle transition), so renaming a closed entity must
    # NOT flip it back to live. See the rename pre-scan in main() and
    # T2-ontology §3.10/§3.11.
    "entity.progressed": "live",
    "entity.completed": "closed",
    "entity.parked": "dormant",
    "entity.cancelled": "closed",
    "entity.superseded": "closed",
    "entity.reopened": "live",
}
# Draft-preserving events: extending a draft entity keeps it draft (still
# authoring, not bypassing the acceptance gate). From any other state,
# entity.extended maps to live as usual (reopening closed/dormant entities,
# same as entity.progressed). See T2-ontology §3.10 / T3-entity-accepted.
DRAFT_PRESERVING = {"entity.extended"}
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
    for table in ("events", "entities", "relationships", "decisions", "commits", "summaries"):
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

    # Pre-scan renames. An `entity.renamed` event MIGRATES an entity's canonical
    # id (from_name -> to_name) — the planning graph's identity-migration
    # primitive. Unlike reattach (which moves a child to a new PARENT), rename
    # rewrites the entity KEY itself everywhere it appears: the entity's own
    # events, and every relationship endpoint / frontmatter seed that referenced
    # the old id. Consequences: (1) the renamed entity carries its full history
    # forward under the new id; (2) children follow for free — no per-child
    # events — because their frozen `milestone`/`t2_parent` seed pointing at the
    # old id is remapped here; (3) no phantom row survives under the old id.
    # Any non-(from_name/to_name) attributes on the rename event patch the
    # migrated entity's materialised attributes (e.g. a milestone_index/title
    # change carried with the rename). entity.renamed is state-neutral (absent
    # from STATE_FROM_EVENT) so renaming a closed entity does not resurrect it.
    # Generic: keyed off whatever from_name/to_name a rename event carries — not
    # hardwired to any specific id. See T2-ontology §3.10/§3.11.
    id_remap = {}              # old_entity_id -> new_entity_id
    rename_attr_patch = {}     # new_entity_id -> {attr: value} (excludes from/to_name)
    for ev in events:
        if ev["type"] != "entity.renamed":
            continue
        attrs = ev.get("attributes", {})
        old_id, new_id = attrs.get("from_name"), attrs.get("to_name")
        if not (old_id and new_id):
            continue
        id_remap[old_id] = new_id
        patch = {k: v for k, v in attrs.items() if k not in ("from_name", "to_name")}
        if patch:
            rename_attr_patch[new_id] = patch

    def rid(eid):
        """Resolve an entity id through the rename map (identity migration)."""
        return id_remap.get(eid, eid) if eid is not None else eid

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
                ev["event_id"], ev["type"], ev.get("entity_type"), rid(ev.get("entity_id")),
                ev["actor"], ev["confidence"], ev["schema_version"],
                json.dumps(ev.get("attributes", {}), separators=(",", ":")),
                line_no, cref, cauthor, cdate, csum, cre_id,
            ),
        )

    # Materialise entities
    entities = {}
    for ev in events:
        et = ev.get("entity_type")
        eid = rid(ev.get("entity_id"))
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
        # Draft-preserving exception: entity.extended on a draft entity keeps
        # it draft (authoring continues; acceptance is a separate gate).
        if new_state and not (ev["type"] in DRAFT_PRESERVING and e["state"] == "draft"):
            e["state"] = new_state
        if ev["type"] == "entity.created":
            e["attrs"] = ev.get("attributes", {})
        elif ev["type"] == "entity.renamed":
            # identity migration: merge any non-(from_name/to_name) attributes
            # (e.g. a milestone_index/title change carried with the rename) onto
            # the migrated entity's materialised attrs. `eid` is already the new id.
            e["attrs"].update(rename_attr_patch.get(eid, {}))

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

    # Pre-scan reattachments. A `relationship.reattached` event MOVES a child
    # from from_parent to to_parent — the planning graph's rebase primitive. It
    # rewrites the spawn graph: the prior `from_parent spawns child` edge is
    # suppressed and a `to_parent spawns child` edge replaces it. Append-only
    # re-reattachment is honoured by last-write-wins. The move itself is also
    # kept as a `reattached` provenance row. (reattached carries from_parent/
    # to_parent, NOT from_entity_id, so the generic loop below skips it.)
    # See T3-milestone-parent-ontology.md §2 D3 + T2-ontology §3.6.
    reattach_new = {}          # (child_type, child_id) -> (to_parent_id, source_event_id)
    suppressed_spawns = set()  # {(from_parent_id, child_id)} spawn edges to drop
    for ev in events:
        if ev["type"] != "relationship.reattached":
            continue
        attrs = ev.get("attributes", {})
        fp, tp = rid(attrs.get("from_parent")), rid(attrs.get("to_parent"))
        child = rid(ev["entity_id"])
        if not (fp and tp):
            continue
        reattach_new[(ev["entity_type"], child)] = (tp, ev["event_id"])
        suppressed_spawns.add((fp, child))

    # Materialise relationships — event-sourced edges first (source='event').
    for ev in events:
        rtype = RELATIONSHIP_TYPES.get(ev["type"])
        if not rtype:
            continue
        attrs = ev.get("attributes", {})
        # reattached: record a provenance row (from_parent -> child, tagged
        # 'reattached'); the spawn rewrite is applied in the dedicated pass below.
        if rtype == "reattached":
            fp, tp = rid(attrs.get("from_parent")), rid(attrs.get("to_parent"))
            child = rid(ev["entity_id"])
            if not (fp and tp):
                continue
            conn.execute(
                """INSERT OR IGNORE INTO relationships (from_entity_type, from_entity_id,
                    to_entity_type, to_entity_id, relationship_type, source_event_id, source)
                    VALUES (?,?,?,?,?,?,?)""",
                ("plan", fp, ev["entity_type"], child, "reattached", ev["event_id"], "event"),
            )
            continue
        from_type = attrs.get("from_entity_type", "plan")
        from_id = rid(attrs.get("from_entity_id"))
        child = rid(ev["entity_id"])
        if not from_id:
            continue
        # Drop spawn edges that a reattachment has since superseded.
        if rtype == "spawns" and (from_id, child) in suppressed_spawns:
            continue
        conn.execute(
            """INSERT OR IGNORE INTO relationships (from_entity_type, from_entity_id,
                to_entity_type, to_entity_id, relationship_type, source_event_id, source)
                VALUES (?,?,?,?,?,?,?)""",
            (from_type, from_id, ev["entity_type"], child, rtype, ev["event_id"], "event"),
        )

    # Reattachment-introduced spawn edges (to_parent spawns child).
    for (child_type, child_id), (tp_id, ev_id) in reattach_new.items():
        conn.execute(
            """INSERT OR IGNORE INTO relationships (from_entity_type, from_entity_id,
                to_entity_type, to_entity_id, relationship_type, source_event_id, source)
                VALUES (?,?,?,?,?,?,?)""",
            ("plan", tp_id, child_type, child_id, "spawns", ev_id, "event"),
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
        # T3 → T2 parent (unless a reattachment has superseded this edge)
        t2p = rid(a.get("t2_parent"))
        if t2p and (t2p, eid) not in suppressed_spawns:
            conn.execute(
                """INSERT OR IGNORE INTO relationships (from_entity_type, from_entity_id,
                    to_entity_type, to_entity_id, relationship_type, source_event_id, source)
                    VALUES (?,?,?,?,?,?,?)""",
                ("plan", t2p, "plan", eid, "spawns", None, "frontmatter"),
            )
        # T3 → milestone (and any plan tagged with a milestone)
        m = rid(a.get("milestone"))
        if m and (m, eid) not in suppressed_spawns:
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

    # Materialise summaries (T2-analyser §3.2 / Phase B).
    # Pass 1: insert one row per analysis.live-summary event.
    # Pass 2: walk analysis.invalidated events and flip valid=0 on referenced summaries.
    # Analysis events are state-neutral on the focal entity (handled above as
    # any-other-event with no STATE_FROM_EVENT entry).
    for ev in events:
        if ev["type"] != "analysis.live-summary":
            continue
        attrs = ev.get("attributes", {})
        cre_id, _, _, _ = find_commit_for(ev["_line_no"])
        conn.execute(
            """INSERT OR REPLACE INTO summaries (event_id, entity_type, entity_id,
                source, model, origin_summary_event_id, supersedes_summary_event_id,
                freeform_path, structured, line_no, valid, invalidated_by_event_id,
                created_commit_recorded_event_id)
                VALUES (?,?,?,?,?,?,?,?,?,?,1,NULL,?)""",
            (
                ev["event_id"],
                ev.get("entity_type"),
                rid(ev.get("entity_id")),
                attrs.get("source", "primary"),
                attrs.get("model", ""),
                attrs.get("origin_summary_event_id"),
                attrs.get("supersedes_summary_event_id"),
                attrs.get("freeform_path", ""),
                json.dumps(attrs.get("structured", {}), separators=(",", ":")),
                ev["_line_no"],
                cre_id,
            ),
        )
    for ev in events:
        if ev["type"] != "analysis.invalidated":
            continue
        attrs = ev.get("attributes", {})
        target = attrs.get("target_event_id")
        cascades = attrs.get("cascades_to_event_ids", []) or []
        for tid in [target] + list(cascades):
            if not tid:
                continue
            conn.execute(
                "UPDATE summaries SET valid = 0, invalidated_by_event_id = ? WHERE event_id = ?",
                (ev["event_id"], tid),
            )

    conn.commit()
    counts = {
        t: conn.execute(f"SELECT count(*) FROM {t}").fetchone()[0]
        for t in ("events", "entities", "relationships", "decisions", "commits",
                  "summaries")
    }
    conn.close()
    print(f"cache built: {counts}")


if __name__ == "__main__":
    main()
