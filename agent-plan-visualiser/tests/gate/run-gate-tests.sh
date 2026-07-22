#!/usr/bin/env bash
# run-gate-tests.sh — fixture verification for gate-composite.py
# (T3-integrity-composite §4 items 2–4, plus a real-log re-run of item 1).
# Exits 0 when every case passes; 1 on the first failure.
set -uo pipefail
cd "$(dirname "$0")" || exit 2
GATE="../../scripts/gate-composite.py"
REPO_ROOT="$(cd ../../.. && pwd)"
FAIL=0

# Fixture caches are derived — rebuild from scratch every run so a stale
# cache (same event count, different content) can't mask a regression.
rm -f fixture-corrupt/cache.sqlite fixture-drift/cache.sqlite fixture-attention/cache.sqlite \
      fixture-project-move/cache.sqlite fixture-project-move-nodecision/cache.sqlite \
      fixture-attribution-drift/cache.sqlite

check() { # check <desc> <test-expr...>
  local desc="$1"; shift
  if "$@"; then
    echo "  ok: $desc"
  else
    echo "  FAIL: $desc"
    FAIL=1
  fi
}

check_absent() { # check_absent <desc> <grep-pattern> — pattern must NOT match $OUT
  local desc="$1" pattern="$2"
  if grep -q "$pattern" <<<"$OUT"; then
    echo "  FAIL: $desc"
    FAIL=1
  else
    echo "  ok: $desc"
  fi
}

run_case() { # run_case <name> <data-dir> <config> -> sets OUT, CODE
  local name="$1" data="$2" cfg="$3"
  echo "== $name"
  OUT="$(python3 "$GATE" --data-dir "$data" --config "$cfg" --planning-dir fixture-drift-planning 2>&1)"
  CODE=$?
}

# --- Case 0: apvlib registry parsing (T3-project-attribution) -------------
# dirs carve-outs, default-project resolution, named_owners longest-prefix —
# asserted on BOTH parser paths (tomllib and the minimal fallback), plus the
# fail-loud negatives (duplicate dir, non-list dirs, absolute/escaping/empty
# entries, cross-type prefix collision).
echo "== apvlib config layer (dirs carve-outs, named owners)"
if python3 - <<'PYEOF'
import sys, tempfile
from pathlib import Path
sys.path.insert(0, "../../scripts")
import apvlib

fail = [0]
def t(desc, cond):
    print(("  ok: " if cond else "  FAIL: ") + desc)
    if not cond: fail[0] = 1

root = Path(tempfile.mkdtemp())
cfg = root / "cfg.toml"
cfg.write_text(
    '[storage]\ndata_dir = ".apv"\n\n'
    '[projects.website]\nplanning_dir = "site/planning"\ndirs = ["site/", "docs/site/"]\n\n'
    '[projects.plugin]\nplanning_dir = "plugin/planning"\ndirs = ["plugin/"]\n'
)

for label in ("tomllib", "minimal"):
    saved = apvlib.tomllib
    if label == "minimal": apvlib.tomllib = None
    try:
        projects = apvlib.apv_projects(root, cfg)
        t(f"{label}: dirs parsed", projects["website"]["dirs"] == ["site/", "docs/site/"]
                                   and projects["plugin"]["dirs"] == ["plugin/"])
        t(f"{label}: default is implicit main", apvlib.apv_default_project(root, cfg) == "main")
        t(f"{label}: planning_dir implicitly owned",
          ("website", "site/planning/") in apvlib.apv_owned_prefixes(root, cfg))
        t(f"{label}: named_owners collects distinct owners",
          apvlib.named_owners(root, ["site/a.js", "plugin/b.py", "README.md"], cfg) == ["website", "plugin"])
        t(f"{label}: longest prefix wins on nesting",
          apvlib.named_owners(root, ["docs/site/x.md"], cfg) == ["website"])
        t(f"{label}: default territory unowned",
          apvlib.named_owner_of(root, "README.md", cfg) is None)
    finally:
        apvlib.tomllib = saved

renamed = root / "renamed.toml"
renamed.write_text('[projects.core]\nplanning_dir = "planning"\ndirs = ["stuff/"]\n\n'
                   '[projects.website]\nplanning_dir = "site/planning"\ndirs = ["site/"]\n')
t("renamed default resolves", apvlib.apv_default_project(root, renamed) == "core")
t("renamed default contributes no carve-outs",
  {n for n, _ in apvlib.apv_owned_prefixes(root, renamed)} == {"website"})

t("no registry: no owners, main default",
  apvlib.named_owners(root, ["site/a.js"], root / "missing.toml") == []
  and apvlib.apv_default_project(root, root / "missing.toml") == "main")

