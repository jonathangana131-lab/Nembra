#!/usr/bin/env python3
"""Run the historical Final GO adversarial suite against the authority-bearing foundation module.

The historical `es80_today_final_go_record.py` import is intentionally non-authorizing. Rather than
reopen that compatibility surface for tests, this harness loads the existing test module and swaps
its module-global `final_go` reference to the real foundation before test discovery/execution.
Class constants already captured from the compatibility export are identical foundation constants;
all runtime builder, Git, validation, and publication calls resolve through this replacement.

Production foundation composition now executes the pinned independent crosscheck producer. These
historical unit fixtures predate the producer's complete retained-candidate directory, so this
harness replaces only that execution seam with deterministic test evidence. The historical
semantic/Git crosscheck verifier still runs on every case; production code never uses this seam.
"""
from __future__ import annotations

import hashlib
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


def _fixture_trusted_crosscheck_receipt(
    *,
    candidate_root: Path,
    expected_source_sha: str,
    supplied_receipt_path: Path,
    tooling_repo: Path,
):
    del candidate_root, tooling_repo
    raw = supplied_receipt_path.read_bytes()
    return {
        "authority": foundation._trusted_crosscheck.TRUSTED_EXECUTION_AUTHORITY,
        "toolCommit": foundation.PINNED_CROSSCHECK_COMMIT,
        "toolPath": foundation._trusted_crosscheck.PINNED_CROSSCHECK_PATH,
        "toolGitBlob": foundation.PINNED_CROSSCHECK_BLOB,
        "producerOutputSHA256": hashlib.sha256(raw).hexdigest(),
        "producerOutputByteCount": len(raw),
        "candidateSourceCommitSHA": expected_source_sha,
        "producerStatus": "PASS_NOT_FINAL_GO",
        "physicalExperimentAuthorization": "not-granted",
    }


foundation._trusted_crosscheck_receipt = _fixture_trusted_crosscheck_receipt


def main() -> int:
    suite = unittest.defaultTestLoader.loadTestsFromModule(legacy_suite)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(main())
