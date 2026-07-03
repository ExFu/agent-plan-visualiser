#!/bin/sh
# extract-capture.sh — agent-plan-visualiser commit-msg hook (apv-extract).
#
# Autonomous capture for commits no session agent saw (T3-autonomous-
# extractor): humans committing from an editor, CI bots, collaborators
# without Claude Code. Session capture stays primary — a fresh
# .last-capture means /apv-capture already ran and this hook passes
# through untouched. Only a stale capture triggers extraction, via
# `claude -p` under scripts/extract-commit.py, which enforces the
# write-side rules in code and blocks the commit on ambiguity
# (needs-review/ carries the halt; resolve in-session).
#
# This lives at commit-msg — the only blocking hook that receives the
# commit message, which the seal requires (T3 §6 Q1 ruling). The
# capture-guard (pre-commit) detects this hook by its "apv-extract"
# marker and defers to it.
#
# Install:  bash agent-plan-visualiser/scripts/install-extractor.sh
#           (or /apv-init --with-extractor)
# Bypass:   git commit --no-verify — capture-free trivia, as ever.

MSG_FILE="$1"

# Baked by the installer (install-extractor.sh --home=<dir>) into installed
# copies. Empty in the source: the vendored/dev case falls through.
APV_HOME=""

# Data dir resolution mirrors capture-guard/apvlib: env -> config -> .apv/.
if [ -n "${APV_DATA_DIR:-}" ]; then
  DATA_DIR="$APV_DATA_DIR"
else
  DATA_DIR=$(sed -n 's/^[[:space:]]*data_dir[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' .apv-config.toml 2>/dev/null | head -n 1)
  [ -n "$DATA_DIR" ] || DATA_DIR=".apv"
fi

# Staleness check — the same contract the guard applies: if no staged file
# is newer than the capture stamp, a session capture already covers this
# commit and the extractor must not run. Returns 0 = fresh, 1 = stale.
# (Plain pipeline + exit codes; a `case` inside $(...) trips POSIX parsers.)
capture_ts=$(cat "$DATA_DIR/.last-capture" 2>/dev/null)
case "$capture_ts" in
  (''|*[!0-9]*) capture_ts=0 ;;
esac

capture_is_fresh() {
  [ "$capture_ts" -gt 0 ] || return 1
  git diff --cached --name-only -z | tr '\0' '\n' | while IFS= read -r file; do
    [ -f "$file" ] || continue
    case "$file" in
      ("$DATA_DIR/cache.sqlite"|"$DATA_DIR/projection.json"|"$DATA_DIR/summary.md") continue ;;
    esac
    file_ts=$(stat -f %m "$file" 2>/dev/null || stat -c %Y "$file" 2>/dev/null)
    case "$file_ts" in
      (''|*[!0-9]*) exit 1 ;;
    esac
    # if-form deliberately: a false `[ ... ] && exit 1` would leave status 1
    # as the loop's last command and read a FRESH capture as stale.
    if [ "$file_ts" -gt "$capture_ts" ]; then exit 1; fi
  done
}

capture_is_fresh && exit 0

# Resolve the orchestrator: env override -> baked home -> vendored layout.
resolve_extractor() {
  if [ -n "${APV_EXTRACTOR:-}" ] && [ -f "$APV_EXTRACTOR" ]; then
    echo "$APV_EXTRACTOR"; return 0
  fi
  if [ -n "$APV_HOME" ] && [ -f "$APV_HOME/scripts/extract-commit.py" ]; then
    echo "$APV_HOME/scripts/extract-commit.py"; return 0
  fi
  if [ -f "agent-plan-visualiser/scripts/extract-commit.py" ]; then
    echo "agent-plan-visualiser/scripts/extract-commit.py"; return 0
  fi
  return 1
}

EXTRACTOR="$(resolve_extractor)" || {
  echo "apv-extract: extract-commit.py not found (set APV_EXTRACTOR, or reinstall" >&2
  echo "apv-extract: via install-extractor.sh --home=<toolchain>)." >&2
  exit 1
}

if ! python3 "$EXTRACTOR" --msg-file "$MSG_FILE"; then
  echo "apv-extract: commit blocked — autonomous capture did not complete." >&2
  echo "apv-extract: resolve in-session (/apv-capture) or use git commit --no-verify" >&2
  echo "apv-extract: for capture-free trivia." >&2
  exit 1
fi

# Git wrote this commit's tree BEFORE this hook ran, so the appended block
# is not in it yet. Flag for the post-commit half (extract-amend.sh),
# which amends the block into the commit it seals.
: > "$DATA_DIR/.pending-extract"
exit 0
