#!/usr/bin/env python3
"""Real-macOS regression for selected Xcode tool ACL custody.

The physical field installer treats the selected Xcode developer tree and exact
xcodebuild/xctrace/devicectl executables as authority-bearing subjects. Root
ownership plus clean BSD group/world-write bits are insufficient on macOS when
an extended ACL separately grants mutation or directory-entry authority.

This regression requires production custody to reject extended ACLs on both an
exact tool leaf and its ancestry while still admitting the runner's real
selected Xcode 27 subjects when they have no such ACL authority.

No device discovery, build, install, Bluetooth, Tuya, or physical action occurs.
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


class CaptureFieldSelectedXcodeToolACLCustodyCurrentTests(unittest.TestCase):
    def setUp(self) -> None:
        if os.uname().sysname != "Darwin":
            self.skipTest("selected-Xcode ACL custody requires the real macOS runner")
        self.source = INSTALLER.read_text(encoding="utf-8")
        self.user = os.environ.get("USER", "").strip()
        self.assertTrue(self.user, "runner user identity is required")
        self.fixture_dir = Path(f"/Applications/NembraToolACLRepair-{os.getpid()}-{id(self)}")
        self.fixture = self.fixture_dir / "xcodebuild-fixture"
        self._sudo(["/bin/mkdir", "-p", str(self.fixture_dir)])
        self._sudo(
            [
                "/bin/sh",
                "-c",
                f"printf '#!/bin/sh\\nexit 0\\n' > {shlex.quote(str(self.fixture))}",
            ]
        )
        self._sudo(
            [
                "/usr/sbin/chown",
                "root:wheel",
                str(self.fixture_dir),
                str(self.fixture),
            ]
        )
        self._sudo(["/bin/chmod", "0755", str(self.fixture_dir)])
        self._sudo(["/bin/chmod", "0555", str(self.fixture)])
        self.validator = self._materialize_validator()

    def tearDown(self) -> None:
        validator = getattr(self, "validator", None)
        if validator is not None:
            Path(validator).unlink(missing_ok=True)
        fixture_dir = getattr(self, "fixture_dir", None)
        if fixture_dir is not None:
            subprocess.run(
                ["/usr/bin/sudo", "-n", "/bin/rm", "-rf", "--", str(fixture_dir)],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )

    def _run(self, argv: list[str], *, check: bool = True, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
        return subprocess.run(argv, text=True, capture_output=True, check=check, env=env)

    def _sudo(self, argv: list[str]) -> subprocess.CompletedProcess[str]:
        return self._run(["/usr/bin/sudo", "-n", *argv])

    def _materialize_validator(self) -> Path:
        match = re.search(
            r"validate_root_custodied_path\(\)\s*\{.*?<<'PY_CUSTODY'\n(?P<body>.*?)\nPY_CUSTODY\n\}",
            self.source,
            re.DOTALL,
        )
        self.assertIsNotNone(match, "production selected-Xcode custody primitive is required")
        assert match is not None
        handle = tempfile.NamedTemporaryFile("w", suffix=".py", delete=False, encoding="utf-8")
        with handle:
            handle.write(match.group("body"))
        return Path(handle.name)

    def _validate(self, path: Path, kind: str) -> subprocess.CompletedProcess[str]:
        return self._run(
            ["/usr/bin/python3", "-I", str(self.validator)],
            check=False,
            env={
                "PATH": "/usr/bin:/bin",
                "HOME": "/tmp",
                "LANG": "C",
                "LC_ALL": "C",
                "NEMBRA_CUSTODY_PATH": str(path),
                "NEMBRA_CUSTODY_KIND": kind,
            },
        )

    def _assert_fixture_metadata_clean(self) -> None:
        for path, expected_type in ((self.fixture_dir, "directory"), (self.fixture, "file")):
            metadata = os.lstat(path)
            if expected_type == "directory":
                self.assertTrue(stat.S_ISDIR(metadata.st_mode))
            else:
                self.assertTrue(stat.S_ISREG(metadata.st_mode))
            self.assertEqual(metadata.st_uid, 0)
            self.assertEqual(metadata.st_mode & 0o022, 0)

    def test_clean_root_owned_fixture_is_admitted(self) -> None:
        self._assert_fixture_metadata_clean()
        admitted = self._validate(self.fixture, "file")
        self.assertEqual(
            admitted.returncode,
            0,
            f"clean root-owned fixture should remain admissible: {admitted.stderr}",
        )

    def test_named_user_write_acl_on_exact_tool_leaf_is_rejected(self) -> None:
        self._sudo(["/bin/chmod", "+a", f"{self.user} allow write", str(self.fixture)])
        self._assert_fixture_metadata_clean()
        acl = self._run(["/bin/ls", "-lde", str(self.fixture)]).stdout
        self.assertIn(self.user, acl)
        self.assertRegex(acl, re.compile(r"(?i)allow\s+write"))

        before = self.fixture.read_bytes()
        mutation = self._run(
            ["/bin/sh", "-c", f"printf '# acl-leaf-write\\n' >> {shlex.quote(str(self.fixture))}"],
            check=False,
        )
        self.assertEqual(
            mutation.returncode,
            0,
            f"fixture must prove ACL-granted leaf mutation authority: {mutation.stderr}",
        )
        self.assertNotEqual(before, self.fixture.read_bytes())

        rejected = self._validate(self.fixture, "file")
        self.assertNotEqual(
            rejected.returncode,
            0,
            "production selected-Xcode custody must reject an ACL-writable exact tool leaf",
        )
        self.assertIn("extended ACL", rejected.stderr)

    def test_named_user_directory_entry_acl_on_ancestry_is_rejected(self) -> None:
        self._sudo(
            [
                "/bin/chmod",
                "+a",
                f"{self.user} allow add_file,delete_child",
                str(self.fixture_dir),
            ]
        )
        self._assert_fixture_metadata_clean()
        acl = self._run(["/bin/ls", "-lde", str(self.fixture_dir)]).stdout
        self.assertIn(self.user, acl)
        self.assertRegex(acl, re.compile(r"(?i)allow.*add_file"))

        injected = self.fixture_dir / "sibling-injected-by-acl"
        injection = self._run(
            ["/bin/sh", "-c", f"printf 'acl ancestry authority\\n' > {shlex.quote(str(injected))}"],
            check=False,
        )
        self.assertEqual(
            injection.returncode,
            0,
            f"fixture must prove ACL-granted directory-entry authority: {injection.stderr}",
        )
        self.assertTrue(injected.is_file())

        rejected_leaf = self._validate(self.fixture, "file")
        self.assertNotEqual(
            rejected_leaf.returncode,
            0,
            "exact selected tool must be rejected when an ancestry component carries extended ACL authority",
        )
        self.assertIn("extended ACL", rejected_leaf.stderr)
        rejected_directory = self._validate(self.fixture_dir, "directory")
        self.assertNotEqual(rejected_directory.returncode, 0)
        self.assertIn("extended ACL", rejected_directory.stderr)

    def test_real_selected_xcode_subjects_remain_compatible(self) -> None:
        developer_dir = Path(
            self._run(["/usr/bin/xcode-select", "-p"]).stdout.strip()
        )
        self.assertTrue(developer_dir.is_absolute())
        environment = dict(os.environ)
        environment["DEVELOPER_DIR"] = str(developer_dir)
        subjects: list[tuple[Path, str]] = [(developer_dir, "directory")]
        for tool in ("xcodebuild", "xctrace", "devicectl"):
            resolved = self._run(
                ["/usr/bin/xcrun", "--find", tool],
                env=environment,
            ).stdout.strip()
            self.assertTrue(resolved, f"selected Xcode must resolve {tool}")
            subject = Path(resolved)
            self.assertTrue(str(subject).startswith(str(developer_dir) + "/"))
            subjects.append((subject, "file"))

        for subject, kind in subjects:
            admitted = self._validate(subject, kind)
            self.assertEqual(
                admitted.returncode,
                0,
                f"runner's real selected Xcode subject must remain compatible ({subject}): {admitted.stderr}",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
