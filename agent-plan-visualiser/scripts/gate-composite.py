#!/usr/bin/env python3
"""gate-composite.py — one question: is this log a trustworthy record?

T3-integrity-composite (M3-clean-gate). Blocking = corruption of the record
(exit 1); warn = advisory signal, printed but never failing (exit 0).
Check lists come from `.apv-config.toml` `[gate]` — moving an id between
`blocking` and `warn` changes enforcement without code edits.

Architecture:
- BLOCKING checks replay events.jsonl directly. They deliberately do NOT
  trust cache.sqlite: cache-build tolerates and repairs some defects
  (frontmatter fallback, generous folds) — the gate must see the raw record.
- WARN checks run against cache.sqlite (rebuilt via cache-build.py when the
  event count disagrees with the log). They are the existing audit
  projections, demoted to advisory by the M3 reframe (M3-clean-gate §2:
  visible true state merges freely; only corruption blocks).
- The schema check shells out to validate-events.sh per schema_version
  group, keeping this script stdlib-only while literally reusing the
  existing validator (resolves T3-integrity-composite §6 Q2: separate entry
  points, shared validator).

Epoch rule (build decision, 2026-06-10): replay-semantics checks enforce the
0.3.0 capture discipline (apv-capture SKILL §3/§4: created-first, draft
gate, explicit reopen) from the schema version that introduced it. Earlier
events were sealed under earlier regimes and are judged by those regimes'
rules, not retroactively. Keying:
- implementation-on-draft keys on the ENTITY's birth regime (its
  entity.created `schema_version` >= 0.3.0). Draft is a creation-time
  property; an entity born pre-0.3.0 was never draft under its own regime —
  cache-build's retroactive created->draft mapping is a replay convenience,
  not a historical claim. The record itself validates this: the first
  acceptance ceremony accepted exactly the plans born into the 0.3.0 regime,
  while T3-entity-accepted (born 0.2.0, the plan that BUILT the machinery)
  needed none.
- referential's lifecycle-without-created and resurrection-without-reopen
  key on the OFFENDING event's schema_version.
Structural checks (dangling decision refs, relationship existence, sealed
tail, fulcrum-without-decision, per-version schema routing) were never
legitimate in any regime and apply to all epochs.

Exit codes: 0 clean (warnings permitted), 1 any blocking instance, 2 usage
or environment error.
"""
import argparse
import json
import os
import re
import sqlite3
import subprocess
import sys
import tempfile
from pathlib import Path

import apvlib

SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_REPO_ROOT = Path(__file__).resolve().parents[2]

# --- Ontology constants. MIRROR cache-build.py — keep the two in sync. ---
STATE_FROM_EVENT = {
    "entity.created": "draft",
    "entity.extended": "live",
    "entity.accepted": "live",
    # entity.renamed intentionally ABSENT: state-neutral identity migration
    # (renaming a closed entity must not resurrect it). See cache-build.py.
    "entity.progressed": "live",
    "entity.completed": "closed",
    "entity.parked": "dormant",
    "entity.cancelled": "closed",
    "entity.superseded": "closed",
    "entity.reopened": "live",
}
DRAFT_PRESERVING = {"entity.extended"}  # extended on draft stays draft
LIFECYCLE_TYPES = set(STATE_FROM_EVENT) | {"entity.renamed"}
FULCRUM_TYPES = {  # mirror audit-fulcrum-without-decision.sql
    "entity.renamed", "entity.parked", "entity.cancelled",
    "entity.superseded", "entity.reopened",
    # project.assigned (0.6.0): a retrospective membership assertion is a
    # re-organisation ruling — same class as rename/reattach. One decision
    # may cover a bulk assignment (event_ids containment). State-neutral:
    # intentionally absent from STATE_FROM_EVENT and LIFECYCLE_TYPES.
    "project.assigned",
}
RELATIONSHIP_FROM_TYPES = {
    "relationship.spawns", "relationship.depends-on",
    "relationship.addendum-to", "relationship.alongside",
}

# The capture-discipline epoch: schema version that introduced created-first,
# the draft gate (entity.accepted), and explicit reopen. An ontology fact,
# not project preference — hence code, not config.
EPOCH = (0, 3, 0)


