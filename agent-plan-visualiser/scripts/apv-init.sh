#!/usr/bin/env bash
# apv-init.sh — attach a repository to agent-plan-visualiser tracking, idempotently.
#
# Usage (from anywhere inside the target repo):
#   bash <toolchain>/scripts/apv-init.sh \
#     [--at=all|pre-push|ref-update|manual] [--accept-claude-md]
#
# What it does — create-if-missing, NEVER clobber (T3-project-init-flow §2):
#   1. Preconditions: inside a non-bare git work tree.
#   2. Seed: the data dir (default `.apv/` — APV_DATA_DIR or an existing
#      `.apv-config.toml` [storage] data_dir override it) with an empty
#      events.jsonl — this is THE one sanctioned creation site; the capture
#      skill refuses to create it — plus schema-version.txt; write
#      `.apv-config.toml` with the default gate lists.
#   3. Command launcher: generate `<data-dir>/bin/apv` plus a `./apv`
#      symlink at the repo root — the entry points to the toolchain's
#      bin/apv dispatcher (serve / init / backfill / refresh). Both are
#      MACHINE-INDEPENDENT and safe to commit: the shim bakes no paths and
#      resolves the toolchain at run time (APV_HOME -> vendored ->
#      `<data-dir>/.toolchain-home` -> Claude plugin cache, newest). The
#      pointer file is the only machine-specific piece and stays local
#      (gitignored, refreshed per init). A pre-existing non-apv file at
#      either path is refused, never clobbered; transitional layouts
#      (root-level bin/apv; shim/symlink gitignore pairs) are migrated.
#   4. Gitignore the local per-checkout state (`.last-capture`,
#      `.pending-extract`, `<data-dir>/.toolchain-home`).
#   5. Hooks: the existing installers (capture-guard pre-commit; gate
#      pre-push; gate ref-update), with the toolchain home baked into the
#      gate copies when the toolchain lives OUTSIDE the repo (plugin-cache
#      install) and verbatim when vendored inside it (the dogfood story).
#      --at picks the gate adapter(s); `--at=manual` installs no git hooks
#      and prints the on-demand contract instead.
#   6. Orient: print the CLAUDE.md offer. The block is appended ONLY with
#      --accept-claude-md — explicit user acceptance; init is the offer's
#      only trigger (re-run init to be offered again). Never written unasked.
#   7. Report: per-component state and next steps. Re-run = audit mode —
#      reports each component, fixes the missing, touches nothing else.
#      A foreign hook is refused loudly (by the installers' own contract);
#      init continues with the other components and exits 1 at the end.
#
# Exit: 0 attached / repaired / nothing-to-do; 1 at least one component
#       refused or failed; 2 usage or environment error.
set -uo pipefail

AT="all"
ACCEPT_CLAUDE_MD=0
WITH_EXTRACTOR=0
for arg in "$@"; do
  case "$arg" in
    --at=all)        AT="all" ;;
    --at=pre-push)   AT="pre-push" ;;
    --at=ref-update) AT="ref-update" ;;
    --at=manual)     AT="manual" ;;
    --accept-claude-md) ACCEPT_CLAUDE_MD=1 ;;
    --with-extractor)   WITH_EXTRACTOR=1 ;;
    *)
      echo "usage: apv-init.sh [--at=all|pre-push|ref-update|manual] [--with-extractor] [--accept-claude-md]" >&2
      exit 2
      ;;
  esac
done

# --- preconditions ----------------------------------------------------------
if [ "$(git rev-parse --is-bare-repository 2>/dev/null)" = "true" ]; then
  echo "apv-init: this is a bare repository — tracking needs a work tree." >&2
  exit 2
fi
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "apv-init: not inside a git repository — run from the repo to attach." >&2
  exit 2
}
cd "$REPO_ROOT" || exit 2

