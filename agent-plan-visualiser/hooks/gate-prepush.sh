#!/bin/sh
# gate-prepush.sh — agent-plan-visualiser pre-push adapter (T3-gate-core §2.2).
#
# Belt-and-braces enforcement of the merge-to-main gate: refuses a push
# that moves refs/heads/main when gate-check fails on the outgoing state.
# Branch pushes are work-in-flight by doctrine and pass untouched
# (T3-gate-core §6 Q1). The primary enforcement path is procedural — the
# /apv-merge skill runs gate-check before a branch lands — this hook only
# catches what slips past it.
#
# Install:  bash agent-plan-visualiser/scripts/install-gate.sh
#           (or copy this file to your hooks dir as `pre-push`, chmod +x).
# Bypass:   git push --no-verify — sanctioned, but integrity defects are
#           repaired, not overridden (M3-clean-gate §4); bypass is for
#           emergencies, not disagreements with the gate.
#
# stdin: one line per ref being pushed:
#   <local-ref> SP <local-sha> SP <remote-ref> SP <remote-sha> LF
# Git runs pre-push hooks from the top of the working tree, so relative
# paths below resolve against the repo root.

ZERO=0000000000000000000000000000000000000000

# Baked by the installer (install-gate.sh --home=<dir>) into installed
# copies — the deciding happens once, at install. Empty in the source:
# the vendored/dev case falls through to the repo-relative step.
APV_HOME=""

# The check itself lives with the toolchain, not in the hooks dir.
# Resolution: APV_GATE_CHECK env override -> the baked toolchain home ->
# the vendored layout relative to the repo root -> PATH (--at=manual).
resolve_gate_check() {
  if [ -n "${APV_GATE_CHECK:-}" ] && [ -f "$APV_GATE_CHECK" ]; then
    echo "$APV_GATE_CHECK"
    return 0
  fi
  if [ -n "$APV_HOME" ] && [ -f "$APV_HOME/scripts/gate-check.sh" ]; then
    echo "$APV_HOME/scripts/gate-check.sh"
    return 0
  fi
  if [ -f "agent-plan-visualiser/scripts/gate-check.sh" ]; then
    echo "agent-plan-visualiser/scripts/gate-check.sh"
    return 0
  fi
  # Plugin-cache installs are not baked (a pinned cache path would freeze
  # the repo at the installing version — old versions stay on disk); the
  # newest installed version resolves at run time, launcher-style.
  newest="$(ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/*/agent-plan-visualiser/*/ 2>/dev/null | sort -V | tail -n 1)"
  newest="${newest%/}"
  if [ -n "$newest" ] && [ -f "$newest/scripts/gate-check.sh" ]; then
    echo "$newest/scripts/gate-check.sh"
    return 0
  fi
  command -v gate-check.sh 2>/dev/null && return 0
  return 1
}

status=0
while read -r local_ref local_sha remote_ref remote_sha; do
  [ "$remote_ref" = "refs/heads/main" ] || continue
  # Deleting remote main pushes no state — nothing outgoing to gate.
  [ "$local_sha" = "$ZERO" ] && continue

  GATE_CHECK="$(resolve_gate_check)" || {
    echo "apv: gate-check.sh not found (set APV_GATE_CHECK, or install the" >&2
    echo "apv: toolchain at agent-plan-visualiser/scripts/, or put it on PATH)." >&2
    exit 1
  }
  if ! bash "$GATE_CHECK" --repo-root "$(pwd)" --ref "$local_sha"; then
    echo "apv: push of refs/heads/main refused — gate-check failed on $local_sha." >&2
    echo "apv: repair the log (integrity defects are repaired, not overridden);" >&2
    echo "apv: git push --no-verify is the sanctioned escape hatch if you must." >&2
    status=1
  fi
done

exit $status
