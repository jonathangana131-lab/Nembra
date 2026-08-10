#!/usr/bin/env python3
from pathlib import Path
import re
import unittest

PRODUCER = Path(__file__).resolve().parents[1] / "xcode27_signed_field_candidate.sh"


class SignedFieldCandidateXcodeEnvironmentCustodySourceTests(unittest.TestCase):
    """Pin the signed-device build toolchain and build-setting environment."""

    def setUp(self) -> None:
        self.source = PRODUCER.read_text(encoding="utf-8")

    def test_xcodebuild_runs_under_one_explicit_closed_environment(self) -> None:
        start = self.source.find("run_xcodebuild()")
        self.assertNotEqual(start, -1, "Expected one producer-owned run_xcodebuild boundary")
        end = self.source.find("\n}", start)
        self.assertNotEqual(end, -1, "Expected run_xcodebuild wrapper terminator")
        wrapper = self.source[start : end + 2]

        self.assertIn(
            "env -i",
            wrapper,
            "Signed-device archive/export must not inherit caller Xcode, xcconfig, toolchain, loader, or build-setting environment semantics.",
        )
        self.assertIn(
            "/usr/bin/xcodebuild",
            wrapper,
            "The release wrapper must execute the system xcodebuild dispatcher by absolute path.",
        )
        self.assertIn(
            "DEVELOPER_DIR=",
            wrapper,
            "The closed child environment must carry only the producer-selected developer directory.",
        )

    def test_producer_verifies_xcode_27_before_real_archive_call(self) -> None:
        archive_call = self.source.find('if ! run_archive_xcodebuild \\\n  -project Nembra.xcodeproj')
        self.assertNotEqual(archive_call, -1, "Expected the signed-device archive call")
        prefix = self.source[:archive_call]

        self.assertRegex(
            prefix,
            re.compile(r"(?:/usr/bin/)?xcodebuild[^\n]*-version|run_xcodebuild[^\n]*-version"),
            "The producer must interrogate the selected Xcode before archive/export.",
        )
        self.assertRegex(
            prefix,
            re.compile(r"Xcode\s+27"),
            "Field-candidate production must fail closed unless the selected toolchain identifies as Xcode 27.",
        )

    def test_raw_xcodebuild_cannot_bypass_closed_wrapper(self) -> None:
        raw_invocations = [
            line
            for line in self.source.splitlines()
            if re.search(r"(^|[;&|$(]\s*)xcodebuild(?:\s|$)", line)
            and not line.lstrip().startswith("#")
        ]
        self.assertEqual(
            raw_invocations,
            [],
            "All archive/export/version interrogation must stay behind the producer-owned Xcode environment boundary: "
            + " | ".join(raw_invocations),
        )


if __name__ == "__main__":
    unittest.main()
