#!/bin/sh
# gate-refupdate.sh — agent-plan-tracker reference-transaction hook: the
# LOCAL belt-and-braces (third adapter in the T3-gate-core §2.2 family;
# operator ruling 2026-06-10: gate local merges, not just pushes).
#
# Refuses any local update of refs/heads/main when gate-check fails on the
# incoming commit. This is the only hook that sees a fast-forward merge —
# the standard /apt-merge landing — which runs neither pre-merge-commit nor
# pre-commit. It equally gates merge commits, direct commits on main,
# amends, rebases and resets: main never points at a red log.
#
# Same contract as the pre-push adapter: strict --ref mode on the prepared
# oid; only refs/heads/main; deletions and no-op updates skip. Branch
# moves are work-in-flight and never gated.
#
# reference-transaction has no --no-verify equivalent, so the sanctioned
# escape hatch is explicit: APT_SKIP_GATE=1 git merge ...  For tooling
# breakage, not for landing red logs — integrity defects are repaired,
# not overridden.
#
# Git updates the worktree BEFORE the ref transaction in a fast-forward
# merge (verified empirically). Two consequences: repo-relative gate-check
# resolution works even for the adoption merge that delivers the toolchain
# itself; and a refused ff may leave the worktree updated — HEAD has not
# moved, so `git reset --hard HEAD` restores the files.
#
# Invocation: $1 is the transaction state (prepared|committed|aborted);
# stdin carries one "<old-oid> <new-oid> <ref-name>" line per update.
# Only "prepared" is abortable — everything else exits 0 immediately.

[ "${1:-}" = "prepared" ] || exit 0

ZERO="0000000000000000000000000000000000000000"

resolve_gate_check() {
  if [ -n "${APT_GATE_CHECK:-}" ]; then
    GATE_CHECK="$APT_GATE_CHECK"
  elif [ -f "agent-plan-tracker/scripts/gate-check.sh" ]; then
    # Hooks run from the top of the working tree.
    GATE_CHECK="agent-plan-tracker/scripts/gate-check.sh"
  else
    GATE_CHECK="$(command -v gate-check.sh || true)"
  fi
  [ -n "$GATE_CHECK" ]
}

status=0
while read -r old new ref; do
  [ "$ref" = "refs/heads/main" ] || continue
  [ "$new" = "$ZERO" ] && continue   # deletion: nothing incoming to gate
  [ "$new" = "$old" ] && continue    # no-op update: nothing moved

  if [ -n "${APT_SKIP_GATE:-}" ]; then
    echo "apt: gate on refs/heads/main skipped (APT_SKIP_GATE set) — repair the log before this state spreads." >&2
    continue
  fi

  if ! resolve_gate_check; then
    echo "apt: local update of refs/heads/main refused — gate-check not found (APT_GATE_CHECK, repo scripts/, or PATH)." >&2
    status=1
    continue
  fi

  if ! bash "$GATE_CHECK" --repo-root "$(pwd)" --ref "$new"; then
    echo "apt: local update of refs/heads/main refused — gate-check failed on $new." >&2
    echo "apt: repair the log on the branch (integrity defects are repaired, not overridden), then merge again." >&2
    echo "apt: APT_SKIP_GATE=1 is the escape hatch for tooling breakage only." >&2
    status=1
  fi
done

exit "$status"
