#!/usr/bin/env python3
from __future__ import annotations

import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
INSTALLER = ROOT / "scripts/field/install_one_time_capture.command"
PROVISIONER = ROOT / "Scripts/provision_capture_tuya_identity.sh"
PROVISIONER_CORE = ROOT / "Scripts/provision_capture_tuya_identity.py"
BOOTSTRAP = ROOT / "Scripts/bootstrap_capture_tuya_sdk.sh"


class CurrentFieldProvisioningRegression(unittest.TestCase):
    def test_private_reader_cannot_write_python_bytecode_into_checkout(self) -> None:
        source = INSTALLER.read_text()
        self.assertIn('/usr/bin/python3 -B -I - "$PRIVATE_DEVICE_RUNNER"', source)
        self.assertNotIn('/usr/bin/python3 -I - "$PRIVATE_DEVICE_RUNNER"', source)
        self.assertLess(
            source.index('-B -I - "$PRIVATE_DEVICE_RUNNER"'),
            source.index('Scripts/bootstrap_capture_tuya_sdk.sh'),
        )

    def test_bootstrap_recovery_command_exists_and_does_not_accept_secret_argv(self) -> None:
        bootstrap = BOOTSTRAP.read_text()
        wrapper = PROVISIONER.read_text()
        core = PROVISIONER_CORE.read_text()
        self.assertIn("Scripts/provision_capture_tuya_identity.sh", bootstrap)
        self.assertIn('unset NEMBRA_TUYA_APP_KEY NEMBRA_TUYA_APP_SECRET', wrapper)
        self.assertIn('getpass.getpass("Tuya AppKey (input hidden): ")', core)
        self.assertIn('getpass.getpass("Tuya AppSecret (input hidden): ")', core)
        self.assertIn('if sys.argv[1:]:', core)
        self.assertNotIn("NEMBRA_TUYA_APP_KEY", core)
        self.assertNotIn("NEMBRA_TUYA_APP_SECRET", core)

    def test_private_output_is_exclusive_private_and_no_clobber(self) -> None:
        core = PROVISIONER_CORE.read_text()
        self.assertIn("os.O_WRONLY | os.O_CREAT | os.O_EXCL", core)
        self.assertIn("LocalSecrets/TuyaRuntime already exists", core)
        self.assertIn("target.mkdir(mode=0o700)", core)
        self.assertIn("os.chmod(directory, 0o700)", core)
        self.assertIn("NembraTuyaPrivateIdentity", core)
        self.assertIn("public static let appKey", core)
        self.assertIn("public static let appSecret", core)

    def test_portable_self_test_passes_without_real_secrets(self) -> None:
        completed = subprocess.run(
            ["/bin/bash", str(PROVISIONER), "--self-test"],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertIn("provisioner self-test: PASS", completed.stdout)


if __name__ == "__main__":
    unittest.main()
