#!/usr/bin/env python3
from pathlib import Path
p=Path('scripts/ci/tmp_v14_seal_installer_execution_subject.py')
s=p.read_text()
lines=s.splitlines(keepends=True)
matched=[i for i,line in enumerate(lines) if 'source!r' in line and 'exit 51' in line]
if len(matched)!=1:
    raise SystemExit(f'expected one self-referential source fixture assertion, found {len(matched)}')
lines[matched[0]]="    '',\n"
s=''.join(lines)
old='    if p != "scripts/ci/tmp_v14_seal_installer_execution_subject.py"\n    and not p.startswith(".github/workflows/tmp-v14-seal-installer-execution-subject")\n'
new='    if p != "scripts/ci/tmp_v14_seal_installer_execution_subject.py"\n    and p != "scripts/ci/tmp_v14_fix_sealed_installer_fixture.py"\n    and not p.startswith(".github/workflows/tmp-v14-seal-installer-execution-subject")\n'
if s.count(old)!=1:
    raise SystemExit(f'product-scope helper seam count={s.count(old)}')
p.write_text(s.replace(old,new,1))
