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
    """The project being OPERATED ON, resolved in three rungs:

    1. the enclosing git repo of the cwd (`git rev-parse --show-toplevel`);
    2. else the nearest ancestor of the cwd (cwd included) that holds
       `.apv-config.toml` — the config lives at the project root by rule,
       so it is the root marker when there is no git (a synced folder,
       T3-synced-folder-runtime §2.2 / M7 §2.2);
    3. else the toolchain's own repo (the vendored/dogfood case).

    The toolchain may live in the plugin cache, far from any tracked
    project — rung 3 there points data resolution at the wrong tree (the
    same trap gate-check's repo-root default fixed in M4), which is why
    rung 2 sits before it. Toolchain CONTENT (schemas, view) is never
    resolved through this — that stays relative to the script's own
    location."""
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
    cwd = Path.cwd().resolve()
    for candidate in (cwd, *cwd.parents):
        if (candidate / ".apv-config.toml").is_file():
            return candidate
    return Path(__file__).resolve().parents[2]


def in_git_work_tree(path) -> bool:
    """True when `path` (or its nearest existing ancestor) is inside a git
    work tree. Decided from the PATH, not the cwd: callers ask about the
    data dir, which may sit far from where the script was invoked."""
    import subprocess
    p = Path(path).resolve()
    while not p.exists() and p != p.parent:
        p = p.parent
    try:
        out = subprocess.run(
            ["git", "-C", str(p), "rev-parse", "--is-inside-work-tree"],
            capture_output=True, text=True,
        )
        return out.returncode == 0 and out.stdout.strip() == "true"
    except OSError:
        return False


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


# --- Where derived files live (T3-synced-folder-runtime §2.3/§2.4) ----------
# cache.sqlite (+ journal) and projection.json are derived — rebuilt from
# events.jsonl on every run (T2-storage §3.1 trust hierarchy). Every consumer
# resolves their location through these three functions, never by hand.

def _cache_leaf(data_dir: Path) -> str:
    """Stable per-project id for the per-machine cache: the scope's folder
    name (human-findable) + 12 hex of sha256 over the resolved absolute data
    dir (unique per machine path — two machines syncing the same folder each
    get their own)."""
    import hashlib
    resolved = Path(data_dir).resolve()
    digest = hashlib.sha256(str(resolved).encode("utf-8")).hexdigest()[:12]
    return f"{resolved.parent.name or 'apv'}-{digest}"


def apv_cache_dir(data_dir, repo_root=None, config_path=None) -> Path:
    """The directory holding the derived cache files for `data_dir`.

    Precedence (mirrors apv_data_dir):
      1. APV_CACHE_DIR env var (absolute, or relative to repo_root);
      2. `.apv-config.toml` `[storage] cache_dir` (same);
      3. else, when `[storage] no_git = true` is declared OR the data dir is
         not inside a git work tree (decided from the DATA DIR's location,
         not the cwd, so subprocesses agree): the per-machine default
         `${XDG_CACHE_HOME:-~/.cache}/apv/<scope>-<hash>/`, created on
         demand; if that cannot be created, `<tempdir>/apv/<scope>-<hash>/`
         with one stderr line saying so. Never the data dir: a synced
         folder must not receive SQLite files (M7 §2.1);
      4. else (a git repo): the data dir itself — unchanged layout, including
         the dogfood repo's committed cache.sqlite.
    """
    import sys
    import tempfile
    data_dir = Path(data_dir)
    root = Path(repo_root) if repo_root is not None else data_dir.parent

    override = os.environ.get("APV_CACHE_DIR")
    if override:
        p = Path(override)
        return p if p.is_absolute() else root / p
    storage = apv_config(root, config_path).get("storage") or {}
    cfg_dir = storage.get("cache_dir")
    if cfg_dir:
        p = Path(cfg_dir)
        return p if p.is_absolute() else root / p

    declared_no_git = storage.get("no_git") is True
    if not declared_no_git and in_git_work_tree(data_dir):
        return data_dir

    leaf = _cache_leaf(data_dir)
    base = os.environ.get("XDG_CACHE_HOME") or str(Path.home() / ".cache")
    preferred = Path(base) / "apv" / leaf
    try:
        preferred.mkdir(parents=True, exist_ok=True)
        return preferred
    except OSError:
        fallback = Path(tempfile.gettempdir()) / "apv" / leaf
        fallback.mkdir(parents=True, exist_ok=True)  # raises if even this fails
        print(f"apv: cache dir {preferred} not writable; using {fallback}", file=sys.stderr)
        return fallback


def apv_cache_path(data_dir, repo_root=None, config_path=None) -> Path:
    return apv_cache_dir(data_dir, repo_root, config_path) / "cache.sqlite"


def apv_projection_path(data_dir, repo_root=None, config_path=None) -> Path:
    return apv_cache_dir(data_dir, repo_root, config_path) / "projection.json"


