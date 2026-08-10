#!/usr/bin/env python3
"""triage-emit.py — the deterministic half of /apv-triage-why
(T3-why-triage-pass; doctrine: T2-ingest §3.7, ontology: T2-ontology §3.12).

Consumes a backfill run's hypotheses file plus the operator's rulings and
appends the conversion events append-only:

  - ruling "confirmed" / "reworded"  ->  a `decision` (tier 2, RECOLLECTED:
    the OPERATOR is the actor — their say-so is the event) referencing the
    fulcrum event_ids, plus `entity.completed` on the standing
    hitl-question (the open question closes because it was answered);
  - ruling "unknown"                 ->  nothing (the hitl-question stands,
    honestly open).

All emitted events carry `origin: "backfilled"` + the run id (they are
part of the mined cohort — repudiating the run repudiates its triage).
The consumed hypotheses file is archived to <data>/archive/, making re-runs
no-ops (idempotency). The caller seals the triage commit normally
(/apv-capture discipline — this script only appends the conversion events).

Usage:
  triage-emit.py --project-path PATH --run-id ID --rulings FILE --actor SLUG

Rulings file: JSON array of
  {"question_entity_id": "...", "ruling": "confirmed"|"reworded"|"unknown",
   "text": "<the rationale, in the operator's words>"}   (text required
   unless ruling is "unknown")
"""
from __future__ import annotations

import argparse
import json
import sys
import uuid
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
import apvlib  # noqa: E402


def ordered(e: dict) -> dict:
    keys = ("event_id", "type", "origin", "actor", "confidence",
            "schema_version", "entity_type", "entity_id", "attributes")
    return {k: e[k] for k in keys if k in e}


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--project-path", required=True, type=Path)
    ap.add_argument("--run-id", required=True)
    ap.add_argument("--rulings", required=True, type=Path)
    ap.add_argument("--actor", required=True,
                    help="the OPERATOR's handle — recollection is their testimony")
    args = ap.parse_args()

    project_path = args.project_path.resolve()
    data_dir = apvlib.apv_data_dir(project_path)
    events_path = data_dir / "events.jsonl"
    hypo_path = data_dir / "needs-review" / f"hypotheses-{args.run_id}.jsonl"

    if not hypo_path.exists():
        print(f"triage-emit: no hypotheses file for run {args.run_id} at {hypo_path} "
              "— already consumed (archived) or the run queued none. Nothing to do.")
        return 0

    hypotheses = {}
    with open(hypo_path) as f:
        for line in f:
            h = json.loads(line)
            hypotheses[h["question_entity_id"]] = h

    rulings = json.loads(args.rulings.read_text())
    if not isinstance(rulings, list):
        sys.exit("ERROR: rulings file must be a JSON array")

    # Already-closed questions are skipped (idempotency at the event level).
    closed = set()
    with open(events_path) as f:
        for line in f:
            ev = json.loads(line)
            if (ev.get("entity_type") == "hitl-question"
                    and ev.get("type") in ("entity.completed", "entity.cancelled")):
                closed.add(ev.get("entity_id"))

    out, n_conf, n_unknown = [], 0, 0
    for r in rulings:
        qid = r.get("question_entity_id")
        ruling = r.get("ruling")
        h = hypotheses.get(qid)
        if h is None:
            sys.exit(f"ERROR: ruling names unknown question '{qid}' "
                     f"(not in {hypo_path.name})")
        if ruling == "unknown":
            n_unknown += 1
            continue
        if ruling not in ("confirmed", "reworded"):
            sys.exit(f"ERROR: bad ruling '{ruling}' for {qid}")
        text = (r.get("text") or "").strip()
        if not text:
            sys.exit(f"ERROR: ruling '{ruling}' for {qid} requires text "
                     "(the rationale in the operator's words)")
        if qid in closed:
            print(f"triage-emit: {qid} already closed — skipping (idempotent)")
            continue
        common = {"origin": "backfilled", "actor": args.actor,
                  "confidence": "explicit", "schema_version": "0.4.0"}
        decision = {
            "event_id": str(uuid.uuid4()), "type": "decision", **common,
            "attributes": {
                "backfill_run": args.run_id,
                "text": f"{text} (Recollected by the operator at the {args.run_id} "
                        f"triage pass; the walk's candidates were: {h.get('summary', '')})",
                "event_ids": h["fulcrum_event_ids"],
            },
        }
        close_q = {
            "event_id": str(uuid.uuid4()), "type": "entity.completed", **common,
            "entity_type": "hitl-question", "entity_id": qid,
            "attributes": {
                "backfill_run": args.run_id,
                "summary": f"Answered at triage — rationale recorded as a recollected "
                           f"decision ({decision['event_id']}).",
            },
        }
        out += [decision, close_q]
        n_conf += 1

    if out:
        with open(events_path, "a") as f:
            for e in out:
                f.write(json.dumps(ordered(e)) + "\n")

    archive = data_dir / "archive"
    archive.mkdir(parents=True, exist_ok=True)
    hypo_path.rename(archive / hypo_path.name)

    print(f"triage-emit: {n_conf} recollected decision(s) appended, "
          f"{n_unknown} question(s) left honestly open; hypotheses archived to "
          f"{archive / hypo_path.name}")
    print("triage-emit: now validate, stamp and seal the triage commit per /apv-capture.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
