#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[3]
PRODUCER = ROOT / '.github/workflows/capture-producer-custody-source.yml'
PROVENANCE = ROOT / '.github/workflows/capture-field-build-provenance.yml'

def python_commands(path: Path) -> list[str]:
    commands = []
    for raw in path.read_text(encoding='utf-8').splitlines():
        command = raw.strip()
        if command.startswith('python3 ') or command.startswith('/usr/bin/python3 '):
            commands.append(command)
    return commands

for path in (PRODUCER, PROVENANCE):
    commands = python_commands(path)
    if not commands:
        raise SystemExit(f'expected Python validation commands in {path}')
    for command in commands:
        if not re.match(r'^/usr/bin/python3\s+-I(?:\s|$)', command):
            raise SystemExit(f'unisolated Python validation command in {path}: {command}')

producer = PRODUCER.read_text(encoding='utf-8')
for needle in (
    'scripts/ci/tests/test_capture_ci_python_isolation.py',
    '/usr/bin/python3 -I -m py_compile scripts/ci/tests/test_capture_ci_python_isolation.py',
    '/usr/bin/python3 -I scripts/ci/tests/test_capture_ci_python_isolation.py',
):
    if needle not in producer:
        raise SystemExit(f'portable producer gate does not enforce CI Python isolation: {needle}')

print('capture CI authority Python isolation source contract: PASS')
