#!/usr/bin/env python3
"""backfill.py — mine a repo's pre-adoption git history into the event log
(T3-backfill-workflow; doctrine: T2-ingest §3.7, ontology: T2-ontology §3.12).

Walks historical commits oldest-first, runs the extraction agent per commit,
and appends one block per commit to the TARGET repo's live log — honestly:
anchored (seals quote the historical commit and carry its sha), marked
(`origin: "backfilled"` + a run id on every event, so a bad run is
repudiable as a cohort), and never fabricating a Why (recovered rationale
cites its source; everything else becomes candidate hypotheses collected
for the post-walk triage pass — see triage-emit.py).

Usage:
  backfill.py --project-path PATH [options]

Options:
  --project-path PATH    The target repo (its apvlib-resolved data dir is
                         the destination — APV_DATA_DIR / .apv-config.toml
                         / .apv, exactly like every other tool).
  --run-id ID            Cohort id. Default: bf-<today>-<n> (date-embedded).
  --until REF            Mine commits strictly BEFORE this commit. Default:
                         the commit of the log's first seal (found by
                         subject match) — i.e. everything pre-adoption.
                         Empty log: all commits up to HEAD.
  --limit N              Only the most recent N commits of the range (0 = all).
  --chunk-size N         Commit the log to git every N blocks (default 25;
                         0 = never commit — caller handles it).
  --dry-run              Print bundles; no extraction, no writes.
  --resume               Skip commits recorded in backfill-state.json.
  --prompt-path PATH     Extraction prompt (default: sibling
                         extract-commit-prompt.md).
  --actor-override SLUG  Force the actor slug (default: per-commit author).
  --verbose

Halting: ambiguity, parse errors, validation failures and write-rule
violations write <data>/needs-review/<sha>-*.md, save state and exit
non-zero — subsequent runs with --resume continue past repaired commits.
Model: APV_CLAUDE_BIN (default "claude"; tests inject a stub),
APV_EXTRACT_MODEL (--model passthrough), APV_EXTRACT_TIMEOUT (default 600).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import shutil
import sys
import time
import uuid
from datetime import date
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
import apvlib  # noqa: E402

DEFAULT_PROMPT = Path(__file__).resolve().parent / "extract-commit-prompt.md"
SCHEMA_PATH = SCRIPTS.parent / "schemas/0.4.0/events.schema.json"
# Oversize diffs are TRUNCATED with an explicit marker, not halted: unlike
# live capture (which can ask the committer to split), history cannot be
# re-cut, and the complete name-status listing + message keep classification
# viable. Surfaced by the exfu rehearsal staging: release commits with
# bundled artefacts produce ~300k-char diffs.
DIFF_CAP = 120_000
FORBIDDEN_TYPES = {"entity.accepted", "analysis.live-summary", "analysis.invalidated"}
UUID4_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")


def log(msg, verbose=False, force=False):
    if verbose or force:
        print(msg, file=sys.stderr, flush=True)


def git(args, cwd, check=True):
    result = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)
    if check and result.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)} failed: {result.stderr.strip()}")
    return result.stdout


def slugify(text, max_len=24):
    slug = re.sub(r"[^a-z0-9]+", "-", (text or "").lower()).strip("-")
    return slug[:max_len].rstrip("-") or "unknown"


# --------------------------- pre-flight ------------------------------------

def first_sealed_commit(project_path: Path, events_path: Path):
    """The adoption boundary: the commit whose subject matches the log's
    FIRST seal. Backfill mines strictly before it (T2-ingest §3.7 —
    'commits older than the log's first seal'). None when the log is empty
    or holds no seal (mine everything)."""
    first_subject = None
    if events_path.exists():
        with open(events_path) as f:
            for raw in f:
                try:
                    ev = json.loads(raw)
                except json.JSONDecodeError:
                    continue
                if ev.get("type") == "commit.recorded":
                    first_subject = (ev.get("attributes") or {}).get("message_first_line")
                    break
    if not first_subject:
        return None
    out = git(["log", "--format=%H%x00%s"], project_path)
    for line in out.splitlines():
        sha, _, subject = line.partition("\x00")
        if subject == first_subject:
            return sha
    return None


def list_commits(project_path: Path, until: str | None, limit: int) -> list[str]:
    """Chronological (oldest first). `until` exclusive when given."""
    args = ["log", "--reverse", "--format=%H"]
    if until:
        args.append(until)   # ancestors of `until`...
    out = git(args, project_path).strip()
    commits = out.splitlines() if out else []
    if until and commits and commits[-1] == git(["rev-parse", until], project_path).strip():
        commits = commits[:-1]  # strictly before the boundary
    if limit > 0 and len(commits) > limit:
        commits = commits[-limit:]
    return commits


def looks_non_native(project_path: Path) -> bool:
    """Heuristic for the mapping-note warning: a native project has
    planning/<id>.md files matching the tier/milestone id convention."""
    planning = project_path / "planning"
    if not planning.is_dir():
        return True
    pat = re.compile(r"^([A-Z]*T\d|M\d)")
    return not any(pat.match(p.stem) for p in planning.glob("*.md"))


# --------------------------- bundle ----------------------------------------

def commit_meta(project_path: Path, commit_ref: str):
    meta = git(["show", "-s", "--format=%an%n%aI%n%H%n%s", commit_ref], project_path).strip()
    lines = meta.splitlines()
    return {
        "author": lines[0] if len(lines) > 0 else "",
        "date_iso": lines[1] if len(lines) > 1 else "",
        "sha": lines[2] if len(lines) > 2 else commit_ref,
        "subject": lines[3] if len(lines) > 3 else "",
    }


def build_bundle(project_path: Path, commit_ref: str, events_path: Path,
                 mapping_note: str | None) -> str:
    meta = commit_meta(project_path, commit_ref)
    body = git(["show", "-s", "--format=%b", commit_ref], project_path)
    diff = git(["show", "--format=", commit_ref], project_path)
    if len(diff) > DIFF_CAP:
        diff = (diff[:DIFF_CAP]
                + f"\n\n[... diff truncated at {DIFF_CAP} chars of "
                f"{len(diff)} — too large for single-shot extraction; the "
                f"files-touched listing below is COMPLETE; classify from it "
                f"+ the message where the diff is missing ...]")
    name_status = git(["show", "--name-status", "--format=", commit_ref], project_path).strip()

    planning_files = []
    for line in name_status.splitlines():
        parts = line.split("\t")
        for f in parts[1:]:
            if f.startswith("planning/") and f.endswith(".md"):
                try:
                    planning_files.append((parts[0], f, git(["show", f"{commit_ref}:{f}"], project_path)))
                except RuntimeError:
                    pass

    prior = ""
    if events_path.exists():
        lines = events_path.read_text().splitlines()
        head = f"(prior log has {len(lines)} events; showing last 200)\n" if len(lines) > 200 else ""
        prior = head + "\n".join(lines[-200:])

    bundle = (
        f"## Input bundle — historical commit {meta['sha'][:12]}\n\n"
        f"### Commit metadata\n\n"
        f"- commit_hash: {meta['sha']}\n- commit_author: {meta['author']}\n"
        f"- commit_date: {meta['date_iso']}\n- commit_message_first_line: {meta['subject']}\n\n"
        f"### Commit message (full)\n\n```\n{meta['subject']}\n\n{body}```\n\n"
        f"### Files touched\n\n```\n{name_status}\n```\n\n"
        f"### Diff (full)\n\n```diff\n{diff}\n```\n\n"
        f"### Planning files at this commit (post-commit content)\n\n"
    )
    if planning_files:
        for status, path, content in planning_files:
            bundle += f"\n#### {status}  {path}\n\n```markdown\n{content}\n```\n"
    else:
        bundle += "_(none)_\n"
    if mapping_note:
        bundle += f"\n### Retrospective mapping note (the project owner's translation brief)\n\n{mapping_note}\n"
    bundle += "\n### Prior log (earlier events — ids and house style)\n\n"
    bundle += f"```jsonl\n{prior}\n```\n" if prior else "_(empty — first mined commit)_\n"
    return bundle


# --------------------------- extraction ------------------------------------

def invoke_extractor(prompt_text: str, bundle_text: str) -> str:
    claude_bin = os.environ.get("APV_CLAUDE_BIN", "claude")
    timeout = int(os.environ.get("APV_EXTRACT_TIMEOUT", "600"))
    cmd = [claude_bin, "-p", "--output-format", "text"]
    model = os.environ.get("APV_EXTRACT_MODEL")
    if model:
        cmd += ["--model", model]
    result = subprocess.run(
        cmd, input=prompt_text + "\n\n---\n\n" + bundle_text +
        "\n\n---\n\nNow output the JSON array of events for this commit.\n",
        capture_output=True, text=True, timeout=timeout,
    )
    if result.returncode != 0:
        raise RuntimeError(f"extractor invocation failed: {result.stderr.strip()[:400]}")
    return result.stdout


def parse_events(text: str) -> list[dict]:
    s = text.strip()
    s = re.sub(r"^```(json)?\s*", "", s)
    s = re.sub(r"\s*```$", "", s)
    start, end = s.find("["), s.rfind("]")
    if start == -1 or end <= start:
        raise ValueError("no JSON array in extractor response")
    events = json.loads(s[start:end + 1])
    if not isinstance(events, list) or not all(isinstance(e, dict) for e in events):
        raise ValueError("extractor response is not a list of objects")
    if not events:
        raise ValueError("extractor returned an empty block")
    return events


class AmbiguityHalt(Exception):
    def __init__(self, reason, candidates=None, question=None):
        super().__init__(reason)
        self.reason = reason
        self.candidates = candidates or []
        self.question = question or "Repair in-session, then re-run with --resume."


def enforce(events: list[dict], meta: dict, run_id: str, actor: str,
            seen_ids: set) -> list[dict]:
    """Write-side rules in code (mirrors extract-commit.py's stance): the
    orchestrator, not the model, guarantees the block's provenance and seal.
    Returns the block to append; raises on violation."""
    if len(events) == 1 and events[0].get("type") == "ambiguity.halt":
        a = events[0].get("attributes") or {}
        raise AmbiguityHalt(a.get("reason", "extractor declared ambiguity"),
                            a.get("candidate_events"), a.get("needs_human_input"))

    seals = [e for e in events if e.get("type") == "commit.recorded"]
    if len(seals) != 1 or events[-1].get("type") != "commit.recorded":
        raise ValueError("block must contain exactly one commit.recorded, last")

    for e in events:
        t = e.get("type", "")
        if t in FORBIDDEN_TYPES or t == "ambiguity.halt":
            raise ValueError(f"forbidden event type from extractor: {t} "
                             "(entity.accepted is operator-only; write-side rule, not prompt)")
        eid = e.get("event_id", "")
        if not UUID4_RE.match(eid):
            e["event_id"] = eid = str(uuid.uuid4())
        if eid in seen_ids:
            raise ValueError(f"event_id reuse: {eid}")
        seen_ids.add(eid)
        # Provenance is the orchestrator's word, never the model's
        # (T2-ontology §3.12): every event marked, every event repudiable.
        e["origin"] = "backfilled"
        e["confidence"] = "derived"
        e["schema_version"] = "0.4.0"
        e["actor"] = actor
        e["attributes"] = dict(e.get("attributes") or {})
        e["attributes"]["backfill_run"] = run_id

    seal = events[-1]
    seal["attributes"]["commit_ref"] = meta["sha"]
    seal["attributes"]["author"] = slugify(meta["author"])
    seal["attributes"]["date"] = (meta["date_iso"] or "")[:10]
    seal["attributes"]["message_first_line"] = meta["subject"]
    seal.pop("entity_type", None)
    seal.pop("entity_id", None)
    return events


def schema_validate(events: list[dict]):
    try:
        from jsonschema import validate  # type: ignore
    except ImportError:
        raise AmbiguityHalt(
            f"jsonschema not installed for {sys.executable} — backfill fails "
            "closed rather than appending unvalidated events. "
            f"Run: {sys.executable} -m pip install --user jsonschema")
    schema = json.loads(SCHEMA_PATH.read_text())
    for e in events:
        validate(instance=e, schema=schema)


def ordered(e: dict) -> dict:
    keys = ("event_id", "type", "origin", "actor", "confidence",
            "schema_version", "entity_type", "entity_id", "attributes")
    return {k: e[k] for k in keys if k in e}


# --------------------------- side channel + chunking ------------------------

def collect_hypotheses(events: list[dict], meta: dict, hypo_path: Path):
    """Tier-3 stand-ins (hitl-questions carrying fulcrum event_ids) are the
    walk's inline hypotheses — collected for the triage pass, never stopped
    for (T2-ingest §3.7)."""
    entries = []
    for e in events:
        if e.get("type") == "entity.created" and e.get("entity_type") == "hitl-question":
            a = e.get("attributes") or {}
            if a.get("event_ids"):
                entries.append({
                    "question_entity_id": e.get("entity_id"),
                    "fulcrum_event_ids": a["event_ids"],
                    "summary": a.get("summary", ""),
                    "commit_ref": meta["sha"],
                    "commit_subject": meta["subject"],
                    "commit_date": (meta["date_iso"] or "")[:10],
                })
    if entries:
        hypo_path.parent.mkdir(parents=True, exist_ok=True)
        with open(hypo_path, "a") as f:
            for entry in entries:
                f.write(json.dumps(entry) + "\n")
    return len(entries)


def commit_chunk(project_path: Path, data_dir: Path, run_id: str,
                 first_sha: str, last_sha: str, n_blocks: int):
    rel = os.path.relpath(data_dir, project_path)
    git(["add", rel], project_path)
    (data_dir / ".last-capture").write_text(f"{int(time.time())}\n")
    msg = f"backfill({run_id}): commits {first_sha[:7]}..{last_sha[:7]}, {n_blocks} blocks"
    git(["commit", "-m", msg], project_path)
    return msg


def write_needs_review(data_dir: Path, sha: str, kind: str, body: str) -> Path:
    d = data_dir / "needs-review"
    d.mkdir(parents=True, exist_ok=True)
    p = d / f"{sha[:8]}-{kind}.md"
    p.write_text(body)
    return p


# --------------------------- state ------------------------------------------

def save_state(state_path: Path, state: dict):
    state_path.parent.mkdir(parents=True, exist_ok=True)
    state_path.write_text(json.dumps(state, indent=2))


def load_state(state_path: Path) -> dict:
    if state_path.exists():
        return json.loads(state_path.read_text())
    return {}


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--project-path", required=True, type=Path)
    ap.add_argument("--run-id", default=None)
    ap.add_argument("--until", default=None)
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--chunk-size", type=int, default=25)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--resume", action="store_true")
    ap.add_argument("--prompt-path", type=Path, default=DEFAULT_PROMPT)
    ap.add_argument("--actor-override", default=None)
    ap.add_argument("--verbose", "-v", action="store_true")
    args = ap.parse_args()

    project_path = args.project_path.resolve()
    if not (project_path / ".git").exists():
        sys.exit(f"ERROR: {project_path} is not a git repo")

    data_dir = apvlib.apv_data_dir(project_path)
    events_path = data_dir / "events.jsonl"
    if not events_path.exists():
        sys.exit(f"ERROR: no events.jsonl in {data_dir} — attach the repo first "
                 "(/apv-init); backfill appends to a live log, it does not create one.")

    run_id = args.run_id or f"bf-{date.today().isoformat()}-a"
    state_path = data_dir / "backfill-state.json"
    hypo_path = data_dir / "needs-review" / f"hypotheses-{run_id}.jsonl"
    state = load_state(state_path) if args.resume else {}
    processed = set(state.get("processed_commits", []))

    # Mapping note (T3-retrospective-mapping-template §2.3): included in the
    # brief verbatim when present; its absence on a non-native-looking repo
    # is a warning, never a block.
    mapping_note = None
    note_path = data_dir / "retrospective-mapping.md"
    if note_path.exists():
        mapping_note = note_path.read_text()
        log(f"mapping note: {note_path}", force=True)
    elif looks_non_native(project_path):
        log("WARNING: no retrospective-mapping.md and the project does not look "
            "native to the T1/T2/T3 convention — extraction quality will suffer. "
            f"Author one at {note_path} (template: retrospective-mapping-template.md).",
            force=True)

    prompt_text = args.prompt_path.read_text()
    claude_bin = os.environ.get("APV_CLAUDE_BIN", "claude")
    if not args.dry_run and not shutil.which(claude_bin):
        sys.exit(f"ERROR: {claude_bin} CLI not found on PATH (use --dry-run to inspect)")

    until = args.until or first_sealed_commit(project_path, events_path)
    commits = list_commits(project_path, until, args.limit)
    if not commits:
        log("nothing to mine — no commits before the adoption boundary", force=True)
        return

    boundary = until[:8] if until else "HEAD (empty-log mine-all)"
    log(f"run {run_id}: {len(commits)} commit(s) before boundary {boundary}", force=True)

    seen_ids = set()
    if events_path.exists():
        for line in events_path.read_text().splitlines():
            m = re.search(r'"event_id":\s*"([^"]+)"', line)
            if m:
                seen_ids.add(m.group(1))

    chunk_first = None
    chunk_count = 0
    n_hypo = 0
    for i, commit_ref in enumerate(commits, start=1):
        if commit_ref in processed:
            log(f"  [{i}/{len(commits)}] {commit_ref[:8]}  SKIP (processed)", force=True)
            continue
        meta = commit_meta(project_path, commit_ref)
        bundle = build_bundle(project_path, commit_ref, events_path, mapping_note)

        if args.dry_run:
            print(f"\n{'=' * 80}\n=== DRY-RUN bundle {commit_ref[:8]} ({len(bundle)} chars) ===\n")
            print(bundle[:3000])
            if len(bundle) > 3000:
                print(f"... [{len(bundle) - 3000} chars truncated]")
            continue

        log(f"  [{i}/{len(commits)}] {commit_ref[:8]}  extracting ({len(bundle)} chars)...", force=True)
        t0 = time.time()
        raw = ""
        try:
            raw = invoke_extractor(prompt_text, bundle)
            events = parse_events(raw)
            actor = args.actor_override or slugify(meta["author"])
            events = enforce(events, meta, run_id, actor, seen_ids)
            schema_validate(events)
        except AmbiguityHalt as h:
            p = write_needs_review(
                data_dir, commit_ref, "ambiguity",
                f"# Backfill halt — {meta['subject']}\n\nCommit: {commit_ref}\n\n"
                f"Reason: {h.reason}\n\nNeeds human input: {h.question}\n\n"
                f"Candidates:\n\n```json\n{json.dumps(h.candidates, indent=2)}\n```\n")
            save_state(state_path, {"run_id": run_id,
                                    "processed_commits": sorted(processed),
                                    "last_halt": commit_ref})
            sys.exit(f"HALT at {commit_ref[:8]} — see {p}; repair, then --resume")
        except Exception as ex:
            p = write_needs_review(
                data_dir, commit_ref, "rejected",
                f"# Backfill rejected — {meta['subject']}\n\nCommit: {commit_ref}\n\n"
                f"Reason: {ex}\n\nRaw response:\n\n```\n{raw[:8000]}\n```\n")
            save_state(state_path, {"run_id": run_id,
                                    "processed_commits": sorted(processed),
                                    "last_failed": commit_ref})
            sys.exit(f"REJECTED at {commit_ref[:8]} — {ex}; see {p}; repair, then --resume")

        with open(events_path, "a") as f:
            for e in events:
                f.write(json.dumps(ordered(e)) + "\n")
        n_hypo += collect_hypotheses(events, meta, hypo_path)
        processed.add(commit_ref)
        chunk_first = chunk_first or commit_ref
        chunk_count += 1
        save_state(state_path, {"run_id": run_id, "processed_commits": sorted(processed)})
        log(f"  [{i}/{len(commits)}] {commit_ref[:8]}  OK ({len(events)} events, "
            f"{time.time() - t0:.1f}s)", force=True)

        if args.chunk_size > 0 and chunk_count >= args.chunk_size:
            msg = commit_chunk(project_path, data_dir, run_id, chunk_first, commit_ref, chunk_count)
            log(f"  chunk committed: {msg}", force=True)
            chunk_first, chunk_count = None, 0

    if not args.dry_run and args.chunk_size > 0 and chunk_count > 0:
        msg = commit_chunk(project_path, data_dir, run_id, chunk_first, commits[-1], chunk_count)
        log(f"  final chunk committed: {msg}", force=True)

    if not args.dry_run:
        log(f"\nrun {run_id} complete — {len(processed)} commit(s) mined; "
            f"{n_hypo} hypothesis(es) queued for /apv-triage-why"
            + (f" at {hypo_path}" if n_hypo else ""), force=True)


if __name__ == "__main__":
    main()
