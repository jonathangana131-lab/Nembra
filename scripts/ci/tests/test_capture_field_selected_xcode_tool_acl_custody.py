#!/usr/bin/env python3
"""Permanent macOS regression for selected Xcode tool ACL custody.

Root ownership and BSD mode bits are not sufficient executable authority on macOS:
a named-user POSIX ACL can grant the field operator write access to a root-owned 0755
subject. The production selected-tool custody primitive must admit the same fixture
before ACL injection, mechanically prove the ACL grants real mutation authority, and
then reject that exact subject after the ACL is present.

This test performs no Xcode device discovery, build, install, launch, Bluetooth, Tuya,
telemetry, scooter command, or physical experiment.
"""
from __future__ import annotations

import os
from pathlib import Path
import re
import shlex
import stat
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
INSTALLER = ROOT / "scripts" / "field" / "install_one_time_capture.command"


class CaptureFieldSelectedXcodeToolACLCustodyTests(unittest.TestCase):
    def setUp(self) -> None:
        if os.uname().sysname != "Darwin":
            self.skipTest("real POSIX ACL authority witness requires macOS")
        self.source = INSTALLER.read_text(encoding="utf-8")
        self.user = os.environ.get("USER", "").strip()
        self.assertTrue(self.user, "runner user identity is required for the ACL witness")
        self.fixture_dir = Path(f"/Applications/NembraSelectedToolACL-{os.getpid()}")
        self.fixture = self.fixture_dir / "xcodebuild-fixture"

    def tearDown(self) -> None:
        if hasattr(self, "fixture_dir"):
            subprocess.run(
                ["/usr/bin/sudo", "-n", "/bin/rm", "-rf", "--", str(self.fixture_dir)],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )

    def _run(self, argv: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
        return subprocess.run(argv, text=True, capture_output=True, check=check)

    def _extract_production_custody_program(self) -> str:
        match = re.search(
            r"validate_root_custodied_path\(\)\s*\{.*?<<'PY_CUSTODY'\n(?P<body>.*?)\nPY_CUSTODY\n\}",
            self.source,
            re.DOTALL,
        )
        self.assertIsNotNone(match, "fixture requires the production selected-Xcode custody primitive")
        assert match is not None
        return match.group("body")

    def _run_validator(self, validator_path: Path) -> subprocess.CompletedProcess[str]:
        env = {
            "PATH": "/usr/bin:/bin",
            "HOME": "/tmp",
            "LANG": "C",
            "LC_ALL": "C",
            "NEMBRA_CUSTODY_PATH": str(self.fixture),
            "NEMBRA_CUSTODY_KIND": "file",
        }
        return subprocess.run(
            ["/usr/bin/python3", "-I", str(validator_path)],
            env=env,
            text=True,
            capture_output=True,
        )

    def test_named_user_write_acl_is_rejected_after_clean_subject_was_admissible(self) -> None:
        self._run(["/usr/bin/sudo", "-n", "/bin/mkdir", "-p", str(self.fixture_dir)])
        self._run(
            [
                "/usr/bin/sudo",
                "-n",
                "/bin/sh",
                "-c",
                f"printf '#!/bin/sh\\nexit 0\\n' > {shlex.quote(str(self.fixture))}",
            ]
        )
        self._run(
            [
                "/usr/bin/sudo",
                "-n",
                "/usr/sbin/chown",
                "root:wheel",
                str(self.fixture_dir),
                str(self.fixture),
            ]
        )
        self._run(["/usr/bin/sudo", "-n", "/bin/chmod", "0755", str(self.fixture_dir), str(self.fixture)])

        metadata = os.lstat(self.fixture)
        self.assertTrue(stat.S_ISREG(metadata.st_mode))
        self.assertEqual(metadata.st_uid, 0)
        self.assertEqual(metadata.st_mode & 0o022, 0)

        program = self._extract_production_custody_program()
        with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False, encoding="utf-8") as handle:
            handle.write(program)
            validator_path = Path(handle.name)
        try:
            baseline = self._run_validator(validator_path)
            self.assertEqual(
                baseline.returncode,
                0,
                f"fixture must be admissible before ACL injection: {baseline.stderr}",
            )

            self._run(
                [
                    "/usr/bin/sudo",
                    "-n",
                    "/bin/chmod",
                    "+a",
                    f"{self.user} allow write",
                    str(self.fixture),
                ]
            )
            acl = self._run(["/bin/ls", "-lde", str(self.fixture)]).stdout
            self.assertIn(self.user, acl, "fixture must expose the named-user ACL grant")
            self.assertRegex(acl, re.compile(r"(?i)allow\s+write"))

            before = self.fixture.read_bytes()
            mutation = subprocess.run(
                ["/bin/sh", "-c", f"printf '# acl-attacker-write\\n' >> {shlex.quote(str(self.fixture))}"],
                text=True,
                capture_output=True,
            )
            self.assertEqual(
                mutation.returncode,
                0,
                f"ACL fixture did not establish same-user mutation authority: {mutation.stderr}",
            )
            self.assertNotEqual(before, self.fixture.read_bytes())

            admitted = self._run_validator(validator_path)
            self.assertNotEqual(
                admitted.returncode,
                0,
                "selected-tool custody accepted a root-owned 0755 executable with ACL-granted field-user write authority",
            )
            self.assertIn("refuses extended ACL authority", admitted.stderr)
        finally:
            validator_path.unlink(missing_ok=True)


if __name__ == "__main__":
    unittest.main(verbosity=2)
