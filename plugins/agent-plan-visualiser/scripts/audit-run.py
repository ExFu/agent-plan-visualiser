#!/usr/bin/env python3
"""audit-run.py — run an audit .sql file (or SQL on stdin) against the cache
through Python's sqlite3 module, so no `sqlite3` CLI is needed.

    audit-run.py <file.sql | -> [--cache PATH]

Why (T3-synced-folder-runtime §2.3): repack-validate.sh shelled out to the
sqlite3 CLI for the three audits; some environments an agent runs in (the
Cowork sandbox) have the Python module but no CLI. The module is already a
hard dependency of cache-build.py.

Behaviour:
- Lines whose first non-blank character is `.` are sqlite3 dot-commands
  (`.headers on`, `.mode column`) — dropped, so the .sql files stay runnable
  by a human with the CLI and by this script alike.
- The remainder is executed as ONE statement (each audit file is a single
  WITH … SELECT). Column names, a separator, then rows, padded to the widest
  value per column — a readable stand-in for `.mode column`.
- Exit 0 when the statement ran, whatever the row count (audits are
  advisory; matches the CLI's exit behaviour). Exit 1 on a sqlite3.Error.
  Exit 2 when the cache file is missing (run cache-build.py first).

The cache path defaults to apvlib.apv_cache_path over the resolved data dir
(APV_DATA_DIR → .apv-config.toml → .apv/; root: git toplevel → nearest
.apv-config.toml → toolchain parent).
"""
import sqlite3
import sys
from pathlib import Path

from apv_runtime import ensure_python
if __name__ == "__main__":
    ensure_python(())

import apvlib


def strip_dot_commands(sql: str) -> str:
    return "\n".join(
        line for line in sql.splitlines() if not line.lstrip().startswith(".")
    )


def render(cols, rows) -> str:
    if not cols:
        return ""
    table = [[("" if v is None else str(v)) for v in row] for row in rows]
    widths = [max(len(c), *(len(r[i]) for r in table)) if table else len(c)
              for i, c in enumerate(cols)]
    lines = [
        "  ".join(c.ljust(widths[i]) for i, c in enumerate(cols)),
        "  ".join("-" * widths[i] for i in range(len(cols))),
    ]
    lines += ["  ".join(r[i].ljust(widths[i]) for i in range(len(cols))) for r in table]
    return "\n".join(line.rstrip() for line in lines)


def main(argv) -> int:
    cache = None
    src = None
    args = list(argv)
    while args:
        a = args.pop(0)
        if a == "--cache":
            if not args:
                print("audit-run: --cache needs a path", file=sys.stderr)
                return 2
            cache = Path(args.pop(0))
        elif a in ("-h", "--help"):
            print(__doc__)
            return 0
        elif src is None:
            src = a
        else:
            print(f"audit-run: unexpected argument {a!r}", file=sys.stderr)
            return 2
    if src is None:
        print("usage: audit-run.py <file.sql | -> [--cache PATH]", file=sys.stderr)
        return 2

    sql = sys.stdin.read() if src == "-" else Path(src).read_text(encoding="utf-8")
    sql = strip_dot_commands(sql).strip()
    if not sql:
        print("audit-run: no SQL to run after stripping dot-commands", file=sys.stderr)
        return 2

    if cache is None:
        root = apvlib.repo_root()
        cache = apvlib.apv_cache_path(apvlib.apv_data_dir(root), root)
    if not cache.is_file():
        print(f"audit-run: cache {cache} not found — build it first: "
              f"python3 {Path(__file__).resolve().parent / 'cache-build.py'}", file=sys.stderr)
        return 2

    try:
        conn = sqlite3.connect(f"file:{cache}?mode=ro", uri=True)
        try:
            cur = conn.execute(sql)
            cols = [d[0] for d in (cur.description or [])]
            rows = cur.fetchall()
        finally:
            conn.close()
    except sqlite3.Error as e:
        print(f"audit-run: {e}", file=sys.stderr)
        return 1
    out = render(cols, rows)
    if out:
        print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
