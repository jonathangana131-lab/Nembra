#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import stat
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
HELPER = REPOSITORY_ROOT / "Scripts" / "capture_tuya_private_input_provenance.py"
SPEC = importlib.util.spec_from_file_location("capture_tuya_private_input_provenance", HELPER)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load private-input provenance helper")
provenance = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(provenance)


class PrivateInputProvenanceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="nembra-private-provenance-")
        self.root = Path(self.temporary.name)
        self.sdk = self.root / "TuyaSDK"
        self.security_build = self.sdk / "Build"
        self.identity = self.root / "TuyaRuntime"
        self.identity_sources = self.identity / "Sources" / "NembraTuyaPrivateConfig"
        self.security_build.mkdir(parents=True)
        self.identity_sources.mkdir(parents=True)
        self.lockfile = self.root / "Podfile.lock"
        self.security_podspec = self.sdk / "ThingSmartCryption.podspec"
        self.identity_podspec = self.identity / "NembraTuyaPrivateConfig.podspec"
        self.record = self.identity / "ResolvedTuyaDependencyProvenance.txt"
        self.review_key = self.identity / "PrivateInputReviewKey.bin"

        self.lockfile.write_text(
            "  - ThingSmartHomeKit (7.8.0)\n"
            "  - ThingSmartBusinessExtensionKit (7.8.0)\n",
            encoding="utf-8",
        )
        self.security_podspec.write_text("security-spec", encoding="utf-8")
        (self.security_build / "ThingSmartCryption.bin").write_bytes(b"sdk-private-bytes")
        self.identity_podspec.write_text("private-identity-spec", encoding="utf-8")
        (self.identity_sources / "NembraTuyaPrivateIdentity.swift").write_text(
            'private let encodedAppKey = "DO-NOT-SERIALIZE"\n',
            encoding="utf-8",
        )

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def current(self) -> dict[str, str]:
        return provenance.build_record(
            lockfile=self.lockfile,
            security_podspec=self.security_podspec,
            security_build=self.security_build,
            identity_podspec=self.identity_podspec,
            identity_sources=self.identity_sources,
        )

    def test_snapshot_is_private_fingerprints_only_and_verifies(self) -> None:
        current = self.current()
        provenance.write_record(self.record, current)
        provenance.verify_record(self.record, self.current())

        text = self.record.read_text(encoding="utf-8")
        self.assertIn("schema=nembra-capture-tuya-dependencies-v2", text)
        self.assertIn("podfile_lock_sha256=", text)
        self.assertIn("private_identity_sources_tree_sha256=", text)
        self.assertNotIn("DO-NOT-SERIALIZE", text)
        self.assertEqual(stat.S_IMODE(self.record.stat().st_mode), 0o600)

    def test_opaque_review_commitment_verifies_same_generation(self) -> None:
        current = self.current()
        commitment = provenance.create_private_review(
            record_path=self.record,
            key_path=self.review_key,
            current=current,
        )
        self.assertRegex(commitment, r"^[0-9a-f]{64}$")
        self.assertEqual(stat.S_IMODE(self.review_key.stat().st_mode), 0o600)
        self.assertEqual(self.review_key.stat().st_size, provenance.PRIVATE_REVIEW_KEY_BYTES)
        self.assertNotIn("DO-NOT-SERIALIZE", commitment)

        provenance.verify_private_review(
            record_path=self.record,
            key_path=self.review_key,
            current=self.current(),
            accepted_commitment=commitment,
        )

    def test_replacing_private_generation_and_local_witness_cannot_match_accepted_commitment(self) -> None:
        accepted = provenance.create_private_review(
            record_path=self.record,
            key_path=self.review_key,
            current=self.current(),
        )

        # Simulate same-user replacement of the entire local private generation.
        (self.security_build / "ThingSmartCryption.bin").write_bytes(b"replacement-sdk")
        (self.identity_sources / "NembraTuyaPrivateIdentity.swift").write_text(
            'private let encodedAppKey = "REPLACEMENT"\n',
            encoding="utf-8",
        )
        replacement = self.current()

        # The attacker can replace the local record and local random key too.
        replacement_commitment = provenance.create_private_review(
            record_path=self.record,
            key_path=self.review_key,
            current=replacement,
        )
        self.assertNotEqual(replacement_commitment, accepted)
        with self.assertRaisesRegex(provenance.ProvenanceError, "externally accepted review commitment"):
            provenance.verify_private_review(
                record_path=self.record,
                key_path=self.review_key,
                current=replacement,
                accepted_commitment=accepted,
            )

    def test_tampered_review_key_is_rejected(self) -> None:
        accepted = provenance.create_private_review(
            record_path=self.record,
            key_path=self.review_key,
            current=self.current(),
        )
        self.review_key.write_bytes(b"x" * provenance.PRIVATE_REVIEW_KEY_BYTES)
        self.review_key.chmod(0o600)
        with self.assertRaisesRegex(provenance.ProvenanceError, "externally accepted review commitment"):
            provenance.verify_private_review(
                record_path=self.record,
                key_path=self.review_key,
                current=self.current(),
                accepted_commitment=accepted,
            )

    def test_review_key_permissions_fail_closed(self) -> None:
        accepted = provenance.create_private_review(
            record_path=self.record,
            key_path=self.review_key,
            current=self.current(),
        )
        self.review_key.chmod(0o644)
        with self.assertRaisesRegex(provenance.ProvenanceError, "mode 0600"):
            provenance.verify_private_review(
                record_path=self.record,
                key_path=self.review_key,
                current=self.current(),
                accepted_commitment=accepted,
            )

    def test_any_private_input_drift_fails_closed(self) -> None:
        provenance.write_record(self.record, self.current())
        (self.security_build / "ThingSmartCryption.bin").write_bytes(b"changed-sdk-bytes")
        with self.assertRaises(provenance.ProvenanceError):
            provenance.verify_record(self.record, self.current())

    def test_symlinked_private_input_is_rejected(self) -> None:
        target = self.root / "real-spec"
        target.write_text("real", encoding="utf-8")
        self.security_podspec.unlink()
        self.security_podspec.symlink_to(target)
        with self.assertRaises(provenance.ProvenanceError):
            self.current()

    def test_unreviewed_public_dependency_version_is_rejected(self) -> None:
        self.lockfile.write_text("  - ThingSmartHomeKit (7.8.1)\n", encoding="utf-8")
        with self.assertRaises(provenance.ProvenanceError):
            self.current()


if __name__ == "__main__":
    unittest.main()
