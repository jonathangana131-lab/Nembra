#!/usr/bin/env python3
"""Regression for Final-GO private-installer process environment custody."""
from __future__ import annotations

import importlib.util
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

MODULE = Path(__file__).resolve().parents[1] / "es80_authenticated_stationary_final_go.py"
SPEC = importlib.util.spec_from_file_location("authenticated_stationary_final_go", MODULE)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load authenticated stationary Final-GO issuer")
GO = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GO)


class InstallerEnvironmentCustodyTests(unittest.TestCase):
    def test_caller_environment_cannot_execute_or_reach_candidate_installer(self) -> None:
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

            sentinel = root / "bash-env-ran"
            bash_env = root / "host-bash-env"
            bash_env.write_text(
                f"printf '%s\\n' 'caller startup code executed' > {str(sentinel)!r}\n",
                encoding="utf-8",
            )

            installer = repository / GO.INSTALLER
            installer.parent.mkdir(parents=True, exist_ok=True)
            installer.write_text(
                "#!/bin/bash\n"
                "set -euo pipefail\n"
                f"[[ \"${{PATH}}\" == {GO.TRUSTED_INSTALLER_PATH!r} ]]\n"
                "[[ \"${BASH_ENV-}\" == /dev/null ]]\n"
                "[[ \"${ENV-}\" == /dev/null ]]\n"
                "[[ -n \"${NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE-}\" ]]\n"
                "[[ -z \"${GITHUB_TOKEN-}\" ]]\n"
                "[[ -z \"${NEMBRA_TUYA_APP_KEY-}\" ]]\n"
                "[[ -z \"${NEMBRA_TUYA_APP_SECRET-}\" ]]\n"
                "[[ -z \"${PYTHONPATH-}\" ]]\n"
                "[[ -z \"${RUBYOPT-}\" ]]\n"
                "[[ -z \"${GEM_HOME-}\" ]]\n"
                "[[ -z \"${DYLD_INSERT_LIBRARIES-}\" ]]\n"
                "[[ -z \"${EVIL_CALLER_VARIABLE-}\" ]]\n"
                "if declare -F nembra_injected >/dev/null; then exit 42; fi\n"
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

            hostile = {
                "PATH": str(root / "attacker-bin"),
                "BASH_ENV": str(bash_env),
                "ENV": str(bash_env),
                "GITHUB_TOKEN": "github-secret",
                "NEMBRA_TUYA_APP_KEY": "tuya-key",
                "NEMBRA_TUYA_APP_SECRET": "tuya-secret",
                "PYTHONPATH": str(root / "python-poison"),
                "RUBYOPT": "-rattacker",
                "GEM_HOME": str(root / "gem-poison"),
                "DYLD_INSERT_LIBRARIES": str(root / "inject.dylib"),
                "EVIL_CALLER_VARIABLE": "must-not-cross-boundary",
                "BASH_FUNC_nembra_injected%%": "() { printf injected; }",
            }
            with mock.patch.dict(os.environ, hostile, clear=False):
                result = GO.installer(repository, source, private_device)

            self.assertEqual(result["result"], "success")
            self.assertFalse(
                sentinel.exists(),
                "caller-controlled BASH_ENV executed before candidate installer",
            )

    def test_passthrough_is_narrow_and_does_not_admit_authority_variables(self) -> None:
        self.assertEqual(
            GO.INSTALLER_ENV_PASSTHROUGH,
            ("HOME", "TMPDIR", "DEVELOPER_DIR", "LANG", "LC_ALL", "USER", "LOGNAME"),
        )
        forbidden = {
            "BASH_ENV",
            "ENV",
            "PATH",
            "GITHUB_TOKEN",
            "GITHUB_ENV",
            "GITHUB_PATH",
            "NEMBRA_TUYA_APP_KEY",
            "NEMBRA_TUYA_APP_SECRET",
            "PYTHONPATH",
            "RUBYOPT",
            "GEM_HOME",
            "GEM_PATH",
            "DYLD_INSERT_LIBRARIES",
            "DYLD_LIBRARY_PATH",
        }
        self.assertTrue(forbidden.isdisjoint(GO.INSTALLER_ENV_PASSTHROUGH))
        self.assertEqual(
            GO.TRUSTED_INSTALLER_PATH,
            "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
