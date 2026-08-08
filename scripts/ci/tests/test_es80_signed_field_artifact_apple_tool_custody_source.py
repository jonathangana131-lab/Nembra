#!/usr/bin/env python3
from pathlib import Path
import re
import unittest

INSPECTOR = Path(__file__).resolve().parents[1] / "es80_signed_field_artifact_evidence.py"


class SignedFieldArtifactAppleToolCustodySourceTests(unittest.TestCase):
    def setUp(self):
        self.source = INSPECTOR.read_text()

    def test_security_critical_apple_tools_are_not_discovered_from_ambient_path(self):
        self.assertNotRegex(
            self.source,
            re.compile(r"\bshutil\.which\s*\(\s*['\"]codesign['\"]\s*\)"),
            "Signed-field evidence must not trust an ambient-PATH codesign executable to attest signature identity.",
        )
        self.assertNotRegex(
            self.source,
            re.compile(r"\bshutil\.which\s*\(\s*['\"]security['\"]\s*\)"),
            "Provisioning evidence must not trust an ambient-PATH security executable to decode the profile being promoted.",
        )

    def test_inspector_names_explicit_system_apple_tool_paths(self):
        self.assertIn(
            "/usr/bin/codesign",
            self.source,
            "The canonical inspector must select the system codesign binary explicitly.",
        )
        self.assertIn(
            "/usr/bin/security",
            self.source,
            "The canonical inspector must select the system security binary explicitly.",
        )

    def test_tool_selection_fails_closed_instead_of_falling_back_to_path_search(self):
        lowered = self.source.lower()
        self.assertTrue(
            "regular" in lowered or "is_file" in self.source or "stat.S_ISREG" in self.source,
            "Explicit Apple tool selection must fail closed if the trusted system path is not a regular file.",
        )
        self.assertNotIn(
            'which("codesign")',
            self.source,
            "No fallback to ambient PATH is allowed after explicit tool validation fails.",
        )
        self.assertNotIn(
            'which("security")',
            self.source,
            "No fallback to ambient PATH is allowed after explicit tool validation fails.",
        )

    def test_tool_and_parent_custody_remain_root_owned_and_nonwritable(self):
        self.assertIn(
            "metadata.st_uid != 0",
            self.source,
            "A security-critical Apple executable must remain root-owned before its output can become evidence.",
        )
        self.assertIn(
            "stat.S_IMODE(metadata.st_mode) & 0o022",
            self.source,
            "Group/world-writable Apple executables must remain rejected.",
        )
        self.assertIn(
            "stat.S_IMODE(metadata.st_mode) & 0o111 == 0",
            self.source,
            "The pinned Apple tool must remain executable rather than merely a root-owned regular file.",
        )
        self.assertIn(
            "stat.S_ISDIR(parent_metadata.st_mode)",
            self.source,
            "The immediate system-tool parent must remain mechanically verified as a directory.",
        )
        self.assertIn(
            "parent_metadata.st_uid != 0",
            self.source,
            "The immediate system-tool parent must remain root-owned.",
        )
        self.assertIn(
            "stat.S_IMODE(parent_metadata.st_mode) & 0o022",
            self.source,
            "A group/world-writable Apple-tool parent must remain rejected.",
        )

    def test_trusted_tool_helper_remains_absolute_and_shared_by_all_authority_paths(self):
        self.assertIn(
            "if not path.is_absolute()",
            self.source,
            "Trusted Apple tools must remain absolute paths rather than caller-relative names.",
        )
        self.assertGreaterEqual(
            self.source.count("_trusted_system_apple_tool(Path(\"/usr/bin/codesign\")"),
            2,
            "Both code-signature and entitlement/certificate paths must share the trusted codesign boundary.",
        )
        self.assertIn(
            "_trusted_system_apple_tool(Path(\"/usr/bin/security\"), \"security\")",
            self.source,
            "Provisioning-profile decoding must share the trusted Apple-tool boundary.",
        )


if __name__ == "__main__":
    unittest.main()
