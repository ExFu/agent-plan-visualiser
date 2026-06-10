#!/usr/bin/env bash
# gate-check.sh — the single boundary contract (T3-gate-core §2.1).
#
# Answers "can main trust this state?" by running two halves:
#   1. The integrity composite (gate-composite.py) — log-only, no git.
#   2. The seal↔commit correspondence check — every *committed*
#      `commit.recorded` seal's message_first_line must match the subject
#      line of a commit reachable from the checked ref. This is the
#      git-aware half T3-integrity-composite §6 Q1 assigned here: the
#      boundary context owns git; the composite stays log-only.
#      Matching is by message, not SHA — the log is rebase-tolerant by
#      design; what this catches is squash/reword orphaning the record.
#      Direction is log→git only: commits without seals are sanctioned
#      (`git commit --no-verify` capture-free trivia).
#      Epoch-gated like the composite's replay-semantics checks, keyed on
#      the SEAL's own schema_version: the exact-match discipline arrived
#      with 0.3.0 (/apt-capture seals quote the commit's first line);
#      earlier hand-written seals were loose summaries judged by their own
#      regime — a pre-0.3.0 mismatch is a NOTICE, never a block.
#
# Modes:
#   gate-check.sh                      filesystem mode — gate the working
#                                      data dir against HEAD's history.
#                                      Seals in the log's uncommitted tail
#                                      (lines beyond HEAD's blob) are
#                                      mid-flow capture — by the
#                                      capture-before-commit discipline the
#                                      seal for commit N is written before N
#                                      exists — so they NOTICE, never block.
#   gate-check.sh --ref <committish>   gate the log AS OF that ref (blob
#                                      extracted to a temp dir) against that
#                                      ref's history, strictly — this is
#                                      what the pre-push adapter calls on
#                                      the outgoing sha. No log at the ref
#                                      means pre-adoption history: nothing
#                                      to gate, pass with a notice.
#
# Known impurity (documented, warn-only blast radius): the composite's
# drift check reads the *working* planning/ dir and committed config even
# in --ref mode. Drift is advisory; the blocking halves are pure.
#
# Exit: 0 trustworthy, 1 blocking defect (either half), 2 usage or
# environment error (a 2 from either half wins: an unverifiable state
# cannot be claimed trustworthy).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
REF=""
CONFIG=""

usage() {
  echo "usage: gate-check.sh [--ref <committish>] [--repo-root <dir>] [--config <file>]" >&2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --ref)       REF="${2:?--ref needs a committish}"; shift 2 ;;
    --repo-root) REPO_ROOT="$(cd "${2:?--repo-root needs a dir}" && pwd)" || exit 2; shift 2 ;;
    --config)    CONFIG="${2:?--config needs a file}"; shift 2 ;;
    -h|--help)   usage; exit 0 ;;
    *)           usage; exit 2 ;;
  esac
done

# Resolve the data dir (env -> .apt-config.toml -> default) through the same
# aptlib the rest of the toolchain uses, plus its repo-relative path (needed
# to address the blob as <ref>:<relpath>). DATA_REL comes back empty when
# the data dir sits outside the repo — the no-git deployment story, where
# blob addressing is impossible.
eval "$(python3 - "$SCRIPT_DIR" "$REPO_ROOT" "$CONFIG" <<'PYEOF'
import shlex, sys
from pathlib import Path
scripts, root, cfg = Path(sys.argv[1]), Path(sys.argv[2]).resolve(), sys.argv[3] or None
sys.path.insert(0, str(scripts))
import aptlib
d = aptlib.apt_data_dir(root, cfg).resolve()
try:
    rel = d.relative_to(root)
except ValueError:
    rel = ""
print("DATA_DIR=" + shlex.quote(str(d)))
print("DATA_REL=" + shlex.quote(str(rel)))
PYEOF
)" || { echo "gate-check: could not resolve the data dir" >&2; exit 2; }

COMPOSITE=(python3 "$SCRIPT_DIR/gate-composite.py" --repo-root "$REPO_ROOT")
[ -n "$CONFIG" ] && COMPOSITE+=(--config "$CONFIG")

