#!/usr/bin/env python3
"""Adversarial regression for exact signed-IPA subject binding.

The signed-field inspector must never emit a digest for one IPA byte sequence after validating
code-signing/provisioning facts from a different byte sequence read through the same mutable path.
"""

from __future__ import annotations

import hashlib
import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "es80_signed_field_artifact_evidence.py"


def load_inspector():
    spec = importlib.util.spec_from_file_location("nembra_signed_field_exact_subject", SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load signed-field inspector")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class SignedFieldArtifactExactSubjectTests(unittest.TestCase):
    def test_digest_subject_and_extracted_subject_are_the_same_exact_bytes(self) -> None:
        inspector = load_inspector()
        source_sha = "a" * 40
        original_ipa = b"exact signed candidate bytes"
        transient_other_ipa = b"different bytes observed by inspection"

        with tempfile.TemporaryDirectory(prefix="nembra-exact-subject-test-") as temporary:
            root = Path(temporary)
            ipa_path = root / "candidate.ipa"
            ipa_path.write_bytes(original_ipa)

            app_path = root / "fake" / "Payload" / "Nembra.app"
            app_path.mkdir(parents=True)
            executable_path = app_path / "Nembra"
            executable_path.write_bytes(b"signed executable fixture")
            info_path = app_path / "Info.plist"
            info_path.write_bytes(b"signed info plist fixture")

            info = {
                "CFBundleIdentifier": inspector.BUNDLE_ID,
                "DTPlatformName": "iphoneos",
                "CFBundleSupportedPlatforms": ["iPhoneOS"],
                "NembraCaptureBuildIdentifier": inspector.expected_build_identifier(source_sha),
                "NembraCaptureBuildInstanceID": "12345678-1234-4abc-8def-1234567890ab",
                "NembraCaptureBuildCommitSHA": source_sha,
                "CFBundleExecutable": "Nembra",
            }

            real_sha256_file = inspector.sha256_file
            first_input_hash = True
            extracted_bytes: list[bytes] = []

            def racing_sha256_file(path: Path) -> str:
                nonlocal first_input_hash
                if path == ipa_path and first_input_hash:
                    first_input_hash = False
                    digest = hashlib.sha256(original_ipa).hexdigest()
                    path.write_bytes(transient_other_ipa)
                    return digest
                return real_sha256_file(path)

            def observing_extract(path: Path, destination: Path) -> Path:
                extracted_bytes.append(path.read_bytes())
                if path == ipa_path:
                    ipa_path.write_bytes(original_ipa)
                return app_path

            with (
                patch.object(inspector, "sha256_file", side_effect=racing_sha256_file),
                patch.object(inspector, "extract_ipa_safely", side_effect=observing_extract),
                patch.object(inspector, "reject_embedded_external_authority"),
                patch.object(inspector, "read_info_plist", return_value=(info, info_path)),
                patch.object(
                    inspector,
                    "verify_device_platform",
                    return_value=("iphoneos", ["iPhoneOS"]),
                ),
                patch.object(
                    inspector,
                    "run_codesign",
                    return_value=("ABCDE12345", ["Apple Development: Fixture"], "b" * 40),
                ),
                patch.object(
                    inspector,
                    "verify_provisioning_profile",
                    return_value=("c" * 64, "PROFILE-UUID", "2099-01-01T00:00:00Z", f"ABCDE12345.{inspector.BUNDLE_ID}"),
                ),
            ):
                inspection = inspector.inspect_ipa(
                    ipa_path,
                    source_sha,
                    intended_device_udid="00008101-001234567890001E",
                )

            self.assertEqual(
                inspection["field_build_record"]["signedInstallableSHA256"],
                hashlib.sha256(original_ipa).hexdigest(),
            )
            self.assertEqual(
                extracted_bytes,
                [original_ipa],
                "The code-signing/provisioning inspection must consume the same exact IPA bytes whose digest becomes field evidence.",
            )


if __name__ == "__main__":
    unittest.main()
