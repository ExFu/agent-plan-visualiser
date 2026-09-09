"""Compact front door to deterministic APV checks; never captures or commits."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

from apv_runtime import ensure_python
import apvlib

SCRIPTS = Path(__file__).resolve().parent


def fingerprint(root):
    """Bind the result to source inputs, excluding rebuildable APV outputs."""
    data = apvlib.apv_data_dir(root).resolve()
    paths = {root / '.apv-config.toml', data / 'events.jsonl', data / 'schema-version.txt'}
    for _, plans in apvlib.apv_planning_roots(root):
        if plans.exists():
            paths.update(p for p in plans.rglob('*') if p.is_file())
    paths.update(p for p in SCRIPTS.parent.rglob('*')
                 if p.is_file() and p.suffix in {'.py', '.sh', '.json', '.sql'})
    cache = apvlib.apv_cache_dir(data, root).resolve()
    derived = {directory / name for directory in (data, cache)
               for name in ('cache.sqlite', 'projection.json', 'summary.md')}
    listing = subprocess.run(['git', '-C', str(root), 'ls-files', '-z', '--cached', '--others', '--exclude-standard'], capture_output=True)
    if listing.returncode == 0:
        paths.update(root / os.fsdecode(p) for p in listing.stdout.split(b'\0') if p)
    h = hashlib.sha256()
    for p in sorted(paths):
        if p.resolve() in derived or p.is_dir():
            continue
        h.update(str(p).encode())
        h.update(p.read_bytes() if p.exists() else b'<missing>')
    # Commit identity matters to seal correspondence. Staging alone does not
    # change validation inputs; the native pre-commit hook still checks it.
    proc = subprocess.run(['git', '-C', str(root), 'rev-parse', 'HEAD'], capture_output=True)
    h.update(proc.stdout)
    return h.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--gate-only', action='store_true', help='skip refresh/frontmatter; run the merge boundary gate')
    parser.add_argument('--ref', help='check a committed Git ref; implies --gate-only')
    parser.add_argument('--json', action='store_true', help='emit the compact result as JSON')
    args = parser.parse_args()
    ensure_python(('jsonschema',) if args.gate_only or args.ref else ('jsonschema', 'yaml'))
    root = apvlib.repo_root()
    started = time.monotonic()
    report_dir = Path(tempfile.mkdtemp(prefix='apv-check-'))
    report_path = report_dir / 'report.json'
    steps = []
    result = {'status': 'error', 'repo': str(root), 'ref': args.ref,
              'report': str(report_path), 'steps': [], 'warnings': 0}
    code = 2
    try:
        before = fingerprint(root)
        commands = []
        if not (args.gate_only or args.ref):
            commands.append(('refresh and validation', ['bash', str(SCRIPTS / 'repack-validate.sh')]))
        git = subprocess.run(['git', '-C', str(root), 'rev-parse', '--show-toplevel'], capture_output=True).returncode == 0
        if args.ref and not git:
            raise ValueError('--ref requires a Git repository')
        gate = ['bash', str(SCRIPTS / 'gate-check.sh')] if git else [sys.executable, str(SCRIPTS / 'gate-composite.py')]
        if args.ref:
            resolved = subprocess.run(['git', '-C', str(root), 'rev-parse', '--verify',
                                       '--end-of-options', args.ref + '^{commit}'],
                                      capture_output=True, text=True)
            if resolved.returncode:
                raise ValueError(f'Cannot resolve Git commit: {args.ref}')
            result['ref'] = resolved.stdout.strip()
            gate += ['--ref', result['ref']]
        commands.append(('integrity and commit correspondence' if git else 'integrity (no Git)', gate))
        code = 0
        for label, command in commands:
            proc = subprocess.run(command, cwd=root, capture_output=True, text=True)
            steps.append({'name': label, 'command': command, 'exit_code': proc.returncode,
                          'stdout': proc.stdout, 'stderr': proc.stderr})
            result['steps'].append({'name': label, 'exit_code': proc.returncode})
            result['warnings'] += sum(line.startswith('WARN') for line in (proc.stdout + '\n' + proc.stderr).splitlines())
            if proc.returncode:
                code = 2 if proc.returncode != 1 else 1
                result['failed_step'] = label
                break
        after = fingerprint(root)
        result['input_sha256'] = after
        # Rebuilt cache/projection/summary are excluded from the fingerprint.
        if before != after:
            code = 2
            result['error'] = 'Inputs changed during checking; rerun against stable inputs.'
        result['status'] = 'pass' if code == 0 else 'fail' if code == 1 else 'error'
    except (OSError, ValueError) as e:
        result['error'] = str(e)
        code = 2
    result['elapsed_seconds'] = round(time.monotonic() - started, 3)
    report_path.write_text(json.dumps(dict(result, diagnostics=steps), indent=2) + '\n')
    if args.json:
        print(json.dumps(result))
    else:
        detail = result.get('error') or result.get('failed_step') or f"{result['warnings']} advisory warning(s)"
        print(f"APV {result['status'].upper()}: {detail}. Report: {report_path}")
    return code


if __name__ == '__main__':
    sys.exit(main())
