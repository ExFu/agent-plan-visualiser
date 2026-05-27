#!/usr/bin/env python3
"""Backfill orchestrator — walks git history of a target project, runs the
per-commit extraction agent on each commit, appends events to the target's
.agent-plan-tracker/events.jsonl.

Usage:
  backfill.py --project-path PATH [options]

Options:
  --project-path PATH    Absolute path to the target project's git repo.
  --output PATH          Path to write events.jsonl. Default:
                         <project-path>/.agent-plan-tracker/events.jsonl
  --limit N              Only process the most recent N commits. Default: 20.
  --from-commit REF      Start from this commit (exclusive). Walks forward.
  --dry-run              Build input bundles + print to stdout; do not call Claude.
  --prompt-path PATH     Path to extraction prompt. Default: sibling extract-commit-prompt.md
  --schema-path PATH     Path to events.schema.json. Default: plugin's bundled schema.
  --resume               Resume from .agent-plan-tracker/backfill-state.json if present.
  --verbose              Verbose logging.

Behaviour:
  - Walks commits in chronological order (oldest -> newest) within the chosen range.
  - For each commit: builds bundle (diff, message, touched planning files, prior log
    delta), invokes claude CLI (unless --dry-run), validates returned events,
    appends to events.jsonl.
  - On ambiguity.halt or validation failure: writes a needs-review file, saves state,
    exits non-zero with instructions.
  - Resumability: state lives in <output-dir>/backfill-state.json.

Requires: claude CLI on PATH (unless --dry-run). Python 3 stdlib only.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

DEFAULT_PROMPT = Path(__file__).resolve().parent / "extract-commit-prompt.md"
DEFAULT_SCHEMA = Path(__file__).resolve().parents[2] / "schemas/0.1.0/events.schema.json"


def log(msg, verbose=False, force=False):
    if verbose or force:
        print(msg, file=sys.stderr, flush=True)


def git(args, cwd, capture=True):
    result = subprocess.run(
        ["git", *args],
        cwd=cwd,
        capture_output=capture,
        text=True,
        check=False,
    )
    if result.returncode != 0 and capture:
        raise RuntimeError(f"git {' '.join(args)} failed: {result.stderr.strip()}")
    return result.stdout if capture else None


def list_commits(project_path: Path, limit: int, from_commit: str | None) -> list[str]:
    """Return commits in chronological order (oldest first), most recent `limit` of them."""
    args = ["log", "--reverse", "--format=%H"]
    if from_commit:
        args.append(f"{from_commit}..HEAD")
    out = git(args, project_path).strip()
    commits = out.splitlines() if out else []
    if limit > 0 and len(commits) > limit:
        commits = commits[-limit:]
    return commits


def build_bundle(project_path: Path, commit_ref: str, prior_log_path: Path | None, verbose=False) -> str:
    """Construct the input bundle the extraction agent sees for one commit."""
    # Commit metadata
    meta = git(
        ["show", "-s", "--format=%an%n%aI%n%H%n%s%n----BODY----%n%b", commit_ref],
        project_path,
    ).strip()
    parts = meta.split("\n----BODY----\n", 1)
    head = parts[0].splitlines()
    author = head[0] if len(head) > 0 else ""
    date_iso = head[1] if len(head) > 1 else ""
    full_hash = head[2] if len(head) > 2 else commit_ref
    message_first_line = head[3] if len(head) > 3 else ""
    body = parts[1] if len(parts) > 1 else ""

    # Diff (full)
    diff = git(["show", "--format=", commit_ref], project_path)

    # List of files touched
    name_status = git(
        ["show", "--name-status", "--format=", commit_ref],
        project_path,
    ).strip()

    # Planning files touched: read their new content (post-commit)
    planning_files_content = []
    for line in name_status.splitlines():
        if not line.strip():
            continue
        parts2 = line.split("\t")
        status = parts2[0]
        files = parts2[1:]
        for f in files:
            if f.startswith("planning/") and f.endswith(".md"):
                try:
                    content = git(["show", f"{commit_ref}:{f}"], project_path)
                    planning_files_content.append((status, f, content))
                except RuntimeError:
                    # File doesn't exist at this commit (e.g. deleted) — skip
                    pass

    # Prior log delta — for now, pass the full prior log if exists, capped
    prior_log_excerpt = ""
    if prior_log_path and prior_log_path.exists():
        try:
            with open(prior_log_path) as f:
                lines = f.readlines()
            if len(lines) > 200:
                prior_log_excerpt = (
                    f"(prior log has {len(lines)} events; showing last 200)\n"
                    + "".join(lines[-200:])
                )
            else:
                prior_log_excerpt = "".join(lines)
        except OSError:
            prior_log_excerpt = ""

    bundle = f"""## Input bundle — commit {full_hash[:12]}

