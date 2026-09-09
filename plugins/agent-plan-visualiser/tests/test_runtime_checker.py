"""Runtime selection, strict batch validation and compact checking regressions.

Run: python3 -m unittest discover -s <plugin>/tests -p 'test_runtime_checker.py'
All writes are confined to temporary fixtures; no model or network required.
"""
import importlib.util
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

PLUGIN = Path(__file__).resolve().parents[1]
SCRIPTS = PLUGIN / 'scripts'
spec = importlib.util.spec_from_file_location('apv_runtime', SCRIPTS / 'apv_runtime.py')
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


class RuntimeCheckerTests(unittest.TestCase):
    def test_no_command_skill_name_collisions(self):
        commands = {p.stem for p in (PLUGIN / 'commands').glob('*.md')}
        skills = {p.parent.name for p in (PLUGIN / 'skills').glob('*/SKILL.md')}
        self.assertFalse(commands & skills, f'Slash namespace collisions: {commands & skills}')

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='apv tests ')
        self.root = Path(self.tmp.name)
        self.env = {k: v for k, v in os.environ.items() if not k.startswith('APV_')}
        self.env['PYTHONDONTWRITEBYTECODE'] = '1'
        self.env['XDG_CACHE_HOME'] = str(self.root / 'cache')
        self.schema = self.root / 'schema.json'
        self.schema.write_text(json.dumps({'$schema': 'https://json-schema.org/draft/2020-12/schema',
                                          'type': 'object', 'required': ['actor']}))
        self.events = self.root / 'events.jsonl'

    def tearDown(self):
        self.tmp.cleanup()

    def run_cmd(self, *args, **kwargs):
        return subprocess.run(args, cwd=self.root, env=kwargs.get('env', self.env),
                              capture_output=True, text=True, timeout=90)

    def validate(self, content):
        self.events.write_text(content)
        return self.run_cmd('bash', str(SCRIPTS / 'validate-events.sh'), str(self.schema), str(self.events))

    def test_batch_never_invokes_check_jsonschema(self):
        cli = self.root / 'check-jsonschema'
        marker = self.root / 'called'
        cli.write_text(f'#!/bin/sh\ntouch {shlex.quote(str(marker))}\nexit 99\n')
        cli.chmod(0o755)
        self.env['PATH'] = str(self.root) + os.pathsep + self.env['PATH']
        proc = self.validate('{"actor":"test"}\n' * 1000)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn('all 1000 events valid', proc.stdout)
        self.assertFalse(marker.exists())

    def test_invalid_json_blank_line_and_scalar_are_rejected(self):
        proc = self.validate('{"actor":"ok"}\n\n{bad\n42\n{}\n')
        self.assertEqual(proc.returncode, 1)
        for line in (2, 3, 4, 5):
            self.assertIn(f'FAIL line {line}', proc.stderr)
        self.assertIn('actor', proc.stderr)

    def test_last_line_without_newline_is_validated(self):
        proc = self.validate('{}')
        self.assertEqual(proc.returncode, 1)
        self.assertIn('FAIL line 1', proc.stderr)

    def test_invalid_schema_is_environment_error(self):
        self.schema.write_text('{"type":"not-a-type"}')
        self.assertEqual(self.validate('{"actor":"ok"}\n').returncode, 2)

    def test_invalid_explicit_override_never_falls_back(self):
        self.env['APV_PYTHON'] = str(self.root / 'missing-python')
        proc = self.validate('{"actor":"ok"}\n')
        self.assertEqual(proc.returncode, 2)
        self.assertIn('missing-python', proc.stderr)
        self.assertIn('-m venv', proc.stderr)
        self.assertNotIn('--user', proc.stderr)

    def test_explicit_venv_missing_dependencies(self):
        venv = self.root / 'empty venv'
        p = self.run_cmd(sys.executable, '-m', 'venv', '--without-pip', str(venv))
        self.assertEqual(p.returncode, 0, p.stderr)
        self.env['APV_PYTHON'] = str(venv / 'bin/python')
        proc = self.validate('{"actor":"ok"}\n')
        self.assertEqual(proc.returncode, 2)
        self.assertIn('jsonschema', proc.stderr)

    def test_candidate_fallback_checks_capability(self):
        def probe(args, **kwargs):
            return subprocess.CompletedProcess(args, 0 if args[0] == '/capable/python' else 1,
                                               '/capable/python\n', '')
        with patch.object(runtime, 'candidates', return_value=iter(['/missing/python', '/capable/python'])), \
             patch.object(runtime.subprocess, 'run', side_effect=probe):
            self.assertEqual(runtime.resolve_python(('yaml', 'jsonschema')), '/capable/python')

    def test_absolute_shebang_candidate_and_no_shell_evaluation(self):
        cli = self.root / 'check-jsonschema'
        cli.write_text('#!/a/venv/bin/python\n')
        with patch.dict(os.environ, {}, clear=True), patch.object(runtime.shutil, 'which', return_value=str(cli)):
            self.assertIn('/a/venv/bin/python', list(runtime.candidates()))
            cli.write_text('#!/usr/bin/env python3\n')
            self.assertNotIn('/usr/bin/env', list(runtime.candidates()))

    def seed_scope(self):
        shutil.copytree(PLUGIN / 'tests/gitless/fixture', self.root / '.apv')
        shutil.move(str(self.root / '.apv/planning'), self.root / 'planning')
        (self.root / '.apv-config.toml').write_text('[storage]\ndata_dir=".apv"\nplanning_dir="planning"\n')

    def test_compact_check_and_interpreter_inheritance(self):
        self.seed_scope()
        venv = self.root / 'working venv'
        p = self.run_cmd(sys.executable, '-m', 'venv', '--without-pip', '--system-site-packages', str(venv))
        self.assertEqual(p.returncode, 0, p.stderr)
        self.env['APV_PYTHON'] = str(venv / 'bin/python')
        original = (self.root / '.apv/events.jsonl').read_bytes()
        proc = self.run_cmd('bash', str(SCRIPTS / 'apv'), 'check', '--json')
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertEqual(len(proc.stdout.splitlines()), 1)
        result = json.loads(proc.stdout)
        self.assertEqual(result['status'], 'pass')
        report = json.loads(Path(result['report']).read_text())
        self.assertEqual(Path(report['diagnostics'][-1]['command'][0]).parent.resolve(), Path(self.env['APV_PYTHON']).parent.resolve())
        self.assertEqual((self.root / '.apv/events.jsonl').read_bytes(), original)
        self.assertFalse((self.root / '.apv/.last-capture').exists())
        shutil.rmtree(Path(result['report']).parent)

    def test_compact_failure_has_detailed_report(self):
        self.seed_scope()
        with (self.root / '.apv/events.jsonl').open('a') as f:
            f.write('{bad\n')
        proc = self.run_cmd('bash', str(SCRIPTS / 'apv'), 'check', '--json')
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        result = json.loads(proc.stdout)
        self.assertEqual(result['status'], 'fail')
        self.assertIn('FAIL line', Path(result['report']).read_text())
        shutil.rmtree(Path(result['report']).parent)

    def test_changed_inputs_cannot_return_pass(self):
        self.seed_scope()
        code = f"""
import runpy, sys
sys.path.insert(0, {str(SCRIPTS)!r})
m = runpy.run_path({str(SCRIPTS / 'check.py')!r})
values = iter(['before', 'after'])
m['main'].__globals__['fingerprint'] = lambda root: next(values)
sys.argv = ['check.py', '--json']
sys.exit(m['main']())
"""
        proc = self.run_cmd(sys.executable, '-c', code)
        self.assertEqual(proc.returncode, 2, proc.stdout + proc.stderr)
        result = json.loads(proc.stdout)
        self.assertEqual(result['status'], 'error')
        self.assertIn('Inputs changed', result['error'])
        shutil.rmtree(Path(result['report']).parent)

    def test_cache_warns_when_legacy_frontmatter_is_skipped(self):
        self.seed_scope()
        path = self.root / '.apv/events.jsonl'
        events = [json.loads(line) for line in path.read_text().splitlines()]
        events = [e for e in events if e['type'] != 'entity.created']
        path.write_text(''.join(json.dumps(e) + '\n' for e in events))
        code = f"""
import builtins, runpy, sys
sys.path.insert(0, {str(SCRIPTS)!r})
original = builtins.__import__
def unavailable(name, *args, **kwargs):
    if name == 'yaml': raise ImportError('fixture: no PyYAML')
    return original(name, *args, **kwargs)
builtins.__import__ = unavailable
m = runpy.run_path({str(SCRIPTS / 'cache-build.py')!r})
m['main']()
"""
        proc = self.run_cmd(sys.executable, '-c', code)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn('WARN: PyYAML unavailable; skipped legacy frontmatter', proc.stderr)

    def test_gate_maps_mixed_epoch_lines(self):
        all_events = [json.loads(x) for x in (PLUGIN.parents[1] / '.agent-plan-tracker/events.jsonl').read_text().splitlines()]
        old = next(e for e in all_events if e['schema_version'] == '0.2.0')
        new = next(e for e in all_events if e['schema_version'] == '0.3.0')
        invalid = dict(new)
        invalid.pop('actor', None)
        self.events.write_text('\n'.join(json.dumps(e) for e in [new, old, invalid]) + '\n')
        config = self.root / '.apv-config.toml'
        config.write_text('[gate]\nblocking=["schema"]\nwarn=[]\n')
        proc = self.run_cmd(sys.executable, str(SCRIPTS / 'gate-composite.py'), '--data-dir', str(self.root), '--config', str(config))
        self.assertEqual(proc.returncode, 1, proc.stderr)
        self.assertIn('[0.3.0] FAIL line 3', proc.stdout)


if __name__ == '__main__':
    unittest.main()