# The toolchain home is wherever this script lives — the plugin cache on a
# real install, the vendored tree in the dogfood repo. Vendored means the
# home sits inside the repo being attached: then the gate hooks ship
# verbatim and their own runtime chain resolves (one shared hook copy must
# serve every worktree); otherwise the home is baked at install time.
TOOLCHAIN_HOME="$(cd "$(dirname "$0")/.." && pwd)"
VENDORED=0
case "$TOOLCHAIN_HOME/" in
  "$REPO_ROOT"/*) VENDORED=1 ;;
esac

# Data dir resolution mirrors capture-guard/apvlib: APV_DATA_DIR env var ->
# committed .apv-config.toml [storage] data_dir -> default .apv/. An
# existing config wins over the fresh-install default — attaching an
# already-attached repo must respect its pin, not fight it.
if [ -n "${APV_DATA_DIR:-}" ]; then
  DATA_DIR="$APV_DATA_DIR"
else
  DATA_DIR=$(sed -n 's/^[[:space:]]*data_dir[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' .apv-config.toml 2>/dev/null | head -n 1)
  [ -n "$DATA_DIR" ] || DATA_DIR=".apv"
fi

FAIL=0
report() { # report <state> <component> [detail]
  printf '  %-8s %s%s\n' "$1" "$2" "${3:+ — $3}"
}

echo "apv-init: attaching $REPO_ROOT"
echo "apv-init: toolchain home $TOOLCHAIN_HOME ($([ "$VENDORED" -eq 1 ] && echo vendored || echo external))"
echo

# --- 1. data dir + events.jsonl ---------------------------------------------
if [ -f "$DATA_DIR/events.jsonl" ]; then
  report ok "$DATA_DIR/events.jsonl" "$(grep -c '' "$DATA_DIR/events.jsonl" 2>/dev/null || echo 0) events"
else
  mkdir -p "$DATA_DIR"
  : > "$DATA_DIR/events.jsonl"
  report created "$DATA_DIR/events.jsonl" "empty log; the first capture writes the first block"
fi
if [ -f "$DATA_DIR/schema-version.txt" ]; then
  report ok "$DATA_DIR/schema-version.txt" "$(cat "$DATA_DIR/schema-version.txt")"
else
  printf '0.3.0\n' > "$DATA_DIR/schema-version.txt"
  report created "$DATA_DIR/schema-version.txt" "0.3.0"
fi

# --- 2. config ---------------------------------------------------------------
if [ -f ".apv-config.toml" ]; then
  report ok ".apv-config.toml" "existing config respected"
else
  cat > .apv-config.toml <<TOML
# .apv-config.toml — committed project configuration for agent-plan-visualiser.
# Lives at the repo root (it names the data dir, so it cannot live inside it).
# Unknown keys are tolerated by design — this file accrues future config.

[gate]
# Check ids the integrity composite (gate-composite.py) enforces.
# blocking = corruption of the record (exit 1); warn = advisory, printed,
# never failing. Moving an id between the lists changes enforcement
# without code edits.
blocking = ["schema", "referential", "sealed-tail", "implementation-on-draft", "resurrection-without-reopen", "fulcrum-without-decision"]
warn = ["drift", "orphans", "stalled", "long-blockers"]

[storage]
# APV_DATA_DIR env var overrides this; default is .apv/ when neither is set.
data_dir = "$DATA_DIR"
TOML
  report created ".apv-config.toml" "default gate lists; data_dir = \"$DATA_DIR\""
fi

# --- 3. command launcher -----------------------------------------------------
# A short entry point — `<data-dir>/bin/apv` — so nobody has to type
# `python3 <toolchain>/scripts/...` by hand. The shim is a pure passthrough
# to the toolchain's bin/apv dispatcher (serve / init / backfill / refresh),
# so new subcommands arrive with a plugin update, no re-init needed.
# The shim is MACHINE-INDEPENDENT (operator ruling 2026-07-07: repo content
# carries zero machine-specific dependency — the plugin runs wherever the
# repo is checked out, not on the machine that attached it): it resolves the
# toolchain at run time (APV_HOME -> vendored -> <data-dir>/.toolchain-home
# -> Claude plugin cache) and is therefore safe to commit. It lives INSIDE
# the data dir (same ruling: the project root's ./bin is for what the
# project itself exposes; this is tracker tooling). A pre-existing NON-apv
# file at the path is refused, never clobbered (the hook installers'
# contract, applied here).
LAUNCHER_PATH="$DATA_DIR/bin/apv"
LAUNCHER_OK=1

# Remove our comment+entry pairs from .gitignore. Pair-scoped: an entry is
# only removed when immediately preceded by our exact comment line — a bare
# same-named line the project added for its own reasons is not ours to touch.
remove_ignore_pairs() {
  [ -f .gitignore ] || return 0
  python3 - "$@" <<'PY'
import sys
targets = set(sys.argv[1:])
comment = "# agent-plan-visualiser local per-checkout state — never tracked"
lines = open(".gitignore").read().splitlines()
out, i, changed = [], 0, False
while i < len(lines):
    if lines[i] in targets and out and out[-1] == comment:
        out.pop(); i += 1; changed = True
        continue
    out.append(lines[i]); i += 1
if changed:
    open(".gitignore", "w").write("\n".join(out) + ("\n" if out else ""))
PY
}

# Migration (transitional): on 2026-07-07 init briefly generated the launcher
# at the project root. Remove OUR old copy (marker-verified) and its
# gitignore pair so a stale ignore line never hides a real bin/apv the
# project later exposes. A root bin/apv without the marker is not ours:
# leave it alone.
OLD_LAUNCHER="bin/apv"
if [ "$OLD_LAUNCHER" != "$LAUNCHER_PATH" ] && [ -f "$OLD_LAUNCHER" ] \
    && grep -q "apv:launcher" "$OLD_LAUNCHER" 2>/dev/null; then
  rm -f "$OLD_LAUNCHER"
  rmdir bin 2>/dev/null || true   # only if the launcher was its sole content
  remove_ignore_pairs "$OLD_LAUNCHER"
  report migrated "$OLD_LAUNCHER" "relocated to $LAUNCHER_PATH (root bin/ is project surface)"
fi
# Migration (transitional): 0.5.3/0.5.4 gitignored the shim and the ./apv
# symlink; both are machine-independent now and may be committed — stale
# ignore lines would silently keep them out of the repo.
remove_ignore_pairs "$DATA_DIR/bin/apv" "/apv"
# Write the desired launcher to $1. The shim is STATIC — nothing machine-
# specific is baked (operator ruling 2026-07-07: zero machine dependency in
# repo content; the plugin is resolved on whatever machine the repo is
# checked out to). It locates the toolchain at RUN time: APV_HOME override,
# a toolchain vendored inside the repo, the local pointer file
# <data-dir>/.toolchain-home (written by init, never committed), then the
# Claude plugin cache (newest installed version). Being byte-identical on
# every machine, the shim and the ./apv symlink are safe to commit. The
# `apv:launcher` marker on line 2 is the foreign-file guard's fingerprint.
gen_launcher() {
  cat > "$1" <<'LAUNCH'
#!/usr/bin/env bash
# apv:launcher (generated by apv-init) — machine-independent; safe to commit.
# Resolves the APV toolchain at run time; nothing machine-specific is baked.
# Order: APV_HOME -> vendored in this repo -> <data-dir>/.toolchain-home
# (local, untracked) -> Claude plugin cache (newest install).
set -euo pipefail
# realpath: we are usually invoked via the ./apv symlink — the data dir is
# where the SHIM lives, not where the link does.
self="$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$0")"
self_dir="$(dirname "$self")"
data_dir="$(dirname "$self_dir")"

usable() { [ -n "${1:-}" ] && [ -x "$1/bin/apv" ]; }

if usable "${APV_HOME:-}"; then
  exec "$APV_HOME/bin/apv" "$@"
fi
repo_root="$(git -C "$self_dir" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -n "$repo_root" ] && usable "$repo_root/agent-plan-visualiser"; then
  exec "$repo_root/agent-plan-visualiser/bin/apv" "$@"
fi
if [ -f "$data_dir/.toolchain-home" ]; then
  pinned="$(head -n 1 "$data_dir/.toolchain-home")"
  # A pin into the plugin cache would freeze this checkout at whatever
  # version attached it (old cache versions stay on disk) — cache installs
  # are resolved by discovery below, newest wins. Pins are for dev/custom
  # toolchains only.
  case "$pinned" in
    */plugins/cache/*) : ;;
    *) if usable "$pinned"; then exec "$pinned/bin/apv" "$@"; fi ;;
  esac
fi
cache="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache"
newest="$(ls -d "$cache"/*/agent-plan-visualiser/*/ 2>/dev/null | sort -V | tail -n 1 || true)"
newest="${newest%/}"
if usable "$newest"; then
  exec "$newest/bin/apv" "$@"
fi
echo "apv: APV toolchain not found (tried \$APV_HOME, a vendored agent-plan-visualiser/," >&2
echo "apv: $data_dir/.toolchain-home, and $cache)." >&2
echo "apv: install the plugin (/plugin install agent-plan-visualiser@apv) or set APV_HOME," >&2
echo "apv: then re-run — or re-attach with /apv-init." >&2
exit 127
LAUNCH
}
LAUNCHER_TMP="$(mktemp)"
gen_launcher "$LAUNCHER_TMP"
if [ -e "$LAUNCHER_PATH" ] && ! grep -q "apv:launcher" "$LAUNCHER_PATH" 2>/dev/null; then
  report REFUSED "$LAUNCHER_PATH" "exists and is not an apv launcher — not overwriting"
  LAUNCHER_OK=0
  FAIL=1
  rm -f "$LAUNCHER_TMP"
elif [ -f "$LAUNCHER_PATH" ] && cmp -s "$LAUNCHER_TMP" "$LAUNCHER_PATH"; then
  report ok "$LAUNCHER_PATH" "run it: ./$LAUNCHER_PATH (serves the view UI)"
  rm -f "$LAUNCHER_TMP"
else
  had_launcher=0; [ -f "$LAUNCHER_PATH" ] && had_launcher=1
  mkdir -p "$(dirname "$LAUNCHER_PATH")"
  cat "$LAUNCHER_TMP" > "$LAUNCHER_PATH"
  chmod +x "$LAUNCHER_PATH"
  rm -f "$LAUNCHER_TMP"
  if [ "$had_launcher" -eq 1 ]; then
    report updated "$LAUNCHER_PATH" "shim refreshed (machine-independent; safe to commit)"
  else
    report created "$LAUNCHER_PATH" "run it: ./$LAUNCHER_PATH (serves the view UI)"
  fi
fi

# --- 3a. local toolchain pointer ----------------------------------------------
# <data-dir>/.toolchain-home pins THIS checkout to the toolchain that
# attached it (the dev checkout for vendored-adjacent setups, the plugin
# cache otherwise). It is per-checkout local state — gitignored, refreshed
# on every init — and only a fallback hint: the shim prefers it over cache
# discovery but survives its absence, so a clone on another machine works
# without it.
PIN_PATH="$DATA_DIR/.toolchain-home"
case "$TOOLCHAIN_HOME" in
  */plugins/cache/*)
    # Plugin-cache install: never pin. Old cache versions stay on disk, so a
    # pin would freeze this checkout at the attaching version; the shim's
    # discovery resolves the newest install every run.
    if [ -f "$PIN_PATH" ]; then
      rm -f "$PIN_PATH"
      report migrated "$PIN_PATH" "removed — cache installs resolve by discovery (newest)"
    else
      report ok "$PIN_PATH" "not needed — cache installs resolve by discovery (newest)"
    fi
    ;;
  *)
    if [ -f "$PIN_PATH" ] && [ "$(cat "$PIN_PATH")" = "$TOOLCHAIN_HOME" ]; then
      report ok "$PIN_PATH" "local toolchain pointer"
    else
      had_pin=0; [ -f "$PIN_PATH" ] && had_pin=1
      printf '%s\n' "$TOOLCHAIN_HOME" > "$PIN_PATH"
      if [ "$had_pin" -eq 1 ]; then
        report updated "$PIN_PATH" "-> $TOOLCHAIN_HOME"
      else
        report created "$PIN_PATH" "-> $TOOLCHAIN_HOME"
      fi
    fi
    ;;
esac

# --- 3b. convenience symlink ---------------------------------------------------
# `./apv` -> <data-dir>/bin/apv gives the short invocation without occupying
# the project's bin/ (operator ruling 2026-07-07: root bin/ is project
# surface; a dotfile-adjacent symlink is not). Relative target, so the repo
# can move — and, like the shim it points at, machine-independent and safe
# to commit. A foreign ./apv is refused; a dangling symlink (e.g. after a
# data-dir rename) is repaired.
SYMLINK_PATH="apv"
SYMLINK_OK=0
if [ "$LAUNCHER_OK" -eq 1 ]; then
  SYMLINK_OK=1
  if [ -L "$SYMLINK_PATH" ] && [ "$(readlink "$SYMLINK_PATH")" = "$LAUNCHER_PATH" ]; then
    report ok "./$SYMLINK_PATH" "-> $LAUNCHER_PATH"
  elif [ -L "$SYMLINK_PATH" ] && [ ! -e "$SYMLINK_PATH" ]; then
    ln -sfn "$LAUNCHER_PATH" "$SYMLINK_PATH"
    report updated "./$SYMLINK_PATH" "dangling link repaired -> $LAUNCHER_PATH"
  elif [ -e "$SYMLINK_PATH" ] && grep -q "apv:launcher" "$SYMLINK_PATH" 2>/dev/null; then
    # an apv launcher (old copy, or a link to one elsewhere) — safe to retarget
    ln -sfn "$LAUNCHER_PATH" "$SYMLINK_PATH"
    report updated "./$SYMLINK_PATH" "-> $LAUNCHER_PATH"
  elif [ -e "$SYMLINK_PATH" ] || [ -L "$SYMLINK_PATH" ]; then
    report REFUSED "./$SYMLINK_PATH" "exists and is not an apv launcher link — not overwriting"
    SYMLINK_OK=0
    FAIL=1
  else
    ln -s "$LAUNCHER_PATH" "$SYMLINK_PATH"
    report created "./$SYMLINK_PATH" "-> $LAUNCHER_PATH"
  fi
fi

# --- 4. gitignore the local per-checkout state -------------------------------
# The stamp (guard), the pending-extract flag (extractor's post-commit half),
# and the toolchain pointer are per-checkout local state; never tracked.
# One line each, appended once. The shim and ./apv symlink are deliberately
# NOT here — they are machine-independent and may be committed.
IGNORE_LINES=("$DATA_DIR/.last-capture" "$DATA_DIR/.pending-extract" "$DATA_DIR/.toolchain-home")
IGNORED_ALL=1
for LOCAL_LINE in "${IGNORE_LINES[@]}"; do
  if [ -f .gitignore ] && grep -qxF "$LOCAL_LINE" .gitignore; then
    :
  else
    IGNORED_ALL=0
    { [ -f .gitignore ] && [ -n "$(tail -c 1 .gitignore 2>/dev/null)" ] && echo; } >> .gitignore 2>/dev/null || true
    printf '# agent-plan-visualiser local per-checkout state — never tracked\n%s\n' "$LOCAL_LINE" >> .gitignore
  fi
done
IGNORE_DETAIL=".last-capture + .pending-extract + .toolchain-home"
if [ "$IGNORED_ALL" -eq 1 ]; then
  report ok ".gitignore" "local per-checkout state already ignored"
else
  report created ".gitignore" "ignoring $IGNORE_DETAIL"
fi

# --- 5. hooks -----------------------------------------------------------------
run_installer() { # run_installer <component> <cmd...>
  local component="$1"; shift
  local out code
  out="$("$@" 2>&1)"; code=$?
  if [ "$code" -eq 0 ]; then
    if printf '%s' "$out" | grep -q "already installed"; then
      report ok "$component"
    elif printf '%s' "$out" | grep -q "refreshed"; then
      report updated "$component" "outdated apv hook refreshed"
    else
      report created "$component"
    fi
  else
    report REFUSED "$component" "see below"
    printf '%s\n' "$out" | sed 's/^/    | /'
    FAIL=1
  fi
}

if [ "$AT" = "manual" ]; then
  report skipped "git hooks" "--at=manual: no hooks; run the gate on demand:"
  echo "    | bash \"$TOOLCHAIN_HOME/scripts/gate-check.sh\" [--ref <committish>]"
  echo "    | (capture discipline is unenforced without the pre-commit guard)"
else
  run_installer "pre-commit (capture-guard)" bash "$TOOLCHAIN_HOME/scripts/install-hook.sh"
  # Bake the toolchain home only for external NON-cache homes (a dev
  # checkout, an unzipped bundle). Plugin-cache paths are version-pinned —
  # baking one freezes the repo's hooks at the installing version (the
  # launcher's never-pin ruling, applied to hooks); the hooks' own chain
  # resolves the newest cache install at run time instead.
  GATE_HOME_ARGS=()
  case "$TOOLCHAIN_HOME" in
    */plugins/cache/*) : ;;
    *) [ "$VENDORED" -eq 0 ] && GATE_HOME_ARGS=(--home="$TOOLCHAIN_HOME") ;;
  esac
  # ${arr[@]+...} expansion: bash 3.2 (macOS /bin/bash) treats an empty
  # array's "${arr[@]}" as unbound under set -u; the + form is safe there.
  if [ "$AT" = "all" ] || [ "$AT" = "pre-push" ]; then
    run_installer "pre-push (gate)" bash "$TOOLCHAIN_HOME/scripts/install-gate.sh" --at=pre-push ${GATE_HOME_ARGS[@]+"${GATE_HOME_ARGS[@]}"}
  fi
  if [ "$AT" = "all" ] || [ "$AT" = "ref-update" ]; then
    run_installer "reference-transaction (gate)" bash "$TOOLCHAIN_HOME/scripts/install-gate.sh" --at=ref-update ${GATE_HOME_ARGS[@]+"${GATE_HOME_ARGS[@]}"}
  fi
  # Autonomous capture is opt-in (T3-autonomous-extractor §2.2): the
  # commit-msg extractor produces captures for non-session committers;
  # the pre-commit guard detects it and defers.
  if [ "$WITH_EXTRACTOR" -eq 1 ]; then
    run_installer "commit-msg (apv-extract)" bash "$TOOLCHAIN_HOME/scripts/install-extractor.sh" ${GATE_HOME_ARGS[@]+"${GATE_HOME_ARGS[@]}"}
  fi
fi

# --- 5b. plugin enablement persistence ---------------------------------------
# A project-scope plugin install is enabled by `enabledPlugins` in
# `.claude/settings.json` at the SESSION's project root. Worktree checkouts
# and fresh clones only carry that file when it is COMMITTED — otherwise the
# plugin (skills, commands, session orientation) silently fails to load
# there while the git hooks, shared via .git/hooks, still fire: agents get
# refused by the capture-guard with no /apv-capture skill to run. Field
# report 2026-07-21. So: ensure the enablement key exists in the shared
# settings file and warn loudly when that file is not git-tracked.
# User-scope installs load in every session and need none of this; vendored
# toolchains do not go through the plugin loader at all.
NEEDS_SETTINGS_COMMIT=0
case "$TOOLCHAIN_HOME" in
  */plugins/cache/*)
    # Cache layout is .../plugins/cache/<marketplace>/<plugin>/<version>.
    PLUGIN_ID="$(basename "$(dirname "$TOOLCHAIN_HOME")")@$(basename "$(dirname "$(dirname "$TOOLCHAIN_HOME")")")"
    INSTALLED_JSON="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/installed_plugins.json"
    USER_SCOPE=0
    if [ -f "$INSTALLED_JSON" ] && python3 - "$INSTALLED_JSON" "$PLUGIN_ID" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
entries = d.get("plugins", {}).get(sys.argv[2], [])
sys.exit(0 if any(e.get("scope") == "user" for e in entries) else 1)
PY
    then USER_SCOPE=1; fi
    if [ "$USER_SCOPE" -eq 1 ]; then
      report ok "plugin enablement" "$PLUGIN_ID is user-scope — loads in every session, worktrees included"
    else
      SETTINGS=".claude/settings.json"
      WROTE="$(python3 - "$SETTINGS" "$PLUGIN_ID" <<'PY'
import json, os, sys
path, pid = sys.argv[1], sys.argv[2]
data = {}
if os.path.exists(path):
    try:
        data = json.load(open(path))
    except Exception:
        print("invalid"); sys.exit(0)
ep = data.setdefault("enabledPlugins", {})
if ep.get(pid) is True:
    print("ok"); sys.exit(0)
ep[pid] = True
os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print("written")
PY
)"
      case "$WROTE" in
        invalid)
          report REFUSED "$SETTINGS" "exists but is not valid JSON — fix it by hand, then re-run"
          FAIL=1 ;;
        ok)
          report ok "$SETTINGS" "enabledPlugins carries $PLUGIN_ID" ;;
        written)
          report created "$SETTINGS" "enabledPlugins[\"$PLUGIN_ID\"] = true" ;;
      esac
      if [ "$WROTE" != "invalid" ]; then
        if git ls-files --error-unmatch "$SETTINGS" >/dev/null 2>&1; then
          report ok "$SETTINGS (tracked)" "worktree checkouts and clones will load the plugin"
        else
          report ACTION "$SETTINGS" "UNTRACKED — commit it, or worktree checkouts and clones will NOT load the plugin (no skills, no commands) while the git hooks still fire"
          NEEDS_SETTINGS_COMMIT=1
        fi
      fi
    fi
    ;;
esac

# --- 6. CLAUDE.md orientation offer ------------------------------------------
# Ruled (M4 §7 Q4, 2026-06-10): offer only; init is the offer's ONLY
# trigger; writing requires explicit user acceptance (--accept-claude-md).
APV_MD_MARKER="<!-- apv:orientation -->"
claude_md_block() {
  cat <<BLOCK
$APV_MD_MARKER
## agent-plan-visualiser (APV) tracking

This repository is tracked by agent-plan-visualiser. The append-only event
log at \`$DATA_DIR/events.jsonl\` is the source of truth for planning state;
plans and status prose are secondary. After each logical unit of work and
**before committing**, run /apv-capture to append a sealed event block —
the pre-commit guard rejects uncaptured commits (\`git commit --no-verify\`
is the sanctioned hatch for capture-free trivia). Land branches on main via
/apv-merge; the gate hooks refuse a main that fails the integrity check.

Skills are plugin-namespaced: /apv-capture may be listed as
\`agent-plan-visualiser:apv-capture\`. If NEITHER form is available, this
session did not load the plugin (typical in worktree checkouts that lack
\`.claude/settings.json\`) — read the skill source directly and follow it:
the newest \`~/.claude/plugins/cache/*/agent-plan-visualiser/*/skills/apv-capture/SKILL.md\`
(same pattern for apv-merge and using-agent-plan-visualiser).
BLOCK
}
if [ -f CLAUDE.md ] && grep -qF "$APV_MD_MARKER" CLAUDE.md; then
  report ok "CLAUDE.md" "orientation block present"
elif [ "$ACCEPT_CLAUDE_MD" -eq 1 ]; then
  { [ -f CLAUDE.md ] && [ -n "$(tail -c 1 CLAUDE.md 2>/dev/null)" ] && echo; } >> CLAUDE.md 2>/dev/null || true
  claude_md_block >> CLAUDE.md
  report created "CLAUDE.md" "orientation block appended (accepted)"
else
  report offered "CLAUDE.md" "orientation block NOT written"
  echo
  echo "apv-init: ---- offer: a CLAUDE.md orientation block ----------------------"
  claude_md_block | sed 's/^/    | /'
  echo "apv-init: to accept, re-run with --accept-claude-md. Init is this offer's"
  echo "apv-init: only trigger — nothing else will write or re-offer it."
fi

# --- 7. next steps ------------------------------------------------------------
echo
if [ "$FAIL" -eq 0 ]; then
  echo "apv-init: attached. Next steps:"
  if [ "$NEEDS_SETTINGS_COMMIT" -eq 1 ]; then
    echo "  - COMMIT .claude/settings.json (plugin enablement): without it, worktree"
    echo "    checkouts and clones run the git hooks but load none of the apv skills."
  fi
  echo "  - Work normally; run /apv-capture after each logical unit of work,"
  echo "    immediately before committing. The guard catches you if you forget."
  echo "  - Land branches on main via /apv-merge; the gate keeps main trustworthy."
  echo "  - See the UI: run ./apv (then open the printed view URL)."
  echo "  - This attaches from NOW: history before today is not mined (that is"
  echo "    backfill, a separate opt-in step)."
else
  echo "apv-init: attached WITH REFUSALS (see above) — inspect the refused"
  echo "apv-init: component(s), merge or remove the foreign hook(s) manually,"
  echo "apv-init: then re-run. Re-running repairs only what is missing."
fi
exit "$FAIL"
