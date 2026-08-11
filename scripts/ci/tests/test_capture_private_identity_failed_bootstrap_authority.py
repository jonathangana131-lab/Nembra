#!/usr/bin/env python3
"""A failed private publication must never become later CocoaPods build input.

This is the accepted counterpart to expected-red #2961. It exercises the real
private writer, leaves attacker-controlled Swift bytes at the canonical identity
path after fail-closed publication, then invokes the real bootstrap from a
fixture containing the accepted authority verifier. CocoaPods must remain
unreached because no root-sealed successful transaction exists for the fixture.
"""

from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
WRITER_PATH = ROOT / "Scripts/provision_capture_tuya_identity_writer.py"
BOOTSTRAP_PATH = ROOT / "Scripts/bootstrap_capture_tuya_sdk.sh"
AUTHORITY_PATH = ROOT / "Scripts/capture_tuya_private_identity_authority.py"
PROVENANCE_PATH = ROOT / "Scripts/capture_tuya_private_input_provenance.py"


def load_writer():
    spec = importlib.util.spec_from_file_location("nembra_failed_bootstrap_writer", WRITER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("private identity writer import unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class FailedPrivateIdentityBootstrapAuthorityTests(unittest.TestCase):
    def test_failed_publication_attacker_source_is_blocked_before_pod(self) -> None:
        writer = load_writer()
        with tempfile.TemporaryDirectory(prefix="nembra-private-failed-bootstrap-") as temporary:
            repo = Path(temporary) / "repo"
            scripts = repo / "Scripts"
            scripts.mkdir(parents=True, mode=0o700)
            for source in (BOOTSTRAP_PATH, AUTHORITY_PATH, PROVENANCE_PATH, WRITER_PATH):
                shutil.copy2(source, scripts / source.name)

            (repo / "Podfile").write_text("# sentinel Podfile\n", encoding="utf-8")
            (repo / "NembraCapture.xcodeproj").mkdir()

            checkout_fd = os.open(repo, writer._directory_flags())
            original_secure_replace = writer._secure_replace_beneath
            attacker_bytes = (
                b"import Foundation\n"
                b"public enum NembraTuyaPrivateIdentity {\n"
                b"  public static let appKey = \"attacker-key\"\n"
                b"  public static let appSecret = \"attacker-secret\"\n"
                b"}\n"
            )
            attacked = False

            def fail_second_publication(root_fd: int, source_name: str, destination_relative: str, sealed) -> None:
                nonlocal attacked
                if destination_relative.endswith("NembraTuyaPrivateIdentity.swift"):
                    attacked = True
                    os.rename(
                        source_name,
                        f"{source_name}.accepted-held",
                        src_dir_fd=root_fd,
                        dst_dir_fd=root_fd,
                    )
                    parent = repo / "LocalSecrets/TuyaRuntime/Sources/NembraTuyaPrivateConfig"
                    canonical = parent / "NembraTuyaPrivateIdentity.swift"
                    canonical.write_bytes(attacker_bytes)
                    canonical.chmod(0o600)
                original_secure_replace(root_fd, source_name, destination_relative, sealed)

            writer._secure_replace_beneath = fail_second_publication
            try:
                with self.assertRaises((writer.ProvisionError, OSError)):
                    writer.provision(
                        checkout_fd,
                        repo,
                        "bmVtYnJhLWR1bW15LWFwcC1rZXk=",
                        "bmVtYnJhLWR1bW15LWFwcC1zZWNyZXQ=",
                    )
            finally:
                writer._secure_replace_beneath = original_secure_replace
                os.close(checkout_fd)

            self.assertTrue(attacked, "fixture never injected the failed second publication")
            canonical = repo / "LocalSecrets/TuyaRuntime/Sources/NembraTuyaPrivateConfig/NembraTuyaPrivateIdentity.swift"
            self.assertEqual(canonical.read_bytes(), attacker_bytes)

            fake_bin = Path(temporary) / "bin"
            fake_bin.mkdir()
            sentinel = Path(temporary) / "pod-invoked"
            fake_pod = fake_bin / "pod"
            fake_pod.write_text(
                "#!/bin/sh\n/bin/echo invoked > \"$NEMBRA_POD_SENTINEL\"\nexit 86\n",
                encoding="utf-8",
            )
            fake_pod.chmod(0o700)

            environment = os.environ.copy()
            environment["PATH"] = f"{fake_bin}:{environment.get('PATH', '')}"
            environment["NEMBRA_POD_SENTINEL"] = str(sentinel)
            environment["NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256"] = "a" * 64
            result = subprocess.run(
                ["/bin/bash", str(scripts / "bootstrap_capture_tuya_sdk.sh")],
                cwd=repo,
                env=environment,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                timeout=20,
                check=False,
            )

            self.assertEqual(result.returncode, 17, result.stdout)
            self.assertFalse(sentinel.exists(), "bootstrap reached CocoaPods with failed-publication identity bytes")
            self.assertIn("root-sealed last successful provisioning transaction", result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
