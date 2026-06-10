#!/usr/bin/env bash
# install-gate.sh — install the gate's pre-push adapter, idempotently.
#
# Usage (from the repo root):
#   bash agent-plan-tracker/scripts/install-gate.sh [--at=pre-push|--at=manual]
#
# --at=pre-push (default): install hooks/gate-prepush.sh as the repo's
#   pre-push hook, with the same idempotency contract as install-hook.sh:
#     - no pre-push hook yet         -> install gate-prepush.sh, chmod +x
#     - identical hook already there -> no-op ("already installed"), exit 0
#     - a DIFFERENT pre-push exists  -> refuse (never clobber), exit 1
# --at=manual: install nothing — verify gate-check.sh is present and print
#   how to call it. The stance-neutral story: the check is one contract,
#   where it fires is installation choice (T3-gate-core §2.2).
set -uo pipefail

AT="pre-push"
for arg in "$@"; do
  case "$arg" in
    --at=pre-push) AT="pre-push" ;;
    --at=manual)   AT="manual" ;;
    *)
      echo "usage: install-gate.sh [--at=pre-push|--at=manual]" >&2
      exit 2
      ;;
  esac
done

GATE_CHECK="$(dirname "$0")/gate-check.sh"
if [ ! -f "$GATE_CHECK" ]; then
  echo "install-gate: gate-check.sh not found at $GATE_CHECK" >&2
  exit 1
fi

if [ "$AT" = "manual" ]; then
  echo "install-gate: manual mode — no hook installed."
  echo "install-gate: run the gate with: bash $GATE_CHECK [--ref <committish>]"
  exit 0
fi

SRC="$(dirname "$0")/../hooks/gate-prepush.sh"
if [ ! -f "$SRC" ]; then
  echo "install-gate: source hook not found at $SRC" >&2
  exit 1
fi

# --git-path resolves the hooks dir correctly in normal repos AND linked
# worktrees (where hooks live in the shared common git dir), and honours
# core.hooksPath if set.
HOOKS_DIR="$(git rev-parse --git-path hooks)" || exit 1
DEST="$HOOKS_DIR/pre-push"

if [ ! -e "$DEST" ] && [ ! -L "$DEST" ]; then
  mkdir -p "$HOOKS_DIR"
  cp "$SRC" "$DEST"
  chmod +x "$DEST"
  echo "install-gate: installed gate-prepush as $DEST"
  exit 0
fi

if cmp -s "$SRC" "$DEST"; then
  chmod +x "$DEST"
  echo "install-gate: already installed at $DEST — nothing to do"
  exit 0
fi

echo "install-gate: $DEST already exists and differs from $SRC — refusing to overwrite." >&2
echo "install-gate: inspect the existing hook and merge or remove it manually, then re-run." >&2
exit 1
