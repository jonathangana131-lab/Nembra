#!/usr/bin/env python3
"""Exploit-positive witness for shared-ancestor cache-dup descriptor cleanup."""
from __future__ import annotations

import errno
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock

REPOSITORY = Path(__file__).resolve().parents[3]
HELPER = REPOSITORY / "scripts/ci/capture_accepted_build_input_snapshot.py"


def load():
    spec = importlib.util.spec_from_file_location("nembra_shared_ancestor_fd_leak", HELPER)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load accepted build-input helper")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CaptureGeneratedSharedAncestorCacheDupFDLeakRedTeamTests(unittest.TestCase):
    def test_cache_dup_failure_leaves_newly_opened_child_descriptor_live(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-shared-ancestor-fd-leak-") as raw:
            root = Path(raw)
            (root / "LocalSecrets/TuyaSDK").mkdir(parents=True)
            root_fd = helper._open_repository_root(root)
            real_dup = os.dup
            real_open_directory = helper._open_directory_at
            opened_children: list[int] = []
            dup_calls = 0

            def capture_open(parent_fd: int, name: str, relative: Path) -> int:
                descriptor = real_open_directory(parent_fd, name, relative)
                opened_children.append(descriptor)
                return descriptor

            def fail_cache_dup(descriptor: int) -> int:
                nonlocal dup_calls
                dup_calls += 1
                if dup_calls == 2:
                    raise OSError(errno.EMFILE, "synthetic cache-dup exhaustion")
                return real_dup(descriptor)

            cache: dict[Path, int] = {}
            try:
                with (
                    mock.patch.object(helper, "_open_directory_at", side_effect=capture_open),
                    mock.patch.object(helper.os, "dup", side_effect=fail_cache_dup),
                ):
                    with self.assertRaisesRegex(OSError, "synthetic cache-dup exhaustion"):
                        helper._open_subject(
                            root_fd,
                            Path("LocalSecrets/TuyaSDK"),
                            cache,
                        )

                self.assertEqual(dup_calls, 2)
                self.assertEqual(cache, {})
                self.assertEqual(len(opened_children), 1)

                leaked = opened_children[0]
                # Exploit-positive current-product evidence: the child opened immediately
                # before the failed cache duplication is still live after _open_subject
                # unwinds. A repaired product should close it and make this fstat fail.
                os.fstat(leaked)
            finally:
                for descriptor in opened_children:
                    try:
                        os.close(descriptor)
                    except OSError:
                        pass
                os.close(root_fd)


if __name__ == "__main__":
    unittest.main(verbosity=2)
