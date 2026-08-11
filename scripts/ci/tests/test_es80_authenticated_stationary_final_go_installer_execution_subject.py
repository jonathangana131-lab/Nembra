#!/usr/bin/env python3
"""Expected-red regression: Final-GO must execute the exact reviewed installer bytes."""
from __future__ import annotations

import importlib.util
import os
import shlex
import subprocess
import tempfile
import unittest
from pathlib import Path

MODULE = Path(__file__).resolve().parents[1] / "es80_authenticated_stationary_final_go.py"
SPEC = importlib.util.spec_from_file_location("nembra_final_go", MODULE)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load Final-GO issuer")
go = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(go)


class InstallerExecutionSubjectCustodyTests(unittest.TestCase):
    def git(self, repo: Path, *args: str) -> str:
        return subprocess.run(
            ["/usr/bin/git", "-C", str(repo), *args],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env={"PATH": "/usr/bin:/bin"},
        ).stdout.strip()

    def test_verified_installer_cannot_be_replaced_only_for_execution(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-installer-subject-") as temporary:
            root = Path(temporary)
            repo = root / "candidate"
            installer = repo / go.INSTALLER
            runbook = repo / go.RUNBOOK
            identity = repo / go.IDENTITY
            installer.parent.mkdir(parents=True)
            runbook.parent.mkdir(parents=True)
            identity.parent.mkdir(parents=True)

            accepted_installer = f'''#!/bin/bash
set -euo pipefail
PROCEDURE_ID="{go.PROC}"
BUNDLE_ID="{go.BUNDLE}"
echo "accepted installer must be the executed subject"
exit 97
'''
            installer.write_text(accepted_installer, encoding="utf-8")
            installer.chmod(0o755)
            runbook.write_text(f"PROCEDURE_ID: `{go.PROC}`\n", encoding="utf-8")
            identity.write_text(
                f'enum BuildIdentity {{ static let requiredFieldProcedureIdentifier = "{go.PROC}" }}\n',
                encoding="utf-8",
            )

            self.git(repo, "init", "-q")
            self.git(repo, "config", "user.name", "nembra-adversarial")
            self.git(repo, "config", "user.email", "nembra-adversarial@invalid.example")
            self.git(repo, "add", ".")
            self.git(repo, "commit", "-q", "-m", "accepted candidate")
            source = self.git(repo, "rev-parse", "HEAD")

            accepted = go.candidate(repo, source)
            self.assertEqual(accepted["sourceCommitSHA"], source)

            backup = root / "accepted-installer.command"
            backup.write_text(accepted_installer, encoding="utf-8")
            backup.chmod(0o755)
            backup_q = shlex.quote(str(backup))
            malicious = f'''#!/bin/bash
set -euo pipefail
trap '/bin/cp {backup_q} "$0"; /bin/chmod 755 "$0"' EXIT
printf '%s\\n' 'SDK-INTEGRATED CAPTURE LAUNCHED'
'''
            installer.write_text(malicious, encoding="utf-8")
            installer.chmod(0o755)

            device = root / "intended-device.txt"
            device.write_text("test-device\n", encoding="utf-8")
            device.chmod(0o600)

            with self.assertRaises(
                go.GoError,
                msg=(
                    "Final-GO accepted a pathname-swapped installer after verifying different Git bytes; "
                    "the actual Bash execution subject must be pinned to the reviewed blob."
                ),
            ):
                go.installer(repo, source, device)

            self.assertEqual(installer.read_text(encoding="utf-8"), accepted_installer)
            self.assertEqual(self.git(repo, "status", "--porcelain=v1", "--untracked-files=all"), "")


if __name__ == "__main__":
    unittest.main()
