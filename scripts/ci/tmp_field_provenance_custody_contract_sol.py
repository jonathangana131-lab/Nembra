#!/usr/bin/env python3
from pathlib import Path

path = Path('.github/workflows/capture-field-build-provenance.yml')
lines = path.read_text(encoding='utf-8').splitlines(keepends=True)
provenance_hits = 0
guard_hits = 0
repaired = []
for line in lines:
    if 'PROVENANCE_HELPER' in line and ' snapshot' in line and 'grep -Fq' in line and 'run_accepted_python_helper' not in line:
        provenance_hits += 1
        indentation = line[:len(line) - len(line.lstrip())]
        line = indentation + "grep -Fq 'run_accepted_python_helper \"$PROVENANCE_HELPER\" \"$PROVENANCE_HELPER_SHA256\" snapshot' \"$bootstrap\"\n"
    if 'guard_line=' in line and 'TUYA_BUILD_WINDOW_GUARD' in line and 'run_accepted_source_python' not in line:
        guard_hits += 1
        line = line.replace('/usr/bin/python3 -I \"$TUYA_BUILD_WINDOW_GUARD\"', 'run_accepted_source_python \"$TUYA_BUILD_WINDOW_GUARD_RELATIVE\"')
    repaired.append(line)
if provenance_hits != 1:
    raise SystemExit(f'expected one stale provenance-helper contract line, found {provenance_hits}')
if guard_hits != 1:
    raise SystemExit(f'expected one stale build-window guard ordering line, found {guard_hits}')
path.write_text(''.join(repaired), encoding='utf-8')
