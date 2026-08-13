#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import unittest


SUBJECT = Path(__file__).with_name("test_capture_apple_signing_trusted_bootstrap_boundary.py")


class NumericIdentityLifecycleSourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source = SUBJECT.read_text(encoding="utf-8")

    def test_candidate_id_checks_process_occupancy(self) -> None:
        self.assertIn("def numeric_uid_processes(", self.source)
        start = self.source.index("def choose_numeric_identity() -> int:")
        end = self.source.index("\n\ndef ds_record_exists", start)
        choose = self.source[start:end]
        self.assertIn("numeric_uid_processes(candidate)", choose)

    def test_cleanup_requires_process_absence_before_identity_deletion(self) -> None:
        delete_anchor = "                delete_identity(user)"
        delete_index = self.source.rindex(delete_anchor)
        finally_index = self.source.rfind("    finally:\n", 0, delete_index)
        self.assertNotEqual(finally_index, -1)
        cleanup = self.source[finally_index:delete_index]
        self.assertIn("numeric_uid_processes(numeric_id)", cleanup)
        self.assertTrue(
            "require(not numeric_uid_processes(numeric_id)" in cleanup
            or "require(len(numeric_uid_processes(numeric_id)) == 0" in cleanup
        )


if __name__ == "__main__":
    unittest.main()
