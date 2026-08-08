#!/usr/bin/env python3
from pathlib import Path
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "xcode27_signed_field_candidate.sh"


class SignedFieldCandidateDescriptorSubjectCustodySourceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.source = SCRIPT.read_text(encoding="utf-8")

    def test_each_executable_tool_descriptor_is_exact_source_bound_after_open(self) -> None:
        start = self.source.index('exec 7< "$PRIVATE_RUNNER_SNAPSHOT"')
        end = self.source.index('rm -f "$PRIVATE_RUNNER_SNAPSHOT" "$INSPECTOR_SNAPSHOT"', start)
        binding = self.source[start:end]
        for descriptor in (7, 8, 9):
            self.assertIn(f"/dev/fd/{descriptor}", binding)
        self.assertGreaterEqual(binding.count("PRIVATE_RUNNER_BLOB_SHA"), 2)
        self.assertIn("INSPECTOR_BLOB_SHA", binding)

    def test_descriptor_verification_preserves_execution_read_position(self) -> None:
        start = self.source.index('exec 7< "$PRIVATE_RUNNER_SNAPSHOT"')
        end = self.source.index('rm -f "$PRIVATE_RUNNER_SNAPSHOT" "$INSPECTOR_SNAPSHOT"', start)
        binding = self.source[start:end].lower()
        self.assertTrue("pread" in binding or "lseek" in binding or "seek(" in binding)


if __name__ == "__main__":
    unittest.main()