bad = root / "bad.toml"
negatives = [
    ("duplicate dir across projects raises",
     '[projects.a]\nplanning_dir = "pa"\ndirs = ["x/"]\n[projects.b]\nplanning_dir = "pb"\ndirs = ["x/"]\n'),
    ("non-list dirs raises", '[projects.a]\nplanning_dir = "pa"\ndirs = "x/"\n'),
    ("absolute dir raises", '[projects.a]\nplanning_dir = "pa"\ndirs = ["/abs"]\n'),
    ("escaping dir raises", '[projects.a]\nplanning_dir = "pa"\ndirs = ["../up"]\n'),
    ("empty dir entry raises", '[projects.a]\nplanning_dir = "pa"\ndirs = [""]\n'),
]
for desc, text in negatives:
    bad.write_text(text)
    try:
        apvlib.apv_projects(root, bad); t(desc, False)
    except ValueError:
        t(desc, True)

bad.write_text('[projects.a]\nplanning_dir = "pa"\ndirs = ["site/planning/"]\n\n'
               '[projects.b]\nplanning_dir = "site/planning"\n')
try:
    apvlib.apv_owned_prefixes(root, bad); t("cross-type prefix collision raises", False)
except ValueError:
    t("cross-type prefix collision raises", True)

sys.exit(fail[0])
PYEOF
then :; else FAIL=1; fi

# --- Case 1: corrupted log, default config (§4.2) -----------------------
# Four distinct corruptions, each named; schema + fulcrum stay clean.
run_case "corrupt fixture / default config" fixture-corrupt config-default.toml
check "exit 1"                                  [ "$CODE" -eq 1 ]
check "4 BLOCK lines"                           [ "$(grep -c '^BLOCK' <<<"$OUT")" -eq 4 ]
check "referential: dangling decision ref"      grep -q '^BLOCK \[referential\].*deadbeef' <<<"$OUT"
check "implementation-on-draft names FIX-A"     grep -q "^BLOCK \[implementation-on-draft\].*'FIX-A'" <<<"$OUT"
check "resurrection-without-reopen names FIX-B" grep -q "^BLOCK \[resurrection-without-reopen\].*'FIX-B'" <<<"$OUT"
check "sealed-tail: trailing run"               grep -q '^BLOCK \[sealed-tail\].*unsealed trailing' <<<"$OUT"
check_absent "schema check stays clean"         '^BLOCK \[schema\]'
check_absent "fulcrum check stays clean"        '^BLOCK \[fulcrum-without-decision\]'

# --- Case 2: drift fixture, default config (§4.3) ------------------------
# Stale frontmatter is advisory: warn reported, exit 0.
run_case "drift fixture / default config" fixture-drift config-default.toml
check "exit 0"                                  [ "$CODE" -eq 0 ]
check_absent "no BLOCK lines"                   '^BLOCK'
check "WARN [drift] names the stale seed"       grep -q "^WARN \[drift\].*'FIX-T2-OLD'.*FIX-T2-NEW" <<<"$OUT"

# --- Case 2b: multi-project roots — registry-resolved drift + duplicate ---
# No --planning-dir: the composite resolves roots from config-projects.toml
# ([projects.rootb] + [storage] as implicit main). Root B carries a copy of
# FIX-D3.md: the drift WARN must still fire (found via the registry) and the
# duplicate plan id must WARN, not block.
echo "== drift across registered roots (config-resolved, no --planning-dir)"
mkdir -p fixture-drift-planning-b
cp fixture-drift-planning/FIX-D3.md fixture-drift-planning-b/FIX-D3.md
OUT="$(python3 "$GATE" --repo-root . --data-dir fixture-drift --config config-projects.toml 2>&1)"
CODE=$?
rm -rf fixture-drift-planning-b
check "exit 0 (warn-only)"                      [ "$CODE" -eq 0 ]
check_absent "no BLOCK lines"                   '^BLOCK'
check "drift found via registry root"           grep -q "^WARN \[drift\].*'FIX-T2-OLD'.*FIX-T2-NEW" <<<"$OUT"
check "duplicate plan id warned"                grep -q "^WARN \[drift\].*duplicate plan id" <<<"$OUT"
check "duplicate names both roots"              grep -q "'rootb' and 'main'" <<<"$OUT"

# --- Case 3: config flip, blocking -> warn (§4.4) ------------------------
# sealed-tail demoted: same corrupt log now reports it as WARN; still exit 1
# on the three remaining blockers.
run_case "corrupt fixture / sealed-tail demoted to warn" fixture-corrupt config-flip-sealed-tail-warn.toml
check "exit 1 (three blockers remain)"          [ "$CODE" -eq 1 ]
check "3 BLOCK lines"                           [ "$(grep -c '^BLOCK' <<<"$OUT")" -eq 3 ]
check_absent "sealed-tail no longer blocks"     '^BLOCK \[sealed-tail\]'
check "sealed-tail surfaces as WARN"            grep -q '^WARN \[sealed-tail\]' <<<"$OUT"

