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

    Covers exactly the shapes `.apv-config.toml` uses — `[section]` and
    dotted `[section.sub]` tables (the `[projects.<name>]` registry), bare
    keys, double-quoted strings, booleans, integers, and single-line
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
            segments = [s.strip() for s in name.split(".")]
            if not all(_BARE_KEY.match(s) for s in segments):
                raise ValueError(f"{source} line {n}: unsupported table {line!r}")
            table = out
            for seg in segments:
                table = table.setdefault(seg, {})
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


def repo_root() -> Path:
    """The repo being OPERATED ON: the enclosing repo of the cwd, falling
    back to the toolchain's own repo (the vendored/dogfood case). The
    toolchain may live in the plugin cache, far from any tracked repo —
    a `parents[2]` default there points data resolution at the wrong tree
    (the same trap gate-check's repo-root default fixed in M4). Toolchain
    CONTENT (schemas, view) is never resolved through this — that stays
    relative to the script's own location."""
    import subprocess
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True, text=True,
        )
        if out.returncode == 0 and out.stdout.strip():
            return Path(out.stdout.strip())
    except OSError:
        pass
    return Path(__file__).resolve().parents[2]


# Headless extractor isolation (backfill.py + extract-commit.py). Two real-run
# incidents shaped this: a target project's autopilot Stop hook hijacked the
# session (exfu_website, 2026-07-07 — fixed by the neutral temp cwd), then a
# USER-scope plugin's hooks killed the claude process outright, non-zero exit,
# empty stderr, after extraction had completed (OMC, 2026-07-09). cwd isolation
# cannot reach user scope; these flags can. Each is added only when the
# installed CLI advertises it in --help — older CLIs hard-error on unknown
# flags, so degrading to fewer layers beats failing every call.
#   --safe-mode           all customizations off (plugins, hooks, MCP,
#                         CLAUDE.md); auth and model selection work normally
#   --settings {...}      disableAllHooks — the hook vector, on CLIs that
#                         predate --safe-mode
#   --strict-mcp-config   no ambient MCP servers
_ISOLATION_CANDIDATES = (
    ("--safe-mode", ["--safe-mode"]),
    ("--settings", ["--settings", '{"disableAllHooks": true}']),
    ("--strict-mcp-config", ["--strict-mcp-config"]),
)
_isolation_cache: dict = {}


def claude_isolation_flags(claude_bin: str) -> list:
    """Isolation flags the installed `claude` supports, probed from --help
    once per binary per process. A failed/hanging probe (missing binary,
    stubbed test model) yields [] — the invocation then proceeds exactly as
    it would have before isolation existed."""
    if claude_bin in _isolation_cache:
        return _isolation_cache[claude_bin]
    import subprocess
    try:
        help_text = subprocess.run(
            [claude_bin, "--help"], capture_output=True, text=True,
            stdin=subprocess.DEVNULL, timeout=20,
        ).stdout
    except Exception:
        help_text = ""
    flags = []
    for token, args in _ISOLATION_CANDIDATES:
        if token in help_text:
            flags += args
    _isolation_cache[claude_bin] = flags
    return flags


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


def apv_planning_dir(repo_root: Path, config_path=None) -> Path:
    """Resolve the plans directory (the T1/T2/T3/M/L plan documents).

    Precedence mirrors apv_data_dir: APV_PLANNING_DIR env var (absolute, or
    relative to repo_root), else `.apv-config.toml` `[storage] planning_dir`,
    else the default `planning/` at the repo root. A monorepo whose tracked
    project lives in a sub-folder pins e.g. `planning_dir = "plugin/planning"`
    — the data dir stays at the repo root (captures are commit-anchored and
    commits are repo-level), only the plan corpus moves.
    """
    override = os.environ.get("APV_PLANNING_DIR")
    if override:
        p = Path(override)
        return p if p.is_absolute() else repo_root / p
    cfg_dir = (apv_config(repo_root, config_path).get("storage") or {}).get("planning_dir")
    if cfg_dir:
        p = Path(cfg_dir)
        return p if p.is_absolute() else repo_root / p
    return repo_root / "planning"


def _dir_prefix(entry, ctx: str) -> str:
    """Normalise an owned-dir carve-out entry to a repo-relative directory
    prefix with a trailing slash (the shape git's repo-relative paths match
    against). Fail-loud on anything else — absolute paths and repo-escaping
    entries can never match a git path, so accepting them would silently
    disable the carve-out."""
    if not isinstance(entry, str) or not entry.strip():
        raise ValueError(f"{ctx}: dirs entries must be non-empty strings")
    if entry.startswith("/"):
        raise ValueError(f"{ctx}: dir {entry!r} must be repo-relative, not absolute")
    s = entry.strip().replace("\\", "/")
    while s.startswith("./"):
        s = s[2:]
    if not s.rstrip("/") or ".." in s.split("/"):
        raise ValueError(f"{ctx}: dir {entry!r} is not a repo-relative directory")
    return s.rstrip("/") + "/"


