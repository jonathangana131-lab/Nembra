#!/usr/bin/env python3
"""Mechanically bind Final GO trusted-workflow authority to the checked-in workflow bytes.

Any edit to the default-branch trusted Xcode workflow changes its Git blob identity. Final GO must
therefore update its pinned workflow blob in the same accepted composition; otherwise a merged
workflow can become impossible to accept even while unit fixtures remain green.
"""
from __future__ import annotations

import hashlib
import importlib.util
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
WORKFLOW = ROOT / ".github/workflows/capture-xcode27-trusted-command.yml"
SUBJECT = ROOT / "scripts/ci/es80_today_trusted_capture_xcode_subject.py"

spec = importlib.util.spec_from_file_location("trusted_subject_workflow_pin", SUBJECT)
trusted_subject = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(trusted_subject)


def git_blob_sha(raw: bytes) -> str:
    header = f"blob {len(raw)}\0".encode("ascii")
    return hashlib.sha1(header + raw).hexdigest()


class TrustedWorkflowBlobPinTests(unittest.TestCase):
    def test_final_go_pin_equals_checked_in_trusted_workflow_git_blob(self) -> None:
        actual = git_blob_sha(WORKFLOW.read_bytes())
        pinned = trusted_subject.TRUSTED_WORKFLOW_BLOB_SHA

        self.assertRegex(pinned, r"^[0-9a-f]{40}$")
        self.assertEqual(
            actual,
            pinned,
            "trusted Xcode workflow bytes changed without updating Final GO workflow authority pin",
        )

    def test_workflow_path_is_the_same_path_final_go_verifies(self) -> None:
        self.assertEqual(
            trusted_subject.TRUSTED_WORKFLOW_PATH,
            ".github/workflows/capture-xcode27-trusted-command.yml",
        )
        self.assertEqual(
            WORKFLOW.relative_to(ROOT).as_posix(),
            trusted_subject.TRUSTED_WORKFLOW_PATH,
        )


if __name__ == "__main__":
    unittest.main()