def is_backfilled(ev):
    """Origin-aware enforcement (T2-ontology §3.12, the 0.4.0 provenance
    epoch): discipline checks do not JUDGE backfilled events — they record
    what happened, not what should have; the methodology cannot be demanded
    retroactively of commits that predate adoption. Backfilled events still
    FOLD into state (the replay must see them) and schema validity applies
    in full regardless of origin. This generalises the schema_version epoch
    keying above: epochs key on when discipline existed; provenance keys on
    whether anyone was there to practise it."""
    return ev.get("origin") == "backfilled"

# Built-in defaults — identical to the committed .apv-config.toml [gate]
# lists; used when no config file exists (the gate must run pre-adoption).
DEFAULT_BLOCKING = [
    "schema", "referential", "sealed-tail", "implementation-on-draft",
    "resurrection-without-reopen", "fulcrum-without-decision",
]
DEFAULT_WARN = [
    "drift", "orphans", "stalled", "long-blockers",
    "pending-ceremony", "deferred-verification",
]

LONG_BLOCKER_COMMITS = 5  # warn when a live blocker has outlived N commits


def parse_version(sv):
    try:
        return tuple(int(x) for x in str(sv).split("."))
    except ValueError:
        return (0, 0, 0)


def parse_frontmatter(path):
    """Minimal regex frontmatter parse (flat `key: value` lines only) — no
    pyyaml dependency; t2_parent/milestone are plain strings."""
    m = re.match(r"^---\n(.*?)\n---", path.read_text(), re.DOTALL)
    fm = {}
    if m:
        for line in m.group(1).splitlines():
            km = re.match(r"^(\w+):\s*(.+?)\s*$", line)
            if km:
                fm[km.group(1)] = km.group(2).strip("'\"")
    return fm


def is_milestone_id(pid):
    """Milestone-axis plan ids are M<n>-... ; everything else is thematic
    (T2-..., XT2-..., PT2-..., T1-...)."""
    return bool(re.match(r"^M\d", pid or ""))


class Ctx:
    """Shared per-run context: parsed events, rename remap, seal lookup,
    birth registry, and a lazily built cache connection for warn checks."""

    def __init__(self, repo_root, data_dir, planning_dir, planning_roots=None):
        self.repo_root = repo_root
        self.data_dir = data_dir
        self.planning_dir = planning_dir
        # Ordered [(project_name, root_path)]; single-root contexts (the
        # --planning-dir flag, fixtures) collapse to one 'main' root.
        self.planning_roots = planning_roots or [("main", planning_dir)]
        self.events_path = data_dir / "events.jsonl"
        self._cache_conn = None

        self.events = []
        with open(self.events_path) as f:
            for line_no, raw in enumerate(f, start=1):
                ev = json.loads(raw)
                ev["_line_no"] = line_no
                self.events.append(ev)

        # Rename pre-scan (mirror cache-build: single-hop resolution).
        self._id_remap = {}
        for ev in self.events:
            if ev["type"] != "entity.renamed":
                continue
            a = ev.get("attributes", {})
            if a.get("from_name") and a.get("to_name"):
                self._id_remap[a["from_name"]] = a["to_name"]

        # Positional rollup boundaries (mirror cache-build.find_commit_for).
        self.boundaries = [
            (ev["_line_no"], ev["event_id"], ev.get("attributes", {}))
            for ev in self.events if ev["type"] == "commit.recorded"
        ]

        # Birth registry: first entity.created per (type, rid) — its schema
        # version (epoch keying) and line (same-block carve-out).
        self.created_sv = {}
        self.created_line = {}
        for ev in self.events:
            if ev["type"] != "entity.created":
                continue
            key = (ev.get("entity_type"), self.rid(ev.get("entity_id")))
            if key[0] and key[1] and key not in self.created_sv:
                self.created_sv[key] = parse_version(ev.get("schema_version"))
                self.created_line[key] = ev["_line_no"]

    def rid(self, eid):
        return self._id_remap.get(eid, eid) if eid is not None else None

    def seal_for(self, line_no):
        """First commit.recorded at line >= line_no, or None (unsealed tail)."""
        for b_line, b_id, b_attrs in self.boundaries:
            if b_line >= line_no:
                return (b_line, b_id, b_attrs)
        return None

    def seal_line(self, line_no):
        s = self.seal_for(line_no)
        return s[0] if s else None

    def cache(self):
        """Connection to cache.sqlite, rebuilding via cache-build.py when the
        event count disagrees with the log. (Count equality is a heuristic —
        a same-length edit slips past — acceptable for advisory checks;
        blocking checks never read the cache.)"""
        if self._cache_conn is not None:
            return self._cache_conn
        cache_path = self.data_dir / "cache.sqlite"
        stale = True
        if cache_path.exists():
            try:
                conn = sqlite3.connect(cache_path)
                n_cache = conn.execute("SELECT COUNT(*) FROM events").fetchone()[0]
                conn.close()
                stale = n_cache != len(self.events)
            except sqlite3.Error:
                stale = True
        if stale:
            env = dict(os.environ, APV_DATA_DIR=str(self.data_dir))
            proc = subprocess.run(
                [sys.executable, str(SCRIPT_DIR / "cache-build.py")],
                env=env, capture_output=True, text=True, cwd=self.repo_root,
            )
            if proc.returncode != 0:
                # tail, not head: a traceback's cause is on its last line
                raise RuntimeError(
                    f"cache-build.py failed: {(proc.stderr or proc.stdout).strip()[-300:]}"
                )
        self._cache_conn = sqlite3.connect(cache_path)
        return self._cache_conn


