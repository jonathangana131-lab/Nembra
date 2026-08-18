#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

MODULE_PATH = Path(__file__).resolve().parents[1] / "es80_authenticated_stationary_signed_artifact.py"
SPEC = importlib.util.spec_from_file_location("signed_artifact_device_custody", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load retained signed-artifact module")
signed = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(signed)

DEVICE = "00008101-0012345678901234"
REPLACEMENT_DEVICE = "00008101-0099999999999999"


class SignedArtifactDeviceCustodyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def private_file(self, parent: Path, value: str = DEVICE) -> Path:
        parent.mkdir(parents=True, exist_ok=True)
        path = parent / "device.udid"
        path.write_text(value, encoding="utf-8")
        path.chmod(0o600)
        return path

    def test_symlinked_ancestor_is_rejected(self) -> None:
        private = self.root / "private"
        self.private_file(private)
        alias = self.root / "alias"
        alias.symlink_to(private, target_is_directory=True)
        with self.assertRaises(signed.SignedArtifactError):
            signed._read_intended_device(alias / "device.udid", self.repo)

    def test_final_open_stays_bound_to_admitted_ancestor_descriptor(self) -> None:
        admitted = self.root / "admitted"
        admitted_device = self.private_file(admitted)
        replacement = self.root / "replacement"
        self.private_file(replacement, REPLACEMENT_DEVICE)
        moved = self.root / "admitted-original"
        original_open = os.open
        original_supports_dir_fd = set(os.supports_dir_fd)
        swapped = False

        def retarget_before_final_open(path: object, flags: int, *args: object, **kwargs: object) -> int:
            nonlocal swapped
            if path == "device.udid" and kwargs.get("dir_fd") is not None and not swapped:
                os.rename(admitted, moved)
                os.rename(replacement, admitted)
                swapped = True
            return original_open(path, flags, *args, **kwargs)

        with mock.patch.object(signed.os, "open", side_effect=retarget_before_final_open) as patched_open:
            with mock.patch.object(
                signed.os,
                "supports_dir_fd",
                original_supports_dir_fd | {patched_open},
            ):
                value = signed._read_intended_device(admitted_device, self.repo)

        self.assertTrue(swapped)
        self.assertEqual(value, DEVICE)
        self.assertEqual((admitted / "device.udid").read_text(encoding="utf-8"), REPLACEMENT_DEVICE)

    def test_repository_ancestry_and_hardlink_alias_fail_closed(self) -> None:
        inside = self.private_file(self.repo / "private")
        with self.assertRaises(signed.SignedArtifactError):
            signed._read_intended_device(inside, self.repo)

        outside = self.private_file(self.root / "outside")
        alias = self.root / "outside-hardlink"
        os.link(outside, alias)
        with self.assertRaises(signed.SignedArtifactError):
            signed._read_intended_device(outside, self.repo)

    def test_mode_and_read_stability_are_authority(self) -> None:
        path = self.private_file(self.root / "private")
        path.chmod(0o644)
        with self.assertRaises(signed.SignedArtifactError):
            signed._read_intended_device(path, self.repo)

        path.chmod(0o600)
        original_read = os.read
        mutated = False

        def mutate_after_first_read(fd: int, count: int) -> bytes:
            nonlocal mutated
            chunk = original_read(fd, count)
            if chunk and not mutated:
                path.write_text(REPLACEMENT_DEVICE, encoding="utf-8")
                path.chmod(0o600)
                mutated = True
            return chunk

        with mock.patch.object(signed.os, "read", side_effect=mutate_after_first_read):
            with self.assertRaises(signed.SignedArtifactError):
                signed._read_intended_device(path, self.repo)
        self.assertTrue(mutated)


if __name__ == "__main__":
    unittest.main(verbosity=2)
