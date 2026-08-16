#!/usr/bin/env python3
"""Exploit-positive oracle for the current generated-directory cache dup FD leak."""
from __future__ import annotations

import errno
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock

REPO = Path(__file__).resolve().parents[3]
HELPER = REPO / "scripts/ci/capture_accepted_build_input_snapshot.py"


def load():
    spec = importlib.util.spec_from_file_location("nembra_current_cache_dup_fd_leak", HELPER)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load accepted build-input helper")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CaptureGeneratedSharedAncestorCacheDupFDLeakCurrentTests(unittest.TestCase):
    def test_cache_dup_failure_does_not_transfer_or_close_new_child_fd(self) -> None:
        helper = load()
        # Keep the fixture under the checkout so macOS does not encounter the unrelated
        # /var -> /private/var compatibility symlink before the intended seam.
        with tempfile.TemporaryDirectory(prefix="nembra-cache-dup-fd-leak-", dir=REPO) as raw:
            root = Path(raw) / "repo"
            (root / "LocalSecrets/TuyaSDK").mkdir(parents=True)

            root_fd = helper._open_repository_root(root)
            captured_child: list[int] = []
            real_open_directory_at = helper._open_directory_at
            real_dup = os.dup

            def capture_open(parent_fd: int, name: str, relative: Path) -> int:
                descriptor = real_open_directory_at(parent_fd, name, relative)
                if relative == Path("LocalSecrets"):
                    captured_child.append(descriptor)
                return descriptor

            def fail_cache_dup(descriptor: int) -> int:
                if captured_child and descriptor == captured_child[-1]:
                    raise OSError(errno.EMFILE, "injected cache duplication failure")
                return real_dup(descriptor)

            try:
                with (
                    mock.patch.object(helper, "_open_directory_at", side_effect=capture_open),
                    mock.patch.object(helper.os, "dup", side_effect=fail_cache_dup),
                ):
                    with self.assertRaises(OSError) as raised:
                        helper._open_subject(
                            root_fd,
                            Path("LocalSecrets/TuyaSDK"),
                            directory_cache={},
                        )
                self.assertEqual(raised.exception.errno, errno.EMFILE)
                self.assertEqual(len(captured_child), 1)

                # Exploit-positive current behavior: the just-opened LocalSecrets child
                # remains live because cache ownership was never established and the
                # outer exception path closes only the prior `current` descriptor.
                leaked = captured_child[0]
                metadata = os.fstat(leaked)
                self.assertTrue(os.path.samestat(metadata, (root / "LocalSecrets").stat()))
            finally:
                for descriptor in captured_child:
                    try:
                        os.close(descriptor)
                    except OSError:
                        pass
                os.close(root_fd)

    def test_source_shape_duplicates_child_before_current_takes_ownership(self) -> None:
        helper = load()
        import inspect

        source = inspect.getsource(helper._open_subject)
        self.assertIn("child = _open_directory_at", source)
        self.assertIn("held = os.dup(child)", source)
        self.assertIn("current = child", source)
        self.assertLess(source.index("held = os.dup(child)"), source.index("current = child"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