# --------------------------- blocking checks ---------------------------

def check_schema(ctx):
    """Every event validates against its own schema_version's schema —
    grouped per version, each group fed to validate-events.sh."""
    instances = []
    groups = {}
    for ev in ctx.events:
        groups.setdefault(str(ev.get("schema_version")), []).append(ev)
    for sv, evs in sorted(groups.items()):
        # Schemas are plugin content (code, not data): they resolve against
        # the toolchain home, NOT --repo-root — a gated repo (sandbox, any
        # adopting project) carries a log, not a copy of the schemas.
        schema = SCRIPT_DIR.parent / "schemas" / sv / "events.schema.json"
        if not schema.exists():
            instances.append(
                f"unknown schema_version '{sv}' ({len(evs)} event(s), first at "
                f"line {evs[0]['_line_no']}) — no such schema directory"
            )
            continue
        tmp = None
        try:
            with tempfile.NamedTemporaryFile(
                "w", suffix=".jsonl", delete=False, encoding="utf-8"
            ) as tf:
                tmp = tf.name
                for ev in evs:
                    clean = {k: v for k, v in ev.items() if not k.startswith("_")}
                    tf.write(json.dumps(clean, separators=(",", ":")) + "\n")
            proc = subprocess.run(
                ["bash", str(SCRIPT_DIR / "validate-events.sh"), str(schema), tmp],
                capture_output=True, text=True, cwd=ctx.repo_root,
            )
            if proc.returncode != 0:
                # Map the validator's group-file line numbers back to the
                # original log's line numbers.
                line_map = {i: ev["_line_no"] for i, ev in enumerate(evs, start=1)}
                found = False
                for out_line in (proc.stderr + "\n" + proc.stdout).splitlines():
                    m = re.search(r"\bline (\d+)\b", out_line)
                    if m and int(m.group(1)) in line_map:
                        found = True
                        mapped = out_line.replace(
                            f"line {m.group(1)}", f"line {line_map[int(m.group(1))]}", 1
                        )
                        instances.append(f"[{sv}] {mapped.strip()}")
                if not found:
                    instances.append(
                        f"[{sv}] validator exit {proc.returncode}: "
                        f"{(proc.stderr or proc.stdout).strip()[:300]}"
                    )
        finally:
            if tmp:
                os.unlink(tmp)
    return instances


