#!/usr/bin/env python3
from pathlib import Path
import re
import unittest

PRODUCER = Path(__file__).resolve().parents[1] / "xcode27_signed_field_candidate.sh"


class SignedFieldCandidateXcodeEnvironmentCustodySourceTests(unittest.TestCase):
    """Pin the signed-device build toolchain and build-setting environment."""

    def setUp(self) -> None:
        self.source = PRODUCER.read_text(encoding="utf-8")

    def _wrapper(self) -> str:
        start = self.source.find("run_xcodebuild()")
        self.assertNotEqual(start, -1, "Expected one producer-owned run_xcodebuild boundary")
        end = self.source.find("\n}", start)
        self.assertNotEqual(end, -1, "Expected run_xcodebuild wrapper terminator")
        return self.source[start : end + 2]

    def test_xcodebuild_runs_under_one_explicit_closed_environment(self) -> None:
        wrapper = self._wrapper()
        self.assertIn("/usr/bin/env -i", wrapper)
        self.assertIn("/usr/bin/xcodebuild", wrapper)
        self.assertIn("DEVELOPER_DIR=", wrapper)
        self.assertIn("HOME=", wrapper)
        self.assertIn("PATH=/usr/bin:/bin:/usr/sbin:/sbin", wrapper)

    def test_producer_selects_developer_directory_without_ambient_developer_dir(self) -> None:
        self.assertIn("/usr/bin/xcode-select -p", self.source)
        selection = self.source[: self.source.find("run_xcodebuild()")]
        self.assertIn("/usr/bin/env -i", selection)
        self.assertIn("PATH=/usr/bin:/bin:/usr/sbin:/sbin", selection)
        self.assertNotIn("${DEVELOPER_DIR", selection)

    def test_producer_verifies_xcode_27_before_real_archive_call(self) -> None:
        archive_call = self.source.find('if ! run_xcodebuild \\\n  -project Nembra.xcodeproj')
        self.assertNotEqual(archive_call, -1, "Expected the signed-device archive call")
        prefix = self.source[:archive_call]
        self.assertIn("run_xcodebuild -version", prefix)
        self.assertRegex(prefix, re.compile(r"Xcode\\ 27|Xcode 27"))

    def test_raw_xcodebuild_cannot_bypass_closed_wrapper(self) -> None:
        wrapper = self._wrapper()
        without_wrapper = self.source.replace(wrapper, "")
        raw_invocations = [
            line.strip()
            for line in without_wrapper.splitlines()
            if re.search(r"(^|[;&|$(]\s*)(?:/usr/bin/)?xcodebuild(?:\s|$)", line)
            and not line.lstrip().startswith("#")
        ]
        self.assertEqual(
            raw_invocations,
            [],
            "All version/archive/export interrogation must stay behind the producer-owned Xcode environment boundary: "
            + " | ".join(raw_invocations),
        )

    def test_ambient_build_setting_override_names_are_not_forwarded(self) -> None:
        wrapper = self._wrapper()
        for name in (
            "XCODE_XCCONFIG_FILE",
            "TOOLCHAINS",
            "SDKROOT",
            "DYLD_INSERT_LIBRARIES",
            "DYLD_LIBRARY_PATH",
        ):
            self.assertNotIn(name, wrapper)


if __name__ == "__main__":
    unittest.main()
