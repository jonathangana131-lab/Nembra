#!/usr/bin/env python3
"""Expected-red macOS witness for selected Xcode tool ACL custody.

A root-owned regular executable with BSD mode 0755 can still be writable by the
field operator when a POSIX ACL grants that named user write access. The current
selected-Xcode file-custody primitive must reject that subject before it can be
used as physical build/device-tool authority.

Validation only. This test performs no Xcode device operation and authorizes no
physical experiment.
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


class CaptureFieldSelectedXcodeToolACLCustodyRedTeamTests(unittest.TestCase):
    def setUp(self) -> None:
        if os.uname().sysname != "Darwin":
            self.skipTest("real POSIX ACL authority witness requires the macOS runner")
        self.source = INSTALLER.read_text(encoding="utf-8")
        self.user = os.environ.get("USER", "").strip()
        self.assertTrue(self.user, "runner user identity is required for the ACL witness")
        self.fixture_dir = Path(f"/Applications/NembraToolACLCustody-{os.getpid()}")
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

    def test_root_owned_0755_tool_with_write_acl_is_rejected_before_authority(self) -> None:
        # Build the fixture underneath /Applications because that is the same
        # root-custodied namespace class as the selected Xcode installation.
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
        self._run(["/usr/bin/sudo", "-n", "/usr/sbin/chown", "root:wheel", str(self.fixture_dir), str(self.fixture)])
        self._run(["/usr/bin/sudo", "-n", "/bin/chmod", "0755", str(self.fixture_dir), str(self.fixture)])
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

        metadata = os.lstat(self.fixture)
        self.assertTrue(stat.S_ISREG(metadata.st_mode))
        self.assertEqual(metadata.st_uid, 0, "fixture must remain root-owned")
        self.assertEqual(metadata.st_mode & 0o022, 0, "fixture must look non-group/world-writable in BSD mode bits")

        acl = self._run(["/bin/ls", "-lde", str(self.fixture)]).stdout
        print("NEMBRA_ACL_WITNESS_LS_BEGIN")
        print(acl.rstrip())
        print("NEMBRA_ACL_WITNESS_LS_END")
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
            f"macOS ACL witness did not establish same-user write authority: {mutation.stderr}",
        )
        after = self.fixture.read_bytes()
        self.assertNotEqual(before, after, "ACL-granted field user must mechanically mutate the root-owned 0755 subject")

        program = self._extract_production_custody_program()
        with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False, encoding="utf-8") as handle:
            handle.write(program)
            validator_path = Path(handle.name)
        try:
            env = {
                "PATH": "/usr/bin:/bin",
                "HOME": "/tmp",
                "LANG": "C",
                "LC_ALL": "C",
                "NEMBRA_CUSTODY_PATH": str(self.fixture),
                "NEMBRA_CUSTODY_KIND": "file",
            }
            admitted = subprocess.run(
                ["/usr/bin/python3", "-I", str(validator_path)],
                env=env,
                text=True,
                capture_output=True,
            )
        finally:
            validator_path.unlink(missing_ok=True)

        self.assertNotEqual(
            admitted.returncode,
            0,
            "EXPECTED RED: current selected-Xcode file custody accepted a root-owned 0755 executable that the field operator can mutate through a POSIX ACL. Exact physical-tool custody must reject ACL-granted write authority before execution.",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
