#!/usr/bin/env python3
"""Expected-red: a failed private-identity publication must not become later build input.

The current #2944 failure policy correctly refuses to delete/mutate an inode that
cannot be proven to be the writer's held staging inode. This diagnostic attacks
the post-name-check publication window for the generated Swift identity source,
then asks whether the normal bootstrap can proceed far enough to invoke
CocoaPods with that attacker-controlled Swift still at the canonical
LocalSecrets/TuyaRuntime identity path.

A safe lineage must fail the bootstrap before CocoaPods admission until fresh
successful provisioning has mechanically re-established private identity
authority. This diagnostic never builds, installs, launches, scans Bluetooth, or
touches physical hardware.
"""

from __future__ import annotations

import base64
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
WRITER_PATH = REPOSITORY / "Scripts" / "provision_capture_tuya_identity_writer.py"
BOOTSTRAP_PATH = REPOSITORY / "Scripts" / "bootstrap_capture_tuya_sdk.sh"


def load_writer():
    spec = importlib.util.spec_from_file_location(
        "nembra_private_identity_failed_bootstrap_redteam", WRITER_PATH
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("private identity writer import unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_all(descriptor: int, payload: bytes) -> None:
    view = memoryview(payload)
    offset = 0
    while offset < len(view):
        written = os.write(descriptor, view[offset:])
        if written <= 0:
            raise RuntimeError("could not write complete adversarial fixture")
        offset += written
    os.fsync(descriptor)


class PrivateIdentityFailedBootstrapAdmissionTests(unittest.TestCase):
    def test_failed_identity_source_publication_cannot_reach_cocoapods_on_later_bootstrap(self) -> None:
        writer = load_writer()
        app_key = base64.b64encode(b"accepted-dummy-key").decode("ascii")
        app_secret = base64.b64encode(b"accepted-dummy-secret").decode("ascii")
        attacker_source = b"""import Foundation\n\npublic enum NembraTuyaPrivateIdentity {\n    public static let appKey = \"attacker-key\"\n    public static let appSecret = \"attacker-secret\"\n}\n"""

        with tempfile.TemporaryDirectory(prefix="nembra-private-failed-bootstrap-") as temporary:
            sandbox = Path(temporary)
            checkout = sandbox / "repo"
            checkout.mkdir(mode=0o700)
            checkout_fd = os.open(checkout, writer._directory_flags())
            original_require = writer._require_sealed_staging_name
            require_calls = 0
            attacked = False

            def adversarial_require(root_fd: int, source_name: str, sealed) -> None:
                nonlocal require_calls, attacked
                original_require(root_fd, source_name, sealed)
                require_calls += 1
                # provision() writes the podspec first and the build-visible Swift
                # identity second. Attack only the Swift publication boundary.
                if require_calls != 2:
                    return
                attacked = True
                stolen_name = f"{source_name}.sealed-owner"
                os.rename(
                    source_name,
                    stolen_name,
                    src_dir_fd=root_fd,
                    dst_dir_fd=root_fd,
                )
                replacement_fd = os.open(
                    source_name,
                    os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC | os.O_NOFOLLOW,
                    0o600,
                    dir_fd=root_fd,
                )
                try:
                    write_all(replacement_fd, attacker_source)
                    os.fchmod(replacement_fd, 0o600)
                finally:
                    os.close(replacement_fd)

            writer._require_sealed_staging_name = adversarial_require
            rejected = False
            try:
                try:
                    writer.provision(checkout_fd, checkout, app_key, app_secret)
                except (writer.ProvisionError, OSError):
                    rejected = True
            finally:
                writer._require_sealed_staging_name = original_require
                os.close(checkout_fd)

            identity = (
                checkout
                / "LocalSecrets"
                / "TuyaRuntime"
                / "Sources"
                / "NembraTuyaPrivateConfig"
                / "NembraTuyaPrivateIdentity.swift"
            )
            self.assertTrue(attacked, "diagnostic never reached the generated Swift publication boundary")
            self.assertTrue(rejected, "writer unexpectedly accepted the post-check source substitution")
            self.assertTrue(identity.is_file(), "fixture did not leave the replacement at the canonical identity path")
            self.assertEqual(
                identity.read_bytes(),
                attacker_source,
                "fixture no longer models the revised #2944 fail-closed preservation contract",
            )

            # Recreate only the non-secret bootstrap prerequisites needed to
            # prove admission reaches CocoaPods. The fake pod records invocation
            # and exits immediately; no dependency resolution or build occurs.
            scripts = checkout / "Scripts"
            scripts.mkdir()
            bootstrap = scripts / "bootstrap_capture_tuya_sdk.sh"
            shutil.copy2(BOOTSTRAP_PATH, bootstrap)
            bootstrap.chmod(0o700)
            (scripts / "capture_tuya_private_input_provenance.py").write_text(
                "#!/usr/bin/env python3\nraise SystemExit('diagnostic should stop before provenance helper')\n",
                encoding="utf-8",
            )
            (checkout / "Podfile").write_text("# red-team placeholder\n", encoding="utf-8")
            (checkout / "NembraCapture.xcodeproj").mkdir()

            sdk = checkout / "LocalSecrets" / "TuyaSDK"
            (sdk / "Build").mkdir(parents=True)
            (sdk / "ThingSmartCryption.podspec").write_text(
                "# red-team placeholder\n", encoding="utf-8"
            )

            sentinel = sandbox / "cocoapods-was-invoked"
            fake_bin = sandbox / "bin"
            fake_bin.mkdir()
            fake_pod = fake_bin / "pod"
            fake_pod.write_text(
                "#!/bin/sh\n"
                f": > {sentinel}\n"
                "exit 97\n",
                encoding="utf-8",
            )
            fake_pod.chmod(0o700)

            environment = os.environ.copy()
            environment["PATH"] = f"{fake_bin}:/usr/bin:/bin:/usr/sbin:/sbin"
            environment["NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256"] = "0" * 64
            result = subprocess.run(
                ["/bin/bash", str(bootstrap)],
                cwd=checkout,
                env=environment,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            self.assertFalse(
                sentinel.exists(),
                "bootstrap reached CocoaPods after failed provisioning left attacker-controlled Swift "
                f"at the canonical private identity path (exit={result.returncode}, "
                f"stdout={result.stdout!r}, stderr={result.stderr!r})",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
