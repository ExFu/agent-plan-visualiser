#!/usr/bin/env python3
"""extract-commit.py — autonomous capture orchestrator (T3-autonomous-extractor).

Invoked by the commit-msg hook (hooks/extract-capture.sh) for commits no
session agent captured. Assembles the input bundle for the staged commit,
invokes `claude -p` with scripts/extract-live-prompt.md, then enforces the
write-side rules IN CODE (never trusting the model):

  - exactly one commit.recorded seal, last, with ground-truth author/date/
    message_first_line substituted from git regardless of model output;
  - entity.accepted and analysis.* are unconditionally rejected;
  - no implementation events against draft entities (implicit-work
    same-block carve-out honoured) and no resurrection of closed entities
    without an in-block entity.reopened;
  - fulcrum events must be referenced by an in-block decision;
  - fresh, unique, well-formed UUID v4 event_ids;
  - JSON-Schema validation against schemas/0.3.0/events.schema.json;
  - the whole block is stamped as autonomous: confidence forced to
    "derived" (T3 §6 Q3 ruling) and actor set from the commit author.

Clean: append the block, `git add` the log, write .last-capture, exit 0.
Ambiguous or invalid: write <data>/needs-review/<slug>.md, exit 1 (commit
blocked; the operator resolves in-session).

Env: APV_CLAUDE_BIN (default "claude"; tests inject a stub),
APV_EXTRACT_MODEL (optional --model passthrough — T3 §6 Q2 resolves
empirically), APV_EXTRACT_TIMEOUT (seconds, default 240), APV_DATA_DIR
(as everywhere). Stdlib + optional jsonschema (halts closed if missing).
"""

import argparse
import json
import os
import re
import subprocess
import sys
import time
import uuid
from datetime import date
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPTS))
import apvlib  # noqa: E402

DIFF_CAP = 80_000          # chars; beyond this we halt (no sub-agent recursion in the first cut)
LOG_TAIL_LINES = 200
FORBIDDEN_TYPES = {"entity.accepted", "analysis.live-summary", "analysis.invalidated"}
FULCRUM_TYPES = {"entity.renamed", "entity.parked", "entity.cancelled",
                 "entity.superseded", "entity.reopened"}
IMPLEMENTATION_TYPES = {"entity.progressed", "entity.completed"}
# Mirrors cache-build's state machine closely enough for write-side gating.
STATE_FROM_EVENT = {
    "entity.created": "draft",
    "entity.accepted": "live",
    "entity.progressed": "live",
    "entity.reopened": "live",
    "entity.parked": "dormant",
    "entity.completed": "closed",
    "entity.cancelled": "closed",
    "entity.superseded": "closed",
}
UUID4_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")


def git(args, cwd, check=True):
    r = subprocess.run(["git"] + args, cwd=cwd, capture_output=True, text=True)
    if check and r.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)}: {r.stderr.strip()}")
    return r.stdout


def slugify(text, max_len=40):
    slug = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    return slug[:max_len].rstrip("-") or "commit"


