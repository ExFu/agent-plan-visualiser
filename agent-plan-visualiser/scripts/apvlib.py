"""apvlib — shared helpers for the agent-plan-visualiser pipeline scripts.

Data-dir resolution (T3-configurable-data-dir + T3-integrity-composite §2.3)
and committed-config parsing. Scripts in this directory can `import apvlib`
directly: Python puts a script's own directory on sys.path when the script
is invoked by path.
"""
import json
import os
import re
from pathlib import Path

try:
    import tomllib  # stdlib, Python >= 3.11
except ModuleNotFoundError:  # pragma: no cover — pre-3.11 interpreters
    tomllib = None

_BARE_KEY = re.compile(r"[A-Za-z0-9_-]+\Z")


def _parse_toml_minimal(text: str, source: str) -> dict:
    """Restricted TOML reader for interpreters without tomllib (< 3.11,
    e.g. stock macOS python3 at 3.9).

    Covers exactly the shapes `.apv-config.toml` uses — `[section]` tables,
    bare keys, double-quoted strings, booleans, integers, and single-line
    arrays of double-quoted strings (all valid JSON, so values delegate to
    json.loads) — and raises ValueError on anything else. A half-understood
    config must fail loud, never silently degrade to defaults: the committed
    config is policy, and ignoring it is the risk hardcoding was rejected
    for (M3-clean-gate §3.3).
    """
    out, table = {}, None
    for n, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            name = line[1:-1].strip()
            if not _BARE_KEY.match(name):
                raise ValueError(f"{source} line {n}: unsupported table {line!r}")
            table = out.setdefault(name, {})
            continue
        key, eq, value = (p.strip() for p in line.partition("="))
        if not eq or not _BARE_KEY.match(key):
            raise ValueError(f"{source} line {n}: unsupported syntax {line!r}")
        try:
            parsed = json.loads(value)
        except json.JSONDecodeError:
            raise ValueError(
                f"{source} line {n}: value not in the supported TOML subset "
                f"(strings, booleans, integers, arrays of strings): {value!r}"
            ) from None
        ok = isinstance(parsed, (str, bool, int, float)) or (
            isinstance(parsed, list) and all(isinstance(x, str) for x in parsed)
        )
        if not ok:
            raise ValueError(f"{source} line {n}: unsupported value type for {key!r}")
        (out if table is None else table)[key] = parsed
    return out


def apv_config(repo_root: Path, config_path=None) -> dict:
    """Parse the committed `.apv-config.toml` at the repo root.

    Returns {} only when the file is absent — every consumer has sane
    defaults. A *present* file is always parsed: tomllib where available
    (>= 3.11), else the minimal subset reader. A present but malformed (or
    subset-exceeding) file raises: silently ignoring config could route
    data to the wrong directory or apply the wrong gate policy, which is
    worse than failing loud. Unknown keys are tolerated by design (the
    file accrues future config).
    """
    path = Path(config_path) if config_path else (repo_root / ".apv-config.toml")
    if not path.exists():
        return {}
    if tomllib is not None:
        with open(path, "rb") as f:
            return tomllib.load(f)
    return _parse_toml_minimal(path.read_text(encoding="utf-8"), str(path))


def apv_data_dir(repo_root: Path, config_path=None) -> Path:
    """Resolve the tracking data directory (events.jsonl, cache, projection...).

    Precedence: APV_DATA_DIR env var (absolute, or relative to repo_root),
    else `.apv-config.toml` `[storage] data_dir`, else the default `.apv/`
    (M4 ruling; this dogfood repo pins its pre-rename `.agent-plan-tracker/`
    via config). Plugin content (schemas, scripts, view) is code, not data —
    it never lives here and is unaffected.
    """
    override = os.environ.get("APV_DATA_DIR")
    if override:
        p = Path(override)
        return p if p.is_absolute() else repo_root / p
    cfg_dir = (apv_config(repo_root, config_path).get("storage") or {}).get("data_dir")
    if cfg_dir:
        p = Path(cfg_dir)
        return p if p.is_absolute() else repo_root / p
    return repo_root / ".apv"
