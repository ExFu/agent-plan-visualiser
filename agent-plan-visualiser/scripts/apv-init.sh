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
#   3. Command launcher: generate `bin/apv` at the repo root, a short entry
#      point (tiny dispatcher — today `apv serve`; delegates to the
#      toolchain's bin/apv-serve). Untracked and regenerated each run — it
#      bakes the machine-/version-specific toolchain path, exactly like the
#      gate hooks. A pre-existing non-apv `bin/apv` is refused, never
#      clobbered.
#   4. Gitignore the local per-checkout state (`.last-capture`,
#      `.pending-extract`, `bin/apv`).
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
# A short project-root entry point — `bin/apv` — so nobody has to type
# `python3 <toolchain>/scripts/...` by hand. The shim is a pure passthrough
# to the toolchain's bin/apv dispatcher (serve / init / backfill / refresh),
# so new subcommands arrive with a plugin update, no re-init needed.
# Generated (never hand-authored), untracked — like the gate hooks it bakes
# the machine- and version-specific toolchain path — and regenerated on every
# init so a plugin update that moves the toolchain home is picked up by a
# re-run. Because bin/ is project-owned, a pre-existing NON-apv bin/apv is
# refused, never clobbered (the hook installers' contract, applied here).
LAUNCHER_PATH="bin/apv"
LAUNCHER_OK=1
# Write the desired launcher to $1. The dispatcher body goes through a QUOTED
# heredoc (no expansion — its `case`/`)`/`$@` are literal, and there is no
# surrounding command substitution to close early), while the one dynamic
# value (the toolchain path) is baked via `printf %q`, which shell-quotes any
# path safely. The `apv:launcher` marker on line 2 is the foreign-file guard's
# fingerprint.
gen_launcher() {
  {
    printf '#!/usr/bin/env bash\n'
    printf '# apv:launcher (generated) — local APV command launcher.\n'
    printf '# GENERATED by apv-init; UNTRACKED and regenerated on re-init. Do not\n'
    printf '# commit or hand-edit: the toolchain path below is machine- and\n'
    printf '# version-specific. After a plugin update, re-run /apv-init to refresh it.\n'
    printf 'TOOLCHAIN=%q\n' "$TOOLCHAIN_HOME"
    cat <<'LAUNCH'
exec "$TOOLCHAIN/bin/apv" "$@"
LAUNCH
  } > "$1"
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
    report updated "$LAUNCHER_PATH" "toolchain path refreshed"
  else
    report created "$LAUNCHER_PATH" "run it: ./$LAUNCHER_PATH (serves the view UI)"
  fi
fi

# --- 4. gitignore the local per-checkout state -------------------------------
# The stamp (guard), the pending-extract flag (extractor's post-commit half),
# and the generated command launcher are per-checkout local state; never
# tracked. One line each, appended once. (A refused foreign bin/apv is left
# out — we do not ignore a file we do not own.)
IGNORE_LINES=("$DATA_DIR/.last-capture" "$DATA_DIR/.pending-extract")
[ "$LAUNCHER_OK" -eq 1 ] && IGNORE_LINES+=("$LAUNCHER_PATH")
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
IGNORE_DETAIL=".last-capture + .pending-extract"
[ "$LAUNCHER_OK" -eq 1 ] && IGNORE_DETAIL="$IGNORE_DETAIL + bin/apv"
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
  GATE_HOME_ARGS=()
  [ "$VENDORED" -eq 0 ] && GATE_HOME_ARGS=(--home="$TOOLCHAIN_HOME")
  if [ "$AT" = "all" ] || [ "$AT" = "pre-push" ]; then
    run_installer "pre-push (gate)" bash "$TOOLCHAIN_HOME/scripts/install-gate.sh" --at=pre-push "${GATE_HOME_ARGS[@]}"
  fi
  if [ "$AT" = "all" ] || [ "$AT" = "ref-update" ]; then
    run_installer "reference-transaction (gate)" bash "$TOOLCHAIN_HOME/scripts/install-gate.sh" --at=ref-update "${GATE_HOME_ARGS[@]}"
  fi
  # Autonomous capture is opt-in (T3-autonomous-extractor §2.2): the
  # commit-msg extractor produces captures for non-session committers;
  # the pre-commit guard detects it and defers.
  if [ "$WITH_EXTRACTOR" -eq 1 ]; then
    run_installer "commit-msg (apv-extract)" bash "$TOOLCHAIN_HOME/scripts/install-extractor.sh" "${GATE_HOME_ARGS[@]}"
  fi
fi

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
  echo "  - Work normally; run /apv-capture after each logical unit of work,"
  echo "    immediately before committing. The guard catches you if you forget."
  echo "  - Land branches on main via /apv-merge; the gate keeps main trustworthy."
  echo "  - See the UI: run ./$LAUNCHER_PATH (then open the printed view URL)."
  echo "  - This attaches from NOW: history before today is not mined (that is"
  echo "    backfill, a separate opt-in step)."
else
  echo "apv-init: attached WITH REFUSALS (see above) — inspect the refused"
  echo "apv-init: component(s), merge or remove the foreign hook(s) manually,"
  echo "apv-init: then re-run. Re-running repairs only what is missing."
fi
exit "$FAIL"