def check_referential(ctx):
    """decision.event_ids resolve; relationship endpoints name entities that
    exist; lifecycle events (>= 0.3.0) name entities with an entity.created."""
    instances = []
    all_event_ids = {ev["event_id"] for ev in ctx.events}
    existing = set()
    for ev in ctx.events:
        # project.assigned events don't establish existence — an annotation's
        # own target must be known from some other event, else the check
        # would vacuously satisfy itself (a typo'd id would slip through).
        if ev["type"] == "project.assigned":
            continue
        if ev.get("entity_type") and ev.get("entity_id"):
            existing.add((ev["entity_type"], ctx.rid(ev["entity_id"])))
    for ev in ctx.events:
        t, a = ev["type"], ev.get("attributes", {})
        loc = f"{ev['event_id']} (line {ev['_line_no']})"
        if t == "decision":
            for ref in a.get("event_ids") or []:
                if ref not in all_event_ids:
                    instances.append(f"decision {loc} references missing event_id {ref}")
        elif t == "relationship.reattached":
            for fld in ("from_parent", "to_parent"):
                pid = ctx.rid(a.get(fld))
                if pid and ("plan", pid) not in existing:
                    instances.append(f"{t} {loc}: {fld} '{pid}' names no known entity")
        elif t in RELATIONSHIP_FROM_TYPES:
            fid = ctx.rid(a.get("from_entity_id"))
            ftype = a.get("from_entity_type", "plan")
            if fid and (ftype, fid) not in existing:
                instances.append(
                    f"{t} {loc}: from-entity {ftype} '{fid}' names no known entity"
                )
        elif t == "project.assigned":
            # Existence-in-record is the bar, NOT created-first (deliberately
            # not in LIFECYCLE_TYPES): the annotation must target a known
            # entity, but legacy pre-0.3.0 entities without an entity.created
            # remain annotatable. The project NAME is not validated — the
            # registry governs roots, not the namespace (see cache-build).
            key = (ev.get("entity_type"), ctx.rid(ev.get("entity_id")))
            if key[0] and key[1] and key not in existing:
                instances.append(
                    f"{t} {loc}: {key[0]} '{key[1]}' names no known entity"
                )
        elif t in LIFECYCLE_TYPES and t != "entity.created":
            if parse_version(ev.get("schema_version")) < EPOCH:
                continue  # pre-discipline epoch: created-first formalised at 0.3.0
            key = (ev.get("entity_type"), ctx.rid(ev.get("entity_id")))
            if key[0] and key[1] and key not in ctx.created_sv:
                instances.append(
                    f"{t} {loc}: {key[0]} '{key[1]}' has no entity.created anywhere in the log"
                )
    return instances


def check_sealed_tail(ctx):
    """No trailing unsealed run — at the merge boundary, trailing events
    would belong to no commit."""
    if not ctx.events:
        return []
    last_line = ctx.events[-1]["_line_no"]
    if not ctx.boundaries:
        return [f"no commit.recorded anywhere — all {last_line} event(s) form an unsealed run"]
    last_seal = ctx.boundaries[-1][0]
    if last_seal < last_line:
        n = last_line - last_seal
        first_unsealed = ctx.events[last_seal]  # 0-based list: line last_seal+1
        return [
            f"{n} unsealed trailing event(s) after line {last_seal} "
            f"(first: {first_unsealed['type']} {first_unsealed['event_id']}) — "
            f"no commit.recorded owns them"
        ]
    return []


def check_impl_on_draft(ctx):
    """entity.progressed/completed against a draft entity — backstop for the
    skill's advisory draft gate. Epoch-keyed on the entity's birth regime;
    honours the implicit-work same-sealed-block carve-out (SKILL §4)."""
    instances = []
    state = {}
    for ev in ctx.events:
        et, eid = ev.get("entity_type"), ctx.rid(ev.get("entity_id"))
        if not (et and eid):
            continue
        key, t = (et, eid), ev["type"]
        if (t in ("entity.progressed", "entity.completed")
                and state.get(key) == "draft" and not is_backfilled(ev)):
            birth = ctx.created_sv.get(key)
            if birth is not None and birth >= EPOCH:
                same_block_implicit = (
                    et == "implicit-work"
                    and key in ctx.created_line
                    and ctx.seal_line(ev["_line_no"]) == ctx.seal_line(ctx.created_line[key])
                )
                if not same_block_implicit:
                    instances.append(
                        f"{t} {ev['event_id']} (line {ev['_line_no']}): {et} '{eid}' "
                        f"is draft — implementation requires operator acceptance "
                        f"(entity.accepted)"
                    )
        new_state = STATE_FROM_EVENT.get(t)
        if new_state and not (t in DRAFT_PRESERVING and state.get(key) == "draft"):
            state[key] = new_state
    return instances


