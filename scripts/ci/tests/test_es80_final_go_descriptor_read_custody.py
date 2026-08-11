#!/usr/bin/env python3
"""Regression witnesses for descriptor-bound Final-GO physical tree reads."""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
PRIVATE = ROOT / "scripts/ci/es80_authenticated_stationary_private_review_final_go.py"
SPEC = importlib.util.spec_from_file_location("nembra_final_go_descriptor_read", PRIVATE)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load current Final-GO candidate authority")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class FinalGoDescriptorReadCustodyTests(unittest.TestCase):
    def test_regular_replacement_at_descriptor_open_boundary_is_rejected(self) -> None:
        accepted_payload = b"accepted-final-go-source\n"
        replacement_payload = b"replacement-must-not-be-admitted\n"
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-descriptor-race-") as temporary:
            root = Path(temporary).resolve(strict=True)
            relative = "NembraApp/App/Capture.swift"
            path = root / relative
            escaped = root / "NembraApp/App/Capture.accepted.swift"
            path.parent.mkdir(parents=True)
            path.write_bytes(accepted_payload)
            path.chmod(0o644)

            original_open = MODULE.os.open
            attack_fired = False

            def interpose_open(subject, flags, mode=0o777, *, dir_fd=None):
                nonlocal attack_fired
                is_final_read = (
                    subject == path.name
                    and dir_fd is not None
                    and not (flags & MODULE.os.O_DIRECTORY)
                    and not (flags & MODULE.os.O_WRONLY)
                    and not (flags & MODULE.os.O_RDWR)
                )
                if is_final_read and not attack_fired:
                    attack_fired = True
                    os.rename(path, escaped)
                    replacement = original_open(
                        path,
                        MODULE.os.O_WRONLY | MODULE.os.O_CREAT | MODULE.os.O_EXCL | getattr(MODULE.os, "O_CLOEXEC", 0),
                        0o644,
                    )
                    try:
                        os.write(replacement, replacement_payload)
                        os.fsync(replacement)
                    finally:
                        os.close(replacement)
                if dir_fd is None:
                    return original_open(subject, flags, mode)
                return original_open(subject, flags, mode, dir_fd=dir_fd)

            MODULE.os.open = interpose_open
            try:
                with self.assertRaises(
                    RuntimeError,
                    msg="Final-GO admitted a replacement regular inode opened after pathname admission",
                ):
                    MODULE._read_physical_payload(root, relative, b"100644")
            finally:
                MODULE.os.open = original_open

            self.assertTrue(attack_fired, "fixture did not interpose at descriptor open boundary")
            self.assertEqual(escaped.read_bytes(), accepted_payload)
            self.assertEqual(path.read_bytes(), replacement_payload)

    def test_symlink_replacement_at_readlink_boundary_is_rejected(self) -> None:
        accepted_target = "../Resources/accepted.json"
        replacement_target = "../Resources/replacement.json"
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-symlink-descriptor-race-") as temporary:
            root = Path(temporary).resolve(strict=True)
            relative = "NembraApp/App/CurrentConfig"
            path = root / relative
            escaped = root / "NembraApp/App/CurrentConfig.accepted"
            path.parent.mkdir(parents=True)
            os.symlink(accepted_target, path)

            original_readlink = MODULE.os.readlink
            attack_fired = False

            def interpose_readlink(subject, *args, **kwargs):
                nonlocal attack_fired
                if subject == path.name and kwargs.get("dir_fd") is not None and not attack_fired:
                    attack_fired = True
                    os.rename(path, escaped)
                    os.symlink(replacement_target, path)
                return original_readlink(subject, *args, **kwargs)

            MODULE.os.readlink = interpose_readlink
            try:
                with self.assertRaises(
                    RuntimeError,
                    msg="Final-GO admitted a replacement symlink occupying the admitted pathname",
                ):
                    MODULE._read_physical_payload(root, relative, b"120000")
            finally:
                MODULE.os.readlink = original_readlink

            self.assertTrue(attack_fired, "fixture did not interpose at descriptor-bound readlink boundary")
            self.assertEqual(os.readlink(escaped), accepted_target)
            self.assertEqual(os.readlink(path), replacement_target)

    def test_stable_regular_and_symlink_payloads_are_admitted(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-descriptor-stable-") as temporary:
            root = Path(temporary).resolve(strict=True)
            regular = root / "NembraApp/App/Capture.swift"
            link = root / "NembraApp/App/CurrentConfig"
            regular.parent.mkdir(parents=True)
            regular.write_bytes(b"stable\n")
            regular.chmod(0o644)
            os.symlink("../Resources/config.json", link)

            regular_payload, regular_metadata = MODULE._read_physical_payload(
                root, "NembraApp/App/Capture.swift", b"100644"
            )
            link_payload, link_metadata = MODULE._read_physical_payload(
                root, "NembraApp/App/CurrentConfig", b"120000"
            )
            self.assertEqual(regular_payload, b"stable\n")
            self.assertGreater(regular_metadata.st_ino, 0)
            self.assertEqual(link_payload, b"../Resources/config.json")
            self.assertGreater(link_metadata.st_ino, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
