#!/usr/bin/env bash
# audit-toolchain-paths.sh — no live surface may address the toolchain by a
# path that only resolves in the dogfood layout.
#
# The bug this exists to prevent (2026-07-23): every shipped instruction and
# script that said `agent-plan-visualiser/scripts/...` worked perfectly in
# APV's own repo and failed with `No such file or directory` for every
# plugin-cache install — including step 1 of /apv-capture's mandatory
# pre-commit validation. It survived because the toolchain and the tracked
# repo are the same tree in dogfood, and only there.
#
# Three defect shapes are hunted:
#   1. an UNGUARDED `agent-plan-visualiser/<toolchain-subdir>/` reference
#      (a guarded fallback rung, `[ -f "agent-plan-visualiser/..." ]`, is
#      deliberate and quoted — the lookbehind lets those through);
#   2. `cd "$(dirname "$0")/../.."` — assumes the toolchain is vendored one
#      level below a repo root;
#   3. a `bash <script>` invocation of the validate/repack family that is not
#      anchored on $APV / ${CLAUDE_PLUGIN_ROOT} / $TOOLCHAIN. Three of the ten
#      references to repack-validate.sh in the 0.7.0 package were BARE names
#      containing no `agent-plan-visualiser/` substring — a fix campaign
#      driven by the folder prefix alone leaves them behind, so they get
#      their own pattern.
#
# Allowlist (the allowlist IS the doctrine):
#   - planning/            append-only record; plans state what was true then.
#   - .agent-plan-tracker/ the dogfood DATA dir, same rule.
#   - tests/               the dev harness legitimately builds both layouts.
#   - this file            necessarily contains the patterns it hunts.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 2

python3 - <<'PYEOF'
import re, subprocess, sys

# 1. Unguarded toolchain-relative path. The lookbehind exempts `"..."`-quoted
#    and `$`-prefixed forms: the guarded vendored rungs in hooks/ are correct.
BARE_PATH = re.compile(
    r'(?<!["$/])agent-plan-visualiser/(?:scripts|schemas|hooks|bin|view)/'
)
# 2. The dogfood-layout cd.
BARE_CD = re.compile(r'cd\s+"\$\(dirname\s+"\$0"\)/\.\./\.\."')
# 3. An unanchored invocation of the pipeline scripts.
INVOKE = re.compile(
    r'\b(?:bash|sh|python3)\s+\S*\b'
    r'(repack-validate\.sh|validate-events\.sh|validate-plan-frontmatter\.sh'
    r'|gate-check\.sh|cache-build\.py|projection-emit\.py|summary-emit\.py)'
)
ANCHORED = re.compile(r'\$APV|CLAUDE_PLUGIN_ROOT|\$TOOLCHAIN|\$SCRIPT_DIR|\$APV_HOME|\$newest')


def allowed_file(p: str) -> bool:
    if p == "agent-plan-visualiser/tests/audit-toolchain-paths.sh":
        return True
    # CLAUDE.md is this repo's OWN orientation file, not a shipped surface:
    # it describes the dogfood checkout, where these paths are correct.
    if p == "CLAUDE.md":
        return True
    return (
        p.startswith("planning/")
        or p.startswith(".agent-plan-tracker/")
        or p.startswith("agent-plan-visualiser/tests/")
    )


files = subprocess.run(["git", "ls-files"], capture_output=True, text=True,
                       check=True).stdout.splitlines()
# BLOCKING = a live surface: something an agent or user actually executes, or
# text a running program prints as guidance. ADVISORY = a `#` header comment
# (an install banner nobody pipes to a shell). Both are wrong; only the first
# breaks a documented workflow, and conflating them would either let real
# defects hide in the noise or hold the suite hostage to comment drift.
blocking, advisory = [], []
for f in files:
    if allowed_file(f):
        continue
    try:
        with open(f, encoding="utf-8") as fh:
            text = fh.read()
    except (UnicodeDecodeError, FileNotFoundError, IsADirectoryError):
        continue  # binary or deleted-in-worktree
    for n, line in enumerate(text.splitlines(), 1):
        stripped = line.strip()
        comment = stripped.startswith("#")
        kind = None
        if BARE_PATH.search(line):
            kind = "toolchain-relative path"
        # A commented-out cd documents what was removed — not a live surface.
        elif BARE_CD.search(line) and not comment:
            kind = "dogfood-layout cd"
        elif INVOKE.search(line) and not ANCHORED.search(line):
            kind = "unanchored invocation"
        if kind:
            # A path the text itself labels as the dogfood case is a
            # documented fallback, not a mis-instruction — the reader has
            # been told which layout it applies to.
            soft = comment or "dogfood" in line.lower()
            (advisory if soft else blocking).append(
                f"{f}:{n}: [{kind}] {stripped[:110]}"
            )

if advisory:
    print(f"audit-toolchain-paths: {len(advisory)} advisory (comment-only, non-blocking):")
    print("\n".join("  " + h for h in advisory))
if blocking:
    print("audit-toolchain-paths: FAIL — live surfaces that only resolve in dogfood:")
    print("\n".join(blocking))
    sys.exit(1)
print(f"audit-toolchain-paths: PASS — {len(files)} tracked files, no dogfood-only live surfaces")
PYEOF
