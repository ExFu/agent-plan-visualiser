"""Validate a JSONL file in one process, preserving physical line numbers."""
import json
from pathlib import Path
import sys

from apv_runtime import ensure_python


def main():
    ensure_python(('jsonschema',))
    from jsonschema.validators import validator_for
    from jsonschema.exceptions import SchemaError
    import apvlib

    schema_path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / 'schemas/0.6.0/events.schema.json'
    events_path = Path(sys.argv[2]) if len(sys.argv) > 2 else apvlib.apv_data_dir(apvlib.repo_root()) / 'events.jsonl'
    try:
        schema = json.loads(schema_path.read_text())
        cls = validator_for(schema)
        cls.check_schema(schema)
        validator = cls(schema)
        failed = valid = 0
        with events_path.open() as f:
            for line, raw in enumerate(f, 1):
                try:
                    event = json.loads(raw)
                except ValueError as e:
                    print(f'FAIL line {line}: JSON parse: {e}', file=sys.stderr)
                    failed += 1
                    continue
                error = next(validator.iter_errors(event), None)
                if error:
                    print(f'FAIL line {line}: {error.message}', file=sys.stderr)
                    failed += 1
                else:
                    valid += 1
        if failed:
            print(f'{failed} events failed; {valid} valid', file=sys.stderr)
            return 1
        print(f'all {valid} events valid')
        return 0
    except (OSError, ValueError, SchemaError) as e:
        print(f'validate-events: {e}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
