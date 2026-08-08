#!/usr/bin/env python3
from pathlib import Path
import re
import unittest

INSPECTOR = Path(__file__).resolve().parents[1] / "es80_signed_field_artifact_evidence.py"


class SignedFieldArtifactAppleToolCustodySourceTests(unittest.TestCase):
    def setUp(self):
        self.source = INSPECTOR.read_text(encoding="utf-8")

    def test_inspector_does_not_discover_trust_tools_from_ambient_path(self):
        for tool in ("codesign", "security"):
            self.assertNotIn(
                f'shutil.which("{tool}")',
                self.source,
                f"Signed-field authority must not discover {tool} from ambient PATH.",
            )
            self.assertNotRegex(
                self.source,
                re.compile(rf"\bwhich\s*\(\s*['\"]{tool}['\"]\s*\)"),
                f"Ambient PATH selection of {tool} can fabricate signed-field evidence.",
            )

    def test_inspector_pins_apple_trust_tools_to_explicit_system_paths(self):
        self.assertIn(
            "/usr/bin/codesign",
            self.source,
            "Signed-field inspection must execute the canonical Apple codesign binary explicitly.",
        )
        self.assertIn(
            "/usr/bin/security",
            self.source,
            "Provisioning inspection must execute the canonical Apple security binary explicitly.",
        )
        self.assertTrue(
            "resolve(strict=True)" in self.source or ".resolve(" in self.source,
            "Apple trust-tool paths must be canonicalized before use.",
        )
        self.assertIn(
            "stat.S_ISREG",
            self.source,
            "Apple trust tools must be verified as regular files before use.",
        )
        self.assertTrue(
            "0o022" in self.source or "group/world-writable" in self.source.lower(),
            "Writable Apple trust-tool custody must fail closed.",
        )
        self.assertIn(
            "st_uid",
            self.source,
            "Apple trust-tool ownership must be mechanically checked.",
        )
        self.assertTrue(
            "st_uid != 0" in self.source
            or "st_uid == 0" in self.source
            or "st_uid not in {0}" in self.source,
            "Canonical Apple trust tools must be root-owned, not merely owned by the signing user.",
        )

    def test_canonical_parent_custody_is_checked_before_trusting_apple_tools(self):
        self.assertTrue(
            "while True" in self.source or ".parents" in self.source,
            "The trust-tool custody check must walk the canonical parent directory chain.",
        )
        self.assertTrue(
            "directory.stat" in self.source or "parent.stat" in self.source,
            "Canonical trust-tool parent directories must be inspected mechanically.",
        )
        self.assertTrue(
            "directory.parent" in self.source or ".parents" in self.source,
            "The custody check must not stop at only the executable inode.",
        )

    def test_codesign_and_provisioning_paths_share_the_custody_boundary(self):
        self.assertNotIn('codesign = shutil.which("codesign")', self.source)
        self.assertNotIn('security = shutil.which("security")', self.source)
        self.assertGreaterEqual(
            self.source.count("codesign"),
            2,
            "Both code-signature verification paths must remain represented after centralizing custody.",
        )
        self.assertIn(
            "embedded.mobileprovision",
            self.source,
            "Provisioning-profile verification must remain part of signed-field inspection.",
        )


if __name__ == "__main__":
    unittest.main()
