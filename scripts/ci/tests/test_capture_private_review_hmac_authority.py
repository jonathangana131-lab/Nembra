#!/usr/bin/env python3
"""Regression for external secret-safe private Tuya review authority."""
from __future__ import annotations

import hashlib
import importlib.util
from pathlib import Path
import subprocess
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
BASE_TEST = REPOSITORY / "scripts/ci/tests/test_capture_private_input_review_witness.py"
PROVENANCE = REPOSITORY / "Scripts/capture_tuya_private_input_provenance.py"
COMMITMENT = REPOSITORY / "Scripts/capture_tuya_private_review_commitment.py"


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load {path.name}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


BASE = load_module(BASE_TEST, "capture_private_review_hmac_fixture")
COMMIT = load_module(COMMITMENT, "capture_private_review_commitment_under_test")


class PrivateReviewHMACAuthorityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.fixture = BASE.PrivateInputReviewWitnessTests(
            "test_normal_field_mode_rejects_substitution_before_cocoapods_and_preserves_witness"
        )
        self.fixture.setUp()

    def tearDown(self) -> None:
        self.fixture.tearDown()

    def snapshot_current_private_generation(self) -> subprocess.CompletedProcess[str]:
        fixture = self.fixture
        return subprocess.run(
            [
                "/usr/bin/python3",
                "-I",
                str(PROVENANCE),
                "snapshot",
                "--lockfile",
                str(fixture.root / "Podfile.lock"),
                "--security-podspec",
                str(fixture.security_sdk / "ThingSmartCryption.podspec"),
                "--security-build",
                str(fixture.security_build),
                "--identity-podspec",
                str(fixture.identity_root / "NembraTuyaPrivateConfig.podspec"),
                "--identity-sources",
                str(fixture.identity_sources),
                "--record",
                str(fixture.record),
            ],
            cwd=fixture.root,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )

    def current_commitment(self) -> str:
        fixture = self.fixture
        return COMMIT.commitment(
            key_file=fixture.private_review_key,
            lockfile=fixture.root / "Podfile.lock",
            security_podspec=fixture.security_sdk / "ThingSmartCryption.podspec",
            security_build=fixture.security_build,
            identity_podspec=fixture.identity_root / "NembraTuyaPrivateConfig.podspec",
            identity_sources=fixture.identity_sources,
        )

    def test_private_generation_plus_local_witness_replacement_is_rejected_by_external_hmac(self) -> None:
        fixture = self.fixture
        review = fixture.run_bootstrap(review_only=True)
        self.assertEqual(review.returncode, 0, review.stdout)
        reviewed_record = fixture.record.read_bytes()
        reviewed_lock = (fixture.root / "Podfile.lock").read_bytes()
        accepted_lock = hashlib.sha256(reviewed_lock).hexdigest()
        accepted_generated = fixture.digest_from_review(
            review.stdout, "CocoaPods generated build subject SHA-256"
        )
        accepted_private_hmac = fixture.digest_from_review(
            review.stdout, "Private Tuya review HMAC SHA-256"
        )
        self.assertEqual(accepted_private_hmac, self.current_commitment())
        self.assertEqual(fixture.pod_counter.read_text(encoding="utf-8").splitlines(), ["pod"])

        fixture.security_binary.write_bytes(b"SUBSTITUTED-PRIVATE-SECURITY-B")
        fixture.identity_source.write_text(
            "enum NembraTuyaPrivateIdentity { static let generation = \"SUBSTITUTED-B\" }\n",
            encoding="utf-8",
        )
        attacker_snapshot = self.snapshot_current_private_generation()
        self.assertEqual(attacker_snapshot.returncode, 0, attacker_snapshot.stdout)
        self.assertNotEqual(
            fixture.record.read_bytes(),
            reviewed_record,
            "diagnostic did not replace the mutable local witness with generation B",
        )
        self.assertNotEqual(
            self.current_commitment(),
            accepted_private_hmac,
            "private generation B unexpectedly retained review HMAC A",
        )

        field = fixture.run_bootstrap(
            review_only=False,
            accepted_lock=accepted_lock,
            accepted_generated=accepted_generated,
            accepted_private_hmac=accepted_private_hmac,
        )
        self.assertNotEqual(field.returncode, 0, field.stdout)
        self.assertIn("externally accepted private review HMAC", field.stdout)
        self.assertEqual(
            fixture.pod_counter.read_text(encoding="utf-8").splitlines(),
            ["pod"],
            "coherent private+witness substitution reached a second CocoaPods execution",
        )
        self.assertEqual(
            (fixture.root / "Podfile.lock").read_bytes(),
            reviewed_lock,
            "external private-authority rejection changed the accepted public lock",
        )

    def test_replacing_private_key_cannot_rebind_an_already_accepted_hmac(self) -> None:
        fixture = self.fixture
        review = fixture.run_bootstrap(review_only=True)
        self.assertEqual(review.returncode, 0, review.stdout)
        accepted_lock = hashlib.sha256((fixture.root / "Podfile.lock").read_bytes()).hexdigest()
        accepted_generated = fixture.digest_from_review(
            review.stdout, "CocoaPods generated build subject SHA-256"
        )
        accepted_private_hmac = fixture.digest_from_review(
            review.stdout, "Private Tuya review HMAC SHA-256"
        )

        fixture.private_review_key.write_bytes(bytes(reversed(range(32))))
        fixture.private_review_key.chmod(0o600)
        self.assertNotEqual(self.current_commitment(), accepted_private_hmac)

        field = fixture.run_bootstrap(
            review_only=False,
            accepted_lock=accepted_lock,
            accepted_generated=accepted_generated,
            accepted_private_hmac=accepted_private_hmac,
        )
        self.assertNotEqual(field.returncode, 0, field.stdout)
        self.assertIn("externally accepted private review HMAC", field.stdout)
        self.assertEqual(fixture.pod_counter.read_text(encoding="utf-8").splitlines(), ["pod"])

    def test_key_path_symlink_is_rejected_before_commitment(self) -> None:
        fixture = self.fixture
        real_key = fixture.identity_root / "real-review.key"
        real_key.write_bytes(bytes(range(32)))
        real_key.chmod(0o600)
        fixture.private_review_key.unlink()
        fixture.private_review_key.symlink_to(real_key.name)

        with self.assertRaisesRegex(COMMIT.CommitmentError, "symlink"):
            self.current_commitment()


if __name__ == "__main__":
    unittest.main(verbosity=2)
