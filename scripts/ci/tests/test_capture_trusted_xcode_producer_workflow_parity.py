#!/usr/bin/env python3
"""Expected-red parity gate for trusted Xcode producer custody.

The Final-GO verifier must not require producer-custody evidence that the pinned default-branch
workflow can never emit. The trusted workflow itself must verify the exact candidate-side Simulator
evidence producer before executing it, and the verifier must pin that exact workflow implementation.
"""
from __future__ import annotations

import hashlib
import importlib.util
from pathlib import Path
import re
import unittest

CI_DIR = Path(__file__).resolve().parents[1]
REPO_ROOT = CI_DIR.parents[1]
WORKFLOW_PATH = REPO_ROOT / ".github/workflows/capture-xcode27-trusted-command.yml"
SUBJECT_PATH = CI_DIR / "es80_today_trusted_capture_xcode_subject.py"


def _load_subject():
    spec = importlib.util.spec_from_file_location("trusted_subject_workflow_parity", SUBJECT_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load trusted Capture Xcode subject verifier")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _git_blob_sha(raw: bytes) -> str:
    framed = f"blob {len(raw)}\0".encode() + raw
    return hashlib.sha1(framed).hexdigest()


class TrustedXcodeProducerWorkflowParityTests(unittest.TestCase):
    def test_pinned_workflow_mechanically_verifies_producer_before_execution(self) -> None:
        subject = _load_subject()
        raw = WORKFLOW_PATH.read_bytes()
        workflow = raw.decode("utf-8")

        custody_marker = "- name: Verify trusted Simulator evidence-producer custody"
        build_marker = "- name: Build, test, and capture Simulator states"
        self.assertIn(custody_marker, workflow, "trusted workflow never emits the custody step required by Final GO")
        self.assertIn(build_marker, workflow)
        custody_start = workflow.index(custody_marker)
        build_start = workflow.index(build_marker)
        self.assertLess(custody_start, build_start, "producer custody must be verified before the producer executes")

        custody_block = workflow[custody_start:build_start]
        self.assertIn(subject.TRUSTED_SIMULATOR_EVIDENCE_PRODUCER_PATH, custody_block)
        self.assertIn(subject.TRUSTED_SIMULATOR_EVIDENCE_PRODUCER_BLOB_SHA, custody_block)
        self.assertRegex(
            custody_block,
            re.compile(r"(?:rev-parse|hash-object|cat-file)", re.IGNORECASE),
            "custody step must derive Git object identity rather than trust a label",
        )
        self.assertRegex(
            custody_block,
            re.compile(r"(?:test\s+.*=|!=|==|assert|raise|exit\s+[1-9])", re.IGNORECASE | re.DOTALL),
            "custody step must fail closed on producer-blob mismatch",
        )

        self.assertEqual(
            _git_blob_sha(raw),
            subject.TRUSTED_WORKFLOW_BLOB_SHA,
            "Final-GO verifier must pin the exact workflow bytes that emit producer-custody evidence",
        )


if __name__ == "__main__":
    unittest.main()
