#!/usr/bin/env python3
from __future__ import annotations

import contextlib
import importlib.util
import io
import os
from pathlib import Path
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

    def test_existing_target_is_rejected_before_secret_provider_runs(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repo, private_dir = self.make_layout(root)
            private_dir.mkdir(mode=0o700)
            target = private_dir / "es80-intended-device.udid"
            target.write_text("KEEP", encoding="utf-8")
            target.chmod(0o600)
            provider_called = False

            def secret_provider() -> str:
                nonlocal provider_called
                provider_called = True
                return self.SECRET

            with self.assertRaisesRegex(module.PrivateInputError, "already-exists"):
                module.create_private_input(
                    private_dir,
                    repo,
                    target.name,
                    secret_provider=secret_provider,
                )
            self.assertFalse(provider_called)
            self.assertEqual(target.read_text(encoding="utf-8"), "KEEP")

    def test_target_appearing_after_precheck_is_still_rejected_by_exclusive_create(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repo, private_dir = self.make_layout(root)
            target = private_dir / "es80-intended-device.udid"

            def secret_provider() -> str:
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

    def test_parent_path_retarget_after_create_fails_closed_and_scrubs_original(self):
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

    def test_partial_write_failure_leaves_only_durably_scrubbed_file(self):
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

            with mock.patch.object(module.os, "write", side_effect=fail_after_prefix):
                with self.assertRaisesRegex(OSError, "simulated private-input write failure"):
                    module.create_private_input(
                        private_dir,
                        repo,
                        target.name,
                        secret_provider=lambda: self.SECRET,
                    )

            self.assertGreaterEqual(write_calls, 2)
            self.assertTrue(target.exists())
            self.assertEqual(target.read_bytes(), b"")

    def test_file_fsync_failure_leaves_only_durably_scrubbed_file(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repo, private_dir = self.make_layout(root)
            target = private_dir / "es80-intended-device.udid"
            real_fsync = os.fsync
            fsync_calls = 0

            def fail_first_fsync(descriptor: int) -> None:
                nonlocal fsync_calls
                fsync_calls += 1
                if fsync_calls == 1:
                    raise OSError("simulated private-input fsync failure")
                real_fsync(descriptor)

            with mock.patch.object(module.os, "fsync", side_effect=fail_first_fsync):
                with self.assertRaisesRegex(OSError, "simulated private-input fsync failure"):
                    module.create_private_input(
                        private_dir,
                        repo,
                        target.name,
                        secret_provider=lambda: self.SECRET,
                    )

            self.assertGreaterEqual(fsync_calls, 2)
            self.assertTrue(target.exists())
            self.assertEqual(target.read_bytes(), b"")

    def test_cleanup_never_uses_pathname_unlink(self):
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
                mock.patch.object(
                    module.os,
                    "unlink",
                    side_effect=AssertionError("cleanup must not unlink a mutable pathname"),
                ),
            ):
                with self.assertRaisesRegex(OSError, "simulated private-input write failure"):
                    module.create_private_input(
                        private_dir,
                        repo,
                        target.name,
                        secret_provider=lambda: self.SECRET,
                    )

            self.assertTrue(target.exists())
            self.assertEqual(target.read_bytes(), b"")

    def test_transient_cleanup_fsync_failure_retries_descriptor_scrub(self):
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
            self.assertTrue(target.exists())
            self.assertEqual(target.read_bytes(), b"")

    def test_retargeted_replacement_is_never_deleted_and_original_inode_is_scrubbed(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repo, private_dir = self.make_layout(root)
            target = private_dir / "es80-intended-device.udid"
            retained = private_dir / "retained-original.udid"
            real_write = os.write
            write_calls = 0

            def retarget_then_fail(descriptor: int, payload: bytes) -> int:
                nonlocal write_calls
                write_calls += 1
                if write_calls == 1:
                    return real_write(descriptor, payload[:4])
                target.rename(retained)
                target.write_bytes(b"KEEP")
                target.chmod(0o600)
                raise OSError("simulated private-input write failure")

            with mock.patch.object(module.os, "write", side_effect=retarget_then_fail):
                with self.assertRaisesRegex(OSError, "simulated private-input write failure"):
                    module.create_private_input(
                        private_dir,
                        repo,
                        target.name,
                        secret_provider=lambda: self.SECRET,
                    )

            self.assertEqual(target.read_bytes(), b"KEEP")
            self.assertTrue(retained.exists())
            self.assertEqual(retained.read_bytes(), b"")

    def test_failed_scrub_preserves_unproven_replacement_and_surfaces_blocker(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repo, private_dir = self.make_layout(root)
            target = private_dir / "es80-intended-device.udid"
            retained = private_dir / "retained-original.udid"
            real_write = os.write
            write_calls = 0

            def retarget_then_fail(descriptor: int, payload: bytes) -> int:
                nonlocal write_calls
                write_calls += 1
                if write_calls == 1:
                    return real_write(descriptor, payload[:4])
                target.rename(retained)
                target.write_bytes(b"KEEP")
                target.chmod(0o600)
                raise OSError("simulated private-input write failure")

            with (
                mock.patch.object(module.os, "write", side_effect=retarget_then_fail),
                mock.patch.object(module.os, "ftruncate", side_effect=OSError("simulated scrub failure")),
                mock.patch.object(
                    module.os,
                    "unlink",
                    side_effect=AssertionError("cleanup must not unlink a mutable pathname"),
                ),
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
            self.assertEqual(target.read_bytes(), b"KEEP")
            self.assertTrue(retained.exists())
            self.assertGreater(retained.stat().st_size, 0)

    def test_cleanup_that_cannot_scrub_surfaces_secret_free_blocker(self):
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
                mock.patch.object(
                    module.os,
                    "unlink",
                    side_effect=AssertionError("cleanup must not unlink a mutable pathname"),
                ),
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
            self.assertGreater(target.stat().st_size, 0)

    def test_cli_refuses_echoed_getpass_fallback_before_consuming_secret(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repo, private_dir = self.make_layout(root)
            target = private_dir / "es80-intended-device.udid"
            fallback_consumed = False

            def simulated_echo_fallback(_prompt: str) -> str:
                nonlocal fallback_consumed
                module.warnings.warn(
                    "simulated terminal cannot disable echo",
                    module.getpass.GetPassWarning,
                )
                fallback_consumed = True
                return self.SECRET

            stdout = io.StringIO()
            stderr = io.StringIO()
            with mock.patch.object(module.getpass, "getpass", side_effect=simulated_echo_fallback):
                with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                    status = module.main(
                        [
                            "--private-directory",
                            str(private_dir),
                            "--source-repo",
                            str(repo),
                        ]
                    )

            combined = stdout.getvalue() + stderr.getvalue()
            self.assertEqual(status, 2)
            self.assertFalse(fallback_consumed)
            self.assertFalse(target.exists())
            self.assertIn("secure-terminal-input-unavailable", stderr.getvalue())
            self.assertNotIn(self.SECRET, combined)

    def test_cli_refuses_eof_terminal_input_without_creating_file(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repo, private_dir = self.make_layout(root)
            target = private_dir / "es80-intended-device.udid"
            stdout = io.StringIO()
            stderr = io.StringIO()

            with mock.patch.object(module.getpass, "getpass", side_effect=EOFError("simulated EOF")):
                with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                    status = module.main(
                        [
                            "--private-directory",
                            str(private_dir),
                            "--source-repo",
                            str(repo),
                        ]
                    )

            combined = stdout.getvalue() + stderr.getvalue()
            self.assertEqual(status, 2)
            self.assertFalse(target.exists())
            self.assertIn("secure-terminal-input-unavailable", stderr.getvalue())
            self.assertNotIn(self.SECRET, combined)


if __name__ == "__main__":
    unittest.main()
