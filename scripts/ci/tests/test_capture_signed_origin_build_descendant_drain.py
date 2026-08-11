#!/usr/bin/env python3
"""Expected-red diagnostic for signed-origin build descendant authority.

The current Capture build guard waits only for the direct build process. This diagnostic
proves a descendant can survive that return boundary and perform a mutation that is
causally gated until *after* run_guarded_build has returned. A compiler-output custody
repair must therefore drain the relevant builder process family or otherwise revoke its
output authority before root lock / first protected snapshot.

Research only: this portable witness does not claim real Xcode leaks descendants and does
not create app, signing, or physical authority.
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
    module_name = "capture_tuya_private_input_build_guard_descendant_diagnostic"
    spec = importlib.util.spec_from_file_location(module_name, GUARD)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load Capture build guard")
    module = importlib.util.module_from_spec(spec)
    # The guard uses dataclasses with postponed annotations. Register before execution
    # so a harness-only import failure cannot masquerade as process-lifetime evidence.
    sys.modules[module_name] = module
    try:
        spec.loader.exec_module(module)
    except Exception:
        sys.modules.pop(module_name, None)
        raise
    return module


class QuietBackend:
    """Portable no-event backend; this diagnostic attacks process authority only."""

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
        return ("stable-input-generation",)


class CaptureSignedOriginBuildDescendantDrainTests(unittest.TestCase):
    def test_guard_return_does_not_leave_descendant_with_post_return_output_authority(self) -> None:
        guard = load_guard()
        with tempfile.TemporaryDirectory(prefix="nembra-signed-origin-descendant-") as temporary:
            root = Path(temporary)
            inputs = InputsFixture(root)
            pid_file = root / "descendant.pid"
            after_guard_gate = root / "after-guard-return.gate"
            would_be_output = root / "would-be-compiler-output.bin"

            # The direct build child spawns a descendant and exits. The descendant is
            # forbidden by construction from mutating `would_be_output` until the test
            # creates `after_guard_gate`, which happens only after run_guarded_build
            # has returned. A later mutation is therefore causal post-return evidence,
            # not merely evidence that the descendant happened to be alive.
            child_source = r'''
import pathlib
import subprocess
import sys

pid_path = pathlib.Path(sys.argv[1])
gate_path = pathlib.Path(sys.argv[2])
output_path = pathlib.Path(sys.argv[3])
grandchild = r"""
import os
import pathlib
import sys
import time

gate = pathlib.Path(sys.argv[1])
output = pathlib.Path(sys.argv[2])
deadline = time.monotonic() + 30.0
while not gate.exists() and time.monotonic() < deadline:
    time.sleep(0.01)
if gate.exists():
    output.write_bytes(b'POST-GUARD-DESCENDANT-MUTATION')
"""
process = subprocess.Popen(
    [sys.executable, "-c", grandchild, str(gate_path), str(output_path)],
    stdin=subprocess.DEVNULL,
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
)
pid_path.write_text(str(process.pid), encoding="utf-8")
'''

            status = guard.run_guarded_build(
                inputs,
                [
                    sys.executable,
                    "-c",
                    child_source,
                    str(pid_file),
                    str(after_guard_gate),
                    str(would_be_output),
                ],
                backend_factory=QuietBackend,
                poll_interval=0.01,
            )
            self.assertEqual(status, 0)
            self.assertTrue(pid_file.is_file(), "fixture child did not publish descendant PID")
            descendant_pid = int(pid_file.read_text(encoding="utf-8").strip())
            self.assertFalse(
                would_be_output.exists(),
                "fixture mutated output before the guard return gate; diagnostic is invalid",
            )

            # This signal is the causal return boundary. The descendant can mutate only
            # after this point.
            after_guard_gate.write_text("GUARD-RETURNED\n", encoding="utf-8")
            deadline = time.monotonic() + 2.0
            while not would_be_output.exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            post_return_mutation = would_be_output.exists()

            alive = False
            try:
                os.kill(descendant_pid, 0)
                alive = True
            except ProcessLookupError:
                pass
            finally:
                if alive:
                    try:
                        os.kill(descendant_pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass

            self.assertFalse(
                post_return_mutation,
                "Capture build guard returned while a build descendant retained post-return output mutation authority. "
                "A signed-origin repair must mechanically drain the relevant builder process family or otherwise "
                "revoke its output authority before root lock / first protected snapshot; waiting only for the direct "
                "build child is insufficient.",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
