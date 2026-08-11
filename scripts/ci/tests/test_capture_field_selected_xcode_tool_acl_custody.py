#!/usr/bin/env python3
"""Permanent macOS authority regression for selected Xcode tool ACL custody.

Root ownership plus BSD mode bits are insufficient when an extended ACL grants the
field user authority to mutate a selected executable or replace it through a parent
directory. The production validator must reject both classes while still admitting
the real selected Xcode 27 developer tree and exact selected tools on the runner.

No device discovery, install, launch, Bluetooth, Tuya, telemetry, or physical action
occurs here.
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


@unittest.skipUnless(os.uname().sysname == "Darwin", "requires the macOS Xcode runner")
class CaptureFieldSelectedXcodeToolACLCustodyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.source = INSTALLER.read_text(encoding="utf-8")
        self.user = subprocess.check_output(["/usr/bin/id", "-un"], text=True).strip()
        self.assertTrue(self.user)
        self.fixture_dir = Path(f"/Applications/NembraToolACLRepair-{os.getpid()}-{id(self)}")
        self.fixture = self.fixture_dir / "xcodebuild-fixture"

    def tearDown(self) -> None:
        subprocess.run(
            ["/usr/bin/sudo", "-n", "/bin/rm", "-rf", "--", str(self.fixture_dir)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )

    def _run(self, argv: list[str], *, check: bool = True, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
        return subprocess.run(argv, text=True, capture_output=True, check=check, env=env)

    def _extract_production_custody_program(self) -> str:
        match = re.search(
            r"validate_root_custodied_path\(\)\s*\{.*?<<'PY_CUSTODY'\n(?P<body>.*?)\nPY_CUSTODY\n\}",
            self.source,
            re.DOTALL,
        )
        self.assertIsNotNone(match, "fixture requires the production selected-Xcode custody primitive")
        assert match is not None
        return match.group("body")

    def _validate(self, path: Path, kind: str) -> subprocess.CompletedProcess[str]:
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
                "NEMBRA_CUSTODY_PATH": str(path),
                "NEMBRA_CUSTODY_KIND": kind,
            }
            return subprocess.run(
                ["/usr/bin/python3", "-I", str(validator_path)],
                env=env,
                text=True,
                capture_output=True,
            )
        finally:
            validator_path.unlink(missing_ok=True)

    def _make_root_owned_fixture(self) -> None:
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
        self._run(
            [
                "/usr/bin/sudo",
                "-n",
                "/bin/chmod",
                "-RN",
                str(self.fixture_dir),
            ]
        )
        self._run(
            [
                "/usr/bin/sudo",
                "-n",
                "/bin/chmod",
                "0755",
                str(self.fixture_dir),
                str(self.fixture),
            ]
        )
        for subject in (self.fixture_dir, self.fixture):
            metadata = os.lstat(subject)
            self.assertEqual(metadata.st_uid, 0)
            self.assertEqual(metadata.st_mode & 0o022, 0)

    def test_clean_root_owned_fixture_is_admitted(self) -> None:
        self._make_root_owned_fixture()
        admitted = self._validate(self.fixture, "file")
        self.assertEqual(admitted.returncode, 0, admitted.stderr)

    def test_named_user_leaf_write_acl_is_rejected(self) -> None:
        self._make_root_owned_fixture()
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
        self.assertEqual(metadata.st_uid, 0)
        self.assertEqual(metadata.st_mode & 0o022, 0)
        acl = self._run(["/bin/ls", "-lde", str(self.fixture)]).stdout
        self.assertIn(self.user, acl)
        self.assertRegex(acl, re.compile(r"(?i)allow\s+write"))

        before = self.fixture.read_bytes()
        mutation = self._run(
            ["/bin/sh", "-c", f"printf '# acl-leaf-write\\n' >> {shlex.quote(str(self.fixture))}"],
            check=False,
        )
        self.assertEqual(mutation.returncode, 0, mutation.stderr)
        self.assertNotEqual(before, self.fixture.read_bytes())

        admitted = self._validate(self.fixture, "file")
        self.assertNotEqual(admitted.returncode, 0, "ACL-writable selected executable was admitted")
        self.assertIn("extended ACL", admitted.stderr)

    def test_parent_acl_that_can_replace_leaf_is_rejected(self) -> None:
        self._make_root_owned_fixture()
        self._run(
            [
                "/usr/bin/sudo",
                "-n",
                "/bin/chmod",
                "+a",
                f"{self.user} allow add_file,delete_child",
                str(self.fixture_dir),
            ]
        )
        metadata = os.lstat(self.fixture_dir)
        self.assertEqual(metadata.st_uid, 0)
        self.assertEqual(metadata.st_mode & 0o022, 0)
        acl = self._run(["/bin/ls", "-lde", str(self.fixture_dir)]).stdout
        self.assertIn(self.user, acl)
        self.assertRegex(acl, re.compile(r"(?i)allow\s+add_file,delete_child|allow\s+delete_child,add_file"))

        replacement = self.fixture_dir / "replacement"
        attack = self._run(
            [
                "/bin/sh",
                "-c",
                (
                    f"rm -f {shlex.quote(str(self.fixture))} && "
                    f"printf '#!/bin/sh\\nexit 99\\n' > {shlex.quote(str(replacement))} && "
                    f"mv {shlex.quote(str(replacement))} {shlex.quote(str(self.fixture))}"
                ),
            ],
            check=False,
        )
        self.assertEqual(attack.returncode, 0, f"ancestor ACL did not establish replacement authority: {attack.stderr}")
        self.assertIn(b"exit 99", self.fixture.read_bytes())

        # Restore a root-owned 0755 leaf so the rejection is attributable to the
        # ancestor ACL rather than the attack-created leaf metadata.
        self._run(["/usr/bin/sudo", "-n", "/usr/sbin/chown", "root:wheel", str(self.fixture)])
        self._run(["/usr/bin/sudo", "-n", "/bin/chmod", "0755", str(self.fixture)])
        admitted = self._validate(self.fixture, "file")
        self.assertNotEqual(admitted.returncode, 0, "ACL-replaceable selected-tool ancestry was admitted")
        self.assertIn("extended ACL", admitted.stderr)

    def test_real_selected_xcode_27_tree_and_tools_are_acl_clean(self) -> None:
        developer_dir = Path(self._run(["/usr/bin/xcode-select", "-p"]).stdout.strip())
        self.assertTrue(developer_dir.is_absolute())
        selected_environment = dict(os.environ)
        selected_environment["DEVELOPER_DIR"] = str(developer_dir)

        admitted_tree = self._validate(developer_dir, "directory")
        self.assertEqual(admitted_tree.returncode, 0, admitted_tree.stderr)

        version = self._run([str(developer_dir / "usr/bin/xcodebuild"), "-version"], check=False)
        self.assertEqual(version.returncode, 0, version.stderr)
        self.assertRegex(version.stdout.splitlines()[0], r"^Xcode\s+27(?:\.|$)")

        for tool in ("xcodebuild", "xctrace", "devicectl"):
            selected = Path(
                self._run(["/usr/bin/xcrun", "--find", tool], env=selected_environment).stdout.strip()
            )
            self.assertTrue(str(selected).startswith(str(developer_dir) + "/"))
            admitted = self._validate(selected, "file")
            self.assertEqual(admitted.returncode, 0, f"real selected {tool} rejected: {admitted.stderr}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