def check_resurrection(ctx):
    """State-bearing events on a closed entity without an intervening
    entity.reopened. Branch-agnostic — also catches cross-branch
    contradictions after a merge. Epoch-keyed on the offending event.

    A LATER entity.reopened for the same entity heals the violations
    before it: every blocking check must be append-only-repairable, and
    the /apv-merge reconciliation repairs a merged contradiction by
    appending the operator's ruling (reopened + paired decision — the
    fulcrum check guarantees the decision). What blocks at the boundary
    is the UNRESOLVED contradiction; a resolved one reads coherently:
    the ruling is in the log. A reopen heals only what precedes it —
    violations after it accumulate afresh."""
    pending = {}  # (et, eid) -> [(line_no, instance)] awaiting a healing reopen
    state = {}
    for ev in ctx.events:
        et, eid = ev.get("entity_type"), ctx.rid(ev.get("entity_id"))
        if not (et and eid):
            continue
        key, t = (et, eid), ev["type"]
        if t == "entity.reopened":
            pending.pop(key, None)  # ruling recorded — earlier contradiction resolved
        elif (
            state.get(key) == "closed"
            and t in STATE_FROM_EVENT
            and parse_version(ev.get("schema_version")) >= EPOCH
            and not is_backfilled(ev)
        ):
            pending.setdefault(key, []).append((
                ev["_line_no"],
                f"{t} {ev['event_id']} (line {ev['_line_no']}): {et} '{eid}' is "
                f"closed — resurrection requires entity.reopened (+ paired decision)",
            ))
        new_state = STATE_FROM_EVENT.get(t)
        if new_state and not (t in DRAFT_PRESERVING and state.get(key) == "draft"):
            state[key] = new_state
    return [msg for _, msg in sorted(p for lst in pending.values() for p in lst)]


def check_fulcrum(ctx):
    """Fulcrum events not paired with a same-commit decision referencing
    them — mirror of audit-fulcrum-without-decision.sql on the raw log
    (same seal + attributes-contains-event_id pairing).

    Backfilled fulcrums (T2-ontology §3.12 three-tier Why): a recovered or
    recollected decision pairs as usual; where only tier 3 exists, a
    same-block hitl-question carrying the fulcrum's event_id (the candidate
    hypotheses) stands in — an honest open question, never a fabricated
    rationale. Captured fulcrums cannot use the stand-in."""
    instances = []
    decisions_by_seal = {}
    hitl_by_seal = {}
    for ev in ctx.events:
        seal = ctx.seal_for(ev["_line_no"])
        sid = seal[1] if seal else None
        if ev["type"] == "decision":
            decisions_by_seal.setdefault(sid, []).append(
                json.dumps(ev.get("attributes", {}))
            )
        elif ev["type"] == "entity.created" and ev.get("entity_type") == "hitl-question":
            hitl_by_seal.setdefault(sid, []).append(
                json.dumps(ev.get("attributes", {}))
            )
    for ev in ctx.events:
        if ev["type"] not in FULCRUM_TYPES:
            continue
        seal = ctx.seal_for(ev["_line_no"])
        sid = seal[1] if seal else None
        paired = sid is not None and any(
            ev["event_id"] in blob for blob in decisions_by_seal.get(sid, [])
        )
        if not paired and is_backfilled(ev) and sid is not None:
            paired = any(
                ev["event_id"] in blob for blob in hitl_by_seal.get(sid, [])
            )
        if not paired:
            instances.append(
                f"{ev['type']} {ev['event_id']} (line {ev['_line_no']}): "
                f"{ev.get('entity_type')} '{ctx.rid(ev.get('entity_id'))}' — "
                f"no paired decision in the same commit"
            )
    return instances


# ----------------------------- warn checks -----------------------------

