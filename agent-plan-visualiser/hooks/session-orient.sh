#!/bin/sh
# session-orient.sh — agent-plan-visualiser SessionStart hook (Claude-side,
# via hooks/hooks.json; distinct from the git hooks sharing this dir).
#
# The third knowledge channel (T3-session-orientation): skills fire on
# recognised relevance, refusals fire on mistakes — this gives a fresh
# session ambient awareness that the repo is tracked, before it works.
#
# Contract: read-only, fast (no cache rebuild, no git calls, no python).
# Tracked repo -> one orientation line on stdout (SessionStart stdout is
# added to the session's context). Untracked repo -> silence, exit 0 —
# no nagging to adopt; silence is a feature.

cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0

# Data dir resolution mirrors capture-guard/apvlib: APV_DATA_DIR env var ->
# committed .apv-config.toml [storage] data_dir -> default .apv/. Same
# deliberate one-key POSIX sed as the guard — dependency-free and fast.
if [ -n "${APV_DATA_DIR:-}" ]; then
  DATA_DIR="$APV_DATA_DIR"
else
  DATA_DIR=$(sed -n 's/^[[:space:]]*data_dir[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' .apv-config.toml 2>/dev/null | head -n 1)
  [ -n "$DATA_DIR" ] || DATA_DIR=".apv"
fi

# The fingerprint is the log itself (fingerprint facts only — counts and
# status are the analyser's job, on demand).
[ -f "$DATA_DIR/events.jsonl" ] || exit 0

# Skills ship plugin-namespaced; say so, and when the plugin root is known
# (hooks receive CLAUDE_PLUGIN_ROOT) give the literal source path too, so
# even a session whose skill listing is truncated — or a subagent — can
# read the SKILL.md directly instead of concluding the skill is missing.
SKILL_HINT="the skills are plugin-namespaced (agent-plan-visualiser:apv-capture etc.)"
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && SKILL_HINT="$SKILL_HINT, sources at $CLAUDE_PLUGIN_ROOT/skills/<name>/SKILL.md"
echo "apv: this project is tracked by agent-plan-visualiser — the append-only event log at $DATA_DIR/events.jsonl is the source of truth for planning state. Run /apv-capture after each logical unit of work, immediately before every commit (the pre-commit guard rejects uncaptured commits); land branches on main via /apv-merge; $SKILL_HINT. For how the tracking works, see the using-agent-plan-visualiser skill."
exit 0
