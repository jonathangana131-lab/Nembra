#!/usr/bin/env python3
"""Expected-red diagnostic for signed-origin build descendant drain.

The current Capture build guard waits only for the direct build process. If that process
spawns a child which remains alive after the direct process exits, the guard can return
while the descendant still has the caller's output access. Any transient-GID origin
repair must therefore include a mechanically proven process-family drain before root
locks the build output and derives the first authority value.

This is research-only. It does not modify production code or create physical authority.
"""

from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import signal
import sys
import tempfile
import time
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
GUARD = REPOSITORY / "Scripts/capture_tuya_private_input_build_guard.py"


def load_guard():
    spec = importlib.util.spec_from_file_location("capture_tuya_private_input_build_guard", GUARD)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load Capture build guard")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class QuietBackend:
    """Portable no-event backend; this diagnostic attacks process lifetime only."""

    def register(self, descriptor: int) -> None:
        del descriptor

    def events(self, timeout: float):
        if timeout > 0:
            time.sleep(min(timeout, 0.01))
        return ()

    def close(self) -> None:
        return None


class InputsFixture:
    def __init__(self, root: Path) -> None:
        self.lockfile = root / "Podfile.lock"
        self.security_podspec = root / "Security.podspec"
        self.security_build = root / "SecurityBuild"
        self.identity_podspec = root / "Identity.podspec"
        self.identity_sources = root / "IdentitySources"
        self.lockfile.write_text("LOCK\n", encoding="utf-8")
        self.security_podspec.write_text("SECURITY\n", encoding="utf-8")
        self.identity_podspec.write_text("IDENTITY\n", encoding="utf-8")
        self.security_build.mkdir()
        self.identity_sources.mkdir()
        (self.security_build / "input.txt").write_text("SECURITY-BUILD\n", encoding="utf-8")
        (self.identity_sources / "input.txt").write_text("IDENTITY-SOURCE\n", encoding="utf-8")

    def generation_snapshot(self):
        # The diagnostic is intentionally scoped to process-family lifetime. The
        # no-event backend plus constant snapshot keeps unrelated input custody out
        # of the oracle while still exercising the real guard's process admission,
        # poll, completion and finally paths.
        return ("stable-input-generation",)


class CaptureSignedOriginBuildDescendantDrainTests(unittest.TestCase):
    def test_guard_cannot_return_while_build_descendant_remains_alive(self) -> None:
        guard = load_guard()
        with tempfile.TemporaryDirectory(prefix="nembra-signed-origin-descendant-") as temporary:
            root = Path(temporary)
            inputs = InputsFixture(root)
            pid_file = root / "descendant.pid"

            child_source = r'''
import pathlib
import subprocess
import sys

pid_path = pathlib.Path(sys.argv[1])
process = subprocess.Popen(
    [sys.executable, "-c", "import time; time.sleep(60)"],
    stdin=subprocess.DEVNULL,
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
)
pid_path.write_text(str(process.pid), encoding="utf-8")
'''

            status = guard.run_guarded_build(
                inputs,
                [sys.executable, "-c", child_source, str(pid_file)],
                backend_factory=QuietBackend,
                poll_interval=0.01,
            )
            self.assertEqual(status, 0)
            self.assertTrue(pid_file.is_file(), "fixture child did not publish descendant PID")
            descendant_pid = int(pid_file.read_text(encoding="utf-8").strip())

            alive = False
            try:
                os.kill(descendant_pid, 0)
                alive = True
            except ProcessLookupError:
                alive = False
            finally:
                if alive:
                    try:
                        os.kill(descendant_pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass

            self.assertFalse(
                alive,
                "Capture build guard returned while a direct build descendant remained alive. "
                "A transient-GID signed-output repair must prove the entire trusted build process "
                "family is drained (or otherwise stripped of output authority) before root lock / "
                "first protected snapshot; waiting for only the direct xcodebuild process is not enough.",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
