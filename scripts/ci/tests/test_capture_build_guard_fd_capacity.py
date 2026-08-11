#!/usr/bin/env python3
"""Expected-red physical-readiness regression for build-window vnode FD capacity.

The real field guard currently keeps one descriptor open for every admitted
private/generated file and directory while xcodebuild runs. A realistic Pods tree
can exceed the shell/process soft RLIMIT_NOFILE even when the hard limit has ample
capacity. The guard must safely adapt the soft limit (or use an equivalently
complete custody design) before opening the whole watch set; silently dropping
watchers is not acceptable.
"""

from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import resource
import sys
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
GUARD_PATH = REPOSITORY / "Scripts" / "capture_tuya_private_input_build_guard.py"

spec = importlib.util.spec_from_file_location("capture_build_guard_fd_capacity", GUARD_PATH)
assert spec is not None and spec.loader is not None
guard = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = guard
spec.loader.exec_module(guard)


class RecordingBackend:
    def __init__(self) -> None:
        self.registered: list[int] = []

    def register(self, descriptor: int) -> None:
        self.registered.append(descriptor)

    def events(self, timeout: float):
        del timeout
        return ()

    def close(self) -> None:
        pass


def _open_fd_count() -> int:
    proc = Path("/proc/self/fd")
    if proc.is_dir():
        return len(tuple(proc.iterdir()))
    # Portable conservative fallback: stdin/stdout/stderr plus test/runtime slack.
    return 16


class BuildGuardDescriptorCapacityTests(unittest.TestCase):
    def test_complete_watch_set_survives_low_soft_limit_when_hard_limit_allows_it(self) -> None:
        original_soft, original_hard = resource.getrlimit(resource.RLIMIT_NOFILE)
        current = _open_fd_count()

        # Leave enough room for the current runtime, but intentionally make the
        # unchanged graph larger than the starting soft limit. Production may
        # raise only the soft limit, never the hard limit, to close this case.
        low_soft = max(current + 12, 32)
        if original_hard != resource.RLIM_INFINITY and original_hard <= low_soft + 96:
            self.skipTest("runner hard RLIMIT_NOFILE is too small for the capacity regression")

        requested_paths = low_soft + 48
        with tempfile.TemporaryDirectory(prefix="nembra-build-guard-fd-") as temporary:
            root = Path(temporary)
            paths: list[Path] = []
            for index in range(requested_paths):
                path = root / f"input-{index:04d}.bin"
                path.write_bytes(b"accepted-build-input\n")
                paths.append(path)

            backend = RecordingBackend()
            watched = ()
            try:
                resource.setrlimit(resource.RLIMIT_NOFILE, (low_soft, original_hard))
                try:
                    watched = guard._open_watched_inputs(paths, backend)
                except guard.BuildGuardError as error:
                    self.fail(
                        "field-build custody exhausted the starting soft open-file limit "
                        "even though the process hard limit had capacity for the complete "
                        f"accepted watch set: {error}"
                    )

                self.assertEqual(len(watched), len(paths))
                self.assertEqual(len(backend.registered), len(paths))
                self.assertGreater(
                    resource.getrlimit(resource.RLIMIT_NOFILE)[0],
                    low_soft,
                    "the current one-descriptor-per-path custody design must provision "
                    "enough soft descriptor capacity before opening a graph larger than "
                    "the initial limit",
                )
            finally:
                for descriptor, _ in watched:
                    try:
                        os.close(descriptor)
                    except OSError:
                        pass
                resource.setrlimit(resource.RLIMIT_NOFILE, (original_soft, original_hard))


if __name__ == "__main__":
    unittest.main(verbosity=2)