def apv_projects(repo_root: Path, config_path=None) -> dict:
    """Parse the `[projects.<name>]` registry (T3-multi-project +
    T3-project-attribution).

    Returns an ordered `{name: {"planning_dir": Path, "dirs": [prefix...]}}`
    — empty when no registry is configured (single-project mode; behaviour
    identical to pre-registry APV). Sub-projects share the repo's ONE event
    log; the registry declares planning roots for membership derivation and
    optional owned-dir carve-outs (`dirs`, repo-relative prefixes) for
    creation-time attribution of planless work.
    Fail-loud like apv_config: a project without planning_dir, two projects
    sharing a planning_dir, an exact duplicate dir across projects, or the
    reserved name `unassigned` all raise.
    """
    raw = apv_config(repo_root, config_path).get("projects") or {}
    projects, seen_dirs, seen_prefixes = {}, {}, {}
    for name, tbl in raw.items():
        if name == "unassigned":
            raise ValueError("[projects.unassigned] is reserved (the no-membership bucket)")
        if not isinstance(tbl, dict) or not tbl.get("planning_dir"):
            raise ValueError(f"[projects.{name}] must declare planning_dir")
        p = Path(tbl["planning_dir"])
        root = p if p.is_absolute() else repo_root / p
        key = str(root)
        if key in seen_dirs:
            raise ValueError(
                f"[projects.{name}] planning_dir duplicates [projects.{seen_dirs[key]}]"
            )
        seen_dirs[key] = name
        dirs_raw = tbl.get("dirs")
        dirs = []
        if dirs_raw is not None:
            if not isinstance(dirs_raw, list):
                raise ValueError(f"[projects.{name}] dirs must be an array of strings")
            for entry in dirs_raw:
                px = _dir_prefix(entry, f"[projects.{name}]")
                if px in seen_prefixes and seen_prefixes[px] != name:
                    raise ValueError(
                        f"[projects.{name}] dir {px!r} duplicates [projects.{seen_prefixes[px]}]"
                    )
                seen_prefixes[px] = name
                if px not in dirs:
                    dirs.append(px)
        projects[name] = {"planning_dir": root, "dirs": dirs}
    return projects


def apv_planning_roots(repo_root: Path, config_path=None) -> list:
    """Ordered [(project_name, planning_root_path)] for membership derivation.

    Registered projects first (declaration order), then the implicit `main`
    project = apv_planning_dir(...) — unless a registered project already
    claims that exact dir (a named project over the storage dir RENAMES the
    default project). Single-project mode: [("main", <planning>)].
    """
    projects = apv_projects(repo_root, config_path)
    main_dir = apv_planning_dir(repo_root, config_path)
    roots = [(name, cfg["planning_dir"]) for name, cfg in projects.items()]
    if not any(str(root) == str(main_dir) for _, root in roots):
        roots.append(("main", main_dir))
    return roots


def apv_default_project(repo_root: Path, config_path=None) -> str:
    """Name of the DEFAULT project: the registered project that claims the
    [storage] planning dir (the rename rule in apv_planning_roots), else the
    implicit `main`. Everything not explicitly carved out is its territory;
    it is never stamped (T3-project-attribution ruling 3 — only named
    sub-projects are)."""
    projects = apv_projects(repo_root, config_path)
    main_dir = apv_planning_dir(repo_root, config_path)
    for name, cfg in projects.items():
        if str(cfg["planning_dir"]) == str(main_dir):
            return name
    return "main"


def apv_owned_prefixes(repo_root: Path, config_path=None) -> list:
    """Ordered [(project_name, repo-relative dir prefix)] over the NAMED
    sub-projects' carve-outs: each project's `dirs` plus its planning_dir
    (implicitly owned). The default project contributes nothing — its
    territory is everything unclaimed, and it is never stamped. [] without
    a registry. An exact prefix claimed by two projects raises (a carve-out
    with two owners cannot attribute deterministically)."""
    projects = apv_projects(repo_root, config_path)
    default = apv_default_project(repo_root, config_path)
    out, seen = [], {}
    for name, cfg in projects.items():
        if name == default:
            continue
        prefixes = list(cfg["dirs"])
        try:
            rel = cfg["planning_dir"].relative_to(repo_root)
            px = str(rel).replace("\\", "/").rstrip("/") + "/"
            if px not in prefixes:
                prefixes.append(px)
        except ValueError:
            pass  # planning root outside the repo: no git path can match it
        for px in prefixes:
            if px in seen and seen[px] != name:
                raise ValueError(
                    f"carve-out {px!r} claimed by both [projects.{seen[px]}] "
                    f"and [projects.{name}]"
                )
            seen[px] = name
            out.append((name, px))
    return out


def named_owners(repo_root: Path, paths, config_path=None) -> list:
    """Distinct NAMED sub-projects owning the given repo-relative paths —
    longest prefix wins per path (carve-outs may nest), first-touched order.
    Paths under no carve-out contribute nothing (default territory). []
    without a registry — single-project behaviour unchanged."""
    prefixes = apv_owned_prefixes(repo_root, config_path)
    owners = []
    for path in paths:
        p = str(path).replace("\\", "/").lstrip("/")
        best, best_len = None, -1
        for name, px in prefixes:
            if p.startswith(px) and len(px) > best_len:
                best, best_len = name, len(px)
        if best is not None and best not in owners:
            owners.append(best)
    return owners


def named_owner_of(repo_root: Path, path, config_path=None):
    """The single named sub-project owning one repo-relative path, or None
    (default territory, or no registry)."""
    got = named_owners(repo_root, [path], config_path)
    return got[0] if got else None
