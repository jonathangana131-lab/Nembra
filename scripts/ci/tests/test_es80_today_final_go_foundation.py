#!/usr/bin/env python3
"""Run the historical Final GO adversarial suite against the authority-bearing foundation module.

The historical `es80_today_final_go_record.py` import is intentionally non-authorizing. Rather than
reopen that compatibility surface for tests, this harness loads the existing test module and swaps
its module-global `final_go` reference to the real foundation before test discovery/execution.
Class constants already captured from the compatibility export are identical foundation constants;
all runtime builder, Git, validation, and publication calls resolve through this replacement.

The legacy fixture predates the real retained-candidate environment/log files required by the
independent crosscheck executable. Its synthetic receipt-validation cases therefore use a test-only
crosscheck execution adapter that returns the fixture receipt bytes unchanged. The production pinned
Git-blob executor is covered separately by the dedicated crosscheck execution-custody regression.
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
    "nembra_today_final_go_foundation_under_test",
    MODULE_DIR / "es80_today_final_go_foundation.py",
)
legacy_suite = _load(
    "nembra_today_final_go_foundation_suite",
    TEST_DIR / "test_es80_today_final_go_record.py",
)
legacy_suite.final_go = foundation


def _legacy_fixture_crosscheck_execution(
    *,
    receipt_path: Path,
    candidate_root: Path,
    expected_source_sha: str,
    tooling_repo: Path,
    now_utc,
):
    del candidate_root, expected_source_sha, tooling_repo, now_utc
    raw, receipt = foundation._json_file(
        receipt_path,
        "legacy synthetic independent crosscheck receipt",
        exact_keys=foundation.CROSSCHECK_KEYS,
    )
    return receipt, raw, foundation.PINNED_CROSSCHECK_BLOB


def main() -> int:
    original_executor = foundation._trusted_crosscheck_execution
    foundation._trusted_crosscheck_execution = _legacy_fixture_crosscheck_execution
    try:
        suite = unittest.defaultTestLoader.loadTestsFromModule(legacy_suite)
        result = unittest.TextTestRunner(verbosity=2).run(suite)
    finally:
        foundation._trusted_crosscheck_execution = original_executor
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(main())
