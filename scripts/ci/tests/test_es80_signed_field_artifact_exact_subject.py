#!/usr/bin/env python3
"""Adversarial regressions for exact signed-IPA subject binding."""

from __future__ import annotations

import hashlib
import importlib.util
import io
import os
import tempfile
import unittest
import zipfile
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


def make_minimal_ipa(marker: bytes) -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        archive.writestr("Payload/Nembra.app/marker.bin", marker)
    return buffer.getvalue()


class SignedFieldArtifactExactSubjectTests(unittest.TestCase):
    def test_field_evidence_digest_is_owned_by_descriptor_bound_extractor(self) -> None:
        inspector = load_inspector()
        source_sha = "a" * 40
        original_ipa = b"exact signed candidate bytes"

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
            observed_identities = []

            def observing_extract(path: Path, destination: Path, *, expected_identity):
                observed_identities.append(expected_identity)
                return app_path, hashlib.sha256(original_ipa).hexdigest(), len(original_ipa)

            with (
                patch.object(inspector, "extract_ipa_safely", side_effect=observing_extract),
                patch.object(inspector, "reject_embedded_external_authority"),
                patch.object(inspector, "read_info_plist", return_value=(info, info_path)),
                patch.object(inspector, "verify_device_platform", return_value=("iphoneos", ["iPhoneOS"])),
                patch.object(inspector, "run_codesign", return_value=("ABCDE12345", ["Apple Development: Fixture"], "b" * 40)),
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
            self.assertEqual(len(observed_identities), 1)

    def test_path_replacement_before_descriptor_open_fails_closed(self) -> None:
        inspector = load_inspector()
        original_ipa = make_minimal_ipa(b"original")
        replacement_ipa = make_minimal_ipa(b"replacement")
        with tempfile.TemporaryDirectory(prefix="nembra-preopen-swap-test-") as temporary:
            root = Path(temporary)
            subject = root / "NembraField.ipa"
            held = root / "held.ipa"
            subject.write_bytes(original_ipa)
            subject.chmod(0o400)
            expected_identity = inspector._stable_file_identity(subject.lstat())
            subject.rename(held)
            subject.write_bytes(replacement_ipa)
            with self.assertRaisesRegex(inspector.EvidenceError, "changed before descriptor-bound extraction"):
                inspector.extract_ipa_safely(
                    subject,
                    root / "extract",
                    expected_identity=expected_identity,
                )

    def test_path_replacement_after_open_never_steers_extraction(self) -> None:
        inspector = load_inspector()
        original_ipa = make_minimal_ipa(b"original exact subject")
        replacement_ipa = make_minimal_ipa(b"replacement pathname subject")
        with tempfile.TemporaryDirectory(prefix="nembra-postopen-swap-test-") as temporary:
            root = Path(temporary)
            subject = root / "NembraField.ipa"
            held = root / "held.ipa"
            extraction = root / "extract"
            subject.write_bytes(original_ipa)
            subject.chmod(0o400)
            expected_identity = inspector._stable_file_identity(subject.lstat())
            real_fdopen = os.fdopen
            replaced = False

            def replace_path_then_fdopen(descriptor: int, *args, **kwargs):
                nonlocal replaced
                if not replaced:
                    replaced = True
                    subject.rename(held)
                    subject.write_bytes(replacement_ipa)
                return real_fdopen(descriptor, *args, **kwargs)

            try:
                with patch.object(inspector.os, "fdopen", side_effect=replace_path_then_fdopen):
                    inspector.extract_ipa_safely(
                        subject,
                        extraction,
                        expected_identity=expected_identity,
                    )
            except inspector.EvidenceError as error:
                self.assertIn("changed during descriptor-bound extraction", str(error))

            self.assertTrue(replaced)
            self.assertEqual(
                (extraction / "Payload" / "Nembra.app" / "marker.bin").read_bytes(),
                b"original exact subject",
            )
            self.assertEqual(subject.read_bytes(), replacement_ipa)

    def test_in_place_mutation_during_extraction_fails_closed(self) -> None:
        inspector = load_inspector()
        original_ipa = make_minimal_ipa(b"original exact subject")
        with tempfile.TemporaryDirectory(prefix="nembra-in-place-mutation-test-") as temporary:
            root = Path(temporary)
            subject = root / "NembraField.ipa"
            subject.write_bytes(original_ipa)
            subject.chmod(0o400)
            expected_identity = inspector._stable_file_identity(subject.lstat())
            real_copy = inspector.shutil.copyfileobj
            mutated = False

            def mutate_after_copy(source, sink, *args, **kwargs):
                nonlocal mutated
                result = real_copy(source, sink, *args, **kwargs)
                if not mutated:
                    mutated = True
                    subject.chmod(0o600)
                    with subject.open("ab") as handle:
                        handle.write(b"mutation")
                return result

            with patch.object(inspector.shutil, "copyfileobj", side_effect=mutate_after_copy):
                with self.assertRaisesRegex(inspector.EvidenceError, "changed during descriptor-bound extraction"):
                    inspector.extract_ipa_safely(
                        subject,
                        root / "extract",
                        expected_identity=expected_identity,
                    )


if __name__ == "__main__":
    unittest.main()
