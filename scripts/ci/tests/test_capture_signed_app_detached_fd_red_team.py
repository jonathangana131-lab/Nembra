#!/usr/bin/env python3
"""Red-team the build-origin helper's descendant retirement boundary on macOS.

The production helper revokes the supplementary-group pathname capability by
changing the DerivedData root to root:root mode 0700, then retires its original
build process group before fingerprinting. POSIX permission changes do not revoke
an already-open writable descriptor. This witness creates a build descendant that
opens the product while legitimately carrying the one-run group capability, moves
itself into a new session, survives the original-process-group retirement, and
then writes through the held descriptor after the root lock.

Validation only. It does not build, sign, install, launch, scan, or touch hardware.
"""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import shutil
import stat
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[3]
HELPER_PATH = ROOT / "scripts/ci/capture_signed_app_build_origin_custody.py"
SPEC = importlib.util.spec_from_file_location("nembra_signed_origin_detached_fd", HELPER_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load signed-app build-origin helper")
HELPER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(HELPER)


@unittest.skipUnless(sys.platform == "darwin" and os.geteuid() == 0, "requires root on macOS")
class SignedAppDetachedFDRedTeamTests(unittest.TestCase):
    def test_detached_descendant_keeps_open_product_fd_after_root_lock_and_process_group_retirement(self) -> None:
        _user, uid, gid, _home, groups = HELPER._invoking_identity()
        capability_gid = HELPER._choose_capability_gid(groups)
        derived = HELPER._prepare_derived(HELPER._require_real_private_tmp(), capability_gid)
        product = derived / "held-product.bin"

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
                    os.setsid()  # mirrors production start_new_session=True
                    os.setgroups(sorted(set(groups) | {capability_gid}))
                    os.setgid(gid)
                    os.setuid(uid)
                    fd = os.open(product, os.O_CREAT | os.O_WRONLY | os.O_TRUNC, 0o644)
                    os.write(fd, b"ACCEPTED_BUILD_OUTPUT\n")
                    os.fsync(fd)

                    detached_pid = os.fork()
                    if detached_pid == 0:
                        try:
                            # We are not the current process-group leader, so this
                            # escapes the launcher's session/process group while
                            # retaining both credentials and the already-open FD.
                            os.setsid()
                            os.write(ready_w, b"R")
                            if os.read(go_r, 1) != b"G":
                                os._exit(91)
                            os.lseek(fd, 0, os.SEEK_END)
                            os.write(fd, b"DETACHED_AFTER_ROOT_LOCK\n")
                            os.fsync(fd)
                            os.write(result_w, b"W")
                            os.close(fd)
                            os._exit(0)
                        except BaseException:
                            try:
                                os.write(result_w, b"E")
                            except OSError:
                                pass
                            os._exit(92)

                    os.close(fd)
                    # Direct build process returns while its escaped descendant
                    # remains alive, matching the authority gap under test.
                    os._exit(0)
                except BaseException:
                    os._exit(93)

            os.close(ready_w)
            os.close(go_r)
            os.close(result_w)
            _, launcher_status = os.waitpid(launcher_pid, 0)
            self.assertTrue(os.WIFEXITED(launcher_status))
            self.assertEqual(os.WEXITSTATUS(launcher_status), 0)
            self.assertEqual(os.read(ready_r, 1), b"R", "detached writer never acquired the build-output descriptor")

            before = product.read_bytes()
            self.assertEqual(before, b"ACCEPTED_BUILD_OUTPUT\n")

            # Exact production ordering on the reviewed parent: close pathname
            # authority first, then retire only the original process group.
            os.chown(derived, 0, 0)
            os.chmod(derived, 0o700)
            HELPER._terminate_remaining_process_group(launcher_pid)

            # A normal pathname reopen under the retired capability is blocked;
            # the detached process nonetheless still owns its pre-lock FD.
            os.write(go_w, b"G")
            self.assertEqual(os.read(result_r, 1), b"W", "detached writer did not survive long enough to exercise its held FD")

            deadline = time.monotonic() + 2.0
            while time.monotonic() < deadline:
                after = product.read_bytes()
                if b"DETACHED_AFTER_ROOT_LOCK" in after:
                    break
                time.sleep(0.02)
            else:
                self.fail("root lock + original process-group retirement unexpectedly revoked the detached open FD")

            self.assertNotEqual(after, before)
            self.assertIn(b"DETACHED_AFTER_ROOT_LOCK", after)
        finally:
            for descriptor in (ready_r, ready_w, go_r, go_w, result_r, result_w):
                try:
                    os.close(descriptor)
                except OSError:
                    pass
            shutil.rmtree(derived, ignore_errors=True)


if __name__ == "__main__":
    unittest.main(verbosity=2)
