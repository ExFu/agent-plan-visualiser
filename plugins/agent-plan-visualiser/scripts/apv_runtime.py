"""Standard-library-only Python selection shared by shell and Python entry points."""
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys


def dependency_help(modules, interpreter=None):
    packages = ' '.join('pyyaml' if m == 'yaml' else m for m in modules)
    return (
        f"APV needs Python with {packages or 'the standard library'}"
        f" (selected: {interpreter or 'automatic discovery'}).\n"
        "Create a virtual environment; no system Python changes are needed:\n"
        '  python3 -m venv "$HOME/.apv-venv"\n'
        f'  "$HOME/.apv-venv/bin/python" -m pip install {packages or "pyyaml jsonschema"}\n'
        '  export APV_PYTHON="$HOME/.apv-venv/bin/python"\n'
    )


def candidates():
    # An explicit override is a contract, never silently ignored.
    if os.environ.get('APV_PYTHON'):
        yield os.environ['APV_PYTHON']
        return
    yield sys.executable
    yield shutil.which('python3')
    yield str(Path.home() / '.apv-venv/bin/python')
    cli = shutil.which('check-jsonschema')
    if cli:
        try:
            with open(cli, encoding='utf-8') as f:
                line = f.readline(4096)
            parts = shlex.split(line[2:].strip()) if line.startswith('#!') else []
            # Only an absolute, argument-free Python shebang. No eval, env
            # wrappers or assumptions that an arbitrary launcher is Python.
            if len(parts) == 1 and Path(parts[0]).is_absolute() and Path(parts[0]).name.startswith('python'):
                yield parts[0]
        except (OSError, UnicodeError, ValueError):
            pass


def resolve_python(modules=()):
    seen = set()
    for candidate in candidates():
        if not candidate or candidate in seen:
            continue
        seen.add(candidate)
        try:
            p = subprocess.run(
                [candidate, '-c',
                 'import importlib,sys; assert sys.version_info >= (3, 11); [importlib.import_module(m) for m in sys.argv[1:]]; print(sys.executable)',
                 *modules], capture_output=True, text=True, timeout=15,
            )
            if p.returncode == 0 and p.stdout.strip():
                return p.stdout.strip()
        except (OSError, subprocess.TimeoutExpired):
            pass
    raise RuntimeError(dependency_help(modules, os.environ.get('APV_PYTHON')))


def ensure_python(modules=(), optional=()):
    """Re-exec direct Python entry points before doing any project work."""
    try:
        try:
            selected = resolve_python((*modules, *optional))
        except RuntimeError:
            if not optional:
                raise
            selected = resolve_python(modules)
    except RuntimeError as e:
        print(e, file=sys.stderr)
        raise SystemExit(2)
    os.environ['APV_PYTHON'] = selected
    # Do not resolve symlinks: a venv can share the base binary but has its
    # own sys.prefix and packages.
    if os.path.abspath(selected) != os.path.abspath(sys.executable):
        os.execv(selected, [selected, *sys.argv])


if __name__ == '__main__':
    try:
        print(resolve_python(sys.argv[1:]))
    except RuntimeError as e:
        print(e, file=sys.stderr)
        sys.exit(2)