def check_drift(ctx):
    """Frontmatter-vs-event drift (the M1.2 IOU): a non-closed plan file
    whose t2_parent/milestone disagrees with the event-sourced spawn
    parentage. Frontmatter is a creation-time seed; relationship.reattached
    is the move primitive; events are SSOT."""
    instances = []
    conn = ctx.cache()
    states = {
        row[0]: row[1]
        for row in conn.execute(
            "SELECT entity_id, derived_state FROM entities WHERE entity_type='plan'"
        )
    }
    parents = {}
    for fid, cid in conn.execute(
        "SELECT from_entity_id, to_entity_id FROM relationships "
        "WHERE relationship_type='spawns' AND source='event' AND to_entity_type='plan'"
    ):
        parents.setdefault(cid, set()).add(fid)
    # Multi-project (T3-multi-project): every registered planning root is
    # checked; a plan id present in TWO roots is itself a defect (entity ids
    # are repo-global in the one-log model) and surfaces here as drift.
    seen_ids = {}
    for root_name, root_dir in ctx.planning_roots:
        for md in sorted(root_dir.glob("*.md")):
            pid = md.stem
            if pid in seen_ids:
                instances.append(
                    f"plan '{pid}' present in planning roots "
                    f"'{seen_ids[pid]}' and '{root_name}' — duplicate plan id "
                    f"(entity ids are repo-global)"
                )
                continue
            seen_ids[pid] = root_name
            if states.get(pid) not in ("live", "draft", "dormant"):
                continue  # closed plans' stale frontmatter is archaeology, not drift
            fm = parse_frontmatter(md)
            for field in ("t2_parent", "milestone"):
                declared = fm.get(field)
                if not declared:
                    continue
                event_parents = {
                    p for p in parents.get(pid, ())
                    if is_milestone_id(p) == (field == "milestone")
                }
                if event_parents and declared not in event_parents:
                    instances.append(
                        f"plan '{pid}' frontmatter {field}: '{declared}' but "
                        f"event-sourced parent is {sorted(event_parents)} — file is "
                        f"stale (events are SSOT)"
                    )
    return instances


def check_orphans(ctx):
    """audit-orphans.sql against the cache: children of closed parents (via
    spawns) still live/dormant/unknown."""
    rows = ctx.cache().execute("""
        WITH closed_parents AS (
          SELECT entity_type, entity_id FROM entities WHERE derived_state = 'closed'
        ),
        orphan_candidates AS (
          SELECT r.to_entity_type AS child_type, r.to_entity_id AS child_id,
                 r.from_entity_id AS parent_id
          FROM relationships r
          JOIN closed_parents p
            ON r.from_entity_type = p.entity_type AND r.from_entity_id = p.entity_id
          WHERE r.relationship_type = 'spawns'
        )
        SELECT oc.child_type, oc.child_id, oc.parent_id, e.derived_state
        FROM orphan_candidates oc
        JOIN entities e
          ON e.entity_type = oc.child_type AND e.entity_id = oc.child_id
        WHERE e.derived_state IN ('live', 'dormant', 'unknown')
        ORDER BY oc.child_id""").fetchall()
    return [
        f"{ct} '{cid}' ({st}) hangs off closed parent '{pid}'"
        for ct, cid, pid, st in rows
    ]


def check_stalled(ctx):
    """audit-stalled.sql against the cache: live entities that didn't fire
    during the most recent commit."""
    rows = ctx.cache().execute("""
        WITH latest_commit AS (
          SELECT first_event_line_no FROM commits
          ORDER BY last_event_line_no DESC LIMIT 1
        ),
        last_per_entity AS (
          SELECT entity_type, entity_id, MAX(line_no) AS last_line
          FROM events WHERE entity_type IS NOT NULL
          GROUP BY entity_type, entity_id
        )
        SELECT e.entity_type, e.entity_id, l.last_line
        FROM entities e
        LEFT JOIN last_per_entity l USING (entity_type, entity_id)
        WHERE e.derived_state = 'live'
          AND l.last_line < (SELECT first_event_line_no FROM latest_commit)
        ORDER BY l.last_line ASC""").fetchall()
    return [
        f"{et} '{eid}' live but silent since line {ll} (before the latest commit)"
        for et, eid, ll in rows
    ]


def check_long_blockers(ctx):
    """Live blockers that have outlived LONG_BLOCKER_COMMITS commits since
    being raised. No prior SQL audit existed — implemented fresh here."""
    conn = ctx.cache()
    out = []
    for eid, born_line in conn.execute("""
        SELECT e.entity_id, (
          SELECT MIN(line_no) FROM events ev
          WHERE ev.entity_type = 'blocker' AND ev.entity_id = e.entity_id
        )
        FROM entities e
        WHERE e.entity_type = 'blocker' AND e.derived_state = 'live'""").fetchall():
        if born_line is None:
            continue
        n = conn.execute(
            "SELECT COUNT(*) FROM commits WHERE first_event_line_no > ?", (born_line,)
        ).fetchone()[0]
        if n >= LONG_BLOCKER_COMMITS:
            out.append(
                f"blocker '{eid}' open for {n} commits (raised at line {born_line}, "
                f"threshold {LONG_BLOCKER_COMMITS})"
            )
    return out


