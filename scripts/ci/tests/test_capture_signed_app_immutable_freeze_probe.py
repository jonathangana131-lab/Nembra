#!/usr/bin/env python3
"""Validate whether macOS immutable file state revokes pre-open compiler-output writes.

This is validation-only evidence for the signed-app compiler-output custody lane. The
production parent revokes future pathname opens by taking the protected DerivedData
root back to root:root mode 0700, but a detached descendant can retain a writable FD
or writable shared mapping that was created while it legitimately held the one-run
build capability. This probe asks a narrower mechanical question: after root takes
ownership of the produced file and sets UF_IMMUTABLE, can that already-open authority
still mutate the file?

No Xcode build, signing, device operation, Bluetooth, Tuya traffic, or physical action
occurs here.
"""
from __future__ import annotations

import importlib.util
import mmap
import os
from pathlib import Path
import select
import shutil
import stat
import sys
import time
import unittest

ROOT = Path(__file__).resolve().parents[3]
HELPER_PATH = ROOT / "scripts/ci/capture_signed_app_build_origin_custody.py"
SPEC = importlib.util.spec_from_file_location("nembra_signed_origin_immutable_probe", HELPER_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load signed-app build-origin helper")
HELPER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(HELPER)


@unittest.skipUnless(sys.platform == "darwin" and os.geteuid() == 0, "requires root on macOS")
class SignedAppImmutableFreezeProbeTests(unittest.TestCase):
    def test_root_owned_immutable_file_rejects_preopened_fd_and_mmap_writes(self) -> None:
        _user, uid, gid, _home, groups = HELPER._invoking_identity()
        capability_gid = HELPER._choose_capability_gid(groups)
        derived = HELPER._prepare_derived(HELPER._require_real_private_tmp(), capability_gid)
        product = derived / "held-product.bin"
        initial = b"ACCEPTED_BUILD_OUTPUT\n" + (b"." * 4074)

        ready_r, ready_w = os.pipe()
        go_r, go_w = os.pipe()
        result_r, result_w = os.pipe()
        launcher_pid = -1
        immutable_set = False
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

                    fd = os.open(product, os.O_CREAT | os.O_RDWR | os.O_TRUNC, 0o644)
                    os.write(fd, initial)
                    os.fsync(fd)
                    mapping = mmap.mmap(fd, len(initial), access=mmap.ACCESS_WRITE)

                    detached_pid = os.fork()
                    if detached_pid == 0:
                        try:
                            os.setsid()
                            os.write(ready_w, b"R")
                            if os.read(go_r, 1) != b"G":
                                os._exit(91)

                            succeeded = 0
                            fchflags = getattr(os, "fchflags", None)
                            if callable(fchflags):
                                try:
                                    fchflags(fd, 0)
                                    succeeded |= 1
                                except OSError:
                                    pass

                            try:
                                os.lseek(fd, 0, os.SEEK_END)
                                os.write(fd, b"FD_AFTER_FREEZE\n")
                                os.fsync(fd)
                                succeeded |= 2
                            except OSError:
                                pass

                            try:
                                mapping[0:4] = b"MMAP"
                                mapping.flush()
                                succeeded |= 4
                            except (BufferError, OSError, ValueError):
                                pass

                            try:
                                os.write(result_w, bytes([succeeded]))
                            except OSError:
                                pass
                            mapping.close()
                            os.close(fd)
                            os._exit(0)
                        except BaseException:
                            try:
                                os.write(result_w, b"E")
                            except OSError:
                                pass
                            os._exit(92)

                    mapping.close()
                    os.close(fd)
                    os._exit(0)
                except BaseException:
                    os._exit(93)

            os.close(ready_w)
            os.close(go_r)
            os.close(result_w)
            _, launcher_status = os.waitpid(launcher_pid, 0)
            self.assertTrue(os.WIFEXITED(launcher_status))
            self.assertEqual(os.WEXITSTATUS(launcher_status), 0)
            self.assertEqual(os.read(ready_r, 1), b"R", "detached writer did not arm FD+mmap authority")
            self.assertEqual(product.read_bytes(), initial)

            # Model the stronger filesystem freeze under consideration. Root ownership
            # prevents the former field owner from clearing UF_IMMUTABLE through its
            # held descriptor; the immutable vnode flag is then asked to stop writes
            # through both an already-open FD and an already-established shared map.
            os.chown(product, 0, 0)
            os.chown(derived, 0, 0)
            os.chmod(derived, 0o700)
            immutable_flag = getattr(stat, "UF_IMMUTABLE", None)
            self.assertIsNotNone(immutable_flag, "Python/macOS exposes no UF_IMMUTABLE flag")
            os.chflags(product, int(immutable_flag))
            immutable_set = True
            self.assertTrue(product.stat().st_flags & int(immutable_flag))

            HELPER._terminate_remaining_process_group(launcher_pid)
            os.write(go_w, b"G")

            readable, _, _ = select.select([result_r], [], [], 3.0)
            self.assertTrue(readable, "detached writer produced no post-freeze result")
            result = os.read(result_r, 1)
            self.assertEqual(result, b"\x00", f"post-freeze authority unexpectedly succeeded: {result!r}")

            # Give any delayed mmap writeback a chance to become visible before the
            # final byte comparison. A green result must preserve the exact bytes.
            time.sleep(0.2)
            self.assertEqual(product.read_bytes(), initial)
        finally:
            for descriptor in (ready_r, ready_w, go_r, go_w, result_r, result_w):
                try:
                    os.close(descriptor)
                except OSError:
                    pass
            if immutable_set:
                try:
                    os.chflags(product, 0)
                except OSError:
                    pass
            shutil.rmtree(derived, ignore_errors=True)


if __name__ == "__main__":
    unittest.main(verbosity=2)
