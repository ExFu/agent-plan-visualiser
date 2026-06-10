#!/usr/bin/env python3
"""One-shot migration: events.jsonl schema_version 0.0.0-prehistoric -> 0.1.0.

Only the schema_version field is touched; all other fields preserved verbatim.
Run once; subsequent runs are idempotent (already-0.1.0 events untouched).
"""
import json
from pathlib import Path

EVENTS_FILE = Path(__file__).resolve().parents[2] / ".agent-plan-tracker/events.jsonl"


def main():
    with open(EVENTS_FILE) as f:
        lines = [json.loads(l) for l in f]

    migrated = 0
    for ev in lines:
        if ev.get("schema_version") == "0.0.0-prehistoric":
            ev["schema_version"] = "0.1.0"
            migrated += 1

    with open(EVENTS_FILE, "w") as f:
        for ev in lines:
            f.write(json.dumps(ev, separators=(",", ":")) + "\n")

    print(f"migrated {migrated} events to schema_version 0.1.0")


if __name__ == "__main__":
    main()
