#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import os
from pathlib import Path
import plistlib
import stat
import tempfile
import unittest
from unittest.mock import patch
import zipfile

INSPECTOR = Path(__file__).resolve().parents[1] / "es80_signed_field_artifact_evidence.py"


def load_inspector():
    spec = importlib.util.spec_from_file_location("nembra_es80_signed_field_artifact_evidence", INSPECTOR)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load signed-field artifact inspector")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def make_ipa(path: Path, *, source_sha: str, executable_bytes: bytes) -> None:
    info = {
        "CFBundleIdentifier": "com.jonathangana131.nembra",
        "CFBundleExecutable": "Nembra",
        "CFBundleSupportedPlatforms": ["iPhoneOS"],
        "DTPlatformName": "iphoneos",
        "NembraCaptureBuildIdentifier": f"Capture Build V14-{source_sha[:12]}",
        "NembraCaptureBuildInstanceID": "12345678-1234-4abc-8def-1234567890ab",
        "NembraCaptureBuildCommitSHA": source_sha,
    }
    entries = {
        "Payload/Nembra.app/Info.plist": plistlib.dumps(info, fmt=plistlib.FMT_BINARY),
        "Payload/Nembra.app/Nembra": executable_bytes,
    }
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_STORED) as archive:
        for name, contents in entries.items():
            entry = zipfile.ZipInfo(name)
            permissions = 0o755 if name.endswith("/Nembra") else 0o644
            entry.external_attr = (stat.S_IFREG | permissions) << 16
            archive.writestr(entry, contents)


class SignedFieldArtifactPostInspectionMutationTests(unittest.TestCase):
    def test_private_snapshot_mutate_restore_cannot_mix_installable_and_executable_evidence(self):
        inspector = load_inspector()
        source_sha = "a" * 40

        with tempfile.TemporaryDirectory(prefix="nembra-field-post-inspection-mutation-") as temporary:
            root = Path(temporary)
            original = root / "original.ipa"
            transient = root / "transient.ipa"
            make_ipa(original, source_sha=source_sha, executable_bytes=b"ORIGINAL-EXECUTABLE")
            make_ipa(transient, source_sha=source_sha, executable_bytes=b"TRANSIENT-EXECUTABL")
            self.assertEqual(original.stat().st_size, transient.stat().st_size)

            original_bytes = original.read_bytes()
            transient_bytes = transient.read_bytes()
            original_ipa_sha = hashlib.sha256(original_bytes).hexdigest()
            transient_executable_sha = hashlib.sha256(b"TRANSIENT-EXECUTABL").hexdigest()

            real_extract = inspector.extract_ipa_safely
            mutation_seen = False

            def mutate_extract_restore(ipa_path: Path, destination: Path) -> Path:
                nonlocal mutation_seen
                mutation_seen = True
                ipa_path.chmod(0o600)
                try:
                    ipa_path.write_bytes(transient_bytes)
                    extracted = real_extract(ipa_path, destination)
                    ipa_path.write_bytes(original_bytes)
                    os.utime(ipa_path, None)
                finally:
                    ipa_path.chmod(0o400)
                return extracted

            with (
                patch.object(inspector, "extract_ipa_safely", side_effect=mutate_extract_restore),
                patch.object(
                    inspector,
                    "run_codesign",
                    return_value=("ABCDE12345", ["Nembra test authority"], "b" * 40),
                ),
                patch.object(
                    inspector,
                    "verify_provisioning_profile",
                    return_value=("c" * 64, "PROFILE-UUID", "2099-01-01T00:00:00Z", "ABCDE12345.com.jonathangana131.nembra"),
                ),
            ):
                with self.assertRaisesRegex(
                    inspector.EvidenceError,
                    "changed during signing/provisioning inspection",
                ):
                    inspector.inspect_ipa(
                        original,
                        source_sha,
                        intended_device_udid="00008101-001234567890001E",
                    )

            self.assertTrue(mutation_seen)
            # Sanity: without the required fail-closed check, the old implementation can combine
            # original installable identity with executable facts extracted from transient bytes.
            self.assertNotEqual(original_ipa_sha, hashlib.sha256(transient_bytes).hexdigest())
            self.assertNotEqual(transient_executable_sha, hashlib.sha256(b"ORIGINAL-EXECUTABLE").hexdigest())


if __name__ == "__main__":
    unittest.main()
