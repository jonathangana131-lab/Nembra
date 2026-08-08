#!/usr/bin/env python3
"""Source-contract regression for trusted Apple signing-tool selection.

The canonical signed-field inspector is a release/provenance authority boundary. It must not
resolve `codesign` or `security` through caller-controlled PATH because a substituted executable
could fabricate signing/provisioning evidence for the retained IPA.

This test is intentionally expected-red on the vulnerable parent. The production repair belongs in
`scripts/ci/es80_signed_field_artifact_evidence.py`; do not weaken this test to make it green.
"""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[3]
INSPECTOR = ROOT / "scripts/ci/es80_signed_field_artifact_evidence.py"


class AppleToolCustodySourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source = INSPECTOR.read_text(encoding="utf-8")

    def test_codesign_does_not_use_ambient_path(self) -> None:
        self.assertNotIn(
            'shutil.which("codesign")',
            self.source,
            "signed-field verification must not let PATH select codesign",
        )
        self.assertIn(
            '"/usr/bin/codesign"',
            self.source,
            "signed-field verification should bind to the protected Apple codesign path",
        )

    def test_security_does_not_use_ambient_path(self) -> None:
        self.assertNotIn(
            'shutil.which("security")',
            self.source,
            "provisioning verification must not let PATH select security",
        )
        self.assertIn(
            '"/usr/bin/security"',
            self.source,
            "provisioning verification should bind to the protected Apple security path",
        )


if __name__ == "__main__":
    unittest.main()
