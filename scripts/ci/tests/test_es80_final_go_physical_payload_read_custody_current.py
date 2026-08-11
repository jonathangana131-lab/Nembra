#!/usr/bin/env python3
"""Validation of current Final-GO descriptor-bound physical payload custody."""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
PRIVATE = ROOT / "scripts/ci/es80_authenticated_stationary_private_review_final_go.py"


def load_module():
    spec = importlib.util.spec_from_file_location("nembra_final_go_read_custody_current", PRIVATE)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load current Final-GO candidate authority")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class FinalGoPhysicalPayloadReadCustodyCurrentTests(unittest.TestCase):
    def test_regular_final_component_swap_after_admission_is_rejected(self) -> None:
        module = load_module()
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-current-file-race-") as temporary:
            root = Path(temporary)
            relative = "NembraApp/App/Capture.swift"
            path = root / relative
            escaped = path.with_name("Capture.accepted.swift")
            path.parent.mkdir(parents=True)
            path.write_bytes(b"accepted-final-go-source\n")
            path.chmod(0o644)

            original_open = module.os.open
            attack_fired = False

            def interpose_open(subject, flags, mode=0o777, *, dir_fd=None):
                nonlocal attack_fired
                if subject == "Capture.swift" and dir_fd is not None and not attack_fired:
                    attack_fired = True
                    os.rename(path, escaped)
                    replacement = original_open(
                        path,
                        os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_CLOEXEC", 0),
                        0o644,
                    )
                    try:
                        os.write(replacement, b"replacement-must-not-be-admitted\n")
                        os.fsync(replacement)
                    finally:
                        os.close(replacement)
                return original_open(subject, flags, mode, dir_fd=dir_fd)

            module.os.open = interpose_open
            try:
                with self.assertRaises(RuntimeError):
                    module._read_physical_payload(root, relative, b"100644")
            finally:
                module.os.open = original_open

            self.assertTrue(attack_fired, "fixture never reached final descriptor-open boundary")
            self.assertEqual(escaped.read_bytes(), b"accepted-final-go-source\n")
            self.assertEqual(path.read_bytes(), b"replacement-must-not-be-admitted\n")

    def test_symlink_final_component_swap_at_readlink_is_rejected(self) -> None:
        module = load_module()
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-current-symlink-race-") as temporary:
            root = Path(temporary)
            relative = "NembraApp/App/CurrentConfig"
            path = root / relative
            escaped = path.with_name("CurrentConfig.accepted")
            path.parent.mkdir(parents=True)
            os.symlink("../Resources/accepted.json", path)

            original_readlink = module.os.readlink
            attack_fired = False

            def interpose_readlink(subject, *args, **kwargs):
                nonlocal attack_fired
                if subject == "CurrentConfig" and kwargs.get("dir_fd") is not None and not attack_fired:
                    attack_fired = True
                    os.rename(path, escaped)
                    os.symlink("../Resources/replacement.json", path)
                return original_readlink(subject, *args, **kwargs)

            module.os.readlink = interpose_readlink
            try:
                with self.assertRaises(RuntimeError):
                    module._read_physical_payload(root, relative, b"120000")
            finally:
                module.os.readlink = original_readlink

            self.assertTrue(attack_fired, "fixture never reached descriptor-relative readlink boundary")
            self.assertEqual(os.readlink(escaped), "../Resources/accepted.json")
            self.assertEqual(os.readlink(path), "../Resources/replacement.json")

    def test_parent_directory_swap_after_descriptor_walk_is_rejected(self) -> None:
        module = load_module()
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-current-parent-race-") as temporary:
            root = Path(temporary)
            relative = "NembraApp/App/Capture.swift"
            accepted_root = root / "NembraApp"
            accepted_path = accepted_root / "App/Capture.swift"
            escaped_root = root / "NembraApp.accepted"
            attacker_root = root / "Attacker"
            attacker_path = attacker_root / "App/Capture.swift"
            accepted_path.parent.mkdir(parents=True)
            attacker_path.parent.mkdir(parents=True)
            accepted_path.write_bytes(b"accepted-final-go-source\n")
            attacker_path.write_bytes(b"parent-swap-attacker-source\n")
            accepted_path.chmod(0o644)
            attacker_path.chmod(0o644)

            original_stat = module.os.stat
            attack_fired = False

            def interpose_stat(subject, *args, **kwargs):
                nonlocal attack_fired
                if (
                    subject == "Capture.swift"
                    and kwargs.get("dir_fd") is not None
                    and kwargs.get("follow_symlinks") is False
                    and not attack_fired
                ):
                    attack_fired = True
                    os.rename(accepted_root, escaped_root)
                    os.symlink("Attacker", accepted_root)
                return original_stat(subject, *args, **kwargs)

            module.os.stat = interpose_stat
            try:
                with self.assertRaises(RuntimeError):
                    module._read_physical_payload(root, relative, b"100644")
            finally:
                module.os.stat = original_stat

            self.assertTrue(attack_fired, "fixture never reached post-ancestry final admission boundary")
            self.assertEqual((escaped_root / "App/Capture.swift").read_bytes(), b"accepted-final-go-source\n")
            self.assertEqual((root / relative).read_bytes(), b"parent-swap-attacker-source\n")


if __name__ == "__main__":
    unittest.main(verbosity=2)
