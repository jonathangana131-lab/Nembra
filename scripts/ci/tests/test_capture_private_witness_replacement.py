#!/usr/bin/env python3
"""Expected-red: a mutable local provenance record cannot be review authority."""
from __future__ import annotations

import hashlib
import importlib.util
from pathlib import Path
import subprocess
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
BASE_TEST = REPOSITORY / "scripts/ci/tests/test_capture_private_input_review_witness.py"
PROVENANCE = REPOSITORY / "Scripts/capture_tuya_private_input_provenance.py"


def load_base_test():
    spec = importlib.util.spec_from_file_location("capture_private_review_witness_fixture", BASE_TEST)
    if spec is None or spec.loader is None:
        raise RuntimeError("review-witness fixture could not be loaded")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


BASE = load_base_test()


class PrivateWitnessReplacementTests(unittest.TestCase):
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

    def test_private_generation_plus_local_witness_replacement_cannot_self_authorize(self) -> None:
        fixture = self.fixture
        review = fixture.run_bootstrap(review_only=True)
        self.assertEqual(review.returncode, 0, review.stdout)
        reviewed_record = fixture.record.read_bytes()
        accepted_lock = hashlib.sha256((fixture.root / "Podfile.lock").read_bytes()).hexdigest()
        accepted_generated = fixture.digest_from_review(
            review.stdout, "CocoaPods generated build subject SHA-256"
        )
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
            "diagnostic did not replace the local private witness",
        )

        field = fixture.run_bootstrap(
            review_only=False,
            accepted_lock=accepted_lock,
            accepted_generated=accepted_generated,
        )

        self.assertNotEqual(
            field.returncode,
            0,
            "field bootstrap accepted substituted private generation B after its mutable local witness was replaced; "
            "the 0600 provenance record is continuity evidence, not external review authority",
        )
        self.assertEqual(
            fixture.pod_counter.read_text(encoding="utf-8").splitlines(),
            ["pod"],
            "rejection must occur before any second CocoaPods execution",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
