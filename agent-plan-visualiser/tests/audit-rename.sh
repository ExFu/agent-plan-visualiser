#!/usr/bin/env bash
# audit-rename.sh — T3-toolchain-portability §4.3: no pre-rename references
# survive on live surfaces. Scans every tracked file except the documented
# allowlist and fails on any hit. The allowlist IS the doctrine:
#
#   - .agent-plan-tracker/        the dogfood DATA dir — append-only record,
#                                 never rewritten; the dir keeps its name
#                                 (pinned via .apv-config.toml).
#   - agent-plan-visualiser/schemas/   epoch-frozen contract artefacts —
#                                 they validate historical events and stay
#                                 byte-stable (0.3.0 even patterns on the
#                                 data dir's real name).
#   - closed plans               archaeology; their prose is true record.
#                                 (Any planning/*.md not in the live list.)
#   - T3-toolchain-portability.md the rename-mapping doc — shows old names
#                                 deliberately.
#   - two deliberate phrases     the rename note's "Renamed from" mapping
#                                 and T2-packaging's historical Q1 wording.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 2

python3 - <<'PYEOF'
import re, subprocess, sys
from pathlib import Path

# Plans that were live (non-closed) at rename time — the surfaces renamed.
# Closed-at-rename plans are archaeology forever; plans born later carry
# the new naming from birth, so this snapshot never needs extending.
LIVE_PLANS = {
    "T1-top-level", "T2-analyser", "T2-extraction", "T2-ingest", "T2-ontology",
    "T2-packaging", "T2-projection", "T2-storage", "M4-fresh-install",
    "T3-toolchain-portability", "T3-project-init-flow", "T3-session-orientation",
    "T3-distribution", "T3-autonomous-extractor",
}

ALLOWED_LINE = re.compile(
    r"Renamed from \*\*agent-plan-tracker\*\*"      # CLAUDE.md mapping note
    r"|Working name `agent-plan-tracker`"            # T2-packaging §7 Q1 history
)

PATTERNS = re.compile(
    r"(?<!\.)agent-plan-tracker"      # the dot guards the data dir's real name
    r"|APT_DATA_DIR|APT_GATE_CHECK|APT_SKIP_GATE"
    r"|aptlib|apt_config|apt_data_dir"
    r"|apt-capture|apt-merge"
    r"|\.apt-config"
)

def allowed_file(p: str) -> bool:
    if p == "agent-plan-visualiser/tests/audit-rename.sh":
        return True  # the audit necessarily contains the patterns it hunts
    if p.startswith(".agent-plan-tracker/"):
        return True
    if p.startswith("agent-plan-visualiser/schemas/"):
        return True
    if p == "planning/T3-toolchain-portability.md":
        return True
    if p.startswith("planning/"):
        stem = Path(p).stem
        return stem not in LIVE_PLANS  # closed plans are archaeology
    return False

files = subprocess.run(["git", "ls-files"], capture_output=True, text=True,
                       check=True).stdout.splitlines()
hits = []
for f in files:
    if allowed_file(f):
        continue
    try:
        text = Path(f).read_text(encoding="utf-8")
    except (UnicodeDecodeError, FileNotFoundError):
        continue  # binary or deleted-in-worktree
    for n, line in enumerate(text.splitlines(), 1):
        if PATTERNS.search(line) and not ALLOWED_LINE.search(line):
            hits.append(f"{f}:{n}: {line.strip()[:120]}")

if hits:
    print("audit-rename: FAIL — pre-rename references on live surfaces:")
    print("\n".join(hits))
    sys.exit(1)
print("audit-rename: PASS — no pre-rename references outside the allowlist")
PYEOF
