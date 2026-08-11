#!/usr/bin/env python3
"""Expected-red regression for Final-GO private-installer process environment custody.

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
    def test_bash_env_cannot_execute_before_candidate_installer(self) -> None:
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
            self.assertFalse(
                sentinel.exists(),
                "caller-controlled BASH_ENV executed before the reviewed candidate installer; "
                "Final GO must launch the installer from a closed startup environment",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
