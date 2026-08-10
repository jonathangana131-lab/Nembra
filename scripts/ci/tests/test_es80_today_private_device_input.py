#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import shutil
import stat
import sys
import tempfile
import unittest
from unittest import mock

MODULE_PATH = Path(__file__).resolve().parents[1] / "es80_today_private_device_input.py"
spec = importlib.util.spec_from_file_location("private_device_input", MODULE_PATH)
module = importlib.util.module_from_spec(spec)
assert spec and spec.loader
sys.modules[spec.name] = module
spec.loader.exec_module(module)


class PrivateDeviceInputTests(unittest.TestCase):
    SECRET = "00008110-PRIVATE-DEVICE-SUBJECT"

    def make_layout(self, root: Path):
        repo = root / "repo"
        repo.mkdir()
        private_dir = root / "home" / ".nembra-private"
        private_dir.parent.mkdir()
        return repo, private_dir

    def test_creates_exact_mode_private_file_without_echoing_secret(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repo, private_dir = self.make_layout(root)
            output = module.create_private_input(
                private_dir,
                repo,
                "es80-intended-device.udid",
                secret_provider=lambda: self.SECRET,
            )
            metadata = output.lstat()
            self.assertTrue(stat.S_ISREG(metadata.st_mode))
            self.assertEqual(stat.S_IMODE(metadata.st_mode), 0o600)
            self.assertEqual(metadata.st_nlink, 1)
            self.assertEqual(output.read_text(encoding="utf-8"), self.SECRET)
            self.assertEqual(stat.S_IMODE(private_dir.lstat().st_mode), 0o700)

    def test_existing_target_is_never_clobbered(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repo, private_dir = self.make_layout(root)
            private_dir.mkdir(mode=0o700)
            target = private_dir / "es80-intended-device.udid"
            target.write_text("KEEP", encoding="utf-8")
            target.chmod(0o600)
            with self.assertRaisesRegex(module.PrivateInputError, "already-exists"):
                module.create_private_input(
                    private_dir,
                    repo,
                    target.name,
                    secret_provider=lambda: self.SECRET,
                )
            self.assertEqual(target.read_text(encoding="utf-8"), "KEEP")

    def test_symlinked_ancestor_is_rejected_before_secret_provider_runs(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repo, private_dir = self.make_layout(root)
            real_home = root / "real-home"
            real_home.mkdir()
            link_home = root / "linked-home"
            try:
                link_home.symlink_to(real_home, target_is_directory=True)
            except (OSError, NotImplementedError) as error:
                self.skipTest(str(error))
            called = False

            def secret_provider():
                nonlocal called
                called = True
                return self.SECRET

            with self.assertRaises(module.PrivateInputError):
                module.create_private_input(
                    link_home / ".nembra-private",
                    repo,
                    "es80-intended-device.udid",
                    secret_provider=secret_provider,
                )
            self.assertFalse(called)

    def test_repository_contained_private_directory_is_rejected_before_secret(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repo = root / "repo"
            repo.mkdir()
            private_dir = repo / ".nembra-private"
            called = False

            def secret_provider():
                nonlocal called
                called = True
                return self.SECRET

            with self.assertRaisesRegex(module.PrivateInputError, "traverses-source-repository"):
                module.create_private_input(
                    private_dir,
                    repo,
                    "es80-intended-device.udid",
                    secret_provider=secret_provider,
                )
            self.assertFalse(called)

    def test_parent_path_retarget_after_create_fails_closed_and_cleans_original(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repo, private_dir = self.make_layout(root)
            moved_dir = private_dir.parent / ".nembra-private-original"
            replacement = private_dir.parent / ".nembra-private-replacement"

            def retarget():
                private_dir.rename(moved_dir)
                replacement.mkdir(mode=0o700)
                replacement.rename(private_dir)

            with self.assertRaisesRegex(module.PrivateInputError, "private-directory-path-retargeted"):
                module.create_private_input(
                    private_dir,
                    repo,
                    "es80-intended-device.udid",
                    secret_provider=lambda: self.SECRET,
                    after_create_hook=retarget,
                )

            self.assertFalse((moved_dir / "es80-intended-device.udid").exists())
            self.assertFalse((private_dir / "es80-intended-device.udid").exists())

    def test_surrounding_whitespace_is_rejected_and_no_file_is_created(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repo, private_dir = self.make_layout(root)
            with self.assertRaisesRegex(module.PrivateInputError, "surrounding-whitespace"):
                module.create_private_input(
                    private_dir,
                    repo,
                    "es80-intended-device.udid",
                    secret_provider=lambda: self.SECRET + "\n",
                )
            self.assertFalse((private_dir / "es80-intended-device.udid").exists())

    def test_partial_write_failure_removes_secret_bearing_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repo, private_dir = self.make_layout(root)
            target = private_dir / "es80-intended-device.udid"
            real_write = os.write
            write_calls = 0

            def fail_after_prefix(descriptor: int, payload: bytes) -> int:
                nonlocal write_calls
                write_calls += 1
                if write_calls == 1:
                    prefix = payload[:4]
                    return real_write(descriptor, prefix)
                raise OSError("simulated private-input write failure")

            with mock.patch.object(module.os, "write", side_effect=fail_after_prefix):
                with self.assertRaisesRegex(OSError, "simulated private-input write failure"):
                    module.create_private_input(
                        private_dir,
                        repo,
                        target.name,
                        secret_provider=lambda: self.SECRET,
                    )

            self.assertGreaterEqual(write_calls, 2)
            self.assertFalse(
                target.exists(),
                "failed private-input acquisition retained a partial secret-bearing file",
            )


if __name__ == "__main__":
    unittest.main()
