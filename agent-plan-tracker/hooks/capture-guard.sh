#!/bin/sh
# capture-guard.sh — agent-plan-tracker pre-commit hook.
#
# Enforces capture-before-commit: a commit is rejected unless /apt-capture
# has run since the last modification of every staged file. The capture
# skill writes a Unix epoch timestamp (seconds) to $DATA_DIR/.last-capture
# as its final act; this hook compares staged-file mtimes against it.
#
# Install:  bash agent-plan-tracker/scripts/install-hook.sh
#           (or copy this file to your hooks dir as `pre-commit`, chmod +x).
# Bypass:   git commit --no-verify — the sanctioned escape hatch for
#           commits that genuinely need no capture (e.g. a pure typo fix);
#           see the /apt-capture skill.
#
# Git runs pre-commit hooks from the top of the working tree, so relative
# paths below resolve against the repo root.

# Data dir defaults to .agent-plan-tracker/; override with APT_DATA_DIR
# (same resolution as the rest of the toolchain).
DATA_DIR="${APT_DATA_DIR:-.agent-plan-tracker}"

# Missing file, empty, or non-numeric content all mean "no usable capture".
capture_ts=$(cat "$DATA_DIR/.last-capture" 2>/dev/null)
case "$capture_ts" in
  ''|*[!0-9]*)
    echo "apt: no capture recorded. Run /apt-capture first." >&2
    exit 1
    ;;
esac

# Iterate staged files NUL-delimited (-z disables git's C-quoting, so names
# arrive byte-exact), converted NUL->newline for a POSIX `read` loop. This
# handles spaces and all other characters except embedded newlines in
# filenames: those split into fragments that fail the -f check below and
# are skipped. Accepted limitation — this is a discipline hook, not a
# security boundary. The loop runs in a pipeline subshell, so `exit 1`
# inside it only leaves the subshell; `|| exit 1` after the pipeline
# propagates the rejection to the hook itself.
git diff --cached --name-only -z | tr '\0' '\n' | while IFS= read -r file; do
  # Staged deletions (and newline-fragment artefacts) have nothing on disk.
  [ -f "$file" ] || continue

  # Derived artefacts are rebuilt by the pipeline after capture, so their
  # mtimes legitimately postdate .last-capture. Exactly these three —
  # events.jsonl is NOT excluded (manual edits require re-capture).
  case "$file" in
    "$DATA_DIR/cache.sqlite"|"$DATA_DIR/projection.json"|"$DATA_DIR/summary.md")
      continue
      ;;
  esac

  # mtime in epoch seconds: BSD/macOS stat first, GNU/Linux stat fallback.
  file_ts=$(stat -f %m "$file" 2>/dev/null || stat -c %Y "$file" 2>/dev/null)
  case "$file_ts" in
    ''|*[!0-9]*)
      # Existing file whose mtime we cannot determine: fail closed.
      echo "apt: cannot determine mtime of '$file'; refusing to commit." >&2
      exit 1
      ;;
  esac

  if [ "$file_ts" -gt "$capture_ts" ]; then
    echo "apt: '$file' modified after last capture. Run /apt-capture first." >&2
    exit 1
  fi
done || exit 1

exit 0
