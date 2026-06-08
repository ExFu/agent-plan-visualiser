---
id: T3-configurable-data-dir
plan_kind: thematic
tier: 3
t2_parent: T2-storage
milestone: M2-auto-extract
status: draft
---

# T3-configurable-data-dir — Make the data directory configurable via `APT_DATA_DIR`

**Status**: Draft.
**Sits at**: T2-storage theme, M2-auto-extract milestone. Foundation T3 — prerequisite for shadow-dev and eventually for M4 fresh-project installs.

---

## 1. Why

Every pipeline script (`cache-build.py`, `projection-emit.py`, `summary-emit.py`, `serve.py`) hardcodes `.agent-plan-tracker/` as the data directory. This blocks two things:

- **M2 shadow-dev.** The capture skill needs to write into a throwaway `.agent-plan-tracker-auto/` while being tuned, without touching the canonical hand-rolled log.
- **M4 fresh-install.** Other projects will need their own data dirs; hardcoding this project's path doesn't generalise.

## 2. What

A single shared path resolver that every script imports. Resolution precedence:

1. **`APT_DATA_DIR` environment variable** — if set, use it (absolute or relative to repo root).
2. **Fallback default** — `.agent-plan-tracker/`.

No config file, no CLI flag, no complexity. An env var is the simplest mechanism that works for both shadow-dev (`APT_DATA_DIR=.agent-plan-tracker-auto/ python3 scripts/cache-build.py`) and future tooling.

## 3. Scope

### In scope
- Create the resolver (a small Python module or function; all scripts already use Python).
- Repoint `cache-build.py`, `projection-emit.py`, `summary-emit.py`, `serve.py` to use it instead of hardcoding `REPO_ROOT / ".agent-plan-tracker/..."`.
- Add `.agent-plan-tracker-auto/` to `.gitignore`.
- Verify: `repack-validate.sh` passes with no env var set (default path, no regression), and passes with `APT_DATA_DIR=.agent-plan-tracker-auto/` after seeding that dir with a copy of events.jsonl.

### Out of scope
- Repointing `backfill.py` — it already takes `--output` and `--project-path` flags; M5 concern.
- Repointing the HTML view's `projection.json` fetch path — that's a JS-side concern for later.
- Config-file-based defaults — YAGNI for now; env var is sufficient.

## 4. Approach

The resolver is ~10 lines:

```python
import os
from pathlib import Path

def apt_data_dir(repo_root: Path) -> Path:
    override = os.environ.get("APT_DATA_DIR")
    if override:
        p = Path(override)
        return p if p.is_absolute() else repo_root / p
    return repo_root / ".agent-plan-tracker"
```

Each script replaces its hardcoded `REPO_ROOT / ".agent-plan-tracker/..."` with a call to this function. The resolver lives alongside the scripts (e.g. `scripts/aptlib.py` or inline in each script — decide during implementation based on import ergonomics).

## 5. Verification

1. `repack-validate.sh` green with **no** env var (regression check — default path).
2. Seed `.agent-plan-tracker-auto/events.jsonl` (copy from canonical), run pipeline with `APT_DATA_DIR=.agent-plan-tracker-auto/`, confirm cache/projection/summary build there.
3. Canonical `.agent-plan-tracker/` untouched during step 2.

## 6. Dependencies

- None (foundation T3, parallel to `T3-apt-capture-skill`).

## 7. Open questions

1. **Resolver location.** Inline in each script (simplest, some duplication) vs shared `scripts/aptlib.py` (DRYer, one more import). Lean shared module since 4+ scripts need it.
