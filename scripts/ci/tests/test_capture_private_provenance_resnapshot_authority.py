#!/usr/bin/env python3
"""Expected-red contract for private Tuya provenance pre-bootstrap authority.

This test intentionally passes while the normal field bootstrap can overwrite the
private-input provenance record from field-owned ignored inputs without an
independently accepted fingerprint for those private inputs. A production repair
must make this diagnostic fail, then replace it with a positive authority gate.
"""

from __future__ import annotations

import hashlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[3]
INSTALLER = REPO / "scripts/field/install_one_time_capture.command"
BOOTSTRAP = REPO / "Scripts/bootstrap_capture_tuya_sdk.sh"
PROVENANCE = REPO / "Scripts/capture_tuya_private_input_provenance.py"


def _run_helper(mode: str, *, root: Path, record: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable,
            "-I",
            str(PROVENANCE),
            mode,
            "--lockfile",
            str(root / "Podfile.lock"),
            "--security-podspec",
            str(root / "TuyaSDK/ThingSmartCryption.podspec"),
            "--security-build",
            str(root / "TuyaSDK/Build"),
            "--identity-podspec",
            str(root / "TuyaRuntime/NembraTuyaPrivateConfig.podspec"),
            "--identity-sources",
            str(root / "TuyaRuntime/Sources/NembraTuyaPrivateConfig"),
            "--record",
            str(record),
        ],
        text=True,
        capture_output=True,
        check=False,
    )


class PrivateProvenanceResnapshotAuthorityRedTeamTests(unittest.TestCase):
    def test_current_field_path_resnapshots_before_verify(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")
        bootstrap = BOOTSTRAP.read_text(encoding="utf-8")

        bootstrap_call = '"$ROOT/Scripts/bootstrap_capture_tuya_sdk.sh"'
        verify_call = "verify_private_tuya_inputs"
        self.assertIn(bootstrap_call, installer)
        self.assertIn(verify_call, installer)
        self.assertLess(installer.index(bootstrap_call), installer.rindex(verify_call))

        self.assertIn("NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256", bootstrap)
        self.assertIn('"$PROVENANCE_HELPER" snapshot', bootstrap)
        self.assertIn('--record "$DEPENDENCY_PROVENANCE"', bootstrap)
        self.assertIn('[[ "$LOCK_SHA256" == "$ACCEPTED_LOCK_SHA256" ]]', bootstrap)

        # Current authority accepts the dependency lock digest, but the normal
        # bootstrap itself recreates the ignored private-input record. Keep this
        # lexical assertion narrow: a future repair should remove this exact
        # normal-mode resnapshot topology rather than merely rename a variable.
        snapshot_offset = bootstrap.index('"$PROVENANCE_HELPER" snapshot')
        lock_accept_offset = bootstrap.index('[[ "$LOCK_SHA256" == "$ACCEPTED_LOCK_SHA256" ]]')
        self.assertLess(snapshot_offset, lock_accept_offset)

    def test_fixed_lock_can_be_rebound_to_mutated_private_inputs(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-private-provenance-red-") as temp:
            root = Path(temp)
            sdk = root / "TuyaSDK"
            sdk_build = sdk / "Build"
            runtime = root / "TuyaRuntime"
            sources = runtime / "Sources/NembraTuyaPrivateConfig"
            sdk_build.mkdir(parents=True)
            sources.mkdir(parents=True)

            lock = root / "Podfile.lock"
            lock.write_text(
                "PODS:\n  - ThingSmartHomeKit (7.8.0)\n  - ThingSmartBusinessExtensionKit (7.8.0)\n",
                encoding="utf-8",
            )
            fixed_lock_sha = hashlib.sha256(lock.read_bytes()).hexdigest()

            (sdk / "ThingSmartCryption.podspec").write_text("security-podspec-v1\n", encoding="utf-8")
            (sdk_build / "libThingSmartCryption.a").write_bytes(b"security-build-A")
            (runtime / "NembraTuyaPrivateConfig.podspec").write_text("identity-podspec-v1\n", encoding="utf-8")
            identity = sources / "NembraTuyaPrivateIdentity.swift"
            identity.write_text('let appKey = "PRIVATE-A"\n', encoding="utf-8")
            record = runtime / "ResolvedTuyaDependencyProvenance.txt"

            first = _run_helper("snapshot", root=root, record=record)
            self.assertEqual(first.returncode, 0, first.stderr)
            record_a = record.read_bytes()

            # Change only an ignored private build input. The reviewed lock is
            # byte-identical, so a lock-only preacceptance remains satisfied.
            identity.write_text('let appKey = "PRIVATE-B"\n', encoding="utf-8")
            self.assertEqual(hashlib.sha256(lock.read_bytes()).hexdigest(), fixed_lock_sha)

            second = _run_helper("snapshot", root=root, record=record)
            self.assertEqual(second.returncode, 0, second.stderr)
            record_b = record.read_bytes()
            self.assertNotEqual(record_a, record_b)

            # The newly rewritten record now certifies the changed private input.
            # This is legitimate helper behavior in isolation, but is unsafe when
            # normal field bootstrap can do it after only the lock digest was
            # independently accepted.
            verify = _run_helper("verify", root=root, record=record)
            self.assertEqual(verify.returncode, 0, verify.stderr)
            self.assertIn("provenance matched", verify.stdout.lower())


if __name__ == "__main__":
    unittest.main(verbosity=2)
