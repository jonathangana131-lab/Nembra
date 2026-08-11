#!/usr/bin/env python3
"""Regression for Final-GO private-installer process environment custody.

The external GO issuer must not let caller-owned Bash startup variables execute code before the
reviewed candidate installer begins. A hostile or stale BASH_ENV is caller-constructible authority;
if it runs, the physical authorization control plane has admitted a side effect outside the exact
candidate installer bytes. The one reviewed Tuya dependency-lock digest is an explicit authority
input and must cross this boundary without reopening the ambient environment.
"""

from __future__ import annotations

import importlib.util
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

MODULE = Path(__file__).resolve().parents[1] / "es80_authenticated_stationary_final_go.py"
SPEC = importlib.util.spec_from_file_location("authenticated_stationary_final_go", MODULE)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load authenticated stationary Final-GO issuer")
GO = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GO)
LOCK_SHA256 = "a" * 64


class InstallerEnvironmentCustodyTests(unittest.TestCase):
    def test_bash_env_and_ambient_secrets_cannot_reach_candidate_installer(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-env-custody-") as temporary:
            root = Path(temporary).resolve(strict=True)
            repository = root / "candidate"
            repository.mkdir()
            subprocess.run(["/usr/bin/git", "-C", str(repository), "init", "-q"], check=True)
            subprocess.run(
                ["/usr/bin/git", "-C", str(repository), "config", "user.email", "capture@nembra.invalid"],
                check=True,
            )
            subprocess.run(
                ["/usr/bin/git", "-C", str(repository), "config", "user.name", "Nembra Capture QA"],
                check=True,
            )

            installer = repository / GO.INSTALLER
            installer.parent.mkdir(parents=True, exist_ok=True)
            installer.write_text(
                "#!/bin/bash\n"
                "set -euo pipefail\n"
                "[[ \"${BASH_ENV:-}\" == /dev/null ]] || exit 41\n"
                "[[ \"${ENV:-}\" == /dev/null ]] || exit 42\n"
                "[[ -z \"${GITHUB_TOKEN:-}\" ]] || exit 43\n"
                "[[ -z \"${NEMBRA_TUYA_APP_SECRET:-}\" ]] || exit 44\n"
                "[[ -z \"${NEMBRA_TUYA_APP_KEY:-}\" ]] || exit 45\n"
                f"[[ \"${{PATH:-}}\" == {GO.TRUSTED_INSTALLER_PATH!r} ]] || exit 46\n"
                f"[[ \"${{NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256:-}}\" == {LOCK_SHA256!r} ]] || exit 47\n"
                "printf '%s\\n' 'SDK-INTEGRATED CAPTURE LAUNCHED'\n",
                encoding="utf-8",
            )
            subprocess.run(["/usr/bin/git", "-C", str(repository), "add", "."], check=True)
            subprocess.run(
                ["/usr/bin/git", "-C", str(repository), "commit", "-qm", "fixture"],
                check=True,
            )
            source = subprocess.check_output(
                ["/usr/bin/git", "-C", str(repository), "rev-parse", "HEAD"],
                text=True,
            ).strip()

            private_device = root / "intended-device"
            private_device.write_text("00008101-001234567890001E", encoding="utf-8")
            private_device.chmod(0o600)

            sentinel = root / "bash-env-ran"
            bash_env = root / "host-bash-env"
            bash_env.write_text(
                f"printf '%s\\n' 'caller startup code executed' > {str(sentinel)!r}\n",
                encoding="utf-8",
            )

            old = dict(os.environ)
            os.environ["BASH_ENV"] = str(bash_env)
            os.environ["ENV"] = str(bash_env)
            os.environ["GITHUB_TOKEN"] = "caller-token-must-not-cross"
            os.environ["NEMBRA_TUYA_APP_SECRET"] = "caller-secret-must-not-cross"
            os.environ["NEMBRA_TUYA_APP_KEY"] = "caller-key-must-not-cross"
            os.environ["NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256"] = "f" * 64
            os.environ["PATH"] = "/caller/prepended/path:/usr/bin:/bin"
            try:
                device_digest = GO.device_hash(private_device)
                result = GO.installer(repository, source, private_device, device_digest, LOCK_SHA256)
            finally:
                os.environ.clear()
                os.environ.update(old)

            self.assertEqual(result["result"], "success")
            self.assertEqual(result["acceptedTuyaDependencyLockSHA256"], LOCK_SHA256)
            self.assertFalse(
                sentinel.exists(),
                "caller-controlled BASH_ENV executed before the reviewed candidate installer; "
                "Final GO must launch the installer from a closed startup environment",
            )

    def test_installer_environment_is_explicit_allowlist(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-env-shape-") as temporary:
            device = Path(temporary).resolve(strict=True) / "device"
            device.write_text("device", encoding="utf-8")
            device.chmod(0o600)
            device_digest = GO.device_hash(device)
            env = GO.installer_environment(device, device_digest, LOCK_SHA256)
            self.assertEqual(env["PATH"], GO.TRUSTED_INSTALLER_PATH)
            self.assertEqual(env["BASH_ENV"], "/dev/null")
            self.assertEqual(env["ENV"], "/dev/null")
            self.assertEqual(env["NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE"], str(device))
            self.assertEqual(env["NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256"], device_digest)
            self.assertEqual(env["NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256"], LOCK_SHA256)
            forbidden = {
                "GITHUB_TOKEN", "GH_TOKEN", "PYTHONPATH", "PYTHONHOME",
                "NEMBRA_TUYA_APP_KEY", "NEMBRA_TUYA_APP_SECRET",
            }
            self.assertTrue(forbidden.isdisjoint(env))
            self.assertTrue(all(not key.startswith("BASH_FUNC_") for key in env))

    def test_installer_environment_rejects_unaccepted_digest_shape(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-env-lock-shape-") as temporary:
            device = Path(temporary).resolve(strict=True) / "device"
            device.write_text("device", encoding="utf-8")
            device.chmod(0o600)
            with self.assertRaises(GO.GoError):
                GO.installer_environment(device, GO.device_hash(device), "not-reviewed-lock")

    def test_installer_environment_rejects_symlinked_private_device_parent(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-env-symlink-") as temporary:
            root = Path(temporary).resolve(strict=True)
            real_parent = root / "private"
            real_parent.mkdir()
            device = real_parent / "device"
            device.write_text("device", encoding="utf-8")
            device.chmod(0o600)
            alias = root / "alias"
            alias.symlink_to(real_parent, target_is_directory=True)
            with self.assertRaises(GO.GoError):
                GO.installer_environment(alias / "device", "0" * 64, LOCK_SHA256)

    def test_installer_environment_preserves_prechecked_digest_instead_of_recomputing(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-prechecked-digest-") as temporary:
            device = Path(temporary).resolve(strict=True) / "device"
            device.write_text("original-device", encoding="utf-8")
            device.chmod(0o600)
            prechecked = GO.device_hash(device)
            device.write_text("replacement-device", encoding="utf-8")
            env = GO.installer_environment(device, prechecked, LOCK_SHA256)
            self.assertEqual(env["NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256"], prechecked)
            self.assertNotEqual(prechecked, GO.device_hash(device))

    def test_installer_environment_rejects_invalid_prechecked_device_digest(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-device-digest-shape-") as temporary:
            device = Path(temporary).resolve(strict=True) / "device"
            device.write_text("device", encoding="utf-8")
            device.chmod(0o600)
            with self.assertRaises(GO.GoError):
                GO.installer_environment(device, "not-a-device-digest", LOCK_SHA256)


if __name__ == "__main__":
    unittest.main(verbosity=2)
