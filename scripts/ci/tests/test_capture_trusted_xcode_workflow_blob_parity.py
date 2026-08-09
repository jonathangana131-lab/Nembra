#!/usr/bin/env python3
"""Require Final-GO trusted-workflow pin to match the exact workflow bytes.

This regression intentionally computes Git blob identity from the checked-out workflow instead of
repeating a hard-coded expected SHA in workflow YAML. Any trusted-workflow edit must therefore move
the verifier pin in the same accepted change, or the gate fails closed.
"""
from __future__ import annotations

import hashlib
import importlib.util
from pathlib import Path
import unittest

CI_DIR = Path(__file__).resolve().parents[1]
REPO_ROOT = CI_DIR.parents[1]
WORKFLOW = REPO_ROOT / ".github/workflows/capture-xcode27-trusted-command.yml"
SUBJECT = CI_DIR / "es80_today_trusted_capture_xcode_subject.py"


def _load_subject():
    spec = importlib.util.spec_from_file_location("nembra_trusted_xcode_blob_parity", SUBJECT)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load trusted Xcode subject verifier")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _git_blob_sha(raw: bytes) -> str:
    return hashlib.sha1(f"blob {len(raw)}\0".encode() + raw).hexdigest()


class TrustedWorkflowBlobParityTests(unittest.TestCase):
    def test_verifier_pins_exact_trusted_workflow_bytes(self) -> None:
        subject = _load_subject()
        actual = _git_blob_sha(WORKFLOW.read_bytes())
        self.assertEqual(
            subject.TRUSTED_WORKFLOW_BLOB_SHA,
            actual,
            "trusted workflow changed without moving Final-GO's exact workflow-source authority pin",
        )


if __name__ == "__main__":
    unittest.main()