# --- What counts as a plan file (T3-synced-folder-runtime §2.1) ------------
# Fail-closed: every *.md directly under a planning root is a plan and must
# validate, with exactly three carve-outs, checked in this order:
#   1. a sub-folder holding a `.apv-ignore` marker is not planning content;
#   2. a basename in `[planning] non_plan_files` (default: the ExFu folder
#      descriptor `agent.md` and a folder `readme.md`) — for files that
#      cannot carry frontmatter;
#   3. a file whose own frontmatter says `apv: ignore`.
# Anything else fails loudly downstream. The validator never learns what a
# plan id looks like beyond what the schema enforces (operator ruling
# 2026-09-03: baking the plan shape into the validator is fail-open).
IGNORE_MARKER = ".apv-ignore"
DEFAULT_NON_PLAN_FILES = ("agent.md", "readme.md")
_FRONTMATTER_RE = re.compile(r"\A---\n(.*?)\n---(?:\n|\Z)", re.DOTALL)
_APV_KEY_RE = re.compile(r"^apv:[ \t]*(.*?)[ \t]*$", re.MULTILINE)


def apv_non_plan_files(repo_root: Path, config_path=None) -> set:
    """Lower-cased basenames excluded from plan validation — `[planning]
    non_plan_files` when set, else DEFAULT_NON_PLAN_FILES. Fail-loud on a
    non-list value (a string would silently exclude nothing)."""
    raw = (apv_config(repo_root, config_path).get("planning") or {}).get("non_plan_files")
    if raw is None:
        return {n.lower() for n in DEFAULT_NON_PLAN_FILES}
    if not isinstance(raw, list) or not all(isinstance(x, str) and x.strip() for x in raw):
        raise ValueError("[planning] non_plan_files must be an array of file names, "
                         f"e.g. {list(DEFAULT_NON_PLAN_FILES)!r}")
    return {x.strip().lower() for x in raw}


def apv_dir_ignored(directory) -> bool:
    """True when `directory` carries the `.apv-ignore` marker file."""
    return (Path(directory) / IGNORE_MARKER).exists()


def frontmatter_apv_key(path):
    """The value of a top-level `apv:` key in the file's YAML frontmatter,
    quotes stripped, or None when there is no frontmatter or no such key.
    Regex on the head of the file — stdlib only, no pyyaml."""
    try:
        text = Path(path).read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return None
    m = _FRONTMATTER_RE.match(text)
    if not m:
        return None
    k = _APV_KEY_RE.search(m.group(1))
    return k.group(1).strip("'\"") if k else None


def plan_files(root, non_plan_files) -> dict:
    """Classify the direct children of one planning root.

    Returns {"plans": [Path], "skipped": [(Path, reason)],
    "unmarked_subdirs": [Path], "bad_apv": [(Path, value)]}.
    `plans` must validate; `skipped` are the three carve-outs with their
    reason text; `unmarked_subdirs` are sub-folders without the marker
    (never scanned — plan ids are flat — but worth one notice so agents
    learn the marker exists); `bad_apv` carry an `apv:` value other than
    `ignore` and must FAIL (a typo cannot hide a plan). Dot-directories are
    ignored silently (never planning content). Raises ValueError when the
    ROOT itself carries the marker — a misconfiguration, not a carve-out."""
    root = Path(root)
    if apv_dir_ignored(root):
        raise ValueError(f"planning root {root} carries {IGNORE_MARKER} — "
                         "remove the marker or change planning_dir")
    out = {"plans": [], "skipped": [], "unmarked_subdirs": [], "bad_apv": []}
    for child in sorted(root.iterdir()):
        if child.is_dir():
            if child.name.startswith("."):
                continue
            if apv_dir_ignored(child):
                out["skipped"].append((child, f"{IGNORE_MARKER} marker"))
            else:
                out["unmarked_subdirs"].append(child)
            continue
        if child.suffix != ".md":
            continue
        if child.name.lower() in non_plan_files:
            out["skipped"].append((child, "listed non-plan file"))
            continue
        value = frontmatter_apv_key(child)
        if value is None:
            out["plans"].append(child)
        elif value == "ignore":
            out["skipped"].append((child, "frontmatter apv: ignore"))
        else:
            out["bad_apv"].append((child, value))
    return out


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


def plan_owner_map(repo_root: Path, paths, config_path=None) -> dict:
    """{plan_id: named_sub_project} for the given repo-relative paths that
    are DIRECT children (`<root>/<id>.md`) of a NAMED sub-project's planning
    root — the creation-time stamp source for plan entities (filename is
    load-bearing: it must equal the frontmatter id). Default-root plans are
    absent (never stamped); {} without a registry."""
    import re as _re
    default = apv_default_project(repo_root, config_path)
    owners = {}
    for name, root in apv_planning_roots(repo_root, config_path):
        if name == default:
            continue
        try:
            px = str(root.relative_to(repo_root)).replace("\\", "/")
        except ValueError:
            continue  # a root outside the repo can't hold repo paths
        for p in paths:
            m = _re.match(rf"^{_re.escape(px)}/([^/]+)\.md$",
                          str(p).replace("\\", "/"))
            if m:
                owners[m.group(1)] = name
    return owners
