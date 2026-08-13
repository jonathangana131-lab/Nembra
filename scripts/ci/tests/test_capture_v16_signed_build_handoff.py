#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]


def text(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


class CaptureV16SignedBuildHandoffTests(unittest.TestCase):
    def test_private_generated_inputs_are_explicitly_ignored(self) -> None:
        ignore = text(".gitignore").splitlines()
        for required in (
            "LocalSecrets/",
            "Pods/",
            "Podfile.lock",
            "NembraCapture.xcworkspace/",
        ):
            self.assertIn(required, ignore)

    def test_authenticated_tuya_workspace_is_exactly_pinned(self) -> None:
        podfile = text("Podfile")
        self.assertIn("project 'NembraCapture.xcodeproj'", podfile)
        self.assertIn("target 'Nembra Capture' do", podfile)
        self.assertIn("pod 'ThingSmartCryption', :path => './LocalSecrets/TuyaSDK'", podfile)
        self.assertIn("pod 'NembraTuyaPrivateConfig', :path => './LocalSecrets/TuyaRuntime'", podfile)
        self.assertIn("pod 'ThingSmartHomeKit', '7.8.0'", podfile)
        self.assertIn("pod 'ThingSmartBusinessExtensionKit', '7.8.0'", podfile)

        bootstrap = text("Scripts/bootstrap_capture_tuya_sdk.sh")
        self.assertIn("NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256", bootstrap)
        self.assertIn("ThingSmartHomeKit (7.8.0)", bootstrap)
        self.assertIn("ThingSmartBusinessExtensionKit (7.8.0)", bootstrap)
        self.assertIn("capture_tuya_private_input_provenance.py", bootstrap)

    def test_signed_candidate_producer_is_build_only(self) -> None:
        producer = text("scripts/field/build_signed_capture_candidate.command")
        self.assertIn('-workspace "$ROOT/NembraCapture.xcworkspace"', producer)
        self.assertIn('-scheme "Nembra Capture"', producer)
        self.assertIn("-configuration Release", producer)
        self.assertIn('-destination "generic/platform=iOS"', producer)
        self.assertIn('-archivePath "$ARCHIVE_PATH"', producer)
        self.assertIn("archive", producer)
        self.assertIn("/usr/bin/codesign --verify --deep --strict", producer)
        self.assertIn("SIGNED BUILD CANDIDATE ONLY — NOT INSTALLED — PHYSICAL NO-GO.", producer)

        for forbidden in (
            "devicectl ",
            "xctrace ",
            "simctl ",
            "install_one_time_capture.command",
            "CBCentralManager",
            "writeValue(",
        ):
            self.assertNotIn(forbidden, producer)

    def test_signed_candidate_binds_current_app_provenance_contract(self) -> None:
        producer = text("scripts/field/build_signed_capture_candidate.command")
        project = text("NembraCapture.xcodeproj/project.pbxproj")
        identity = text("NembraApp/App/NembraCaptureBuildIdentity.swift")

        for setting in (
            "NEMBRA_CAPTURE_BUILD_IDENTIFIER=$BUILD_LABEL",
            "NEMBRA_CAPTURE_BUILD_COMMIT_SHA=$SOURCE_SHA",
            "NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256=$TUYA_LOCK_SHA256",
            "NEMBRA_CAPTURE_PROCEDURE_IDENTIFIER=$PROCEDURE_ID",
        ):
            self.assertIn(setting, producer)

        for key in (
            "NembraCaptureBuildIdentifier",
            "NembraCaptureSourceCommitSHA",
            "NembraCaptureTuyaDependencyLockSHA256",
            "NembraCaptureProcedureIdentifier",
        ):
            self.assertIn(key, producer)
            self.assertIn(key, project)
            self.assertIn(key, identity)

        self.assertIn('PROCEDURE_ID="ES80-AUTHENTICATED-STATIONARY-v1"', producer)
        self.assertIn('BUILD_LABEL="capture-v14-${SOURCE_SHA:0:12}"', producer)
        self.assertIn('requiredFieldProcedureIdentifier = "ES80-AUTHENTICATED-STATIONARY-v1"', identity)
        self.assertIn("capture-v14-", identity)

    def test_candidate_manifest_cannot_claim_install_or_physical_authority(self) -> None:
        producer = text("scripts/field/build_signed_capture_candidate.command")
        self.assertIn('"installationExecuted": False', producer)
        self.assertIn('"bluetoothExecuted": False', producer)
        self.assertIn('"physicalAuthorityCreated": False', producer)
        self.assertIn('"candidateKind": "signed-xcarchive"', producer)

    def test_installation_objective_remains_unimplemented_here(self) -> None:
        self.assertFalse((ROOT / "scripts/field/install_one_time_capture.command").exists())
        standalone = text(".github/workflows/capture-v16-standalone.yml")
        self.assertIn("test ! -e scripts/field/install_one_time_capture.command", standalone)


if __name__ == "__main__":
    unittest.main()