# --- Case 4: config flip, warn -> blocking (§4.4) ------------------------
# drift promoted: the drift fixture now fails the gate.
run_case "drift fixture / drift promoted to blocking" fixture-drift config-flip-drift-blocking.toml
check "exit 1"                                  [ "$CODE" -eq 1 ]
check "BLOCK [drift] present"                   grep -q '^BLOCK \[drift\]' <<<"$OUT"

# --- Case 5: attention surfaces, default config ---------------------------
# T3-pending-ceremony-surfacing + T3-verification-deferred (M5.1): a draft
# plan and an all-T3s-closed-but-live milestone warn as pending ceremonies;
# an open verification.deferred warns until a later verification.* resolves
# it. All advisory — exit 0, no BLOCK lines.
run_case "attention fixture / default config" fixture-attention config-default.toml
check "exit 0 (all advisory)"                   [ "$CODE" -eq 0 ]
check_absent "no BLOCK lines"                   '^BLOCK'
check "acceptance ceremony pending"             grep -q "^WARN \[pending-ceremony\].*'FIX-ATT-DRAFT' is draft" <<<"$OUT"
check "closure ceremony pending"                grep -q "^WARN \[pending-ceremony\].*'M9-fix-att' has all 1 scheduled T3(s) closed" <<<"$OUT"
check "open deferral warns with reason"         grep -q "^WARN \[deferred-verification\].*'T3-fix-att-open'.*operator leg pending" <<<"$OUT"
check_absent "resolved deferral stays quiet"    "T3-fix-att-healed"

# --- Case 5b: project.assigned on a CLOSED entity is gate-clean -----------
# T3-retrospective-project-annotation: the membership assertion is
# state-neutral (absent from STATE_FROM_EVENT), so annotating a closed
# entity must NOT trip resurrection-without-reopen; the paired decision
# satisfies the fulcrum check; the cache folds the project while the
# derived state stays closed.
run_case "project assignment on closed entity / default config" fixture-project-move config-default.toml
check "exit 0"                                  [ "$CODE" -eq 0 ]
check_absent "no BLOCK lines"                   '^BLOCK'
check_absent "no resurrection block"            '\[resurrection-without-reopen\]'
PMROW="$(sqlite3 fixture-project-move/cache.sqlite \
  "SELECT project || '|' || derived_state FROM entities WHERE entity_id='FIX-PM';")"
check "cache folds project=rootb, still closed" [ "$PMROW" = "rootb|closed" ]

# --- Case 5c: project.assigned negatives ----------------------------------
# Unpaired assignment -> fulcrum block; assignment naming an unknown entity
# -> referential block (project.assigned events don't self-establish
# existence); 0.3.0-stamped assignment -> schema block (epoch stamping
# self-polices via per-version routing).
run_case "project assignment negatives / default config" fixture-project-move-nodecision config-default.toml
check "exit 1"                                  [ "$CODE" -eq 1 ]
check "fulcrum block names project.assigned"    grep -q '^BLOCK \[fulcrum-without-decision\].*project\.assigned' <<<"$OUT"
check "referential block names FIX-GHOST"       grep -q "^BLOCK \[referential\].*'FIX-GHOST'" <<<"$OUT"
check "schema block on the 0.3.0-stamped event" grep -q '^BLOCK \[schema\].*\[0\.3\.0\]' <<<"$OUT"

# --- Case 5d: attribution-drift — stamp vs file location ------------------
# T3-project-attribution: an OPEN plan stamped rootb whose file sits under
# the main root WARNs (the stamp is authoritative; the file is stale); the
# CLOSED plan in the same shape stays quiet (retrospective annotation
# without file moves is the blessed workflow). Advisory only — exit 0.
echo "== attribution-drift fixture / registry config"
OUT="$(python3 "$GATE" --repo-root . --data-dir fixture-attribution-drift --config config-attribution.toml 2>&1)"
CODE=$?
check "exit 0 (warn-only)"                      [ "$CODE" -eq 0 ]
check_absent "no BLOCK lines"                   '^BLOCK'
check "open stamped plan warns"                 grep -q "^WARN \[attribution-drift\].*'FIX-AD' asserted project 'rootb'.*root 'main'" <<<"$OUT"
check_absent "closed stamped plan stays quiet"  "\[attribution-drift\].*FIX-AD-CLOSED"

# --- Case 6: the real log, repo defaults (§4.1) --------------------------
echo "== real log / repo defaults"
OUT="$(cd "$REPO_ROOT" && python3 agent-plan-visualiser/scripts/gate-composite.py 2>&1)"
CODE=$?
check "exit 0 against this repo's log"          [ "$CODE" -eq 0 ]
check_absent "no BLOCK lines"                   '^BLOCK'

echo
if [ "$FAIL" -eq 0 ]; then
  echo "gate tests: ALL PASS"
else
  echo "gate tests: FAILURES (see above)"
fi
exit "$FAIL"
