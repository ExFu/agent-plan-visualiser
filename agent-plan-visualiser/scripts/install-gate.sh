#!/usr/bin/env bash
# install-gate.sh — install the gate's enforcement adapters, idempotently.
#
# Usage (from the repo root):
#   bash agent-plan-visualiser/scripts/install-gate.sh \
#     [--at=pre-push|--at=ref-update|--at=manual] [--home=<toolchain-dir>]
#
# --home=<dir>: bake <dir> as the toolchain home (APV_HOME) into the
#   installed hook copy — plugin-cache installs pass ${CLAUDE_PLUGIN_ROOT}.
#   Omitted: the copy ships verbatim and the hook's own resolution chain
#   decides at run time (the vendored/dogfood story).
#
# --at=pre-push (default): install hooks/gate-prepush.sh as the repo's
#   pre-push hook — gates pushes that update refs/heads/main.
# --at=ref-update: install hooks/gate-refupdate.sh as the repo's
#   reference-transaction hook — gates LOCAL moves of refs/heads/main
#   (merges including fast-forward, direct commits, amends, resets; the
#   only hook class that sees a fast-forward merge). Operator ruling
#   2026-06-10: local merges gate, not just pushes.
# --at=manual: install nothing — verify gate-check.sh is present and print
#   how to call it. The stance-neutral story: the check is one contract,
#   where it fires is installation choice (T3-gate-core §2.2).
#
# Idempotency contract (same as install-hook.sh), per adapter:
#   - no hook of that name yet      -> install, chmod +x
#   - identical hook already there  -> no-op ("already installed"), exit 0
#   - a DIFFERENT hook exists       -> refuse (never clobber), exit 1
set -uo pipefail

AT="pre-push"
HOME_DIR=""
for arg in "$@"; do
  case "$arg" in
    --at=pre-push)   AT="pre-push" ;;
    --at=ref-update) AT="ref-update" ;;
    --at=manual)     AT="manual" ;;
    --home=*)        HOME_DIR="${arg#--home=}" ;;
    *)
      echo "usage: install-gate.sh [--at=pre-push|--at=ref-update|--at=manual] [--home=<toolchain-dir>]" >&2
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

case "$AT" in
  pre-push)   LABEL="gate-prepush";   HOOK_NAME="pre-push" ;;
  ref-update) LABEL="gate-refupdate"; HOOK_NAME="reference-transaction" ;;
esac
SRC="$(dirname "$0")/../hooks/$LABEL.sh"
if [ ! -f "$SRC" ]; then
  echo "install-gate: source hook not found at $SRC" >&2
  exit 1
fi

# Render the copy to install. With --home=<dir>, the toolchain home is
# baked into the hook's APV_HOME line — the deciding happens once, at
# install (plugin-cache installs pass ${CLAUDE_PLUGIN_ROOT} here). Without
# it the source ships verbatim and the hook's own fallback chain decides
# (the vendored/dogfood story). Idempotency compares against the RENDERED
# copy, so a re-run with the same --home is a no-op and a different --home
# refuses loudly.
RENDERED="$(mktemp)" || exit 1
trap 'rm -f "$RENDERED"' EXIT
if [ -n "$HOME_DIR" ]; then
  HOME_ABS="$(cd "$HOME_DIR" 2>/dev/null && pwd)" || {
    echo "install-gate: --home dir not found: $HOME_DIR" >&2
    exit 1
  }
  sed "s|^APV_HOME=\"\"|APV_HOME=\"$HOME_ABS\"|" "$SRC" > "$RENDERED"
else
  cp "$SRC" "$RENDERED"
fi

# --git-path resolves the hooks dir correctly in normal repos AND linked
# worktrees (where hooks live in the shared common git dir), and honours
# core.hooksPath if set.
HOOKS_DIR="$(git rev-parse --git-path hooks)" || exit 1
DEST="$HOOKS_DIR/$HOOK_NAME"

if [ ! -e "$DEST" ] && [ ! -L "$DEST" ]; then
  mkdir -p "$HOOKS_DIR"
  cp "$RENDERED" "$DEST"
  chmod +x "$DEST"
  echo "install-gate: installed $LABEL as $DEST"
  exit 0
fi

if cmp -s "$RENDERED" "$DEST"; then
  chmod +x "$DEST"
  echo "install-gate: already installed at $DEST — nothing to do"
  exit 0
fi

echo "install-gate: $DEST already exists and differs from the $LABEL this installer would write — refusing to overwrite." >&2
echo "install-gate: inspect the existing hook and merge or remove it manually, then re-run." >&2
exit 1
