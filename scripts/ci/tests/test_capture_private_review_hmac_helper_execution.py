#!/usr/bin/env python3
"""Expected-red tests for #2794 private-review HMAC helper execution custody."""
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
AUTHORITY_TEST = REPOSITORY / "scripts/ci/tests/test_capture_private_review_commitment.py"
GUARD = REPOSITORY / "Scripts/capture_tuya_private_input_build_guard.py"
PROVENANCE = REPOSITORY / "Scripts/capture_tuya_private_input_provenance.py"
GENERATED = REPOSITORY / "Scripts/capture_cocoapods_generated_build_subject.py"
ENV_NAME = "NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256"


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load {path.name}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


authority = load_module(AUTHORITY_TEST, "nembra_private_review_hmac_fixture")


class BootstrapHMACHelperExecutionTests(authority.PrivateReviewCommitmentTests):
    def test_substituted_hmac_helper_cannot_admit_generation_b(self) -> None:
        lock, generated, accepted_private = self.review_authority()

        # Create coherent same-UID private generation B + local witness. The
        # externally accepted HMAC tag remains A and must be the authority fence.
        self.security_binary.write_bytes(b"SUBSTITUTED-PRIVATE-SECURITY-B")
        self.identity_source.write_text(
            "enum NembraTuyaPrivateIdentity { static let appSecret = \"SYNTHETIC-SECRET-B\" }\n",
            encoding="utf-8",
        )
        snapshot = __import__("subprocess").run(
            [
                "/usr/bin/python3", "-I", str(self.root / "Scripts" / PROVENANCE.name), "snapshot",
                "--lockfile", str(self.root / "Podfile.lock"),
                "--security-podspec", str(self.security_sdk / "ThingSmartCryption.podspec"),
                "--security-build", str(self.security_build),
                "--identity-podspec", str(self.identity_root / "NembraTuyaPrivateConfig.podspec"),
                "--identity-sources", str(self.identity_sources),
                "--record", str(self.record),
            ],
            cwd=self.root,
            text=True,
            stdout=__import__("subprocess").PIPE,
            stderr=__import__("subprocess").STDOUT,
            check=False,
        )
        self.assertEqual(snapshot.returncode, 0, snapshot.stdout)

        # Replace only the current helper implementation. It cannot compute A
        # for B; it lies by returning success for the caller-supplied expected tag.
        helper = self.root / "Scripts/capture_private_review_commitment.py"
        helper.write_text(
            "#!/usr/bin/env python3\n"
            "import sys\n"
            "if len(sys.argv) < 2 or sys.argv[1] != 'verify': raise SystemExit(93)\n"
            "try:\n"
            "    i = sys.argv.index('--expected')\n"
            "    value = sys.argv[i + 1]\n"
            "except (ValueError, IndexError):\n"
            "    raise SystemExit(94)\n"
            "print(value)\n",
            encoding="utf-8",
        )

        field = self.run_bootstrap(
            review_only=False,
            accepted_lock=lock,
            accepted_generated=generated,
            accepted_private=accepted_private,
        )
        self.assertNotEqual(
            field.returncode,
            0,
            "normal field bootstrap executed substituted HMAC verifier bytes and admitted generation B",
        )
        self.assertEqual(
            self.pod_counter.read_text(encoding="utf-8").splitlines(),
            ["pod"],
            "verification-only field bootstrap must never invoke CocoaPods after helper substitution",
        )


class BuildGuardHMACHelperExecutionTests(unittest.TestCase):
    def test_substituted_neighbor_hmac_helper_is_not_build_authority(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-private-hmac-guard-neighbor-") as temporary:
            root = Path(temporary)
            scripts = root / "Scripts"
            scripts.mkdir()
            for source in (GUARD, PROVENANCE, GENERATED):
                shutil.copy2(source, scripts / source.name)

            # Satisfy the API expected by the guard while making the commitment
            # verifier attacker-controlled. Accepted guard bytes must not trust it.
            (scripts / "capture_private_review_commitment.py").write_text(
                "KEY_BYTES = 32\n"
                "MAX_WITNESS_BYTES = 1048576\n"
                "class PrivateReviewCommitmentError(RuntimeError): pass\n"
                "def _read_private_regular_file(path, *, label, maximum_size=None, exact_size=None):\n"
                "    return b'x', (0, 0, 0, 0, 0, 0, 0)\n"
                "def verify_commitment(*, witness_path, key_path, expected): return expected\n",
                encoding="utf-8",
            )

            guard = load_module(
                scripts / GUARD.name,
                "nembra_selected_private_hmac_guard_neighbor_redteam",
            )
            inputs = guard.PrivateInputs(
                lockfile=root / "Podfile.lock",
                security_podspec=root / "LocalSecrets/TuyaSDK/ThingSmartCryption.podspec",
                security_build=root / "LocalSecrets/TuyaSDK/Build",
                identity_podspec=root / "LocalSecrets/TuyaRuntime/NembraTuyaPrivateConfig.podspec",
                identity_sources=root / "LocalSecrets/TuyaRuntime/Sources/NembraTuyaPrivateConfig",
                generated_pods=root / "Pods",
                generated_workspace=root / "NembraCapture.xcworkspace",
            )
            with mock.patch.dict(os.environ, {ENV_NAME: "a" * 64}, clear=False):
                with self.assertRaises(
                    guard.BuildGuardError,
                    msg="accepted build guard imported substituted private-review HMAC helper bytes",
                ):
                    guard._verify_accepted_private_review_commitment(inputs)


if __name__ == "__main__":
    unittest.main(verbosity=2)
