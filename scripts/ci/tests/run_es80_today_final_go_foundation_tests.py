#!/usr/bin/env python3
"""Run the retained closed-world Final GO tests against the explicit foundation module.

The historical test source predates the non-authorizing compatibility split. Keep that adversarial
suite byte-stable while redirecting its single module-under-test path in memory, so making the
legacy import fail closed does not discard foundation coverage.
"""
from __future__ import annotations

from pathlib import Path

SOURCE = Path(__file__).with_name("test_es80_today_final_go_record.py")
LEGACY_TARGET = 'MODULE_PATH = Path(__file__).resolve().parents[1] / "es80_today_final_go_record.py"'
FOUNDATION_TARGET = 'MODULE_PATH = Path(__file__).resolve().parents[1] / "es80_today_final_go_foundation.py"'

text = SOURCE.read_text(encoding="utf-8")
if text.count(LEGACY_TARGET) != 1:
    raise RuntimeError("Final GO foundation test module target drifted")
text = text.replace(LEGACY_TARGET, FOUNDATION_TARGET, 1)

# Execute inside this __main__ namespace so the retained unittest.main() call discovers the exact
# original test classes, while __file__ remains the retained source path for its relative lookup.
globals()["__file__"] = str(SOURCE)
exec(compile(text, str(SOURCE), "exec"), globals(), globals())
