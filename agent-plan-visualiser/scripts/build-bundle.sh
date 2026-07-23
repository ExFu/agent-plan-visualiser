#!/usr/bin/env bash
# build-bundle.sh — package the plugin tree as the distributable artefact
# (T3-distribution §2.2). Version comes from the manifest; the output is
# a staged install-source tree plus one uploadable zip:
#
#   <out>/exfu-marketplace/                       staged single-plugin marketplace
#     .claude-plugin/marketplace.json            (source: "./agent-plan-visualiser")
#     agent-plan-visualiser/                     the plugin tree
#   <out>/agent-plan-visualiser-<v>.zip          the bundle (test channel: exfu.ai)
#
# Usage (from the repo root):
#   bash agent-plan-visualiser/scripts/build-bundle.sh [--out=<dir>]   # default dist/
#
# The marketplace wrapper is the documented local-install shape: a plain
# directory (no git needed) whose root holds .claude-plugin/marketplace.json
# with a relative source path. Users add the dir, then install the plugin.
# Plugin contents shipped: manifest, commands, skills, hooks (+ hooks.json),
# scripts, schemas, view, cheatsheet, philosophies, README. Excluded:
# tests/ (dev-only), scripts/local/ (per-user), caches.
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(pwd)/dist"
for arg in "$@"; do
  case "$arg" in
    --out=*) OUT="${arg#--out=}" ;;
    *) echo "usage: build-bundle.sh [--out=<dir>]" >&2; exit 2 ;;
  esac
done

VERSION="$(python3 -c "import json; print(json.load(open('$PLUGIN_DIR/.claude-plugin/plugin.json'))['version'])")" || {
  echo "build-bundle: cannot read version from plugin.json" >&2
  exit 1
}

MARKET="$OUT/exfu-marketplace"
STAGE="$MARKET/agent-plan-visualiser"
ZIP="$OUT/agent-plan-visualiser-$VERSION.zip"
mkdir -p "$OUT"
rm -rf "$MARKET" "$ZIP"

# Stage the plugin tree with dev-only surfaces excluded. tar-pipe keeps
# this portable across BSD/GNU (no rsync dependency).
mkdir -p "$STAGE"
(cd "$PLUGIN_DIR" && tar cf - \
    --exclude='./tests' \
    --exclude='./scripts/local' \
    --exclude='__pycache__' \
    --exclude='.DS_Store' \
    .) | tar xf - -C "$STAGE"

# The single-plugin marketplace catalog at the bundle root — the unzipped
# dir is then directly `/plugin marketplace add`-able (plain local paths
# are a supported marketplace source; relative plugin sources resolve
# against the marketplace root).
mkdir -p "$MARKET/.claude-plugin"
cat > "$MARKET/.claude-plugin/marketplace.json" <<JSON
{
  "name": "exfu",
  "owner": { "name": "Alastair Brayne" },
  "plugins": [
    {
      "name": "exfu-agent-plan-visualiser",
      "source": "./agent-plan-visualiser",
      "description": "Event-sourced planning methodology with git-history extraction and projection."
    }
  ]
}
JSON

(cd "$OUT" && zip -qr "$(basename "$ZIP")" "$(basename "$MARKET")") || exit 1

echo "build-bundle: staged  $MARKET"
echo "build-bundle: bundle  $ZIP ($(du -h "$ZIP" | cut -f1 | tr -d ' '))"
echo
echo "Install locally (Claude Code):"
echo "  /plugin marketplace add $MARKET"
echo "  /plugin install exfu-agent-plan-visualiser@exfu"
echo "Then, in the project to attach:  /apv-init"
