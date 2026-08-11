#!/usr/bin/env python3
"""Expected-red tests for mutable opaque-commitment helper execution subjects."""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest import mock

REPOSITORY = Path(__file__).resolve().parents[3]
AUTHORITY_TEST = REPOSITORY / "scripts/ci/tests/test_capture_private_review_commitment_authority.py"
GUARD = REPOSITORY / "Scripts/capture_tuya_private_input_build_guard.py"
PROVENANCE = REPOSITORY / "Scripts/capture_tuya_private_input_provenance.py"
GENERATED = REPOSITORY / "Scripts/capture_cocoapods_generated_build_subject.py"
ENV_NAME = "NEMBRA_CAPTURE_ACCEPTED_TUYA_PRIVATE_REVIEW_HMAC_SHA256"


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load {path.name}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


authority = load_module(AUTHORITY_TEST, "nembra_private_commitment_authority_fixture")


class BootstrapCommitmentHelperExecutionTests(authority.PrivateReviewAuthorityTests):
    def test_substituted_commitment_helper_cannot_admit_generation_b(self) -> None:
        review = self.run_bootstrap(review=True)
        self.assertEqual(review.returncode, 0, review.stdout)
        lock_a = self.subject(review.stdout, "Podfile.lock SHA-256")
        generated_a = self.subject(review.stdout, "CocoaPods generated build subject SHA-256")
        tag_a = self.subject(review.stdout, "Private-input review HMAC-SHA256")

        self.security_binary.write_bytes(b"PRIVATE-SECURITY-B")
        self.identity_source.write_text(
            "enum PrivateIdentity { static let generation = \"B\" }\n",
            encoding="utf-8",
        )
        self.snapshot_private()

        helper = self.root / "Scripts/capture_tuya_private_review_commitment.py"
        helper.write_text(
            "#!/usr/bin/env python3\n"
            "import sys\n"
            "if len(sys.argv) < 2 or sys.argv[1] != 'verify': raise SystemExit(93)\n"
            "try:\n"
            "    i = sys.argv.index('--accepted-tag')\n"
            "    value = sys.argv[i + 1]\n"
            "except (ValueError, IndexError):\n"
            "    raise SystemExit(94)\n"
            "print(value)\n",
            encoding="utf-8",
        )

        field = self.run_bootstrap(
            review=False,
            lock=lock_a,
            generated=generated_a,
            private_tag=tag_a,
        )
        self.assertNotEqual(
            field.returncode,
            0,
            "normal field bootstrap executed a same-UID substituted HMAC verifier and admitted unreviewed private generation B",
        )


class BuildGuardCommitmentHelperExecutionTests(unittest.TestCase):
    def test_substituted_neighbor_commitment_helper_is_not_build_authority(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-private-commitment-guard-neighbor-") as temporary:
            root = Path(temporary)
            scripts = root / "Scripts"
            scripts.mkdir()
            for source in (GUARD, PROVENANCE, GENERATED):
                shutil.copy2(source, scripts / source.name)

            (scripts / "capture_tuya_private_review_commitment.py").write_text(
                "MAX_WITNESS_BYTES = 1048576\n"
                "KEY_BYTES = 32\n"
                "class PrivateReviewCommitmentError(RuntimeError): pass\n"
                "def _read_private_regular_file(path, *, label, maximum_size=None, exact_size=None):\n"
                "    return b'x', (0, 0, 0, 0, 0, 0, 0)\n"
                "def verify_commitment(*, witness, key_file, repository_root, accepted_tag):\n"
                "    return accepted_tag\n",
                encoding="utf-8",
            )

            guard = load_module(
                scripts / GUARD.name,
                "nembra_private_commitment_guard_neighbor_redteam",
            )
            inputs = guard.PrivateInputs(
                lockfile=root / "Podfile.lock",
                security_podspec=root / "LocalSecrets/TuyaSDK/ThingSmartCryption.podspec",
                security_build=root / "LocalSecrets/TuyaSDK/Build",
                identity_podspec=root / "LocalSecrets/TuyaRuntime/NembraTuyaPrivateConfig.podspec",
                identity_sources=root / "LocalSecrets/TuyaRuntime/Sources/NembraTuyaPrivateConfig",
                private_provenance=root / "LocalSecrets/TuyaRuntime/ResolvedTuyaDependencyProvenance.txt",
                private_review_key=root / "LocalSecrets/TuyaRuntime/ResolvedTuyaDependencyReview.key",
            )
            with mock.patch.dict(os.environ, {ENV_NAME: "a" * 64}, clear=False):
                with self.assertRaises(
                    guard.BuildGuardError,
                    msg="build guard imported a same-UID substituted HMAC helper as accepted authority",
                ):
                    guard._verify_accepted_private_review_commitment(inputs)


if __name__ == "__main__":
    unittest.main(verbosity=2)
