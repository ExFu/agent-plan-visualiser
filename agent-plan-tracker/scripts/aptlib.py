"""aptlib — shared helpers for the agent-plan-tracker pipeline scripts.

Currently just the data-dir resolver (T3-configurable-data-dir). Scripts in
this directory can `import aptlib` directly: Python puts a script's own
directory on sys.path when the script is invoked by path.
"""
import os
from pathlib import Path


def apt_data_dir(repo_root: Path) -> Path:
    """Resolve the tracking data directory (events.jsonl, cache, projection...).

    Precedence: APT_DATA_DIR env var (absolute, or relative to repo_root),
    else the default `.agent-plan-tracker/`. Plugin content (schemas, scripts,
    view) is code, not data — it never lives here and is unaffected.
    """
    override = os.environ.get("APT_DATA_DIR")
    if override:
        p = Path(override)
        return p if p.is_absolute() else repo_root / p
    return repo_root / ".agent-plan-tracker"
