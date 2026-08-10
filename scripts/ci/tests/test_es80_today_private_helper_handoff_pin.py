#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import re
import unittest

REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
HANDOFF = REPOSITORY_ROOT / "docs" / "ES80_TODAY_SIGNED_FIELD_CANDIDATE_PRODUCTION.md"

MERGED_HELPER_COMMIT = "b479d851a54437ef394a4901c69db2d829d280e4"
HELPER_BLOB = "62b719e8d9afb34da6d35d696e80edf926442696"
TESTED_HEAD = "90d3578a1d39a1d019000583a712306b67786acf"
FOCUSED_RUN = "31350148402"
FOCUSED_JOB = "93339277106"
SUPERSEDED_HELPER_COMMIT = "af75ffa6dc4409a21822295428e4eeb922ac3d16"
SUPERSEDED_HELPER_BLOB = "50b12675a57fd2f570d833cfcdbfd7be59f52ca4"


class PrivateHelperHandoffPinTests(unittest.TestCase):
    def test_primary_materialization_uses_nondestructive_helper_identity(self):
        handoff = HANDOFF.read_text(encoding="utf-8")
        self.assertIn(MERGED_HELPER_COMMIT, handoff)
        self.assertIn(HELPER_BLOB, handoff)
        self.assertIn(TESTED_HEAD, handoff)
        self.assertIn(FOCUSED_RUN, handoff)
        self.assertIn(FOCUSED_JOB, handoff)
        self.assertIn(
            f"PRIVATE_INPUT_HELPER_COMMIT='{MERGED_HELPER_COMMIT}'",
            handoff,
        )
        self.assertIn(
            f"PRIVATE_INPUT_HELPER_BLOB='{HELPER_BLOB}'",
            handoff,
        )

    def test_superseded_helper_is_audit_only_not_materialization_authority(self):
        handoff = HANDOFF.read_text(encoding="utf-8")
        self.assertIn(SUPERSEDED_HELPER_COMMIT, handoff)
        self.assertIn(SUPERSEDED_HELPER_BLOB, handoff)
        self.assertNotIn(
            f"PRIVATE_INPUT_HELPER_COMMIT='{SUPERSEDED_HELPER_COMMIT}'",
            handoff,
        )
        self.assertNotIn(
            f"PRIVATE_INPUT_HELPER_BLOB='{SUPERSEDED_HELPER_BLOB}'",
            handoff,
        )
        self.assertIn("Do not materialize or invoke that superseded helper", handoff)

    def test_handoff_preserves_nondestructive_cleanup_boundary(self):
        handoff = HANDOFF.read_text(encoding="utf-8")
        required_phrases = (
            "never unlinks a mutable pathname replacement",
            "zero-length spent subject",
            "do not delete/reuse the occupied private path",
            "PHYSICAL EXPERIMENT ONE REMAINS NO-GO",
        )
        for phrase in required_phrases:
            with self.subTest(phrase=phrase):
                self.assertIn(phrase, handoff)

    def test_materialized_helper_is_verified_by_exact_git_blob(self):
        handoff = HANDOFF.read_text(encoding="utf-8")
        pattern = re.compile(
            r"git rev-parse --verify \"\$PRIVATE_INPUT_HELPER_COMMIT:"
            r"scripts/ci/es80_today_private_device_input\.py\"\)\" = "
            r"\"\$PRIVATE_INPUT_HELPER_BLOB\""
        )
        self.assertRegex(handoff, pattern)


if __name__ == "__main__":
    unittest.main()