### Commit metadata

- commit_hash: {full_hash}
- commit_author: {author}
- commit_date: {date_iso}
- commit_message_first_line: {message_first_line}

### Commit message (full)

```
{message_first_line}

{body}
```

### Files touched (status, path)

```
{name_status}
```

### Diff (full)

```diff
{diff}
```

### Planning files at this commit (post-commit content)

"""
    if planning_files_content:
        for status, path, content in planning_files_content:
            bundle += f"\n#### {status}  {path}\n\n```markdown\n{content}\n```\n"
    else:
        bundle += "\n_(none — commit touches no `planning/` files)_\n"

    bundle += "\n### Prior log (events extracted from earlier commits)\n\n"
    if prior_log_excerpt:
        bundle += f"```jsonl\n{prior_log_excerpt}```\n"
    else:
        bundle += "_(empty — this is the bootstrap commit)_\n"

    return bundle


def invoke_extractor(prompt_text: str, bundle_text: str, claude_bin: str = "claude") -> str:
    """Run `claude -p <full_prompt>` and return its stdout."""
    full_prompt = (
        prompt_text
        + "\n\n---\n\n"
        + bundle_text
        + "\n\n---\n\nNow output the JSON array of events for this commit.\n"
    )
    # Pass via stdin to avoid shell-arg-length limits
    result = subprocess.run(
        [claude_bin, "-p", "--output-format", "text"],
        input=full_prompt,
        capture_output=True,
        text=True,
        timeout=600,
    )
    if result.returncode != 0:
        raise RuntimeError(f"claude CLI failed: {result.stderr.strip()}")
    return result.stdout


def parse_events_response(text: str) -> list[dict]:
    """Extract JSON array from response, tolerating optional markdown fences."""
    s = text.strip()
    if s.startswith("```"):
        # Strip fences
        first_newline = s.find("\n")
        if first_newline > 0:
            s = s[first_newline + 1:]
        if s.rstrip().endswith("```"):
            s = s.rstrip()[: -3].rstrip()
    return json.loads(s)


def validate_events(events: list[dict], schema_path: Path) -> list[str]:
    """Returns a list of error messages; empty list means valid."""
    try:
        from jsonschema import validate, ValidationError
    except ImportError:
        return [
            f"jsonschema not available for {sys.executable}. "
            f"Run: {sys.executable} -m pip install --user jsonschema"
        ]
    with open(schema_path) as f:
        schema = json.load(f)
    errors = []
    for i, ev in enumerate(events):
        if ev.get("type") == "ambiguity.halt":
            continue  # not a real ontology event
        try:
            validate(instance=ev, schema=schema)
        except ValidationError as e:
            errors.append(f"event[{i}] ({ev.get('event_id', '?')}): {e.message}")
    return errors


def is_ambiguity_halt(events: list[dict]) -> bool:
    return len(events) == 1 and events[0].get("type") == "ambiguity.halt"


def save_state(state_path: Path, state: dict):
    state_path.parent.mkdir(parents=True, exist_ok=True)
    state_path.write_text(json.dumps(state, indent=2))


def load_state(state_path: Path) -> dict:
    if state_path.exists():
        return json.loads(state_path.read_text())
    return {}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--project-path", required=True, type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--limit", type=int, default=20)
    parser.add_argument("--from-commit", type=str, default=None)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--prompt-path", type=Path, default=DEFAULT_PROMPT)
    parser.add_argument("--schema-path", type=Path, default=DEFAULT_SCHEMA)
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--verbose", "-v", action="store_true")
    parser.add_argument("--claude-bin", default="claude")
    args = parser.parse_args()

    project_path = args.project_path.resolve()
    if not (project_path / ".git").exists():
        sys.exit(f"ERROR: {project_path} is not a git repo")

    output_path = args.output or (project_path / ".agent-plan-tracker/events.jsonl")
    output_path.parent.mkdir(parents=True, exist_ok=True)

    state_path = output_path.parent / "backfill-state.json"
    state = load_state(state_path) if args.resume else {}
    processed_commits = set(state.get("processed_commits", []))

    if not args.prompt_path.exists():
        sys.exit(f"ERROR: prompt file not found: {args.prompt_path}")
    prompt_text = args.prompt_path.read_text()

    if not args.dry_run and not shutil.which(args.claude_bin):
        sys.exit(f"ERROR: {args.claude_bin} CLI not found on PATH (use --dry-run to skip)")

    commits = list_commits(project_path, args.limit, args.from_commit)
    if not commits:
        log("no commits to process", force=True)
        return

    log(f"processing {len(commits)} commits ({commits[0][:8]} -> {commits[-1][:8]})", force=True)

    for i, commit_ref in enumerate(commits, start=1):
        if commit_ref in processed_commits:
            log(f"  [{i}/{len(commits)}] {commit_ref[:8]}  SKIP (already processed)", force=True)
            continue
        log(f"  [{i}/{len(commits)}] {commit_ref[:8]}  building bundle...", force=True)

        bundle = build_bundle(project_path, commit_ref, output_path if output_path.exists() else None, args.verbose)

        if args.dry_run:
            print(f"\n{'=' * 80}\n=== DRY-RUN: bundle for {commit_ref[:8]} ({len(bundle)} chars) ===\n{'=' * 80}\n")
            print(bundle[:3000])
            if len(bundle) > 3000:
                print(f"\n... [{len(bundle) - 3000} more chars truncated in dry-run preview]")
            print()
            continue

        log(f"  [{i}/{len(commits)}] {commit_ref[:8]}  invoking extractor ({len(bundle)} chars)...", force=True)
        t0 = time.time()
        try:
            response = invoke_extractor(prompt_text, bundle, args.claude_bin)
        except subprocess.TimeoutExpired:
            log(f"  TIMEOUT on commit {commit_ref}", force=True)
            save_state(state_path, {"processed_commits": list(processed_commits), "last_failed": commit_ref})
            sys.exit(2)
        elapsed = time.time() - t0

        try:
            events = parse_events_response(response)
        except json.JSONDecodeError as e:
            log(f"  PARSE ERROR for commit {commit_ref}: {e}", force=True)
            review_path = output_path.parent / f"needs-review/{commit_ref[:8]}-parse-error.md"
            review_path.parent.mkdir(parents=True, exist_ok=True)
            review_path.write_text(f"# Parse error\n\nCommit: {commit_ref}\n\nResponse:\n\n```\n{response}\n```\n")
            save_state(state_path, {"processed_commits": list(processed_commits), "last_failed": commit_ref})
            sys.exit(3)

        if is_ambiguity_halt(events):
            log(f"  AMBIGUITY HALT on commit {commit_ref}", force=True)
            halt = events[0]["attributes"]
            review_path = output_path.parent / f"needs-review/{commit_ref[:8]}-ambiguity.md"
            review_path.parent.mkdir(parents=True, exist_ok=True)
            review_path.write_text(
                f"# Ambiguity halt\n\nCommit: {commit_ref}\n\n"
                f"Reason: {halt.get('reason')}\n\n"
                f"Needs human input: {halt.get('needs_human_input')}\n\n"
                f"Candidate events (if you want to proceed):\n\n```json\n{json.dumps(halt.get('candidate_events', []), indent=2)}\n```\n"
            )
            save_state(state_path, {"processed_commits": list(processed_commits), "last_halt": commit_ref})
            sys.exit(4)

        errors = validate_events(events, args.schema_path)
        if errors:
            log(f"  VALIDATION FAILED for commit {commit_ref}: {len(errors)} errors", force=True)
            review_path = output_path.parent / f"needs-review/{commit_ref[:8]}-validation.md"
            review_path.parent.mkdir(parents=True, exist_ok=True)
            review_path.write_text(
                f"# Validation failed\n\nCommit: {commit_ref}\n\n"
                f"Errors:\n\n" + "\n".join(f"- {e}" for e in errors) + "\n\n"
                f"Response:\n\n```json\n{json.dumps(events, indent=2)}\n```\n"
            )
            save_state(state_path, {"processed_commits": list(processed_commits), "last_failed": commit_ref})
            sys.exit(5)

        with open(output_path, "a") as f:
            for ev in events:
                f.write(json.dumps(ev, separators=(",", ":")) + "\n")

        processed_commits.add(commit_ref)
        save_state(state_path, {"processed_commits": list(processed_commits)})
        log(f"  [{i}/{len(commits)}] {commit_ref[:8]}  OK ({len(events)} events, {elapsed:.1f}s)", force=True)

    log(f"\ndone — {len(processed_commits)} commits processed, events in {output_path}", force=True)


if __name__ == "__main__":
    main()
