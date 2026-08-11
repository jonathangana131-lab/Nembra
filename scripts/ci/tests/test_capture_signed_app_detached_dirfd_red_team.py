#!/usr/bin/env python3
"""Expected-red witness for detached directory-FD compiler-output authority.

The current signed-app build-origin helper revokes future pathname traversal by
changing only the protected DerivedData root to root:root mode 0700, then retires
the original build process group. A build descendant can instead retain an open
file descriptor to a writable nested product directory, detach into a new session,
and later create/replace directory entries relative to that held descriptor without
traversing the now-locked DerivedData root.

This is validation-only. Success means the attack was demonstrated and production
must not treat top-level pathname revocation as complete output-writer retirement.
"""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import select
import shutil
import sys
import time
import unittest

ROOT = Path(__file__).resolve().parents[3]
HELPER_PATH = ROOT / "scripts/ci/capture_signed_app_build_origin_custody.py"
SPEC = importlib.util.spec_from_file_location("nembra_signed_origin_dirfd_redteam", HELPER_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load signed-app build-origin helper")
HELPER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(HELPER)


def drop(uid: int, gid: int, groups: list[int]):
    normalized = sorted(set(groups))

    def apply() -> None:
        os.setgroups(normalized)
        os.setgid(gid)
        os.setuid(uid)

    return apply


@unittest.skipUnless(sys.platform == "darwin" and os.geteuid() == 0, "requires root on macOS")
class SignedAppDetachedDirectoryFDRedTeamTests(unittest.TestCase):
    def test_detached_writer_can_create_product_entry_through_held_directory_fd(self) -> None:
        _user, uid, gid, _home, groups = HELPER._invoking_identity()
        capability_gid = HELPER._choose_capability_gid(groups)
        derived = HELPER._prepare_derived(HELPER._require_real_private_tmp(), capability_gid)

        ready_r, ready_w = os.pipe()
        go_r, go_w = os.pipe()
        result_r, result_w = os.pipe()
        launcher_pid = -1
        try:
            launcher_pid = os.fork()
            if launcher_pid == 0:
                try:
                    os.close(ready_r)
                    os.close(go_w)
                    os.close(result_r)

                    # Mirrors production start_new_session=True plus the one-run
                    # supplementary build capability.
                    os.setsid()
                    os.setgroups(sorted(set(groups) | {capability_gid}))
                    os.setgid(gid)
                    os.setuid(uid)

                    bundle = derived / "Build/Products/Debug-iphoneos/Nembra Capture.app"
                    bundle.mkdir(parents=True)
                    original = bundle / "accepted.bin"
                    original.write_bytes(b"ORIGINAL_BUILD_OUTPUT\n")
                    bundle_fd = os.open(
                        bundle,
                        os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_CLOEXEC", 0),
                    )

                    detached_pid = os.fork()
                    if detached_pid == 0:
                        try:
                            # Escape the process group production currently retires,
                            # but retain the already-open nested product directory FD.
                            os.setsid()
                            os.write(ready_w, b"R")
                            if os.read(go_r, 1) != b"G":
                                os._exit(91)

                            succeeded = False
                            try:
                                late_fd = os.open(
                                    "late-entry.bin",
                                    os.O_CREAT | os.O_WRONLY | os.O_TRUNC,
                                    0o600,
                                    dir_fd=bundle_fd,
                                )
                                try:
                                    os.write(late_fd, b"DETACHED_DIRFD_WRITE\n")
                                    os.fsync(late_fd)
                                finally:
                                    os.close(late_fd)
                                succeeded = True
                            except OSError:
                                pass

                            os.write(result_w, b"1" if succeeded else b"0")
                            os.close(bundle_fd)
                            os._exit(0)
                        except BaseException:
                            try:
                                os.write(result_w, b"E")
                            except OSError:
                                pass
                            os._exit(92)

                    os.close(bundle_fd)
                    os._exit(0)
                except BaseException:
                    os._exit(93)

            os.close(ready_w)
            os.close(go_r)
            os.close(result_w)

            _, launcher_status = os.waitpid(launcher_pid, 0)
            self.assertTrue(os.WIFEXITED(launcher_status))
            self.assertEqual(os.WEXITSTATUS(launcher_status), 0)
            self.assertEqual(os.read(ready_r, 1), b"R", "detached directory-FD writer did not arm")

            bundle = derived / "Build/Products/Debug-iphoneos/Nembra Capture.app"
            original = bundle / "accepted.bin"
            late = bundle / "late-entry.bin"
            self.assertEqual(original.read_bytes(), b"ORIGINAL_BUILD_OUTPUT\n")
            self.assertFalse(late.exists())

            # Exact production revocation shape: only the DerivedData root loses
            # the one-run group/pathname capability before the original process
            # group is retired.
            os.chown(derived, 0, 0)
            os.chmod(derived, 0o700)
            HELPER._terminate_remaining_process_group(launcher_pid)

            # Confirm a fresh same-UID process cannot traverse the locked root.
            path_attack_pid = os.fork()
            if path_attack_pid == 0:
                try:
                    os.setgroups(sorted(set(groups)))
                    os.setgid(gid)
                    os.setuid(uid)
                    fd = os.open(str(bundle / "fresh-path-entry.bin"), os.O_CREAT | os.O_WRONLY, 0o600)
                    os.close(fd)
                    os._exit(0)
                except BaseException:
                    os._exit(1)
            _, path_status = os.waitpid(path_attack_pid, 0)
            self.assertTrue(os.WIFEXITED(path_status))
            self.assertNotEqual(os.WEXITSTATUS(path_status), 0, "fresh pathname write unexpectedly survived root lock")

            os.write(go_w, b"G")
            readable, _, _ = select.select([result_r], [], [], 3.0)
            self.assertTrue(readable, "detached directory-FD writer produced no post-lock result")
            result = os.read(result_r, 1)

            # EXPECTED-RED PRODUCT VERDICT: the current production boundary is
            # insufficient if the retained nested dirfd can still mint entries.
            self.assertEqual(result, b"1", f"detached directory-FD attack was not demonstrated: {result!r}")
            self.assertEqual(late.read_bytes(), b"DETACHED_DIRFD_WRITE\n")
            self.assertEqual(original.read_bytes(), b"ORIGINAL_BUILD_OUTPUT\n")
        finally:
            for descriptor in (ready_r, ready_w, go_r, go_w, result_r, result_w):
                try:
                    os.close(descriptor)
                except OSError:
                    pass
            time.sleep(0.05)
            shutil.rmtree(derived, ignore_errors=True)


if __name__ == "__main__":
    unittest.main(verbosity=2)
