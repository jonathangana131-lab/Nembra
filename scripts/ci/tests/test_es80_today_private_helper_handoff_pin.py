#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import unittest

REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
PRODUCTION_HANDOFF = REPOSITORY_ROOT / "docs" / "ES80_TODAY_SIGNED_FIELD_CANDIDATE_PRODUCTION.md"
CUSTODY_HANDOFF = REPOSITORY_ROOT / "docs" / "ES80_TODAY_PRIVATE_DEVICE_INPUT_CUSTODY.md"


class PrivateHelperHandoffPinTests(unittest.TestCase):
    MERGED_COMMIT = "b479d851a54437ef394a4901c69db2d829d280e4"
    ACCEPTED_HEAD = "90d3578a1d39a1d019000583a712306b67786acf"
    HELPER_BLOB = "62b719e8d9afb34da6d35d696e80edf926442696"
    QA_RUN = "31350094260"
    QA_JOB = "93339137927"

    def documents(self) -> tuple[str, str]:
        return (
            PRODUCTION_HANDOFF.read_text(encoding="utf-8"),
            CUSTODY_HANDOFF.read_text(encoding="utf-8"),
        )

    def test_both_operator_handoffs_cross_bind_current_accepted_helper(self):
        production, custody = self.documents()
        for document in (production, custody):
            with self.subTest(document=document[:48]):
                self.assertIn(self.MERGED_COMMIT, document)
                self.assertIn(self.ACCEPTED_HEAD, document)
                self.assertIn(self.HELPER_BLOB, document)
                self.assertIn(self.QA_RUN, document)
                self.assertIn(self.QA_JOB, document)

    def test_active_materialization_assignments_cannot_be_satisfied_by_audit_history(self):
        production, custody = self.documents()
        active_commit = f"PRIVATE_INPUT_HELPER_COMMIT='{self.MERGED_COMMIT}'"
        active_blob = f"PRIVATE_INPUT_HELPER_BLOB='{self.HELPER_BLOB}'"
        stale_commit = "PRIVATE_INPUT_HELPER_COMMIT='af75ffa6dc4409a21822295428e4eeb922ac3d16'"
        stale_blob = "PRIVATE_INPUT_HELPER_BLOB='50b12675a57fd2f570d833cfcdbfd7be59f52ca4'"

        for document in (production, custody):
            with self.subTest(document=document[:48]):
                self.assertEqual(document.count(active_commit), 1)
                self.assertEqual(document.count(active_blob), 1)
                self.assertNotIn(stale_commit, document)
                self.assertNotIn(stale_blob, document)

    def test_handoffs_keep_nondestructive_failure_cleanup_and_no_go_boundary(self):
        production, custody = self.documents()
        for document in (production, custody):
            with self.subTest(document=document[:48]):
                self.assertIn("zero-length", document)
                self.assertIn("NO-GO", document)
        self.assertIn("never unlinks a pathname", production)
        self.assertIn("never performs pathname deletion", custody)

    def test_both_handoffs_make_fresh_leaf_retry_mechanically_executable(self):
        production, custody = self.documents()
        filename_assignment = "UDID_FILENAME='es80-intended-device.udid'"
        derived_path = 'UDID_FILE="$PRIVATE_DIR/$UDID_FILENAME"'
        helper_filename_argument = '--filename "$UDID_FILENAME"'

        for document in (production, custody):
            with self.subTest(document=document[:48]):
                self.assertEqual(document.count(filename_assignment), 1)
                self.assertEqual(document.count(derived_path), 1)
                self.assertIn(helper_filename_argument, document)
                self.assertIn("set `UDID_FILENAME` to a fresh leaf name", document)
                self.assertLess(document.index(filename_assignment), document.index(helper_filename_argument))
                self.assertLess(document.index(derived_path), document.index(helper_filename_argument))


if __name__ == "__main__":
    unittest.main()