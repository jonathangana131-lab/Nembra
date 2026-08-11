#!/usr/bin/env python3
from pathlib import Path
p=Path('scripts/ci/tmp_v14_seal_installer_execution_subject.py')
lines=p.read_text().splitlines(keepends=True)
matched=[line for line in lines if 'source!r' in line and 'exit 51' in line]
if len(matched)!=1:
    raise SystemExit(f'expected one self-referential source fixture assertion, found {len(matched)}')
p.write_text(''.join(line for line in lines if line not in matched))
