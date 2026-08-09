#!/usr/bin/env python3
"""Expected-red witness for trusted Capture runner metadata provenance.

The default-branch trusted workflow intentionally executes one pinned Simulator evidence producer
blob under an ``env -i`` boundary. The currently pinned producer blob
``4e9ae0cb6728dc68d9b8dd43aac7c50128702ed9`` is the exact producer used by the live Capture
candidate. That producer retains ``githubRunID`` and ``githubRunAttempt`` in
``capture-runner-metadata.json`` and falls back to ``local`` / ``0`` only when those values are
absent for legitimate local execution.

A trusted GitHub Actions run must therefore reintroduce the GitHub-context-expanded run identity
inside the clean interpreter environment. Inheriting caller environment variables would reopen the
boundary; omitting the values records false CI provenance.

This test is validation-only until the workflow and its Final-GO workflow-blob pin are composed on
current main. It does not authorize physical Experiment One.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
WORKFLOW = ROOT / ".github/workflows/capture-xcode27-trusted-command.yml"
SUBJECT = ROOT / "scripts/ci/es80_today_trusted_capture_xcode_subject.py"
KNOWN_RUNNER_METADATA_PRODUCER_BLOB = "4e9ae0cb6728dc68d9b8dd43aac7c50128702ed9"

spec = importlib.util.spec_from_file_location("trusted_subject_runner_metadata", SUBJECT)
trusted_subject = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(trusted_subject)


def workflow_step(name: str) -> str:
    text = WORKFLOW.read_text(encoding="utf-8")
    marker = f"      - name: {name}\n"
    start = text.find(marker)
    if start < 0:
        raise AssertionError(f"missing trusted workflow step: {name}")
    next_step = text.find("\n      - name: ", start + len(marker))
    return text[start:] if next_step < 0 else text[start:next_step]


class TrustedRunnerMetadataContractTests(unittest.TestCase):
    def test_pinned_producer_requires_trusted_github_run_identity(self) -> None:
        self.assertEqual(
            trusted_subject.TRUSTED_SIMULATOR_EVIDENCE_PRODUCER_BLOB_SHA,
            KNOWN_RUNNER_METADATA_PRODUCER_BLOB,
            "re-review this witness when the trusted Simulator producer pin changes",
        )

        step = workflow_step("Build, test, and capture Simulator states")

        # Keep the producer behind a clean-environment interpreter boundary.
        self.assertRegex(
            step,
            re.compile(r"\|\s*/usr/bin/env\s+-i\b(?:(?!^      - name: ).){0,2200}?/bin/bash\b", re.MULTILINE | re.DOTALL),
        )

        # GitHub context expansion supplies trusted run provenance without inheriting mutable
        # process-environment values into the authority-producing interpreter.
        self.assertIn('GITHUB_RUN_ID="${{ github.run_id }}"', step)
        self.assertIn('GITHUB_RUN_ATTEMPT="${{ github.run_attempt }}"', step)
        self.assertNotIn('GITHUB_RUN_ID="$GITHUB_RUN_ID"', step)
        self.assertNotIn('GITHUB_RUN_ATTEMPT="$GITHUB_RUN_ATTEMPT"', step)


if __name__ == "__main__":
    unittest.main()
