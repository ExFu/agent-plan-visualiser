"""aptlib — shared helpers for the agent-plan-tracker pipeline scripts.

Data-dir resolution (T3-configurable-data-dir + T3-integrity-composite §2.3)
and committed-config parsing. Scripts in this directory can `import aptlib`
directly: Python puts a script's own directory on sys.path when the script
is invoked by path.
"""
import os
from pathlib import Path

try:
    import tomllib  # stdlib, Python >= 3.11
except ModuleNotFoundError:  # pragma: no cover — pre-3.11 interpreters
    tomllib = None


def apt_config(repo_root: Path, config_path=None) -> dict:
    """Parse the committed `.apt-config.toml` at the repo root.

    Returns {} when the file is absent or tomllib is unavailable (< 3.11) —
    every consumer has sane defaults. A *present but malformed* file raises:
    silently ignoring a typo'd config could route data to the wrong
    directory, which is worse than failing loud. Unknown keys are tolerated
    by design (the file accrues future config).
    """
    path = Path(config_path) if config_path else (repo_root / ".apt-config.toml")
    if tomllib is None or not path.exists():
        return {}
    with open(path, "rb") as f:
        return tomllib.load(f)


def apt_data_dir(repo_root: Path, config_path=None) -> Path:
    """Resolve the tracking data directory (events.jsonl, cache, projection...).

    Precedence: APT_DATA_DIR env var (absolute, or relative to repo_root),
    else `.apt-config.toml` `[storage] data_dir`, else the default
    `.agent-plan-tracker/`. Plugin content (schemas, scripts, view) is code,
    not data — it never lives here and is unaffected.
    """
    override = os.environ.get("APT_DATA_DIR")
    if override:
        p = Path(override)
        return p if p.is_absolute() else repo_root / p
    cfg_dir = (apt_config(repo_root, config_path).get("storage") or {}).get("data_dir")
    if cfg_dir:
        p = Path(cfg_dir)
        return p if p.is_absolute() else repo_root / p
    return repo_root / ".agent-plan-tracker"
