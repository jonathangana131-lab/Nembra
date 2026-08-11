#!/usr/bin/env python3
from pathlib import Path

path = Path("scripts/ci/tests/test_es80_authenticated_stationary_final_go.py")
text = path.read_text()
old = "self.dev.write_text('device-token\\n')"
new = "self.dev.write_text('device-token')"
if text.count(old) != 1:
    raise SystemExit(f"expected one legacy newline device fixture, found {text.count(old)}")
path.write_text(text.replace(old, new, 1))
