#!/usr/bin/env python3
"""Exploit-positive source oracle for the field installer strict-root routing gap."""

from __future__ import annotations

from pathlib import Path
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
INSTALLER = REPOSITORY / "scripts/field/install_one_time_capture.command"
ORCHESTRATOR = REPOSITORY / "scripts/ci/capture_selected_xcode_build_orchestrator.py"


class CaptureFieldInstallerStrictRootRoutingRedTeamTests(unittest.TestCase):
    def test_field_installer_can_still_omit_accepted_generated_manifest_authority(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")
        orchestrator = ORCHESTRATOR.read_text(encoding="utf-8")

        self.assertIn(
            '"$SELECTED_XCODE_BUILD_ORCHESTRATOR_BASE64" \\\n        "$SELECTED_XCODE_BUILD_ORCHESTRATOR_BLOB" \\\n        --field-pid "$$"',
            installer,
        )
        self.assertIn('--install-custody-blob "$SIGNED_APP_CUSTODY_HELPER_BLOB"', installer)

        self.assertNotIn("--accepted-generated-manifest-sha256", installer)
        self.assertIn('parser.add_argument("--accepted-generated-manifest-sha256")', orchestrator)
        self.assertIn("if accepted_generated_manifest_sha256 is not None:", orchestrator)
        self.assertIn(
            "use_native_darwin_acl=(accepted_root is not None)",
            orchestrator,
        )

        print(
            "NEMBRA_FIELD_INSTALLER_STRICT_ROOT_RED "
            "installerPassesAcceptedGeneratedManifest=false "
            "acceptedRootMandatory=false nativeDarwinLeaseMandatory=false "
            "physicalAuthorityCreated=false"
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
