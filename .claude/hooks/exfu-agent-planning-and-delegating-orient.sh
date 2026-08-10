#!/bin/sh
# exfu-agent-planning-and-delegating SessionStart orientation hook.
# Installed by exfu-planning-init to <project>/.claude/hooks/exfu-agent-planning-and-delegating-orient.sh
# and registered as a project-scope SessionStart hook. Its stdout is consumed as
# additionalContext. Deterministic, no network, always exits 0. The lines below
# are PINNED (asserted by T3-global-local-init VH) and must stay in substance
# with the CLAUDE.md exfu-agent-planning-and-delegating:orientation block.
cat <<'EOF'
exfu-agent-planning-and-delegating: this project depends on the exfu-agent-planning-and-delegating plugin (ExFu Planning
Methodology + grounded delegation; skills: exfu-delegate, exfu-grounding,
exfu-planning-methodology), wired via .exfu/providers.toml.
Confirm now that exfu-agent-planning-and-delegating:* skills are available. If they are NOT (this
session did not load the plugin), resolve the source in order:
  (a) `claude plugin list --json` -> the enabled exfu-agent-planning-and-delegating install path;
  (b) else the highest-version match under
      ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/*/exfu-agent-planning-and-delegating/*/skills/<name>/SKILL.md;
  (c) else install it:
      claude plugin marketplace add https://github.com/ExFu/exfu-marketplace.git
      claude plugin install exfu-agent-planning-and-delegating@exfu
EOF
exit 0
