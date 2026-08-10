#!/bin/sh
# extract-amend.sh — agent-plan-visualiser post-commit hook (apv-extract).
#
# Second half of autonomous capture: git writes the commit's TREE before
# the commit-msg hook runs, so the block extract-capture.sh appends there
# cannot ride the commit it seals. This hook closes the gap — when the
# extractor left its pending flag, amend the just-created commit to
# include the log. The amended commit is the same logical commit, local
# and pre-push; the seal's message_first_line is unchanged.
#
# Recursion-safe: the flag is consumed before amending, and the amend
# itself runs --no-verify (pre-commit and commit-msg skipped; this
# post-commit re-fires, finds no flag, no-ops).
#
# Install: bash agent-plan-visualiser/scripts/install-extractor.sh
#          (installed alongside the commit-msg extractor).

# Data dir resolution mirrors capture-guard/apvlib: env -> config -> .apv/.
if [ -n "${APV_DATA_DIR:-}" ]; then
  DATA_DIR="$APV_DATA_DIR"
else
  DATA_DIR=$(sed -n 's/^[[:space:]]*data_dir[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' .apv-config.toml 2>/dev/null | head -n 1)
  [ -n "$DATA_DIR" ] || DATA_DIR=".apv"
fi

FLAG="$DATA_DIR/.pending-extract"
[ -f "$FLAG" ] || exit 0
rm -f "$FLAG"

git add "$DATA_DIR/events.jsonl" || exit 0
if ! GIT_EDITOR=: git commit --amend --no-edit --no-verify --quiet; then
  echo "apv-extract: WARNING — could not amend the extracted block into the" >&2
  echo "apv-extract: commit; $DATA_DIR/events.jsonl remains staged for the next one." >&2
fi
exit 0
