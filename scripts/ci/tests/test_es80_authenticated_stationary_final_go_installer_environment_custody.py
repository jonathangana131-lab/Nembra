#!/usr/bin/env python3
"""Regression for Final-GO private-installer process environment custody.

The external GO issuer must not let caller-owned Bash startup variables execute code before the
reviewed candidate installer begins. A hostile or stale BASH_ENV is caller-constructible authority;
if it runs, the physical authorization control plane has admitted a side effect outside the exact
candidate installer bytes.
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

            accepted_lock = "a" * 64
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
                f"[[ \"${{NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256:-}}\" == {accepted_lock!r} ]] || exit 47\n"
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
            os.environ["NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256"] = "b" * 64
            os.environ["PATH"] = "/caller/prepended/path:/usr/bin:/bin"
            try:
                result = GO.installer(repository, source, private_device, accepted_lock)
            finally:
                os.environ.clear()
                os.environ.update(old)

            self.assertEqual(result["result"], "success")
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
            accepted_lock = "c" * 64
            env = GO.installer_environment(device, accepted_lock)
            self.assertEqual(env["PATH"], GO.TRUSTED_INSTALLER_PATH)
            self.assertEqual(env["BASH_ENV"], "/dev/null")
            self.assertEqual(env["ENV"], "/dev/null")
            self.assertEqual(env["NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE"], str(device))
            self.assertEqual(env["NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256"], accepted_lock)
            forbidden = {
                "GITHUB_TOKEN", "GH_TOKEN", "PYTHONPATH", "PYTHONHOME",
                "NEMBRA_TUYA_APP_KEY", "NEMBRA_TUYA_APP_SECRET",
            }
            self.assertTrue(forbidden.isdisjoint(env))
            self.assertTrue(all(not key.startswith("BASH_FUNC_") for key in env))

    def test_noncanonical_tuya_lock_digest_is_rejected_before_installer(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-lock-shape-") as temporary:
            device = Path(temporary).resolve(strict=True) / "device"
            device.write_text("device", encoding="utf-8")
            device.chmod(0o600)
            for digest in ("A" * 64, "a" * 63, "not-a-digest"):
                with self.assertRaises(GO.GoError):
                    GO.installer_environment(device, digest)

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
                GO.installer_environment(alias / "device", "d" * 64)


if __name__ == "__main__":
    unittest.main(verbosity=2)