def check_pending_ceremony(ctx):
    """Ceremonies are enforced lazily (draft gate, operator-only acceptance)
    but nothing PROMPTS one — the 2026-07-03.ceremony-prompting-gap lesson:
    an authored-but-unaccepted plan sat 23 days while everyone believed it
    built. Two flavours, both advisory:
    - acceptance pending: a plan in draft (inbox items are excluded — draft
      is their correct untriaged resting state);
    - closure pending: a live milestone whose scheduled T3s are all closed —
      either its ceremony is owed or its definition-of-done legs are the
      only thing left, and both deserve the operator's eye."""
    conn = ctx.cache()
    out = []
    for eid, born_line in conn.execute("""
        SELECT e.entity_id, (
          SELECT MIN(line_no) FROM events ev
          WHERE ev.entity_type = 'plan' AND ev.entity_id = e.entity_id
        )
        FROM entities e
        WHERE e.entity_type = 'plan' AND e.derived_state = 'draft'
        ORDER BY e.entity_id""").fetchall():
        n = conn.execute(
            "SELECT COUNT(*) FROM commits WHERE first_event_line_no > ?",
            (born_line or 0,),
        ).fetchone()[0]
        out.append(
            f"plan '{eid}' is draft — acceptance ceremony pending "
            f"({n} commit(s) since authoring; the draft gate blocks "
            f"implementation against it meanwhile)"
        )
    for mid, sched, closed in conn.execute("""
        SELECT r.from_entity_id,
               COUNT(*) AS scheduled,
               SUM(CASE WHEN c.derived_state = 'closed' THEN 1 ELSE 0 END)
        FROM relationships r
        JOIN entities m ON m.entity_type = 'plan' AND m.entity_id = r.from_entity_id
        JOIN entities c ON c.entity_type = r.to_entity_type AND c.entity_id = r.to_entity_id
        WHERE r.relationship_type = 'spawns'
          AND r.from_entity_id GLOB 'M[0-9]*'
          AND r.to_entity_id GLOB 'T3-*'
          AND m.derived_state = 'live'
        GROUP BY r.from_entity_id
        ORDER BY r.from_entity_id""").fetchall():
        if sched and closed == sched:
            out.append(
                f"milestone '{mid}' has all {sched} scheduled T3(s) closed but is "
                f"still live — closure ceremony (or its remaining definition-of-done "
                f"legs) pending"
            )
    return out


def check_deferred_verification(ctx):
    """Open operator deferrals (verification.deferred, the 0.5.0 epoch):
    'skipped, but we mean to come back'. An entity's deferral is open while
    its LATEST verification.* event is a deferral; any later verification
    event on the same entity resolves it. Advisory by design — a deferral
    is an honest recorded state, not corruption; this check is the
    come-back-to-it prompt."""
    conn = ctx.cache()
    latest = {}  # (entity_type, entity_id) -> (line_no, attributes_json)
    for et, eid, typ, attrs, line in conn.execute("""
        SELECT entity_type, entity_id, type, attributes, line_no
        FROM events
        WHERE type LIKE 'verification.%' AND entity_id IS NOT NULL
        ORDER BY line_no ASC"""):
        latest[(et, eid)] = (typ, attrs, line)
    out = []
    for (et, eid), (typ, attrs, line) in sorted(latest.items(), key=lambda kv: kv[1][2]):
        if typ != "verification.deferred":
            continue
        try:
            reason = json.loads(attrs or "{}").get("reason", "")
        except json.JSONDecodeError:
            reason = ""
        out.append(
            f"{et} '{eid}' has an open deferred verification (line {line})"
            + (f": {reason}" if reason else "")
        )
    return out


CHECKS = {
    "schema": check_schema,
    "referential": check_referential,
    "sealed-tail": check_sealed_tail,
    "implementation-on-draft": check_impl_on_draft,
    "resurrection-without-reopen": check_resurrection,
    "fulcrum-without-decision": check_fulcrum,
    "drift": check_drift,
    "orphans": check_orphans,
    "stalled": check_stalled,
    "long-blockers": check_long_blockers,
    "pending-ceremony": check_pending_ceremony,
    "deferred-verification": check_deferred_verification,
}