def replay_states(log_path: Path) -> dict:
    """Derive each entity's current state from the log (rename-aware enough:
    identity migrations are folded last-write-wins on entity_id)."""
    states = {}
    renames = {}
    if not log_path.exists():
        return states
    with open(log_path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                e = json.loads(line)
            except json.JSONDecodeError:
                continue
            eid = e.get("entity_id")
            etype = e.get("type")
            if etype == "entity.renamed":
                frm = (e.get("attributes") or {}).get("from_name")
                to = (e.get("attributes") or {}).get("to_name")
                if frm and to and frm in states:
                    states[to] = states.pop(frm)
                    renames[frm] = to
                continue
            if not eid:
                continue
            eid = renames.get(eid, eid)
            if etype == "entity.extended":
                # draft-preserving; from any other state -> live
                if states.get(eid) != "draft":
                    states[eid] = "live"
                continue
            if etype in STATE_FROM_EVENT:
                states[eid] = STATE_FROM_EVENT[etype]
    return states


def existing_event_ids(log_path: Path) -> set:
    ids = set()
    if log_path.exists():
        with open(log_path) as f:
            for line in f:
                m = re.search(r'"event_id":\s*"([^"]+)"', line)
                if m:
                    ids.add(m.group(1))
    return ids


def build_bundle(repo_root: Path, data_dir: Path, msg_text: str) -> str:
    staged_names = git(["diff", "--cached", "--name-only"], repo_root).strip()
    diff = git(["diff", "--cached", "--unified=3"], repo_root)
    if len(diff) > DIFF_CAP:
        raise AmbiguityHalt(
            f"staged diff is {len(diff)} chars (cap {DIFF_CAP}) — too large for "
            "single-shot extraction; capture in-session or split the commit "
            "(sub-agent recursion is deliberately out of the first cut).")

    tail = ""
    log_path = data_dir / "events.jsonl"
    if log_path.exists():
        lines = log_path.read_text().splitlines()
        tail = "\n".join(lines[-LOG_TAIL_LINES:])

    frontmatters = []
    for name in staged_names.splitlines():
        if re.match(r"^planning/[^/]+\.md$", name):
            try:
                content = git(["show", f":0:{name}"], repo_root)
            except RuntimeError:
                continue  # staged deletion
            m = re.match(r"^---\n(.*?)\n---\n", content, re.S)
            if m:
                frontmatters.append(f"--- {name} frontmatter ---\n{m.group(1)}")

    return (
        f"## Commit message\n\n{msg_text}\n\n"
        f"## Staged files\n\n{staged_names}\n\n"
        f"## Staged diff\n\n{diff}\n\n"
        f"## Event log tail (last {LOG_TAIL_LINES} lines; house style + current entity ids)\n\n{tail}\n\n"
        f"## Touched planning frontmatter\n\n" + ("\n\n".join(frontmatters) or "(none)") + "\n"
    )


class AmbiguityHalt(Exception):
    def __init__(self, reason, candidates=None, question=None):
        super().__init__(reason)
        self.reason = reason
        self.candidates = candidates or []
        self.question = question or "Review and capture in-session (/apv-capture), then commit."


def invoke_model(prompt: str, bundle: str) -> str:
    claude_bin = os.environ.get("APV_CLAUDE_BIN", "claude")
    timeout = int(os.environ.get("APV_EXTRACT_TIMEOUT", "240"))
    cmd = [claude_bin, "-p", "--output-format", "text"]
    model = os.environ.get("APV_EXTRACT_MODEL")
    if model:
        cmd += ["--model", model]
    r = subprocess.run(cmd, input=prompt + "\n\n# INPUT BUNDLE\n\n" + bundle,
                       capture_output=True, text=True, timeout=timeout)
    if r.returncode != 0:
        raise RuntimeError(f"extractor invocation failed: {r.stderr.strip()[:400]}")
    return r.stdout


def parse_events(text: str) -> list:
    t = text.strip()
    t = re.sub(r"^```(json)?\s*", "", t)
    t = re.sub(r"\s*```$", "", t)
    start, end = t.find("["), t.rfind("]")
    if start == -1 or end <= start:
        raise ValueError("no JSON array in extractor response")
    events = json.loads(t[start:end + 1])
    if not isinstance(events, list) or not all(isinstance(e, dict) for e in events):
        raise ValueError("extractor response is not a list of objects")
    if not events:
        raise ValueError("extractor returned an empty block")
    return events


def enforce(events: list, msg_text: str, actor: str, data_dir: Path) -> list:
    """Write-side rules, in code. Returns the block to append (may rewrite
    ground-truth fields); raises AmbiguityHalt / ValueError on violation."""
    if len(events) == 1 and events[0].get("type") == "ambiguity.halt":
        a = events[0].get("attributes") or {}
        raise AmbiguityHalt(a.get("reason", "extractor declared ambiguity"),
                            a.get("candidate_events"), a.get("needs_human_input"))

    for e in events:
        t = e.get("type", "")
        if t in FORBIDDEN_TYPES or t == "ambiguity.halt":
            raise ValueError(f"forbidden event type from extractor: {t} "
                             "(entity.accepted is operator-only; write-side rule, not prompt)")

    seals = [e for e in events if e.get("type") == "commit.recorded"]
    if len(seals) != 1 or events[-1].get("type") != "commit.recorded":
        raise ValueError("block must contain exactly one commit.recorded, last")

    seen_ids = existing_event_ids(data_dir / "events.jsonl")
    states = replay_states(data_dir / "events.jsonl")
    block_created = set()
    fulcrum_ids = {}
    decision_refs = set()

    for e in events:
        eid = e.get("event_id", "")
        if not UUID4_RE.match(eid):
            e["event_id"] = eid = str(uuid.uuid4())
        if eid in seen_ids:
            raise ValueError(f"event_id reuse: {eid}")
        seen_ids.add(eid)

        # The whole block is autonomous: T3 §6 Q3 — derived, actor = author.
        e["confidence"] = "derived"
        e["actor"] = actor
        e["schema_version"] = "0.3.0"

        t = e.get("type", "")
        ent = e.get("entity_id")
        if t == "decision":
            decision_refs.update((e.get("attributes") or {}).get("event_ids") or [])
        if t in FULCRUM_TYPES:
            fulcrum_ids[e["event_id"]] = t
        if t == "entity.created" and ent:
            block_created.add((e.get("entity_type"), ent))
            states[ent] = "draft"
        elif t in IMPLEMENTATION_TYPES and ent:
            state = states.get(ent)
            if state == "closed":
                raise ValueError(f"resurrection: {t} against closed entity {ent} "
                                 "without entity.reopened")
            if state == "draft":
                # Draft gate: only the implicit-work created-in-this-block
                # carve-out passes through draft transiently by design.
                carve_out = (e.get("entity_type") == "implicit-work"
                             and ("implicit-work", ent) in block_created)
                if not carve_out:
                    raise ValueError(f"draft gate: {t} against draft entity {ent} "
                                     "(acceptance is operator-only; capture in-session)")
            states[ent] = STATE_FROM_EVENT[t]
        elif t in STATE_FROM_EVENT and ent:
            states[ent] = STATE_FROM_EVENT[t]
        elif t == "entity.extended" and ent and states.get(ent) != "draft":
            states[ent] = "live"

    unexplained = [t for eid, t in fulcrum_ids.items() if eid not in decision_refs]
    if unexplained:
        raise ValueError(f"fulcrum event(s) without paired decision: {unexplained}")

    # Ground truth on the seal — never the model's word.
    seal = events[-1]
    seal["attributes"] = dict(seal.get("attributes") or {})
    seal["attributes"]["message_first_line"] = msg_text.splitlines()[0].strip()
    seal["attributes"]["author"] = actor
    seal["attributes"]["date"] = date.today().isoformat()
    seal.pop("entity_type", None)
    seal.pop("entity_id", None)

    return events


def schema_validate(events: list):
    schema_path = SCRIPTS.parent / "schemas" / "0.3.0" / "events.schema.json"
    try:
        from jsonschema import validate  # type: ignore
    except ImportError:
        raise AmbiguityHalt(
            f"jsonschema not installed for {sys.executable} — the extractor "
            "fails closed rather than appending unvalidated events. "
            f"Run: {sys.executable} -m pip install --user jsonschema")
    schema = json.loads(schema_path.read_text())
    for e in events:
        validate(instance=e, schema=schema)


def write_needs_review(data_dir: Path, msg_text: str, reason: str,
                       candidates=None, raw: str = "", question: str = ""):
    d = data_dir / "needs-review"
    d.mkdir(parents=True, exist_ok=True)
    slug = slugify(msg_text.splitlines()[0] if msg_text else "commit")
    path = d / f"{date.today().isoformat()}-{slug}.md"
    body = [f"# Autonomous capture halted — {slug}", "",
            f"**Commit message (first line)**: {msg_text.splitlines()[0] if msg_text else '(empty)'}",
            f"**Reason**: {reason}", ""]
    if question:
        body += [f"**Needs human input**: {question}", ""]
    if candidates:
        body += ["## Candidate events (extractor's best guess — NOT appended)", "",
                 "```json", json.dumps(candidates, indent=2), "```", ""]
    if raw:
        body += ["## Raw extractor response", "", "```", raw[:8000], "```", ""]
    body += ["## Next steps", "",
             "Resolve in-session: run /apv-capture to record this work properly, "
             "then re-run the commit. Or `git commit --no-verify` if this is "
             "genuinely capture-free trivia.", ""]
    path.write_text("\n".join(body))
    return path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--msg-file", required=True)
    ap.add_argument("--repo-root", default=None)
    args = ap.parse_args()

    repo_root = Path(args.repo_root or git(["rev-parse", "--show-toplevel"], Path.cwd()).strip())
    data_dir = apvlib.apv_data_dir(repo_root)
    msg_text = Path(args.msg_file).read_text()
    # Comment lines never reach the recorded message.
    msg_text = "\n".join(l for l in msg_text.splitlines() if not l.startswith("#")).strip()
    if not msg_text:
        print("apv-extract: empty commit message; nothing to seal", file=sys.stderr)
        return 1

    author = git(["config", "user.name"], repo_root).strip() or "unknown"
    actor = slugify(author, 24)

    raw = ""
    try:
        bundle = build_bundle(repo_root, data_dir, msg_text)
        prompt = (SCRIPTS / "extract-live-prompt.md").read_text()
        raw = invoke_model(prompt, bundle)
        events = parse_events(raw)
        events = enforce(events, msg_text, actor, data_dir)
        schema_validate(events)
    except AmbiguityHalt as h:
        p = write_needs_review(data_dir, msg_text, h.reason, h.candidates, raw, h.question)
        print(f"apv-extract: HALT — {h.reason}\napv-extract: see {p}", file=sys.stderr)
        return 1
    except Exception as ex:  # validation failures, model errors — fail closed
        p = write_needs_review(data_dir, msg_text, str(ex), raw=raw)
        print(f"apv-extract: REJECTED — {ex}\napv-extract: see {p}", file=sys.stderr)
        return 1

    log_path = data_dir / "events.jsonl"
    with open(log_path, "a") as f:
        for e in events:
            ordered = {k: e[k] for k in
                       ("event_id", "type", "actor", "confidence", "schema_version",
                        "entity_type", "entity_id", "attributes") if k in e}
            f.write(json.dumps(ordered) + "\n")
    rel = os.path.relpath(log_path, repo_root)
    git(["add", rel], repo_root)
    (data_dir / ".last-capture").write_text(f"{int(time.time())}\n")
    print(f"apv-extract: appended {len(events)} autonomous events (sealed: "
          f"{events[-1]['attributes']['message_first_line']!r})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
