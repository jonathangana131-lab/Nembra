#!/usr/bin/env python3
from pathlib import Path
import re
import unittest

PRODUCER = Path(__file__).resolve().parents[1] / "xcode27_signed_field_candidate.sh"


class SignedFieldCandidateXcodeEnvironmentCustodySourceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.source = PRODUCER.read_text(encoding="utf-8")

    def test_xcodebuild_runs_under_one_explicit_closed_environment(self) -> None:
        start = self.source.find("run_xcodebuild()")
        self.assertNotEqual(start, -1)
        end = self.source.find("\n}", start)
        self.assertNotEqual(end, -1)
        wrapper = self.source[start : end + 2]
        self.assertIn("env -i", wrapper)
        self.assertIn("/usr/bin/xcodebuild", wrapper)
        self.assertIn("DEVELOPER_DIR=", wrapper)

    def test_producer_verifies_xcode_27_before_real_archive_call(self) -> None:
        archive_call = self.source.find('if ! run_xcodebuild \\\n  -project Nembra.xcodeproj')
        self.assertNotEqual(archive_call, -1)
        prefix = self.source[:archive_call]
        self.assertRegex(prefix, re.compile(r"(?:/usr/bin/)?xcodebuild[^\n]*-version|run_xcodebuild[^\n]*-version"))
        self.assertRegex(prefix, re.compile(r"Xcode\s+27"))

    def test_raw_xcodebuild_cannot_bypass_closed_wrapper(self) -> None:
        raw_invocations = [
            line for line in self.source.splitlines()
            if re.search(r"(^|[;&|$(]\s*)xcodebuild(?:\s|$)", line)
            and not line.lstrip().startswith("#")
        ]
        self.assertEqual(raw_invocations, [])


if __name__ == "__main__":
    unittest.main()