def resolve_check_lists(cfg):
    """[gate] blocking/warn from config (built-in defaults when absent).
    Unknown ids are dropped with a notice; an id in both lists is blocking."""
    gate = cfg.get("gate") or {}
    blocking = gate.get("blocking", DEFAULT_BLOCKING)
    warn = gate.get("warn", DEFAULT_WARN)

    def known(ids, label):
        kept = []
        for cid in ids:
            if cid in CHECKS:
                kept.append(cid)
            else:
                print(f"notice: unknown {label} check id '{cid}' ignored", file=sys.stderr)
        return kept

    blocking = known(blocking, "blocking")
    warn = [c for c in known(warn, "warn") if c not in blocking]
    return blocking, warn


def main():
    ap = argparse.ArgumentParser(
        description="Integrity composite: is this event log a trustworthy record?"
    )
    ap.add_argument("--repo-root", type=Path, default=DEFAULT_REPO_ROOT)
    ap.add_argument("--config", type=Path, default=None,
                    help="path to .apv-config.toml (default: <repo-root>/.apv-config.toml; "
                         "explicit path must exist)")
    ap.add_argument("--data-dir", type=Path, default=None,
                    help="data dir override (default: apvlib resolution — env, config, default)")
    ap.add_argument("--planning-dir", type=Path, default=None,
                    help="plans dir for the drift check (default: apvlib resolution — "
                         "env, config [storage] planning_dir, <repo-root>/planning)")
    args = ap.parse_args()

    # Resolve every path to absolute up front: data_dir is re-exported as
    # APV_DATA_DIR into the cache-build subprocess (different cwd), where a
    # relative path would silently resolve against the wrong base.
    repo_root = args.repo_root.resolve()
    for name in ("config", "data_dir", "planning_dir"):
        v = getattr(args, name)
        if v is not None:
            setattr(args, name, v.resolve())
    if args.config and not args.config.exists():
        print(f"error: --config {args.config} does not exist", file=sys.stderr)
        return 2
    try:
        cfg = apvlib.apv_config(repo_root, args.config)
    except Exception as e:  # malformed committed config: fail loud, not open
        print(f"error: cannot parse config: {e}", file=sys.stderr)
        return 2
    blocking_ids, warn_ids = resolve_check_lists(cfg)

    data_dir = args.data_dir or apvlib.apv_data_dir(repo_root, args.config)
    planning_dir = args.planning_dir or apvlib.apv_planning_dir(repo_root, args.config)
    # Multi-project roots for the drift check: an explicit --planning-dir
    # collapses the registry to that single root (fixture behaviour
    # unchanged); otherwise the committed registry + implicit main resolve.
    if args.planning_dir:
        planning_roots = [("main", args.planning_dir)]
    else:
        planning_roots = [
            (n, p.resolve()) for n, p in apvlib.apv_planning_roots(repo_root, args.config)
        ]
    if not (data_dir / "events.jsonl").exists():
        print(f"error: no events.jsonl in {data_dir}", file=sys.stderr)
        return 2

    ctx = Ctx(repo_root, data_dir, planning_dir, planning_roots)

    n_block = n_warn = 0
    for cid in blocking_ids:
        try:
            found = CHECKS[cid](ctx)
        except Exception as e:
            # A blocking check that cannot run fails CLOSED.
            found = [f"check errored ({e.__class__.__name__}: {e}) — failing closed"]
        for inst in found:
            n_block += 1
            print(f"BLOCK [{cid}] {inst}")
    for cid in warn_ids:
        try:
            found = CHECKS[cid](ctx)
        except Exception as e:
            # An advisory check that cannot run is reported but never gates.
            print(f"notice: warn check '{cid}' skipped ({e})", file=sys.stderr)
            continue
        for inst in found:
            n_warn += 1
            print(f"WARN [{cid}] {inst}")

    print(f"checks: blocking={blocking_ids} warn={warn_ids}")
    if n_block:
        print(f"gate: {n_block} blocking instance(s), {n_warn} warning(s) — FAIL")
        return 1
    print(f"gate: clean, {n_warn} warning(s) — PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
