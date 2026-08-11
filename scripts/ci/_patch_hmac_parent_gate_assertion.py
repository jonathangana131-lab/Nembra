#!/usr/bin/env python3
from pathlib import Path

path = Path("scripts/ci/tests/test_capture_cocoapods_generated_build_subject.py")
source = path.read_text(encoding="utf-8")
old = '        self.assertIn("generated CocoaPods build inputs do not match", field.stdout)\n'
new = '        self.assertIn("generated build inputs do not match", field.stdout)\n'
if source.count(old) != 1:
    raise SystemExit("expected generated-substitution assertion was not found exactly once")
path.write_text(source.replace(old, new), encoding="utf-8")
