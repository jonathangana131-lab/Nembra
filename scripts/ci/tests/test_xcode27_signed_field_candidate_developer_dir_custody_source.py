#!/usr/bin/env python3
from pathlib import Path
import re
import unittest

PRODUCER = Path(__file__).resolve().parents[1] / "xcode27_signed_field_candidate.sh"


class SignedFieldCandidateDeveloperDirectoryCustodySourceTests(unittest.TestCase):
    """Pin selected Xcode as a custody-verified release-authority subject."""

    def setUp(self) -> None:
        self.source = PRODUCER.read_text(encoding="utf-8")

    def test_developer_directory_is_selected_by_system_tool_not_caller_environment(self) -> None:
        self.assertRegex(
            self.source,
            re.compile(r'DEVELOPER_DIR=.*(?:/usr/bin/)?xcode-select[^\n]*-p'),
            "Signed field production must derive DEVELOPER_DIR from the system Xcode selector rather than trust a caller-supplied developer directory.",
        )
        self.assertNotRegex(
            self.source,
            re.compile(r'DEVELOPER_DIR=\"?\$\{?NEMBRA_|DEVELOPER_DIR=\"?\$\{?DEVELOPER_DIR'),
            "The release toolchain root must not be selected from caller environment variables.",
        )

    def test_selected_developer_directory_has_root_nonwritable_ancestry_custody(self) -> None:
        custody_function = re.search(
            r'(?ms)^validate_root_custodied_path\(\)\s*\{.*?^\}',
            self.source,
        )
        self.assertIsNotNone(custody_function, "Expected the existing root/nonwritable custody primitive")
        self.assertRegex(
            self.source,
            re.compile(r'validate_root_custodied_path\s+\"?\$DEVELOPER_DIR\"?\s+directory'),
            "The exact selected Developer directory must pass the same root-owned/non-group-or-world-writable ancestry proof as other release executables.",
        )

    def test_xcode_version_probe_and_archive_share_same_closed_wrapper(self) -> None:
        start = self.source.find("run_xcodebuild()")
        self.assertNotEqual(start, -1, "Expected one producer-owned Xcode boundary")
        end = self.source.find("\n}", start)
        self.assertNotEqual(end, -1, "Expected run_xcodebuild wrapper terminator")
        wrapper = self.source[start : end + 2]
        self.assertIn("env -i", wrapper)
        self.assertIn("/usr/bin/xcodebuild", wrapper)
        self.assertIn("DEVELOPER_DIR=", wrapper)

        version_probe = re.search(r'run_xcodebuild[^\n]*-version', self.source)
        self.assertIsNotNone(version_probe, "Selected Xcode must be interrogated through the same closed wrapper used for archive/export")
        archive_call = self.source.find('if ! run_xcodebuild \\\n  -project Nembra.xcodeproj')
        self.assertGreater(archive_call, version_probe.start())
        self.assertRegex(
            self.source[:archive_call],
            re.compile(r'Xcode\s+27(?:\.|\b)'),
            "Archive must be unreachable unless the selected toolchain identifies as Xcode 27.",
        )

    def test_closed_xcode_child_does_not_reimport_toolchain_override_environment(self) -> None:
        start = self.source.find("run_xcodebuild()")
        self.assertNotEqual(start, -1)
        end = self.source.find("\n}", start)
        wrapper = self.source[start : end + 2]
        for forbidden in (
            "TOOLCHAINS=$TOOLCHAINS",
            "SDKROOT=$SDKROOT",
            "XCODE_XCCONFIG_FILE=$XCODE_XCCONFIG_FILE",
            "DYLD_INSERT_LIBRARIES=$DYLD_INSERT_LIBRARIES",
            "DYLD_LIBRARY_PATH=$DYLD_LIBRARY_PATH",
        ):
            self.assertNotIn(forbidden, wrapper)


if __name__ == "__main__":
    unittest.main()
