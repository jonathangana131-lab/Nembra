#!/usr/bin/env python3
"""Portable source contract for immutable private-input provenance export custody."""

from __future__ import annotations

from pathlib import Path
import subprocess
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
IDENTITY = REPOSITORY / "NembraApp/App/NembraCaptureBuildIdentity.swift"
ENTRYPOINT = REPOSITORY / "NembraApp/App/NembraCaptureEntrypoint.swift"
PROJECT = REPOSITORY / "NembraCapture.xcodeproj/project.pbxproj"
INFO_PLIST = REPOSITORY / "NembraCapture-Info.plist"
INSTALLER = REPOSITORY / "scripts/field/install_one_time_capture.command"
EXPORT_WORKFLOW = REPOSITORY / ".github/workflows/capture-private-provenance-export-custody.yml"
FINAL_AUTHORITY_WORKFLOW = REPOSITORY / ".github/workflows/capture-final-authority-exact-head.yml"


class CapturePrivateProvenanceExportCustodyTests(unittest.TestCase):
    def test_build_identity_requires_exact_private_manifest_sha256(self) -> None:
        source = IDENTITY.read_text(encoding="utf-8")
        self.assertIn(
            'tuyaPrivateInputProvenanceSHA256InfoKey = "NembraCaptureTuyaPrivateInputProvenanceSHA256"',
            source,
        )
        self.assertIn("let tuyaPrivateInputProvenanceSHA256: String", source)
        self.assertIn("tuyaPrivateInputProvenanceSHA256.count == 64", source)
        self.assertIn("tuyaPrivateInputProvenanceSHA256.allSatisfy", source)

    def test_project_stamps_private_manifest_into_generated_info_plist(self) -> None:
        source = PROJECT.read_text(encoding="utf-8")
        marker = (
            'INFOPLIST_KEY_NembraCaptureTuyaPrivateInputProvenanceSHA256 = '
            '"$(NEMBRA_CAPTURE_TUYA_PRIVATE_PROVENANCE_SHA256)";'
        )
        self.assertEqual(source.count(marker), 2)

    def test_explicit_info_plist_and_acceptance_gates_cover_private_manifest(self) -> None:
        plist = INFO_PLIST.read_text(encoding="utf-8")
        self.assertIn("<key>NembraCaptureTuyaPrivateInputProvenanceSHA256</key>", plist)
        self.assertIn("<string>$(NEMBRA_CAPTURE_TUYA_PRIVATE_PROVENANCE_SHA256)</string>", plist)

        trigger = "      - NembraCapture-Info.plist"
        for workflow in (EXPORT_WORKFLOW, FINAL_AUTHORITY_WORKFLOW):
            source = workflow.read_text(encoding="utf-8")
            self.assertEqual(
                source.count(trigger),
                1,
                f"{workflow.name} must re-run on an explicit Capture Info.plist provenance change",
            )

    def test_installer_passes_and_reads_back_same_accepted_digest_before_install(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")
        compile_marker = (
            '"NEMBRA_CAPTURE_TUYA_PRIVATE_PROVENANCE_SHA256='
            '$ACCEPTED_TUYA_PROVENANCE_SHA256"'
        )
        read_marker = (
            'plutil -extract NembraCaptureTuyaPrivateInputProvenanceSHA256 raw '
            '-o - "$APP_INFO_PLIST"'
        )
        check_marker = (
            '[[ "$BUILT_TUYA_PRIVATE_PROVENANCE_SHA256" == '
            '"$ACCEPTED_TUYA_PROVENANCE_SHA256" ]]'
        )
        install_marker = (
            'say "Installing SDK-integrated Capture on the intended iPhone through '
            'frozen selected-Xcode devicectl"'
        )
        for marker in (compile_marker, read_marker, check_marker, install_marker):
            self.assertIn(marker, source)
        self.assertLess(source.index(compile_marker), source.index(read_marker))
        self.assertLess(source.index(read_marker), source.index(check_marker))
        self.assertLess(source.index(check_marker), source.index(install_marker))

    def test_immutable_export_carries_digest_and_schema_is_bumped(self) -> None:
        source = ENTRYPOINT.read_text(encoding="utf-8")
        self.assertIn("let tuyaPrivateInputProvenanceSHA256: String", source)
        self.assertIn(
            "tuyaPrivateInputProvenanceSHA256: buildIdentity.tuyaPrivateInputProvenanceSHA256",
            source,
        )
        self.assertIn("schemaVersion: 11", source)
        self.assertNotIn("schemaVersion: 10", source)

    def test_field_installer_still_parses_after_provenance_promotion(self) -> None:
        completed = subprocess.run(
            ["/bin/bash", "-n", str(INSTALLER)],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
