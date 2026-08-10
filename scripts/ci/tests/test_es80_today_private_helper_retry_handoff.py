#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import unittest

REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
HANDOFF = REPOSITORY_ROOT / "docs" / "ES80_TODAY_SIGNED_FIELD_CANDIDATE_PRODUCTION.md"


class PrivateHelperRetryHandoffTests(unittest.TestCase):
    def test_spent_subject_retry_uses_one_derived_fresh_leaf(self):
        handoff = HANDOFF.read_text(encoding="utf-8")
        filename = "UDID_FILENAME='es80-intended-device.udid'"
        derived_path = 'UDID_FILE="$PRIVATE_DIR/$UDID_FILENAME"'
        filename_argument = '--filename "$UDID_FILENAME"'
        helper_invoke = '/usr/bin/python3 -I "$PRIVATE_INPUT_HELPER"'

        self.assertIn(filename, handoff)
        self.assertIn(derived_path, handoff)
        self.assertIn(filename_argument, handoff)
        self.assertLess(handoff.index(filename), handoff.index(helper_invoke))
        self.assertLess(handoff.index(derived_path), handoff.index(helper_invoke))
        self.assertIn("zero-length mode-`0600` spent subject", handoff)
        self.assertIn("set `UDID_FILENAME` to a fresh leaf name", handoff)
        self.assertIn("Do not delete or overwrite an occupied subject", handoff)

    def test_retry_does_not_weaken_accepted_helper_authority(self):
        handoff = HANDOFF.read_text(encoding="utf-8")
        self.assertIn(
            "PRIVATE_INPUT_HELPER_COMMIT='b479d851a54437ef394a4901c69db2d829d280e4'",
            handoff,
        )
        self.assertIn(
            "PRIVATE_INPUT_HELPER_BLOB='62b719e8d9afb34da6d35d696e80edf926442696'",
            handoff,
        )
        self.assertNotIn("af75ffa6dc4409a21822295428e4eeb922ac3d16", handoff)
        self.assertNotIn("50b12675a57fd2f570d833cfcdbfd7be59f52ca4", handoff)
        self.assertIn("PHYSICAL EXPERIMENT ONE REMAINS NO-GO", handoff)


if __name__ == "__main__":
    unittest.main()
