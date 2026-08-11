#!/usr/bin/env python3
"""Regression for Final-GO private-installer process environment custody."""

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
    def fixture(self, root: Path, script: str) -> tuple[Path, str, Path]:
        repository = root / "candidate"
        repository.mkdir()
        subprocess.run(["/usr/bin/git", "-C", str(repository), "init", "-q"], check=True)
        subprocess.run(["/usr/bin/git", "-C", str(repository), "config", "user.email", "capture@nembra.invalid"], check=True)
        subprocess.run(["/usr/bin/git", "-C", str(repository), "config", "user.name", "Nembra Capture QA"], check=True)
        installer = repository / GO.INSTALLER
        installer.parent.mkdir(parents=True, exist_ok=True)
        installer.write_text(script, encoding="utf-8")
        subprocess.run(["/usr/bin/git", "-C", str(repository), "add", "."], check=True)
        subprocess.run(["/usr/bin/git", "-C", str(repository), "commit", "-qm", "fixture"], check=True)
        source = subprocess.check_output(["/usr/bin/git", "-C", str(repository), "rev-parse", "HEAD"], text=True).strip()
        private_device = root / "intended-device"
        private_device.write_text("00008101-001234567890001E", encoding="utf-8")
        private_device.chmod(0o600)
        return repository, source, private_device

    def test_bash_env_cannot_execute_before_candidate_installer(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-env-custody-") as temporary:
            root = Path(temporary).resolve(strict=True)
            repository, source, private_device = self.fixture(
                root,
                "#!/bin/bash\nset -euo pipefail\nprintf '%s\\n' 'SDK-INTEGRATED CAPTURE LAUNCHED'\n",
            )
            sentinel = root / "bash-env-ran"
            bash_env = root / "host-bash-env"
            bash_env.write_text(f"printf '%s\\n' 'caller startup code executed' > {str(sentinel)!r}\n", encoding="utf-8")
            previous = os.environ.get("BASH_ENV")
            os.environ["BASH_ENV"] = str(bash_env)
            try:
                result = GO.installer(repository, source, private_device)
            finally:
                if previous is None:
                    os.environ.pop("BASH_ENV", None)
                else:
                    os.environ["BASH_ENV"] = previous
            self.assertEqual(result["result"], "success")
            self.assertFalse(sentinel.exists(), "caller-controlled BASH_ENV executed before reviewed candidate installer")

    def test_caller_path_and_exported_function_do_not_become_installer_authority(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-env-path-") as temporary:
            root = Path(temporary).resolve(strict=True)
            repository, source, private_device = self.fixture(
                root,
                "#!/bin/bash\nset -euo pipefail\n"
                "case \"$PATH\" in *nembra-host-path*) exit 91;; esac\n"
                "env | grep -q '^BASH_FUNC_nembra_host%%=' && exit 92 || true\n"
                "printf '%s\\n' 'SDK-INTEGRATED CAPTURE LAUNCHED'\n",
            )
            old_path = os.environ.get("PATH")
            old_function = os.environ.get("BASH_FUNC_nembra_host%%")
            os.environ["PATH"] = f"{root}/nembra-host-path:" + (old_path or "")
            os.environ["BASH_FUNC_nembra_host%%"] = "() { printf hostile; }"
            try:
                result = GO.installer(repository, source, private_device)
            finally:
                if old_path is None:
                    os.environ.pop("PATH", None)
                else:
                    os.environ["PATH"] = old_path
                if old_function is None:
                    os.environ.pop("BASH_FUNC_nembra_host%%", None)
                else:
                    os.environ["BASH_FUNC_nembra_host%%"] = old_function
            self.assertEqual(result["result"], "success")


if __name__ == "__main__":
    unittest.main(verbosity=2)
