#!/usr/bin/env bash
# install-hook.sh — install the capture-guard pre-commit hook, idempotently.
#
# Usage (from the repo root): bash agent-plan-visualiser/scripts/install-hook.sh
#
# Behaviour:
#   - no pre-commit hook yet        -> install capture-guard.sh, chmod +x
#   - identical hook already there  -> no-op ("already installed"), exit 0
#   - a DIFFERENT pre-commit exists -> refuse (never clobber), exit 1
set -uo pipefail

SRC="$(dirname "$0")/../hooks/capture-guard.sh"
if [ ! -f "$SRC" ]; then
  echo "install-hook: source hook not found at $SRC" >&2
  exit 1
fi

# --git-path resolves the hooks dir correctly in normal repos AND linked
# worktrees (where hooks live in the shared common git dir), and honours
# core.hooksPath if set.
HOOKS_DIR="$(git rev-parse --git-path hooks)" || exit 1
DEST="$HOOKS_DIR/pre-commit"

if [ ! -e "$DEST" ] && [ ! -L "$DEST" ]; then
  mkdir -p "$HOOKS_DIR"
  cp "$SRC" "$DEST"
  chmod +x "$DEST"
  echo "install-hook: installed capture-guard as $DEST"
  exit 0
fi

if cmp -s "$SRC" "$DEST"; then
  chmod +x "$DEST"
  echo "install-hook: already installed at $DEST — nothing to do"
  exit 0
fi

# An apv capture-guard of a different vintage (older release) is OURS to
# refresh — the never-clobber contract protects FOREIGN hooks, not our own
# outdated copies. Recognition: the header fingerprint every shipped
# generation carries on its first lines.
if head -n 3 "$DEST" | grep -q "capture-guard.sh — agent-plan-visualiser"; then
  cp "$SRC" "$DEST"
  chmod +x "$DEST"
  echo "install-hook: refreshed apv capture-guard at $DEST (outdated copy replaced)"
  exit 0
fi

echo "install-hook: $DEST already exists and differs from $SRC — refusing to overwrite." >&2
echo "install-hook: inspect the existing hook and merge or remove it manually, then re-run." >&2
exit 1
