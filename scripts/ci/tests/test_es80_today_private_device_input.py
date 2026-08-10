#!/usr/bin/env python3
from __future__ import annotations

from contextlib import redirect_stderr, redirect_stdout
import importlib.util
import io
import os
from pathlib import Path
import stat
import sys
import tempfile
import unittest
from unittest import mock
import warnings

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

    def test_existing_target_is_rejected_before_secret_provider_runs(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repo, private_dir = self.make_layout(root)
            private_dir.mkdir(mode=0o700)
            target = private_dir / "es80-intended-device.udid"
            target.write_text("KEEP", encoding="utf-8")
            target.chmod(0o600)
            called = False

            def secret_provider():
                nonlocal called
                called = True
                return self.SECRET

            with self.assertRaisesRegex(module.PrivateInputError, "already-exists"):
                module.create_private_input(
                    private_dir,
                    repo,
                    target.name,
                    secret_provider=secret_provider,
                )
            self.assertFalse(called)
            self.assertEqual(target.read_text(encoding="utf-8"), "KEEP")

    def test_target_appearing_after_precheck_is_caught_by_exclusive_create(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repo, private_dir = self.make_layout(root)
            target = private_dir / "es80-intended-device.udid"

            def secret_provider():
                target.write_text("RACE", encoding="utf-8")
                target.chmod(0o600)
                return self.SECRET

            with self.assertRaisesRegex(module.PrivateInputError, "already-exists"):
                module.create_private_input(
                    private_dir,
                    repo,
                    target.name,
                    secret_provider=secret_provider,
                )
            self.assertEqual(target.read_text(encoding="utf-8"), "RACE")

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

            original = moved_dir / "es80-intended-device.udid"
            self.assertTrue(original.exists())
            self.assertEqual(original.read_bytes(), b"")
            self.assertFalse((private_dir / "es80-intended-device.udid").exists())

    def test_write_failure_after_creation_removes_created_file(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repo, private_dir = self.make_layout(root)
            target = private_dir / "es80-intended-device.udid"

            with mock.patch.object(module, "_write_all", side_effect=OSError("injected write failure")):
                with self.assertRaisesRegex(OSError, "injected write failure"):
                    module.create_private_input(
                        private_dir,
                        repo,
                        target.name,
                        secret_provider=lambda: self.SECRET,
                    )

            self.assertFalse(target.exists())

    def test_fsync_failure_after_creation_removes_created_file(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repo, private_dir = self.make_layout(root)
            target = private_dir / "es80-intended-device.udid"
            real_fsync = os.fsync
            calls = 0

            def fail_primary_fsync(descriptor: int) -> None:
                nonlocal calls
                calls += 1
                if calls == 1:
                    raise OSError("injected fsync failure")
                real_fsync(descriptor)

            with mock.patch.object(module.os, "fsync", side_effect=fail_primary_fsync):
                with self.assertRaisesRegex(OSError, "injected fsync failure"):
                    module.create_private_input(
                        private_dir,
                        repo,
                        target.name,
                        secret_provider=lambda: self.SECRET,
                    )

            self.assertFalse(target.exists())

    def test_failure_cleanup_never_unlinks_a_path_replacement(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repo, private_dir = self.make_layout(root)
            target = private_dir / "es80-intended-device.udid"

            def replace_then_fail(_descriptor: int, _payload: bytes) -> None:
                target.unlink()
                target.write_text("KEEP", encoding="utf-8")
                target.chmod(0o600)
                raise OSError("injected write failure after replacement")

            with mock.patch.object(module, "_write_all", side_effect=replace_then_fail):
                with self.assertRaisesRegex(OSError, "injected write failure after replacement"):
                    module.create_private_input(
                        private_dir,
                        repo,
                        target.name,
                        secret_provider=lambda: self.SECRET,
                    )

            self.assertTrue(target.exists())
            self.assertEqual(target.read_text(encoding="utf-8"), "KEEP")

    def test_terminal_abort_after_secret_write_removes_created_file(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repo, private_dir = self.make_layout(root)
            target = private_dir / "es80-intended-device.udid"
            real_write_all = module._write_all

            def write_then_interrupt(descriptor: int, payload: bytes) -> None:
                real_write_all(descriptor, payload)
                raise KeyboardInterrupt()

            with mock.patch.object(module, "_write_all", side_effect=write_then_interrupt):
                with self.assertRaises(KeyboardInterrupt):
                    module.create_private_input(
                        private_dir,
                        repo,
                        target.name,
                        secret_provider=lambda: self.SECRET,
                    )

            self.assertFalse(
                target.exists(),
                "terminal abort retained a secret-bearing intended-device file",
            )

    def test_partial_write_unlink_failure_leaves_only_durably_scrubbed_inode(self):
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
                    return real_write(descriptor, payload[:4])
                raise OSError("simulated private-input write failure")

            with (
                mock.patch.object(module.os, "write", side_effect=fail_after_prefix),
                mock.patch.object(module.os, "unlink", side_effect=OSError("simulated unlink failure")),
            ):
                with self.assertRaisesRegex(OSError, "simulated private-input write failure"):
                    module.create_private_input(
                        private_dir,
                        repo,
                        target.name,
                        secret_provider=lambda: self.SECRET,
                    )

            self.assertTrue(target.exists())
            self.assertEqual(target.stat().st_size, 0)
            self.assertEqual(target.read_bytes(), b"")

    def test_partial_write_cleanup_file_fsync_failure_falls_back_to_durable_unlink(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repo, private_dir = self.make_layout(root)
            target = private_dir / "es80-intended-device.udid"
            real_write = os.write
            real_fsync = os.fsync
            write_calls = 0
            cleanup_fsync_calls = 0

            def fail_after_prefix(descriptor: int, payload: bytes) -> int:
                nonlocal write_calls
                write_calls += 1
                if write_calls == 1:
                    return real_write(descriptor, payload[:4])
                raise OSError("simulated private-input write failure")

            def fail_first_cleanup_fsync(descriptor: int) -> None:
                nonlocal cleanup_fsync_calls
                cleanup_fsync_calls += 1
                if cleanup_fsync_calls == 1:
                    raise OSError("simulated cleanup file fsync failure")
                real_fsync(descriptor)

            with (
                mock.patch.object(module.os, "write", side_effect=fail_after_prefix),
                mock.patch.object(module.os, "fsync", side_effect=fail_first_cleanup_fsync),
            ):
                with self.assertRaisesRegex(OSError, "simulated private-input write failure"):
                    module.create_private_input(
                        private_dir,
                        repo,
                        target.name,
                        secret_provider=lambda: self.SECRET,
                    )

            self.assertGreaterEqual(cleanup_fsync_calls, 2)
            self.assertFalse(target.exists())

    def test_unlink_fallback_rejects_hard_link_created_during_unlink(self):
        if os.link not in os.supports_dir_fd:
            self.skipTest("descriptor-relative hard links unavailable")

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repo, private_dir = self.make_layout(root)
            target = private_dir / "es80-intended-device.udid"
            retained = private_dir / "retained-copy.udid"
            real_write = os.write
            real_unlink = os.unlink
            real_link = os.link
            write_calls = 0

            def fail_after_prefix(descriptor: int, payload: bytes) -> int:
                nonlocal write_calls
                write_calls += 1
                if write_calls == 1:
                    return real_write(descriptor, payload[:4])
                raise OSError("simulated private-input write failure")

            def add_link_then_unlink(filename: str, *, dir_fd: int) -> None:
                real_link(
                    filename,
                    retained.name,
                    src_dir_fd=dir_fd,
                    dst_dir_fd=dir_fd,
                    follow_symlinks=False,
                )
                real_unlink(filename, dir_fd=dir_fd)

            with (
                mock.patch.object(module.os, "write", side_effect=fail_after_prefix),
                mock.patch.object(module.os, "ftruncate", side_effect=OSError("simulated scrub failure")),
                mock.patch.object(module.os, "unlink", side_effect=add_link_then_unlink),
            ):
                with self.assertRaisesRegex(
                    module.PrivateInputError,
                    "private-intended-device-cleanup-failed",
                ) as raised:
                    module.create_private_input(
                        private_dir,
                        repo,
                        target.name,
                        secret_provider=lambda: self.SECRET,
                    )

            self.assertNotIn(self.SECRET, str(raised.exception))
            self.assertFalse(target.exists())
            self.assertTrue(retained.exists())

    def test_cleanup_that_cannot_scrub_or_unlink_surfaces_secret_free_blocker(self):
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
                    return real_write(descriptor, payload[:4])
                raise OSError("simulated private-input write failure")

            with (
                mock.patch.object(module.os, "write", side_effect=fail_after_prefix),
                mock.patch.object(module.os, "ftruncate", side_effect=OSError("simulated scrub failure")),
                mock.patch.object(module.os, "unlink", side_effect=OSError("simulated unlink failure")),
            ):
                with self.assertRaisesRegex(
                    module.PrivateInputError,
                    "private-intended-device-cleanup-failed",
                ) as raised:
                    module.create_private_input(
                        private_dir,
                        repo,
                        target.name,
                        secret_provider=lambda: self.SECRET,
                    )

            self.assertNotIn(self.SECRET, str(raised.exception))
            self.assertTrue(target.exists())

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

    def test_secure_provider_refuses_getpass_echo_fallback_without_returning_secret(self):
        fallback_returned = False

        def warned_getpass(_prompt: str) -> str:
            nonlocal fallback_returned
            warnings.warn("Can not control echo on the terminal.", module.getpass.GetPassWarning)
            fallback_returned = True
            return self.SECRET

        stdout = io.StringIO()
        stderr = io.StringIO()
        with mock.patch.object(module.getpass, "getpass", side_effect=warned_getpass):
            with redirect_stdout(stdout), redirect_stderr(stderr):
                with self.assertRaisesRegex(module.PrivateInputError, "secure-terminal-input-unavailable"):
                    module._secure_secret_provider()

        self.assertFalse(fallback_returned)
        self.assertNotIn(self.SECRET, stdout.getvalue())
        self.assertNotIn(self.SECRET, stderr.getvalue())

    def test_secure_provider_echo_failure_creates_no_private_file(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repo, private_dir = self.make_layout(root)

            def warned_getpass(_prompt: str) -> str:
                warnings.warn("Can not control echo on the terminal.", module.getpass.GetPassWarning)
                return self.SECRET

            with mock.patch.object(module.getpass, "getpass", side_effect=warned_getpass):
                with self.assertRaisesRegex(module.PrivateInputError, "secure-terminal-input-unavailable"):
                    module.create_private_input(
                        private_dir,
                        repo,
                        "es80-intended-device.udid",
                        secret_provider=module._secure_secret_provider,
                    )

            self.assertFalse((private_dir / "es80-intended-device.udid").exists())

    def test_secure_provider_eof_fails_closed(self):
        with mock.patch.object(module.getpass, "getpass", side_effect=EOFError):
            with self.assertRaisesRegex(module.PrivateInputError, "secure-terminal-input-unavailable"):
                module._secure_secret_provider()


if __name__ == "__main__":
    unittest.main()