# seal_check <log-path> <ref> <committed-line-count>
# Lines beyond <committed-line-count> are the uncommitted tail (mid-flow);
# pass the total line count (or any larger number) for strict mode.
seal_check() {
  python3 - "$1" "$2" "$3" "$REPO_ROOT" <<'PYEOF'
import json, subprocess, sys
log, ref, committed, root = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
try:
    subjects = set(subprocess.run(
        ["git", "-C", root, "log", "--format=%s", ref],
        capture_output=True, text=True, check=True).stdout.splitlines())
except subprocess.CalledProcessError as e:
    print(f"gate-check: git log {ref} failed: {e.stderr.strip()[-200:]}", file=sys.stderr)
    sys.exit(2)  # cannot verify -> cannot claim trustworthy
blocks = 0
with open(log, encoding="utf-8") as f:
    for n, line in enumerate(f, 1):
        line = line.strip()
        if not line:
            continue
        try:
            ev = json.loads(line)
        except json.JSONDecodeError:
            continue  # malformed lines are the composite schema check's verdict
        if ev.get("type") != "commit.recorded":
            continue
        msg = (ev.get("attributes") or {}).get("message_first_line")
        if msg in subjects:
            continue
        try:
            sv = tuple(int(x) for x in str(ev.get("schema_version")).split("."))
        except ValueError:
            sv = (0, 0, 0)  # malformed version: the composite's schema check owns it
        if n > committed:
            print(f"NOTICE [seal-commit] line {n}: seal '{msg}' has no commit yet "
                  f"(uncommitted tail — mid-flow capture, sealed by the commit to come)")
        elif sv < (0, 3, 0):
            # Pre-epoch seals were hand-written loose summaries; exact-match
            # is 0.3.0 capture-skill law. Judged by their own regime.
            print(f"NOTICE [seal-commit] line {n}: pre-0.3.0 seal '{msg}' matches no commit "
                  f"subject (loose wording predates the exact-match discipline; advisory only)")
        else:
            blocks += 1
            print(f"BLOCK [seal-commit] line {n}: committed seal '{msg}' matches no commit "
                  f"reachable from {ref} — squash/reword has orphaned the record")
if blocks:
    print(f"seal-commit: {blocks} orphaned seal(s)")
sys.exit(1 if blocks else 0)
PYEOF
}

if [ -n "$REF" ]; then
  # --- ref mode: gate the log as of the outgoing/named commit ------------
  SHA="$(git -C "$REPO_ROOT" rev-parse --verify --quiet "$REF^{commit}")" \
    || { echo "gate-check: '$REF' is not a commit" >&2; exit 2; }
  if [ -z "$DATA_REL" ]; then
    echo "gate-check: data dir $DATA_DIR is outside the repo — cannot gate a ref" >&2
    exit 2
  fi
  TMP="$(mktemp -d)" || exit 2
  trap 'rm -rf "$TMP"' EXIT
  if ! git -C "$REPO_ROOT" show "$SHA:$DATA_REL/events.jsonl" > "$TMP/events.jsonl" 2>/dev/null; then
    echo "gate-check: no $DATA_REL/events.jsonl at $SHA — nothing to gate (pre-adoption history)"
    exit 0
  fi
  echo "== integrity composite ($SHA)"
  "${COMPOSITE[@]}" --data-dir "$TMP"
  COMP_CODE=$?
  echo "== seal-commit correspondence ($SHA, strict)"
  TOTAL=$(($(wc -l < "$TMP/events.jsonl")))  # $((...)) strips wc's padding
  seal_check "$TMP/events.jsonl" "$SHA" "$TOTAL"
  SEAL_CODE=$?
else
  # --- filesystem mode: gate the working data dir against HEAD -----------
  LOG="$DATA_DIR/events.jsonl"
  if [ ! -f "$LOG" ]; then
    echo "gate-check: no events.jsonl at $DATA_DIR — nothing to gate"
    exit 0
  fi
  echo "== integrity composite (working tree)"
  "${COMPOSITE[@]}"
  COMP_CODE=$?
  if git -C "$REPO_ROOT" rev-parse --verify --quiet HEAD >/dev/null; then
    if [ -n "$DATA_REL" ]; then
      # Committed extent of the log: seals beyond it are mid-flow.
      COMMITTED=$(($(git -C "$REPO_ROOT" show "HEAD:$DATA_REL/events.jsonl" 2>/dev/null | wc -l)))
    else
      COMMITTED=0  # log lives outside the repo: never committed, all mid-flow
      echo "gate-check: data dir outside the repo — seal-commit runs advisory only"
    fi
    echo "== seal-commit correspondence (HEAD, committed extent: $COMMITTED line(s))"
    seal_check "$LOG" "HEAD" "$COMMITTED"
    SEAL_CODE=$?
  else
    echo "== seal-commit correspondence skipped (no commits yet)"
    SEAL_CODE=0
  fi
fi

if [ "$COMP_CODE" -eq 2 ] || [ "$SEAL_CODE" -eq 2 ]; then FINAL=2
elif [ "$COMP_CODE" -eq 1 ] || [ "$SEAL_CODE" -eq 1 ]; then FINAL=1
else FINAL=0; fi
if [ "$FINAL" -eq 0 ]; then VERDICT="PASS"; else VERDICT="FAIL"; fi
echo "gate-check: $VERDICT (composite=$COMP_CODE, seal-commit=$SEAL_CODE)"
exit "$FINAL"
