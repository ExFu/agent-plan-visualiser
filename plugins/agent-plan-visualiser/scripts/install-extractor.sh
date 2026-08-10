#!/usr/bin/env bash
# install-extractor.sh — install the autonomous-capture commit-msg hook,
# idempotently (T3-autonomous-extractor §2.2; opt-in — /apv-init only
# installs it with --with-extractor).
#
# Usage (from the repo root):
#   bash plugins/agent-plan-visualiser/scripts/install-extractor.sh [--home=<toolchain-dir>]
#
# --home=<dir>: bake <dir> as the toolchain home (APV_HOME) into the
#   installed copy — plugin-cache installs pass ${CLAUDE_PLUGIN_ROOT}.
#   Omitted: the copy ships verbatim and the hook's own resolution chain
#   decides at run time (the vendored/dogfood story).
#
# Idempotency contract (same as install-hook.sh / install-gate.sh):
#   - no commit-msg hook yet        -> install, chmod +x
#   - identical hook already there  -> no-op ("already installed"), exit 0
#   - a DIFFERENT commit-msg exists -> refuse (never clobber), exit 1
set -uo pipefail

HOME_DIR=""
for arg in "$@"; do
  case "$arg" in
    --home=*) HOME_DIR="${arg#--home=}" ;;
    *) echo "usage: install-extractor.sh [--home=<toolchain-dir>]" >&2; exit 2 ;;
  esac
done

# Two halves, both required: commit-msg extracts (it alone receives the
# message the seal needs), post-commit amends the block into the commit it
# seals (git writes the tree before commit-msg, so the append cannot ride
# the commit from there).
HOOKS_DIR="$(git rev-parse --git-path hooks)" || exit 1
STATUS=0

install_one() { # install_one <src-basename> <hook-name>
  local SRC DEST RENDERED
  SRC="$(dirname "$0")/../hooks/$1"
  DEST="$HOOKS_DIR/$2"
  if [ ! -f "$SRC" ]; then
    echo "install-extractor: source hook not found at $SRC" >&2
    STATUS=1; return
  fi
  RENDERED="$(mktemp)" || { STATUS=1; return; }
  if [ -n "$HOME_DIR" ]; then
    local HOME_ABS
    HOME_ABS="$(cd "$HOME_DIR" 2>/dev/null && pwd)" || {
      echo "install-extractor: --home dir not found: $HOME_DIR" >&2
      rm -f "$RENDERED"; STATUS=1; return
    }
    sed "s|^APV_HOME=\"\"|APV_HOME=\"$HOME_ABS\"|" "$SRC" > "$RENDERED"
  else
    cp "$SRC" "$RENDERED"
  fi

  if [ ! -e "$DEST" ] && [ ! -L "$DEST" ]; then
    mkdir -p "$HOOKS_DIR"
    cp "$RENDERED" "$DEST"
    chmod +x "$DEST"
    echo "install-extractor: installed $1 as $DEST"
  elif cmp -s "$RENDERED" "$DEST"; then
    chmod +x "$DEST"
    echo "install-extractor: already installed at $DEST — nothing to do"
  elif head -n 3 "$DEST" | grep -q "$1 — agent-plan-visualiser"; then
    # Our own hook of a different vintage — refresh, never refuse (the
    # never-clobber contract protects FOREIGN hooks, not outdated apv ones).
    cp "$RENDERED" "$DEST"
    chmod +x "$DEST"
    echo "install-extractor: refreshed apv $1 at $DEST (outdated copy replaced)"
  else
    echo "install-extractor: $DEST already exists and differs from the $1 this installer would write — refusing to overwrite." >&2
    echo "install-extractor: inspect the existing hook and merge or remove it manually, then re-run." >&2
    STATUS=1
  fi
  rm -f "$RENDERED"
}

install_one extract-capture.sh commit-msg
install_one extract-amend.sh post-commit
exit "$STATUS"
