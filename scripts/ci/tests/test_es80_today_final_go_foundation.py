#!/usr/bin/env python3
"""Run the historical Final GO adversarial suite against the private validator library.

Every public/compatibility Final GO builder and retired implementation filename is intentionally
non-authorizing. The canonical hardened composer consumes
`_es80_today_final_go_foundation_library.py` directly, so this harness runs the closed-world
historical validator tests against that same preserved library implementation without reopening a
public builder or executable path.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
import unittest

TEST_DIR = Path(__file__).resolve().parent
MODULE_DIR = TEST_DIR.parent


def _load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load {path.name}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


foundation = _load(
    "nembra_today_final_go_foundation_library_under_test",
    MODULE_DIR / "_es80_today_final_go_foundation_library.py",
)
legacy_suite = _load(
    "nembra_today_final_go_foundation_suite",
    TEST_DIR / "test_es80_today_final_go_record.py",
)
legacy_suite.final_go = foundation


def main() -> int:
    suite = unittest.defaultTestLoader.loadTestsFromModule(legacy_suite)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(main())
