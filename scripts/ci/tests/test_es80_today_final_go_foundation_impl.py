#!/usr/bin/env python3
"""Run the original closed-world Final GO behavioral suite against the private implementation."""
from __future__ import annotations

from pathlib import Path
import unittest

ORIGINAL_TEST = Path(__file__).with_name("test_es80_today_final_go_record.py")
source = ORIGINAL_TEST.read_text(encoding="utf-8")
needle = 'MODULE_PATH = Path(__file__).resolve().parents[1] / "es80_today_final_go_record.py"'
replacement = 'MODULE_PATH = Path(__file__).resolve().parents[1] / "_es80_today_final_go_foundation_impl.py"'
if source.count(needle) != 1:
    raise RuntimeError("original Final GO foundation test import seam drifted")
namespace = {
    "__name__": "nembra_private_final_go_foundation_tests",
    "__file__": str(ORIGINAL_TEST),
}
exec(compile(source.replace(needle, replacement), str(ORIGINAL_TEST), "exec"), namespace)
FinalGoRecordTests = namespace["FinalGoRecordTests"]


if __name__ == "__main__":
    unittest.main()
